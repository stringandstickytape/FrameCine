extends Node

## Hardware video: which way 10-bit video plays (docs/features.md, "Hardware 10-bit video"). features.hwvideo.
##
## 10-bit HEVC, HDR10 included, plays in hardware with Valve's stock driver: the engine reads the decoder's compressed
## 10-bit output (Q10C) through the GPU's YCbCr sampler (docs/decisions.md D14). When the system's decoder driver
## offers linear P010 (mainline Linux 7.2 does), the engine takes P010 first (HWVideoTexture, V4L2Decoder). Without
## either, 10-bit up to 1080p plays in software. Nothing here installs anything or asks for a password: this node only
## reads what the engine found, for the System tab's row (ui/hw_video_row.gd) and the read command `hwvideo_status`.
##
## Settings: [hwvideo] hw_vp9 (true): VP9 in hardware, one session at a time (HWVideoSource.hw_vp9 ->
## HWVideoTexture.hw_vp9; HWVIDEO_HW_VP9=0/1 in the environment overrides it). False: VP9 always in software.
## [hwvideo] iris_bundle and iris_setup_prompt (the removed one-time setup, D21) are ignored when an old settings file
## still has them.

const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

## Emitted when the 10-bit path may have changed (the decoder's formats were read, a 10-bit file opened).
signal changed

const SECTION := "hwvideo"
## The decoder's device (V4L2Decoder.is_p010_available()'s default).
const DEVICE := "/dev/video-dec0"
const PROBE_TIMEOUT := 10.0

## The paths, as status()["path"] gives them, and how the System row says each.
const PATH_TEXTS := {
	"p010": "on (P010 from the system's video driver)",
	"q10c": "on (Q10C through the GPU, stock driver)",
	"software": "off: 10-bit plays in software",
	"unknown": "checking ...",
}

## The app core (scripts/main.gd). Untyped: main.gd preloads the hub, which preloads this.
var main: Node
## The decoder's formats have been read (V4L2Decoder.is_p010_available() answered once). Before that, P010 is not
## asked for in status(): asking opens the decoder, and that is done once, at start, on a worker thread.
var probed := false


func _ready() -> void:
	HWVideoSource.hw_vp9 = bool(main.settings.get_value(SECTION, "hw_vp9", true))
	register_commands()
	main.file_opened.connect(_on_file_opened)


## Called by main.gd once the pane is up: reads the decoder's formats once on a worker thread (the engine keeps the
## answer), then says which way 10-bit plays. Nothing runs as root.
func start(_args: Dictionary) -> void:
	if not _engine_has("V4L2Decoder", "is_p010_available") or OS.get_name() != "Linux":
		probed = true
		_log()
		changed.emit()
		return
	await WorkerTask.run(get_tree(), func() -> Variant:
		return ClassDB.class_call_static("V4L2Decoder", "is_p010_available", DEVICE), PROBE_TIMEOUT)
	probed = true
	_log()
	changed.emit()


## The engine can show 10-bit video from the stock driver: the GPU lists the decoder's compressed 10-bit format and no
## import or picture check has failed in this run (DmabufImage.is_q10c_available()). False without the hwvideo module.
static func q10c_available() -> bool:
	return _engine_has("DmabufImage", "is_q10c_available") \
			and bool(ClassDB.class_call_static("DmabufImage", "is_q10c_available"))


## The system's decoder driver offers linear P010 (the engine's cached answer; a 10-bit stream's own format list wins
## over the look at idle). False without the hwvideo module, and before the look at start.
func p010_available() -> bool:
	return probed and _engine_has("V4L2Decoder", "is_p010_available") \
			and bool(ClassDB.class_call_static("V4L2Decoder", "is_p010_available", DEVICE))


## Which way 10-bit video plays now, in the engine's order (HWVideoTexture.open_source()): "p010" when the driver
## offers it, else "q10c" when the GPU reads Q10C, else "software"; "unknown" before the look at start.
func path() -> String:
	if not probed:
		return "unknown"
	if p010_available():
		return "p010"
	return "q10c" if q10c_available() else "software"


## What the System row says after "Hardware 10-bit video: ".
func summary() -> String:
	return str(PATH_TEXTS.get(path(), path()))


## The 10-bit path for the dev link, the assistant and the System row. Read-only: nothing is installed or run.
##   path              "p010", "q10c", "software" or "unknown" (path())
##   text              the System row's words for it
##   p010              the decoder driver offers linear P010
##   q10c              the GPU reads the stock driver's Q10C (no failure in this run)
##   q10c_off_reason   why Q10C was turned off in this run ("" when it wasn't)
##   decoder_formats   the decoder's CAPTURE formats as the engine last read them ("" before the look)
##   hw_vp9            VP9 in hardware is on ([hwvideo] hw_vp9)
func status() -> Dictionary:
	var p := path()
	return {
		"path": p,
		"text": str(PATH_TEXTS.get(p, p)),
		"p010": p010_available(),
		"q10c": q10c_available(),
		"q10c_off_reason": str(ClassDB.class_call_static("DmabufImage", "get_q10c_disabled_reason"))
				if _engine_has("DmabufImage", "get_q10c_disabled_reason") else "",
		"decoder_formats": str(ClassDB.class_call_static("V4L2Decoder", "get_idle_capture_formats"))
				if probed and _engine_has("V4L2Decoder", "get_idle_capture_formats") else "",
		"hw_vp9": HWVideoSource.hw_vp9,
	}


func _log() -> void:
	print("HW video: 10-bit path %s (%s)" % [path(), summary()])


static func _engine_has(cls: String, method: String) -> bool:
	return ClassDB.class_exists(cls) and ClassDB.class_has_method(cls, method)


## A 10-bit file opened: what the engine learned from it (P010 in the stream's list, a failed Q10C check) may change
## the path. The row is told a moment later, once the session has started.
func _on_file_opened(_path: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var src: Object = main.player.source
	if src == null or int(src.get_video_info().get("bit_depth", 8)) < 10:
		return
	changed.emit()


## Short names of the codecs that only decode in software, for the overlay ("software (DivX 3)").
const SOFTWARE_CODEC_NAMES := {"mpeg4": "MPEG-4", "msmpeg4v1": "DivX 3 (v1)", "msmpeg4v2": "DivX 3 (v2)",
		"msmpeg4v3": "DivX 3", "mpeg1video": "MPEG-1", "mpeg2video": "MPEG-2", "h263": "H.263", "h263p": "H.263+",
		"h261": "H.261", "flv1": "Flash H.263", "wmv1": "WMV 7", "wmv2": "WMV 8", "wmv3": "WMV 9", "vc1": "VC-1",
		"rv10": "RealVideo 1", "rv20": "RealVideo 2", "rv30": "RealVideo 3", "rv40": "RealVideo 4", "theora": "Theora",
		"vp3": "VP3", "vp6f": "VP6", "vp6": "VP6", "vp8": "VP8", "av1": "AV1", "mjpeg": "Motion JPEG", "dvvideo": "DV",
		"prores": "ProRes", "cinepak": "Cinepak", "svq1": "Sorenson 1", "svq3": "Sorenson 3", "indeo3": "Indeo 3",
		"indeo4": "Indeo 4", "indeo5": "Indeo 5", "vc1image": "VC-1", "wmv3image": "WMV 9"}


## The decode path for the overlay: "hardware (10-bit)" while a 10-bit file plays in hardware, "hardware (VP9)" (or
## "hardware (VP9, 10-bit)") for VP9 in hardware, "hardware", "software", "software (DivX 3)" (with the codec when
## only software decodes it), or the source kind ("stub", "window", ...) when it has none.
static func decode_text(kind: String, info: Dictionary, stats: Dictionary) -> String:
	var path := str(stats.get("decode_path", ""))
	if kind != "hw" or path == "":
		return kind
	var ten := int(info.get("bit_depth", 8)) >= 10
	if path == "software":
		var codec := str(info.get("codec", ""))
		if codec != "" and not codec in ["h264", "hevc", "vp9"]:
			var label := str(SOFTWARE_CODEC_NAMES.get(codec, codec.to_upper()))
			return "software (%s, 10-bit)" % label if ten else "software (%s)" % label
		return "software (10-bit)" if ten else "software"
	if str(info.get("codec", "")) == "vp9":
		return "hardware (VP9, 10-bit)" if ten else "hardware (VP9)"
	return "hardware (10-bit)" if ten else "hardware"


# --- Dev link ---------------------------------------------------------------------------------------------------

## `hwvideo_status` (read): the same as main.features.hwvideo.status().
func register_commands() -> void:
	DevCommands.register("hwvideo_status", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return status(), {
		"description": "Hardware video: which way 10-bit video plays now (P010 from the system's driver, Q10C "
				+ "through the GPU with the stock driver, or software), and whether VP9 plays in hardware. Read-only.",
		"params": [],
		"returns": "{path: p010|q10c|software|unknown, text, p010, q10c, q10c_off_reason, decoder_formats, hw_vp9}",
		"assistant": "read"})
