extends Node3D

## Spike 03: plays a raw H.264/HEVC elementary stream, or the video of a container file (MediaSource: MKV, MP4, TS...),
## through the hardware decoder (V4L2Decoder) with no copy (HWVideoTexture: decoder dmabufs imported once as Vulkan
## images, sampled in place) on a virtual screen, with the audio as the master clock.
## User arguments (after `--`):
##   --media=PATH         container file (MediaSource): video, audio track and frame times (PTS) all come from it;
##                        --file/--codec/--fps/--audio are then ignored. smb://host/share/path/file.mkv reads it from a
##                        file share (SMB2/3), with --smb-user=NAME, --smb-domain=NAME (optional) and the password from
##                        --smb-password-file=PATH (its first line) or the SMB_PASSWORD environment variable. Never printed.
##                        --net-requests=N (reads in flight, default 4) and --net-buffer-mb=N (readahead, default 16)
##                        for network A/B runs.
##                        Before open() it prints "SMB: HOST as USER (password from ...)"; without that line, this
##                        script is older than the SMB options (they would be ignored and the login would be as guest).
##   --audio-track=N      with --media: audio track (default: the file's default; -1: none).
##   --start=S            with --media: seek to S seconds before playing.
##   --trick=X            with --media: trick play at X times speed (2 to 64), keyframes only, from --start.
##   --trick-for=S        with --trick: after S seconds, normal playback (with audio) from the frame on screen.
##   --letterbox          with --media: letterbox detection; prints the picture's rectangle when known and when final.
##   --next=PATH          with --media: the next item, opened on a second HWVideoTexture and prerolled (set_next()); it
##                        takes over at the end of the first, with its audio. Prints the preroll time, the boundary and
##                        the process CPU and memory before, during and after the preroll.
##   --next-before=S      with --next: open it S seconds before the end of the first item (default: at the start).
##   --seek-eos=0|1|2     with --media: end-of-sequence NAL unit before the first access unit after a seek (V4L2Decoder
##                        seek_eos): 0 off, 1 in the same buffer (iris rejects it), 2 in a buffer of its own (default).
##   --seek-every=S       with --media: seek every S seconds of playback, by --seek-by=D seconds (default 37; back to
##                        30 s near the end). The audio pauses until the target frame is on screen. Each seek logs how
##                        long it took to settle and the decoder errors during it.
##   --subtitle-track=N   with --media: print the events of subtitle track N when they are due (text tracks: the text).
##   --subtitle-track2=M  with --subtitle-track: dual subtitles, text track M read alongside; each event says its track.
##   --subtitle-lines=N   with --media: once playback starts, read every line of text subtitle track N on a thread
##                        (MediaSource.get_subtitle_lines(): the whole file is read again) and print how long it took
##                        and what it cost the playback (process CPU, dropped frames, audio underruns).
##   --pull-audio[=S]     with --media: no AudioStreamPlayer; the audio is taken with MediaSource.read_audio_frames() at
##                        the wall clock's pace (and dropped), against an external clock S seconds ahead of it (default
##                        0; set_external_clock()). The stats line shows the clock error and the resampling ratio.
##   --file=PATH          raw Annex-B stream (default ~/spike01/streams/documentary_sbs.h264).
##   --codec=h264|hevc    (default h264).
##   --fps=N              frame rate of the stream (default 23.976). Frame N is shown at N / fps.
##   --audio=PATH         OGG Vorbis file played as the master clock (default ~/spike01/streams/documentary.ogg if it
##                        exists). --audio= (empty) plays without audio, on the frame clock.
##   --av-offset=S        added to the audio clock, in seconds (positive: video earlier). Default 0.
##   --sbs                full side-by-side 3D: left half to the left eye, right half to the right eye (flat: left half).
##   --screen-width=M     width of the 16:9 screen in metres, 3 m in front (default 4.0).
##   --loop               start again at the end (video only; meant for runs without audio).
##   --capture-buffers=N  decoder CAPTURE buffers (default 12). --lead=S: input lead over the clock (default 0.25 s).
##   --capture-format=F   decoder CAPTURE fourcc for 8-bit video: Q08C (default since PLAYER_P010; UBWC-compressed NV12,
##                        imported with the QCOM_COMPRESSED modifier as two Vulkan images; NV12 once if that fails) or NV12.
##   --chroma-offset=N    byte offset of the chroma plane in NV12/P010 CAPTURE buffers (V4L2Decoder.capture_chroma_offset),
##                        for a driver whose layout differs from the computed one. 10-bit HEVC goes to P010 when the
##                        decoder offers it (HWVIDEO_P010=1/0 in the environment forces yes/no), else to software decode.
##   --gpu-time           measure the GPU time of the main viewport and add it to the stats line.
##   --overlay-stats      also print HWVideoTexture.get_overlay_stats() every 2 s (bitrate, queues, rates, GPU clock,
##                        temperatures, battery power: what a stats overlay would show).
##   --hdr-target=NITS    HDR (PQ, HLG) is tone-mapped to an SDR display of this peak (default 203; MediaSource.get_tone_mapping()).
##   --no-tone-map        show HDR video's code values as if they were SDR (to compare).
##   --10bit             decode 10-bit HEVC to Q10C and show it (experiment, a dead end: see the README;
##                        V4L2Decoder.experimental_10bit). --q10c-view=V: how the Q10C planes are imported
##                        (rgb10a2, rgb10a2_mutable (default), rgba8, rgba8_mutable; HWVideoTexture.q10c_view).
##   --dump-planes=PREFIX at the screenshot frame, pause and save the texels of both plane textures exactly as the GPU
##                        reads them (PREFIX-plane0.png, PREFIX-plane1.png; RGBA8 planes keep all four bytes), then go on.
##   --verbose-decoder    log every decoder setup step.
##   --probe              split the file into access units, print the statistics and quit (no decoder, no GPU).
##                        With --media: open it with MediaSource (same credentials and open() as playback), print the
##                        stream info and the first access units, and quit.
##   --no-xr              flat Camera3D instead of OpenXR (also used when OpenXR isn't initialized).
##   --quit-after=N       quit after N frames (for runs over ssh).
##   --screenshot=PATH    save a PNG of the flat view at --screenshot-frame (default 300).

const STATS_INTERVAL_MS := 2000
const SCREEN_DISTANCE := 3.0

@onready var screen: MeshInstance3D = $Screen
@onready var flat_camera: Camera3D = $FlatCamera
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var audio: AudioStreamPlayer = $Audio

var video: HWVideoTexture
var source: MediaSource
var material: ShaderMaterial
var media_path := ""
var seek_every := 0.0
var trick := 0.0
var trick_for := 0.0
var trick_end_msec := 0
var letterbox := false
var letterbox_reported := 0
var next_path := ""
var next_before := -1.0 # Seconds before the end of the first item to open the next; -1: at the start.
var next_video: HWVideoTexture
var next_frame_reported := false
var cost_marks := {} # Process CPU and RSS at points of the run, for --next.
var seek_by := 37.0
var seek_settling := false
var seek_started_msec := 0
var seek_errors_before := 0
var seek_count := 0
var next_seek_msec := 0
var subtitle_events: Array[Dictionary] = []
var subtitle_lines_track := -1
var lines_thread: Thread
var lines_result: Array = []
var lines_before: Array = [] # _cost() and [frames dropped, audio underruns] when the read started.
var pull_audio := false
var pull_offset := 0.0
var pull_start_usec := 0
var pull_frames := 0
var pull_peak := 0.0
var file_path := ""
var audio_path := ""
var codec := "h264"
var fps := 23.976
var av_offset := 0.0
var sbs := false
var started := false
var ended_reported := false
var error_reported := false
var quit_after := -1
var screenshot_path := ""
var screenshot_frame := 300
var dump_prefix := ""
var frames := 0
var last_stats_msec := 0
var last_stats: Dictionary = {}
var last_shown_frames := 0
var gpu_time := false
var overlay_stats := false
var hdr_target := 203.0
var tone_map := true
var last_process_cpu := -1.0
var gpu_ms_sum := 0.0
var gpu_ms_max := 0.0
var gpu_samples := 0


func _ready() -> void:
	var home := OS.get_environment("HOME")
	file_path = home.path_join("spike01/streams/documentary_sbs.h264")
	audio_path = home.path_join("spike01/streams/documentary.ogg")
	var audio_given := false
	var use_xr := true
	var probe := false
	var screen_width := 4.0
	var loop := false
	var capture_buffers := 12
	var capture_format := ""
	var chroma_offset := 0
	var ten_bit := false
	var q10c_view := ""
	var lead := 0.25
	var verbose_decoder := false
	var audio_track := -2
	var start_at := 0.0
	var seek_eos := -1
	var subtitle_track := -1
	var subtitle_track2 := -1
	var smb_user := ""
	var smb_domain := ""
	var smb_password_file := ""
	var net_requests := 0
	var net_buffer_mb := 0
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-xr":
			use_xr = false
		elif arg == "--sbs":
			sbs = true
		elif arg == "--loop":
			loop = true
		elif arg == "--probe":
			probe = true
		elif arg == "--verbose-decoder":
			verbose_decoder = true
		elif arg.begins_with("--file="):
			file_path = _expand(arg.trim_prefix("--file="))
		elif arg.begins_with("--media="):
			media_path = _expand(arg.trim_prefix("--media="))
		elif arg.begins_with("--audio-track="):
			audio_track = arg.trim_prefix("--audio-track=").to_int()
		elif arg.begins_with("--start="):
			start_at = arg.trim_prefix("--start=").to_float()
		elif arg == "--letterbox":
			letterbox = true
		elif arg.begins_with("--next="):
			next_path = _expand(arg.trim_prefix("--next="))
		elif arg.begins_with("--next-before="):
			next_before = arg.trim_prefix("--next-before=").to_float()
		elif arg.begins_with("--trick="):
			trick = arg.trim_prefix("--trick=").to_float()
		elif arg.begins_with("--trick-for="):
			trick_for = arg.trim_prefix("--trick-for=").to_float()
		elif arg.begins_with("--seek-eos="):
			seek_eos = arg.trim_prefix("--seek-eos=").to_int()
		elif arg.begins_with("--seek-every="):
			seek_every = arg.trim_prefix("--seek-every=").to_float()
		elif arg.begins_with("--seek-by="):
			seek_by = arg.trim_prefix("--seek-by=").to_float()
		elif arg.begins_with("--subtitle-track="):
			subtitle_track = arg.trim_prefix("--subtitle-track=").to_int()
		elif arg.begins_with("--subtitle-track2="):
			subtitle_track2 = arg.trim_prefix("--subtitle-track2=").to_int()
		elif arg.begins_with("--subtitle-lines="):
			subtitle_lines_track = arg.trim_prefix("--subtitle-lines=").to_int()
		elif arg == "--pull-audio":
			pull_audio = true
		elif arg.begins_with("--pull-audio="):
			pull_audio = true
			pull_offset = arg.trim_prefix("--pull-audio=").to_float()
		elif arg.begins_with("--smb-user="):
			smb_user = arg.trim_prefix("--smb-user=")
		elif arg.begins_with("--smb-domain="):
			smb_domain = arg.trim_prefix("--smb-domain=")
		elif arg.begins_with("--net-requests="):
			net_requests = arg.trim_prefix("--net-requests=").to_int()
		elif arg.begins_with("--net-buffer-mb="):
			net_buffer_mb = arg.trim_prefix("--net-buffer-mb=").to_int()
		elif arg.begins_with("--smb-password-file="):
			smb_password_file = _expand(arg.trim_prefix("--smb-password-file="))
		elif arg.begins_with("--audio="):
			audio_path = _expand(arg.trim_prefix("--audio="))
			audio_given = true
		elif arg.begins_with("--codec="):
			codec = arg.trim_prefix("--codec=")
		elif arg.begins_with("--fps="):
			fps = arg.trim_prefix("--fps=").to_float()
		elif arg.begins_with("--av-offset="):
			av_offset = arg.trim_prefix("--av-offset=").to_float()
		elif arg.begins_with("--screen-width="):
			screen_width = arg.trim_prefix("--screen-width=").to_float()
		elif arg.begins_with("--capture-buffers="):
			capture_buffers = arg.trim_prefix("--capture-buffers=").to_int()
		elif arg.begins_with("--capture-format="):
			capture_format = arg.trim_prefix("--capture-format=")
		elif arg.begins_with("--chroma-offset="):
			chroma_offset = arg.trim_prefix("--chroma-offset=").to_int()
		elif arg == "--gpu-time":
			gpu_time = true
		elif arg == "--overlay-stats":
			overlay_stats = true
		elif arg.begins_with("--hdr-target="):
			hdr_target = arg.trim_prefix("--hdr-target=").to_float()
		elif arg == "--no-tone-map":
			tone_map = false
		elif arg == "--10bit":
			ten_bit = true
		elif arg.begins_with("--q10c-view="):
			q10c_view = arg.trim_prefix("--q10c-view=")
		elif arg.begins_with("--lead="):
			lead = arg.trim_prefix("--lead=").to_float()
		elif arg.begins_with("--quit-after="):
			quit_after = arg.trim_prefix("--quit-after=").to_int()
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-frame="):
			screenshot_frame = arg.trim_prefix("--screenshot-frame=").to_int()
		elif arg.begins_with("--dump-planes="):
			dump_prefix = arg.trim_prefix("--dump-planes=")
		else:
			push_warning("main.gd: unknown argument %s (ignored)." % arg)

	if media_path.begins_with("smb://") and not _smb_credentials(media_path, smb_user, smb_domain, smb_password_file):
		get_tree().quit(1)
		return

	if probe:
		if media_path != "":
			_probe_media()
		else:
			_probe()
		get_tree().quit()
		return

	_setup_view(use_xr)
	(screen.mesh as QuadMesh).size = Vector2(screen_width, screen_width * 9.0 / 16.0)
	screen.position = Vector3(0, 1.6, -SCREEN_DISTANCE)

	if media_path != "":
		source = MediaSource.new()
		if net_requests > 0:
			source.network_requests = net_requests
		if net_buffer_mb > 0:
			source.network_buffer_size = net_buffer_mb << 20
		source.letterbox_detection = letterbox
		var open_msec := Time.get_ticks_msec()
		var source_err := source.open(media_path)
		print("MediaSource.open() took %d ms" % (Time.get_ticks_msec() - open_msec))
		if source_err != OK:
			push_error("Can't open %s: %s (%s)" % [media_path, source.get_last_error(), error_string(source_err)])
			get_tree().quit(1)
			return
		var info := source.get_info()
		print("Media: %s, %.1f s, video %s" % [info["format"], info["duration"], info["video"]])
		for t in info["audio_tracks"]:
			print("  audio track %d: %s %s %d Hz %s %s" % [t["index"], t["codec"], t["channel_layout"], t["sample_rate"], t["language"], t["title"]])
		if audio_track >= -1:
			source.select_audio_track(audio_track)
		if subtitle_track >= 0:
			source.select_subtitle_track(subtitle_track)
			print("Subtitles: track %d %s" % [subtitle_track, info["subtitle_tracks"][subtitle_track] if subtitle_track < info["subtitle_tracks"].size() else "?"])
			if subtitle_track2 >= 0:
				var err2 := source.select_secondary_subtitle_track(subtitle_track2)
				print("Subtitles: second track %d: %s" % [subtitle_track2, error_string(err2) if err2 != OK else "selected"])
		if trick > 0.0:
			source.trick_play(trick, start_at)
			print("Trick play: %.0fx from %.1f s (keyframes only)%s" % [trick, start_at, ", for %.1f s" % trick_for if trick_for > 0.0 else ""])
		elif start_at > 0.0:
			source.seek(start_at)
		if source.get_audio_track() >= 0 and pull_audio:
			print("Audio: track %d of the file (%d Hz), pulled with read_audio_frames() and dropped, master clock; external clock %+.3f s ahead" % [
					source.get_audio_track(), source.get_output_rate(), pull_offset])
		elif source.get_audio_track() >= 0:
			audio.stream = source.get_audio_stream()
			print("Audio: track %d of the file (%d Hz), master clock" % [source.get_audio_track(), source.get_output_rate()])
	elif audio_path != "" and (audio_given or FileAccess.file_exists(audio_path)):
		var stream := AudioStreamOggVorbis.load_from_file(audio_path)
		if stream:
			audio.stream = stream
			print("Audio: %s (%.1f s), master clock" % [audio_path, stream.get_length()])
		else:
			push_error("Can't load %s as OGG Vorbis; playing without audio." % audio_path)
	if not audio.stream and not (pull_audio and source and source.get_audio_track() >= 0):
		print("Audio: none, the video runs on the frame clock")

	video = HWVideoTexture.new()
	var decoder := video.get_decoder()
	decoder.loop = loop
	decoder.capture_buffer_count = capture_buffers
	decoder.lead_time = lead
	decoder.verbose = verbose_decoder
	if seek_eos >= 0:
		decoder.seek_eos = seek_eos
		print("Decoder: seek_eos %d" % seek_eos)
	if capture_format != "":
		decoder.capture_format = capture_format
		print("Decoder: CAPTURE format %s" % capture_format)
	if chroma_offset > 0:
		decoder.capture_chroma_offset = chroma_offset
		print("Decoder: chroma offset %d" % chroma_offset)
	if ten_bit:
		decoder.experimental_10bit = true
		if q10c_view != "":
			video.q10c_view = q10c_view
		print("Decoder: experimental 10-bit (Q10C), planes imported as %s" % video.q10c_view)
	if gpu_time:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	material = screen.material_override as ShaderMaterial
	material.set_shader_parameter("y_tex", video.get_plane_texture(0))
	material.set_shader_parameter("uv_tex", video.get_plane_texture(1))
	material.set_shader_parameter("stereo_mode", 1 if sbs else 0)
	if source:
		_set_colour(source.get_video_info())
	video.format_changed.connect(_on_format_changed)

	var err: Error
	if source:
		print("Video: %s from the container%s" % [media_path, ", side-by-side 3D" if sbs else ""])
		err = video.open_source(source)
	else:
		print("Video: %s, %s at %.3f fps%s" % [file_path, codec, fps, ", side-by-side 3D" if sbs else ""])
		err = video.open(file_path, codec, fps)
	if err != OK:
		push_error("Can't play %s: %s (%s)" % [media_path if source else file_path, video.get_last_error(), error_string(err)])
		video = null
	last_stats_msec = Time.get_ticks_msec()


func _expand(path: String) -> String:
	if path.begins_with("~/"):
		return OS.get_environment("HOME").path_join(path.trim_prefix("~/"))
	return path


# Registers the SMB credentials for path's host. False (with an error) when a password was asked for but can't be had.
func _smb_credentials(path: String, user: String, domain: String, password_file: String) -> bool:
	var host := path.trim_prefix("smb://").get_slice("/", 0)
	if user == "":
		print("SMB: no --smb-user: %s is logged into as guest (most PCs refuse that)." % host)
		return true
	var password := OS.get_environment("SMB_PASSWORD")
	var source_name := "SMB_PASSWORD"
	if password_file != "":
		source_name = password_file
		var f := FileAccess.open(password_file, FileAccess.READ)
		if f == null:
			push_error("SMB: can't read the password file %s: %s." % [password_file, error_string(FileAccess.get_open_error())])
			return false
		password = f.get_as_text().get_slice("\n", 0).strip_edges()
	if password == "":
		push_error("SMB: the password from %s is empty." % source_name)
		return false
	MediaSource.set_smb_credentials(host, user, password, domain)
	print("SMB: %s as %s%s (password from %s, %d characters)" % [host, user, (" in domain " + domain) if domain != "" else ", no domain",
			source_name, password.length()])
	return true


# --probe with --media: the stream as MediaSource sees it, through the same open() as playback.
func _probe_media() -> void:
	var probe_source := MediaSource.new()
	var t0 := Time.get_ticks_msec()
	var err := probe_source.open(media_path)
	print("MediaSource.open() took %d ms" % (Time.get_ticks_msec() - t0))
	if err != OK:
		push_error("Can't open %s: %s (%s)" % [media_path, probe_source.get_last_error(), error_string(err)])
		return
	var info := probe_source.get_info()
	print("Media: %s, %.1f s, video %s" % [info["format"], info["duration"], info["video"]])
	for t in info["audio_tracks"]:
		print("  audio %s" % t)
	var sizes: Array[int] = []
	var deadline := Time.get_ticks_msec() + 10000
	while sizes.size() < 12 and Time.get_ticks_msec() < deadline:
		var packet := probe_source.read_video_packet()
		if packet.is_empty():
			OS.delay_msec(1)
			continue
		sizes.push_back(packet["data"].size())
	print("first access units (bytes) %s" % [sizes])
	var stats := probe_source.get_stats()
	if stats.get("network", false):
		print("network: %.1f MB read, %.0f Mbit/s while reading" % [stats["net_bytes_read"] / 1e6, stats["net_read_mbps"]])
	probe_source.close()


func _probe() -> void:
	print("Probing %s as %s..." % [file_path, codec])
	var info := V4L2Decoder.probe_file(file_path, codec)
	if info.is_empty():
		push_error("Probe failed.")
		return
	var count: int = info["access_units"]
	print("access_units %d (%.1f s at %.3f fps)" % [count, count / fps, fps])
	print("sps %dx%d, display %dx%d, %d-bit, chroma_format %d" % [info["width"], info["height"],
			info["display_width"], info["display_height"], info["bit_depth"], info["chroma_format"]])
	print("file_size %d, max_au_bytes %d, avg_au_bytes %.0f, %.2f Mbit/s at %.3f fps" % [info["file_size"],
			info["max_au_bytes"], info["avg_au_bytes"], info["avg_au_bytes"] * 8.0 * fps / 1e6, fps])
	print("first_access_units (offset, size) %s" % [info["first_access_units"]])
	print("sps_size_changes (au, width, height) %s" % [info["sps_size_changes"]])
	print("parse_seconds %.2f" % info["parse_seconds"])


func _setup_view(use_xr: bool) -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if use_xr and xr_interface and xr_interface.is_initialized():
		# The OpenXR runtime paces frames.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		xr_camera.current = true
		print("View: OpenXR")
	else:
		flat_camera.current = true
		print("View: flat camera")


# The shader's matrix and range from the stream's colour description. Unspecified: BT.601 below 720 lines, else BT.709.
func _set_colour(v: Dictionary) -> void:
	var m := 0
	if v.get("matrix_bt2020", false):
		m = 1
	elif v.get("color_matrix", "") in ["bt470bg", "smpte170m"] or (v.get("color_matrix", "") == "" and v.get("height", 1080) < 720):
		m = 2
	material.set_shader_parameter("matrix", m)
	material.set_shader_parameter("full_range", v.get("full_range", false))
	var hdr_note := ""
	var tm := MediaSource.get_tone_mapping(v, hdr_target)
	var transfer: int = {"pq": 1, "hlg": 2}.get(tm["transfer"], 0)
	if not tone_map:
		transfer = 0
	material.set_shader_parameter("hdr_transfer", transfer)
	if transfer != 0:
		material.set_shader_parameter("gamut", tm["gamut_matrix"])
		for key in ["tone_mapping", "source_min_pq", "source_max_pq", "max_luminance", "knee_start", "target_peak_nits", "hlg_system_gamma"]:
			material.set_shader_parameter(key, tm[key])
		hdr_note = " (HDR %s, %.0f nits to %.0f nits%s)" % [tm["transfer"], tm["source_peak_nits"], tm["target_peak_nits"], "" if tm["tone_mapping"] else ", fits"]
	elif v.get("hdr", false):
		hdr_note = " (HDR shown as SDR: --no-tone-map)"
	print("Colour: matrix %s, range %s, primaries %s, transfer %s%s" % [["BT.709", "BT.2020", "BT.601"][m], "full" if v.get("full_range", false) else "limited",
			v.get("color_primaries", "?"), v.get("color_transfer", "?"), hdr_note])


# --next: [process CPU seconds, resident MB, msec] now.
func _cost() -> Array:
	var rss_mb := 0.0
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f:
		# Line by line: /proc files have no length, so get_as_text() reads nothing.
		for i in 80:
			var line := f.get_line()
			if line.begins_with("VmRSS:"):
				rss_mb = line.get_slice(":", 1).strip_edges().to_int() / 1024.0
				break
			if f.eof_reached():
				break
	# The next item's own threads (decoder, demux), to see what waiting costs without the rest of the process.
	var next_threads := 0.0
	if next_video:
		next_threads = float(next_video.get_stats()["thread_cpu_seconds"]) + float(next_video.get_media_source().get_stats()["thread_cpu_seconds"])
	return [float(video.get_stats()["process_cpu_seconds"]) if video else 0.0, rss_mb, Time.get_ticks_msec(), next_threads]


# --next: CPU (share of one core) and memory change between two marks.
func _cost_line(from: String, to: String) -> String:
	var a: Array = cost_marks[from]
	var b: Array = cost_marks[to]
	var seconds := maxf((b[2] - a[2]) / 1000.0, 0.001)
	return "process %.1f %% of a core over %.1f s (the next item's threads %.2f %%), RSS %.0f MB (%+.0f MB)" % [
			(b[0] - a[0]) / seconds * 100.0, seconds, (b[3] - a[3]) / seconds * 100.0, b[1], b[1] - a[1]]


func _open_next() -> void:
	cost_marks["open"] = _cost()
	var next_source := MediaSource.new()
	var t := Time.get_ticks_msec()
	if next_source.open(next_path) != OK:
		push_error("--next: can't open %s: %s" % [next_path, next_source.get_last_error()])
		next_path = ""
		return
	next_video = HWVideoTexture.new()
	var decoder := next_video.get_decoder()
	var current := video.get_decoder()
	decoder.capture_buffer_count = current.capture_buffer_count
	decoder.lead_time = current.lead_time
	decoder.capture_format = current.capture_format
	if next_video.open_source(next_source) != OK:
		push_error("--next: can't play %s: %s" % [next_path, next_video.get_last_error()])
		next_path = ""
		next_video = null
		return
	video.set_next(next_video)
	video.next_started.connect(_on_next_started)
	print("Next item: %s opened in %d ms at %.2f s of the first (%s path); prerolling" % [next_path.get_file(), Time.get_ticks_msec() - t, video.get_position(), next_video.get_decode_path()])


func _check_next_item() -> void:
	if next_path == "" or not started or not source:
		return
	if next_video == null and not cost_marks.has("open") and (next_before < 0.0 or source.get_duration() - video.get_position() <= next_before):
		if cost_marks.has("start"):
			cost_marks["alone"] = _cost()
		_open_next()
	if next_video and not next_frame_reported and next_video.has_frame():
		next_frame_reported = true
		cost_marks["prerolled"] = _cost()
		print("Next item: prerolled in %.3f s (first frame %.3f held); while it opened: %s" % [video.get_stats()["next_preroll_seconds"], next_video.get_frame_time(), _cost_line("open", "prerolled")])
	if cost_marks.has("prerolled") and not cost_marks.has("waiting") and Time.get_ticks_msec() - cost_marks["prerolled"][2] >= 5000:
		cost_marks["waiting"] = _cost()
		var alone := (" (first item alone: %s)" % _cost_line("start", "alone")) if cost_marks.has("alone") else ""
		print("Next item: waiting, prerolled: %s%s" % [_cost_line("prerolled", "waiting"), alone])


func _on_next_started(incoming: HWVideoTexture) -> void:
	var outgoing := video
	var outgoing_source := source
	video = incoming
	source = incoming.get_media_source()
	video.format_changed.connect(_on_format_changed)
	_on_format_changed()
	_set_colour(source.get_video_info())
	if source.get_audio_track() >= 0:
		audio.stream = source.get_audio_stream()
		audio.play()
	print("Next item took over at frame %d: the first item's last frame %.3f s (clock %.3f, %d frames shown); the next one shows %.3f s" % [
			frames, outgoing.get_frame_time(), outgoing.get_position(), outgoing.get_stats()["frames_shown"], video.get_frame_time()])
	outgoing.close()
	outgoing_source.close()
	next_video = null
	next_path = ""
	# The stats line's rates start again from the new texture's counters.
	last_stats = {}
	last_shown_frames = 0
	last_stats_msec = Time.get_ticks_msec()
	cost_marks["swapped"] = _cost()


func _on_format_changed() -> void:
	var r := video.get_visible_uv_rect()
	material.set_shader_parameter("visible_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	material.set_shader_parameter("packing", video.get_packing())
	material.set_shader_parameter("frame_size", Vector2(video.get_decoded_size()))
	print("Video format: buffers %s, visible %s (uv %s), packing %d" % [video.get_decoded_size(), video.get_visible_rect(), r, video.get_packing()])


# The position of what is heard now, as the Godot docs recommend for audio sync (time since the last mix, minus the
# output latency), plus --av-offset.
func _audio_clock() -> float:
	return audio.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency() + av_offset


func _process(delta: float) -> void:
	frames += 1
	if frames == 3 and get_viewport().use_xr:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)

	if video:
		var master_clock := -1.0
		if started and audio.playing:
			master_clock = maxf(_audio_clock(), 0.0)
		elif started and pull_start_usec > 0:
			master_clock = maxf(source.get_audio_position() + av_offset, 0.0)
		video.update(delta, master_clock)
		if not started and video.has_frame():
			# The first frame is decoded and on screen: start the clocks together.
			started = true
			if audio.stream:
				audio.play()
			elif pull_audio and source and source.get_audio_track() >= 0:
				pull_start_usec = Time.get_ticks_usec()
				source.set_external_clock(source.get_audio_position() + pull_offset, pull_start_usec)
			video.play()
			next_seek_msec = Time.get_ticks_msec() + int(seek_every * 1000.0)
			if trick > 0.0 and trick_for > 0.0:
				trick_end_msec = Time.get_ticks_msec() + int(trick_for * 1000.0)
			if next_path != "":
				cost_marks["start"] = _cost()
			print("Playback started at frame %d (%.2f s after launch)" % [frames, Time.get_ticks_msec() / 1000.0])
		if source and trick_end_msec > 0 and Time.get_ticks_msec() >= trick_end_msec:
			# --trick-for: back to normal playback, with audio, from the frame on screen.
			trick_end_msec = 0
			print("Trick play off at %.2f s: normal playback from there" % video.get_position())
			source.trick_play(0.0, video.get_position())
		if source:
			_seek_test()
			_subtitles()
			_check_next_item()
			_pull_audio()
			_subtitle_lines()
		_report()

	if frames == screenshot_frame and screenshot_path != "":
		_save_screenshot()
	if frames == screenshot_frame and dump_prefix != "" and video:
		_dump_planes()
	if quit_after > 0 and frames == quit_after:
		print("Quitting after %d frames" % frames)
		# The audio server lets go of a stopped playback (and so the source) at its next mix: stop now, quit a few frames
		# later, or both outlive Godot's leak check.
		audio.stop()
		audio.stream = null
	if quit_after > 0 and frames >= quit_after + 6:
		get_tree().quit()


# --seek-every: seek, hold the audio and the video clock until the frame at the target is on screen, then go on together.
func _seek_test() -> void:
	var stats := video.get_stats()
	if seek_settling:
		if not stats["settling"]:
			seek_settling = false
			video.play()
			audio.stream_paused = false
			print("Seek %d settled in %d ms: frame %.3f for target %.3f, %d frames skipped so far, decoder errors during the seek %d, end-of-sequence NAL units %d" % [
					seek_count, Time.get_ticks_msec() - seek_started_msec, stats["frame_time"], stats["seek_target"], stats["frames_skipped"],
					stats["frames_error"] - seek_errors_before, stats.get("eos_inserted", 0)])
		return
	if seek_every <= 0.0 or not started or Time.get_ticks_msec() < next_seek_msec:
		return
	next_seek_msec = Time.get_ticks_msec() + int(seek_every * 1000.0)
	var target := source.get_position() + seek_by
	if source.get_duration() > 0.0 and target > source.get_duration() - 30.0:
		target = 30.0
	seek_count += 1
	seek_settling = true
	seek_started_msec = Time.get_ticks_msec()
	seek_errors_before = stats["frames_error"]
	video.pause()
	audio.stream_paused = true
	source.seek(target)
	print("Seek %d: to %.3f" % [seek_count, target])


# --subtitle-track: events arrive ahead of time; print each when the clock reaches it.
func _subtitles() -> void:
	while true:
		var event := source.read_subtitle_event()
		if event.is_empty():
			break
		if event["serial"] == source.get_serial():
			subtitle_events.push_back(event)
	var clock := video.get_position()
	while not subtitle_events.is_empty() and subtitle_events[0]["start"] <= clock:
		var e: Dictionary = subtitle_events.pop_front()
		if e["bitmap"]:
			print("[subtitle %.3f -> %.3f] bitmap packet, %d bytes" % [e["start"], e["end"], e["data"].size()])
		else:
			print("[subtitle %d %.3f -> %.3f] %s" % [e.get("track", -1), e["start"], e["end"], e["text"].replace("\n", " / ")])


# --pull-audio: take the audio due by the wall clock since playback started, as an output device would; keep the peak.
func _pull_audio() -> void:
	if pull_start_usec == 0:
		return
	var due := int((Time.get_ticks_usec() - pull_start_usec) * source.get_output_rate() / 1e6) - pull_frames
	if due <= 0:
		return
	var chunk := source.read_audio_frames(due)
	pull_frames += chunk.size()
	for i in range(0, chunk.size(), 8):
		pull_peak = maxf(pull_peak, absf(chunk[i].x))


# --subtitle-lines: one read of the whole track on a thread, started with playback; report it when it is done.
func _subtitle_lines() -> void:
	if subtitle_lines_track < 0 or not started:
		return
	if lines_thread == null:
		lines_before = [_cost(), video.get_stats()["frames_dropped"], source.get_stats()["audio_underruns"]]
		lines_thread = Thread.new()
		lines_thread.start(_read_lines.bind(source, subtitle_lines_track))
		print("Subtitle lines: reading track %d on a thread" % subtitle_lines_track)
	elif not lines_thread.is_alive():
		lines_thread.wait_to_finish()
		var cost := _cost()
		var a: Array = lines_before[0]
		var seconds := maxf((cost[2] - a[2]) / 1000.0, 0.001)
		var first: Dictionary = lines_result[0] if lines_result.size() > 0 else {}
		print("Subtitle lines: %d lines of track %d in %.1f s%s; meanwhile process CPU %.0f %% of a core, frames dropped %+d, audio underruns %+d%s" % [
				lines_result.size(), subtitle_lines_track, seconds, (", first %.3f s '%s'" % [first["start"], first["text"].replace("\n", " / ")]) if first else "",
				(cost[0] - a[0]) / seconds * 100.0, video.get_stats()["frames_dropped"] - lines_before[1], source.get_stats()["audio_underruns"] - lines_before[2],
				(", " + source.get_last_error()) if lines_result.is_empty() else ""])
		subtitle_lines_track = -1


func _read_lines(from: MediaSource, track: int) -> void:
	lines_result = from.get_subtitle_lines(track)


func _report() -> void:
	if letterbox and source and frames % 60 == 0:
		# --letterbox: the result once it is known, and again when it is final (looked at about once a second).
		var lb := source.get_letterbox()
		var state := 2 if lb["done"] else (1 if lb["known"] else 0)
		if state > letterbox_reported:
			letterbox_reported = state
			print("Letterbox (%s): picture %s of %s, bars %s, aspect %.3f; %d frames used, %d of %d scanned dark; detector CPU %.3f s, slowest keyframe %.0f ms%s" % [
					"final" if lb["done"] else "known", lb["rect"], lb["frame_size"], lb["bars"], lb["picture_aspect"], lb["frames"], lb["dark"], lb["scanned"],
					lb["cpu_seconds"], lb["decode_seconds_max"] * 1000.0, (", " + lb["error"]) if lb["error"] != "" else ""])
	var stats := video.get_stats()
	if stats["state"] == V4L2Decoder.STATE_ERROR and not error_reported:
		error_reported = true
		push_error("Decoder error: %s" % stats["last_error"])
	if stats["state"] == V4L2Decoder.STATE_ENDED and not ended_reported:
		ended_reported = true
		print("End of the stream: %d frames decoded, %d shown, %d dropped" % [stats["frames_decoded"],
				stats["frames_shown"], stats["frames_dropped"]])

	if gpu_time:
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		gpu_ms_sum += gpu_ms
		gpu_ms_max = maxf(gpu_ms_max, gpu_ms)
		gpu_samples += 1
	var now := Time.get_ticks_msec()
	if now - last_stats_msec < STATS_INTERVAL_MS:
		return
	var seconds := (now - last_stats_msec) / 1000.0
	if overlay_stats:
		var o := video.get_overlay_stats()
		var history: PackedFloat32Array = o.get("video_kbps_history", PackedFloat32Array())
		o.erase("video_kbps_history")
		print("Overlay: %s; bitrate history (last 10 s, kbit/s): %s" % [JSON.stringify(o), Array(history.slice(history.size() - 10)).map(func(v: float) -> int: return int(v))])
	var decoded: int = stats["frames_decoded"] - last_stats.get("frames_decoded", 0)
	var shown: int = stats["frames_shown"] - last_stats.get("frames_shown", 0)
	var dropped: int = stats["frames_dropped"] - last_stats.get("frames_dropped", 0)
	var frame_time: float = stats["frame_time"]
	var position: float = stats["position"]
	var offset_ms: float = (position - frame_time) * 1000.0 if frame_time >= 0.0 else 0.0
	var source_line := ""
	if source:
		var s := source.get_stats()
		source_line = ", demux queue %d AUs / audio %.2f s, underruns %d (+%d waits after seeks), decoder errors %d, demux CPU %.1f s, decoder CPU %.1f s" % [s["video_queue"],
				s["audio_buffered"], s["audio_underruns"], s.get("audio_seek_waits", 0), stats["frames_error"], s["thread_cpu_seconds"], stats["thread_cpu_seconds"]]
		if pull_start_usec > 0:
			source_line += ", pulled audio: clock error %+.1f ms, ratio %.4f, peak %.2f" % [s.get("external_clock_error_ms", 0.0), s.get("external_clock_ratio", 1.0), pull_peak]
			pull_peak = 0.0
		if s.get("network", false):
			source_line += ", network %.0f Mbit/s avg (%.0f while reading, %.0f in refills), buffer %.1f MB ahead, stalls %d (%.1f s) + %d waits in %d refills, reconnects %d, errors %d, readahead CPU %.1f s" % [
					s["net_average_mbps"], s["net_read_mbps"], s["net_refill_mbps"], s["net_buffered_bytes"] / 1e6, s["net_stalls"], s["net_stall_seconds"], s["net_seek_waits"],
					s["net_refills"], s["net_reconnects"], s["net_errors"], s["net_thread_cpu_seconds"]]
	# The whole process's CPU time (all threads, FFmpeg's decoder threads included), in % of one core.
	var process_cpu: float = stats.get("process_cpu_seconds", -1.0)
	if last_process_cpu >= 0.0 and process_cpu >= 0.0:
		source_line += ", process CPU %.0f%% of a core" % [(process_cpu - last_process_cpu) / seconds * 100.0]
	last_process_cpu = process_cpu
	if stats.get("decode_path", "") == "software":
		source_line += ", SOFTWARE decode (%s, converting %.1f s)" % [stats.get("software_description", ""), stats.get("software_convert_seconds", 0.0)]
	elif str(stats.get("decode_path_text", "hardware")) != "hardware":
		source_line += ", %s" % stats["decode_path_text"] # "hardware (VP9)", "hardware (10-bit)", ...
	if gpu_samples > 0:
		source_line += ", GPU %.2f ms avg / %.2f max" % [gpu_ms_sum / gpu_samples, gpu_ms_max]
		gpu_ms_sum = 0.0
		gpu_ms_max = 0.0
		gpu_samples = 0
	print("[%7.1f s] %s: decode %.1f fps, shown %.1f fps, dropped %d (total %d), A/V offset %+.0f ms (clock %.3f, frame %.3f), render %.0f fps, latency avg %.0f max %.0f ms, queued rate %.1f, in driver %d out/%d cap, ready %d, retiring %d%s" % [
			now / 1000.0, stats["state_name"], decoded / seconds, shown / seconds, dropped, stats["frames_dropped"],
			offset_ms, stats["position"], frame_time, Engine.get_frames_per_second(), stats["latency_avg_ms"],
			stats["latency_max_ms"], stats["queued_rate"], stats["output_in_driver"], stats["capture_in_driver"],
			stats["frames_ready"], stats["buffers_retiring"], source_line])
	last_stats = stats
	last_stats_msec = now


# Renders each plane texture texel for texel (texelFetch, no blending, alpha kept) into a SubViewport of its size and
# saves it as PNG: the decompressed data as the GPU reads it, for comparing with a reference decode offline.
func _dump_planes() -> void:
	var was_playing := video.is_playing()
	video.pause() # No new frame while the dump renders.
	audio.stream_paused = true
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D plane : filter_nearest;
void fragment() {
	COLOR = texelFetch(plane, ivec2(FRAGCOORD.xy), 0);
}
"
	var viewports: Array[SubViewport] = []
	for p in 2:
		var texture := video.get_plane_texture(p)
		var size := Vector2i(texture.get_width(), texture.get_height())
		var sub := SubViewport.new()
		sub.size = size
		sub.transparent_bg = true
		sub.disable_3d = true
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var rect := ColorRect.new()
		rect.size = Vector2(size)
		var dump_material := ShaderMaterial.new()
		dump_material.shader = shader
		dump_material.set_shader_parameter("plane", texture)
		rect.material = dump_material
		sub.add_child(rect)
		add_child(sub)
		viewports.push_back(sub)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for p in 2:
		var image := viewports[p].get_texture().get_image()
		var path := "%s-plane%d.png" % [dump_prefix, p]
		print("Plane dump %s: %dx%d %s, frame time %.6f, packing %d: %s" % [path, image.get_width(), image.get_height(),
				image.get_format(), video.get_frame_time(), video.get_packing(), error_string(image.save_png(path))])
		viewports[p].queue_free()
	audio.stream_paused = false
	if was_playing:
		video.play()


func _save_screenshot() -> void:
	# Under gamescope an unfocused X11 window may never be drawn, so render the screenshot through an offscreen
	# SubViewport that shares the main world. In XR this shows what the flat camera (and the left eye) would see.
	var sub := SubViewport.new()
	sub.size = Vector2i(1920, 1080)
	sub.world_3d = get_world_3d()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.global_transform = flat_camera.global_transform
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	var err := img.save_png(screenshot_path)
	print("Screenshot (offscreen) %s (%dx%d) at frame time %.3f: %s" % [screenshot_path, img.get_width(),
			img.get_height(), video.get_frame_time() if video else -1.0, error_string(err)])
	sub.queue_free()


func _exit_tree() -> void:
	if video:
		var stats := video.get_stats()
		print("Final: %d frames decoded, %d shown, %d dropped, %d stale, %d decoder errors, state %s" % [
				stats["frames_decoded"], stats["frames_shown"], stats["frames_dropped"], stats["frames_stale"],
				stats["frames_error"], stats["state_name"]])
		video.close()
	if source:
		source.close() # Also stops a --subtitle-lines read still going.
		source = null
	if lines_thread and lines_thread.is_started():
		lines_thread.wait_to_finish()
	# The material belongs to the cached scene: let go of the plane textures so nothing outlives the video.
	if material:
		material.set_shader_parameter("y_tex", null)
		material.set_shader_parameter("uv_tex", null)
	video = null
