extends Node3D

## PC windows in the headset (docs/pc-windows.md, decision D31): the feature (main.features.pc_windows). It runs the
## service while System, PC windows is on (pc_service.gd), and owns what the viewer sees and uses:
##   panes      a window opened from the Files tab (or `pc_open`) becomes a pane in front of the viewer (pc_pane.gd),
##              its picture decoded by pc_video.gd; several at once. Squeeze and hold on a pane to move it (it follows
##              the laser at the distance it was taken), the stick up / down while holding makes it bigger or smaller.
##              Its bar: Close, Show on the big screen (the window becomes the big screen's source, a film's place
##              and the room's presentation: pc_window_source.gd) and back.
##   focus      the pane looked at for DWELL seconds (eye gaze, else the head) is highlighted and takes the keyboard
##              and the voice. It and the big screen ask the PC for the full rate (FULL_FPS, FULL_KBPS), the others
##              for a few frames a second. The PC window comes to the front (`focus`) only before its first click or
##              key after it gained the focus.
##   cursor     a mouse paired with the headset: once a PC is connected and the mouse moves, the mouse is captured
##              and its motion turns a cursor round the head (pc_cursor.gd). Over a pane it is that window's mouse
##              (`mouse` move, down, up, wheel at the pane's pixel); over the menu it clicks the menu; over nothing
##              it does nothing. The controller's laser and trigger are a mouse on a pane too.
##   keyboard   while a pane has the focus (and the menu isn't taking the text), each key goes to its window as
##              Godot's name for the physical key, down and up (shortcuts work).
##   text       the talk button with a pane in focus types what was said into it (`text`); the Files tab's PC place
##              has a line and the on-pane keyboard for the same.
##   sound      the PC's sound while a pane is open (pc_sound.gd), from the big screen when a window is on it.
## Privacy: the panes, and the cursor over them, are on the private render layer; titles and thumbnails never reach a
## log or an assistant (the commands give ids, kinds, the program's name and sizes).
## Settings: [pc_windows] enabled, port, delay (seconds, 0.15).
## Commands: pc_status, pc_list (read); pc_open, pc_close, pc_screen, pc_pane_size (control).

signal changed

const PcService := preload("res://scripts/pc/pc_service.gd")
const PcSession := preload("res://scripts/pc/pc_session.gd")
const PcPane := preload("res://scripts/pc/pc_pane.gd")
const PcVideo := preload("res://scripts/pc/pc_video.gd")
const PcSound := preload("res://scripts/pc/pc_sound.gd")
const PcCursor := preload("res://scripts/pc/pc_cursor.gd")
const PcProtocol := preload("res://scripts/pc/pc_protocol.gd")
const PcWindowSource := preload("res://scripts/pc/pc_window_source.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const PushToTalk := preload("res://scripts/dev/push_to_talk.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")

const SECTION := "pc_windows"
const DWELL := 0.5
const FULL_FPS := 60
const FULL_KBPS := 20000
const LOW_FPS := 5
const LOW_KBPS := 1500
## The most a stream should be (the PC scales a larger window down).
const MAX_SIZE := Vector2i(3840, 2160)
const PANE_DISTANCE := 1.0
## The cursor's sphere round the head where it is over nothing (metres), and the mouse's degrees per count.
const CURSOR_RADIUS := 2.0
const MOUSE_DEG := 0.05
const STICK_DEAD := 0.2
const RESIZE_RATE := 0.8
## A stream is asked for again at most this often (a decoder that lost its place, a stream that ended).
const RESTART_SECONDS := 2.0

var main: Node3D
var service: PcService
var panes: Array[PcPane] = []
var focused: PcPane
var cursor: PcCursor
var sound: PcSound
## Tests: the service's port, files and address ({port, bind_address, clients_path, tls_key_path, tls_cert_path}),
## set before it starts.
var service_overrides := {}
## Tests: run as in the headset without an XR session; look where gaze_override says ([origin, dir], [] for none).
var test_xr := false
var use_gaze_override := false
var gaze_override: Array = []
## The mouse is captured and moves the cursor.
var mouse_active := false
## The cursor's direction from the head, world yaw and pitch (radians).
var cursor_yaw := 0.0
var cursor_pitch := 0.0
## What the cursor is over: {pane, pixel} or {pane, button} or {screen: true, pixel} or {menu: true} or {}.
var cursor_target := {}
## The pane on the big screen, or null.
var screen_pane: PcPane
var _dwell_pane: PcPane
var _dwell_since := 0.0
## pane -> its window was told `focus` since it gained the focus.
var _focus_sent := {}
## Protocol button names held down -> the pane they went to.
var _buttons_down := {}
## hand -> {pane, distance} while the squeeze holds a pane.
var _holds := {}
## hand -> the pane its laser points at ({pane, pixel?, button?, distance}).
var _aims := {}
var _lit := {}
var _trigger_on := {}
var _last_move := {}
var _restart_at := {}
var _recorder: Node
var _talking := false
var _voice_jobs := {}
## Sent to the PCs by the tests' count: text messages and their characters (never what they said).
var texts_sent := 0


func _ready() -> void:
	PcWindowSource.find_video = _find_video
	PcWindowSource.released = _on_screen_released
	cursor = PcCursor.new()
	cursor.name = "Cursor"
	add_child(cursor)
	if enabled():
		_start_service()
	register_commands()
	Transcriber.instance().connect("done", _on_transcribed)


func _exit_tree() -> void:
	var t: Object = Transcriber.instance()
	if t.is_connected("done", _on_transcribed):
		t.disconnect("done", _on_transcribed)
	if mouse_active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _settings() -> RefCounted:
	return main.settings if main != null else null


# --- The service ---------------------------------------------------------------------------------------------------

func enabled() -> bool:
	return _settings() != null and bool(_settings().get_value(SECTION, "enabled", false))


## System, PC windows: on or off (remembered).
func set_enabled(on: bool) -> void:
	if _settings() != null:
		_settings().set_value(SECTION, "enabled", true if on else null)
	if on and service == null:
		_start_service()
	elif not on and service != null:
		close_all()
		service.queue_free()
		service = null
		print("PC windows: off")
	changed.emit()


func _start_service() -> void:
	service = PcService.new()
	service.name = "Service"
	service.settings = _settings()
	for k: String in service_overrides:
		service.set(k, service_overrides[k])
	add_child(service)
	service.windows_changed.connect(_on_windows_changed)
	service.sessions_changed.connect(_on_sessions_changed)
	service.status_changed.connect(func() -> void: changed.emit())
	service.pairing_changed.connect(func() -> void: changed.emit())


func sessions() -> Array:
	return service.sessions() if service != null else []


func connected() -> bool:
	return not sessions().is_empty()


func _session(client_id: String) -> PcSession:
	return service.session(client_id) if service != null else null


func _on_windows_changed() -> void:
	# A window the PC closed takes its pane with it.
	for pane: PcPane in panes.duplicate():
		var s := _session(pane.client_id)
		if s != null and s.window(pane.window_id).is_empty() and not s.windows.is_empty():
			close_pane(pane)
	changed.emit()


func _on_sessions_changed() -> void:
	for pane: PcPane in panes.duplicate():
		if _session(pane.client_id) == null:
			close_pane(pane)
	for s: PcSession in sessions():
		if not s.window_closed.is_connected(_on_window_closed):
			s.window_closed.connect(_on_window_closed.bind(s))
		if not s.cursor_changed.is_connected(_on_cursor_changed):
			s.cursor_changed.connect(_on_cursor_changed.bind(s))
	if not connected():
		_release_mouse()
	_update_sound()
	changed.emit()


func _on_window_closed(id: String, s: PcSession) -> void:
	for pane: PcPane in panes.duplicate():
		if pane.client_id == s.client_id and pane.window_id == id:
			close_pane(pane)


func _on_cursor_changed(id: String, shape: String, s: PcSession) -> void:
	var t: PcPane = cursor_target.get("pane")
	if t != null and t.client_id == s.client_id and t.window_id == id:
		cursor.set_shape(shape)


# --- Panes ---------------------------------------------------------------------------------------------------------

func pane_for(client_id: String, window_id: String) -> PcPane:
	for p: PcPane in panes:
		if p.client_id == client_id and p.window_id == window_id:
			return p
	return null


func _head() -> Node3D:
	return main.camera if main != null else null


## Opens a window of a connected PC as a pane in front of the viewer (or brings its pane back into focus). Null when
## the PC or the window isn't there.
func open_window(client_id: String, window_id: String) -> PcPane:
	var s := _session(client_id)
	if s == null or s.window(window_id).is_empty():
		return null
	var existing := pane_for(client_id, window_id)
	if existing != null:
		set_focus(existing)
		return existing
	var w := s.window(window_id)
	var pane := PcPane.new()
	pane.name = "Pane%d" % (panes.size() + 1)
	pane.client_id = client_id
	pane.window_id = window_id
	pane.title = str(w.get("title", ""))
	if int(w.get("w", 0)) > 0 and int(w.get("h", 0)) > 0:
		var scale := minf(1.0, minf(float(MAX_SIZE.x) / float(w["w"]), float(MAX_SIZE.y) / float(w["h"])))
		pane.pixels = Vector2i(roundi(float(w["w"]) * scale), roundi(float(w["h"]) * scale))
	add_child(pane)
	_label(pane)
	pane.set_width(PcPane.natural_width(pane.pixels.x, PANE_DISTANCE))
	_place_new(pane)
	pane.attach(PcVideo.new())
	pane.stream = s.open_stream(window_id, MAX_SIZE, FULL_FPS, FULL_KBPS)
	panes.append(pane)
	set_focus(pane)
	_update_sound()
	print("PC windows: a pane opened (%d open)" % panes.size())
	changed.emit()
	return pane


func _label(pane: PcPane) -> void:
	pane.set_labels(tr("Close"), tr("Back to a pane") if pane.on_screen else tr("Show on the big screen"))


## In front of the head; with panes open already, turned round the head to one side or the other by about a pane's
## width, so the new one doesn't cover them.
func _place_new(pane: PcPane) -> void:
	var head := _head()
	var origin := head.global_position if head != null else Vector3(0, 1.2, 0)
	var fwd := -head.global_transform.basis.z if head != null else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var n := panes.size()
	var step := 2.0 * atan(pane.width / (2.0 * PANE_DISTANCE)) + deg_to_rad(4.0)
	var turn := 0.0 if n == 0 else step * ceilf(n / 2.0) * (-1.0 if n % 2 == 1 else 1.0)
	pane.global_position = origin + fwd.rotated(Vector3.UP, turn) * PANE_DISTANCE
	pane.face(origin)


func close_pane(pane: PcPane) -> void:
	if not panes.has(pane):
		return
	if pane == screen_pane:
		screen_pane = null
		if main != null and PcWindowSource.is_pc_path(str(main.current_path)):
			main.close_media()
	var s := _session(pane.client_id)
	if s != null:
		s.close_stream(pane.stream)
	for b: String in _buttons_down.keys():
		if _buttons_down[b] == pane:
			_buttons_down.erase(b)
	if pane.video != null:
		pane.video.close()
	panes.erase(pane)
	_focus_sent.erase(pane)
	if focused == pane:
		focused = null
	if _dwell_pane == pane:
		_dwell_pane = null
	for h: Object in _holds.keys():
		if _holds[h]["pane"] == pane:
			_holds.erase(h)
	for h: Object in _aims.keys():
		if _aims[h].get("pane") == pane:
			_aims.erase(h)
	if cursor_target.get("pane") == pane:
		cursor_target = {}
	pane.close()
	_update_sound()
	changed.emit()


func close_all() -> void:
	for pane: PcPane in panes.duplicate():
		close_pane(pane)


func set_focus(pane: PcPane) -> void:
	if pane == focused:
		return
	if focused != null:
		focused.set_focused(false)
	focused = pane
	if pane != null:
		pane.set_focused(true)
		_focus_sent[pane] = false
	_update_quality()
	changed.emit()


## The window's `focus` before its first click or key since it gained the focus in the headset.
func _ensure_pc_focus(pane: PcPane) -> void:
	if bool(_focus_sent.get(pane, false)):
		return
	var s := _session(pane.client_id)
	if s == null:
		return
	s.send({"t": "focus", "id": pane.window_id})
	_focus_sent[pane] = true


func _update_quality() -> void:
	for pane: PcPane in panes:
		var s := _session(pane.client_id)
		if s == null:
			continue
		var full := pane == focused or pane == screen_pane
		s.set_quality(pane.stream, FULL_FPS if full else LOW_FPS, FULL_KBPS if full else LOW_KBPS)


## Asks for the pane's stream again from a key frame: the old one closes, a new number opens.
func _restart_stream(pane: PcPane, why: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_restart_at.get(pane, 0.0)):
		return
	_restart_at[pane] = now + RESTART_SECONDS
	var s := _session(pane.client_id)
	if s == null:
		return
	print("PC windows: a stream starts again (%s)" % why)
	s.close_stream(pane.stream)
	pane.video.reset()
	var full := pane == focused or pane == screen_pane
	pane.stream = s.open_stream(pane.window_id, MAX_SIZE, FULL_FPS if full else LOW_FPS,
			FULL_KBPS if full else LOW_KBPS)


# --- The big screen ------------------------------------------------------------------------------------------------

## The window on the big screen (a film's place), or back to its pane.
func show_on_screen(pane: PcPane, on: bool) -> void:
	if on == pane.on_screen and (not on or screen_pane == pane):
		return
	if on:
		if screen_pane != null and screen_pane != pane:
			screen_pane.set_on_screen(false)
			_label(screen_pane)
		screen_pane = pane
		pane.set_on_screen(true)
		_label(pane)
		main.open_path(PcWindowSource.path_for(pane.client_id, pane.window_id))
	else:
		if PcWindowSource.is_pc_path(str(main.current_path)):
			main.close_media()
		_back_to_pane(pane)
	_update_quality()
	_update_sound()
	changed.emit()


func _back_to_pane(pane: PcPane) -> void:
	if pane == null:
		return
	pane.set_on_screen(false)
	_label(pane)
	if screen_pane == pane:
		screen_pane = null


func _find_video(path: String) -> RefCounted:
	for pane: PcPane in panes:
		if PcWindowSource.path_for(pane.client_id, pane.window_id) == path:
			return pane.video
	return null


## The screen let go of a window (another file opened, Stop): back to its pane.
func _on_screen_released(path: String) -> void:
	for pane: PcPane in panes:
		if PcWindowSource.path_for(pane.client_id, pane.window_id) == path and pane.on_screen:
			_back_to_pane(pane)
			_update_quality()
			_update_sound()
			changed.emit()


# --- Sound ---------------------------------------------------------------------------------------------------------

## The PC's sound while one of its windows is open; one PC's at a time (the focused pane's, else the first).
func _update_sound() -> void:
	var want: PcSession = null
	var lead: PcPane = focused if focused != null else (panes[0] if not panes.is_empty() else null)
	if lead != null:
		want = _session(lead.client_id)
	for s: PcSession in sessions():
		s.set_sound(s == want)
	if want == null:
		if sound != null:
			sound.queue_free()
			sound = null
		return
	if sound == null:
		sound = PcSound.new()
		sound.name = "Sound"
		add_child(sound)
	sound.clock = want.clock
	sound.head = _head()
	sound.at_screen = main.screen if screen_pane != null else null


# --- Every frame ---------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)


## One frame (tests call it).
func step(delta: float) -> void:
	if service == null:
		return
	for pane: PcPane in panes.duplicate():
		var s := _session(pane.client_id)
		if s == null:
			continue
		var reader: RefCounted = s.reader(pane.stream)
		if reader != null:
			var src: Object = reader.take_source()
			if src != null:
				pane.video.use_source(src)
		var clock := s.clock.now()
		if clock >= 0.0:
			pane.video.update(delta, clock)
		if reader != null and (pane.video.wants_key_frame() or reader.ended()):
			_restart_stream(pane, "the decoder lost its place" if not reader.ended() else "the stream ended")
	if sound != null:
		var s := _session(_sound_client())
		sound.source = s.reader(0) if s != null else null
	_update_gaze()
	_update_hands(delta)
	_update_cursor()


func _sound_client() -> String:
	for s: PcSession in sessions():
		if s.sound_on:
			return s.client_id
	return ""


## Where the viewer looks: the calibrated eye gaze, else the head (window_pointer.gd's), or the tests'.
func gaze_ray() -> Array:
	if use_gaze_override:
		return gaze_override
	if main != null and main.get("window_pointer") != null:
		return main.window_pointer.gaze_ray()
	return []


## The nearest pane a ray meets: {pane, pixel or button, distance}, or {}.
func pane_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for pane: PcPane in panes:
		var h := pane.hit(origin, dir)
		if h.is_empty():
			continue
		if best.is_empty() or float(h["distance"]) < float(best["distance"]):
			h["pane"] = pane
			best = h
	return best


## The big screen, while a window is on it: {screen: true, pixel, distance}, or {}.
func screen_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	if screen_pane == null or main.get("window_pointer") == null:
		return {}
	var h: Dictionary = main.window_pointer.ray_to_uv(origin, dir)
	if h.is_empty():
		return {}
	var uv: Vector2 = h["uv"]
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return {}
	return {"screen": true, "pane": screen_pane, "pixel": uv * Vector2(screen_pane.pixels),
			"distance": h["distance"]}


func _update_gaze() -> void:
	var g := gaze_ray()
	var looked: PcPane = null
	if not g.is_empty():
		var h := pane_hit(g[0], g[1])
		if h.is_empty():
			h = screen_hit(g[0], g[1])
		looked = h.get("pane")
	var now := Time.get_ticks_msec() / 1000.0
	if looked != _dwell_pane:
		_dwell_pane = looked
		_dwell_since = now
	elif looked != null and looked != focused and now - _dwell_since >= DWELL:
		set_focus(looked)


# --- Mouse and keyboard --------------------------------------------------------------------------------------------

## main.gd's _unhandled_input asks this first (after the menu's text fields). True when used.
func on_input(event: InputEvent) -> bool:
	if service == null or not connected():
		return false
	if event is InputEventMouseMotion:
		if not (main.use_xr or test_xr):
			return false
		if not mouse_active:
			_capture_mouse()
		var m := event as InputEventMouseMotion
		cursor_yaw -= deg_to_rad(m.relative.x * MOUSE_DEG)
		cursor_pitch = clampf(cursor_pitch - deg_to_rad(m.relative.y * MOUSE_DEG), -1.4, 1.4)
		_update_cursor()
		if cursor_target.has("menu") and main.ui != null:
			main.ui.on_mouse(event, cursor_ray())
		return true
	if event is InputEventMouseButton:
		if not mouse_active:
			return false
		return _mouse_button(event as InputEventMouseButton)
	if event is InputEventKey:
		return _key(event as InputEventKey)
	return false


func _capture_mouse() -> void:
	mouse_active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var head := _head()
	if head != null:
		var f := -head.global_transform.basis.z
		cursor_yaw = atan2(-f.x, -f.z)
		cursor_pitch = asin(clampf(f.y, -1.0, 1.0))


func _release_mouse() -> void:
	if not mouse_active:
		return
	mouse_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cursor.visible = false
	cursor_target = {}


## The cursor's ray: from the head along the cursor's direction.
func cursor_ray() -> Array:
	var head := _head()
	var origin := head.global_position if head != null else Vector3(0, 1.2, 0)
	var dir := Vector3(-sin(cursor_yaw) * cos(cursor_pitch), sin(cursor_pitch), -cos(cursor_yaw) * cos(cursor_pitch))
	return [origin, dir.normalized()]


func _update_cursor() -> void:
	if not mouse_active:
		return
	var r := cursor_ray()
	var h := pane_hit(r[0], r[1])
	if h.is_empty():
		h = screen_hit(r[0], r[1])
	var point: Vector3 = r[0] + r[1] * CURSOR_RADIUS
	if h.is_empty() and main.ui != null and main.ui.get("panel") != null:
		var m: Dictionary = main.ui.panel.ray_hit(r[0], r[1])
		if not m.is_empty():
			h = {"menu": true, "distance": float(m.get("distance", CURSOR_RADIUS))}
	if h.has("distance"):
		point = r[0] + r[1] * (float(h["distance"]) - 0.003)
	var old_pane: PcPane = cursor_target.get("pane")
	cursor_target = h
	var pane: PcPane = h.get("pane")
	if pane != old_pane:
		var s := _session(pane.client_id) if pane != null else null
		cursor.set_shape(str(s.cursors.get(pane.window_id, "arrow")) if s != null else "arrow")
	cursor.place(point, r[0], pane != null)
	if pane != null and h.has("pixel"):
		_send_move(pane, h["pixel"], "cursor")


func _send_move(pane: PcPane, px: Vector2, who: String) -> void:
	var key := str(pane.get_instance_id()) + who
	var last: Variant = _last_move.get(key)
	if last != null and (last as Vector2).distance_to(px) < 0.5:
		return
	_last_move[key] = px
	var s := _session(pane.client_id)
	if s != null:
		s.send({"t": "mouse", "id": pane.window_id, "event": "move", "x": snappedf(px.x, 0.01),
				"y": snappedf(px.y, 0.01)})


func _mouse_button(b: InputEventMouseButton) -> bool:
	var pane: PcPane = cursor_target.get("pane")
	if cursor_target.has("menu"):
		return main.ui.on_mouse(b, cursor_ray()) if main.ui != null else false
	if b.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT,
			MOUSE_BUTTON_WHEEL_RIGHT]:
		if pane == null or not b.pressed or not cursor_target.has("pixel"):
			return pane != null
		var f := b.factor if b.factor > 0.0 else 1.0
		var dx := (f if b.button_index == MOUSE_BUTTON_WHEEL_RIGHT else (-f if b.button_index == MOUSE_BUTTON_WHEEL_LEFT
				else 0.0))
		var dy := (f if b.button_index == MOUSE_BUTTON_WHEEL_UP else (-f if b.button_index == MOUSE_BUTTON_WHEEL_DOWN
				else 0.0))
		_wheel(pane, cursor_target["pixel"], dx, dy)
		return true
	var name := str(PcProtocol.BUTTONS.get(b.button_index, ""))
	if name == "":
		return pane != null
	if not b.pressed and _buttons_down.has(name):
		# Up goes where the down went, wherever the cursor is now.
		var down_pane: PcPane = _buttons_down[name]
		_buttons_down.erase(name)
		var px: Vector2 = cursor_target.get("pixel", Vector2.ZERO) if pane == down_pane else Vector2.ZERO
		_button(down_pane, px, name, false)
		return true
	if pane == null:
		return false
	if cursor_target.has("button"):
		if b.pressed and name == "left":
			press_pane_button(pane, str(cursor_target["button"]))
		return true
	if b.pressed and cursor_target.has("pixel"):
		set_focus(pane)
		_buttons_down[name] = pane
		_button(pane, cursor_target["pixel"], name, true)
	return true


func _button(pane: PcPane, px: Vector2, name: String, down: bool) -> void:
	var s := _session(pane.client_id)
	if s == null:
		return
	if down:
		_ensure_pc_focus(pane)
	s.send({"t": "mouse", "id": pane.window_id, "event": "down" if down else "up", "x": snappedf(px.x, 0.01),
			"y": snappedf(px.y, 0.01), "button": name})


func _wheel(pane: PcPane, px: Vector2, dx: float, dy: float) -> void:
	var s := _session(pane.client_id)
	if s != null:
		s.send({"t": "mouse", "id": pane.window_id, "event": "wheel", "x": snappedf(px.x, 0.01),
				"y": snappedf(px.y, 0.01), "dx": dx, "dy": dy})


func _key(k: InputEventKey) -> bool:
	if focused == null:
		return false
	var s := _session(focused.client_id)
	if s == null:
		return false
	var name := PcProtocol.key_name(k)
	if name == "":
		return false
	if k.pressed:
		_ensure_pc_focus(focused)
	s.send({"t": "key", "id": focused.window_id, "key": name, "down": k.pressed})
	return true


## Text typed as it is (voice, the on-pane keyboard) into the focused pane's window. False with no pane in focus.
func send_text(text: String) -> bool:
	if focused == null or text == "":
		return false
	var s := _session(focused.client_id)
	if s == null:
		return false
	_ensure_pc_focus(focused)
	s.send({"t": "text", "id": focused.window_id, "text": text})
	texts_sent += 1
	return true


## A pane's bar: "close" or "screen".
func press_pane_button(pane: PcPane, button: String) -> void:
	match button:
		"close":
			close_pane(pane)
		"screen":
			show_on_screen(pane, not pane.on_screen)


# --- Controllers ---------------------------------------------------------------------------------------------------

## The laser is free for the panes on this hand (nothing else has it).
func _hand_free(hand: Node) -> bool:
	var ui: Node = main.ui
	if ui != null and ui.has_method("laser_in_use") and ui.laser_in_use(hand):
		return false
	var grab: Node = main.features.get("grab") if main.get("features") != null else null
	if grab != null and (grab.owns_laser(hand) or grab.holding(hand) != ""):
		return false
	return true


func _update_hands(delta: float) -> void:
	if main == null or not (main.use_xr or test_xr):
		return
	for hand: Node in main.hands:
		if _holds.has(hand):
			_hold(hand, delta)
			continue
		var aim := {}
		if (hand.get_is_active() or test_xr) and _hand_free(hand) and not panes.is_empty():
			var o: Vector3 = hand.get_ray_origin()
			var d: Vector3 = hand.get_ray_direction()
			aim = pane_hit(o, d)
		if aim.is_empty():
			_aims.erase(hand)
		else:
			_aims[hand] = aim
			var pane: PcPane = aim["pane"]
			pane.hover_button = str(aim.get("button", ""))
			if aim.has("pixel"):
				_send_move(pane, aim["pixel"], "hand%d" % hand.get_instance_id())
		var want := not aim.is_empty()
		if want:
			hand.set_laser(true, float(aim["distance"]), true)
		elif bool(_lit.get(hand, false)):
			var ui: Node = main.ui
			if ui == null or not ui.has_method("laser_in_use") or not ui.laser_in_use(hand):
				hand.set_laser(false)
		_lit[hand] = want
	for pane: PcPane in panes:
		var hovered := false
		for h: Object in _aims:
			hovered = hovered or (_aims[h]["pane"] == pane and _aims[h].has("button"))
		if not hovered:
			pane.hover_button = ""


## The trigger on a pane: the left button at the laser's pixel, or the bar's button. True when used.
func on_trigger(hand: Node, pressed: bool) -> bool:
	if not pressed and _trigger_on.has(hand):
		var pane: PcPane = _trigger_on[hand]
		_trigger_on.erase(hand)
		if panes.has(pane):
			var a: Dictionary = _aims.get(hand, {})
			_button(pane, a.get("pixel", Vector2.ZERO) if a.get("pane") == pane else Vector2.ZERO, "left", false)
		return true
	var aim: Dictionary = _aims.get(hand, {})
	if aim.is_empty():
		return false
	if not pressed:
		return true
	var pane: PcPane = aim["pane"]
	if aim.has("button"):
		press_pane_button(pane, str(aim["button"]))
	elif aim.has("pixel"):
		set_focus(pane)
		_trigger_on[hand] = pane
		_button(pane, aim["pixel"], "left", true)
	if hand.has_method("pulse"):
		hand.pulse()
	return true


## The squeeze on a pane takes hold of it; letting go puts it there. True when used.
func on_grip(hand: Node, pressed: bool) -> bool:
	if not pressed:
		if _holds.has(hand):
			_holds.erase(hand)
			changed.emit()
			return true
		return false
	var aim: Dictionary = _aims.get(hand, {})
	if aim.is_empty():
		return false
	var pane: PcPane = aim["pane"]
	_holds[hand] = {"pane": pane, "distance": float(aim["distance"])}
	set_focus(pane)
	return true


## The stick while holding a pane: up bigger, down smaller. True when used.
func on_stick(hand: Node, stick: Vector2, delta: float) -> bool:
	if not _holds.has(hand):
		return false
	if absf(stick.y) > STICK_DEAD:
		var pane: PcPane = _holds[hand]["pane"]
		pane.set_width(pane.width * (1.0 + stick.y * RESIZE_RATE * delta))
	return true


func _hold(hand: Node, _delta: float) -> void:
	var hold: Dictionary = _holds[hand]
	var pane: PcPane = hold["pane"]
	if not panes.has(pane):
		_holds.erase(hand)
		return
	var o: Vector3 = hand.get_ray_origin()
	var d: Vector3 = hand.get_ray_direction()
	pane.global_position = o + d * float(hold["distance"])
	var head := _head()
	if head != null:
		pane.face(head.global_position)
	hand.set_laser(true, float(hold["distance"]), true)


func holding(hand: Node) -> bool:
	return _holds.has(hand)


func owns_laser(hand: Node) -> bool:
	return _holds.has(hand) or _aims.has(hand)


# --- Voice ---------------------------------------------------------------------------------------------------------

## The talk button types into the focused pane while one has the focus and the menu is hidden.
func wants_talk() -> bool:
	return focused != null and connected() and not bool(main.get("menu_shown"))


func on_talk(held: bool) -> bool:
	if held:
		if not wants_talk():
			return false
		if _recorder == null:
			_recorder = PushToTalk.new()
			_recorder.name = "PcPushToTalk"
			_recorder.set("register_command", false)
			_recorder.set("key_enabled", false)
			_recorder.set("link", self)
			add_child(_recorder)
		_talking = bool(_recorder.call("begin"))
		return true
	if not _talking:
		return false
	_talking = false
	_recorder.call("end")
	return true


## The recorder's link (push_to_talk.gd): the clip on release goes to the headset's speech to text, nowhere else.
func send_event(event_name: String, data: Variant = {}) -> void:
	if event_name != "voice_clip":
		return
	var wav := Marshalls.base64_to_raw(str((data as Dictionary).get("wav_b64", ""))) if data is Dictionary \
			else PackedByteArray()
	if wav.size() <= 44 or not Transcriber.available():
		return
	var id := Transcriber.transcribe(wav.slice(44), true)
	if id >= 0:
		_voice_jobs[id] = true


func _on_transcribed(id: int, text: String, final: bool) -> void:
	if not _voice_jobs.has(id) or not final:
		return
	_voice_jobs.erase(id)
	var said := text.strip_edges()
	if said != "":
		send_text(said)


# --- State and commands --------------------------------------------------------------------------------------------

## For the assistant and the dev link: no titles, no thumbnails, no PC names (docs/pc-windows.md, privacy).
func status() -> Dictionary:
	var pcs: Array = []
	for s: PcSession in sessions():
		pcs.append({"pc": s.client_id, "windows": s.windows.size(), "sound": s.sound_on})
	var open: Array = []
	for p: PcPane in panes:
		var st := p.status()
		st["pc"] = p.client_id
		st["decode"] = p.video.decode_path() if p.video != null else ""
		open.append(st)
	return {"on": service != null, "listening": service != null and service.is_listening(),
			"pairing": service != null and service.pairing(), "paired": service.paired().size() if service != null else 0,
			"connected": pcs, "panes": open, "focused": focused.window_id if focused != null else "",
			"big_screen": screen_pane.window_id if screen_pane != null else "", "mouse": mouse_active}


## The windows of the connected PCs without their titles: [{pc, id, kind, app, w, h}].
func list_windows(pc := "") -> Array:
	var out: Array = []
	for s: PcSession in sessions():
		if pc != "" and s.client_id != pc:
			continue
		for w: Dictionary in s.windows:
			out.append({"pc": s.client_id, "id": w["id"], "kind": w["kind"], "app": w["app"], "w": w["w"], "h": w["h"],
					"open": pane_for(s.client_id, w["id"]) != null})
	return out


## The PC holding a window id (the first connected one when `pc` is "").
func _pc_of(id: String, pc: String) -> String:
	for s: PcSession in sessions():
		if (pc == "" or s.client_id == pc) and not s.window(id).is_empty():
			return s.client_id
	return ""


func _pane_by_id(id: String) -> PcPane:
	for p: PcPane in panes:
		if p.window_id == id:
			return p
	return null


func register_commands() -> void:
	DevCommands.register("pc_status", func(_a: Dictionary, _c: DevCommands.Call) -> Variant: return status(), {
			"description": "PC windows: whether the service is on, the PCs connected (by id), the panes open and which has the focus. No window titles.",
			"assistant": "read"})
	DevCommands.register("pc_list", func(a: Dictionary, _c: DevCommands.Call) -> Variant:
			return list_windows(str(a.get("pc", ""))), {
			"description": "The windows and monitors of the connected PCs: id, kind, the program's name and size (titles and pictures stay in the headset).",
			"params": [{"name": "pc", "type": "string", "description": "One PC's id (pc_status); empty: all."}],
			"assistant": "read"})
	DevCommands.register("pc_open", _cmd_open, {
			"description": "Opens a PC window or monitor as a pane in front of the viewer.",
			"params": [{"name": "id", "type": "string", "required": true, "description": "The window's id from pc_list (w:... or m:...)."},
				{"name": "pc", "type": "string", "description": "The PC's id when more than one has that window."}],
			"level": "control", "assistant": "control"})
	DevCommands.register("pc_close", _cmd_close, {
			"description": "Closes a PC window's pane (the window stays open on the PC).",
			"params": [{"name": "id", "type": "string", "required": true, "description": "The window's id."}],
			"level": "control", "assistant": "control"})
	DevCommands.register("pc_screen", _cmd_screen, {
			"description": "Shows an open PC window on the big screen, where the film goes, or puts it back in its pane.",
			"params": [{"name": "id", "type": "string", "required": true, "description": "The window's id."},
				{"name": "on", "type": "bool", "default": true, "description": "True: on the big screen; false: back to its pane."}],
			"level": "control", "assistant": "control"})
	DevCommands.register("pc_pane_size", _cmd_size, {
			"description": "Makes a PC window's pane bigger or smaller.",
			"params": [{"name": "id", "type": "string", "required": true, "description": "The window's id."},
				{"name": "width", "type": "float", "required": true, "description": "Metres across, 0.2 to 8."}],
			"level": "control", "assistant": "control"})


func _cmd_open(a: Dictionary, ctx: DevCommands.Call) -> Variant:
	var id := str(a.get("id", ""))
	var pc := _pc_of(id, str(a.get("pc", "")))
	if pc == "":
		return ctx.fail("no connected PC has the window %s (pc_list)" % id)
	var had := pane_for(pc, id) != null
	var pane := open_window(pc, id)
	if pane == null:
		return ctx.fail("the window did not open")
	ctx.summary = "opened a PC window"
	if not had:
		ctx.undo = func() -> void: close_pane(pane)
	return pane.status()


func _cmd_close(a: Dictionary, ctx: DevCommands.Call) -> Variant:
	var pane := _pane_by_id(str(a.get("id", "")))
	if pane == null:
		return ctx.fail("no pane shows %s" % str(a.get("id", "")))
	var pc := pane.client_id
	var id := pane.window_id
	close_pane(pane)
	ctx.summary = "closed a PC window's pane"
	ctx.undo = func() -> void: open_window(pc, id)
	return status()


func _cmd_screen(a: Dictionary, ctx: DevCommands.Call) -> Variant:
	var pane := _pane_by_id(str(a.get("id", "")))
	if pane == null:
		return ctx.fail("no pane shows %s" % str(a.get("id", "")))
	var on := bool(a.get("on", true))
	var was := pane.on_screen
	show_on_screen(pane, on)
	ctx.summary = "a PC window on the big screen" if on else "a PC window back in its pane"
	ctx.undo = func() -> void:
		if panes.has(pane):
			show_on_screen(pane, was)
	return pane.status()


func _cmd_size(a: Dictionary, ctx: DevCommands.Call) -> Variant:
	var pane := _pane_by_id(str(a.get("id", "")))
	if pane == null:
		return ctx.fail("no pane shows %s" % str(a.get("id", "")))
	var old := pane.width
	pane.set_width(float(a.get("width", old)))
	ctx.summary = "a PC window's pane %.2f m across" % pane.width
	ctx.undo = func() -> void:
		if panes.has(pane):
			pane.set_width(old)
	return pane.status()
