extends RefCounted

## One stream connection from a PC (docs/pc-windows.md, "Stream connections"), after its first line was checked: a
## thread of its own reads the TLS connection, splits the PCW1 packets and hands them on, so the frame never waits on
## the network or the decryption.
##   video (stream 1 up): each access unit goes straight into a MediaSource in stream mode (MediaSource.open_stream()
##          of the engine fork, branch frame/pc-windows), which the hardware decoder reads as it reads a film's. The
##          first key frame, and every key frame with the config-change flag (a new size or codec), starts a new
##          MediaSource; the main thread picks it up with take_source() and opens its decoder on it.
##   sound (stream 0): each AAC frame is decoded here (AudioPacketDecoder) into stereo frames, kept with its time
##          for take_sound().
## Every packet's arrival is a sample for the PC's clock (pc_clock.gd).
## Nothing here logs what a packet holds.

const PcProtocol := preload("res://scripts/pc/pc_protocol.gd")
const PcClock := preload("res://scripts/pc/pc_clock.gd")

## Sound kept for the player at most (seconds): beyond it the oldest goes.
const SOUND_KEEP := 2.0
const READ_CHUNK := 262144
const IDLE_USEC := 2000

var number := 0
var clock: PcClock
var _tcp: StreamPeerTCP
var _tls: StreamPeer
var _thread: Thread
var _mutex := Mutex.new()
var _stop := false
var _ended := false
var _error := ""
var _buf := PackedByteArray()
## Video: the source taking access units now, and a newer one for the main thread.
var _source: Object
var _new_source: Object
var _generation := 0
## Sound: [{time (microseconds), frames: PackedVector2Array}].
var _sound: Array[Dictionary] = []
var _sound_frames := 0
var _decoder: Object
var _output_rate := 48000
## Counters: packets, bytes, keys, configs, dropped (refused by the source), last (ticks of the last packet).
var _stats := {"packets": 0, "bytes": 0, "keys": 0, "configs": 0, "dropped": 0, "sound_packets": 0, "last": 0}


## Takes over the connection (its first line already read; `rest` is what came after it).
func start(tcp: StreamPeerTCP, tls: StreamPeer, rest: PackedByteArray, p_number: int, p_clock: PcClock) -> void:
	_tcp = tcp
	_tls = tls
	_buf = rest
	number = p_number
	clock = p_clock
	_output_rate = int(AudioServer.get_mix_rate())
	_thread = Thread.new()
	_thread.start(_run)


func is_sound() -> bool:
	return number == 0


## Closes the connection and waits for the thread.
func stop() -> void:
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


func ended() -> bool:
	_mutex.lock()
	var e := _ended
	_mutex.unlock()
	return e


func error() -> String:
	_mutex.lock()
	var e := _error
	_mutex.unlock()
	return e


func stats() -> Dictionary:
	_mutex.lock()
	var s := _stats.duplicate()
	_mutex.unlock()
	return s


## Video: a MediaSource started since the last call (it holds its first key frame), or null.
func take_source() -> Object:
	_mutex.lock()
	var s: Object = _new_source
	_new_source = null
	_mutex.unlock()
	return s


## Sound: what was decoded since the last call, [{time, frames}] in order.
func take_sound() -> Array[Dictionary]:
	_mutex.lock()
	var out := _sound
	_sound = []
	_sound_frames = 0
	_mutex.unlock()
	return out


# --- The thread ----------------------------------------------------------------------------------------------------

func _run() -> void:
	while true:
		_mutex.lock()
		var stopping := _stop
		_mutex.unlock()
		if stopping:
			break
		_tcp.poll()
		if _tls != _tcp:
			_tls.poll()
		var st: int = _tls.get_status()
		if st != StreamPeerTLS.STATUS_CONNECTED:
			_finish("")
			break
		var got := 0
		while got < READ_CHUNK * 8:
			var r: Array = _tls.get_partial_data(READ_CHUNK)
			if r[0] != OK:
				_finish("")
				break
			var d: PackedByteArray = r[1]
			if d.is_empty():
				break
			_buf.append_array(d)
			got += d.size()
		if ended():
			break
		if not _buf.is_empty():
			var t := PcProtocol.take_packets(_buf, 256)
			for p: Dictionary in t["packets"]:
				_handle(p)
			if int(t["used"]) > 0:
				_buf = _buf.slice(int(t["used"]))
			if str(t["error"]) != "":
				_finish(str(t["error"]))
				break
		if got == 0:
			OS.delay_usec(IDLE_USEC)
	if _tls is StreamPeerTLS and _tls.get_status() == StreamPeerTLS.STATUS_CONNECTED:
		(_tls as StreamPeerTLS).disconnect_from_stream()
	_tcp.disconnect_from_host()
	_mutex.lock()
	var src: Object = _source
	_mutex.unlock()
	if src != null:
		src.call("end_stream")


func _finish(why: String) -> void:
	_mutex.lock()
	_ended = true
	if why != "" and _error == "":
		_error = why
	_mutex.unlock()


func _handle(p: Dictionary) -> void:
	var time: int = p["time"]
	if clock != null:
		clock.observe(time)
	var data: PackedByteArray = p["data"]
	_mutex.lock()
	_stats["packets"] += 1
	_stats["bytes"] += data.size()
	_stats["last"] = Time.get_ticks_msec()
	_mutex.unlock()
	if int(p["kind"]) == PcProtocol.KIND_SOUND:
		_handle_sound(time, data)
	else:
		_handle_video(time, data, bool(p["key"]), bool(p["config"]))


func _handle_video(time: int, data: PackedByteArray, key: bool, config: bool) -> void:
	_mutex.lock()
	var src: Object = _source
	_mutex.unlock()
	if key and (src == null or config):
		# A new decoder from this key frame (the first, or a new size or codec).
		var codec := sniff_codec(data)
		var fresh: Object = ClassDB.instantiate("MediaSource") if ClassDB.class_exists("MediaSource") else null
		if fresh == null or not fresh.has_method("open_stream"):
			_finish("this engine has no stream decoder (MediaSource.open_stream)")
			return
		if fresh.call("open_stream", codec, 0, 0, 8) != OK:
			_finish("the stream decoder did not open")
			return
		if src != null:
			src.call("end_stream")
		src = fresh
		_mutex.lock()
		_source = fresh
		_new_source = fresh
		_generation += 1
		if config:
			_stats["configs"] += 1
		_mutex.unlock()
	if src == null:
		return  # Before the first key frame: nothing can decode it.
	if key:
		_mutex.lock()
		_stats["keys"] += 1
		_mutex.unlock()
	if not bool(src.call("push_video_packet", data, time, key)):
		_mutex.lock()
		_stats["dropped"] += 1
		_mutex.unlock()


func _handle_sound(time: int, data: PackedByteArray) -> void:
	if _decoder == null:
		if not ClassDB.class_exists("AudioPacketDecoder"):
			return
		_decoder = ClassDB.instantiate("AudioPacketDecoder")
		if _decoder.call("open", "aac", _output_rate) != OK:
			_decoder = null
			_finish("no AAC decoder in this engine")
			return
	var frames: PackedVector2Array = _decoder.call("decode", data)
	_mutex.lock()
	_stats["sound_packets"] += 1
	if not frames.is_empty():
		_sound.append({"time": time, "frames": frames})
		_sound_frames += frames.size()
		while _sound_frames > int(SOUND_KEEP * _output_rate) and _sound.size() > 1:
			_sound_frames -= (_sound[0]["frames"] as PackedVector2Array).size()
			_sound.remove_at(0)
	_mutex.unlock()


## "hevc" or "h264" from an access unit's first NAL unit: HEVC's two-byte header has its type in bits 1-6 of the first
## byte and a layer / temporal id of 1 in the second (a key frame starts with a VPS, an SPS or an access unit
## delimiter: 0x40, 0x42, 0x46 then 0x01); H.264's one byte never looks like that at a key frame (SPS 0x67 / 0x27,
## AUD 0x09).
static func sniff_codec(au: PackedByteArray) -> String:
	var n := au.size()
	for i in range(0, mini(n - 4, 64)):
		if au[i] == 0 and au[i + 1] == 0 and au[i + 2] == 1:
			var b0 := au[i + 3]
			var b1 := au[i + 4] if i + 4 < n else 0
			var hevc_type := (b0 >> 1) & 0x3f
			if (b0 & 0x81) == 0 and b1 == 1 and hevc_type >= 32 and hevc_type <= 40:
				return "hevc"
			return "h264"
	return "h264"
