extends "res://scripts/video/stub_video_source.gd"

## The test lab's calibration cards as video (idea #48; docs/test-lab.md): "lab://<card>" paths. Built on the test
## pattern source, so each card goes through the same NV12 encode, video shader, crop and eye selection as real video.
## The judder cards present one picture per content frame at 24, 30 or 60 fps, timed from the playback position like
## a decoder's frames, so the display's own cadence shows.

const LabCard := preload("res://scripts/video/lab_card.gd")
const LAB_SCHEME := "lab://"

## [id, label, card, mode id, width, height, content fps (0: static, redrawn at 10 Hz; -1: a still, drawn once),
## description]
const CARDS: Array = [
	["alignment", "Per-eye alignment", "alignment", "flat_sbs", 3840, 1080, 0.0,
			"Nonius lines and grids per eye: the half-lines meet in one cross when the eyes line up."],
	["convergence", "Convergence and IPD", "convergence", "flat_sbs", 3840, 1080, 0.0,
			"Rings from near to far: every ring should fuse into one."],
	["judder_24", "Judder 24 fps", "judder", "flat_mono", 1280, 720, 24.0,
			"Motion at the film rate: the bar should glide evenly."],
	["judder_30", "Judder 30 fps", "judder", "flat_mono", 1280, 720, 30.0, "Motion at 30 fps."],
	["judder_60", "Judder 60 fps", "judder", "flat_mono", 1280, 720, 60.0, "Motion at 60 fps."],
	["av_sync", "A/V sync", "av_sync", "flat_mono", 1280, 720, 60.0,
			"A flash and a beep each second: move the A/V offset until they land together."],
	["zoneplate", "Zone plate, flat 4K", "zoneplate", "flat_mono", 3840, 2160, -1.0,
			"Rings down to the finest the frame holds: false rings show where the picture aliases."],
	["zoneplate_360", "Zone plate, 360° 8K", "zoneplate", "360_mono", 7680, 3840, -1.0,
			"The zone plate as an 8K 360° frame: shrunk about 2 times on the display."],
	["starfield_360", "Starfield, 360° 8K", "starfield", "360_mono", 7680, 3840, -1.0,
			"Single-pixel stars in an 8K 360° frame: they should stay steady as you turn, not twinkle."],
]
## The A/V sync card's audio (idea #24): a 30 ms 1 kHz beep at each whole second, silence between. 8-bit at 8 kHz:
## 600 s is 4.8 MB, and as the player's audio it is the master clock, so the A/V offset moves the picture against
## it exactly as for a film.
const BEEP_RATE := 8000
const BEEP_SECONDS := 0.03
const BEEP_HZ := 1000.0

var _card_kind := "alignment"
var _beep: AudioStreamWAV
var _fps := 0.0
var _frame_index := -1


static func list_cards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Array in CARDS:
		out.append({"path": LAB_SCHEME + c[0], "label": c[1], "description": c[7]})
	return out


static func is_lab_path(p: String) -> bool:
	return p.begins_with(LAB_SCHEME)


func get_kind() -> String:
	return "lab"


func open(p_path: String) -> Error:
	path = p_path
	var id := p_path.trim_prefix(LAB_SCHEME)
	var entry: Array = CARDS[0]
	for c: Array in CARDS:
		if c[0] == id:
			entry = c
	_card_kind = entry[2]
	_fps = entry[6]
	_frame_index = -1
	var mode := VideoMode.from_id(entry[3])
	_known_mode = mode
	_duration = 600.0
	_build(mode, Vector2i(entry[4], entry[5]), entry[1], entry[7])
	return OK


func _new_card() -> TestCard:
	var card := LabCard.new()
	card.card_id = _card_kind
	card.fps = _fps if _fps > 0.0 else 24.0
	return card


func update(delta: float, master_clock: float) -> void:
	if _fps < 0.0:
		_update_still(delta, master_clock)
		return
	if _fps <= 0.0:
		super(delta, master_clock)
		return
	if _card == null:
		return
	_frames += 1
	if _playing:
		_position = master_clock if master_clock >= 0.0 else _position + delta
		if _position >= _duration:
			_position = fmod(_position, _duration)
	# One picture per content frame, as a decoder would deliver them: redraw when the frame index changes.
	var index := int(floor(_position * _fps))
	if index != _frame_index:
		_frame_index = index
		_card.time = _position
		(_card as LabCard).frame_index = index
		_card.queue_redraw()
		_card_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_encode_frames = 2
		_redraws += 1
	if _encode_frames > 0:
		_encode_frames -= 1
		_y_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_uv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## A still card: drawn and encoded once (an 8K frame redrawn ten times a second would cost more than what it is there
## to measure); the position runs on as a film's would.
func _update_still(delta: float, master_clock: float) -> void:
	if _card == null:
		return
	_frames += 1
	if _playing:
		_position = master_clock if master_clock >= 0.0 else _position + delta
		if _position >= _duration:
			_position = fmod(_position, _duration)
	if _frame_index < 0:
		_frame_index = 0
		_card.queue_redraw()
		_card_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_encode_frames = 2
		_redraws += 1
	if _encode_frames > 0:
		_encode_frames -= 1
		_y_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_uv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## The beep track for `seconds` (the A/V sync card's audio).
static func beep_stream(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * BEEP_RATE)
	var data := PackedByteArray()
	data.resize(n)
	var beep := int(BEEP_SECONDS * BEEP_RATE)
	for s in int(seconds):
		for i in beep:
			# Signed 8-bit; a short fade in and out against clicks.
			var env := minf(1.0, minf(i, beep - i) / 24.0)
			data.encode_s8(s * BEEP_RATE + i, int(100.0 * env * sin(TAU * BEEP_HZ * i / BEEP_RATE)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = BEEP_RATE
	w.stereo = false
	w.data = data
	return w


func get_audio_stream() -> AudioStream:
	if _card_kind != "av_sync":
		return super()
	if _beep == null:
		_beep = beep_stream(_duration)
	return _beep


func get_video_info() -> Dictionary:
	var info := super()
	info["codec"] = "calibration card (NV12)"
	if _fps > 0.0:
		info["fps"] = _fps
	return info
