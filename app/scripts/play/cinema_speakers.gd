extends Node3D

## Virtual cinema speakers (ideas #21) and world-locked sound for 180 / 360 (#47): each channel of the film's audio
## plays from its own place in the room instead of as a stereo mix inside the head. Dialogue (the centre channel)
## comes from the screen, the fronts from the screen's edges, the surrounds from beside and behind the seat. Turn the
## head and the sound stays where it is. In 180 / 360 the speakers stand round the viewer, facing the picture's front.
##
## How: the engine keeps the audio's channels apart (MediaSource.discrete_channels, set before the file opens,
## through HWVideoSource.discrete_channels) and gives one mono AudioStream per channel. Each present channel gets an
## AudioStreamPlayer3D (no distance attenuation: direction only). The player's stereo AudioStreamPlayer goes on
## playing as the clock, on a muted bus. Play, pause, seek and the sleep fade are mirrored onto the speakers each
## frame. At a playback speed other than 1 the engine time-stretches only the stereo stream, so the stereo sound
## comes back until the speed is 1 again. Another feature that takes the player's bus (the PC audio sink) wins: the
## speakers stop while it has it and come back when it gives it back.
##
## Placement (angles from the front, positive to the right):
##   FC 0, FL / FR at the flat screen's edges (180 / 360: -30 / 30)
##   5.1: the surround pair present (SL / SR or BL / BR) at -110 / 110
##   7.1: SL / SR at -90 / 90, BL / BR at -145 / 145
##   LFE: not placed; left out by default, as in the engine's stereo mix ([speakers] lfe: a non-positional player)
## A stereo track gets the two fronts only: world-locked stereo.
##
##   enabled, set_enabled(on)    [speakers] enabled (default off); turning it on reopens the open file at its place
##   lfe, set_lfe(on)            [speakers] lfe (default off)
##   active                      speakers playing now (false: the stereo mix plays)
##   channels() -> Array[String] the placed channels, e.g. ["FL", "FR", "FC", "SL", "SR"]
##   speaker(name) -> Node       the player for a channel (AudioStreamPlayer3D, or AudioStreamPlayer for LFE)
##   static angles(present: Array) -> {name: degrees}
##   signal changed(active)

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")

signal changed(active: bool)

const NAMES := ["FL", "FR", "FC", "LFE", "BL", "BR", "SL", "SR"]
const BUS := "SpeakersClock"
## Distance of the surround speakers (and of every speaker in 180 / 360) from the seat, metres. Attenuation is off,
## so it only sets directions.
const RING := 2.5

var main: Node3D
var enabled := false
var lfe := false
var active := false
var _players := {}
var _source: Object = null
var _old_bus := "Master"
var _stereo_now := false
var _reopen_at := -1.0


func _ready() -> void:
	enabled = bool(main.settings.get_value("speakers", "enabled", false))
	lfe = bool(main.settings.get_value("speakers", "lfe", false))
	HWVideoSource.discrete_channels = enabled
	main.file_opened.connect(_on_file_opened)
	main.player.audio_track_selected.connect(func(_i: int) -> void: _rebuild())
	_rebuild()


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("speakers", "enabled", on if on else null)
	HWVideoSource.discrete_channels = on
	var src: Object = main.player.source
	if on and src != null and src.has_method("has_discrete_channels") and not src.has_discrete_channels() \
			and main.current_path != "":
		# The channels are chosen when the file opens: open it again where it was.
		_reopen_at = main.player.get_position()
		main.open_path(main.current_path, false)
		changed.emit(active)
		return
	_rebuild()
	changed.emit(active)


func set_lfe(on: bool) -> void:
	lfe = on
	main.settings.set_value("speakers", "lfe", on if on else null)
	_rebuild()


func channels() -> Array[String]:
	var out: Array[String] = []
	for i: int in _players:
		out.append(NAMES[i])
	return out


func speaker(channel_name: String) -> Node:
	return _players.get(NAMES.find(channel_name))


## Directions (degrees from the front, positive to the right) for the present channel names. On a flat screen
## _place() puts FL, FC and FR on the screen instead.
static func angles(present: Array) -> Dictionary:
	var out := {}
	var seven := "SL" in present and "BL" in present
	for n: String in present:
		match n:
			"FC":
				out[n] = 0.0
			"FL", "FR":
				out[n] = -30.0 if n == "FL" else 30.0
			"SL", "SR":
				out[n] = (90.0 if seven else 110.0) * (-1.0 if n == "SL" else 1.0)
			"BL", "BR":
				out[n] = (145.0 if seven else 110.0) * (-1.0 if n == "BL" else 1.0)
	return out


func _on_file_opened(_path: String) -> void:
	_rebuild()
	if _reopen_at >= 0.0:
		var t := _reopen_at
		_reopen_at = -1.0
		if main.player.can_seek():
			main.player.seek(t)
		changed.emit(active)  # The pane refreshes after the switch, whether or not the file has channels.


func _clear() -> void:
	for p: Node in _players.values():
		p.queue_free()
	_players.clear()
	var audio: AudioStreamPlayer = main.player.audio
	if audio.bus == BUS:
		audio.bus = _old_bus
	_source = null
	_stereo_now = false


func _rebuild() -> void:
	var was := active
	_clear()
	active = false
	var src: Object = main.player.source
	var audio: AudioStreamPlayer = main.player.audio
	if enabled and src != null and src.has_method("has_discrete_channels") and src.has_discrete_channels() \
			and (audio.bus == "Master" or audio.bus == BUS):
		var present: Array = src.get_audio_channels()
		for i in mini(present.size(), NAMES.size()):
			var c: Variant = present[i]
			var here: bool = c.get("present", false) if c is Dictionary else bool(c)
			if not here or (i == 3 and not lfe):
				continue
			var p: Node
			if i == 3:
				p = AudioStreamPlayer.new()
			else:
				var p3 := AudioStreamPlayer3D.new()
				p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
				p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
				p3.max_db = 0.0
				p3.unit_size = 100.0
				p = p3
			p.name = NAMES[i]
			p.set("stream", src.get_audio_channel_stream(i))
			add_child(p)
			_players[i] = p
		if not _players.is_empty():
			_source = src
			_ensure_bus()
			_old_bus = "Master"
			audio.bus = BUS
			active = true
			_place()
	if active != was or active:
		changed.emit(active)


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_mute(i, true)


func _process(_delta: float) -> void:
	var audio: AudioStreamPlayer = main.player.audio
	if not active:
		if audio.bus == BUS:
			# The bus came back to us after the speakers stopped (the PC audio sink restores what it found).
			audio.bus = "Master"
			_rebuild()
		return
	if main.player.source != _source or (audio.bus != BUS and audio.bus != "Master"):
		# A new file, or another feature took the sound (the PC audio sink): the speakers stop or rebuild.
		_rebuild()
		return
	# Time-stretched speeds play the stereo stream only.
	var stereo := not is_equal_approx(main.player.speed, 1.0)
	if stereo != _stereo_now:
		_stereo_now = stereo
		audio.bus = _old_bus if stereo else BUS
	var want := audio.playing and not audio.stream_paused and not stereo
	for p: Node in _players.values():
		p.set("volume_db", audio.volume_db)
		if want and not p.get("playing"):
			p.call("play", audio.get_playback_position())
		elif p.get("playing"):
			p.set("stream_paused", not want)
		if not audio.playing and p.get("playing"):
			p.call("stop")
	_place()


func _place() -> void:
	var names: Array = []
	for i: int in _players:
		names.append(NAMES[i])
	var spherical: bool = main.mode.is_spherical()
	var ang := angles(names)
	var cam: Node3D = main.camera
	var seat: Vector3 = cam.global_position if cam != null else Vector3(0, main.eye_height, 0)
	var front: Vector3
	if spherical:
		front = Vector3(sin(main.screen_yaw), 0.0, -cos(main.screen_yaw))
	else:
		front = main.screen.global_position - seat
		front.y = 0.0
		front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
	for i: int in _players:
		var p: Node = _players[i]
		if not p is Node3D:
			continue
		var n: String = NAMES[i]
		var pos: Vector3
		if not spherical and n in ["FL", "FR", "FC"]:
			# On the screen: the centre at its middle, the fronts at its edges.
			var w: float = main.screen.get_flat_size().x
			var x := 0.0 if n == "FC" else (-0.5 if n == "FL" else 0.5) * w
			pos = main.screen.global_transform * Vector3(x, 0.0, 0.0)
		else:
			var dir := front.rotated(Vector3.UP, -deg_to_rad(ang.get(n, 0.0)))
			pos = seat + dir * RING
		(p as Node3D).global_position = pos
