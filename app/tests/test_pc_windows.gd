extends SceneTree

## PC windows (docs/pc-windows.md, scripts/pc/): the packet framing and the clock on their own, then the real main
## scene against the fake PC (tools/pc_windows_fake_pc.py, run with python3): discovery only while allowed, pairing
## with a wrong and the right code (the token kept only as its hash), five wrong codes closing pairing, the window
## list, panes decoding HEVC and H.264 from pushed packets (the engine fork's MediaSource.open_stream, branch
## frame/pc-windows), frames shown at their time plus the delay, a config change mid-stream, a stream that ends and
## starts again, input reaching the PC at the right pixels, focus by gaze dwell with the quality asked for, the big
## screen and back, the private layer, the sound.
## Needs the engine with the stream decoder and, for the pictures, a renderer (lavapipe; the decoder parts are skipped
## headless, where nothing draws):
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a <godot> --xr-mode off --path app \
##       --script res://tests/test_pc_windows.gd
## The clips: python3 tools/pc_windows_fake_pc.py --make-clips (ffmpeg; the test makes them when missing).
## The pane's picture is kept as user://pc_windows_test/pane.png (and later.png, big_screen.png) for a look.

const PcProtocol := preload("res://scripts/pc/pc_protocol.gd")
const PcClock := preload("res://scripts/pc/pc_clock.gd")
const PcStream := preload("res://scripts/pc/pc_stream.gd")
const PcPane := preload("res://scripts/pc/pc_pane.gd")
const PcWindowSource := preload("res://scripts/pc/pc_window_source.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const PcWindowsRow := preload("res://ui/pc_windows_row.gd")
const PcPlace := preload("res://ui/pc_place.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const PORT := 47913
const OUT := "user://pc_windows_test"

var _failures := 0
var _checks := 0
var main: Node3D
var pc: Node
var _procs: Array[int] = []
var _log := ""
var _token_file := ""
var _tool := ""
var _render := false


## A hand for the hold: the ray along its -Z, the laser calls ignored.
class FakeHand extends Node3D:
	func get_ray_origin() -> Vector3:
		return global_position

	func get_ray_direction() -> Vector3:
		return -global_basis.z

	func set_laser(_on: bool, _length := 3.0, _hit := false, _beam := Color(), _dot := Color()) -> void:
		pass


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_protocol()
	_test_clock()
	_test_sniff()
	await _test_bar()
	_render = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_tool = ProjectSettings.globalize_path("res://").path_join("../tools/pc_windows_fake_pc.py").simplify_path()
	_log = ProjectSettings.globalize_path(OUT.path_join("fake_pc.jsonl"))
	_token_file = ProjectSettings.globalize_path(OUT.path_join("token"))
	for f in [_log, _token_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var clients := ProjectSettings.globalize_path(OUT.path_join("clients.cfg"))
	if FileAccess.file_exists(clients):
		DirAccess.remove_absolute(clients)
	if not ClassDB.class_has_method("MediaSource", "open_stream"):
		print("test_pc_windows: this engine has no MediaSource.open_stream (branch frame/pc-windows); only the units ran")
		_finish()
		return
	OS.execute("python3", [_tool, "--make-clips"])

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	await _frames(5)
	pc = main.features.pc_windows
	pc.service_overrides = {"port": PORT, "bind_address": "127.0.0.1", "clients_path": OUT.path_join("clients.cfg"),
			"tls_key_path": OUT.path_join("tls.key"), "tls_cert_path": OUT.path_join("tls.crt")}
	pc.test_xr = true
	await _test_service()
	if pc.connected():
		await _test_panes()
		await _test_input()
		await _test_focus()
		await _test_big_screen()
		await _test_restart_and_config()
		await _test_commands()
		await _test_sound()
	await _test_reconnect()
	for pid in _procs:
		OS.kill(pid)
	main.queue_free()
	await _frames(3)
	_finish()


func _finish() -> void:
	print("test_pc_windows: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- Units -------------------------------------------------------------------------------------------------------

func _test_protocol() -> void:
	var payload := PackedByteArray([0, 0, 0, 1, 0x40, 1, 2, 3])
	var p := PcProtocol.build_packet(PcProtocol.KIND_VIDEO, PcProtocol.FLAG_KEY | PcProtocol.FLAG_CONFIG,
			-1234567890123, payload)
	_check("packet: 20 bytes of header", p.size() == 20 + payload.size())
	var h := PcProtocol.parse_header(p)
	_check("packet: kind, flags, time, length (%s)" % h, int(h.get("kind", 0)) == 1 and bool(h.get("key", false))
			and bool(h.get("config", false)) and int(h.get("time", 0)) == -1234567890123 and int(h["length"]) == 8)
	_check("packet: too short is nothing yet", PcProtocol.parse_header(p.slice(0, 19)).is_empty())
	var bad := p.duplicate()
	bad[0] = 0x58
	_check("packet: no magic is an error", PcProtocol.parse_header(bad).has("error"))
	var big := p.duplicate()
	big.encode_u32(16, PcProtocol.MAX_PAYLOAD + 1)
	_check("packet: a huge length is an error", PcProtocol.parse_header(big).has("error"))
	var odd := p.duplicate()
	odd[4] = 9
	_check("packet: an unknown kind is an error", PcProtocol.parse_header(odd).has("error"))
	var two := p.duplicate()
	two.append_array(PcProtocol.build_packet(PcProtocol.KIND_SOUND, 0, 42, PackedByteArray([9, 9])))
	two.append_array(p.slice(0, 10))
	var t := PcProtocol.take_packets(two)
	_check("packets: two whole, the half third left", (t["packets"] as Array).size() == 2
			and int(t["used"]) == p.size() + 22 and str(t["error"]) == "")
	_check("packets: the payloads", (t["packets"][0]["data"] as PackedByteArray) == payload
			and int(t["packets"][1]["kind"]) == 2 and int(t["packets"][1]["time"]) == 42)
	var lines := "{\"t\":\"a\"}\n\n[1, 2]\n{\"t\":\"b\",\"n\":2}\n{\"t\":\"c\"".to_utf8_buffer()
	var l := PcProtocol.take_lines(lines)
	_check("lines: the JSON objects, the rest kept", (l["lines"] as Array).size() == 2
			and str(l["lines"][1]["t"]) == "b" and lines.slice(int(l["used"])).get_string_from_utf8() == "{\"t\":\"c\"")
	_check("ids: w:hex and m:n", PcProtocol.is_window_id("w:1a2b") and PcProtocol.is_window_id("m:0")
			and not PcProtocol.is_window_id("w:") and not PcProtocol.is_window_id("x:1")
			and not PcProtocol.is_window_id("w:zz"))
	var k := InputEventKey.new()
	k.physical_keycode = KEY_A
	_check("keys: Godot's name for the physical key", PcProtocol.key_name(k) == "A")
	k.physical_keycode = KEY_KP_1
	_check("keys: the keypad (%s)" % PcProtocol.key_name(k), PcProtocol.key_name(k) == "Kp 1")


func _test_clock() -> void:
	var c := PcClock.new()
	c.delay = 0.15
	_check("clock: unknown before a packet", c.now(1000) < 0.0)
	# PC time 5 s arrives at headset tick 100 s; one later by 30 ms (jitter) must not move the offset.
	c.observe(5_000_000, 100_000_000)
	c.observe(5_100_000, 100_130_000)
	_check("clock: plays the PC's time less the delay", is_equal_approx(c.now(100_200_000), 5.2 - 0.15))
	c.observe(5_200_000, 100_190_000)  # earlier than any so far: the new best
	_check("clock: a quicker packet becomes the offset", is_equal_approx(c.now(100_200_000), 5.21 - 0.15))
	_check("clock: lateness", is_equal_approx(c.lateness(5_300_000, 100_320_000), 0.03))
	# The PC's clock runs slow: every packet in the next windows later by 5 ms: the offset moves 2 ms a window.
	c.observe(10_200_000, 105_200_000 + 5_000)
	c.observe(10_300_000, 105_300_000 + 5_000)
	c.observe(15_300_000, 110_300_000 + 5_000)
	var moved := c.now(110_300_000) - (110.3 - 94.99 - 0.15)
	_check("clock: drift slews the offset by 2 ms a window (%.4f)" % moved, moved < -0.0015 and moved > -0.0025)
	var r := PcClock.new()
	r.observe(1_000_000, 10_000_000)
	r.observe(1_000_000 + 6_000_000, 10_000_000 + 6_000_000 + 2_000_000)
	r.observe(1_000_000 + 12_000_000, 10_000_000 + 12_000_000 + 2_000_000)
	_check("clock: a jump of seconds (the PC restarted) resets it", is_equal_approx(r.now(24_000_000),
			(24.0 - 11.0) - r.delay))


func _test_sniff() -> void:
	_check("sniff: HEVC VPS", PcStream.sniff_codec(PackedByteArray([0, 0, 0, 1, 0x40, 0x01, 0x0c])) == "hevc")
	_check("sniff: HEVC AUD", PcStream.sniff_codec(PackedByteArray([0, 0, 1, 0x46, 0x01, 0x50])) == "hevc")
	_check("sniff: H.264 SPS", PcStream.sniff_codec(PackedByteArray([0, 0, 0, 1, 0x67, 0x64, 0x00])) == "h264")
	_check("sniff: H.264 AUD", PcStream.sniff_codec(PackedByteArray([0, 0, 0, 1, 0x09, 0xf0])) == "h264")


# --- The service -------------------------------------------------------------------------------------------------

func _fake(args: Array, wait := true) -> int:
	var all := [_tool, "--host", "127.0.0.1", "--port", str(PORT), "--log", _log] + args
	if wait:
		return OS.execute("python3", PackedStringArray(all))
	var pid := OS.create_process("python3", PackedStringArray(all))
	_procs.append(pid)
	return pid


func _logged() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(_log, FileAccess.READ)
	if f == null:
		return out
	for line in f.get_as_text().split("\n"):
		var v: Variant = JSON.parse_string(line) if line.strip_edges() != "" else null
		if v is Dictionary:
			out.append(v)
	return out


## The messages of type `t` the fake PC got from the headset.
func _got(t: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _logged():
		if str(e.get("t", "")) == "got" and str(e["msg"].get("t", "")) == t:
			out.append(e["msg"])
	return out


func _last(t: String) -> Dictionary:
	var out := {}
	for e in _logged():
		if str(e.get("t", "")) == t:
			out = e
	return out


## Runs the fake PC on a thread so the scene keeps its frames (OS.execute blocks).
func _fake_async(args: Array) -> int:
	var th := Thread.new()
	th.start(func() -> int: return _fake(args, true))
	while th.is_alive():
		await process_frame
	return th.wait_to_finish()


func _test_service() -> void:
	pc.set_enabled(true)
	var svc: Node = pc.service
	_check("on: the service runs", svc != null)
	await _frames(3)
	_check("on, nobody paired, not pairing: not listening", not svc.is_listening())
	svc.start_pairing()
	_check("pairing: a six-digit code", (svc.pairing_code() as String).length() == 6
			and (svc.pairing_code() as String).is_valid_int())
	_check("pairing: ten minutes", float(svc.pairing_left()) > 590.0)
	_check("pairing: the code is not in the status line", not (svc.status_text() as String).contains(svc.pairing_code()))
	if not await _wait(func() -> bool: return svc.is_listening(), 60.0):
		_check("pairing: listening (the certificate made) (%s)" % svc.problem, false)
		return
	_check("pairing: listening", true)
	var rc := await _fake_async(["--discover-only"])
	var d: Dictionary = _last("discovered").get("reply", {}) if _last("discovered").get("reply") != null else {}
	_check("discovery while pairing: a reply (rc %d)" % rc, rc == 0 and str(d.get("t", "")) == "pcw_here"
			and bool(d.get("pairing", false)) and int(d.get("port", 0)) == PORT)
	var pin := str(d.get("pin", ""))
	_check("discovery: the pin is the certificate's SHA-256 (%s)" % pin.left(12), pin.length() == 64
			and pin == svc.tls.cert_sha256)
	var code: String = svc.pairing_code()
	var wrong := "000000" if code != "000000" else "111111"
	rc = await _fake_async(["--code", wrong, "--token-file", _token_file, "--name", "WRONG-PC"])
	_check("a wrong code: refused (rc %d, %s)" % [rc, _last("answer")], rc == 2
			and str(_last("answer").get("type", "")) == "refused")
	_check("a wrong code: the TLS pin checked", bool(_last("tls").get("pin_ok", false)))
	_check("a wrong code: still pairing", svc.pairing() and svc.paired().is_empty())
	_fake(["--code", code, "--token-file", _token_file, "--name", "FAKE-PC"], false)
	if not await _wait(func() -> bool: return pc.connected(), 20.0):
		_check("the right code: connected (%s)" % _last("answer"), false)
		return
	_check("the right code: paired and connected", svc.paired().size() == 1 and not svc.pairing())
	_check("the right code: a token for the PC", bool(_last("answer").get("has_token", false))
			and FileAccess.file_exists(_token_file))
	var token := FileAccess.get_file_as_string(_token_file).strip_edges()
	var cfg := FileAccess.get_file_as_string(OUT.path_join("clients.cfg"))
	_check("the token is kept only as its SHA-256", token.length() == 64 and not cfg.contains(token)
			and cfg.contains(token.sha256_text()))
	if OS.get_name() == "Linux":
		var mode := FileAccess.get_unix_permissions(OUT.path_join("clients.cfg"))
		_check("pc_clients.cfg: owner only (%x)" % mode, mode & 63 == 0)
	await _frames(2)
	rc = await _fake_async(["--discover-only", "--name", "SOMEONE-ELSE"])
	_check("discovery, not pairing, an unknown PC: no reply", rc == 3)
	rc = await _fake_async(["--discover-only", "--name", "FAKE-PC"])
	_check("discovery, not pairing, the paired PC: a reply", rc == 0)
	# Five wrong codes close pairing.
	svc.start_pairing()
	var c2: String = svc.pairing_code()
	var w2 := "222222" if c2 != "222222" else "333333"
	for i in 5:
		await _fake_async(["--code", w2, "--name", "WRONG-%d" % i])
	_check("five wrong codes: pairing closed", not svc.pairing() and svc.paired().size() == 1)
	if not await _wait(func() -> bool: return pc.list_windows().size() >= 5, 10.0):
		_check("the window list (%s)" % [pc.list_windows()], false)
		return
	var list: Array = pc.list_windows()
	_check("the window list: windows and a monitor", list.size() == 5 and list.any(func(w: Dictionary) -> bool:
			return w["kind"] == "monitor"))
	var s: RefCounted = pc.sessions()[0]
	_check("the window list: thumbnails decoded", s.window("w:1a2b").get("thumb") is Texture2D)
	_check("the assistant's list has no titles", not JSON.stringify(list).contains("Test pattern"))
	_check("pc_status has no PC names", not JSON.stringify(pc.status()).contains("FAKE-PC"))
	await _test_ui()


## The System tab's section and the Files tab's place, on their own.
func _test_ui() -> void:
	var svc: Node = pc.service
	var row: VBoxContainer = PcWindowsRow.new()
	root.add_child(row)
	row.bind(main)
	_check("System: the section is on", (row.get("_toggle") as Button).button_pressed)
	_check("System: the paired PC listed", (row.get("_paired_box") as Node).get_child_count() == 1)
	svc.start_pairing()
	row.tick()
	var shown := (row.get("_code") as Label).text.replace(" ", "")
	_check("System: Add a PC shows the code", (row.get("_pair_box") as Control).visible and shown == svc.pairing_code())
	svc.cancel_pairing()
	row.refresh()
	_check("System: Cancel hides it", not (row.get("_pair_box") as Control).visible)
	row.queue_free()
	var place: VBoxContainer = PcPlace.new()
	root.add_child(place)
	place.bind(pc)
	_check("Files: a tile for each window (%d)" % place.tiles.size(), place.tiles.size() == 5)
	var tile: Dictionary = place.tiles.filter(func(t: Dictionary) -> bool: return t["id"] == "m:0").front()
	(tile["button"] as Button).pressed.emit()
	await _frames(2)
	var m := _pane("m:0")
	_check("Files: a tile opens its pane", m != null)
	if m != null:
		pc.close_pane(m)
	# A title that moves (a terminal's, every second): the tiles stay, only the text changes.
	var first: Button = place.tiles[0]["button"]
	var moved: Dictionary = pc.sessions()[0].windows.filter(func(w: Dictionary) -> bool: return w["id"] == place.tiles[0]["id"]).front()
	moved["title"] = "moved on"
	pc.changed.emit()
	await _frames(2)
	_check("Files: a changed title is set in place, the tiles are not built again", place.tiles.size() == 5
			and place.tiles[0]["button"] == first and is_instance_valid(first)
			and (place.tiles[0]["label"] as Label).text == "moved on")
	place.queue_free()
	await _frames(2)


# --- Panes -------------------------------------------------------------------------------------------------------

func _pane_shot(pane: Node3D, file: String) -> Image:
	if not _render:
		return null
	var cam: Camera3D = main.camera
	cam.global_position = pane.global_position + pane.global_basis.z * 0.9
	cam.look_at(pane.global_position, Vector3.UP)
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT.path_join(file))
	return img


func _picture_check(img: Image, what: String) -> void:
	if img == null:
		return
	# The test pattern's colours, round the middle of the view (where the pane is).
	var hues := {}
	var bright := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h / 4, h * 3 / 4, 8):
		for x in range(w / 4, w * 3 / 4, 8):
			var c := img.get_pixel(x, y)
			if c.v > 0.3:
				bright += 1
			if c.s > 0.4 and c.v > 0.3:
				hues[int(c.h * 6.0)] = true
	_check("%s: a coloured picture (%d bright, %d hues)" % [what, bright, hues.size()], bright > 100 and hues.size() >= 3)


func _test_panes() -> void:
	var s: RefCounted = pc.sessions()[0]
	main.camera.global_position = Vector3(0, 1.2, 0)
	main.camera.rotation = Vector3.ZERO
	await _frames(2)
	var pane: Node3D = pc.open_window(s.client_id, "w:1a2b")
	_check("open: a pane", pane != null and pc.panes.size() == 1)
	if pane == null:
		return
	var asked := func() -> bool: return _got("open").any(func(m: Dictionary) -> bool:
			return m["id"] == "w:1a2b" and int(m["stream"]) == pane.stream)
	_check("open: the PC was asked for the stream", await _wait(asked, 5.0))
	_check("open: on the private layer only", pane.get_node("Picture").get_layer_mask_value(VideoScreen.PRIVATE_LAYER)
			and not pane.get_node("Picture").get_layer_mask_value(1))
	_check("open: about one PC pixel per headset pixel (%.2f m)" % pane.width,
			absf(pane.width - PcPane.natural_width(640, 1.0)) < 0.01 and pane.width > 0.5 and pane.width < 0.6)
	_check("open: in front of the head", pane.global_position.distance_to(Vector3(0, 1.2, -1.0)) < 0.05)
	if not _render:
		print("test_pc_windows: headless, the decoding checks are skipped")
		return
	if not await _wait(func() -> bool: return pane.video.has_frame(), 15.0):
		_check("decode: a frame (%s)" % [pane.video.stats()], false)
		return
	_check("decode: frames from pushed packets (%s)" % pane.video.decode_path(), pane.video.decode_path() != "")
	_check("decode: the stream's size", pane.video.size() == Vector2i(640, 360))
	await _wait(func() -> bool: return int(pane.video.stats().get("frames_shown", 0)) > 20, 5.0)
	# Paced: the frame on show is the newest due on the PC's clock less the delay.
	var lags: Array[float] = []
	for i in 30:
		await process_frame
		var now: float = s.clock.now()
		var ft: float = pane.video.frame_time()
		if ft > 0.0:
			lags.append(now - ft)
	lags.sort()
	var med := lags[lags.size() / 2] if not lags.is_empty() else -1.0
	_check("paced: the frame on show is at most a frame interval behind its time + delay (median %.3f s, %s)" % [
			med, [lags.front(), lags.back()] if not lags.is_empty() else []],
			not lags.is_empty() and lags.front() >= -0.002 and med < 0.06)
	var shot := await _pane_shot(pane, "pane.png")
	_picture_check(shot, "the pane")
	var f1: float = pane.video.frame_time()
	await _frames(20)
	var later := await _pane_shot(pane, "later.png")
	_check("the picture moves on (%.3f -> %.3f)" % [f1, pane.video.frame_time()], pane.video.frame_time() > f1)
	if shot != null and later != null:
		var diff := 0
		for y in range(0, shot.get_height(), 16):
			for x in range(0, shot.get_width(), 16):
				if not shot.get_pixel(x, y).is_equal_approx(later.get_pixel(x, y)):
					diff += 1
		_check("the pattern moved between the pictures (%d samples differ)" % diff, diff > 5)
	var h := await _open_and_wait(s, "w:264")
	_check("H.264: frames", h != null and h.video.has_frame())
	await _test_hold(pane)


## Holding a pane (the user, 2026-11-08): it rides the ray and turns with the hand, kept level. It is taken by the
## trigger on its title bar (the user, 2026-11-11), and the squeeze leaves it alone.
func _test_hold(pane: Node3D) -> void:
	var hand := FakeHand.new()
	root.add_child(hand)
	hand.global_position = Vector3(0.2, 1.1, -0.2)
	hand.look_at(pane.global_position, Vector3.UP)
	var d := hand.global_position.distance_to(pane.global_position)
	var before: Basis = pane.global_basis
	pc._aims[hand] = {"pane": pane, "distance": d}
	_check("hold: the squeeze on the picture does nothing now", not pc.on_grip(hand, true) and not pc.holding(hand))
	pc._aims[hand] = {"pane": pane, "distance": d, "bar": true}
	_check("hold: the trigger on the title bar takes the pane and selects it", pc.on_trigger(hand, true)
			and pc.holding(hand) and pc.focused == pane and main.pointing.selected == pane
			and pc.point_holds(hand))
	pc._hold(hand, 0.016)
	_check("hold: no jump on taking it (%.3f)" % pane.global_basis.z.angle_to(before.z),
			pane.global_basis.z.angle_to(before.z) < 0.01)
	hand.rotate_y(deg_to_rad(20.0))
	hand.rotate_object_local(Vector3.RIGHT, deg_to_rad(-15.0))
	pc._hold(hand, 0.016)
	var front: Vector3 = pane.global_basis.z
	var yaw := rad_to_deg(wrapf(atan2(front.x, front.z) - atan2(before.z.x, before.z.z), -PI, PI))
	var tilt := rad_to_deg(asin(clampf(front.y, -1.0, 1.0)))
	_check("hold: turning the hand turns the pane (yaw %.1f, tilt %.1f)" % [yaw, tilt],
			absf(yaw - 20.0) < 6.0 and tilt > 8.0)
	_check("hold: level, no roll (%.3f)" % pane.global_basis.x.y, absf(pane.global_basis.x.y) < 0.001)
	_check("hold: on the ray", pane.global_position.distance_to(hand.get_ray_origin() + hand.get_ray_direction() * d)
			< 0.001)
	hand.rotate_y(deg_to_rad(-20.0))
	_check("hold: the trigger up lets go", pc.on_trigger(hand, false) and not pc.holding(hand))
	pc._aims.erase(hand)
	hand.free()


## A pane's frame (docs/dev/surfaces-design.md): the title bar over it is a share of its height, Close is at the bar's
## right end, and Show on the big screen is in the stack joined to its right edge.
func _test_bar() -> void:
	var p := PcPane.new()
	root.add_child(p)
	await process_frame
	p.set_width(1.6)
	var h: float = p.height()
	var bar: float = p.frame.bar_height()
	_check("frame: the bar is a share of the picture's height (%.3f of %.3f)" % [bar, h],
			is_equal_approx(bar, h * p.frame.BAR_SHARE))
	p.set_width(0.4)
	_check("frame: a quarter the pane, a quarter the bar", is_equal_approx(p.frame.bar_height(), bar * 0.25))
	h = p.height()
	bar = p.frame.bar_height()
	var from := Vector3(0, 0, 1)
	var hit: Dictionary = p.hit(from + Vector3(0, h / 2.0 + bar / 2.0, 0), Vector3(0, 0, -1))
	_check("frame: the title bar is over the picture (%s)" % hit, hit.get("bar", false) == true)
	hit = p.hit(from + Vector3(p.width / 2.0 - bar, h / 2.0 + bar / 2.0, 0), Vector3(0, 0, -1))
	_check("frame: Close at the bar's right end (%s)" % hit, str(hit.get("button", "")) == "close")
	hit = p.hit(from + Vector3(p.width / 2.0 + bar, h / 2.0 + bar / 2.0, 0), Vector3(0, 0, -1))
	_check("frame: Show on the big screen in the stack beside it (%s)" % hit, str(hit.get("button", "")) == "screen")
	hit = p.hit(from + Vector3(p.width / 2.0 + bar, h / 2.0 - bar, 0), Vector3(0, 0, -1))
	_check("frame: under the stack's one button is nothing (%s)" % hit, hit.is_empty())
	hit = p.hit(from + Vector3(0, h / 2.0 + bar * 1.5, 0), Vector3(0, 0, -1))
	_check("frame: over the bar is nothing", hit.is_empty())
	hit = p.hit(from, Vector3(0, 0, -1))
	_check("frame: the picture is the picture", hit.has("pixel"))
	var rects: Array = p.frame.outline()
	_check("frame: the stack touches the picture's edge", is_equal_approx((rects[1] as Rect2).position.x,
			(rects[0] as Rect2).end.x) and is_equal_approx((rects[1] as Rect2).end.y, (rects[0] as Rect2).end.y))
	p.frame.set_shown(false)
	hit = p.hit(from + Vector3(0, h / 2.0 + bar / 2.0, 0), Vector3(0, 0, -1))
	_check("frame: hidden with the UI, nothing of it can be hit", hit.is_empty() and not p.frame.visible)
	p.free()


func _open_and_wait(s: RefCounted, id: String) -> Node3D:
	var pane: Node3D = pc.open_window(s.client_id, id)
	if pane == null:
		return null
	await _wait(func() -> bool: return pane.video.has_frame(), 15.0)
	return pane


func _pane(id: String) -> Node3D:
	for p: Node3D in pc.panes:
		if p.window_id == id:
			return p
	return null


# --- Input -------------------------------------------------------------------------------------------------------

func _motion(rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.relative = rel
	pc.on_input(m)


func _click(button: MouseButton, down: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = button
	b.pressed = down
	pc.on_input(b)


func _point_cursor_at(world: Vector3) -> void:
	var o: Vector3 = main.camera.global_position
	var d := (world - o).normalized()
	pc.cursor_yaw = atan2(-d.x, -d.z)
	pc.cursor_pitch = asin(d.y)
	_motion(Vector2.ZERO)


func _test_input() -> void:
	var pane := _pane("w:1a2b")
	if pane == null:
		return
	main.camera.global_position = Vector3(0, 1.2, 0)
	main.camera.rotation = Vector3.ZERO
	pc.set_focus(null)
	await _frames(2)
	_motion(Vector2(1, 0))
	_check("mouse: the first motion captures it", pc.mouse_active)
	# A quarter of the way across, a third down: pixel (160, 120) of 640 x 360.
	var target: Vector3 = pane.pixel_to_world(Vector2(160, 120))
	_point_cursor_at(target)
	_check("cursor: over the pane (%s)" % [pc.cursor_target.keys()], pc.cursor_target.get("pane") == pane)
	_check("cursor: on the private layer over a pane", pc.cursor.get_layer_mask_value(VideoScreen.PRIVATE_LAYER)
			and not pc.cursor.get_layer_mask_value(1))
	_click(MOUSE_BUTTON_LEFT, true)
	_click(MOUSE_BUTTON_LEFT, false)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	pc.on_input(wheel)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_A
	k.keycode = KEY_A
	k.pressed = true
	pc.on_input(k)
	k = k.duplicate()
	k.pressed = false
	pc.on_input(k)
	pc.send_text("héllo wörld")
	await _wait(func() -> bool: return not _got("text").is_empty(), 5.0)
	var mice := _got("mouse")
	var down := mice.filter(func(m: Dictionary) -> bool: return m["event"] == "down")
	_check("mouse: a down reached the PC", not down.is_empty())
	if not down.is_empty():
		var m: Dictionary = down.back()
		_check("mouse: at the right pixel (%.1f, %.1f)" % [m["x"], m["y"]], m["id"] == "w:1a2b"
				and absf(float(m["x"]) - 160.0) < 2.0 and absf(float(m["y"]) - 120.0) < 2.0 and m["button"] == "left")
	_check("mouse: up after down", mice.any(func(m: Dictionary) -> bool: return m["event"] == "up"))
	_check("mouse: the wheel, a notch down", mice.any(func(m: Dictionary) -> bool:
			return m["event"] == "wheel" and float(m["dy"]) == -1.0))
	_check("mouse: moves too", mice.any(func(m: Dictionary) -> bool: return m["event"] == "move"))
	var focus := _got("focus")
	_check("focus: sent before the first click", not focus.is_empty() and focus.back()["id"] == "w:1a2b")
	var order: Array[String] = []
	for e in _logged():
		if str(e.get("t", "")) == "got" and str(e["msg"].get("t", "")) in ["focus", "mouse"]:
			if str(e["msg"]["t"]) == "focus" or str(e["msg"].get("event", "")) == "down":
				order.append(str(e["msg"]["t"]))
	_check("focus: before the down (%s)" % [order], order.size() >= 2 and order[order.size() - 2] == "focus")
	var keys := _got("key")
	_check("keys: A down and up", keys.size() >= 2 and keys[-2]["key"] == "A" and bool(keys[-2]["down"])
			and not bool(keys[-1]["down"]))
	var texts := _got("text")
	_check("text: as typed, Unicode", not texts.is_empty() and texts.back()["text"] == "héllo wörld")
	_check("focus: only once while it keeps the focus", _got("focus").size() == 1)
	# Off the pane: the cursor goes to the ordinary layer, nothing is sent.
	pc.cursor_yaw = PI
	_motion(Vector2.ZERO)
	_check("cursor: over nothing, on the ordinary layer", pc.cursor_target.is_empty()
			and pc.cursor.get_layer_mask_value(1) and not pc.cursor.get_layer_mask_value(VideoScreen.PRIVATE_LAYER))


func _test_focus() -> void:
	var a := _pane("w:1a2b")
	var b := _pane("w:264")
	if a == null or b == null:
		return
	pc.set_focus(a)
	await _frames(2)
	# Looking at another pane does nothing (the user, 2026-11-11: gaze never changes where typing goes).
	pc.use_gaze_override = true
	var o: Vector3 = main.camera.global_position
	pc.gaze_override = [o, (b.global_position - o).normalized()]
	await _seconds(0.7)
	_check("focus: looking at another pane leaves the selection", pc.focused == a and main.pointing.selected == a)
	pc.use_gaze_override = false
	pc.gaze_override = []
	pc.set_focus(b)
	_check("focus: selecting is the app's one selection", pc.focused == b and main.pointing.selected == b
			and b.focused and not a.focused)
	await _frames(3)
	var q := _got("quality")
	var qa := q.filter(func(m: Dictionary) -> bool: return int(m["stream"]) == a.stream)
	var qb := q.filter(func(m: Dictionary) -> bool: return int(m["stream"]) == b.stream)
	_check("quality: the pane looked away from asks for a few frames (%s)" % [qa.back() if not qa.is_empty() else {}],
			not qa.is_empty() and int(qa.back()["fps"]) <= 5)
	_check("quality: the pane in focus for the full rate", qb.is_empty() or int(qb.back()["fps"]) >= 30)
	main.pointing.select(null)
	_check("focus: something else selected, no PC window has the keys", pc.focused == null and not b.focused)
	pc.set_focus(b)


func _test_big_screen() -> void:
	var pane := _pane("w:1a2b")
	if pane == null:
		return
	pc.show_on_screen(pane, true)
	await _frames(10)
	var src: Object = main.player.source
	_check("big screen: the window is the screen's source", src != null and src.get_kind() == "pc"
			and PcWindowSource.is_pc_path(main.current_path))
	_check("big screen: the pane's picture hides, its bar stays", not pane.get_node("Picture").visible and pane.visible)
	_check("big screen: the screen is private", main.screen.get_node("Flat").get_layer_mask_value(VideoScreen.PRIVATE_LAYER))
	_check("big screen: the screen has the planes", src != null and src.get_plane_texture(0) != null)
	_check("big screen: not the next start's file", str(main.settings.get_value("player", "last_file", "")) == ""
			or not PcWindowSource.is_pc_path(str(main.settings.get_value("player", "last_file", ""))))
	if _render:
		main.camera.global_position = Vector3(0, 1.2, 0)
		main.camera.look_at(main.screen.global_position, Vector3.UP)
		await _frames(6)
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OUT.path_join("big_screen.png"))
		_picture_check(img, "the big screen")
	pc.show_on_screen(pane, false)
	await _frames(4)
	_check("back: the pane shows again", pane.get_node("Picture").visible and not pane.on_screen
			and pc.screen_pane == null)
	_check("back: the screen let go", main.player.source == null or main.player.source.get_kind() != "pc")
	# Another file over a window on the screen gives the window back too.
	pc.show_on_screen(pane, true)
	await _frames(4)
	main.open_path("stub://bars")
	await _frames(6)
	_check("another file: the window back in its pane", not pane.on_screen and pc.screen_pane == null)


func _test_restart_and_config() -> void:
	if not _render:
		return
	var s: RefCounted = pc.sessions()[0]
	var e := await _open_and_wait(s, "w:e0d")
	if e == null:
		_check("short stream: a pane", false)
		return
	var first: int = e.stream
	await _wait(func() -> bool: return e.stream != first, 8.0)
	_check("a stream that ended: asked for again (%d -> %d)" % [first, e.stream], e.stream > first)
	_check("a stream that ended: the old one closed", _got("close").any(func(m: Dictionary) -> bool:
			return int(m["stream"]) == first))
	await _wait(func() -> bool: return e.video.has_frame(), 8.0)
	_check("a stream that ended: pictures again", e.video.has_frame())
	pc.close_pane(e)
	var c := await _open_and_wait(s, "w:c0ffee")
	if c == null:
		_check("config change: a pane", false)
		return
	_check("config change: first 640 x 360", c.video.size() == Vector2i(640, 360))
	await _wait(func() -> bool: return c.video.size() == Vector2i(480, 270), 8.0)
	_check("config change: then 480 x 270 (%s)" % [c.video.size()], c.video.size() == Vector2i(480, 270))
	_check("config change: the pane takes the new shape", c.pixels == Vector2i(480, 270))
	_check("config change: still showing", c.video.has_frame() and int(c.video.stats().get("opened", 0)) >= 2)
	await _frames(10)
	var shot := await _pane_shot(c, "resized.png")
	_picture_check(shot, "the resized pane")
	pc.close_pane(c)
	_check("close: the pane goes", not pc.panes.has(c))


## The commands an assistant reaches (docs/dev/assistant-coverage/room-system.md), as the dev link runs them.
func _test_commands() -> void:
	var r: Dictionary = await DevCommands.execute("pc_list", {}, true)
	_check("pc_list: the windows, no titles", r["ok"] and (r["result"] as Array).size() == 5
			and not JSON.stringify(r["result"]).contains("Test pattern"))
	r = await DevCommands.execute("pc_open", {"id": "m:0"}, true)
	var m := _pane("m:0")
	_check("pc_open: a pane", r["ok"] and m != null)
	if m == null:
		return
	r = await DevCommands.execute("pc_pane_size", {"id": "m:0", "width": 1.5}, true)
	_check("pc_pane_size: 1.5 m", r["ok"] and is_equal_approx(m.width, 1.5))
	(r["call"] as DevCommands.Call).undo.call()
	_check("pc_pane_size: undo", not is_equal_approx(m.width, 1.5))
	r = await DevCommands.execute("pc_screen", {"id": "m:0", "on": true}, true)
	await _frames(4)
	_check("pc_screen: on the big screen", r["ok"] and m.on_screen and PcWindowSource.is_pc_path(main.current_path))
	(r["call"] as DevCommands.Call).undo.call()
	await _frames(4)
	_check("pc_screen: undo, back in its pane", not m.on_screen)
	r = await DevCommands.execute("pc_status", {}, true)
	_check("pc_status: the pane listed", r["ok"] and (r["result"]["panes"] as Array).any(func(p: Dictionary) -> bool:
			return p["window"] == "m:0"))
	r = await DevCommands.execute("pc_close", {"id": "m:0"}, true)
	_check("pc_close: the pane goes", r["ok"] and _pane("m:0") == null)
	(r["call"] as DevCommands.Call).undo.call()
	_check("pc_close: undo opens it again", _pane("m:0") != null)
	r = await DevCommands.execute("pc_open", {"id": "w:nothere"}, true)
	_check("pc_open: a window no PC has is refused", not r["ok"])
	if _pane("m:0") != null:
		pc.close_pane(_pane("m:0"))


func _test_sound() -> void:
	if pc.panes.is_empty():
		return
	_check("sound: asked for while a pane is open", _got("sound").any(func(m: Dictionary) -> bool: return bool(m["on"])))
	await _wait(func() -> bool: return pc.sound != null and int(pc.sound.pushed) > 4800, 8.0)
	_check("sound: AAC decoded and played at its time (%s)" % [pc.sound.status() if pc.sound != null else {}],
			pc.sound != null and int(pc.sound.pushed) > 4800)
	pc.close_all()
	await _frames(3)
	_check("close all: no panes, the sound asked off", pc.panes.is_empty() and pc.sound == null
			and _got("sound").back()["on"] == false)


func _test_reconnect() -> void:
	if pc.service == null or not FileAccess.file_exists(_token_file):
		return
	for pid in _procs:
		OS.kill(pid)
	_procs.clear()
	await _wait(func() -> bool: return not pc.connected(), 20.0)
	_check("the PC went: no session", not pc.connected())
	_fake(["--token-file", _token_file, "--name", "FAKE-PC"], false)
	await _wait(func() -> bool: return pc.connected(), 20.0)
	_check("the paired PC again with its token: connected", pc.connected() and pc.service.paired().size() == 1)
	var id: String = pc.service.paired()[0]["id"]
	pc.service.forget(id)
	await _frames(3)
	_check("forget: the PC goes and its token stops", not pc.connected() and pc.service.paired().is_empty())
	pc.set_enabled(false)
	_check("off: no service", pc.service == null)


# --- Helpers -----------------------------------------------------------------------------------------------------

func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _wait(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())
