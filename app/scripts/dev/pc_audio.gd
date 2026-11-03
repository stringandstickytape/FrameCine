extends Node

## PC audio sync, groundwork (idea #9; docs/pc-audio.md): the headset plays the film silent and streams its decoded
## sound to a PC (tools/audio_sink.py), which plays it and is the clock: it reports which media time its speakers
## play, and the headset holds the video back by the measured delay so picture and PC sound agree.
##
## The headset connects OUT to the sink (TCP, default port 47820); the sink listens on the PC. Stream:
##   headset -> PC   one JSON line {v, rate, channels: 2, format: "s16le"}, then frames:
##                   "A" [u32 bytes][f64 media time of the first sample][f64 headset clock][PCM s16le stereo]
##   PC -> headset   JSON lines: {t: "clock", media, buffer_ms, underruns, drift_ppm} 10x a second; {t: "pong", h}
##
## Two ways to get the sound:
## - Pull (PLAYER_REQUESTS on, the default when the engine can): MediaSource.read_audio_frames() takes the decoded
##   sound straight from the engine, instead of the player's AudioStreamPlayer (player.audio_external), paced at real
##   time. The video runs on frame time. The sync error is the PC's media time now minus the video's; above 80 ms it
##   is fixed at once (audio skipped ahead, or held back), below that MediaSource.set_external_clock() resamples the
##   sound by up to 0.5 % until the error is gone.
## - Capture (any engine, and the test tone): the player's AudioStreamPlayer goes to a muted bus "PCAudio" with an
##   AudioEffectCapture, so the headset is silent and the frames are what it would have played. The delay: the local
##   audio clock minus the media time the PC plays now; smoothed, it sets player.av_offset (video later by the delay),
##   moving at most 20 ms per report after the first.
## The PC's media time now: its last report, aged by the time since, plus half a round trip. The sink absorbs the
## drift between the two sound clocks by dropping or repeating single frames.
##
##   const PCAudio := preload("res://scripts/dev/pc_audio.gd")
##   PCAudio.start(main, "192.168.1.10")  /  PCAudio.stop()  /  PCAudio.instance().status()
## Commands: pc_audio {host, port, on, mode}, pc_audio_status. Start flags: --pc-audio=HOST[:PORT],
## --pc-audio-mode=auto|pull|capture.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const NODE_NAME := "PCAudio"
const BUS := "PCAudio"
const PORT := 47820
const PING_EVERY := 1.0
const MAX_STEP := 0.02
const SMOOTH := 0.2
## Pull mode: a sync error above this is fixed at once; below it the engine's external clock resamples.
const JUMP_OVER := 0.08
## Pull mode: the most sent after a stall, so the PC is not flooded.
const MAX_PULL := 0.5
const STATUS_EVERY := 10.0

var host := ""
## A test signal instead of the film (a 440 Hz tone with a click each second, on its own exact clock): checks the
## transport, the sink and the delay measurement where no film can play in real time.
var test_tone := false
var port := PORT
## "auto": pull when the engine can (MediaSource.read_audio_frames), else capture. "pull" or "capture" to force one.
var mode := "auto"
var main: Node:
	get:
		var tree := Engine.get_main_loop() as SceneTree
		return tree.current_scene if tree != null else null

var _peer := StreamPeerTCP.new()
var _connected := false
var _capture: AudioEffectCapture
var _old_bus := ""
var _player: AudioStreamPlayer
var _in := PackedByteArray()
var _rate := 48000
var _tone: AudioStreamGeneratorPlayback
var _tone_pushed := 0
## The media time the next captured frame continues from (-1: unknown), so stamps stay continuous between reads.
var _next_t := -1.0
var _sent_frames := 0
var _sent_bytes := 0
var _report := {}           # the last clock report, with "rx"
var _rtt := 0.0
var _ping_at := 0.0
var _delay := -1.0          # smoothed seconds
var _base_offset := 0.0
var _applied := 0.0
var _reconnect_at := 0.0
var _error := ""
## Pull mode state.
var _pulling := false
var _media: Object
var _pull_clock := -1.0     # the headset time up to which frames were taken (-1: start pacing again)
var _hold_until := 0.0      # no jump before this: the last one has not reached the reports yet
var _sync := 0.0            # smoothed sync error, seconds (PC minus video)
var _sync_n := 0
var _jumps := 0
var _status_at := 0.0


## The node made by the last start, until its deferred add_child has run (instance() finds it meanwhile).
static var _pending: Node = null


static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var n: Node = tree.root.get_node_or_null(NODE_NAME) if tree != null else null
	if n == null and is_instance_valid(_pending) and not _pending.is_queued_for_deletion():
		return _pending
	return n


## Adds a new node to the root at the end of the frame (the root may be busy now: main's _ready), unless it was
## stopped meanwhile. The argument is untyped: it may be a freed object by then.
static func _add_later(root: Node, n: Node) -> void:
	_pending = n
	_add_now.call_deferred(root, n)


static func _add_now(root: Node, n) -> void:
	if not is_instance_valid(n) or n != _pending:
		return
	_pending = null
	root.add_child(n)


## Takes a node away at once: out of the tree now (its _exit_tree closes sockets and frees the name, so a new one can
## take both in the same frame), freed later. A node not yet added is freed now.
static func _discard(n: Node) -> void:
	if n == _pending:
		_pending = null
	if n.is_inside_tree():
		n.get_parent().remove_child(n)
		n.queue_free()
	else:
		n.free()


static func attach(m: Node, args: Dictionary) -> Node:
	if not args.has("pc-audio"):
		return null
	return start(m, str(args["pc-audio"]), false, str(args.get("pc-audio-mode", "auto")))


## target: "HOST" or "HOST:PORT". how: auto, pull or capture.
static func start(m: Node, target: String, tone := false, how := "auto") -> Node:
	stop()
	var n: Node = (load("res://scripts/dev/pc_audio.gd") as GDScript).new()
	n.name = NODE_NAME
	n.test_tone = tone
	n.mode = how if how in ["auto", "pull", "capture"] else "auto"
	n.host = target.get_slice(":", 0)
	n.port = int(target.get_slice(":", 1)) if target.contains(":") else PORT
	_add_later(m.get_tree().root, n)
	return n


static func stop() -> void:
	var n := instance()
	if n != null:
		_discard(n)


static func _now() -> float:
	return Time.get_ticks_usec() / 1e6


func _ready() -> void:
	_rate = int(AudioServer.get_mix_rate())
	_ensure_bus()
	if test_tone:
		_player = AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = _rate
		gen.buffer_length = 0.2
		_player.stream = gen
		add_child(_player)
		_old_bus = BUS
		_player.bus = BUS
		_player.play()
		_tone = _player.get_stream_playback()
	else:
		_player = main.player.audio
		_old_bus = _player.bus
		_player.bus = BUS
		main.player.opened.connect(_choose_mode)
		main.player.seeked.connect(_on_seeked)
		_choose_mode()
	_base_offset = float(main.player.av_offset)
	_connect()
	print("PC audio: sending to %s:%d (%s); the headset plays silent" % [host, port, "pull" if _pulling else "capture"])


func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.bus = _old_bus
	var m := main
	if m != null and is_instance_valid(m) and not test_tone:
		m.player.av_offset = _base_offset
		if m.player.opened.is_connected(_choose_mode):
			m.player.opened.disconnect(_choose_mode)
			m.player.seeked.disconnect(_on_seeked)
		if _pulling:
			if _media_ok() and _media.has_method("set_external_clock"):
				_media.call("set_external_clock", -1.0, 0)
			m.player.audio_external = false
	_peer.disconnect_from_host()
	print("PC audio: off; sound back on the headset")


func _media_now() -> Object:
	var src: Object = main.player.source if main != null else null
	return src.get("_media") if src != null and "_media" in src else null


func _media_ok() -> bool:
	return _media != null and is_instance_valid(_media)


## Pull or capture, for the file open now (called again for each file).
func _choose_mode() -> void:
	var m := _media_now()
	var can_pull := m != null and m.has_method("read_audio_frames")
	if mode == "pull" and not can_pull:
		print("PC audio: this engine or file has no MediaSource.read_audio_frames(); capturing instead")
	var pull := can_pull and mode != "capture"
	var rate := int(m.call("get_output_rate")) if pull and m.has_method("get_output_rate") else \
			int(AudioServer.get_mix_rate())
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	if pull != _pulling or rate != _rate:
		# A new stream format: the sink takes it from a new header, so connect again.
		if _connected:
			_peer.disconnect_from_host()
	_pulling = pull
	_media = m if pull else null
	_rate = rate
	main.player.audio_external = pull
	_restart_sync()


func _restart_sync() -> void:
	_pull_clock = -1.0
	_next_t = -1.0
	_sync = 0.0
	_sync_n = 0
	_hold_until = _now() + 1.0


func _on_seeked(_t: float) -> void:
	_restart_sync()


func _ensure_bus() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_mute(i, true)
		var fx := AudioEffectCapture.new()
		# Room for a stall of a second or two (a slow frame must not lose sound).
		fx.buffer_length = 2.0
		AudioServer.add_bus_effect(i, fx)
	_capture = AudioServer.get_bus_effect(i, 0) as AudioEffectCapture


func _connect() -> void:
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host(host, port)
	if err != OK:
		_error = "can't connect: %s" % error_string(err)
	_connected = false
	_reconnect_at = _now() + 3.0


## Where the stream being sent is: the player's position, or for the test tone the frames it has mixed.
func _stream_position() -> float:
	if _tone != null:
		var queued := int(0.2 * _rate) - _tone.get_frames_available()
		return float(_tone_pushed - queued) / _rate
	return _player.get_playback_position()


func _fill_tone() -> void:
	var n := _tone.get_frames_available()
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var k := _tone_pushed + i
		var v := 0.2 * sin(TAU * 440.0 * k / _rate)
		if k % _rate < _rate / 100:
			v = 0.8  # A 10 ms click on each whole second.
		frames[i] = Vector2(v, v)
	_tone.push_buffer(frames)
	_tone_pushed += n


func _process(_delta: float) -> void:
	if _tone != null:
		_fill_tone()
	_peer.poll()
	var st := _peer.get_status()
	if st != StreamPeerTCP.STATUS_CONNECTED:
		if _connected:
			print("PC audio: the sink went away; trying again")
		_connected = false
		_capture.clear_buffer()
		if st != StreamPeerTCP.STATUS_CONNECTING and _now() > _reconnect_at:
			_connect()
		return
	if not _connected:
		_connected = true
		_peer.set_no_delay(true)  # only on an open socket
		_error = ""
		var head := JSON.stringify({"v": 1, "rate": _rate, "channels": 2, "format": "s16le",
				"app": str(ProjectSettings.get_setting("application/config/name"))}) + "\n"
		_peer.put_data(head.to_utf8_buffer())
		print("PC audio: connected to %s:%d, %d Hz" % [host, port, _rate])
	_send_audio()
	_read_reports()
	if _now() - _status_at > STATUS_EVERY and not _report.is_empty():
		_status_at = _now()
		print("PC audio: %s, %s, PC buffer %s ms, round trip %d ms, %d jumps" % ["pull" if _pulling else "capture",
				("sync error %+d ms" % roundi(_sync * 1000.0)) if _pulling else ("delay %d ms" % roundi(_delay * 1000.0)),
				str(_report.get("buffer_ms", "?")), roundi(_rtt * 1000.0), _jumps])
	if _now() - _ping_at > PING_EVERY:
		_ping_at = _now()
		_peer.put_data((JSON.stringify({"t": "ping", "h": _ping_at}) + "\n").to_utf8_buffer())


func _send_audio() -> void:
	if _pulling:
		_send_pulled()
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var frames := _capture.get_buffer(n)
	# The newest captured sample is about where the player's stream is now. Stamps continue from the last read, and
	# follow the stream again only when it jumped (a seek): the stream position moves in mix-sized steps.
	var newest := _stream_position() + AudioServer.get_time_since_last_mix()
	var first := newest - float(frames.size()) / _rate
	if _next_t >= 0.0 and absf(first - _next_t) < 0.15:
		first = _next_t
	_next_t = first + float(frames.size()) / _rate
	_send_frames(frames, first)


## Pull mode: takes the frames due since the last call (real time on the headset clock) from the engine.
func _send_pulled() -> void:
	var p: Node = main.player
	if not _media_ok() or not p.is_playing() or p.is_settling():
		_pull_clock = -1.0
		return
	var now := _now()
	if _pull_clock < 0.0:
		_pull_clock = now
		return
	var n := int((now - _pull_clock) * _rate)
	if n <= 0:
		return
	if n > int(MAX_PULL * _rate):
		n = int(MAX_PULL * _rate)
		_pull_clock = now
	else:
		_pull_clock += float(n) / _rate
	var frames: PackedVector2Array = _media.call("read_audio_frames", n)
	if frames.is_empty():
		return
	var first := float(_media.call("get_audio_position")) - float(frames.size() - 1) / _rate
	_send_frames(frames, first)


## Sends frames as one "A" message: [u32 bytes][f64 media time of the first][f64 headset clock][s16le stereo].
func _send_frames(frames: PackedVector2Array, first: float) -> void:
	var pcm := PackedByteArray()
	pcm.resize(frames.size() * 4)
	for i in frames.size():
		var v := frames[i]
		pcm.encode_s16(i * 4, clampi(int(v.x * 32767.0), -32768, 32767))
		pcm.encode_s16(i * 4 + 2, clampi(int(v.y * 32767.0), -32768, 32767))
	var head := PackedByteArray()
	head.resize(21)
	head[0] = 0x41  # "A": a frame (JSON lines start with "{")
	head.encode_u32(1, pcm.size())
	head.encode_double(5, first)
	head.encode_double(13, _now())
	head.append_array(pcm)
	var r: Array = _peer.put_partial_data(head)
	if r[0] == OK and int(r[1]) < head.size():
		# The socket is full: finish this frame so the stream stays framed (the sink buffers it).
		_peer.put_data(head.slice(int(r[1])))
	_sent_frames += frames.size()
	_sent_bytes += head.size()


func _read_reports() -> void:
	var avail := _peer.get_available_bytes()
	if avail <= 0:
		return
	var r: Array = _peer.get_partial_data(avail)
	if r[0] != OK:
		return
	_in.append_array(r[1])
	while true:
		var nl := _in.find(10)
		if nl < 0:
			break
		var line := _in.slice(0, nl).get_string_from_utf8()
		_in = _in.slice(nl + 1)
		var msg: Variant = JSON.parse_string(line)
		if not msg is Dictionary:
			continue
		match str(msg.get("t", "")):
			"pong":
				_rtt = _now() - float(msg.get("h", _now()))
			"clock":
				msg["rx"] = _now()
				_report = msg
				_follow()


## The PC's media time now, from its last report.
func pc_media_time() -> float:
	if _report.is_empty():
		return -1.0
	return float(_report["media"]) + (_now() - float(_report["rx"])) + _rtt / 2.0


func _follow() -> void:
	var m := main
	if m == null or (not test_tone and not m.player.is_playing()):
		return
	if _pulling:
		_follow_pulled()
		return
	var pc := pc_media_time()
	if pc < 0.0:
		return
	var local := _stream_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
	var d := local - pc
	if d < -1.0 or d > 5.0:
		return  # A seek or a gap: wait for the reports to settle.
	_delay = d if _delay < 0.0 else lerpf(_delay, d, SMOOTH)
	if test_tone:
		return
	# Video later by the delay (av_offset > 0 is video earlier).
	var target := _base_offset - _delay
	var current := float(m.player.av_offset)
	var next := target if _applied == 0.0 else current + clampf(target - current, -MAX_STEP, MAX_STEP)
	m.player.av_offset = next
	_applied = next


## Pull mode: the PC's media time against the video's. A big error is fixed at once (skip ahead, or hold back), a
## small one by the engine's external clock: its error is audio position minus clock, so the clock given is the
## audio position less the sync error.
func _follow_pulled() -> void:
	var p: Node = main.player
	if not _media_ok() or p.is_settling():
		return
	var pc := pc_media_time()
	if pc < 0.0:
		return
	var e := pc - float(p.get_position())
	if absf(e) > 5.0:
		return  # A seek on its way through the sink.
	_sync = e if _sync_n == 0 else lerpf(_sync, e, SMOOTH)
	_sync_n += 1
	var now := _now()
	if now < _hold_until:
		return
	if absf(_sync) > JUMP_OVER and _sync_n >= 3:
		var behind := _sync < 0.0
		if behind:
			_media.call("read_audio_frames", int(-_sync * _rate))  # The PC is behind: skip the sound ahead.
		elif _pull_clock >= 0.0:
			_pull_clock += _sync  # The PC is ahead: send nothing for that long.
		_jumps += 1
		print("PC audio: sync error %+d ms, %s" % [roundi(_sync * 1000.0), "skipped ahead" if behind else "held back"])
		_sync = 0.0
		_sync_n = 0
		_hold_until = now + 1.0 + _rtt
		return
	if _media.has_method("set_external_clock"):
		_media.call("set_external_clock", float(_media.call("get_audio_position")) - _sync, Time.get_ticks_usec())


func status() -> Dictionary:
	var engine := {}
	if _pulling and _media_ok() and _media.has_method("get_stats"):
		var st: Dictionary = _media.call("get_stats")
		for k in ["external_clock", "external_clock_error_ms", "external_clock_ratio"]:
			if st.has(k):
				engine[k] = st[k]
	return {"host": "%s:%d" % [host, port], "connected": _connected, "test_tone": test_tone, "rate": _rate,
			"mode": "pull" if _pulling else "capture", "sync_error_ms": snappedf(_sync * 1000.0, 0.1) if _pulling else null,
			"jumps": _jumps, "engine": engine, "sent_seconds":
			snappedf(float(_sent_frames) / _rate, 0.01), "sent_mb": snappedf(_sent_bytes / 1e6, 0.01),
			"rtt_ms": snappedf(_rtt * 1000.0, 0.1), "delay_ms": null if _pulling else snappedf(_delay * 1000.0, 0.1),
			"av_offset": snappedf(float(main.player.av_offset), 0.001) if main != null else 0.0,
			"pc": _report.duplicate(), "pc_media_time": snappedf(pc_media_time(), 0.001), "error": _error,
			"engine_clock": main != null and main.player.source != null and "_media" in main.player.source
					and main.player.source.get("_media") != null
					and (main.player.source.get("_media") as Object).has_method("set_external_clock")}


static func register_commands(cmd_host: Node) -> void:
	DevCommands.register("pc_audio", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		if not args["on"]:
			stop()
			return {"on": false}
		if str(args["host"]) == "":
			return ctx.fail("give host: the PC running tools/audio_sink.py")
		start(cmd_host.main, "%s:%d" % [args["host"], args["port"]], args["test_tone"], args["mode"])
		ctx.summary = "sound to the PC"
		return {"on": true, "host": args["host"], "port": args["port"]}, {
		"description": "Plays the film's sound on a PC (tools/audio_sink.py) with the PC as the clock; the headset is "
				+ "silent and holds its picture back to match (docs/pc-audio.md; the Sound tab's Play sound on a PC).",
		"params": [{"name": "host", "type": "string", "default": "",
				"description": "the PC's address on this network, e.g. 192.168.1.10; needed when on is true"},
				{"name": "port", "type": "int", "default": PORT, "description": "the port audio_sink.py listens on"},
				{"name": "on", "type": "bool", "default": true,
				"description": "true starts the sound on the PC, false brings it back to the headset"},
				{"name": "test_tone", "type": "bool", "default": false, "description": "a tone with a click each "
						+ "second instead of the film, on an exact clock"},
				{"name": "mode", "type": "string", "default": "auto", "description": "auto (pull when the engine "
						+ "can), pull (MediaSource.read_audio_frames) or capture (the player's sound from a muted bus)"}],
		"level": "control", "assistant": "control", "returns": "{on, host, port}"})
	DevCommands.register("pc_audio_status", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		var n := instance()
		return n.status() if n != null else {"on": false}, {
		"description": "PC audio: connected, delay, av_offset, the PC's last clock report.", "assistant": "read",
		"returns": "{connected, delay_ms, av_offset, pc, ...}"})
