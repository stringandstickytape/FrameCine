extends RefCounted

## The PC windows protocol (docs/pc-windows.md, "Network", "Control connection", "Stream connections"): its numbers,
## the stream packets' header, JSON lines, and the names both sides use. Static: the service, the readers and the
## tests share it.
##
## A stream packet: "PCW1", kind (1 video, 2 sound), flags (bit 0 key frame, bit 1 config change), 2 reserved bytes,
## the time (8 bytes, microseconds, little-endian signed, the PC's one clock), the payload's length (4 bytes,
## little-endian), the payload.

const PORT := 47803
const VERSION := 1
const MAGIC := "PCW1"
const HEADER_SIZE := 20
const KIND_VIDEO := 1
const KIND_SOUND := 2
const FLAG_KEY := 1
const FLAG_CONFIG := 2
## A payload larger than this is no access unit we asked for (a 4K key frame at a high bitrate is a few MB).
const MAX_PAYLOAD := 32 << 20
## A control line or a stream's first line longer than this is refused (a window list with 64 thumbnails is under 1 MB).
const MAX_LINE := 4 << 20
## Cursor shapes the PC reports (`cursor`).
const CURSOR_SHAPES: Array[String] = ["arrow", "ibeam", "hand", "wait", "cross", "size_we", "size_ns", "size_nwse",
		"size_nesw", "move", "no", "other"]
## Godot's mouse buttons and the protocol's names.
const BUTTONS := {MOUSE_BUTTON_LEFT: "left", MOUSE_BUTTON_RIGHT: "right", MOUSE_BUTTON_MIDDLE: "middle",
		MOUSE_BUTTON_XBUTTON1: "x1", MOUSE_BUTTON_XBUTTON2: "x2"}


## The header at `at` in `buf`: {kind, flags, key, config, time (microseconds), length}, {} while fewer than
## HEADER_SIZE bytes are there, or {"error": why} when it is no packet (the stream is lost then).
static func parse_header(buf: PackedByteArray, at := 0) -> Dictionary:
	if buf.size() - at < HEADER_SIZE:
		return {}
	if buf.slice(at, at + 4).get_string_from_ascii() != MAGIC:
		return {"error": "no PCW1 magic"}
	var kind := buf[at + 4]
	var flags := buf[at + 5]
	var length := buf.decode_u32(at + 16)
	if kind != KIND_VIDEO and kind != KIND_SOUND:
		return {"error": "unknown kind %d" % kind}
	if length > MAX_PAYLOAD:
		return {"error": "a payload of %d bytes" % length}
	return {"kind": kind, "flags": flags, "key": (flags & FLAG_KEY) != 0, "config": (flags & FLAG_CONFIG) != 0,
			"time": buf.decode_s64(at + 8), "length": length}


## A packet's bytes (the fake PC in the tests sends these too).
static func build_packet(kind: int, flags: int, time_usec: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(HEADER_SIZE)
	out.encode_u8(0, 0x50)  # P
	out.encode_u8(1, 0x43)  # C
	out.encode_u8(2, 0x57)  # W
	out.encode_u8(3, 0x31)  # 1
	out.encode_u8(4, kind)
	out.encode_u8(5, flags)
	out.encode_s64(8, time_usec)
	out.encode_u32(16, payload.size())
	out.append_array(payload)
	return out


## Splits whole packets off the front of `buf`: {packets: [{kind, flags, key, config, time, data}], used: bytes
## taken, error: "" or why the stream is lost}.
static func take_packets(buf: PackedByteArray, max_packets := 64) -> Dictionary:
	var packets: Array[Dictionary] = []
	var at := 0
	while packets.size() < max_packets:
		var h := parse_header(buf, at)
		if h.is_empty():
			break
		if h.has("error"):
			return {"packets": packets, "used": at, "error": str(h["error"])}
		var end := at + HEADER_SIZE + int(h["length"])
		if buf.size() < end:
			break
		h["data"] = buf.slice(at + HEADER_SIZE, end)
		packets.append(h)
		at = end
	return {"packets": packets, "used": at, "error": ""}


## One JSON object as a line.
static func line(obj: Dictionary) -> PackedByteArray:
	return (JSON.stringify(obj) + "\n").to_utf8_buffer()


## Splits whole lines off the front of `buf`: {lines: [Dictionary], used, error}. A line that is no JSON object is
## skipped (either side may be newer); one over MAX_LINE is an error.
static func take_lines(buf: PackedByteArray, max_lines := 64) -> Dictionary:
	var lines: Array[Dictionary] = []
	var at := 0
	while lines.size() < max_lines:
		var nl := buf.find(10, at)
		if nl < 0:
			if buf.size() - at > MAX_LINE:
				return {"lines": lines, "used": at, "error": "a line over %d bytes" % MAX_LINE}
			break
		var text := buf.slice(at, nl).get_string_from_utf8().strip_edges()
		at = nl + 1
		if text == "":
			continue
		var v: Variant = JSON.parse_string(text)
		if v is Dictionary:
			lines.append(v)
	return {"lines": lines, "used": at, "error": ""}


## A window id as the PC gives it: "w:<hex>" or "m:<index>".
static func is_window_id(id: String) -> bool:
	if id.begins_with("w:"):
		return id.length() > 2 and id.substr(2).is_valid_hex_number()
	if id.begins_with("m:"):
		return id.substr(2).is_valid_int()
	return false


## The protocol's name for a key: Godot's name for the physical key (docs/pc-windows.md, `key`).
static func key_name(event: InputEventKey) -> String:
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	return OS.get_keycode_string(code)
