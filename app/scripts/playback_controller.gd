extends Node

## Owns the current VideoSource and its audio, and runs the clock: A/V sync with the audio as master (as spike 03):
## the clocks start together once the first frame is ready; every frame the video shows the frame for the audio
## position (get_playback_position + time since last mix - output latency + A/V offset). Without audio the source
## advances on frame time.

const VideoSource := preload("res://scripts/video/video_source.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")

## A new source is open (or a stand-in for a file that couldn't be played).
signal opened
## An smb:// file is connecting on a worker thread; `opened` follows.
signal connecting(path: String)
signal format_changed
signal playing_changed(playing: bool)
signal ended
## A seek was issued to `seconds` (after clamping), by anyone.
signal seeked(seconds: float)
## select_audio_track() was called (by the menu or a feature); index into source.get_audio_tracks().
signal audio_track_selected(index: int)

var source: VideoSource
## The smb:// file being connected to on a worker thread, or "".
var connecting_path := ""
var _open_id := 0
var _open_tasks: Array[int] = []
var audio: AudioStreamPlayer
## Seconds added to the audio clock (positive: video earlier).
var av_offset := 0.0
## Playback speed (scripts/play/playback_speed.gd): the mix-time corrections of the audio clock are real seconds, so
## they count this many media seconds each.
var speed := 1.0
## Someone else takes the source's audio (PC audio pulls it with MediaSource.read_audio_frames(), which drains the same
## ring as get_audio_stream()): no AudioStreamPlayer stream then, and the video runs on frame time.
var audio_external := false:
	set(v):
		if v == audio_external:
			return
		audio_external = v
		if audio == null:
			return
		if v:
			audio.stop()
			audio.stream = null
		elif source != null:
			audio.stream = source.get_audio_stream()
			if audio.stream and _started:
				audio.play(source.get_position())
				audio.stream_paused = not _want_playing or _settle_target >= 0.0
var _want_playing := true
var _started := false
var _ended_sent := false
## Seek target while the decoder works from the keyframe up to it (audio held, video clock held there), or -1.
var _settle_target := -1.0
var _settle_frames := 0
## Frames to wait before trusting "not settling" (the texture notices the seek in its next update), and the most to
## hold (10 s at 72 Hz) whatever happens.
const SETTLE_MIN_FRAMES := 2
## The audio clock, smoothed: it runs on with real time and is pulled towards the audio position by CLOCK_PULL of the
## error each frame, at most CLOCK_MAX_STEP seconds a frame (so the frame cadence never visibly changes), and snaps to
## it when they differ by more than CLOCK_SNAP (a seek, a stall). Seen on the Frame: with a DTS 5.1 track (a 1080p
## MKV) the raw audio position lags for about a second, then jumps 90 to 140 ms (a sawtooth), two video frames
## fell due at once and one was dropped, about 40 % of them; with the audio off, none. The raw clock stays the
## reference, so A/V sync is unchanged on average (within the sawtooth's half depth).
const CLOCK_PULL := 0.02
const CLOCK_MAX_STEP := 0.0005
const CLOCK_SNAP := 0.25
var _smooth_clock := -1.0
const SETTLE_MAX_FRAMES := 720


func _ready() -> void:
	audio = AudioStreamPlayer.new()
	audio.name = "Audio"
	# The film's own bus (scripts/env/env_audio.gd): the room's sounds duck under it, the binaural mix included.
	EnvAudio.ensure_buses()
	audio.bus = EnvAudio.FILM
	add_child(audio)


## Opens a file. smb:// container files connect, log in and probe on a worker thread (seconds when the host doesn't
## answer): `connecting_path` is set meanwhile, and `opened` comes when that is done. Opening something else in
## between drops the late answer.
func open(path: String) -> void:
	close()
	if HWVideoSource.opens_async(path):
		_open_id += 1
		var id := _open_id
		connecting_path = path
		_open_tasks.append(WorkerThreadPool.add_task(func() -> void:
			var result := HWVideoSource.open_media_blocking(path)
			_on_media_opened.call_deferred(id, path, result), false, "open " + path))
		connecting.emit(path)
		return
	_use_source(VideoSourceFactory.create(path, self))


func _on_media_opened(id: int, path: String, result: Dictionary) -> void:
	for i in range(_open_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_open_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_open_tasks[i])
			_open_tasks.remove_at(i)
	if id != _open_id:
		# Superseded: the user opened something else meanwhile.
		var media: Object = result.get("media")
		if media != null and media.has_method("close"):
			media.call("close")
		return
	connecting_path = ""
	_use_source(VideoSourceFactory.create_from_media(path, self, result))


func _use_source(new_source: VideoSource) -> void:
	source = new_source
	source.format_changed.connect(func() -> void: format_changed.emit())
	audio.stream = null if audio_external else source.get_audio_stream()
	_started = false
	_ended_sent = false
	_want_playing = true
	opened.emit()


## Gapless change (scripts/play/gapless.gd, ideas #44): `new_source` took over the plane textures at the end of the
## current one and is already playing. It becomes the source (opened is emitted as for any open) and the old one closes;
## its audio starts with the first frame, as after an open. keep_old (picture in picture's swap, #87): the old source
## stays open and is returned, for the caller to keep playing.
func adopt(new_source: VideoSource, keep_old := false) -> VideoSource:
	var old := source
	_open_id += 1
	connecting_path = ""
	audio.stop()
	_settle_target = -1.0
	_use_source(new_source)
	if old != null and old != new_source and not keep_old:
		old.close()
		return null
	return old


func close() -> void:
	_open_id += 1
	connecting_path = ""
	audio.stop()
	audio.stream = null
	if source != null:
		source.close()
	source = null
	_started = false


func has_source() -> bool:
	return source != null


func is_playing() -> bool:
	return _want_playing


func play() -> void:
	if source == null:
		return
	if source.is_ended():
		seek(0.0)
	_want_playing = true
	if _started:
		source.play()
		if audio.stream:
			if audio.playing:
				# After a seek the audio waits for the target frame (_process releases it).
				audio.stream_paused = _settle_target >= 0.0
			else:
				audio.play(source.get_position())
	playing_changed.emit(true)


func pause() -> void:
	if source == null:
		return
	_want_playing = false
	source.pause()
	audio.stream_paused = true
	playing_changed.emit(false)


func toggle() -> void:
	if _want_playing:
		pause()
	else:
		play()


func seek(seconds: float) -> void:
	if source == null:
		return
	var duration := source.get_duration()
	var t := maxf(seconds, 0.0)
	if duration > 0.0:
		t = minf(t, duration)
	if not source.can_seek():
		# Raw streams can only restart; never move the audio away from the video. Live streams can't even restart.
		if t > 0.5 or (source.has_method("is_live") and source.is_live()):
			return
		t = 0.0
	source.seek(t)
	_ended_sent = false
	# The decoder restarts at the keyframe before t and decodes up to it (seconds of video on long GOPs): hold the
	# audio until the frame at t is shown, else those frames come out late and the picture jumps when it catches up.
	_settle_target = t
	_settle_frames = 0
	if audio.stream and _started:
		audio.play(t)
		audio.stream_paused = not _want_playing or _settle_target >= 0.0
	seeked.emit(t)


func seek_relative(delta_seconds: float) -> void:
	if source != null:
		seek(source.get_position() + delta_seconds)


## A seek is settling: the decoder works up to the target, the video clock is held there.
func is_settling() -> bool:
	return _settle_target >= 0.0


func can_seek() -> bool:
	return source != null and source.can_seek()


## Media time of playback. While a seek settles (the decoder works from the keyframe up to the target), the source
## still reports the frame from before the seek; this reports the target then, so a second +10 s, a chapter skip or a
## loop check right after a seek starts from where playback is going.
func get_position() -> float:
	if source == null:
		return 0.0
	return _settle_target if _settle_target >= 0.0 else source.get_position()


func get_duration() -> float:
	return source.get_duration() if source != null else 0.0


func select_audio_track(index: int) -> void:
	if source == null:
		return
	source.select_audio_track(index)
	audio_track_selected.emit(index)
	var stream: AudioStream = null if audio_external else source.get_audio_stream()
	if stream == audio.stream:
		return  # Same stream, new track behind it (MediaSource).
	var t := source.get_position()
	audio.stream = stream
	if audio.stream and _started:
		audio.play(t)
		audio.stream_paused = not _want_playing


func _audio_clock() -> float:
	return audio.get_playback_position() + (AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()) * speed + av_offset


func _process(delta: float) -> void:
	if source == null:
		return
	var master_clock := -1.0
	if _settle_target >= 0.0:
		master_clock = _settle_target
	elif _started and audio.stream and audio.playing and not audio.stream_paused:
		var raw := maxf(_audio_clock(), 0.0)
		if _smooth_clock < 0.0:
			_smooth_clock = raw
		else:
			_smooth_clock += delta * speed
			var err := raw - _smooth_clock
			_smooth_clock = raw if absf(err) > CLOCK_SNAP 					else _smooth_clock + clampf(err * CLOCK_PULL, -CLOCK_MAX_STEP, CLOCK_MAX_STEP)
		master_clock = _smooth_clock
	if master_clock < 0.0 or _settle_target >= 0.0:
		_smooth_clock = -1.0
	source.update(delta, master_clock)
	var gave_up := false
	if _settle_target >= 0.0:
		_settle_frames += 1
		gave_up = _settle_frames >= SETTLE_MAX_FRAMES
		if (_settle_frames >= SETTLE_MIN_FRAMES and not source.is_settling()) or gave_up:
			_settle_target = -1.0
			if audio.stream and _started:
				audio.stream_paused = not _want_playing
	if not _started and (source.has_frame() or gave_up or source.is_audio_blocking_video()):
		# The first frame is ready: start the clocks together. Or it can't come first (a sparse or finished video track,
		# seen with a resume in a 1 fps file): the sound starts without it, and the picture follows when it can.
		_started = true
		if _want_playing:
			source.play()
			if audio.stream:
				audio.play(source.get_position())
	if source.is_ended() and not _ended_sent:
		_ended_sent = true
		_want_playing = false
		audio.stream_paused = true
		playing_changed.emit(false)
		ended.emit()
