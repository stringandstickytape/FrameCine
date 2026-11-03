extends RefCounted

## Picks the source for a path: test patterns (stub://) are always the stub; browser:// and window:// the window source
## (a desktop window, docs/window-source.md); pictures (jpg, png, webp, jps, mpo) the image source
## (scripts/play/image_source.gd, ideas #22); otherwise the hardware source when the engine has HWVideoTexture and the
## file opens. When the right source can't open, the stub stands in (with the reason on screen).

const VideoSource := preload("res://scripts/video/video_source.gd")
const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const StubVideoSource := preload("res://scripts/video/stub_video_source.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const DirectoryLister := preload("res://scripts/net/directory_lister.gd")
const LabVideoSource := preload("res://scripts/video/lab_video_source.gd")
const ImageSource := preload("res://scripts/play/image_source.gd")
const MusicSource := preload("res://scripts/play/music_source.gd")

## Files the player lists and plays in a folder. The engine's FFmpeg reads every one of these containers; H.264, HEVC
## and VP9 decode in hardware, everything else (DivX/Xvid, MPEG-1/2, WMV/VC-1, RealVideo, FLV, Theora, VP8, AV1, ...)
## in software (docs/decisions.md D18). The engine's MediaLanguages.is_video_extension() has the same list.
const VIDEO_EXTENSIONS: Array[String] = ["mkv", "mk3d", "mp4", "m4v", "mov", "qt", "avi", "divx", "xvid", "ts", "m2ts",
		"mts", "m2t", "tp", "trp", "webm", "wmv", "asf", "mpg", "mpeg", "mpe", "m1v", "m2v", "mpv", "vob", "evo", "vro",
		"rm", "rmvb", "rv", "flv", "f4v", "ogv", "ogm", "3gp", "3g2", "mxf", "nut", "dv", "dif", "wtv", "dvr-ms", "nsv",
		"ivf", "y4m", "mjpg", "mjpeg", "amv", "bik", "smk", "nuv", "h264", "264", "avc", "h265", "265", "hevc", "obu",
		"h263", "vc1"]


static func is_video_file(path: String) -> bool:
	return path.get_extension().to_lower() in VIDEO_EXTENSIONS


## Pictures the player shows (ideas #22).
static func is_image_file(path: String) -> bool:
	return ImageSource.is_image_path(path)


## Music files (ideas #64; scripts/play/music_source.gd).
static func is_music_file(path: String) -> bool:
	return MusicSource.is_music_path(path)


## A video, a picture or music: what folders list and the playlist holds.
static func is_media_file(path: String) -> bool:
	return is_video_file(path) or is_image_file(path) or is_music_file(path)


## The video files and pictures in a folder, natural order (the playlist for next / previous); test patterns for
## "stub://".
static func list_videos(folder: String) -> Array[String]:
	var out: Array[String] = []
	if folder == "lab:" or folder == "lab://":
		for c in LabVideoSource.list_cards():
			out.append(c["path"])
		return out
	if folder == "stub:" or folder == "stub://":
		for p in StubVideoSource.list_patterns():
			out.append(p["path"])
		return out
	if folder.begins_with("smb://"):
		# Blocking network listing: only for --dir=smb://... at start; the browser lists on a worker thread.
		for e: Dictionary in DirectoryLister.list(folder)["entries"]:
			if not e["is_dir"] and is_media_file(e["name"]):
				out.append(folder.trim_suffix("/") + "/" + str(e["name"]))
		return out
	var files := Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return is_media_file(f))
	files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for f: String in files:
		out.append(folder.path_join(f))
	return out


static func create(path: String, host: Node) -> VideoSource:
	if LabVideoSource.is_lab_path(path):
		var card := LabVideoSource.new()
		card.attach(host)
		card.open(path)
		return card
	if StubVideoSource.is_stub_path(path):
		var pattern := StubVideoSource.new()
		pattern.attach(host)
		pattern.open(path)
		return pattern
	if WindowVideoSource.is_window_path(path):
		var window := WindowVideoSource.new()
		window.attach(host)
		if window.open(path) == OK:
			return window
		return _placeholder(path, host, window.last_error)
	if ImageSource.is_image_path(path):
		var picture := ImageSource.new()
		picture.attach(host)
		if picture.open(path) == OK:
			return picture
		return _placeholder(path, host, picture.last_error)
	if MusicSource.is_music_path(path) and MusicSource.available():
		var music := MusicSource.new()
		music.attach(host)
		if music.open(path) == OK:
			return music
		return _placeholder(path, host, music.last_error)
	var reason := ""
	if HWVideoSource.is_available():
		var hw := HWVideoSource.new()
		hw.attach(host)
		if hw.open(path) == OK:
			return hw
		reason = hw.last_error
	else:
		reason = "no hardware video in this engine build"
	return _placeholder(path, host, reason)


## For an smb:// file whose MediaSource was opened on a worker thread (HWVideoSource.open_media_blocking()).
static func create_from_media(path: String, host: Node, result: Dictionary) -> VideoSource:
	if MusicSource.is_music_path(path) and MusicSource.available():
		var music := MusicSource.new()
		music.attach(host)
		if music.open_with_media(path, result) == OK:
			return music
		return _placeholder(path, host, music.last_error)
	var hw := HWVideoSource.new()
	hw.attach(host)
	if hw.open_with_media(path, result) == OK:
		return hw
	return _placeholder(path, host, hw.last_error)


static func _placeholder(path: String, host: Node, reason: String) -> VideoSource:
	push_warning("Using the test-pattern stand-in for %s: %s" % [path, reason])
	var stub := StubVideoSource.new()
	stub.attach(host)
	stub.open_placeholder(path, reason)
	return stub
