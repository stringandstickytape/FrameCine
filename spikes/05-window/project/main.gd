extends Node3D

## Spike 05: shows an X11 window of the desktop (e.g. Chromium playing a video) on a virtual screen through
## X11WindowSource (Composite + DRI3 dmabuf, imported once per buffer, damage-driven; MIT-SHM copy as the fallback), and
## forwards the desktop mouse/keyboard or the right controller to it.
## User arguments (after `--`):
##   --list                 print the toplevel windows and quit.
##   --title=TEXT           capture the first window whose title contains TEXT (case-insensitive).
##   --class=TEXT           ... whose WM_CLASS class or instance contains TEXT.
##   --window=ID            ... with this X id (0x... or decimal).
##   --launch=URL           start Chromium (flatpak org.chromium.Chromium) on URL as an app window, capture its window.
##   --chromium=CMD         the command for --launch, words separated by spaces (default: flatpak run org.chromium.Chromium).
##   --kiosk                with --launch: add --kiosk (fullscreen, no browser UI).
##   --wait=S               wait up to S seconds for the window to appear (default 20).
##   --shm / --get-image    force the copy path (MIT-SHM / plain GetImage) instead of the dmabuf.
##   --input=sendevent|xtest   how input is sent (default sendevent).
##   --passthrough          make our own window transparent to pointer input (for --input=xtest).
##   --test-input[=FRAME]   at FRAME (default 120): move to the centre, left click, type "Hi!", Enter, scroll 3 down.
##   --focus=METHOD[@FRAME] at FRAME (default 180) apply a focus method and print the focus state before and 60 frames
##                          after. Several methods: joined with +. METHOD: self-x, self-raise, self-remap, self-gamescope, target-x, target-raise,
##                          target-remap, target-gamescope, release-gamescope.
##   --close-on-exit        close the captured window (WM_DELETE_WINDOW) when this program quits.
##   --no-xr                flat camera instead of OpenXR.
##   --screen-width=M       width of the screen in metres, 3 m in front (default 4.0; height follows the window).
##   --quit-after=N         quit after N frames. --screenshot=PATH, --screenshot-frame=N (default 300).
## FRAME numbers count from the capture (when a window is given; the program waits for it first).

const STATS_INTERVAL_MS := 2000
const SCREEN_DISTANCE := 3.0
const CHROMIUM_FLAGS := [
	"--ozone-platform=x11", # gamescope's Xwayland: X11 windows are what we can capture.
	"--window-size=1920,1080",
	"--window-position=0,0",
	"--no-first-run",
	"--disable-backgrounding-occluded-windows",
	"--disable-renderer-backgrounding",
	"--disable-background-timer-throttling",
	"--autoplay-policy=no-user-gesture-required",
]

@onready var screen: MeshInstance3D = $Screen
@onready var flat_camera: Camera3D = $FlatCamera
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var right_hand: XRController3D = $XROrigin3D/RightHand

var source: X11WindowSource
var material: ShaderMaterial
var screen_width := 4.0
var frames := 0
var capture_frame := 0 # Frame of the first successful capture; the frame options below count from it.
var quit_after := -1
var screenshot_path := ""
var screenshot_frame := 300
var last_stats_msec := 0
var last_stats: Dictionary = {}
var use_xr := true
var wait_seconds := 20.0
var match_title := ""
var match_class := ""
var match_id := 0
var launch_url := ""
var chromium_cmd := "flatpak run org.chromium.Chromium"
var kiosk := false
var close_on_exit := false
var launched_pid := -1
var windows_before: Dictionary = {}
var waiting_since_msec := 0
var test_input_frame := -1
var focus_method := ""
var focus_frame := 180
var passthrough := false
var trigger_down := false
var grip_down := false
var buttons_prev := Vector2.ZERO # A/X and B/Y last frame, for edge detection.
var pointer_on_screen := false
var last_pointer := Vector2(-1, -1)
var hit_marker: MeshInstance3D


func _ready() -> void:
	var list_only := false
	var preferred := X11WindowSource.CAPTURE_DMABUF
	var input_method := X11WindowSource.INPUT_SEND_EVENT
	for arg in OS.get_cmdline_user_args():
		if arg == "--list":
			list_only = true
		elif arg == "--no-xr":
			use_xr = false
		elif arg == "--shm":
			preferred = X11WindowSource.CAPTURE_SHM
		elif arg == "--get-image":
			preferred = X11WindowSource.CAPTURE_GET_IMAGE
		elif arg == "--kiosk":
			kiosk = true
		elif arg == "--close-on-exit":
			close_on_exit = true
		elif arg == "--passthrough":
			passthrough = true
		elif arg == "--test-input":
			test_input_frame = 120
		elif arg.begins_with("--test-input="):
			test_input_frame = arg.trim_prefix("--test-input=").to_int()
		elif arg.begins_with("--focus="):
			var spec := arg.trim_prefix("--focus=").split("@")
			focus_method = spec[0]
			if spec.size() > 1:
				focus_frame = spec[1].to_int()
		elif arg.begins_with("--input="):
			input_method = X11WindowSource.INPUT_XTEST if arg.ends_with("xtest") else X11WindowSource.INPUT_SEND_EVENT
		elif arg.begins_with("--title="):
			match_title = arg.trim_prefix("--title=").to_lower()
		elif arg.begins_with("--class="):
			match_class = arg.trim_prefix("--class=").to_lower()
		elif arg.begins_with("--window="):
			var id := arg.trim_prefix("--window=")
			match_id = id.hex_to_int() if id.begins_with("0x") else id.to_int()
		elif arg.begins_with("--launch="):
			launch_url = arg.trim_prefix("--launch=")
		elif arg.begins_with("--chromium="):
			chromium_cmd = arg.trim_prefix("--chromium=")
		elif arg.begins_with("--wait="):
			wait_seconds = arg.trim_prefix("--wait=").to_float()
		elif arg.begins_with("--screen-width="):
			screen_width = arg.trim_prefix("--screen-width=").to_float()
		elif arg.begins_with("--quit-after="):
			quit_after = arg.trim_prefix("--quit-after=").to_int()
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-frame="):
			screenshot_frame = arg.trim_prefix("--screenshot-frame=").to_int()

	source = X11WindowSource.new()
	var err := source.open()
	if err != OK:
		push_error("X11WindowSource.open: %s (%s)" % [source.get_last_error(), error_string(err)])
		get_tree().quit(1)
		return
	print("X extensions: %s" % source.get_extensions())
	print("Own window: 0x%x (toplevel 0x%x)" % [source.get_own_window(), source.get_toplevel(source.get_own_window()) if source.get_own_window() != 0 else 0])
	_print_windows()
	if list_only:
		_print_focus("Focus state")
		get_tree().quit()
		return

	source.set_preferred_mode(preferred)
	source.set_input_method(input_method)
	source.window_closed.connect(_on_window_closed)
	source.size_changed.connect(_on_size_changed)
	hit_marker = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.012
	dot.height = 0.024
	var dot_material := StandardMaterial3D.new()
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.albedo_color = Color(1, 0.2, 0.2)
	dot.material = dot_material
	hit_marker.mesh = dot
	hit_marker.visible = false
	add_child(hit_marker)
	material = screen.material_override as ShaderMaterial
	material.set_shader_parameter("window_tex", source.get_texture())
	_setup_view()
	_layout_screen(Vector2i(16, 9))

	if passthrough and source.get_own_window() != 0:
		var pt_err := source.set_input_passthrough(source.get_toplevel(source.get_own_window()), true)
		print("Own window input passthrough: %s" % error_string(pt_err))

	if launch_url != "":
		_launch_browser()
	waiting_since_msec = Time.get_ticks_msec()
	last_stats_msec = Time.get_ticks_msec()


func _print_windows() -> void:
	var own := source.get_own_window()
	print("Windows (bottom to top):")
	for w in source.list_windows():
		print("  0x%x%s %4dx%-4d +%d+%d depth %d  class %s/%s  pid %d  steam_game %d%s  \"%s\"%s" % [w["id"],
				"" if w["frame"] == w["id"] else " (frame 0x%x)" % w["frame"], w["width"], w["height"], w["x"], w["y"], w["depth"],
				w["instance"], w["class"], w["pid"], w["steam_game"], " override-redirect" if w["override_redirect"] else "",
				w["title"], "  <- this program" if w["id"] == own else ""])


func _print_focus(label: String) -> void:
	var info := source.get_focus_info()
	var parts: PackedStringArray = []
	for key in info:
		var value = info[key]
		if value is PackedInt64Array:
			var hex: PackedStringArray = []
			for v in value:
				hex.append("0x%x" % v if v > 65535 else str(v))
			value = "[%s]" % ", ".join(hex)
		elif value is int and value > 65535:
			value = "0x%x" % value
		parts.append("%s=%s" % [key, value])
	print("%s: %s" % [label, ", ".join(parts)])


func _launch_browser() -> void:
	for w in source.list_windows(true):
		windows_before[w["id"]] = true
	var words := chromium_cmd.split(" ", false)
	var args: PackedStringArray = words.slice(1)
	args.append_array(CHROMIUM_FLAGS)
	if kiosk:
		args.append("--kiosk")
	args.append("--app=" + launch_url)
	launched_pid = OS.create_process(words[0], args)
	print("Launched %s %s (pid %d); waiting for its window." % [words[0], " ".join(args), launched_pid])


func _find_window() -> int:
	for w in source.list_windows():
		var id: int = w["id"]
		if id == source.get_own_window():
			continue
		if match_id != 0:
			if id == match_id or w["frame"] == match_id:
				return id
			continue
		if launch_url != "":
			# A new window from Chromium (the flatpak may hand the URL to an already running browser: any new window counts).
			var cls := (str(w["class"]) + " " + str(w["instance"])).to_lower()
			if not windows_before.has(id) and ("chrom" in cls or (match_title != "" and match_title in str(w["title"]).to_lower())):
				return id
			continue
		if match_title != "" and match_title in str(w["title"]).to_lower():
			return id
		if match_class != "" and (match_class in str(w["class"]).to_lower() or match_class in str(w["instance"]).to_lower()):
			return id
	return 0


func _setup_view() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if use_xr and xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		xr_camera.current = true
		print("View: OpenXR")
	else:
		use_xr = false
		flat_camera.current = true
		print("View: flat camera")


func _layout_screen(window_size: Vector2i) -> void:
	var aspect := float(window_size.y) / float(maxi(window_size.x, 1))
	(screen.mesh as QuadMesh).size = Vector2(screen_width, screen_width * aspect)
	screen.position = Vector3(0, 1.6, -SCREEN_DISTANCE)


func _on_size_changed(new_size: Vector2i) -> void:
	print("Window size: %s" % new_size)
	_layout_screen(new_size)


func _on_window_closed() -> void:
	print("The captured window was closed: %s" % source.get_last_error())


func _process(_delta: float) -> void:
	frames += 1
	if frames == 3 and use_xr:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)

	if source and source.is_open() and not source.is_capturing() and (match_title != "" or match_class != "" or match_id != 0 or launch_url != ""):
		if frames % 15 == 0:
			var id := _find_window()
			if id != 0:
				var err := source.capture(id)
				print("Capture 0x%x: %s %s" % [id, error_string(err), source.get_last_error() if err != OK else ""])
				if err == OK:
					_layout_screen(source.get_size())
					match_id = id
					if capture_frame == 0:
						capture_frame = frames
			elif Time.get_ticks_msec() - waiting_since_msec > int(wait_seconds * 1000.0):
				push_error("No matching window after %.0f s." % wait_seconds)
				_print_windows()
				match_title = ""
				match_class = ""
				match_id = 0
				launch_url = ""

	if source and source.is_open():
		source.update()
		if source.is_capturing():
			_controller_input(_delta)
			_test_input()
			_focus_test()
			_report()

	var searching := source != null and source.is_open() and capture_frame == 0 and (match_title != "" or match_class != "" or match_id != 0 or launch_url != "")
	var f := frames - capture_frame
	if f == screenshot_frame and screenshot_path != "" and not searching:
		_save_screenshot()
	if quit_after > 0 and f >= quit_after and not searching:
		print("Quitting after %d frames" % frames)
		get_tree().quit()


# Window pixel under a ray, or (-1, -1) if the ray misses the screen.
func _ray_to_window(origin: Vector3, direction: Vector3) -> Vector2:
	var to_local := screen.global_transform.affine_inverse()
	var o := to_local * origin
	var d := to_local.basis * direction
	if absf(d.z) < 1e-6:
		return Vector2(-1, -1)
	var t := -o.z / d.z
	if t <= 0.0:
		return Vector2(-1, -1)
	var hit := o + d * t
	var quad := (screen.mesh as QuadMesh).size
	var uv := Vector2(hit.x / quad.x + 0.5, 0.5 - hit.y / quad.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	var size := source.get_size()
	return Vector2(uv.x * size.x, uv.y * size.y)


func _unhandled_input(event: InputEvent) -> void:
	if not source or not source.is_capturing() or use_xr:
		return
	if event is InputEventMouse:
		var p := _ray_to_window(flat_camera.project_ray_origin(event.position), flat_camera.project_ray_normal(event.position))
		pointer_on_screen = p.x >= 0.0
		if not pointer_on_screen:
			return
		source.send_pointer(p.x, p.y)
		if event is InputEventMouseButton:
			var b: int = event.button_index
			match b:
				MOUSE_BUTTON_WHEEL_UP:
					if event.pressed:
						source.send_scroll(0, -1)
				MOUSE_BUTTON_WHEEL_DOWN:
					if event.pressed:
						source.send_scroll(0, 1)
				MOUSE_BUTTON_WHEEL_LEFT:
					if event.pressed:
						source.send_scroll(-1, 0)
				MOUSE_BUTTON_WHEEL_RIGHT:
					if event.pressed:
						source.send_scroll(1, 0)
				MOUSE_BUTTON_LEFT:
					source.send_button(1, event.pressed)
				MOUSE_BUTTON_MIDDLE:
					source.send_button(2, event.pressed)
				MOUSE_BUTTON_RIGHT:
					source.send_button(3, event.pressed)
				MOUSE_BUTTON_XBUTTON1:
					source.send_button(8, event.pressed)
				MOUSE_BUTTON_XBUTTON2:
					source.send_button(9, event.pressed)
	elif event is InputEventKey:
		if event.keycode == KEY_F10 and event.pressed:
			get_tree().quit()
			return
		# Printable characters as text (keeps the layout's shifted symbols right), the rest as keys.
		if event.unicode >= 32 and not event.ctrl_pressed and not event.alt_pressed:
			if event.pressed:
				source.send_unicode(event.unicode, true)
				source.send_unicode(event.unicode, false)
		else:
			source.send_godot_key(event.keycode, event.pressed)


# Right controller: aim at the screen to move the pointer; trigger = left button, grip = right button,
# stick = scroll (up/down, left/right), A = Space (play/pause in most players), B = browser Back.
# Action names are the app's action map (xr/openxr_action_map.tres): next_file is A, prev_file is B.
func _controller_input(delta: float) -> void:
	if not use_xr or not right_hand.get_has_tracking_data():
		return
	var aim := right_hand.global_transform
	var p := _ray_to_window(aim.origin, -aim.basis.z)
	pointer_on_screen = p.x >= 0.0
	hit_marker.visible = pointer_on_screen
	if pointer_on_screen:
		var size := Vector2(source.get_size())
		var quad := (screen.mesh as QuadMesh).size
		hit_marker.global_position = screen.global_transform * Vector3((p.x / size.x - 0.5) * quad.x, (0.5 - p.y / size.y) * quad.y, 0.01)
		if p.distance_to(last_pointer) >= 0.5:
			last_pointer = p
			source.send_pointer(p.x, p.y)
	var trigger := right_hand.get_float("trigger") > 0.6
	if trigger != trigger_down and (pointer_on_screen or not trigger):
		trigger_down = trigger
		source.send_button(1, trigger)
	var grip := right_hand.get_float("squeeze") > 0.6
	if grip != grip_down and (pointer_on_screen or not grip):
		grip_down = grip
		source.send_button(3, grip)
	var s := right_hand.get_vector2("thumbstick")
	if s.length() > 0.2:
		# About 12 notches a second at full deflection.
		source.send_scroll(s.x * 12.0 * delta, -s.y * 12.0 * delta)
	if right_hand.is_button_pressed("next_file") and not buttons_prev.x:
		source.send_key(0x20, true)
		source.send_key(0x20, false)
	if right_hand.is_button_pressed("prev_file") and not buttons_prev.y:
		source.send_godot_key(KEY_BACK, true)
		source.send_godot_key(KEY_BACK, false)
	buttons_prev = Vector2(1 if right_hand.is_button_pressed("next_file") else 0, 1 if right_hand.is_button_pressed("prev_file") else 0)


func _test_input() -> void:
	if test_input_frame < 0:
		return
	var size := source.get_size()
	var f := frames - capture_frame - test_input_frame
	match f:
		0, 1, 2, 3, 4:
			if f == 0:
				print("Test input: pointer sweep to the centre %d,%d" % [size.x / 2, size.y / 2])
			source.send_pointer(size.x * (0.3 + 0.05 * f), size.y * (0.3 + 0.05 * f))
		5:
			print("Test input: left click")
			source.send_button(1, true)
		7:
			source.send_button(1, false)
		20:
			print("Test input: text \"Hi!\" and Enter")
			source.send_text("Hi!")
			source.send_godot_key(KEY_ENTER, true)
			source.send_godot_key(KEY_ENTER, false)
		40:
			print("Test input: scroll 3 down")
			source.send_scroll(0, 3)
		45:
			print("Test input: done (%d input events sent)" % source.get_stats()["input_events"])


func _focus_test() -> void:
	if focus_method == "":
		return
	if frames - capture_frame == focus_frame:
		_print_focus("Focus before %s" % focus_method)
		var own := source.get_own_window()
		var target := source.get_window()
		for method in focus_method.split("+"):
			_apply_focus(method, own, target)
	elif frames - capture_frame == focus_frame + 60:
		_print_focus("Focus 60 frames after %s" % focus_method)


func _apply_focus(method: String, own: int, target: int) -> void:
	var err := OK
	match method:
		"self-x":
			err = source.set_input_focus(own)
		"self-raise":
			err = source.raise_window(own)
		"self-remap":
			err = source.remap_window(own)
		"self-gamescope":
			err = source.gamescope_focus(own)
		"target-x":
			err = source.set_input_focus(target)
		"target-raise":
			err = source.raise_window(target)
		"target-remap":
			err = source.remap_window(target)
		"target-gamescope":
			err = source.gamescope_focus(target)
		"release-gamescope":
			err = source.gamescope_release_focus()
		_:
			push_error("Unknown focus method %s" % method)
	print("Focus method %s: %s" % [method, error_string(err)])


func _report() -> void:
	var now := Time.get_ticks_msec()
	if now - last_stats_msec < STATS_INTERVAL_MS:
		return
	var s := source.get_stats()
	var seconds := (now - last_stats_msec) / 1000.0
	var damage: int = s["damage_events"] - last_stats.get("damage_events", 0)
	var updated: int = s["frames_updated"] - last_stats.get("frames_updated", 0)
	var copied: int = s["bytes_copied"] - last_stats.get("bytes_copied", 0)
	print("[%7.1f s] %s %s%s %dx%d: damage %.1f/s, updates %.1f/s, deferred %d, imports %d (cached %d, switches %d), copy %.1f MB/s, fetch avg %.2f max %.2f ms, render %.0f fps, input %d, X errors %d%s" % [
			now / 1000.0, s["mode"], s["format"], " " + str(s["modifier"]) if s["zero_copy"] else "", s["size"].x, s["size"].y,
			damage / seconds, updated / seconds, s["frames_deferred"], s["imports"], s["buffers_cached"], s["buffer_switches"],
			copied / seconds / 1e6, s["fetch_ms_avg"], s["fetch_ms_max"], Engine.get_frames_per_second(), s["input_events"], s["x_errors"],
			"" if s["dmabuf_error"] == "" else " (dmabuf: %s)" % s["dmabuf_error"]])
	last_stats = s
	last_stats_msec = now


func _save_screenshot() -> void:
	# Under gamescope an unfocused X11 window may never be drawn, so render through an offscreen SubViewport.
	var sub := SubViewport.new()
	sub.size = Vector2i(1920, 1080)
	sub.world_3d = get_world_3d()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.global_transform = flat_camera.global_transform
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	var err := img.save_png(screenshot_path)
	print("Screenshot (offscreen) %s (%dx%d): %s" % [screenshot_path, img.get_width(), img.get_height(), error_string(err)])
	sub.queue_free()


func _exit_tree() -> void:
	if source:
		var s := source.get_stats()
		print("Final: mode %s, %d damage events, %d updates, %d deferred, %d imports, %d copies (%.1f MB), %d input events, %d X errors (%s)" % [
				s["mode"], s["damage_events"], s["frames_updated"], s["frames_deferred"], s["imports"], s["copies"], s["bytes_copied"] / 1e6,
				s["input_events"], s["x_errors"], s["last_x_error"]])
		if close_on_exit and source.is_capturing():
			print("Closing the browser window 0x%x" % source.get_window())
			source.close_window(source.get_window())
		source.close()
	if material:
		material.set_shader_parameter("window_tex", null)
	source = null
