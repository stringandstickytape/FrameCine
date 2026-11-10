extends Node3D

## FrameCine: the app core. The view (XR, or a flat camera when there is no runtime), the PlaybackController,
## the VideoScreen, environments, the info overlay, settings, the playlist, command-line arguments and the direct
## controller / keyboard bindings. The menu is the panel (docs/ui-design.md), a separate, optional layer
## (app/ui/ui_layer.gd, node "UILayer"): it uses only the public functions and signals below and the features hub, and
## the core runs without it.
##
## Direct bindings (controllers through xr/openxr_action_map.tres; keys on a desktop):
##   trigger             play / pause (laser on the panel: click; panel open: the focused)  Space, K
##   thumbstick x        seek -/+10 s, repeats while held (on the menu: -)                 Left / Right, J / L
##   thumbstick y        screen distance (laser on the panel: scroll; panel open: focus)    Up / Down
##   A/X, B/Y            next / previous video in the folder or playlist                    N / P
##   menu (either hand)  open the panel in front / close it; hold 0.6 s: recentre it        M, F3 (Esc closes)
##   overlay (left stick click) show / hide the info overlay                                Tab, F1
##   Y (right)           the agent's terminal on or off, while the right hand points        -
##   X (right)           Enter in the agent's terminal while it shows; nothing otherwise     -
##   grip                quick squeeze: right click on a captured window (no longer moves the screen); a desktop
##                       still moves it with G (hold) + mouse
##   grip + trigger      180 / 360: the zoom lens on the aimed part of the picture (hold)   -
##   grip (hold)         pointing at an object (or in one): picks it up; stick near-far / turn, let go to drop or
##                       throw, B back (scripts/play/object_grab.gd, docs/physics.md)                   -
##   -                   recenter                                                           R
##   -                   next projection / layout / half / swap eyes / environment          V / O / H / X / E
## While a captured window (Browser place) is on the screen and the menu is hidden, the right controller, the mouse
## and the keyboard work the window instead: see scripts/window_pointer.gd.
##
## User arguments (after `--`):
##   --file=PATH            open a file (or stub://<mode id>, e.g. stub://360_tb); its folder is the playlist
##   --dir=PATH             play every video in a folder in order (--file= picks the first one)
##   --mode=MODE            flat, sbs, hsbs, fsbs, tb, ou, hou, 3d, 180, 180sbs, 360, 360tb, fisheye, dualfisheye (dfe),
##                          mono, or a full id (flat_sbs_half, fisheye_sbs_fov200, dualfisheye_mono, ...). Default:
##                          guessed from the file name and size.
##   --fov=DEG              fisheye field of view
##   --screen-width=M  --distance=M  --height=M (screen centre above eye level)
##   --env=void|room|cinema
##   --overlay / --debug    info overlay on (--debug also logs every controller input, as --verbose-input does)
##   --labels-debug         a 2 mm sphere at each controller label's anchor (alignment checks)
##   --dump-render-models=DIR  write the runtime controller models to DIR/<side>_controller.glb + .json (never commit)
##   --controller-model=runtime|ours  the runtime's controller model with our printed labels (default in XR), or our
##                          own model with the legends printed (models/controllers; always on a desktop)
##   --snapshot-dir=DIR     head view + controller close-ups to PNG on left bumper + A, F12 (scripts/dev/snapshots.gd)
##   --snapshot-every=S     also every S seconds
##   --no-ui                don't open the panel in front at start
##   --no-xr                flat camera even if XR is up
##   --look=YAW,PITCH  --camera-fov=DEG   flat camera direction / vertical field of view (degrees)
##   --quit-after=N         quit after N rendered frames
##   --screenshot=PATH      at --screenshot-frame=N (default 90): PNG of both eyes side by side (flat camera)
##   --shots=DIR            screenshot tour (scripts/dev/screenshot_tour.gd), then quit
##   --ui-test              menu input test (scripts/dev/ui_input_test.gd), then quit
##   --window-test          Browser place and window source test on an X11 desktop (scripts/dev/window_test.gd)
##   --browser-command="CMD ARGS"  --browser-match=TEXT   run CMD instead of the browser, and find its window by class
##                          (tests; see scripts/video/window_video_source.gd)
##   --no-save              don't read or write user://settings.cfg
##   --pseudo-locale        the menus in the pseudo-locale for this run (scripts/i18n.gd, docs/i18n.md; a dev check)
##   --benchmark[=PATH]     decode the biggest video in a folder (or PATH) for 10 s and report what the device can do
##                          (scripts/dev/benchmark.gd; it also runs once by itself on the first run)
##   --tour=FILE            run a tour: a room, a playlist and screen / camera moves from a JSON file (FILE: a path or
##                          a name in user://tours; docs/tours.md). --kiosk loops it for ever.
##   --pc-audio=HOST[:PORT] the film's sound on a PC (tools/audio_sink.py), the PC as the clock (docs/pc-audio.md)
##   --pc-audio-mode=auto|pull|capture  how PC audio gets the sound (auto: from the engine when it can)
##   --hands / --passthrough  XR spikes, untested on the device: hand tracking (pinch = trigger, index = laser), the
##                          runtime's camera view behind the scene (scripts/xr_spikes/, docs/xr-spikes.md)
##   --pane-layer / --video-layer  XR spike #70, untested on the device: the pane, or the flat screen, as OpenXR quad
##                          layers the runtime composites itself (scripts/xr_spikes/quad_layers.gd; the screen's
##                          layer is the film layer, scripts/play/film_layer.gd, on for the run)

signal file_opened(path: String)
signal mode_changed(mode: VideoMode, auto_text: String)
signal screen_changed(width: float, distance: float, height_offset: float)
signal environment_changed(id: String, light_scale: float)
## Volume, A/V offset, overlay or foveation changed.
signal audio_settings_changed
## The file ended and nothing plays next.
signal playback_ended

const VideoMode := preload("res://scripts/video_mode.gd")
const RoomParticles := preload("res://scripts/assistant/room_particles.gd")
const AppSettings := preload("res://scripts/app_settings.gd")
const I18n := preload("res://scripts/i18n.gd")
const PlaybackController := preload("res://scripts/playback_controller.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const VideoSource := preload("res://scripts/video/video_source.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const XRHand := preload("res://scripts/xr/xr_hand.gd")
const ControllerLook := preload("res://scripts/xr/controller_look.gd")
const InfoOverlay := preload("res://scripts/info_overlay.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
const SavedPlaces := preload("res://scripts/net/saved_places.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const WindowPointer := preload("res://scripts/window_pointer.gd")
const BrowserDictation := preload("res://scripts/video/browser_dictation.gd")
const PictureKeeper := preload("res://scripts/pictures/picture_keeper.gd")
const LocalAgents := preload("res://scripts/agents/local_agents.gd")
const Intro := preload("res://ui/intro.gd")
const AndroidApps := preload("res://scripts/android/android_apps.gd")
const VREnvironment := preload("res://environments/vr_environment.gd")
const ScreenshotTour := preload("res://scripts/dev/screenshot_tour.gd")
const UIInputTest := preload("res://scripts/dev/ui_input_test.gd")
const WindowTest := preload("res://scripts/dev/window_test.gd")
const Snapshots := preload("res://scripts/dev/snapshots.gd")
const Features := preload("res://scripts/play/features.gd")
const Recipes := preload("res://scripts/dev/recipes.gd")
const EnvLibrary := preload("res://scripts/env/env_library.gd")
const Showrooms := preload("res://scripts/env/showrooms.gd")
const ContainerMode := preload("res://scripts/play/container_mode.gd")
const Sidecar := preload("res://scripts/play/sidecar.gd")
const HwVideo := preload("res://scripts/play/hw_video.gd")

## [id, display name, scene, aliases]
const ENVIRONMENTS: Array = [
	["void", "Void", "res://environments/void.tscn", ["none", "black"]],
	["dim_room", "Dim room", "res://environments/dim_room.tscn", ["room", "dim"]],
	["cinema", "Cinema", "res://environments/cinema.tscn", ["theatre", "theater"]],
	["passthrough", "Passthrough", "res://environments/passthrough.tscn",
			["real room", "my room", "mixed reality", "camera", "cameras"]],
]
const SEEK_STEP := 10.0
const SEEK_REPEAT := 0.4
const FLAT_EYE_HEIGHT := 1.2
## The eye height every room is built for: a seated viewer's (scripts/assistant/room_schema.gd NOMINAL_EYE_HEIGHT).
## The room is lifted by the viewer's real eye height less this, so their eyes are where the room's seat puts them
## and a telly, a screen's frame or a stage lines up with the picture (lift_room()).
const ROOM_EYE_HEIGHT := 1.2
## Every room's seat as the viewer sits in it (the user, 2026-11-07: "in every case ... maybe 30 cm too far back and
## 10 cm too low"): the eyes 0.1 m higher in every room, and nearer the screen by SEAT_NEARER of its distance from the
## seat, at most SEAT_NEARER_MAX (25 cm in a cinema, a few at a telly: a fixed 25 cm put the viewer on the front edge of
## the chair and against TV 1937's set, 2026-11-08). The room moves, its screen with it (_apply_room_offset()).
const SEAT_RISE := 0.1
const SEAT_NEARER := 0.03
const SEAT_NEARER_MAX := 0.25
## The shift in use (zero where the room is not lifted): the room's move on top of the lift.
var room_shift := Vector3.ZERO
var _lift := 0.0
## A grip shorter than this, with the hand turned less than GRIP_TAP_ANGLE, is a tap (screen to gaze).
const GRIP_TAP_MSEC := 350
const GRIP_TAP_ANGLE := deg_to_rad(4.0)
## Thumbstick up/down: relative distance change per second at full deflection.
const DISTANCE_RATE := 0.8
## Spherical modes: the overlay this far ahead and below eye level.
const OVERLAY_SPHERE_DISTANCE := 2.0
const OVERLAY_SPHERE_DROP := 0.75
## Overlay scale per metre of viewing distance (scale 1 = 0.4 m wide).
const OVERLAY_SCALE_PER_METRE := 0.9

## Controller labels: what each action of the action map does, [menu hidden, menu shown] ("" = no label). The one
## place for this text: the controller labels print it on the controller next to whatever input the bound profile
## maps the action to. Short legends, like print on a device: 5 to 6 mm per line, and the face plate is crowded.
## Printed in the menus' language (controller_labels(); the legends of the three tables are keys, docs/i18n.md).
# i18n: begin
const CONTROL_LABELS := {
	"trigger": ["PLAY / PAUSE", "CLICK"],
	"squeeze": ["", ""],
	"thumbstick": ["SEEK / DIST", "SCROLL"],
	"menu": ["MENU", "CLOSE"],
	# The right stick click on the headset's own controllers: the menu, except on an image in the browser (below).
	"stick_click": ["MENU", "CLOSE"],
	"overlay": ["INFO", "INFO"],
	"next_file": ["NEXT", "NEXT"],
	"prev_file": ["PREV", "PREV"],
	"labels": ["LABELS", "LABELS"],
	# Only bound by the opt-in d-pad map, xr/openxr_action_map_dpad.tres (docs/features.md, #15).
	"chapter_prev": ["CHAPTER -", "CHAPTER -"],
	"chapter_next": ["CHAPTER +", "CHAPTER +"],
	"replay": ["REPLAY", "REPLAY"],
	# X: no legend until an agent's terminal shows (ENTER_LABEL).
	"enter": ["", ""],
}
## X's legend while an agent's terminal shows (scripts/agents/local_agents.gd enter_ready()), menu open or not.
const ENTER_LABEL := "ENTER"
## The right controller's legends while a captured window has the input (scripts/window_pointer.gd); actions not
## listed keep CONTROL_LABELS. The left controller drops trigger, NEXT and PREV then (they do nothing on a window).
## These are the laser's ([browser] laser, while the viewer looks away); the stick pointer has the two below.
const WINDOW_LABELS := {
	"trigger": "CLICK",
	"squeeze": "R-CLICK",
	"thumbstick": "SCROLL / KEYS",
	"next_file": "SPACE",
	"prev_file": "BACK",
}
## Pointer mode (the viewer looks at the screen): the stick moves the cursor, the trigger clicks, squeeze held + stick
## scrolls (a squeeze tap is still the right click).
const WINDOW_POINTER_LABELS := {
	"trigger": "CLICK",
	"squeeze": "HOLD: SCROLL",
	"thumbstick": "POINTER",
	"next_file": "SPACE",
	"prev_file": "BACK",
	# The stick click keeps the picture under the cursor (scripts/pictures/picture_keeper.gd): its legend only while
	# the cursor is over an image (window_pointer.gd window_labels()).
	"stick_click": "",
}
const KEEP_PICTURE_LABEL := "KEEP PICTURE"
## Applying a material or a picture to a part (the Objects tab's Apply, ui/object_placer.gd), the pointer controller.
const APPLY_LABELS := {
	"trigger": "APPLY",
	"thumbstick": "SIZE / TURN",
	"prev_file": "CANCEL",
}
## Looking away: no cursor, the stick does its normal job; the trigger and the squeeze do nothing ("" hides them).
const WINDOW_AWAY_LABELS := {
	"trigger": "",
	"squeeze": "",
	"thumbstick": "SCROLL / KEYS",
	"next_file": "SPACE",
	"prev_file": "BACK",
}
# i18n: end
const WINDOW_LEFT_HIDDEN: Array[String] = ["trigger", "next_file", "prev_file"]
# i18n: begin
## The pointer controller's legends while an agent's terminal has the input (scripts/agents/local_agents.gd: a prompt
## waits on the pane, the viewer looks at it, or the terminal is on the big screen). Squeeze held + stick scrolls back.
const TERMINAL_LABELS := {
	"trigger": "ENTER",
	"squeeze": "HOLD: SCROLL",
	"thumbstick": "ARROWS",
	"next_file": "SPACE",
	"prev_file": "ESC",
}
## Object physics (docs/physics.md): the squeeze's legend while the room has objects to pick up (menu hidden), and a
## controller's legends while it holds one ("" hides an action's legend: the trigger does nothing then).
const GRAB_LABEL := "GRAB"
const HOLD_LABELS := {
	"trigger": "",
	"squeeze": "LET GO: THROW",
	"thumbstick": "NEAR-FAR / TURN",
	"prev_file": "CANCEL",
}
# i18n: end
## Back in focus (dashboard closed, headset on): resume this long after, if focus loss paused playback.
const AUTO_RESUME_DELAY := 0.3
## Without a runtime (desktop, screenshot tour) the labels preview this profile.
const PREVIEW_PROFILE := "/interaction_profiles/valve/frame_controller_valve"
## Binding path segment -> label anchor of controller_visual.gd, where the names differ.
const INPUT_ALIASES := {"select": "trigger", "primary": "a", "secondary": "b"}
## [view] foveation: the words for OpenXRInterface.foveation_level 0 to 3 (D22).
const FOVEATION_LEVELS := ["off", "low", "medium", "high"]

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRHand = $XROrigin3D/LeftHand
@onready var right_hand: XRHand = $XROrigin3D/RightHand
@onready var flat_camera: Camera3D = $FlatCamera
@onready var env_root: Node3D = $EnvironmentRoot
@onready var screen: VideoScreen = $VideoScreen
@onready var player: PlaybackController = $Player
@onready var overlay: InfoOverlay = $InfoOverlay
## The optional menu layer (ui/ui_layer.gd), or null.
@onready var ui: Node = get_node_or_null("UILayer")

var settings := AppSettings.new()
var use_xr := false
var camera: Camera3D
var hands: Array[XRHand] = []
var env: VREnvironment
var env_id := "void"
## The room of a new install (the user, 2026-11-09); a chosen room, the Void too, is kept in [view] environment.
const DEFAULT_ENVIRONMENT := "cinema"
var room_light := 1.0
var mode: VideoMode = VideoMode.new()
## Where the mode came from: "auto" (file name + size), "metadata" (the container's stereo / spherical metadata),
## "arg" (--mode), "file" (remembered), "sidecar" (<file>.vrmode.json next to it), "user", "pattern".
var mode_source := "auto"
var current_path := ""
var playlist: Array[String] = []
var playlist_index := -1
## [path, what its NFO calls it] of the file on show, for display_title().
var _library_title := ["", ""]
## --dir: go on to the next file at the end of one.
var auto_advance := false
var eye_height := FLAT_EYE_HEIGHT
var screen_width := 3.0
var screen_distance := 3.0
var screen_height_offset := 0.0
## Screen direction around the viewer, radians, > 0 = to the right.
var screen_yaw := 0.0
## A feature's say in the flat screen's pose (scripts/comfort/screen_pose.gd: lying down, head follow): called by
## _place_screen() with the pose it computed, returns the pose to use. Unset: main's own pose.
var screen_pose_override: Callable
## The flat screen's own facing when a room fixes it (an assistant's room with its own screen; seat_choice.gd sets
## it): the yaw of its picture's normal in the world. NAN: the screen faces the viewer, as always. The viewer's
## recentre clears it for the session.
var screen_turn := NAN
var overlay_on := false
var volume := 1.0
## [view] foveation: one of FOVEATION_LEVELS (D22).
var foveation := "medium"
## [view] foveation_sharp_panel: foveation off while the panel or the agent pane shows.
var foveation_sharp_panel := true
## What foveation is set on: the OpenXR interface in XR (_setup_view), else null. Tests put a stand-in here.
var foveation_xr: Object
## False from _setup_view until the session has drawn a few frames. The engine makes the eye swapchains foveated only
## if the level is above 0 when it creates them (the session's first frames). Until then the level stays at
## project.godot's: setting 0 earlier (the panel rule, at start) left foveation off for good (2026-11-09).
var foveation_live := true
## [controllers] look and look_options: how both controllers look (scripts/xr/controller_look.gd).
var controller_look := ControllerLook.DEFAULT
var controller_look_options := {}

## Screen / sphere drag: {"ray": Callable -> [origin, dir], "hand": XRHand or null, "distance", "yaw", "start_dir",
## "start_msec"}
var _grab := {}
## hand -> msec of its squeeze press, for the quick squeeze (a right click on a captured window).
var _grip_down := {}
var _seek_hold := {}
var _look := Vector2.ZERO
var _mouse_look := false
var _frames := 0
var _eye_height_frames := 0
var _save_timer := 0.0
var _overlay_timer := 0.0
var _last_stats := {}
var _last_stats_msec := 0
var _args := {}
var _overlay_suppressed := false
var menu_shown := false
## The XR session is FOCUSED (input and full frame rate). True without XR.
var session_focused := true
var _particles_timed := false # RoomParticles.allow() is due (on_session_state()).
## Playback was paused because the session lost focus (resumes on focus); false once the user plays or pauses.
var auto_paused := false
var _auto_toggle := false
var _resume_at_msec := -1
## Who holds the labels button: hand -> true. Only the snapshot chord asks.
var _labels_holders := {}
## The legends were last printed with GRAB on the squeeze (object physics had objects then).
var _grab_labelled := false
## "profile|side" -> [[input, action, press], ...] from the action map.
static var _binding_cache := {}
## Input for a captured window (browser) on the screen.
var window_pointer: WindowPointer
## Voice into the browser's selected field (scripts/video/browser_dictation.gd): the talk button asks the page first.
var browser_dictation: BrowserDictation
## Keeping pictures from the browser on the big screen (scripts/pictures/picture_keeper.gd): the right stick click on
## an image, Chromium's Copy image, a save to Downloads.
var picture_keeper: PictureKeeper
## The agents on the headset, in their terminals (scripts/agents/local_agents.gd).
var local_agents: LocalAgents
## Android apps on the big screen (scripts/android/android_apps.gd).
var android_apps: AndroidApps
## --snapshot-dir: head view and controller close-ups to PNG (null when off).
var snapshots: Snapshots
## Playback features (scripts/play/features.gd, docs/features.md): end time, battery forecast, resume, ...
var features: Features


func _ready() -> void:
	_args = _parse_args()
	if _args.has("no-save") or _args.has("shots") or _args.has("ui-test") or _args.has("window-test"):
		settings.read_only = true
	settings.load_file()
	# The menus' language ([language] ui) and its fonts, before anything builds a text (docs/i18n.md).
	I18n.setup(settings, _args.has("pseudo-locale"))
	I18n.holder().changed.connect(_on_language_changed)
	NetworkHosts.load_from(settings)
	WebPages.load_from(settings)
	SavedPlaces.load_from(settings)
	if _args.has("browser-command"):
		WindowVideoSource.browser_command.assign(str(_args["browser-command"]).split(" ", false))
	if _args.has("browser-match"):
		WindowVideoSource.browser_match = str(_args["browser-match"]).to_lower()
	window_pointer = WindowPointer.new()
	window_pointer.name = "WindowPointer"
	window_pointer.main = self
	add_child(window_pointer)
	browser_dictation = BrowserDictation.new()
	browser_dictation.name = "BrowserDictation"
	browser_dictation.main = self
	add_child(browser_dictation)
	picture_keeper = PictureKeeper.new()
	picture_keeper.name = "PictureKeeper"
	picture_keeper.main = self
	add_child(picture_keeper)
	local_agents = LocalAgents.new()
	local_agents.name = "LocalAgents"
	local_agents.main = self
	add_child(local_agents)
	android_apps = AndroidApps.new()
	android_apps.name = "AndroidApps"
	android_apps.main = self
	add_child(android_apps)
	overlay_on = bool(settings.get_value("view", "overlay", false)) or _args.has("overlay") or _args.has("debug")
	volume = float(settings.get_value("audio", "volume", 1.0))
	player.av_offset = float(settings.get_value("audio", "av_offset", 0.0))
	_apply_volume()
	load_foveation()

	_setup_view(not _args.has("no-xr"))
	screen.head = camera
	hands = [left_hand, right_hand]
	for hand in hands:
		hand.verbose = _args.has("debug") or _args.has("verbose-input")
		hand.visual.set_debug_anchors(_args.has("labels-debug"))
		if _args.has("dump-render-models"):
			hand.visual.dump_dir = _expand(str(_args["dump-render-models"]))
		hand.trigger_changed.connect(_on_trigger)
		hand.grip_changed.connect(_on_grip)
		hand.menu_pressed.connect(func(h: XRController3D) -> void: on_menu(h as XRHand, true))
		hand.menu_released.connect(func(h: XRController3D) -> void: on_menu(h as XRHand, false))
		# The right stick click: keeps the picture under the browser's cursor (pointer mode), else the menu.
		hand.stick_clicked.connect(func(h: XRController3D, pressed: bool) -> void:
			if picture_keeper != null and picture_keeper.on_stick_click(h as XRHand, pressed):
				return
			on_menu(h as XRHand, pressed))
		hand.overlay_pressed.connect(func(_h: XRController3D) -> void: set_overlay(not overlay_on))
		hand.next_pressed.connect(func(h: XRController3D) -> void:
			# Left bumper held + A: a snapshot (--snapshot-dir).
			if snapshots != null and h == right_hand and _labels_holders.has(left_hand):
				snapshots.take()
				return
			# A on the first start's introduction (ui/intro.gd): its next step.
			if ui != null and ui.on_intro_next(h as XRHand):
				return
			if local_agents.on_button(h, "next_file"):
				return
			if not window_pointer.on_button(h as XRHand, "next_file"):
				next_file())
		hand.prev_pressed.connect(func(h: XRController3D) -> void:
			# B while holding an object puts it back where it was picked up (object_grab.gd).
			if features != null and features.grab.on_back(h):
				return
			# B cancels the pane's seat picking (ui_layer.gd) before it means "previous file".
			if ui != null and ui.on_back(h as XRHand):
				return
			if local_agents.on_button(h, "prev_file"):
				return
			if not window_pointer.on_button(h as XRHand, "prev_file"):
				previous_file())
		hand.labels_held.connect(func(h: XRController3D, held: bool) -> void:
			# With the dev link on, the pointer hand's bumper is push-to-talk (ui_layer.gd); the other shows labels.
			if ui != null and ui.on_bumper(h as XRHand, held):
				return
			set_labels_held(h, held))
		hand.agent_pressed.connect(func(h: XRController3D) -> void: local_agents.on_agent_button(h))
		# X (headset profile, right controller): Enter in the agent's terminal while it shows; nothing otherwise.
		hand.enter_pressed.connect(func(h: XRController3D) -> void: local_agents.on_enter_button(h))
		hand.bound_profile_changed.connect(func(_h: XRController3D, _p: String) -> void: update_controller_labels())
		# Our model (printed legends) shows at once; with "runtime" (the default in XR) the runtime's model replaces it
		# when it arrives, with our layout's printed labels.
		hand.visual.use_our_model()
		if use_xr and str(_args.get("controller-model", "runtime")) != "ours":
			hand.setup_render_model()
	load_controller_look()
	update_controller_labels()
	if _args.has("snapshot-dir"):
		snapshots = Snapshots.new()
		snapshots.name = "Snapshots"
		snapshots.main = self
		snapshots.out_dir = _expand(str(_args["snapshot-dir"]))
		snapshots.every = float(_args.get("snapshot-every", 0.0))
		add_child(snapshots)
	player.opened.connect(_on_opened)
	player.connecting.connect(func(path: String) -> void:
		screen.set_shown(false)
		print("Connecting to %s ..." % path))
	player.format_changed.connect(_on_format_changed)
	# A play / pause by the user (any input) ends an automatic pause: no resume on focus then.
	player.playing_changed.connect(func(_p: bool) -> void:
		if not _auto_toggle:
			auto_paused = false
			_resume_at_msec = -1)
	player.ended.connect(_on_ended)

	features = Features.new()
	features.name = "Features"
	features.main = self
	add_child(features)
	# The legends follow object physics: GRAB while there are objects to pick up, the holding ones while holding.
	features.grab.changed.connect(update_controller_labels)
	features.physics.changed.connect(func() -> void:
		if features.physics.available() != _grab_labelled:
			update_controller_labels())
	if ui != null:
		ui.setup(self)
	set_environment(_env_from_arg(str(_args.get("env", settings.get_value("view", "environment", DEFAULT_ENVIRONMENT)))))
	if _args.has("screen-width") or _args.has("distance") or _args.has("height"):
		set_screen(float(_args.get("screen-width", screen_width)), float(_args.get("distance", screen_distance)),
				float(_args.get("height", screen_height_offset)))
	_update_overlay_visibility()

	if _args.has("camera-fov"):
		flat_camera.fov = float(_args["camera-fov"])
	if _args.has("look"):
		var parts := str(_args["look"]).split(",")
		_look = Vector2(parts[0].to_float(), parts[1].to_float() if parts.size() > 1 else 0.0)
	_apply_look()

	var start := ""
	var start_playlist: Array[String] = []
	if _args.has("dir"):
		var folder := _expand(str(_args["dir"]))
		var files := VideoSourceFactory.list_videos(folder)
		if files.is_empty():
			push_error("--dir=%s: no video files" % folder)
		else:
			auto_advance = true
			start_playlist = files
			start = _expand(str(_args["file"])) if _args.has("file") else files[0]
			if not start.is_absolute_path() and not start.begins_with("stub://"):
				start = folder.path_join(start)
	elif _args.has("file"):
		start = _expand(str(_args["file"]))
	if start != "":
		open_path(start, true, start_playlist)
	# The panel starts open in front (docs/ui-design.md), unless --no-ui.
	if ui != null and not _args.has("no-ui"):
		ui.show_panel()
	# The first start's introduction in the panel (ui/intro.gd), until it is gone through; not on a run started for a
	# file, a tour or a test, nor with read-only settings.
	if ui != null and Intro.wanted(settings, _args):
		ui.show_intro()
	# Hardware 10-bit video (scripts/play/hw_video.gd): reads the decoder's formats once on a worker thread.
	features.hwvideo.start(_args)
	if _args.has("shots"):
		var tour := ScreenshotTour.new()
		tour.main = self
		tour.out_dir = _expand(str(_args["shots"]))
		add_child(tour)
	if _args.has("ui-test"):
		var test := UIInputTest.new()
		test.main = self
		add_child(test)
	if _args.has("window-test"):
		var window_test := WindowTest.new()
		window_test.main = self
		add_child(window_test)
	# Dev plumbing (docs/dev/): hot-reload with --dev. Returns at once and makes nothing when it is off.
	preload("res://scripts/dev/dev_host.gd").attach(self, _args)
	# Phone remote (docs/remote.md): only with --remote or [remote] enabled; nothing is loaded otherwise.
	preload("res://scripts/remote/remote.gd").attach(self, _args)
	# The assistant service (docs/assistant.md): only with [assistant] enabled; nothing is loaded otherwise.
	preload("res://scripts/assistant/assistant.gd").attach(self)
	# Self-benchmark (docs/benchmark.md): once on the first run when idle, or with --benchmark.
	preload("res://scripts/dev/benchmark.gd").attach(self, _args)
	# Scripted tour / kiosk (docs/tours.md): only with --tour.
	preload("res://scripts/dev/tour.gd").attach(self, _args)
	# PC audio sync (docs/pc-audio.md): only with --pc-audio.
	if _args.has("pc-audio"):
		load("res://scripts/dev/pc_audio.gd").attach(self, _args)
	# XR spikes (docs/xr-spikes.md): the capabilities log line in XR; hands and passthrough only with their flags.
	load("res://scripts/xr_spikes/xr_spikes.gd").attach(self, _args)
	load("res://scripts/xr_spikes/quad_layers.gd").attach(self, _args)


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


static func _expand(p: String) -> String:
	if p.begins_with("~/"):
		return OS.get_environment("HOME").path_join(p.trim_prefix("~/"))
	return p


func _env_from_arg(text: String) -> String:
	var t := text.to_lower()
	for e: Array in all_environments():
		if t == str(e[0]).to_lower() or t in e[3]:
			return e[0]
	return "void"


func _setup_view(want_xr: bool) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if want_xr and xr != null and xr.is_initialized():
		# The XR runtime paces frames; the window's vsync is left as it is. Asking for it off warned at every start on
		# the Frame ("not available", so it stayed on) and changed nothing: the eye images go to the runtime, not the window.
		get_viewport().use_xr = true
		# Foveation ([xr] in project.godot; the level is [view] foveation): the runtime's density map shapes the eye
		# images only with VRS XR. Set once: switching the viewport's VRS mode at run time left the eye images low
		# resolution all over, then unfoveated whatever the level, with odd distortions (2026-11-04).
		get_viewport().vrs_mode = Viewport.VRS_XR
		foveation_xr = xr
		foveation_live = false
		xr.connect("session_visible", _foveation_go_live)
		xr.connect("session_stopping", _foveation_hold)
		if xr.get_session_state() >= OpenXRInterface.SESSION_STATE_VISIBLE:
			_foveation_go_live.call_deferred()
		xr_camera.current = true
		camera = xr_camera
		use_xr = true
		if xr.has_signal("pose_recentered"):
			xr.connect("pose_recentered", recenter)
		# Session states, like the engine's own --verbose "On state ..." lines. Controller profiles are bound only once the
		# session is focused (headset worn); the hands time their "no profile" warning from then. Focus changes pause
		# and resume playback (on_session_state()).
		RoomParticles.hold()
		for state: String in ["session_begun", "session_synchronized", "session_visible", "session_focussed",
				"session_stopping", "session_loss_pending", "instance_exiting"]:
			if xr.has_signal(state):
				xr.connect(state, on_session_state.bind(state))
		print("View: XR, %s; action map %s" % [xr.get_system_info(), ProjectSettings.get_setting("xr/openxr/default_action_map")])
	else:
		flat_camera.current = true
		flat_camera.position = Vector3(0, FLAT_EYE_HEIGHT, 0)
		camera = flat_camera
		eye_height = FLAT_EYE_HEIGHT
		print("View: flat camera (keyboard and mouse)")


# --- Session focus: pause while the runtime's dashboard is up or the headset is off ----------------------------

## The XR session's state changed ("session_focussed", "session_visible", "session_synchronized", ...). Also called by
## the desktop test to simulate the runtime. Leaving FOCUSED (the dashboard opens: VISIBLE; the headset comes off:
## SYNCHRONIZED or stopping) pauses playback, audio and video together: our frame loop slows meanwhile while the audio
## clock runs on, and the video would drop frames to catch up. Back to FOCUSED resumes after AUTO_RESUME_DELAY (a
## quick dashboard flick doesn't stutter), but only if we paused it: a film the user paused stays paused.
func on_session_state(state: String) -> void:
	print("XR: %s (%.1f s)" % [state, Time.get_ticks_msec() / 1000.0])
	if state in ["session_visible", "session_focussed"] and not _particles_timed:
		_particles_timed = true
		get_tree().create_timer(RoomParticles.SAFE_AFTER).timeout.connect(RoomParticles.allow)
	var was_focused := session_focused
	session_focused = state == "session_focussed"
	if session_focused:
		for hand: XRHand in [left_hand, right_hand]:
			hand.focused_msec = Time.get_ticks_msec()
		if auto_paused:
			_resume_at_msec = Time.get_ticks_msec() + int(AUTO_RESUME_DELAY * 1000.0)
	elif was_focused and state in ["session_visible", "session_synchronized", "session_stopping",
			"session_loss_pending"]:
		_resume_at_msec = -1
		if player.is_playing() and player.has_source():
			_auto_toggle = true
			player.pause()
			_auto_toggle = false
			auto_paused = true
			print("Paused: the session lost focus (%s)" % state)


func _update_auto_resume() -> void:
	if _resume_at_msec < 0 or Time.get_ticks_msec() < _resume_at_msec:
		return
	_resume_at_msec = -1
	if auto_paused and session_focused:
		_auto_toggle = true
		player.play()
		_auto_toggle = false
		auto_paused = false
		print("Resumed: the session is focused again")


# --- Files and playlist ------------------------------------------------------------------------------------------

## Opens a file (or stub:// pattern). With update_playlist, the playlist becomes `siblings` when given (the browser
## passes the video files it lists, so network folders aren't listed again on the main thread), else the file's
## folder (the test patterns for stub://; just the file for smb://).
func open_path(path: String, update_playlist := true, siblings: Array[String] = []) -> void:
	current_path = path
	if update_playlist or playlist.find(path) < 0:
		if not siblings.is_empty():
			playlist = siblings.duplicate()
		elif path.begins_with("stub://"):
			playlist = VideoSourceFactory.list_videos("stub://")
		elif NetworkHosts.is_smb(path) or path.begins_with("http://") or path.begins_with("https://") \
				or path.begins_with("udp://") or WindowVideoSource.is_window_path(path) 				or path.begins_with("pcwindow://"):
			playlist = [path]
		elif LibraryIndex.is_inside(path) and VideoSourceFactory.is_video_file(path):
			# Episodes in order, and not the posters and thumbnails beside them.
			playlist = LibraryIndex.playlist_for(path)
		else:
			playlist = VideoSourceFactory.list_videos(path.get_base_dir())
	playlist_index = playlist.find(path)
	player.open(path)


## The gapless change (scripts/play/gapless.gd, ideas #44): `src`, chained behind the current file, took over at its
## end and plays; it becomes the open file as open_path() would make it, without the gap of opening. keep_old (picture
## in picture's swap, #87): the old source stays open and is returned.
func adopt_next(path: String, src: VideoSource, keep_old := false) -> VideoSource:
	current_path = path
	playlist_index = playlist.find(path)
	return player.adopt(src, keep_old)


func next_file() -> void:
	if playlist_index >= 0 and playlist_index + 1 < playlist.size():
		open_path(playlist[playlist_index + 1], false)


## Back to the start of the file if more than 3 s in, else the previous file.
func previous_file() -> void:
	if player.get_position() > 3.0 and player.can_seek():
		player.seek(0.0)
	elif playlist_index > 0:
		open_path(playlist[playlist_index - 1], false)


func _on_ended() -> void:
	if player.source is WindowVideoSource:
		# The window went away (or the browser never came): nothing more to show.
		screen.set_shown(false)
	elif features.queue.on_ended():
		# Repeat, or the queue going on (scripts/play/play_queue.gd, ideas #78).
		return
	if auto_advance and playlist_index + 1 < playlist.size():
		next_file()
	else:
		playback_ended.emit()


func _on_opened() -> void:
	var src := player.source
	_bind_textures(src)
	var remembered := settings.get_file_mode(current_path)
	var remembered_source := "file"
	if remembered == "" and src.get_kind() != "window":
		# A mode chosen elsewhere and written next to the file (scripts/play/sidecar.gd, ideas #60).
		remembered = Sidecar.read_mode(current_path)
		remembered_source = "sidecar"
	if remembered == "" and src.get_kind() != "window" and features != null:
		# The folder's rule (scripts/play/folder_modes.gd, ideas #83).
		remembered = features.folder_modes.mode_for(current_path)
		remembered_source = "folder"
	if src.get_kind() == "window":
		# A window is a flat 2D page: the pointer maps onto the flat screen only.
		mode = src.get_known_mode().copy()
		mode_source = "window"
	elif _args.has("mode"):
		mode_source = "arg"
		mode = _arg_mode()
	elif remembered != "":
		mode = VideoMode.from_id(remembered)
		mode_source = remembered_source
	elif src.get_known_mode() != null:
		mode = src.get_known_mode().copy()
		mode_source = "pattern"
	else:
		mode = _guessed_mode()
		mode_source = "metadata" if _container_mode()["mode"] != null else "auto"
	# A browser that is still starting, or a picture still decoding, has nothing to show yet: the screen shows once
	# there is (format_changed).
	screen.set_shown(src.has_frame() or not src.get_kind() in ["window", "image"])
	# An agent's terminal and an Android app stay out of the room snapshots for assistants.
	# So does a PC window (scripts/pc/pc_window_source.gd).
	screen.set_private((src.get_kind() == "window" and (src.is_terminal() or src.is_named()))
			or src.get_kind() == "pc")
	_apply_mode()
	# A PC window is there only while its pane is: nothing to open again at the next start.
	if src.get_kind() != "pc":
		settings.set_value("player", "last_file", current_path)
	_last_stats = {}
	_last_stats_msec = Time.get_ticks_msec()
	print("Opened %s (%d/%d in playlist): %s source, %s (%s)" % [current_path, playlist_index + 1, playlist.size(),
			src.get_kind(), mode.describe(), mode_source])
	if src.last_error != "":
		print("  note: %s" % src.last_error)
	file_opened.emit(current_path)


func _on_format_changed() -> void:
	var src := player.source
	if src == null:
		return
	_bind_textures(src)
	if src.has_frame() and not screen.is_shown():
		screen.set_shown(true)
	# Guesses that depend on the frame size are redone once the decoder knows it.
	if mode_source == "auto" or mode_source == "metadata":
		mode = _guessed_mode()
	elif mode_source == "arg":
		mode = _arg_mode()
	_apply_mode()
	print("Video format: %s, visible uv %s" % [src.get_video_info(), src.get_visible_uv_rect()])


## The source's picture on the screen: one RGB texture (a window) or the NV12 planes.
func _bind_textures(src: VideoSource) -> void:
	var rgb := src.get_rgb_texture()
	if rgb != null:
		screen.set_rgb_texture(rgb)
	else:
		screen.set_textures(src.get_plane_texture(0), src.get_plane_texture(1), src.is_p010())
	screen.set_visible_rect(src.get_visible_uv_rect())


## Stops what is on screen (the menu's "Stop showing" for a window): the source closes, which closes a browser window
## the player launched.
func close_media() -> void:
	player.close()
	screen.set_shown(false)
	screen.set_textures(null, null)
	current_path = ""
	playlist.clear()
	playlist_index = -1
	file_opened.emit("")


## What is on screen, for titles: the window's title, the page's URL, the file name or the test pattern.
func display_title() -> String:
	var src := player.source
	if src is WindowVideoSource:
		var title: String = (src as WindowVideoSource).get_title()
		return title if title != "" else WindowVideoSource.describe_path(current_path)
	if WindowVideoSource.is_window_path(current_path):
		return WindowVideoSource.describe_path(current_path)
	# A PC window's title stays in its pane (the header shows in the room snapshots).
	if current_path.begins_with("pcwindow://"):
		return tr("PC window")
	if LibraryIndex.is_inside(current_path):
		# Asked for many times a second: read once per file.
		if _library_title[0] != current_path:
			_library_title = [current_path, LibraryIndex.title_for(current_path)]
		if _library_title[1] != "":
			return _library_title[1]
	return current_path.get_file() if not current_path.begins_with("stub://") else current_path


## The UI layer asks before it resets a hand's laser: true while the hand points at a captured window.
func window_pointer_owns(hand: XRHand) -> bool:
	return window_pointer != null and window_pointer.owns_laser(hand)


# --- Modes -------------------------------------------------------------------------------------------------------

## Visible frame size, with non-square pixels (MediaSource's sample_aspect_ratio) folded into the width so the flat
## screen gets the display aspect.
func _frame_size() -> Vector2:
	if player.source == null:
		return Vector2.ZERO
	var info := player.source.get_video_info()
	var sar := float(info.get("sample_aspect_ratio", 1.0))
	if sar <= 0.0:
		sar = 1.0
	return Vector2(float(info.get("width", 0)) * sar, float(info.get("height", 0)))


## The mode without a user's or argument's choice: the source's own (test patterns), then the container's stereo /
## spherical metadata (scripts/play/container_mode.gd, ideas #25), then the guess from the file name and size.
func _guessed_mode() -> VideoMode:
	var size := _frame_size()
	if player.source != null and player.source.get_known_mode() != null:
		return player.source.get_known_mode().copy()
	var meta := _container_mode()
	if meta["mode"] != null:
		return meta["mode"]
	return VideoMode.guess(current_path.get_file(), int(size.x), int(size.y))


## {mode: VideoMode or null, reason} from the container's metadata.
func _container_mode() -> Dictionary:
	if player.source == null:
		return {"mode": null, "reason": ""}
	var size := _frame_size()
	return ContainerMode.from_info(player.source.get_video_info(), current_path.get_file(), int(size.x), int(size.y))


func _arg_mode() -> VideoMode:
	var size := _frame_size()
	var m := VideoMode.from_arg(str(_args["mode"]), int(size.x), int(size.y))
	if _args.has("fov"):
		m.fisheye_fov = float(_args["fov"])
	return m


func _apply_mode() -> void:
	screen.set_mode(mode, _frame_size())
	env_root.visible = not mode.is_spherical()
	_place_screen()
	var reason: String = _container_mode()["reason"]
	mode_changed.emit(mode, "Auto: " + _guessed_mode().describe() + (" (%s)" % reason if reason != "" else ""))


## A mode chosen by the user: applied and remembered for this file.
func set_video_mode(m: VideoMode, remember := true) -> void:
	mode = m.copy()
	mode_source = "user"
	if remember and current_path != "":
		settings.set_file_mode(current_path, mode.to_id())
	_apply_mode()


## Back to the guess (forgets a remembered mode).
func auto_mode() -> void:
	settings.set_file_mode(current_path, "")
	mode = _guessed_mode()
	mode_source = "metadata" if _container_mode()["mode"] != null else "auto"
	_apply_mode()


# --- Screen, environment, audio, overlay ---------------------------------------------------------------------------

## The built-in environments, then the rooms from scripts/env/env_library.gd (more built-in rooms, photo rooms, glTF
## rooms), then the scene recipes saved under user://recipes (scripts/dev/recipes.gd, docs/recipes.md), then the
## showrooms that ship with the app (scripts/env/showrooms.gd, docs/showrooms.md; always last: the Room tab groups
## them).
func all_environments() -> Array:
	return ENVIRONMENTS + EnvLibrary.environments() + Recipes.environments() + Showrooms.environments()


func get_environment_list() -> Array:
	var out: Array = []
	for e: Array in all_environments():
		out.append([e[0], e[1]])
	return out


func set_environment(id: String) -> void:
	var entry: Array = ENVIRONMENTS[0]
	for e: Array in all_environments():
		if e[0] == id:
			entry = e
	use_environment(EnvLibrary.instantiate(entry) as VREnvironment, entry[0])


## Shows an environment node made elsewhere (also the assistant's rooms, scripts/assistant/room_editor.gd) as `id`.
## keep_screen: the screen stays where it is (a preview of a change to this room); keep_old: the old environment is
## taken out but not freed, and returned (for an Undo). An id starting "assistant:" is never remembered.
func use_environment(node: VREnvironment, id: String, keep_screen := false, keep_old := false) -> VREnvironment:
	var old := env
	if env != null:
		env_root.remove_child(env)
		if not keep_old:
			env.queue_free()
	env = node
	env_root.add_child(env)
	env_id = id
	lift_room()
	room_light = float(settings.get_value("env_" + env_id, "light", room_light if keep_screen else 1.0))
	env.apply_light(room_light)
	if not keep_screen:
		var d := env.get_default_screen()
		var section := "screen_" + env_id
		# A placement saved against another default (the room rebuilt, its screen moved) is stale: the cinema's
		# screen hung four metres in front of the new stage (the user, 2026-11-04). It goes; the room's own stands.
		var made_for := str(settings.get_value(section, "room_default", ""))
		if made_for != "" and made_for != _screen_default_key(d):
			for k in ["width", "distance", "height_offset", "yaw", "room_default"]:
				settings.set_value(section, k, null)
		screen_width = float(settings.get_value(section, "width", d["width"]))
		screen_distance = float(settings.get_value(section, "distance", d["distance"]))
		screen_height_offset = float(settings.get_value(section, "height_offset", d["height_offset"]))
		screen_yaw = float(settings.get_value(section, "yaw", 0.0))
	_place_screen()
	if not env_id.begins_with("assistant:"):
		settings.set_value("view", "environment", env_id)
	environment_changed.emit(env_id, room_light)
	screen_changed.emit(screen_width, screen_distance, screen_height_offset)
	return old if keep_old else null


## The environment on show is now known as `id` (an assistant's room once kept): remembered, with this screen.
func adopt_environment_id(id: String) -> void:
	env_id = id
	settings.set_value("view", "environment", env_id)
	_save_screen_settings()
	settings.set_value("env_" + env_id, "light", room_light)
	environment_changed.emit(env_id, room_light)


func set_room_light(scale: float) -> void:
	room_light = scale
	env.apply_light(scale)
	settings.set_value("env_" + env_id, "light", scale)


## Flat screen: width, distance from the viewer, centre height above eye level (metres). Remembered per environment.
func set_screen(width: float, distance: float, height_offset: float) -> void:
	screen_width = clampf(width, 0.2, 40.0)
	screen_distance = clampf(distance, 0.5, 40.0)
	screen_height_offset = clampf(height_offset, -5.0, 10.0)
	_place_screen()
	_save_screen_settings()
	screen_changed.emit(screen_width, screen_distance, screen_height_offset)


## Everything back to the room's own layout: the room's own seat, the screen at its home in the room, the view
## recentred on the head. For when the screen and the room have drifted apart (a screen recentred to the gaze turns the
## screen but not the room, and can put it inside a wall; seen in the headset, 2026-10-31).
func reset_room() -> void:
	# An assistant's room with its own screen keeps the room: its default seat (else its own spot), the screen at the
	# room's home, the view recentred.
	if env != null and env.has_method("has_home_screen") and env.has_home_screen() and features != null \
			and features.seat != null:
		features.seat.choose_seat(int(env.get_default_seat()))
		features.seat.home_screen()
		recenter()
		return
	# Other assistant's rooms (scripts/assistant/assistant_room.gd) go back to the stock room they were built on.
	if env != null and str(env.get("base_id")) != "" and env.get("base_id") != null:
		set_environment(str(env.get("base_id")))
	if features != null and features.seat != null:
		features.seat.choose_seat(-1)
	reset_screen()
	recenter()


func reset_screen() -> void:
	var d := env.get_default_screen()
	screen_yaw = 0.0
	screen.sphere_yaw = 0.0
	set_screen(d["width"], d["distance"], d["height_offset"])


## The screen (or the sphere's front) to where the head looks, keeping its distance and height.
func recenter_screen_to_gaze() -> void:
	var look := -camera.global_basis.z
	var yaw := atan2(look.x, -look.z)
	if mode.is_spherical():
		screen.sphere_yaw = -yaw
	screen_yaw = yaw
	screen_turn = NAN
	_place_screen()
	_save_screen_settings()


func _save_screen_settings() -> void:
	var section := "screen_" + env_id
	settings.set_value(section, "width", snappedf(screen_width, 0.01))
	settings.set_value(section, "distance", snappedf(screen_distance, 0.01))
	settings.set_value(section, "height_offset", snappedf(screen_height_offset, 0.01))
	settings.set_value(section, "yaw", snappedf(screen_yaw, 0.001))
	if env != null:
		settings.set_value(section, "room_default", _screen_default_key(env.get_default_screen()))


## The room's own screen placement as a short key: a saved placement remembers the one it was made against.
static func _screen_default_key(d: Dictionary) -> String:
	return "%.2f %.2f %.2f" % [float(d.get("width", 0.0)), float(d.get("distance", 0.0)), float(d.get("height_offset", 0.0))]


## The room up or down so the viewer's eyes are at its seat's eye height (ROOM_EYE_HEIGHT above its floor): the
## screen is placed from the eyes, so without it a viewer whose eyes are higher (sitting tall, standing) sees the
## picture float above the room's telly (the user, 2026-11-07: TV 1930's picture well above the set). Not in the
## passthrough room (the real room), lying down (the pose places the screen), or off XR.
func lift_room() -> void:
	var lying := features != null and features.get("pose") != null and bool(features.pose.get("lying"))
	_lift = eye_height - ROOM_EYE_HEIGHT if use_xr and env_id != "passthrough" and not lying else 0.0
	var was := room_shift
	_apply_room_offset()
	if room_shift != was and screen != null and env != null:
		# Lying down or sitting up: the screen goes with the room.
		_place_screen()


## The room's place: the lift, and the seat shift for the seat in use (the screen's distance from it, so a seat
## change or a new room moves it again; the screen being pushed away or pulled near does not).
func _apply_room_offset() -> void:
	var lying := features != null and features.get("pose") != null and bool(features.pose.get("lying"))
	var shift := Vector3.ZERO
	if use_xr and env_id != "passthrough" and not lying and env != null and env.has_method("get_screen_anchor"):
		var a: Vector3 = env.transform * env.get_screen_anchor().origin
		var flat := Vector3(a.x, 0.0, a.z)
		var nearer := minf(flat.length() * SEAT_NEARER, SEAT_NEARER_MAX)
		shift = Vector3(0.0, -SEAT_RISE, 0.0) - (flat.normalized() * nearer if flat.length() > 0.01 else Vector3.ZERO)
	room_shift = shift
	env_root.position = Vector3(0.0, _lift, 0.0) + shift


## Puts the flat screen at screen_yaw / screen_distance / eye height + offset, facing the viewer; the overlay with it.
func _place_screen() -> void:
	_apply_room_offset()
	var pos := Vector3(sin(screen_yaw) * screen_distance, eye_height + screen_height_offset,
			-cos(screen_yaw) * screen_distance) + room_shift
	var t := Transform3D(Basis(Vector3.UP, -screen_yaw if is_nan(screen_turn) or mode.is_spherical() else screen_turn),
			pos)
	if screen_pose_override.is_valid():
		t = screen_pose_override.call(t)
	screen.transform = t
	screen.set_width(screen_width)
	if env != null:
		env.on_screen_changed(screen.transform, screen.get_flat_size())
	RenderingServer.global_shader_parameter_set("screen_center", t.origin)
	_place_overlay()


## Flat: under the screen's bottom-left corner, scaled with the distance. Spherical: low in front.
func _place_overlay() -> void:
	if mode.is_spherical():
		var yaw := screen_yaw
		var pos := Vector3(sin(yaw) * OVERLAY_SPHERE_DISTANCE, eye_height - OVERLAY_SPHERE_DROP,
				-cos(yaw) * OVERLAY_SPHERE_DISTANCE)
		overlay.transform = Transform3D(Basis(Vector3.UP, -yaw).scaled(Vector3.ONE * OVERLAY_SPHERE_DISTANCE * OVERLAY_SCALE_PER_METRE), pos)
		return
	var size := screen.get_flat_size()
	# About 20 degrees wide at the screen's distance, so its 24 px text is ~0.8 degrees tall in the headset.
	var s := clampf(screen_distance * OVERLAY_SCALE_PER_METRE, 0.5, 30.0)
	var local := Vector3(-size.x * 0.5 + InfoOverlay.WIDTH * 0.5 * s,
			-size.y * 0.5 - overlay.get_height() * 0.5 * s - 0.03 * s, 0.02)
	overlay.transform = screen.transform * Transform3D(Basis.from_scale(Vector3.ONE * s), local)


func recenter() -> void:
	if use_xr:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
		# The camera moves on the next frames; then take the eye height and put the screen in front again.
		_eye_height_frames = 3
	else:
		_look = Vector2.ZERO
		_apply_look()


func set_overlay(on: bool) -> void:
	overlay_on = on
	_update_overlay_visibility()
	_overlay_timer = 1.0
	settings.set_value("view", "overlay", on)
	audio_settings_changed.emit()


## The UI layer tells the core when its panel opens or closes. Open: the overlay hides (it draws on top of everything
## and would cover the panel's controls), and the controller labels switch to the panel's meanings.
func set_menu_shown(shown: bool) -> void:
	_overlay_suppressed = shown
	_update_overlay_visibility()
	if shown == menu_shown:
		return
	menu_shown = shown
	update_controller_labels()


## [view] foveation and foveation_sharp_panel (the System tab's Foveation row, D22). Unknown words read as "medium" (the default since 2026-11-09).
func load_foveation() -> void:
	var level := str(settings.get_value("view", "foveation", "medium"))
	foveation = level if level in FOVEATION_LEVELS else "medium"
	foveation_sharp_panel = bool(settings.get_value("view", "foveation_sharp_panel", true))


## level: one of FOVEATION_LEVELS. Applies at once (the runtime takes a new profile for the swapchain).
func set_foveation(level: String) -> void:
	if not level in FOVEATION_LEVELS:
		return
	foveation = level
	settings.set_value("view", "foveation", level)
	_update_foveation()
	audio_settings_changed.emit()


func set_foveation_sharp_panel(on: bool) -> void:
	foveation_sharp_panel = on
	settings.set_value("view", "foveation_sharp_panel", on)
	_update_foveation()
	audio_settings_changed.emit()


## [controllers] look and look_options (the System tab's Controllers section, the controller_look command). A look or
## options that no longer check out (a preset since renamed, a bound since narrowed) read as the default.
func load_controller_look() -> void:
	var initial: bool = settings.get_value("controllers", "look", null) == null
	var id := str(settings.get_value("controllers", "look", ControllerLook.INITIAL))
	var options: Variant = settings.get_value("controllers", "look_options",
			ControllerLook.INITIAL_OPTIONS if initial else {})
	if not ControllerLook.validate(id, options).is_empty():
		id = ControllerLook.DEFAULT
		options = {}
	controller_look = id
	controller_look_options = (options as Dictionary).duplicate(true)
	_apply_controller_look()


## Both controllers take a look (controller_look.gd LOOKS) with these options over the preset's; kept in the settings.
## Returns "" or what is wrong ("$.options.speed: 0..1"), and changes nothing then.
func set_controller_look(id: String, options := {}) -> String:
	var errors := ControllerLook.validate(id, options)
	if not errors.is_empty():
		return "; ".join(errors.map(func(e: Dictionary) -> String: return "%s: %s" % [e["path"], e["error"]]))
	controller_look = id
	controller_look_options = options.duplicate(true)
	# Nothing saved for the initial look (so a later change of the initial look reaches it); any other look,
	# black too, is saved.
	var initial := id == ControllerLook.INITIAL and options == ControllerLook.INITIAL_OPTIONS
	settings.set_value("controllers", "look", null if initial else id)
	settings.set_value("controllers", "look_options", null if initial or options.is_empty() else controller_look_options)
	_apply_controller_look()
	return ""


func _apply_controller_look() -> void:
	for hand in hands:
		hand.visual.set_look(controller_look, controller_look_options)


## The swapchain is foveated only if xr/openxr/foveation_level was above 0 at start; after that the level can change,
## but foveation can't be turned on for a swapchain made without it.
static func foveation_available() -> bool:
	return int(ProjectSettings.get_setting("xr/openxr/foveation_level", 0)) > 0


## The level to set (0 off to 3 High): `level`, except 0 while the panel or the agent pane is in front of the viewer and
## `sharp_panel` is on. At Low the sharp area is small enough that the edges of the panel's text soften; text is cheap
## to draw, so the saving isn't missed then.
static func foveation_choice(level: int, sharp_panel: bool, panel_shown: bool, pane_shown: bool) -> int:
	if sharp_panel and (panel_shown or pane_shown):
		return 0
	return clampi(level, 0, FOVEATION_LEVELS.size() - 1)


## Sets the runtime's foveation level from [view] foveation and the panel rule. Called with the controller labels,
## which change exactly when the panel or the agent pane opens or closes, and when either setting changes.
func _update_foveation() -> void:
	if foveation_xr == null or not "foveation_level" in foveation_xr or not foveation_available() \
			or not foveation_live:
		return
	var want := foveation_choice(FOVEATION_LEVELS.find(foveation), foveation_sharp_panel, menu_shown,
			local_agents != null and local_agents.pane_shown())
	if foveation_xr.foveation_level != want:
		foveation_xr.foveation_level = want


## The session is visible: the engine creates the eye swapchains on the frames that follow. A few frames later the
## level from the settings can apply (see foveation_live).
func _foveation_go_live() -> void:
	if foveation_live:
		return
	for i in 10:
		await get_tree().process_frame
	if foveation_live or foveation_xr == null:
		return
	foveation_live = true
	_update_foveation()


## The session ends: a new one makes new swapchains, so the level goes back to project.godot's until they exist.
func _foveation_hold() -> void:
	foveation_live = false
	if foveation_xr != null and foveation_available():
		foveation_xr.foveation_level = int(ProjectSettings.get_setting("xr/openxr/foveation_level", 1))


func _update_overlay_visibility() -> void:
	overlay.visible = overlay_on and not _overlay_suppressed


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	settings.set_value("audio", "volume", volume)
	audio_settings_changed.emit()


func set_av_offset(seconds: float) -> void:
	player.av_offset = seconds
	settings.set_value("audio", "av_offset", seconds)
	# Also for the display's refresh rate now (scripts/play/av_latency.gd, ideas #24).
	if features != null:
		features.latency.remember(seconds)
	audio_settings_changed.emit()


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func toggle_menu() -> void:
	if ui != null:
		ui.toggle_panel()


## The menu button of a controller (or null: the M / F3 key) pressed or released: the UI layer decides (a press opens,
## a short press closes, a hold recentres). Without the layer, a press does nothing.
func on_menu(hand: XRHand, pressed: bool) -> void:
	if ui != null:
		ui.on_menu(hand, pressed)


# --- Controllers -------------------------------------------------------------------------------------------------

func _on_trigger(hand: XRController3D, pressed: bool) -> void:
	# Holding an object: the trigger does nothing (scripts/play/object_grab.gd).
	if features != null and features.grab.on_trigger(hand, pressed):
		return
	if ui != null and ui.on_trigger(hand, pressed):
		return
	# On a PC window's pane: the left button there (scripts/pc/pc_windows.gd).
	if features != null and features.pc_windows.on_trigger(hand, pressed):
		return
	if local_agents.on_trigger(hand, pressed):
		return
	if window_pointer.on_trigger(hand as XRHand, pressed):
		return
	# Grip held + trigger in 180 / 360: the zoom lens (scripts/play/zoom_lens.gd, ideas #38).
	if features != null and features.zoom_lens.on_trigger(hand, pressed):
		return
	if pressed:
		player.toggle()
		(hand as XRHand).pulse()


func _on_grip(hand: XRController3D, pressed: bool) -> void:
	var h := hand as XRHand
	# Pointing at an object (or in one): the grip picks it up; letting go drops or throws it (object_grab.gd). Its
	# release goes there first, so nothing else keeps it.
	if features != null and features.grab.on_grip(h, pressed):
		_grip_down.erase(h)
		return
	if ui != null and ui.on_grip(h, pressed):
		return
	# On a PC window's pane: squeeze and hold moves it (scripts/pc/pc_windows.gd).
	if features != null and features.pc_windows.on_grip(h, pressed):
		_grip_down.erase(h)
		return
	# On an agent's terminal window: the same (scripts/agents/local_agents.gd).
	if local_agents.on_grip(h, pressed):
		_grip_down.erase(h)
		return
	# Squeeze no longer moves the screen or turns it to the gaze (the user, in the headset, 2026-10-31: the Room and
	# Picture controls and Reset room do that in terms of the room). A quick squeeze is still a right click on a
	# captured window; a held squeeze is the zoom lens's modifier in 180 / 360 (zoom_lens.gd reads it itself).
	if pressed:
		_grip_down[h] = Time.get_ticks_msec()
	elif _grip_down.has(h):
		if Time.get_ticks_msec() - int(_grip_down[h]) < GRIP_TAP_MSEC:
			window_pointer.on_grip_tap(h)
		_grip_down.erase(h)


func _start_grab(ray: Callable, hand: XRHand) -> void:
	var r: Array = ray.call()
	_grab = {"ray": ray, "hand": hand, "distance": maxf((r[0] as Vector3).distance_to(screen.global_position), 0.5),
			"yaw": _ray_yaw(r[1]), "start_dir": r[1], "start_msec": Time.get_ticks_msec()}


func _end_grab() -> void:
	_grab = {}
	_save_screen_settings()
	screen_changed.emit(screen_width, screen_distance, screen_height_offset)


static func _ray_yaw(dir: Vector3) -> float:
	return atan2(dir.x, -dir.z)


func _update_grab(delta: float) -> void:
	var r: Array = (_grab["ray"] as Callable).call()
	var origin: Vector3 = r[0]
	var dir: Vector3 = r[1]
	if Time.get_ticks_msec() - int(_grab["start_msec"]) < GRIP_TAP_MSEC and dir.angle_to(_grab["start_dir"]) < GRIP_TAP_ANGLE:
		return  # Maybe a tap: don't move anything yet.
	if mode.is_spherical():
		# Turn the sphere with the hand's horizontal swing.
		var yaw := _ray_yaw(dir)
		screen.sphere_yaw -= wrapf(yaw - float(_grab["yaw"]), -PI, PI)
		_grab["yaw"] = yaw
		return
	var hand: XRHand = _grab.get("hand")
	if hand != null:
		# The stick while gripping (the user, 2026-11-08): left / right smaller or bigger, up / down further or nearer;
		# the stronger direction only, so a diagonal push does one thing.
		var stick := hand.get_stick()
		if absf(stick.x) > 0.25 and absf(stick.x) >= absf(stick.y):
			screen_width = clampf(screen_width * (1.0 + stick.x * delta * 1.2), 0.2, 40.0)
		elif absf(stick.y) > 0.25:
			_grab["distance"] = clampf(float(_grab["distance"]) * (1.0 + stick.y * delta * 1.5), 0.5, 30.0)
	var p := origin + dir * float(_grab["distance"]) - room_shift
	screen_yaw = atan2(p.x, -p.z)
	screen_distance = clampf(Vector2(p.x, p.z).length(), 0.5, 30.0)
	screen_height_offset = clampf(p.y - eye_height, -3.0, 6.0)
	_place_screen()
	screen_changed.emit(screen_width, screen_distance, screen_height_offset)


func _update_sticks(delta: float) -> void:
	for hand in hands:
		# Sticks and buttons work whether or not the pose is tracked.
		if _grab.get("hand") == hand:
			continue
		var stick := hand.get_stick()
		# Holding an object: the stick brings it nearer or further and turns it (object_grab.gd).
		if features != null and features.grab.on_stick(hand, stick, delta):
			_seek_hold[hand] = -1.0
			continue
		# Holding a PC window's pane: the stick makes it bigger or smaller (scripts/pc/pc_windows.gd).
		if features != null and features.pc_windows.on_stick(hand, stick, delta):
			_seek_hold[hand] = -1.0
			continue
		if (ui != null and ui.on_stick(hand, stick, delta)) or local_agents.on_stick(hand, stick, delta) \
				or window_pointer.on_stick(hand, stick, delta):
			_seek_hold[hand] = -1.0
			continue
		# A circle round the rim scrubs (scripts/play/jog_wheel.gd, ideas #63); it hands flicks and pushes back.
		if features != null and features.jog.on_stick(hand, stick, delta):
			_seek_hold[hand] = -1.0
			continue
		# Held right: scan at 4x, then 8x (scripts/play/trick_play.gd, ideas #46); a tap still skips 10 s below.
		if features != null and features.trick.on_stick(hand, stick, delta):
			_seek_hold[hand] = -1.0
			continue
		_stick_seek(hand, stick.x, delta)
		if absf(stick.y) > 0.25 and not mode.is_spherical():
			# Up = further away.
			set_screen(screen_width, screen_distance * (1.0 + stick.y * DISTANCE_RATE * delta), screen_height_offset)


## Left/right past 0.75 seeks 10 s, then again every SEEK_REPEAT seconds while held.
func _stick_seek(key: Variant, x: float, delta: float) -> void:
	var hold: float = _seek_hold.get(key, -1.0)
	if absf(x) > 0.75:
		if hold < 0.0 or hold >= SEEK_REPEAT:
			player.seek_relative(SEEK_STEP * signf(x))
			hold = 0.0
		hold += delta
	else:
		hold = -1.0
	_seek_hold[key] = hold


# --- Controller labels -------------------------------------------------------------------------------------------

## The menus' language changed (scripts/i18n.gd): the legends in it.
func _on_language_changed(_code: String) -> void:
	if is_node_ready():
		update_controller_labels()


## Sets each controller's label texts from CONTROL_LABELS and the bindings of the profile the runtime bound for it
## (menu shown or not). Called when a profile changes and when the menu shows / hides, never per frame.
func update_controller_labels() -> void:
	_update_foveation()
	var on_window := window_pointer != null and window_pointer.is_active()
	var terminal := local_agents != null and (local_agents.waiting() and local_agents.pane_shown()
			or local_agents.looking() or local_agents.on_big_screen())
	var enter := local_agents != null and local_agents.enter_ready()
	_grab_labelled = features != null and features.physics.available()
	# The stick pointer's mode: pointer (looking at the screen) or away (scripts/window_pointer.gd).
	var window_texts: Dictionary = window_pointer.window_labels() if on_window else {}
	for hand in hands:
		var side := "left" if hand == left_hand else "right"
		var holding := features != null and features.grab.holding(hand) != ""
		var applying: bool = ui != null and ui.is_applying() and hand == ui.pointer_hand
		var texts := controller_labels(hand.profile if use_xr else PREVIEW_PROFILE, side, menu_shown, on_window,
				terminal, _grab_labelled, holding, window_texts, applying, enter)
		if ui != null and ui.talk_hand() == hand and texts.has("bumper"):
			texts["bumper"] = tr("TALK")
		hand.visual.set_texts(texts)
		hand.visual.set_print_state("menu" if menu_shown else ("window" if on_window else "normal"))
		hand.visual.set_input_bindings(_profile_bindings(hand.profile if use_xr else PREVIEW_PROFILE, side))


## The labels are always printed, so holding the "labels" button only counts as the left bumper of the snapshot chord
## (left bumper + A).
func set_labels_held(holder: Variant, held: bool) -> void:
	if held:
		_labels_holders[holder] = true
	else:
		_labels_holders.erase(holder)


## input (controller_visual.gd anchor name) -> label text, for one hand of `profile`. on_window: a captured window
## has the input (menu hidden), WINDOW_LABELS apply; terminal: an agent's terminal has it, TERMINAL_LABELS apply.
## grab: the room has objects to pick up (the squeeze says GRAB_LABEL, menu hidden); holding: this controller holds
## one, HOLD_LABELS apply (over everything else). window_texts: the window's legends for its mode now
## (WINDOW_POINTER_LABELS or WINDOW_AWAY_LABELS, window_pointer.gd's window_labels()); {}: WINDOW_LABELS.
## enter: an agent's terminal shows, X is Enter (ENTER_LABEL), the menu open or not.
static func controller_labels(profile: String, side: String, p_menu_shown: bool, on_window := false,
		terminal := false, grab := false, holding := false, window_texts := {}, applying := false,
		enter := false) -> Dictionary:
	var out := {}
	var window_map: Dictionary = window_texts if not window_texts.is_empty() else WINDOW_LABELS
	for b: Array in _profile_bindings(profile, side):
		var texts: Array = CONTROL_LABELS.get(b[1], [])
		if texts.is_empty():
			continue
		var legend := str(texts[1 if p_menu_shown else 0])
		if on_window and not p_menu_shown:
			if side == "left" and b[1] in WINDOW_LEFT_HIDDEN:
				continue
			if side == "right" and window_map.has(b[1]):
				legend = window_map[b[1]]
		if terminal and not p_menu_shown and side == "right" and TERMINAL_LABELS.has(b[1]):
			legend = TERMINAL_LABELS[b[1]]
		if grab and not p_menu_shown and not on_window and not terminal and b[1] == "squeeze":
			legend = GRAB_LABEL
		if holding and HOLD_LABELS.has(b[1]):
			legend = HOLD_LABELS[b[1]]
		if applying and APPLY_LABELS.has(b[1]):
			legend = APPLY_LABELS[b[1]]
		if enter and b[1] == "enter":
			legend = ENTER_LABEL
		# Last: an action with no legend of its own can have one on a window or a terminal.
		if legend == "":
			continue
		# In the menus' language (docs/i18n.md); English when none is loaded.
		legend = TranslationServer.translate(legend)
		var text: String = TranslationServer.translate("PUSH: %s") % legend if b[2] else legend
		out[b[0]] = text if not out.has(b[0]) else str(out[b[0]]) + "\n" + text
	return out


## [[input, action, press], ...] for the bindings of `profile` on one hand, from the action map (cached). press: a
## click on an input that also has a non-click binding (the thumbstick).
static func _profile_bindings(profile: String, side: String) -> Array:
	var key := profile + "|" + side
	if _binding_cache.has(key):
		return _binding_cache[key]
	var out: Array = []
	var map := load(str(ProjectSettings.get_setting("xr/openxr/default_action_map"))) as OpenXRActionMap
	var ip: OpenXRInteractionProfile = map.find_interaction_profile(profile) if map != null and profile != "" else null
	if ip != null:
		var prefix := "/user/hand/%s/input/" % side
		for i in ip.get_binding_count():
			var binding := ip.get_binding(i)
			if binding.action == null or not binding.binding_path.begins_with(prefix):
				continue
			var parts := binding.binding_path.trim_prefix(prefix).split("/")
			var input: String = INPUT_ALIASES.get(parts[0], parts[0])
			if side == "left" and input in ["a", "b"] and parts[0] in ["primary", "secondary"]:
				input = "x" if input == "a" else "y"
			out.append([input, binding.action.resource_name, input == "thumbstick" and parts.size() > 1 and parts[1] == "click"])
	_binding_cache[key] = out
	return out


# --- Desktop input -----------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Typing into a text field of the menu (desktop keyboard) goes to the menu, not to the shortcuts.
	if event is InputEventKey and ui != null and ui.on_key(event as InputEventKey):
		return
	# A PC connected: the mouse paired with the headset moves the PC windows' cursor, and the keys go to the pane in
	# focus (scripts/pc/pc_windows.gd).
	if features != null and features.pc_windows.on_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if local_agents.on_key(key) or window_pointer.on_key(key):
			pass
		elif key.pressed and not key.echo:
			_on_key(key)
		elif not key.pressed and key.keycode == KEY_G and not _grab.is_empty():
			_end_grab()
		elif not key.pressed and key.keycode in [KEY_M, KEY_F3]:
			on_menu(null, false)
	elif (event is InputEventMouseButton or event is InputEventMouseMotion) and not use_xr:
		_on_mouse(event as InputEventMouse)


func mouse_ray(pos: Vector2) -> Array:
	return [flat_camera.project_ray_origin(pos), flat_camera.project_ray_normal(pos)]


func _on_mouse(event: InputEventMouse) -> void:
	if ui != null and not _mouse_look and ui.on_mouse(event, mouse_ray(event.position)):
		return
	if not _mouse_look and window_pointer.on_mouse(event, mouse_ray(event.position)):
		return
	if event is InputEventMouseMotion:
		if _mouse_look:
			_look += Vector2((event as InputEventMouseMotion).relative.x, -(event as InputEventMouseMotion).relative.y) * 0.15
			_apply_look()
		return
	var button := event as InputEventMouseButton
	match button.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			# Drag on the scene to look around.
			_mouse_look = button.pressed
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed and not _grab.is_empty():
				var steps := 1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				_grab["distance"] = clampf(float(_grab["distance"]) * (1.0 + 0.08 * steps), 0.5, 30.0)


func _apply_look() -> void:
	_look.y = clampf(_look.y, -89.0, 89.0)
	flat_camera.rotation = Vector3(deg_to_rad(_look.y), -deg_to_rad(_look.x), 0.0)


func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_SPACE, KEY_K:
			player.toggle()
		KEY_LEFT, KEY_J:
			player.seek_relative(-SEEK_STEP)
		KEY_RIGHT, KEY_L:
			player.seek_relative(SEEK_STEP)
		KEY_UP:
			set_screen(screen_width, screen_distance * 1.1, screen_height_offset)
		KEY_DOWN:
			set_screen(screen_width, screen_distance / 1.1, screen_height_offset)
		KEY_N:
			next_file()
		KEY_P:
			previous_file()
		KEY_M, KEY_F3:
			on_menu(null, true)
		KEY_ESCAPE:
			if ui != null:
				ui.hide_panel()
		KEY_TAB, KEY_F1:
			set_overlay(not overlay_on)
		KEY_R:
			reset_room()
		KEY_V:
			var m := mode.copy()
			m.projection = ((int(m.projection) + 1) % VideoMode.Proj.size()) as VideoMode.Proj
			set_video_mode(m)
		KEY_O:
			var m := mode.copy()
			m.layout = ((int(m.layout) + 1) % VideoMode.Layout.size()) as VideoMode.Layout
			set_video_mode(m)
		KEY_H:
			var m := mode.copy()
			m.half = not m.half
			set_video_mode(m)
		KEY_X:
			var m := mode.copy()
			m.swap = not m.swap
			set_video_mode(m)
		KEY_E:
			var envs := all_environments()
			var i := 0
			for k in envs.size():
				if envs[k][0] == env_id:
					i = k
			set_environment(envs[(i + 1) % envs.size()][0])
		KEY_G:
			if player.source != null and _grab.is_empty() and not use_xr:
				_start_grab(func() -> Array: return mouse_ray(get_viewport().get_mouse_position()), null)
		KEY_F12:
			if snapshots != null:
				snapshots.take()
			else:
				_save_screenshot("user://screenshot_%d.png" % Time.get_unix_time_from_system())


# --- Frame loop --------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_frames += 1
	if use_xr and _frames == 3:
		recenter()
	if _eye_height_frames > 0:
		_eye_height_frames -= 1
		if _eye_height_frames == 0:
			eye_height = maxf(xr_camera.global_position.y, 0.5)
			lift_room()
			_place_screen()
			print("Recentered; eye height %.2f m" % eye_height)

	_update_auto_resume()
	if use_xr:
		_update_sticks(delta)
	if not _grab.is_empty():
		_update_grab(delta)

	if overlay.visible:
		_overlay_timer += delta
		if _overlay_timer >= 0.25:
			_overlay_timer = 0.0
			overlay.set_text(_overlay_text())
	_save_timer += delta
	if _save_timer >= 1.0:
		_save_timer = 0.0
		settings.save_if_dirty()

	if _args.has("screenshot") and _frames == int(_args.get("screenshot-frame", 90)):
		_save_screenshot(_expand(str(_args["screenshot"])))
	if _args.has("quit-after") and _frames >= int(_args["quit-after"]):
		print("Quitting after %d frames" % _frames)
		get_tree().quit()


static func _format_time(t: float) -> String:
	var s := maxi(0, int(t))
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _overlay_text() -> String:
	var lines: Array[String] = []
	var src := player.source
	var battery_text := features.battery_text()
	if src == null:
		if player.connecting_path != "":
			lines.append(player.connecting_path.get_file())
			lines.append("Connecting to %s ..." % NetworkHosts.host_of(player.connecting_path))
		else:
			lines.append("No file open")
		lines.append("%s  |  %s" % [env.display_name if env else "-", battery_text])
		return "\n".join(lines)
	var title := display_title()
	if src.get_kind() == "window":
		return _window_overlay_text(src, title, battery_text)
	if playlist.size() > 1:
		title += "  (%d/%d)" % [playlist_index + 1, playlist.size()]
	lines.append(title)
	var info := src.get_video_info()
	var stats := src.get_stats()
	# The decode path: "hardware (10-bit)" while a 10-bit file plays in hardware (scripts/play/hw_video.gd).
	lines.append("%s  [%s]  |  %s %dx%d" % [mode.describe(), mode_source,
			HwVideo.decode_text(src.get_kind(), info, stats), int(info.get("width", 0)),
			int(info.get("height", 0))])
	lines.append("%s / %s  %s  %s" % [_format_time(player.get_position()), _format_time(player.get_duration()),
			features.end_text(),
			"playing" if player.is_playing() else ("paused (headset not in focus)" if auto_paused else "paused")])
	var feature_status := features.status_line()
	if feature_status != "":
		lines.append(feature_status)
	var now := Time.get_ticks_msec()
	var seconds := maxf((now - _last_stats_msec) / 1000.0, 0.001)
	var decoded := maxi(0, int(stats.get("frames_decoded", 0)) - int(_last_stats.get("frames_decoded", 0)))
	lines.append("decode %.1f fps | dropped %d | render %d fps" % [decoded / seconds, int(stats.get("frames_dropped", 0)),
			Engine.get_frames_per_second()])
	if bool(stats.get("network", false)):
		lines.append("network %.1f Mbit/s | buffered %.1f MB | stalls %d | reconnects %d" % [
				float(stats.get("net_average_mbps", 0.0)), float(stats.get("net_buffered_bytes", 0)) / 1e6,
				int(stats.get("net_stalls", 0)), int(stats.get("net_reconnects", 0))])
	lines.append("%s  |  %s" % [battery_text, env.display_name if env else "-"])
	if src.last_error != "":
		lines.append(src.last_error)
	_last_stats = stats
	_last_stats_msec = now
	return "\n".join(lines)


## The overlay for a captured window: capture path, picture updates and damage events a second, fetch cost.
func _window_overlay_text(src: VideoSource, title: String, battery_text: String) -> String:
	var lines: Array[String] = [title]
	var info := src.get_video_info()
	var stats := src.get_stats()
	var now := Time.get_ticks_msec()
	var seconds := maxf((now - _last_stats_msec) / 1000.0, 0.001)
	lines.append("%s  [%s]  |  window %dx%d" % [mode.describe(), mode_source, int(info.get("width", 0)),
			int(info.get("height", 0))])
	if src.is_ended():
		lines.append(src.last_error)
	elif not src.has_frame():
		lines.append("Starting the browser ...")
	else:
		var updates := maxi(0, int(stats.get("frames_updated", 0)) - int(_last_stats.get("frames_updated", 0)))
		var damage := maxi(0, int(stats.get("damage_events", 0)) - int(_last_stats.get("damage_events", 0)))
		lines.append("capture %s%s | %.1f updates/s | damage %.1f/s | fetch %.2f ms avg" % [stats.get("mode", "?"),
				" (zero copy)" if bool(stats.get("zero_copy", false)) else " (copy)", updates / seconds,
				damage / seconds, float(stats.get("fetch_ms_avg", 0.0))])
		lines.append("render %d fps | input events %d" % [Engine.get_frames_per_second(),
				int(stats.get("input_events", 0))])
	lines.append("%s  |  %s" % [battery_text, env.display_name if env else "-"])
	_last_stats = stats
	_last_stats_msec = now
	return "\n".join(lines)


# --- Screenshots -------------------------------------------------------------------------------------------------

## Both eyes (as the flat camera sees the scene), side by side, each eye_width pixels wide.
func capture_eyes(eye_width := 640) -> Image:
	var shots: Array[Image] = []
	for eye in [0, 1]:
		screen.set_force_eye(eye)
		overlay.set_force_eye(eye)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(eye_width, roundi(eye_width * float(img.get_height()) / img.get_width()), Image.INTERPOLATE_LANCZOS)
		shots.append(img)
	screen.set_force_eye(-1)
	overlay.set_force_eye(-1)
	var h := shots[0].get_height()
	var out := Image.create_empty(eye_width * 2 + 4, h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.5, 0.5, 0.5))
	out.blit_rect(shots[0], Rect2i(0, 0, eye_width, h), Vector2i.ZERO)
	out.blit_rect(shots[1], Rect2i(0, 0, eye_width, h), Vector2i(eye_width + 4, 0))
	return out


func _save_screenshot(path: String) -> void:
	var img: Image = await capture_eyes()
	var err := img.save_png(path)
	print("Screenshot %s (%dx%d): %s" % [path, img.get_width(), img.get_height(), error_string(err)])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		settings.save_if_dirty()


func _exit_tree() -> void:
	player.close()
	# Let go of the plane textures so nothing outlives the video.
	screen.set_textures(null, null)
