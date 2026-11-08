extends AudioStreamPlayer3D

## The PC's sound (docs/pc-windows.md, phase 1: one stream for the whole PC, stream 0). The reader (pc_stream.gd)
## decodes the AAC frames; here they go into an AudioStreamGenerator so that each is heard at its time on the PC's
## clock plus the delay, the same number the pictures are shown against (pc_clock.gd): a frame due before what is heard
## now is dropped, a gap before the next frame is filled with silence. Small slips (under TOLERANCE) are left alone,
## so the clocks' drift costs a dropped or added moment every few minutes, not a resampler.
## It plays from the big screen when a PC window is there (`at_screen`), else just in front of the head. On the Film bus
## (scripts/env/env_audio.gd), as the film's sound is.

const PcClock := preload("res://scripts/pc/pc_clock.gd")

const BUFFER_SECONDS := 0.3
const TOLERANCE := 0.03
const AHEAD := 1.2

var clock: PcClock
var source: RefCounted
## The node the sound comes from (the big screen), or null: in front of `head`.
var at_screen: Node3D
var head: Node3D
var _gen: AudioStreamGenerator
var _playback: AudioStreamGeneratorPlayback
var _pending: Array[Dictionary] = []
var _rate := 48000.0
## Counters for the tests and the status: frames pushed, dropped (late), silence filled.
var pushed := 0
var dropped := 0
var silence := 0


func _ready() -> void:
	_rate = AudioServer.get_mix_rate()
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = _rate
	_gen.buffer_length = BUFFER_SECONDS
	stream = _gen
	if AudioServer.get_bus_index(&"Film") >= 0:
		bus = &"Film"
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	unit_size = 10.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if at_screen != null and is_instance_valid(at_screen):
		global_position = at_screen.global_position
	elif head != null and is_instance_valid(head):
		global_position = head.global_position - head.global_transform.basis.z * AHEAD
	step()


## Moves what the reader decoded into the generator (tests call it without the tree's frames).
func step() -> void:
	if source != null:
		_pending.append_array(source.call("take_sound"))
	if _playback == null or clock == null or not clock.known() or _pending.is_empty():
		return
	var space := _playback.get_frames_available()
	var queued := int(BUFFER_SECONDS * _rate) - space
	# The PC time of the next frame pushed now, when it will be heard.
	var due := clock.now() + float(maxi(queued, 0)) / _rate + AudioServer.get_output_latency()
	while not _pending.is_empty() and space > 0:
		var c: Dictionary = _pending[0]
		var frames: PackedVector2Array = c["frames"]
		var start := float(c["time"]) / 1e6
		var end := start + float(frames.size()) / _rate
		if end < due - TOLERANCE:
			dropped += frames.size()
			_pending.remove_at(0)
			continue
		if start < due - TOLERANCE:
			# Partly late: from the frame due now.
			var skip := clampi(int((due - start) * _rate), 0, frames.size())
			dropped += skip
			frames = frames.slice(skip)
			start += float(skip) / _rate
		elif start > due + TOLERANCE:
			# Early: silence until it is due.
			var gap := mini(int((start - due) * _rate), space)
			if gap > 0:
				var quiet := PackedVector2Array()
				quiet.resize(gap)
				_playback.push_buffer(quiet)
				silence += gap
				space -= gap
				due += float(gap) / _rate
			if space <= 0:
				break
		var n := mini(frames.size(), space)
		if n <= 0:
			break
		_playback.push_buffer(frames.slice(0, n) if n < frames.size() else frames)
		pushed += n
		space -= n
		due += float(n) / _rate
		if n < frames.size():
			_pending[0] = {"time": int(round((start + float(n) / _rate) * 1e6)), "frames": frames.slice(n)}
			break
		_pending.remove_at(0)


func status() -> Dictionary:
	return {"pushed": pushed, "dropped": dropped, "silence": silence, "pending": _pending.size(),
			"at_screen": at_screen != null}
