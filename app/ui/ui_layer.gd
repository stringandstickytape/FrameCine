extends Node3D

## The UI layer: the menu, on the tablet (ui/tablet.gd; the user, 2026-11-06: the front panel, the first UI, is
## gone). It talks to the app (scripts/main.gd)
## only through the app's public functions, signals and its features hub, and the app works without it (delete the
## UILayer node from main.tscn: direct controller bindings and command-line arguments still drive everything).
##
## The panel is closed or open; nothing else. The menu button on either controller opens it on the tablet, which
## is placed from the head (below and in front of the eyes, tilted up to them; Tablet.pose()) and then stays there in
## the room. Menu again closes it. Held for [pane] recentre_hold seconds while open, the menu button brings it back in
## front of the head instead. The
## controller whose menu button opened it is the pointer: its laser aims, its trigger clicks, its stick scrolls the
## list or nudges the slider under the laser, and with the laser off the panel its stick moves a focus highlight and
## its trigger activates it, so aiming is never needed. One controller is enough; where the other one is never
## matters. At launch the panel is open with the right controller as the pointer ([accessibility] left_handed: the
## left), and if the pointer controller isn't tracked while the other one is, the other one takes over.
##
## Pointer rules: the laser shows only while it is aimed at the panel (token colours, a dot at the hit point). Hover
## gives the theme's highlight and one haptic tick per new target. Trigger clicks. Either stick scrolls what is under
## the laser. Poking the panel with the pointer controller's tip clicks too. With the panel closed, the controllers
## keep their direct bindings (main.gd).
##
## The app asks the layer first for pointer-like input: on_menu(), on_trigger(), on_stick(), on_grip(), on_key(),
## on_mouse() return true when the panel used the input.
##
## For other agents: show_panel(hand = null) opens it in front of the head (also when open: a recentre),
## hide_panel() closes it, toggle_panel(), recentre(), is_open(), reload_theme(). `docked` is kept as an alias of
## is_open() (the panel used to have a docked state; now that is the only one). `panel` is the quad (ui/pane.gd), `ui`
## its controls (ui/pane_ui.gd).
##
## The tablet shows and hides with the panel, placed from the head whenever the panel is; the panel (the menu) is on
## its main pane. The laser on the tablet's time bar shows the seek bar's picture there (Tablet.hover_bar()).

const Pane := preload("res://ui/pane.gd")
const PaneUI := preload("res://ui/pane_ui.gd")
const PanePose := preload("res://ui/pane_pose.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const XRHand := preload("res://scripts/xr/xr_hand.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const DevHost := preload("res://scripts/dev/dev_host.gd")
const W := preload("res://ui/pane_widgets.gd")
const ControllerBattery := preload("res://scripts/xr/controller_battery.gd")
const WorldToast := preload("res://ui/world_toast.gd")
const HandHint := preload("res://ui/hand_hint.gd")
const WatchCard := preload("res://ui/watch_card.gd")
const Assistant := preload("res://scripts/assistant/assistant.gd")
const I18n := preload("res://scripts/i18n.gd")
## The header lists the controller batteries at or below this.
const CONTROLLER_BATTERY_HEADER := 20

## Layout defaults, tunable in the headset (System, Panel; [pane] recentre_hold). The menu's text also follows the
## accessibility UI scale (features.access, #74, "Larger panel").
const LAYOUT_DEFAULTS := {"recentre_hold": PanePose.RECENTRE_HOLD}
const STICK_SCROLL_RATE := 10.0
## The stick's smooth scroll: pixels a second at full stick, past STICK_SCROLL_DEAD, rising as the push's
## STICK_SCROLL_CURVE power (a light push creeps, a full one runs).
const STICK_SCROLL_SPEED := 1100.0
const STICK_SCROLL_DEAD := 0.2
const STICK_SCROLL_CURVE := 1.6
## Stick focus: past this deflection, one step, then repeats.
const FOCUS_STICK := 0.6
const FOCUS_REPEAT_FIRST := 0.4
const FOCUS_REPEAT := 0.18
## Poke: the tip this close to the panel's front presses, this far releases.
const POKE_PRESS := 0.008
const POKE_RELEASE := 0.02
## Grip held this long with the laser on the panel: remote changes allowed for an hour (dev mode).
const GRIP_ALLOW_SECONDS := 2.0
## The first frames in XR have no head pose yet: the launch panel is placed again until then.
const LAUNCH_REPLACE_SECONDS := 0.6

## scripts/main.gd
var app: Node3D
var panel: Pane
var ui: PaneUI
## The controller that points at the panel (the one whose menu button opened it), and the other one.
var pointer_hand: XRHand
var other_hand: XRHand
## Kept for older callers: the panel is open (it used to be "docked in front").
var docked: bool:
	get:
		return _open
## The menu button's press and hold (the hold from the settings, apply_layout()).
var menu := PanePose.MenuPress.new()
var _open := false
## The left_handed value the pointer was last set from (a change picks the pointer again).
var _left_handed_applied: Variant = null
var _pointed := false
var _hit := {}
var _replace_left := 0.0
var _hover: Control
var _scroll_acc := {}
var _focus_dir := Vector2i.ZERO
var _focus_wait := 0.0
var _poke_down := false
## The tablet (ui/tablet.gd): what the pointer's ray hits on it ({} for nothing); the hand dragging its bar, and how
## ("trigger" or "touch").
var _tablet_hit := {}
var _scrub_hand: XRHand
var _scrub_by := ""
var _grip_held := -1.0
var _refresh_timer := 0.0
## A network file was picked: close once it is open.
var _hide_on_open := false
## A page or window was picked: close once the window is captured (the browser takes seconds).
var _hide_on_window := false
var _title := ""
## Controller batteries (#75) and the quiet world toast for warnings while the panel is closed.
var controller_battery: ControllerBattery
var world_toast: WorldToast
## The steps of marking or editing a window to the real room, over the pointer controller (ui/hand_hint.gd).
var hand_hint: HandHint
## The watch-along card beside the screen (#54); the laser and the trigger dismiss it.
var card: WatchCard
var _card_pointed := false
var _card_hit := {}
## Push-to-talk (#14, scripts/dev/push_to_talk.gd), there only while the dev link is on; looked up once a second.
var _ptt: Node
var _ptt_check := 0.0
var _talking := false
## The header's extra items: low controller batteries (from the last levels: side -> percent), and "Assistant" while
## the assistant link is connected.
var _battery_levels := {}
var _assistant: Node
## Seat picking (#19, the Room tab's "Pick a seat"): the laser goes out to the floor; the seat the ray passes nearest
## (within SEAT_AIM metres of it) gets a ring on the floor; the trigger takes it; B or menu cancels.
## The aimed seat: {index, point, distance} or {}.
const SEAT_AIM := 0.6
const SEAT_RING_RADIUS := 0.32
var _seat_pick := false
var _seat_aim := {}
var _seat_ring: MeshInstance3D
## Placing or moving a library object (the Room tab's Place and Move): ui/object_placer.gd, made on first use. Like
## seat picking, it takes the laser, the trigger and the pointer controller's stick; B or menu cancels.
var _placer: ObjectPlacer
const ObjectPlacer := preload("res://ui/object_placer.gd")
const Tablet := preload("res://ui/tablet.gd")
var tablet: Tablet


## Called by the app once its nodes are ready.
func setup(p_app: Node3D) -> void:
	app = p_app
	PaneStyle.use(str(app.settings.get_value("pane", "theme", PaneStyle.DEFAULT_PATH)))
	panel = Pane.new()
	panel.name = "Pane"
	add_child(panel)
	ui = panel.ui
	ui.bind(app)
	tablet = Tablet.new()
	tablet.name = "Tablet"
	tablet.app = app
	add_child(tablet)
	apply_layout()
	tablet.layout_changed.connect(apply_tablet)
	apply_tablet()
	ui.system.layout_changed.connect(apply_layout)
	ui.system.reset_layout_requested.connect(reset_layout)
	ui.system.reload_theme_requested.connect(reload_theme)
	app.features.access.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "left_handed":
			apply_layout()
		elif key == "ui_scale":
			apply_tablet())

	# Pane -> app.
	var files := ui.files
	files.file_selected.connect(_on_file_selected)
	app.player.opened.connect(func() -> void:
		if _hide_on_open:
			_hide_on_open = false
			hide_panel())
	files.folder_changed.connect(func(p: String) -> void: app.settings.set_value("browser", "last_folder", p))
	files.close_requested.connect(func() -> void:
		_hide_on_window = false
		app.close_media())
	ui.play_pause_pressed.connect(func() -> void: app.player.toggle())
	ui.previous_requested.connect(func() -> void: app.previous_file())
	ui.next_requested.connect(func() -> void: app.next_file())
	ui.skip_requested.connect(func(d: float) -> void: app.player.seek_relative(d))

	# App -> pane.
	app.file_opened.connect(_on_file_opened)
	app.mode_changed.connect(func(_m: VideoMode, _t: String) -> void: ui.tick())
	app.player.playing_changed.connect(func(_p: bool) -> void: _refresh())
	app.playback_ended.connect(show_panel)
	var f: Node = app.features
	f.resume.resumed.connect(func(position_s: float) -> void:
		ui.show_toast(tr("Resumed at %s") % W.clock(position_s), tr("Start over"), func() -> void: f.resume.start_over()))
	f.resume.entries_changed.connect(func() -> void: ui.files.refresh_markers())
	_connect_dev.call_deferred()
	card = WatchCard.new()
	card.name = "WatchCard"
	card.app = app
	add_child(card)
	card.register_commands()
	hand_hint = HandHint.new()
	add_child(hand_hint)
	world_toast = WorldToast.new()
	world_toast.name = "WorldToast"
	world_toast.head = app.camera
	add_child(world_toast)
	controller_battery = ControllerBattery.new()
	controller_battery.name = "ControllerBattery"
	add_child(controller_battery)
	controller_battery.low.connect(func(side: String, pct: int) -> void:
		notify(_battery_notice(side, pct)))
	controller_battery.changed.connect(func(levels: Dictionary) -> void:
		_battery_levels = levels.duplicate()
		_update_header_extra())
	I18n.holder().changed.connect(_on_language_changed)

	files.open_folder(str(app.settings.get_value("browser", "last_folder", "")))


## The dev tools come up a frame after the app (dev_host.gd); their remote changes toast here with Undo.
func _connect_dev() -> void:
	var dev := DevHost.instance()
	if dev == null or dev.get("permissions") == null:
		return
	dev.permissions.remote_change.connect(func(e: Dictionary) -> void:
		if str(e.get("state", "")) == "done":
			var id := int(e["id"])
			ui.show_toast(tr("Remote: %s") % e["summary"], tr("Undo") if bool(e.get("undoable", false)) else "",
					func() -> void: dev.permissions.undo(id), 8.0))


func _on_file_selected(p: String) -> void:
	# The folder on show is the playlist (no second listing, which matters on network shares).
	app.open_path(p, true, ui.files.get_video_paths())
	# A network file connects first: the panel stays (saying "Connecting...") until it is open. The same for a
	# browser window ("Starting the browser...").
	var src = app.player.source
	if not _open:
		return
	if WindowVideoSource.is_window_path(p) and src != null and not src.has_frame() and not src.is_ended():
		_hide_on_window = true
		_refresh()
	elif app.player.connecting_path != "":
		_hide_on_open = true
		_refresh()
	else:
		hide_panel()


func _on_file_opened(path: String) -> void:
	_title = app.display_title()
	ui.files.set_active(path, _title)


## Makes `hand` the pointer (null: keep the current one). The other controller's laser goes off.
func set_pointer_hand(hand: XRHand) -> void:
	if hand == null or app.hands.size() < 2 or hand == pointer_hand:
		return
	if pointer_hand != null and not app.window_pointer_owns(pointer_hand):
		pointer_hand.set_laser(false)
	if pointer_hand != null and panel.is_pressed():
		panel.pointer_exit()
	pointer_hand = hand
	other_hand = app.right_hand if hand == app.left_hand else app.left_hand
	_scroll_acc.clear()
	_focus_dir = Vector2i.ZERO
	# The talk hand (push-to-talk) is the pointer hand: its label follows.
	if _ptt != null:
		app.update_controller_labels()


## The controller that points by default: the right one, or the left with [accessibility] left_handed.
func dominant_hand() -> XRHand:
	return app.left_hand if bool(app.features.access.get_value("left_handed")) else app.right_hand


## Applies the layout settings: the recentre hold, and the default pointer (accessibility left_handed, when it
## changed).
func apply_layout() -> void:
	var access: Node = app.features.access
	menu.hold = clampf(float(layout_value("recentre_hold")), 0.2, 3.0)
	var left := bool(access.get_value("left_handed"))
	if pointer_hand == null or left != _left_handed_applied:
		_left_handed_applied = left
		set_pointer_hand(dominant_hand())
	if _open:
		recentre()


func layout_value(key: String) -> Variant:
	return app.settings.get_value("pane", key, LAYOUT_DEFAULTS[key])


## Back to the doc's numbers: the hold, right-handed, the text size; opens in front.
func reset_layout() -> void:
	for key: String in LAYOUT_DEFAULTS:
		app.settings.set_value("pane", key, null)
	app.features.access.set_value("left_handed", false)
	app.features.access.set_value("ui_scale", 1.0)
	apply_layout()
	show_panel()


## A short notice: in the panel's footer when it is open, else a quiet line in the world where the head looks.
## (The caller translates `text`, tr(); it shows as given, docs/i18n.md.)
func notify(text: String) -> void:
	if _open:
		ui.show_toast(text)
	else:
		world_toast.show_text(text)


## The hand whose bumper is push-to-talk (the pointer hand while the dev link or an assistant is connected), or
## null.
func talk_hand() -> XRHand:
	return pointer_hand if _ptt != null and is_instance_valid(_ptt) else null


## The bumper (the app's "labels" action): on the talk hand, hold to record and release to send. True when used.
func on_bumper(hand: XRHand, held: bool) -> bool:
	if _ptt == null or not is_instance_valid(_ptt) or hand != pointer_hand:
		return false
	if app.local_agents != null and _ptt == app.local_agents.push_to_talk():
		app.local_agents.on_talk(held)
	if held:
		_talking = bool(_ptt.begin())
	elif _talking:
		_talking = false
		_ptt.end()
	return true


## Where the voice goes: [assistant] voice_to, "dev" (the dev link on 47800), "assistant" (the assistant service on
## 47801) or an agent on this headset ("claude", "codex": opening one sets it). The System tab's assistant section
## shows the choice when there is more than one. The viewer's choice holds; an agent that is active takes the voice
## unless the viewer chose a link that exists. With one target, the voice goes to that one.
func voice_target() -> Node:
	var dev := get_tree().root.get_node_or_null("DevHost")
	var dev_ptt: Node = dev.get_node_or_null("PushToTalk") if dev != null else null
	var asst_ptt: Node = Assistant.push_to_talk()  # the assistant service's, while an assistant is paired (docs/assistant.md)
	var agent_ptt: Node = app.local_agents.push_to_talk() if app.local_agents != null else null
	if agent_ptt != null:
		var to := str(app.settings.get_value("assistant", "voice_to", ""))
		if not ((to == "dev" and dev_ptt != null) or (to == "assistant" and asst_ptt != null)):
			return agent_ptt
	if dev_ptt != null and asst_ptt != null:
		return asst_ptt if str(app.settings.get_value("assistant", "voice_to", "dev")) == "assistant" else dev_ptt
	return dev_ptt if dev_ptt != null else asst_ptt


## Re-checks the voice target now (the System tab calls it when the choice changes).
func check_push_to_talk() -> void:
	_check_push_to_talk()


func _check_push_to_talk() -> void:
	var p: Node = voice_target()
	_check_assistant()
	if p == _ptt and (p == null or is_instance_valid(p)):
		return
	# A switch while the button is held: the old recorder ends and sends what it has.
	if _talking and _ptt != null and is_instance_valid(_ptt):
		_ptt.end()
	_talking = false
	_ptt = p
	if p != null:
		if not p.recording_changed.is_connected(_on_listening):
			p.recording_changed.connect(_on_listening)
	app.update_controller_labels()


## The assistant service (scripts/assistant/assistant_service.gd): its changes toast with Undo, "Assistant" shows in
## the header while an assistant is connected, and a pairing request opens the panel at its code.
func _check_assistant() -> void:
	var link := Assistant.instance()
	if link == _assistant:
		return
	_assistant = link
	if link != null:
		# Methods, not lambdas: the link outlives this layer across `reload app`.
		link.remote_change.connect(_on_assistant_change)
		link.connected_changed.connect(_on_assistant_connected)
		link.room_changed.connect(_on_room_changed)
		link.pairing_changed.connect(_on_assistant_pairing)
	_update_header_extra()


func _on_assistant_change(summary: String, undo: Callable) -> void:
	ui.show_toast(tr("Assistant: %s") % summary, tr("Undo") if undo.is_valid() else "", undo, 8.0)


## An assistant changed the room: on show and kept at once (docs/assistant.md); a short note, nothing to decide.
func _on_room_changed(summary: String) -> void:
	ui.show_toast(tr("Assistant: %s") % summary, "", Callable(), 5.0)


## An assistant asks to pair: the panel opens at the System tab's code (the card beside the screen shows it too).
func _on_assistant_pairing() -> void:
	if _assistant == null or not is_instance_valid(_assistant) or _assistant.pairing().is_empty():
		return
	show_panel()
	ui.show_tab(ui.Tab.SYSTEM)
	var row: Node = ui.system.assistant_row if ui.system != null else null
	if row != null:
		row.refresh()
		ui.system.ensure_control_visible.call_deferred(row.pairing_prompt())


func _on_assistant_connected(_on: bool) -> void:
	_update_header_extra()


func _update_header_extra() -> void:
	var parts: Array[String] = []
	for side: String in _battery_levels:
		if int(_battery_levels[side]) <= CONTROLLER_BATTERY_HEADER:
			parts.append(_battery_header(side, int(_battery_levels[side])))
	if _assistant != null and is_instance_valid(_assistant) and _assistant.is_link_connected():
		parts.append(tr("Assistant"))
	ui.header_extra = ", ".join(parts)


## The language changed (scripts/i18n.gd): the header's extra items in it.
func _on_language_changed(_code: String) -> void:
	_update_header_extra()


## "Left controller battery 14 %" (a notice), whole sentences per side (docs/i18n.md).
func _battery_notice(side: String, pct: int) -> String:
	match side:
		"left":
			return tr("Left controller battery %d %%") % pct
		"right":
			return tr("Right controller battery %d %%") % pct
	return tr("Controller battery %d %%") % pct


## "Left controller 14 %" (the header).
func _battery_header(side: String, pct: int) -> String:
	match side:
		"left":
			return tr("Left controller %d %%") % pct
		"right":
			return tr("Right controller %d %%") % pct
	return tr("Controller %d %%") % pct


func _on_listening(on: bool) -> void:
	ui.set_listening(on)
	# Typing into an agent: its pane shows the red dot and the words arrive in the terminal.
	if app.local_agents != null and _ptt == app.local_agents.push_to_talk():
		return
	if not _open:
		if on:
			world_toast.show_text(tr("Listening"), INF)
		else:
			world_toast.hide_now()


## Reads the theme file again (a restyle while the app runs).
func reload_theme() -> void:
	PaneStyle.reload()


# --- Open and closed ----------------------------------------------------------------------------------------------

## True while the panel is open (it can be seen).
func is_open() -> bool:
	return _open


## The panel as the menu on the tablet's main pane (its size and resolution, the tablet's theme and text size times
## the accessibility UI scale, no halo). Again on a change of the tablet's style.
func apply_tablet() -> void:
	panel.halo_shown = false
	panel.configure(tablet.panel_rect().size, tablet.panel_pixels(), tablet.panel_render_scale())
	var band: Dictionary = tablet.menu_band()
	ui.set_band(int(band["band"]), int(band["gap"]))
	var menu_theme: Theme = PaneStyle.tablet_theme(tablet.menu_colours())
	ui.set_tablet_theme(menu_theme)
	PaneStyle.set_active(menu_theme)
	ui.set_text_scale(tablet.panel_text_scale() * float(app.features.access.get_value("ui_scale")))
	if _open:
		recentre()


## Opens the panel in front of the head (the menu button; at launch; at the end of a file). Already open: brings it
## back in front (a recentre). hand: the new pointer (null: keep the current one).
func show_panel(hand: XRHand = null) -> void:
	set_pointer_hand(hand)
	var was_open := _open
	_open = true
	tablet.show_at(_head())
	recentre()
	if app.get("_frames") != null and int(app.get("_frames")) < 10:
		_replace_left = LAUNCH_REPLACE_SECONDS
	panel.fade_to(1.0)
	if not was_open:
		# Labels say CLICK / SCROLL while the panel takes the input, and show for a moment.
		app.set_menu_shown(true)
		_refresh()
		var first := ui.default_focus()
		if first != null:
			first.grab_focus.call_deferred()


## Closes the panel.
func hide_panel() -> void:
	if not _open:
		return
	_open = false
	panel.fade_to(0.0)
	tablet.hide_tablet()
	var focus := panel.focus_owner()
	if focus != null:
		focus.release_focus()
	app.set_menu_shown(false)


## Opens or closes the panel (seat picking: cancels that instead). hand: the pointer when it opens.
func toggle_panel(hand: XRHand = null) -> void:
	if cancel_seat_pick() or cancel_object_place() or cancel_window_mark():
		return
	if _open:
		hide_panel()
	else:
		show_panel(hand)


## Puts the tablet in front of the head again (its place for the head), and the panel onto it.
func recentre() -> void:
	if tablet == null:
		return
	tablet.place(_head())
	panel.global_transform = tablet.panel_transform()


## The menu button of `hand` (null: the desktop's M key) pressed or released. A press opens a closed panel at once,
## with that controller as the pointer; on an open panel, a short press closes it and a hold of [pane] recentre_hold
## brings it in front of the head (with that controller as the pointer). Seat picking: the press cancels it.
func on_menu(hand: XRHand, pressed: bool) -> bool:
	if pressed:
		var cancel := _seat_pick or is_placing_object() or is_marking_window()
		match menu.press(hand, _open, cancel):
			"cancel":
				cancel_seat_pick()
				cancel_object_place()
				# Edit: the menu button keeps what is shown (B puts it back); the sweep keeps on letting go.
				if is_marking_window() and _real_windows().mode == "edit":
					_finish_window_mark()
				else:
					cancel_window_mark()
			"open":
				show_panel(hand)
	elif menu.release(hand) == "close":
		hide_panel()
	return true


func _head() -> Transform3D:
	return (app.camera as Camera3D).global_transform


# --- Frame ----------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if app == null:
		return
	if menu.step(delta) == "recentre":
		show_panel(menu.hand as XRHand)
		if menu.hand != null:
			(menu.hand as XRHand).pulse()
	if _replace_left > 0.0:
		_replace_left -= delta
		if _open:
			recentre()
	_take_over_pointer()
	_update_pointer()
	_update_poke()
	_update_grip_hold(delta)
	_ptt_check -= delta
	if _ptt_check <= 0.0:
		_ptt_check = 1.0
		_check_push_to_talk()
		ui.room.check_party()

	if _hide_on_window:
		var src = app.player.source
		if src == null or src.is_ended():
			_hide_on_window = false
		elif src.has_frame():
			_hide_on_window = false
			hide_panel()
	_refresh_timer += delta
	if _refresh_timer >= 0.1:
		_refresh_timer = 0.0
		_refresh()


## One controller is enough: when the pointer controller has no pose and the other one has, the other one points.
func _take_over_pointer() -> void:
	if not app.use_xr or pointer_hand == null or other_hand == null:
		return
	if not pointer_hand.get_is_active() and other_hand.get_is_active():
		set_pointer_hand(other_hand)


## The pointer hand's ray against the panel: laser, hover, haptic tick.
func _update_pointer() -> void:
	if not app.use_xr or pointer_hand == null:
		return
	var hit := {}
	if pointer_hand.get_is_active() and _open:
		hit = panel.ray_hit(pointer_hand.get_ray_origin(), pointer_hand.get_ray_direction())
	_pointed = not hit.is_empty()
	_hit = hit
	var card_hit := {}
	if not _pointed and pointer_hand.get_is_active():
		card_hit = card.ray_hit(pointer_hand.get_ray_origin(), pointer_hand.get_ray_direction())
	_card_pointed = not card_hit.is_empty()
	_card_hit = card_hit
	_tablet_hit = {}
	if not _pointed and not _card_pointed and pointer_hand.get_is_active():
		_tablet_hit = tablet.ray_hit(pointer_hand.get_ray_origin(), pointer_hand.get_ray_direction())
	# A grab with the trigger held (the bar, a list): it follows the laser on the tablet's plane, on or off it.
	if _scrub_by == "trigger" and _scrub_hand == pointer_hand and tablet.is_grabbing():
		var at: Variant = tablet.plane_point(pointer_hand.get_ray_origin(), pointer_hand.get_ray_direction())
		if at != null:
			tablet.grab_move(at)
			_tablet_hit = {"point": at, "distance": (at as Vector3).distance_to(pointer_hand.get_ray_origin()),
					"pane": "grab", "fraction": -1.0}
	tablet.hover_bar(float(_tablet_hit.get("fraction", -1.0)) if not _tablet_hit.is_empty() else -1.0)
	if not _tablet_hit.is_empty():
		card_hit = _tablet_hit
		_card_pointed = false
	var laser_on := _pointed or _card_pointed or not _tablet_hit.is_empty()
	if not (_seat_pick and not laser_on) and seat_ring_shown():
		_seat_ring.visible = false
	if not is_marking_window() and hand_hint != null and hand_hint.visible:
		hand_hint.hide_hint()
	if is_marking_window():
		# Marking: no laser; the controller's tip is what sweeps or touches (scripts/play/real_windows.gd). What to do
		# now on the card over it.
		pointer_hand.set_laser(false)
		if pointer_hand.get_is_active():
			_real_windows().add_point(pointer_hand.get_ray_origin())
		hand_hint.show_over(pointer_hand if pointer_hand.get_is_active() else null, app.camera, _real_windows().hint())
	elif is_placing_object() and not laser_on and pointer_hand.get_is_active():
		pointer_hand.set_laser(true, _placer.update(pointer_hand), true, PaneStyle.color(&"laser"),
				PaneStyle.color(&"laser_dot"))
	elif _seat_pick and not laser_on and pointer_hand.get_is_active():
		var o := pointer_hand.get_ray_origin()
		var d := pointer_hand.get_ray_direction()
		_seat_aim = aimed_seat(o, d)
		var aimed := not _seat_aim.is_empty()
		pointer_hand.set_laser(true, float(_seat_aim.get("distance", floor_distance(o, d))), aimed,
				PaneStyle.color(&"laser"), PaneStyle.color(&"laser_dot"))
		_show_seat_ring(_seat_aim)
	elif not app.window_pointer_owns(pointer_hand) or _card_pointed or not _tablet_hit.is_empty():
		pointer_hand.set_laser(laser_on, float((hit if _pointed else card_hit).get("distance", 3.0)), laser_on,
				PaneStyle.color(&"laser"), PaneStyle.color(&"laser_dot"))
	if other_hand != null and not app.window_pointer_owns(other_hand):
		other_hand.set_laser(false)
	if _pointed:
		panel.pointer_move(hit["pixel"])
	elif not panel.is_pressed():
		panel.pointer_exit()
	_check_hover(pointer_hand)


## One haptic tick when the pointer moves onto a new target (features.haptics, #32).
func _check_hover(hand: XRHand) -> void:
	var c := panel.hovered_control() if _pointed else null
	var target: Control = c if c is BaseButton or c is Slider or c is LineEdit or (c != null and c.focus_mode != Control.FOCUS_NONE) \
			else null
	if target != _hover:
		_hover = target
		if target != null and hand != null and app.features != null:
			app.features.haptics.hover(hand)


## Poking the panel with the pointer controller's tip clicks, as people will try it (with [pane] distance set short).
## The tablet's time bar is grabbed by touch too: either controller's tip pushed through it, moved along it, and
## pulled back out where the film should be. A tip held in the panel and moved drags a list.
func _update_poke() -> void:
	_update_tablet_poke()
	_update_panel_poke()


func _update_tablet_poke() -> void:
	if _scrub_by == "touch":
		var h := _scrub_hand
		if h == null or not app.use_xr or not h.get_is_active() or not tablet.is_shown():
			tablet.release()
			_scrub_hand = null
			_scrub_by = ""
			return
		var probe := tablet.poke_probe(h.get_ray_origin())
		var depth: float = probe["depth"]
		if depth > POKE_RELEASE or depth < -0.08:
			# Pulled back out (or right through): let go there.
			if tablet.release():
				h.pulse()
			_scrub_hand = null
			_scrub_by = ""
		else:
			tablet.grab_move(probe["point"])
		return
	if _scrub_by != "" or not app.use_xr or not tablet.is_shown():
		return
	for hand: XRHand in [pointer_hand, other_hand]:
		if hand == null or not hand.get_is_active():
			continue
		var probe := tablet.poke_probe(hand.get_ray_origin())
		var depth: float = probe["depth"]
		if depth < POKE_PRESS and depth > -0.05 and tablet.grab(probe["point"]):
			_scrub_hand = hand
			_scrub_by = "touch"
			hand.pulse()
			return


func _update_panel_poke() -> void:
	if not app.use_xr or pointer_hand == null or not pointer_hand.get_is_active() or not _open:
		if _poke_down:
			_poke_down = false
			panel.pointer_exit()
		return
	var probe := panel.poke_probe(pointer_hand.get_ray_origin())
	var depth: float = probe["depth"]
	if not _poke_down and probe["inside"] and depth < POKE_PRESS and depth > -0.05:
		_poke_down = true
		panel.pointer_button(probe["pixel"], true)
		pointer_hand.pulse()
	elif _poke_down and (depth > POKE_RELEASE or depth < -0.08 or not (probe["inside"] or panel.dragging)):
		_poke_down = false
		if probe["inside"] or panel.dragging:
			panel.pointer_button(probe["pixel"], false)
		else:
			panel.pointer_exit()
	elif _poke_down:
		# Held in: the tip moving drags a list (ui/pane.gd).
		panel.pointer_move(probe["pixel"])


func _update_grip_hold(delta: float) -> void:
	if _grip_held < 0.0:
		return
	if not _pointed:
		_grip_held = -1.0
		return
	_grip_held += delta
	if _grip_held >= GRIP_ALLOW_SECONDS:
		_grip_held = -1.0
		var dev := DevHost.instance()
		if dev != null and dev.get("permissions") != null:
			dev.permissions.allow_for(3600.0)
			ui.show_toast(tr("Remote changes allowed for an hour"), tr("Revoke"), func() -> void: dev.permissions.revoke())
			pointer_hand.pulse()


func _refresh() -> void:
	if not panel.visible and not _open:
		return
	var player: Node = app.player
	ui.set_playback(player.get_position(), player.get_duration(), player.is_playing(), player.can_seek())
	ui.tick()
	tablet.set_header(ui.chapter_text(), ui.status_line_text())
	var src = player.source
	if src == null:
		ui.set_status(tr("Connecting...") if player.connecting_path != "" else "")
		return
	if src.get_kind() == "window":
		var title: String = app.display_title()
		if title != _title:
			_title = title
			ui.files.set_active(app.current_path, title)
		if src.is_ended():
			ui.set_status(src.last_error)
		elif not src.has_frame():
			ui.set_status(tr("Starting the browser..."))
		else:
			ui.set_status("")
		return
	ui.set_status("")


# --- Input the app forwards ---------------------------------------------------------------------------------------

## Seat picking: the pane moves out of the way and the laser goes out into the room.
func start_seat_pick() -> void:
	_seat_pick = true
	_seat_aim = {}
	hide_panel()
	notify(tr("Point at a seat and pull the trigger. B cancels."))


## B or menu while picking a seat: stop, nothing changes. True when it was picking (the button is used up).
func cancel_seat_pick() -> bool:
	if not _seat_pick:
		return false
	_seat_pick = false
	_seat_aim = {}
	_show_seat_ring({})
	notify(tr("Seat unchanged"))
	return true


## The main.gd hook for B (the right hand's "previous file" button): cancels seat picking, placing an object or marking
## a window.
func on_back(_hand: XRHand) -> bool:
	return cancel_seat_pick() or cancel_object_place() or cancel_window_mark()


## Place (the Room tab's objects): the panel goes, and the object follows the laser on the walls and the floor until
## the trigger sets it (ui/object_placer.gd).
func start_object_place(id: String) -> bool:
	return _start_placer(_ensure_placer().start_place(id))


## Move: the same for something already in the room.
func start_object_move(placed_name: String) -> bool:
	return _start_placer(_ensure_placer().start_move(placed_name))


func _start_placer(started: bool) -> bool:
	if not started:
		notify(tr("That object can't be placed here"))
		return false
	cancel_seat_pick()
	hide_panel()
	notify(tr("Point at a wall or the floor and pull the trigger. Stick: turn and size. B cancels."))
	return true


func _ensure_placer() -> ObjectPlacer:
	if _placer == null:
		_placer = ObjectPlacer.new()
		_placer.name = "ObjectPlacer"
		_placer.app = app
		add_child(_placer)
	return _placer


## Windows to the real room (the Mixed reality tab; scripts/play/real_windows.gd): the panel goes and the view is the
## cameras'. Sweep: the trigger held sweeps the controller over the place, letting go keeps it. Edit: a face at a
## time, the stick moves it, the trigger goes to the next face and then Turn, menu keeps it. B cancels each.
func start_window_mark() -> bool:
	return _start_window(_real_windows() != null and _real_windows().start_mark())


func start_window_edit(id: String) -> bool:
	return _start_window(_real_windows() != null and _real_windows().start_edit(id))


## The steps' instructions are on the card over the controller (hand_hint), for as long as the mode lasts.
func _start_window(started: bool) -> bool:
	var rw := _real_windows()
	if not started:
		notify(tr("The headset's cameras can't show here.") if rw == null or not rw.available()
				else tr("That's as many areas as there can be: delete one first."))
		return false
	cancel_seat_pick()
	cancel_object_place()
	hide_panel()
	return true


func is_marking_window() -> bool:
	var rw := _real_windows()
	return rw != null and rw.marking


func cancel_window_mark() -> bool:
	if not is_marking_window():
		return false
	_real_windows().cancel_mark()
	notify(tr("Nothing marked"))
	return true


## The area made or changed is kept. The panel comes back with Undo in its footer.
func _finish_window_mark() -> void:
	var rw := _real_windows()
	var was: Dictionary = rw.before()
	var w: Dictionary = rw.finish()
	show_panel()
	if w.is_empty():
		notify(tr("Nothing marked"))
		return
	if was.is_empty():
		ui.show_toast(tr("%s added: the cameras show there") % w["name"], tr("Undo"), func() -> void:
			rw.remove(str(w["id"]))
			ui.hide_toast(), 8.0)
	else:
		ui.show_toast(tr("%s changed") % w["name"], tr("Undo"), func() -> void:
			rw.restore(was)
			ui.hide_toast(), 8.0)


func _real_windows() -> Node:
	return app.features.get("real_windows") if app.features != null else null


func is_placing_object() -> bool:
	return _placer != null and _placer.active()


## B or menu while placing: nothing changes. True when it was placing (the button is used up).
func cancel_object_place() -> bool:
	if _placer == null or not _placer.cancel():
		return false
	notify(tr("Nothing placed"))
	return true


## The trigger while placing: sets the object where it shows. The panel comes back (the object's parts are there) and
## its footer says so, with Undo.
func _commit_object() -> void:
	var r: Dictionary = await _placer.commit()
	if r.get("ok") == true:
		var said := str(r.get("summary", "placed"))
		show_panel()
		ui.show_toast(said.left(1).to_upper() + said.substr(1), tr("Undo") if r.get("undo") is Callable else "",
				r.get("undo", Callable()), 8.0)
	else:
		notify(str(r.get("error", tr("Not placed"))))


func is_picking_seat() -> bool:
	return _seat_pick


## Takes the aimed seat (aimed_seat()'s answer) and ends seat picking; with none, says so and ends too.
func pick_seat(aim: Dictionary) -> bool:
	_seat_pick = false
	_seat_aim = {}
	_show_seat_ring({})
	var seat: Node = app.features.seat
	if aim.is_empty() or not seat.choose_seat_at(aim["point"], true):
		notify(tr("No seat there"))
		return false
	notify(str(seat.names()[int(aim["index"])]) if int(aim.get("index", -1)) >= 0 else tr("Seat"))
	return true


## The seat a ray passes nearest, within SEAT_AIM of it and ahead of the hand: {index, point, distance}, or {}.
func aimed_seat(origin: Vector3, direction: Vector3) -> Dictionary:
	var env: Node3D = app.env
	var seat: Node = app.features.seat
	if env == null:
		return {}
	var best := {}
	var best_off := SEAT_AIM
	var seats: Array = seat.seats()
	for i in seats.size():
		var p: Vector3 = env.global_transform * (seats[i] as Vector3)
		var along := (p - origin).dot(direction)
		if along <= 0.0:
			continue
		var off := (p - (origin + direction * along)).length()
		if off < best_off:
			best_off = off
			best = {"index": i, "point": p, "distance": along}
	return best


## How far along a ray the floor (y = 0, the play space's floor) is; 6 m when the ray doesn't go down to it.
static func floor_distance(origin: Vector3, direction: Vector3) -> float:
	if direction.y >= -0.01:
		return 6.0
	return clampf(-origin.y / direction.y, 0.05, 30.0)


## The ring on the aimed seat's floor point (the theme's laser dot colour), hidden with none.
func _show_seat_ring(aim: Dictionary) -> void:
	if aim.is_empty():
		if _seat_ring != null:
			_seat_ring.visible = false
		return
	if _seat_ring == null:
		var torus := TorusMesh.new()
		torus.inner_radius = SEAT_RING_RADIUS - 0.03
		torus.outer_radius = SEAT_RING_RADIUS
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = PaneStyle.color(&"laser_dot")
		mat.no_depth_test = true
		torus.material = mat
		_seat_ring = MeshInstance3D.new()
		_seat_ring.name = "SeatRing"
		_seat_ring.mesh = torus
		_seat_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_seat_ring)
	_seat_ring.global_position = (aim["point"] as Vector3) + Vector3.UP * 0.02
	_seat_ring.visible = true


func seat_ring_shown() -> bool:
	return _seat_ring != null and _seat_ring.visible


## Trigger of the pointer controller: with the laser on the panel, a click there; open and not aimed: activates the
## focused control. Closed: not used (the app's play / pause).
func on_trigger(hand: XRHand, pressed: bool) -> bool:
	if hand != pointer_hand:
		return false
	if is_marking_window():
		var rw := _real_windows()
		match rw.mode:
			"sweep":
				if pressed:
					rw.sweep(true)
					hand.pulse()
				elif rw.sweeping:
					_finish_window_mark()
					hand.pulse()
			"edit":
				if pressed:
					rw.next_face()
					hand.pulse()
		return true
	if is_placing_object() and not _pointed and not _card_pointed:
		if pressed:
			_commit_object()
			hand.pulse()
		return true
	if _seat_pick and not _pointed and not _card_pointed:
		if pressed:
			pick_seat(_seat_aim)
			hand.pulse()
		return true
	if _scrub_by == "trigger" and not pressed and hand == _scrub_hand:
		if tablet.release():
			hand.pulse()
		_scrub_hand = null
		_scrub_by = ""
		return true
	if not _tablet_hit.is_empty():
		if pressed and _scrub_by == "" and tablet.grab(_tablet_hit["point"]):
			_scrub_hand = hand
			_scrub_by = "trigger"
			hand.pulse()
		return true
	if _card_pointed:
		if pressed:
			if _card_hit.has("point"):
				card.click(_card_hit["point"])
			else:
				card.dismiss("user")
			hand.pulse()
		return true
	if _pointed:
		panel.pointer_button(_hit["pixel"], pressed)
		if pressed:
			hand.pulse()
		return true
	if panel.is_pressed() and not pressed:
		panel.pointer_exit()
		return true
	if _open:
		if pressed:
			panel.push_action(&"ui_accept")
			hand.pulse()
		return true
	return false


## Thumbstick: either stick scrolls the list under the laser, or nudges the slider under it (up or right: more). Open
## and not aimed, the pointer controller's stick moves the focus.
func on_stick(hand: XRHand, stick: Vector2, delta: float) -> bool:
	# The eye calibration moves its pip with the stick (scripts/xr/eye_gaze.gd reads it): no seeking meanwhile.
	var gaze: Node = app.features.get_node_or_null("EyeGaze") if app.features != null else null
	if gaze != null and gaze.calibrating:
		return true
	if is_marking_window():
		if hand == pointer_hand:
			_real_windows().on_stick(stick, delta)
			return true
		return false
	if is_placing_object() and not _pointed:
		# The pointer controller's stick turns and sizes the object; the other one's is left alone.
		if hand == pointer_hand:
			_placer.on_stick(stick, delta)
			return true
		return false
	if _pointed:
		var axis := stick.y
		var on_slider := panel.hovered_control() is Slider
		if on_slider and absf(stick.x) > absf(stick.y):
			axis = stick.x
		# A list moves smoothly; a slider (and anything else) still steps.
		if not on_slider:
			var push := clampf((absf(axis) - STICK_SCROLL_DEAD) / (1.0 - STICK_SCROLL_DEAD), 0.0, 1.0)
			if push <= 0.0 or panel.scroll_by(signf(axis) * pow(push, STICK_SCROLL_CURVE) * STICK_SCROLL_SPEED * delta):
				_scroll_acc[hand] = 0.0
				return true
		var acc: float = _scroll_acc.get(hand, 0.0) + axis * STICK_SCROLL_RATE * delta
		if absf(axis) < 0.2:
			acc = 0.0
		while absf(acc) >= 1.0:
			panel.pointer_scroll(_hit["pixel"], 1 if acc > 0.0 else -1)
			acc -= signf(acc)
		_scroll_acc[hand] = acc
		return true
	if _open and hand == pointer_hand:
		_focus_step(stick, delta)
		return true
	return false


func _focus_step(stick: Vector2, delta: float) -> void:
	var dir := Vector2i.ZERO
	if absf(stick.x) > FOCUS_STICK and absf(stick.x) >= absf(stick.y):
		dir.x = signi(int(signf(stick.x)))
	elif absf(stick.y) > FOCUS_STICK:
		dir.y = -signi(int(signf(stick.y)))
	if dir == Vector2i.ZERO:
		_focus_dir = dir
		return
	if dir != _focus_dir:
		_focus_dir = dir
		_focus_wait = FOCUS_REPEAT_FIRST
	else:
		_focus_wait -= delta
		if _focus_wait > 0.0:
			return
		_focus_wait = FOCUS_REPEAT
	if panel.focus_owner() == null:
		var first := ui.stick_focus()
		if first != null:
			first.grab_focus()
		return
	var action := &"ui_right" if dir.x > 0 else (&"ui_left" if dir.x < 0 else (&"ui_down" if dir.y > 0 else &"ui_up"))
	panel.push_action(action)
	var focus := panel.focus_owner()
	if focus != null:
		_ensure_visible(focus)
		if app.features != null:
			app.features.haptics.hover(pointer_hand)


## Scrolls the focused control into view inside its scroll container.
func _ensure_visible(c: Control) -> void:
	var p := c.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p is ScrollContainer:
		(p as ScrollContainer).ensure_control_visible(c)


## Grip: held 2 s with the laser on the pane allows remote changes for an hour (dev mode). The grip on the pane does
## not move the screen.
func on_grip(hand: XRHand, pressed: bool) -> bool:
	if hand != pointer_hand or not _pointed:
		if not pressed:
			_grip_held = -1.0
		return false
	if DevHost.instance() == null:
		return false
	_grip_held = 0.0 if pressed else -1.0
	return true


## Desktop keyboard: while a text field of the pane has focus, keys type into it. True when the pane used the event.
func on_key(event: InputEventKey) -> bool:
	if not panel.visible:
		return false
	var focus := panel.focus_owner()
	if focus is LineEdit and focus.is_visible_in_tree():
		panel.viewport.push_input(event, true)
		return true
	return false


## Desktop mouse; ray = [origin, direction] from the flat camera. True when the pane used the event.
func on_mouse(event: InputEventMouse, ray: Array) -> bool:
	var hit := panel.ray_hit(ray[0], ray[1])
	if event is InputEventMouseMotion:
		if not hit.is_empty():
			panel.pointer_move(hit["pixel"])
			return true
		if panel.is_pressed():
			return true
		panel.pointer_exit()
		return false
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and hit.is_empty() 			and not card.ray_hit(ray[0], ray[1]).is_empty():
		card.click(card.ray_hit(ray[0], ray[1])["point"])
		return true
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed and not hit.is_empty():
			panel.pointer_button(hit["pixel"], true)
			return true
		if not button.pressed and panel.is_pressed():
			if hit.is_empty():
				panel.pointer_exit()
			else:
				panel.pointer_button(hit["pixel"], false)
			return true
	elif button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not hit.is_empty():
		if button.pressed:
			panel.pointer_scroll(hit["pixel"], 1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		return true
	return false
