extends Node

## Headless test of MediaSource (modules/hwvideo): stream info, the first access units against a raw Annex-B extraction
## of the same video, decoded audio, a seek, the audio clock through a real AudioStreamPlayer, and a clean failure of the
## hardware path where there is no decoder. Needs no decoder and no GPU (host build, --headless).
## User arguments (after `--`):
##   --file=PATH        container to open (default: Documentary.3D.Full-SBS.mkv in the local test library, $VRVP_LIBRARY
##                      or ~/media-tests/library: a link to a full-SBS 3D H.264 MKV of your own).
##   --raw=PATH         raw Annex-B extraction of the same video stream (ffmpeg -i in.mkv -c:v copy -bsf:v
##                      h264_mp4toannexb out.h264) to compare the first access units with. Empty: no comparison.
##                      Default: spikes/01-decode/streams/documentary_sbs.h264 when --file is the default.
##   --aus=N            access units to pull (and compare). Default 200.
##   --audio-seconds=S  audio to decode and check. Default 10.
##   --seek=S           seek target. Default 600, at most 80 % of the duration.
##   --track=N          audio track. Default: the file's default track.
##   --audio-option=K=V FFmpeg audio decoder option (MediaSource.audio_decoder_options), e.g. core_only=1 for DTS core
##                      only. Repeatable.
##   --realtime=S       at the end, play S seconds from 120 s as a player would: audio through the AudioStreamPlayer, video
##                      taken by the audio clock. Reports read rate, network stalls, underruns, CPU of the demux and
##                      readahead threads. Default 20 for smb:// files, else 0 (off).
##   --throughput=S     then seek to 0 and pull video as fast as possible for S seconds: read rate, CPU per MiB.
##                      Default 5 for smb:// files, else 0 (off).
##   --browse=HOST      instead: test MediaBrowser against smb://HOST (shares, folders, errors) and a local folder, and
##                      MediaSource's SMB errors. SMB_SHARE (default Movies) and SMB_FILE name a share and a file in it.
## smb:// files and --browse take the credentials from the environment: SMB_USER, SMB_PASSWORD, SMB_DOMAIN (never
## printed). run-tests.sh reads them from ~/.config/frame-player/smb-test.env.

var DEFAULT_FILE := (OS.get_environment("VRVP_LIBRARY") if OS.has_environment("VRVP_LIBRARY")
		else OS.get_environment("HOME").path_join("media-tests/library")).path_join("Documentary.3D.Full-SBS.mkv")
var DEFAULT_RAW := ProjectSettings.globalize_path("res://").path_join("../../01-decode/streams/documentary_sbs.h264").simplify_path()
const TIMEOUT_MS := 30000
const CHUNK := 1024

@onready var player: AudioStreamPlayer = $Audio

var source: MediaSource
var audio_options := {}
var failures: PackedStringArray = []


func _ready() -> void:
	var file_path := DEFAULT_FILE
	var raw_path := ""
	var raw_given := false
	var au_count := 200
	var audio_seconds := 10.0
	var seek_to := 600.0
	var track := -2
	var throughput := -1.0
	var realtime := -1.0
	var browse_host := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--file="):
			file_path = arg.trim_prefix("--file=")
		elif arg.begins_with("--raw="):
			raw_path = arg.trim_prefix("--raw=")
			raw_given = true
		elif arg.begins_with("--aus="):
			au_count = arg.trim_prefix("--aus=").to_int()
		elif arg.begins_with("--audio-seconds="):
			audio_seconds = arg.trim_prefix("--audio-seconds=").to_float()
		elif arg.begins_with("--seek="):
			seek_to = arg.trim_prefix("--seek=").to_float()
		elif arg.begins_with("--audio-option="):
			var kv := arg.trim_prefix("--audio-option=").split("=", true, 1)
			audio_options[kv[0]] = kv[1] if kv.size() > 1 else ""
		elif arg.begins_with("--track="):
			track = arg.trim_prefix("--track=").to_int()
		elif arg.begins_with("--realtime="):
			realtime = arg.trim_prefix("--realtime=").to_float()
		elif arg.begins_with("--throughput="):
			throughput = arg.trim_prefix("--throughput=").to_float()
		elif arg.begins_with("--browse="):
			browse_host = arg.trim_prefix("--browse=")
	if not raw_given and file_path == DEFAULT_FILE:
		raw_path = DEFAULT_RAW
	if browse_host != "":
		_set_credentials(browse_host)
		_browse(browse_host)
	else:
		if file_path.begins_with("smb://"):
			_set_credentials(file_path.trim_prefix("smb://").get_slice("/", 0))
		await _run(file_path, raw_path, au_count, audio_seconds, seek_to, track)
		if realtime < 0.0:
			realtime = 20.0 if file_path.begins_with("smb://") else 0.0
		if source and realtime > 0.0 and source.get_state() != MediaSource.STATE_CLOSED:
			await _realtime(realtime)
		if throughput < 0.0:
			throughput = 5.0 if file_path.begins_with("smb://") else 0.0
		if source and throughput > 0.0 and source.get_state() != MediaSource.STATE_CLOSED:
			_throughput(throughput)
	if source:
		var final_stats := source.get_stats()
		print("Final source stats: %s" % final_stats)
		if final_stats.get("network", false):
			print("Network: %.1f MB read in %d requests, %.0f Mbit/s while reading (%.0f on average since open), buffer %.1f of %.0f MB, %d resets, %d waits (%d stalls, %.2f s), %d reconnects, %d errors; readahead thread CPU %.2f s" % [
					final_stats["net_bytes_read"] / 1e6, final_stats["net_requests"], final_stats["net_read_mbps"], final_stats["net_average_mbps"], final_stats["net_buffered_bytes"] / 1e6,
					final_stats["net_buffer_bytes"] / 1e6, final_stats["net_resets"], final_stats["net_waits"], final_stats["net_stalls"], final_stats["net_wait_seconds"],
					final_stats["net_reconnects"], final_stats["net_errors"], final_stats["net_thread_cpu_seconds"]])
		var t_close := Time.get_ticks_usec()
		source.close()
		print("close() took %.1f ms" % ((Time.get_ticks_usec() - t_close) / 1000.0))
	print("")
	if failures.is_empty():
		print("RESULT: PASS")
	else:
		print("RESULT: FAIL (%d): %s" % [failures.size(), ", ".join(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)


# Credentials for an SMB host from the environment (never printed).
func _set_credentials(host: String) -> void:
	var user := OS.get_environment("SMB_USER")
	if user == "":
		print("No SMB_USER in the environment: connecting to %s as guest." % host)
		return
	MediaSource.set_smb_credentials(host, user, OS.get_environment("SMB_PASSWORD"), OS.get_environment("SMB_DOMAIN"))
	print("SMB credentials for %s: user %s, domain \"%s\", password from the environment." % [host, user, OS.get_environment("SMB_DOMAIN")])


func _check(condition: bool, what: String) -> void:
	print(("  PASS  " if condition else "  FAIL  ") + what)
	if not condition:
		failures.push_back(what)


# Pulls up to p_count access units (of serial p_serial if >= 0) from the source's queue.
func _pull(p_count: int, p_serial: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while out.size() < p_count and Time.get_ticks_msec() < deadline:
		var packet := source.read_video_packet()
		if packet.is_empty():
			if source.is_eof() and source.get_stats()["video_queue"] == 0:
				break
			OS.delay_msec(1)
			continue
		if p_serial >= 0 and packet["serial"] != p_serial:
			continue
		out.push_back(packet)
	return out


# Nobody decodes the video here: empty its queue so the demuxer keeps reading for the audio.
func _drain_video() -> void:
	while not source.read_video_packet().is_empty():
		pass


func _wait_audio(p_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while source.get_stats()["audio_buffered"] < p_seconds:
		var stats := source.get_stats()
		if stats["audio_finished"] or Time.get_ticks_msec() > deadline:
			return false
		if stats["eof"] and stats["audio_buffered"] > 0.0:
			return true # The last, partial chunk.
		_drain_video()
		OS.delay_msec(1)
	return true


static func _starts_with_start_code(data: PackedByteArray) -> bool:
	return data.size() > 4 and data[0] == 0 and data[1] == 0 and (data[2] == 1 or (data[2] == 0 and data[3] == 1))


# Mixes p_seconds of audio from p_playback, waiting for the demux thread as needed. Returns [rms, peak, frames, silent_chunks].
func _mix(p_playback: AudioStreamPlayback, p_seconds: float) -> Array:
	var rate := source.get_output_rate()
	var total := int(p_seconds * rate)
	var mixed := 0
	var sum_sq := 0.0
	var peak := 0.0
	var silent_chunks := 0
	while mixed < total:
		if not _wait_audio(float(CHUNK) / rate):
			break
		var frames: PackedVector2Array = p_playback.mix_audio(1.0, CHUNK)
		var chunk_sq := 0.0
		for f in frames:
			chunk_sq += f.x * f.x + f.y * f.y
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		if chunk_sq == 0.0:
			silent_chunks += 1
		sum_sq += chunk_sq
		mixed += frames.size()
	var rms := sqrt(sum_sq / maxf(2.0 * mixed, 1.0))
	return [rms, peak, mixed, silent_chunks]


func _run(file_path: String, raw_path: String, au_count: int, audio_seconds: float, seek_to: float, track: int) -> void:
	print("== MediaSource test: %s" % file_path)
	if not file_path.begins_with("smb://") and not FileAccess.file_exists(file_path):
		_check(false, "file exists: %s" % file_path)
		return

	# 1. Open and stream info.
	source = MediaSource.new()
	if not audio_options.is_empty():
		source.audio_decoder_options = audio_options
	var t0 := Time.get_ticks_usec()
	var err := source.open(file_path)
	var open_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(err == OK, "open() (%s, %.0f ms): %s" % [error_string(err), open_ms, source.get_last_error()])
	if err != OK:
		return
	var info := source.get_info()
	print("Stream info:")
	print("  format %s, duration %.3f s, start %.3f s, %d kbit/s" % [info["format"], info["duration"], info["start_time"], info["bit_rate"] / 1000])
	print("  video %s" % JSON.stringify(info["video"]))
	for t in info["audio_tracks"]:
		print("  audio %s" % JSON.stringify(t))
	for t in info["subtitle_tracks"]:
		print("  subtitle %s" % JSON.stringify(t))
	print("  selected audio track %d, output %d Hz" % [info["audio_track"], info["output_rate"]])
	var video: Dictionary = info["video"]
	_check(not video.is_empty(), "has a video stream")
	if track >= -1:
		_check(source.select_audio_track(track) == OK, "select_audio_track(%d)" % track)

	# 2. The first access units.
	t0 = Time.get_ticks_usec()
	var aus := _pull(au_count)
	var pull_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(aus.size() == au_count, "pulled %d access units (%d asked) in %.0f ms" % [aus.size(), au_count, pull_ms])
	if aus.is_empty():
		return
	print("First access units (dts, pts, keyframe, size, sps):")
	for k in range(mini(aus.size(), 12)):
		var a := aus[k]
		print("  %3d  dts %8.4f  pts %8.4f  %s  %7d  %s" % [k, a["dts"], a["pts"], "K" if a["keyframe"] else "-", a["data"].size(),
				"%dx%d" % [a["sps_width"], a["sps_height"]] if a["sps_width"] else ""])
	_check(aus[0]["keyframe"], "the first access unit is a keyframe")
	var annexb: bool = video.get("is_h264", false) or video.get("is_hevc", false)
	if annexb:
		_check(aus[0]["sps_width"] > 0, "the first access unit carries the parameter sets (SPS %dx%d)" % [aus[0]["sps_width"], aus[0]["sps_height"]])
		var all_annexb := true
		for a in aus:
			all_annexb = all_annexb and _starts_with_start_code(a["data"])
		_check(all_annexb, "every access unit is Annex-B (starts with a start code)")
	var dts_ok := true
	var pts_list: Array[float] = []
	for k in range(aus.size()):
		pts_list.push_back(aus[k]["pts"])
		if k > 0 and aus[k]["dts"] <= aus[k - 1]["dts"]:
			dts_ok = false
	# Informational: Matroska stores no DTS (FFmpeg reports the PTS), MP4 does. The decoder doesn't use it.
	print("  info  DTS %s" % ("strictly increasing" if dts_ok else "not monotonic (no DTS in the container; DTS = PTS)"))
	pts_list.sort()
	var fps: float = video.get("fps", 0.0)
	if fps > 0.0:
		var irregular := 0
		var worst := 0.0
		var worst_at := 0
		# The last few in decode order are P-frames whose B-frames come later: leave the tail out.
		for k in range(1, maxi(pts_list.size() - 16, 2)):
			var error := absf(pts_list[k] - pts_list[k - 1] - 1.0 / fps)
			if error > worst:
				worst = error
				worst_at = k
			if error > 0.0015:
				irregular += 1
		# One irregular step is tolerated: some files have a gap (Action.720p.mp4: no frame at 0.042 s).
		_check(irregular <= 1, "PTS in display order are evenly spaced at 1/%.3f s: %d irregular step(s) (first %.4f, last %.4f; worst step %.4f s after %.4f)" % [fps, irregular,
				pts_list[0], pts_list[-1], pts_list[worst_at] - pts_list[worst_at - 1], pts_list[worst_at - 1]])

	if raw_path != "":
		_compare_with_raw(aus, raw_path)

	# 3. Audio: decoded, resampled, not silent; the clock advances by exactly what was mixed.
	if source.get_audio_track() >= 0:
		var playback := source.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		_mix(playback, float(CHUNK) / source.get_output_rate())
		var pos0 := playback.get_playback_position()
		t0 = Time.get_ticks_usec()
		var result := _mix(playback, audio_seconds)
		var mix_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var pos1 := playback.get_playback_position()
		var frames: int = result[2]
		print("Audio: %d frames in %.0f ms, rms %.4f, peak %.3f, %d silent chunks, position %.4f -> %.4f" % [frames, mix_ms, result[0], result[1], result[3], pos0, pos1])
		_check(frames >= int(audio_seconds * source.get_output_rate()), "decoded %.1f s of audio" % audio_seconds)
		_check(result[0] > 0.001, "the audio is not silent (rms %.4f, %.1f dBFS)" % [result[0], 20.0 * log(maxf(result[0], 1e-9)) / log(10.0)])
		_check(absf((pos1 - pos0) - float(frames) / source.get_output_rate()) < 0.002, "the playback position advanced by the audio mixed (%.4f s for %.4f s)" % [pos1 - pos0, float(frames) / source.get_output_rate()])
		_check(source.get_stats()["audio_underruns"] == 0, "no audio underruns (%d)" % source.get_stats()["audio_underruns"])
	else:
		print("No audio track selected; audio checks skipped.")

	# 4. Seek: the next access unit is the last keyframe at or before the target, with the parameter sets; audio starts
	# exactly at the target.
	var duration: float = info["duration"]
	var target := minf(seek_to, duration * 0.8) if duration > 0.0 else seek_to
	t0 = Time.get_ticks_usec()
	var serial := source.seek(target)
	var after := _pull(1, serial)
	var seek_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(not after.is_empty(), "access units after seek(%.1f) (serial %d, first in %.0f ms)" % [target, serial, seek_ms])
	if not after.is_empty():
		var first := after[0]
		# Read on past the target: no other keyframe may lie between the one the seek landed on and the target.
		var keyframes_between := 0
		var next_keyframe := -1.0
		var count := 1
		while count < 2000:
			var more := _pull(1, serial)
			if more.is_empty():
				break
			count += 1
			var a := more[0]
			if a["keyframe"]:
				if a["pts"] <= target + 0.001:
					keyframes_between += 1
				elif next_keyframe < 0.0:
					next_keyframe = a["pts"]
			if a["pts"] > target + 1.0 and next_keyframe >= 0.0:
				break
		print("After the seek: dts %.4f pts %.4f %s (%s) size %d sps %dx%d; %d access units read on, next keyframe at %.3f; seek retries %d" % [first["dts"], first["pts"],
				"keyframe" if first["keyframe"] else "not a keyframe", first.get("random_access", ""), first["data"].size(), first["sps_width"], first["sps_height"], count,
				next_keyframe, source.get_stats()["seek_retries"]])
		_check(first["keyframe"], "the first access unit after the seek is a keyframe")
		_check(first["pts"] <= target + 0.001 and first["pts"] > target - 10.0, "its PTS %.4f is at or before the target %.1f (within 10 s)" % [first["pts"], target])
		if info["format"] == "mpegts":
			# No keyframe index: the seek goes back by 2, 4, 8... s until the first keyframe is before the target, so a later
			# keyframe can lie in between (decoded from a little earlier than needed).
			print("  info  mpegts: %d keyframe(s) between it and the target (the next is at %.3f)" % [keyframes_between, next_keyframe])
		else:
			_check(keyframes_between == 0, "it is the last keyframe at or before the target (%d keyframes in between; the next is at %.3f)" % [keyframes_between, next_keyframe])
		if annexb:
			_check(first["sps_width"] > 0 and _starts_with_start_code(first["data"]), "it carries the parameter sets in band")
	if source.get_audio_track() >= 0:
		var playback := source.get_audio_stream().instantiate_playback()
		playback.start(0.0)
		var pos_seek := playback.get_playback_position()
		var result := _mix(playback, 1.0)
		var pos_after := playback.get_playback_position()
		print("Audio after the seek: position %.4f -> %.4f, rms %.4f, stats %s" % [pos_seek, pos_after, result[0], source.get_stats()])
		_check(absf(pos_seek - target) < 0.001, "the audio clock is at the target right after the seek (%.4f)" % pos_seek)
		_check(absf(pos_after - (target + float(result[2]) / source.get_output_rate())) < 0.002, "and continues from it without a gap (%.4f)" % pos_after)
		_check(result[0] > 0.001, "audio after the seek is not silent (rms %.4f)" % result[0])

	# 5. The end: everything up to the end of the file comes out, the audio finishes, and a seek after the end reads again.
	if duration > 30.0:
		var end_serial := source.seek(duration - 3.0)
		var tail := _pull(100000, end_serial)
		var tail_end: float = tail[-1]["pts"] if not tail.is_empty() else -1.0
		_check(source.is_eof() and source.get_state() == MediaSource.STATE_ENDED, "seek(duration - 3 s): read to the end (%d access units, last PTS %.3f of %.3f s, state %d)" % [tail.size(), tail_end, duration, source.get_state()])
		if source.get_audio_track() >= 0:
			var playback := source.get_audio_stream().instantiate_playback()
			playback.start(0.0)
			var result := _mix(playback, 10.0)
			print("Audio at the end: %.3f s mixed, position %.3f, playing %s, stats audio_finished %s" % [float(result[2]) / source.get_output_rate(), playback.get_playback_position(),
					playback.is_playing(), source.get_stats()["audio_finished"]])
			_check(source.get_stats()["audio_finished"] and not playback.is_playing(), "the audio finishes at the end (position %.3f)" % playback.get_playback_position())
		var again := source.seek(0.0)
		var first_again := _pull(1, again)
		_check(not first_again.is_empty() and first_again[0]["keyframe"] and first_again[0]["pts"] < 1.0 and source.get_state() == MediaSource.STATE_READING,
				"seek(0) after the end reads again (first PTS %.3f)" % (first_again[0]["pts"] if not first_again.is_empty() else -1.0))

	# 6. Through a real AudioStreamPlayer (headless: the dummy audio driver mixes in real time).
	if source.get_audio_track() >= 0:
		# The app's pattern: seek, then (re)start the player at the same position. That must not seek again.
		var seek_serial := source.seek(30.0)
		player.stream = source.get_audio_stream()
		player.play(30.0)
		_check(source.get_serial() == seek_serial, "AudioStreamPlayer.play(t) right after seek(t) doesn't seek again (serial %d, %d)" % [seek_serial, source.get_serial()])
		# The clock holds while the queues refill after the seek (from the keyframe before the target: longer over a
		# network); measure from when it runs, plus 300 ms.
		var warm := Time.get_ticks_msec()
		while player.get_playback_position() < 30.05 and Time.get_ticks_msec() - warm < 5000:
			_drain_video()
			await get_tree().process_frame
		print("AudioStreamPlayer: the clock runs %d ms after play(30.0)" % (Time.get_ticks_msec() - warm))
		var running := Time.get_ticks_msec()
		while Time.get_ticks_msec() - running < 300:
			_drain_video()
			await get_tree().process_frame
		var start_ms := Time.get_ticks_msec()
		var p0 := player.get_playback_position()
		var cpu0: float = source.get_stats()["thread_cpu_seconds"]
		var net_cpu0: float = source.get_stats().get("net_thread_cpu_seconds", 0.0)
		var net_bytes0: int = source.get_stats().get("net_bytes_read", 0)
		while Time.get_ticks_msec() - start_ms < 2000:
			_drain_video()
			await get_tree().process_frame
		var p1 := player.get_playback_position()
		var wall := (Time.get_ticks_msec() - start_ms) / 1000.0
		var cpu: float = source.get_stats()["thread_cpu_seconds"] - cpu0
		print("AudioStreamPlayer: position %.3f -> %.3f over %.3f s of wall time, mix rate %d, underruns %d; demux thread CPU %.1f ms (%.1f %% of a core; the video is read and dropped by this script)" % [
				p0, p1, wall, AudioServer.get_mix_rate(), source.get_stats()["audio_underruns"], cpu * 1000.0, cpu / wall * 100.0])
		if source.get_stats().get("network", false):
			var net_cpu: float = source.get_stats()["net_thread_cpu_seconds"] - net_cpu0
			var net_bytes: int = source.get_stats()["net_bytes_read"] - net_bytes0
			print("  network (as fast as the script drops the video): %.1f MB read (%.1f Mbit/s), readahead thread CPU %.1f ms (%.2f %% of a core), %d stalls so far" % [net_bytes / 1e6,
					net_bytes * 8.0 / wall / 1e6, net_cpu * 1000.0, net_cpu / wall * 100.0, source.get_stats()["net_stalls"]])
		if p1 == p0:
			print("  SKIP  the audio driver doesn't mix here (no output in this environment)")
		else:
			_check(absf((p1 - p0) - wall) < 0.25, "the AudioStreamPlayer clock follows wall time (%.3f s vs %.3f s)" % [p1 - p0, wall])
		player.stop()
		player.stream = null
		# Let the AudioServer drop the stopped playback (it holds the source).
		await get_tree().create_timer(0.2).timeout

	# 7. Without a decoder device (a desktop), what the software decoder can take (any codec FFmpeg decodes, up to about
	# 1080p; AV1 further) opens on the software path, as does what the hardware can't show (10-bit, VP9, every other
	# codec). The rest (too large) fails cleanly and leaves the source usable.
	var texture := HWVideoTexture.new()
	err = texture.open_source(source)
	print("HWVideoTexture.open_source without a decoder: %s: %s (path \"%s\")" % [error_string(err), texture.get_last_error(), texture.get_decode_path()])
	var v: Dictionary = info["video"]
	var no_device := not FileAccess.file_exists(texture.get_decoder().device_path)
	var software_fits: bool = str(v.get("codec", "")) in ["h264", "hevc", "vp9"] and int(v.get("width", 0)) * int(v.get("height", 0)) <= texture.software_max_pixels \
			and int(v.get("bit_depth", 8)) <= 10
	if bool(v.get("software_decodable", false)) or (no_device and software_fits):
		_check(err == OK and texture.get_decode_path() == "software", "open_source() takes the software path for what the hardware can't show or decode here")
	else:
		_check(err != OK and texture.get_last_error() != "", "open_source() fails with a message when there is no V4L2 decoder")
	texture.close()
	_check(source.get_state() != MediaSource.STATE_ERROR, "the source is still fine after that")

	# 8. Subtitles: each track (at most 4) selected in turn, events read from a seek on. Audio off, so nothing has to be
	# mixed to keep the demuxer reading.
	var subtitle_tracks: Array = info["subtitle_tracks"]
	if subtitle_tracks.is_empty():
		return
	source.select_audio_track(-1)
	var sub_from := 0.0 if duration < 300.0 else target
	for t in subtitle_tracks.slice(0, 4):
		_check_subtitles(t, sub_from, file_path)


# Plays p_seconds from 120 s like the player: the AudioStreamPlayer mixes in real time (dummy driver), and video access
# units are taken when the audio clock reaches them (a decoder takes them a little ahead; here 0.2 s).
func _realtime(p_seconds: float) -> void:
	var track: int = source.get_info()["audio_track"]
	if source.get_audio_track() < 0 and source.get_audio_tracks().size() > 0:
		source.select_audio_track(maxi(track, 0))
	source.select_subtitle_track(-1)
	var start := minf(120.0, source.get_duration() * 0.5)
	var serial := source.seek(start)
	player.stream = source.get_audio_stream()
	player.play(start)
	var held := {}
	var taken := 0
	var s0 := {}
	var t0 := 0
	var warm_until := Time.get_ticks_msec() + 1000
	var min_buffered := 1 << 40
	var underruns0 := 0
	while true:
		var now := Time.get_ticks_msec()
		if s0.is_empty() and now >= warm_until:
			s0 = source.get_stats()
			underruns0 = s0["audio_underruns"]
			t0 = now
		if not s0.is_empty() and now - t0 >= p_seconds * 1000.0:
			break
		var clock := player.get_playback_position()
		while true:
			if held.is_empty():
				held = source.read_video_packet()
				if held.is_empty():
					break
				if held["serial"] != serial:
					held = {}
					continue
			if held["pts"] > clock + 0.2:
				break
			taken += 1
			held = {}
		if not s0.is_empty():
			min_buffered = mini(min_buffered, source.get_stats().get("net_buffered_bytes", 0))
		await get_tree().process_frame
	var s1 := source.get_stats()
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	var demux_cpu: float = s1["thread_cpu_seconds"] - s0["thread_cpu_seconds"]
	var played: float = player.get_playback_position() - start
	print("Real time: %.1f s from %.0f s, clock at %.2f, %d access units taken; audio underruns %d; demux thread CPU %.0f ms (%.2f %% of a core)" % [wall, start,
			player.get_playback_position(), taken, s1["audio_underruns"] - underruns0, demux_cpu * 1000.0, demux_cpu / wall * 100.0])
	if s1.get("network", false):
		var net_mib: float = (s1["net_bytes_read"] - s0["net_bytes_read"]) / 1048576.0
		var net_cpu: float = s1["net_thread_cpu_seconds"] - s0["net_thread_cpu_seconds"]
		print("  network: %.1f MiB (%.1f Mbit/s), readahead thread CPU %.0f ms (%.2f %% of a core, %.2f ms per MiB), stalls %d, waits %d, lowest buffer ahead %.1f MiB, %d requests" % [
				net_mib, net_mib * 8.388608 / wall, net_cpu * 1000.0, net_cpu / wall * 100.0, net_cpu * 1000.0 / maxf(net_mib, 0.001), s1["net_stalls"] - s0["net_stalls"],
				s1["net_waits"] - s0["net_waits"], min_buffered / 1048576.0, s1["net_requests"] - s0["net_requests"]])
		_check(s1["net_stalls"] - s0["net_stalls"] == 0, "no network stalls while playing in real time")
	_check(s1["audio_underruns"] - underruns0 == 0, "no audio underruns while playing in real time")
	_check(absf(played - wall - 1.0) < 0.5, "the clock advanced with wall time (%.2f s played, %.2f s measured after 1 s of warm-up)" % [played, wall])
	player.stop()
	player.stream = null
	await get_tree().create_timer(0.2).timeout


# Reads the video from the start as fast as it comes (no audio, no subtitles): the read rate of the demuxer and, for
# smb:// files, of the network path, with the CPU time per MiB of the demux and readahead threads.
func _throughput(p_seconds: float) -> void:
	source.select_audio_track(-1)
	source.select_subtitle_track(-1)
	var serial := source.seek(0.0)
	var s0 := source.get_stats()
	var t0 := Time.get_ticks_usec()
	var bytes := 0
	var aus := 0
	var last_pts := 0.0
	while Time.get_ticks_usec() - t0 < p_seconds * 1e6:
		var packet := source.read_video_packet()
		if packet.is_empty():
			if source.is_eof() and source.get_stats()["video_queue"] == 0:
				break
			OS.delay_usec(200)
			continue
		if packet["serial"] == serial:
			bytes += packet["data"].size()
			aus += 1
			last_pts = maxf(last_pts, packet["pts"])
	var wall := (Time.get_ticks_usec() - t0) / 1e6
	var s1 := source.get_stats()
	var file_mib: float = (s1["bytes_read"] - s0["bytes_read"]) / 1048576.0
	var demux_cpu: float = s1["thread_cpu_seconds"] - s0["thread_cpu_seconds"]
	print("Throughput: %d access units (%.1f s of video) in %.2f s: %.0f Mbit/s of video, %.1f x real time; demux thread CPU %.2f s (%.2f ms per MiB of file)" % [aus, last_pts, wall,
			bytes * 8.0 / wall / 1e6, last_pts / wall, demux_cpu, demux_cpu * 1000.0 / maxf(file_mib, 0.001)])
	if s1.get("network", false):
		var net_mib: float = (s1["net_bytes_read"] - s0["net_bytes_read"]) / 1048576.0
		var net_cpu: float = s1["net_thread_cpu_seconds"] - s0["net_thread_cpu_seconds"]
		var busy: float = s1["net_busy_seconds"] - s0["net_busy_seconds"]
		print("  network: %.1f MiB in %.2f s (%.0f Mbit/s overall, %.0f while requests were in flight), readahead thread CPU %.2f s (%.2f ms per MiB), waits %d, stalls %d" % [net_mib, wall,
				net_mib * 8.388608 / wall, net_mib * 8.388608 / maxf(busy, 0.001), net_cpu, net_cpu * 1000.0 / maxf(net_mib, 0.001), s1["net_waits"] - s0["net_waits"],
				s1["net_stalls"] - s0["net_stalls"]])
		if OS.get_environment("HWVIDEO_SMB_DROP_AFTER_MB") != "":
			# The test hook drops the connection once: one error, one reconnect, and the demuxer reads on unharmed.
			_check(s1["net_errors"] == 1 and s1["net_reconnects"] == 1 and s1["read_errors"] == 0 and source.get_state() == MediaSource.STATE_READING,
					"after the dropped connection: reconnected and read on (%d errors, %d reconnects, %d demuxer read errors)" % [s1["net_errors"], s1["net_reconnects"], s1["read_errors"]])
		else:
			_check(net_mib > 0.0 and s1["net_errors"] == 0, "network reading without errors (%d errors, %d reconnects)" % [s1["net_errors"], s1["net_reconnects"]])


# MediaBrowser and the SMB error paths, against smb://p_host.
func _browse(p_host: String) -> void:
	var share := OS.get_environment("SMB_SHARE") if OS.get_environment("SMB_SHARE") != "" else "Movies"
	var file := OS.get_environment("SMB_FILE") if OS.get_environment("SMB_FILE") != "" else "Documentary.3D.Full-SBS.mkv"
	print("== MediaBrowser test: smb://%s, share %s, file %s" % [p_host, share, file])
	var browser := MediaBrowser.new()
	# The app's way: credentials through call() on an instance (network_hosts.gd apply_credentials()).
	_check(browser.has_method("set_smb_credentials"), "MediaBrowser has set_smb_credentials() (static, callable on an instance)")
	browser.call("set_smb_credentials", p_host, OS.get_environment("SMB_USER"), OS.get_environment("SMB_PASSWORD"), OS.get_environment("SMB_DOMAIN"))

	var t0 := Time.get_ticks_usec()
	var shares: Array = browser.list_shares(p_host)
	print("list_shares(%s) in %.0f ms: %s %s" % [p_host, (Time.get_ticks_usec() - t0) / 1000.0, shares, browser.get_last_error()])
	_check(shares.has(share), "list_shares() lists %s (hidden and administrative shares left out: %s)" % [share, not shares.any(func(n: String) -> bool: return n.ends_with("$"))])

	t0 = Time.get_ticks_usec()
	var root: Array = browser.list_dir("smb://" + p_host)
	print("list_dir(smb://%s) in %.0f ms: %s" % [p_host, (Time.get_ticks_usec() - t0) / 1000.0, root])
	_check(root.any(func(e: Dictionary) -> bool: return e["name"] == share and e["is_dir"]), "list_dir(smb://host) gives the shares as folders")

	for attempt in 2:
		t0 = Time.get_ticks_usec()
		var entries: Array = browser.list_dir("smb://%s/%s" % [p_host, share])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var dirs := entries.filter(func(e: Dictionary) -> bool: return e["is_dir"]).size()
		print("list_dir(smb://%s/%s) in %.0f ms (%s connection): %d entries, %d folders; first: %s" % [p_host, share, ms, "new" if attempt == 0 else "kept", entries.size(), dirs,
				entries.slice(0, 3)])
		var hit: Array = entries.filter(func(e: Dictionary) -> bool: return e["name"] == file)
		_check(hit.size() == 1 and not hit[0]["is_dir"] and hit[0]["size"] > 1000000 and hit[0]["mtime"] > 1000000000,
				"the share lists %s with its size and time (%s)" % [file, hit[0] if not hit.is_empty() else "missing"])
		var folders_first := true
		for k in range(1, entries.size()):
			folders_first = folders_first and not (entries[k]["is_dir"] and not entries[k - 1]["is_dir"])
		_check(folders_first, "folders come first")

	var local: Array = browser.list_dir(ProjectSettings.globalize_path("res://").path_join("../..").simplify_path())
	_check(local.any(func(e: Dictionary) -> bool: return e["name"] == "03-player" and e["is_dir"]), "a local folder lists too (%d entries)" % local.size())

	# Errors, as readable strings.
	var cases := [
		["smb://%s/NoSuchShare" % p_host, "no share"],
		["smb://%s/%s/no such folder" % [p_host, share], "Not found"],
		["/no/such/local/folder", "Not found"],
		["smb://127.0.0.1/x", "refused"],
		["smb://nosuchhost.invalid/x", "Can't find"],
	]
	for c in cases:
		t0 = Time.get_ticks_usec()
		var r: Array = browser.list_dir(c[0])
		var e := browser.get_last_error()
		print("list_dir(%s) in %.0f ms: %d entries, error \"%s\"" % [c[0], (Time.get_ticks_usec() - t0) / 1000.0, r.size(), e])
		_check(r.is_empty() and e.contains(c[1]), "error for %s says \"%s\"" % [c[0], c[1]])

	var source_err := MediaSource.new()
	var err := source_err.open("smb://%s/%s/no-such-file.mkv" % [p_host, share])
	print("MediaSource.open(missing file): %s: %s" % [error_string(err), source_err.get_last_error()])
	_check(err != OK and source_err.get_last_error().contains("Not found"), "MediaSource.open() of a missing smb:// file fails with \"Not found\"")

	# One wrong password (Windows locks an account out after about 10 in a row), then the right one again.
	MediaBrowser.set_smb_credentials(p_host, OS.get_environment("SMB_USER"), "not-the-password", OS.get_environment("SMB_DOMAIN"))
	browser.disconnect_host()
	var denied: Array = browser.list_dir("smb://%s/%s" % [p_host, share])
	print("list_dir with a wrong password: %d entries, error \"%s\"" % [denied.size(), browser.get_last_error()])
	_check(denied.is_empty() and browser.get_last_error().contains("Access denied"), "a wrong password gives \"Access denied\"")
	_check(not browser.get_last_error().contains("not-the-password"), "the error doesn't show the password")
	MediaSource.set_smb_credentials(p_host, OS.get_environment("SMB_USER"), OS.get_environment("SMB_PASSWORD"), OS.get_environment("SMB_DOMAIN"))
	_check(not browser.list_dir("smb://%s/%s" % [p_host, share]).is_empty(), "the right password works again (credentials shared by MediaSource and MediaBrowser)")

	# close() while the readahead is busy returns quickly.
	var busy := MediaSource.new()
	if busy.open("smb://%s/%s/%s" % [p_host, share, file]) == OK:
		OS.delay_msec(200)
		t0 = Time.get_ticks_usec()
		busy.close()
		var close_ms := (Time.get_ticks_usec() - t0) / 1000.0
		_check(close_ms < 1000.0, "close() during readahead takes %.0f ms" % close_ms)


# Selects subtitle track p_track, seeks to p_from and reads events while the video advances by up to 120 s.
func _check_subtitles(p_track: Dictionary, p_from: float, file_path: String) -> void:
	var index: int = p_track["index"]
	_check(source.select_subtitle_track(index) == OK, "select_subtitle_track(%d): %s %s \"%s\" (%s)" % [index, p_track["codec"], p_track["language"], p_track["title"],
			"text" if p_track["text"] else ("bitmap" if p_track["bitmap"] else "other")])
	var serial := source.seek(p_from)
	var events: Array[Dictionary] = []
	var last_pts := p_from
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while last_pts < p_from + 120.0 and Time.get_ticks_msec() < deadline:
		var packet := source.read_video_packet()
		if packet.is_empty():
			if source.is_eof() and source.get_stats()["video_queue"] == 0:
				break
			OS.delay_msec(1)
		elif packet["serial"] == serial:
			last_pts = maxf(last_pts, packet["pts"])
		while true:
			var event := source.read_subtitle_event()
			if event.is_empty():
				break
			if event["serial"] == serial:
				events.push_back(event)
	var header := source.get_subtitle_header()
	print("Subtitle track %d: %d events between %.1f and %.1f s; header %d bytes%s" % [index, events.size(), p_from, last_pts, header.length(),
			(" (" + header.get_slice("\n", 0) + " ...)") if header != "" else ""])
	for k in range(mini(events.size(), 4)):
		var e := events[k]
		if e["bitmap"]:
			print("  %8.3f -> %8.3f  bitmap packet, %d bytes" % [e["start"], e["end"], e["data"].size()])
		else:
			print("  %8.3f -> %8.3f  text %s | ass %s" % [e["start"], e["end"], JSON.stringify(e["text"]), JSON.stringify(e["ass"])])
	var ordered := true
	for k in range(1, events.size()):
		ordered = ordered and events[k]["start"] >= events[k - 1]["start"]
	_check(source.get_stats()["subtitle_decode_errors"] == 0, "no subtitle decode errors")
	if events.is_empty():
		print("  info  no events in this window")
		return
	_check(ordered and events[0]["start"] >= p_from - 10.0, "events in order, from the seek on (first at %.3f)" % events[0]["start"])
	if p_track["text"]:
		var texts_ok := true
		for e in events:
			texts_ok = texts_ok and e["text"] != "" and e["ass"] != ""
		_check(texts_ok and header.contains("[Script Info]"), "text events have text and an ASS line; the ASS header is there")
	else:
		var data_ok := true
		for e in events:
			data_ok = data_ok and e["bitmap"] and e["data"].size() > 0
		_check(data_ok, "bitmap events carry their packet")
	# The made-up cues of make-test-files.sh: 17, one every 5 s (SRT: 2.5 s long, "Cue N at S s"; ASS: 2 s, italic "ASS N" and
	# a second line). The remux shifts the file's timeline (the video starts at the keyframe before the cut, 8.3 s earlier
	# for this file; FFmpeg's own extraction gives the same 9.299 s for the first cue), so times are checked relative.
	if file_path.ends_with("animated_subs.mkv"):
		var srt: bool = p_track["codec"] == "subrip"
		var ok := events.size() == 17
		for k in range(events.size()):
			var e := events[k]
			ok = ok and absf(e["start"] - events[0]["start"] - 5.0 * k) < 0.01 and absf(e["end"] - e["start"] - (2.5 if srt else 2.0)) < 0.01
			ok = ok and (e["text"] == "Cue %d at %d s" % [k, 5 * k + 1] if srt else e["text"] == "ASS %d\nsecond line" % k and e["ass"].contains("{\\i1}ASS %d{\\i0}\\Nsecond line" % k))
		_check(ok, "%s cues as written: 17, 5 s apart, %.1f s long, text%s" % ["SRT" if srt else "ASS", 2.5 if srt else 2.0, "" if srt else " without and ASS line with the override tags"])


func _compare_with_raw(aus: Array[Dictionary], raw_path: String) -> void:
	if not FileAccess.file_exists(raw_path):
		_check(false, "raw stream exists: %s" % raw_path)
		return
	var t0 := Time.get_ticks_usec()
	var probe := V4L2Decoder.probe_file(raw_path, "h264", aus.size(), aus.size())
	var list: Array = probe.get("first_access_units", [])
	print("Raw %s: split %d access units in %.0f ms, SPS %dx%d" % [raw_path, list.size(), (Time.get_ticks_usec() - t0) / 1000.0, probe.get("width", 0), probe.get("height", 0)])
	_check(list.size() == aus.size(), "the raw stream gives %d access units (%d)" % [aus.size(), list.size()])
	var raw := FileAccess.open(raw_path, FileAccess.READ)
	var mismatches := 0
	var size_mismatches := 0
	var bytes := 0
	for k in range(mini(aus.size(), list.size())):
		var entry: Vector2i = list[k]
		var got: PackedByteArray = aus[k]["data"]
		bytes += got.size()
		if got.size() != entry.y:
			size_mismatches += 1
		raw.seek(entry.x)
		var expected := raw.get_buffer(entry.y)
		if got != expected:
			mismatches += 1
			if mismatches <= 3:
				var first_diff := -1
				for i in range(mini(got.size(), expected.size())):
					if got[i] != expected[i]:
						first_diff = i
						break
				print("  access unit %d differs: %d bytes vs %d raw at offset %d, first difference at byte %d" % [k, got.size(), expected.size(), entry.x, first_diff])
	var last: Vector2i = list[-1] if not list.is_empty() else Vector2i()
	_check(mismatches == 0 and size_mismatches == 0, "the first %d access units are byte-identical to the raw stream's (%d bytes, %d different, %d of different size)" % [list.size(), bytes, mismatches, size_mismatches])
	_check(bytes == last.x + last.y, "and they cover the raw stream's first %d bytes without a gap" % (last.x + last.y))
