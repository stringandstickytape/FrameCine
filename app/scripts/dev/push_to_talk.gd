extends Node

## Push-to-talk (ideas #14 and #41; docs/dev/voice.md): hold a button, speak, let go. The clip goes over the dev link
## to the PC as a `voice_clip` event (16 kHz mono 16-bit WAV, base64). The PC listener (tools/listener.py) saves it,
## transcribes it if it can, and maps the sentence to commands (tools/voice.py). The headset only talks; it does not
## listen for anything (the link is the one the headset opened).
##
## Made by dev_tools.gd when the link is on. Hold F8 on a keyboard; on the controllers, the pane or the core calls
## begin() / end() from a binding (app-shell):
##   var ptt := preload("res://scripts/dev/push_to_talk.gd").instance()   # null without the link
##   ptt.begin(); ...; ptt.end()          # ptt.recording_changed(on) for an indicator; ptt.clip_sent(seconds)
## The `push_to_talk` command records for a given time (tests, and a desktop without a button).
##
## Needs [audio] driver/enable_input = true in project.godot (the microphone opens only while recording).

signal recording_changed(on: bool)
signal clip_sent(seconds: float)

const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const NODE_NAME := "PushToTalk"
const BUS := "PushToTalk"
const KEY := KEY_F8
const OUT_RATE := 16000
const MIN_SECONDS := 0.3
# Only a guard against a stuck button, not a limit on speaking (the user: "there really shouldn't be" one).
const MAX_SECONDS := 600.0

## scripts/dev/dev_link.gd, or the assistant service (scripts/assistant/assistant_service.gd): anything with
## send_event(name, data).
var link: Node
## The assistant link's copy does not register the `push_to_talk` dev command, and leaves F8 to the dev link's.
var register_command := true
var key_enabled := true
var recording := false
var _player: AudioStreamPlayer
var _effect: AudioEffectRecord
var _started_msec := 0
## Live transcription: while recording, the new audio goes out every PARTIAL_SECONDS as a `voice_partial` event
## (16 kHz mono 16-bit PCM, base64, `seq` from 0), so the PC can show the words as they are spoken and correct them
## as more arrive. The final `voice_clip` still carries the whole clip.
const PARTIAL_SECONDS := 1.0
var _raw_sent := 0
var _partial_left := 0.0
var _partial_seq := 0


## The push-to-talk node, or null when the dev link is off.
static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var dev := tree.root.get_node_or_null("DevHost")
	return dev.get_node_or_null(NODE_NAME) if dev != null else null


func _ready() -> void:
	if not register_command:
		return
	DevCommands.register("push_to_talk", _cmd_record, {
		"description": "Records the microphone for some seconds and sends it as a voice_clip event, as holding the "
				+ "push-to-talk button does.",
		"params": [{"name": "seconds", "type": "float", "default": 3.0}],
		"level": "control", "returns": "{seconds, bytes}"})


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not key_enabled or k == null or k.keycode != KEY or k.echo:
		return
	if k.pressed:
		begin()
	else:
		end()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if recording and Time.get_ticks_msec() - _started_msec > int(MAX_SECONDS * 1000.0):
		end()
	elif recording:
		_partial_left -= delta
		if _partial_left <= 0.0:
			_partial_left = PARTIAL_SECONDS
			_send_partial()


## The audio recorded since the last partial, as a `voice_partial` event.
func _send_partial() -> void:
	if link == null:
		return
	var rec := _effect.get_recording()
	if rec == null:
		return
	var frame_bytes := 4 if rec.stereo else 2
	var start := _raw_sent - _raw_sent % frame_bytes
	if rec.data.size() <= start:
		return
	var mono := to_mono_16k(rec.data.slice(start), rec.mix_rate, rec.stereo)
	_raw_sent = rec.data.size()
	link.send_event("voice_partial", {"pcm_b64": Marshalls.raw_to_base64(mono), "seq": _partial_seq,
			"rate": OUT_RATE})
	_partial_seq += 1


## While recording, the film's sound drops to DUCK of its volume so the microphone hears the speaker, not the
## film (the user's idea, 2026-10-31). The master bus carries the film; the microphone's own bus is separate.
const DUCK := 0.12


func _duck(on: bool) -> void:
	var main := get_tree().current_scene
	var v := float(main.get("volume")) if main != null and main.get("volume") != null else 1.0
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v * (DUCK if on else 1.0), 0.0001)))


## Starts recording (no-op while recording). False when there is no microphone input.
func begin() -> bool:
	if recording:
		return true
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		push_warning("Push-to-talk: audio/driver/enable_input is off in project.godot; no microphone.")
		return false
	_ensure_bus()
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS
		add_child(_player)
	_player.play()
	_effect.set_recording_active(true)
	_duck(true)
	recording = true
	_started_msec = Time.get_ticks_msec()
	_raw_sent = 0
	_partial_seq = 0
	_partial_left = PARTIAL_SECONDS
	recording_changed.emit(true)
	if link != null:
		link.send_event("voice_state", {"recording": true})
	return true


## Stops and sends the clip. Returns its length in seconds (0: too short, not sent).
func end() -> float:
	if not recording:
		return 0.0
	recording = false
	_effect.set_recording_active(false)
	var rec := _effect.get_recording()
	_player.stop()
	_duck(false)
	recording_changed.emit(false)
	if link != null:
		link.send_event("voice_state", {"recording": false})
	if rec == null:
		return 0.0
	var mono := to_mono_16k(rec.data, rec.mix_rate, rec.stereo)
	var seconds := mono.size() / 2.0 / OUT_RATE
	if seconds < MIN_SECONDS:
		print("Push-to-talk: %.2f s, too short; not sent" % seconds)
		return 0.0
	var wav := wav_bytes(mono, OUT_RATE)
	if link != null:
		link.send_event("voice_clip", {"wav_b64": Marshalls.raw_to_base64(wav), "seconds": snappedf(seconds, 0.01),
				"rate": OUT_RATE, "peak": peak(mono)})
	print("Push-to-talk: sent %.1f s" % seconds)
	clip_sent.emit(seconds)
	return seconds


func _ensure_bus() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		# Not heard: the effect records before the bus's mute applies.
		AudioServer.set_bus_mute(i, true)
		var fx := AudioEffectRecord.new()
		fx.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(i, fx)
	_effect = AudioServer.get_bus_effect(i, 0) as AudioEffectRecord


func _cmd_record(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if not begin():
		return ctx.fail("no microphone input (audio/driver/enable_input is off)")
	var end_msec := Time.get_ticks_msec() + int(clampf(args["seconds"], 0.5, MAX_SECONDS) * 1000.0)
	while recording and Time.get_ticks_msec() < end_msec:
		await get_tree().process_frame
	var s := end()
	return {"seconds": snappedf(s, 0.01), "sent": s > 0.0}


## 16-bit PCM (interleaved when stereo) at `rate` -> 16-bit mono at 16 kHz (linear interpolation; a box average first
## when going down by more than 2x, against aliasing).
static func to_mono_16k(data: PackedByteArray, rate: int, stereo: bool) -> PackedByteArray:
	var channels := 2 if stereo else 1
	var frames := data.size() / (2 * channels)
	var mono := PackedFloat32Array()
	mono.resize(frames)
	for f in frames:
		var s := 0.0
		for c in channels:
			s += data.decode_s16((f * channels + c) * 2)
		mono[f] = s / channels
	var step := float(rate) / OUT_RATE
	var box := maxi(int(step), 1)
	var out_frames := int(frames / step)
	var out := PackedByteArray()
	out.resize(out_frames * 2)
	for o in out_frames:
		var pos := o * step
		var i := int(pos)
		var v := 0.0
		if box > 2:
			var n := 0
			for k in range(i, mini(i + box, frames)):
				v += mono[k]
				n += 1
			v /= maxi(n, 1)
		else:
			var frac := pos - i
			v = lerpf(mono[i], mono[mini(i + 1, frames - 1)], frac)
		out.encode_s16(o * 2, clampi(int(v), -32768, 32767))
	return out


## A RIFF WAVE file around 16-bit mono PCM.
static func wav_bytes(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)        # "RIFF"
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)        # "WAVE"
	h.encode_u32(12, 0x20746d66)       # "fmt "
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)                # PCM
	h.encode_u16(22, 1)                # mono
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)       # "data"
	h.encode_u32(40, pcm.size())
	h.append_array(pcm)
	return h


## The loudest sample, 0..1 (a silent clip says the microphone gave nothing).
static func peak(pcm: PackedByteArray) -> float:
	var m := 0
	for i in range(0, pcm.size(), 2):
		m = maxi(m, absi(pcm.decode_s16(i)))
	return snappedf(m / 32768.0, 0.001)
