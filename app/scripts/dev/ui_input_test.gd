extends Node

## --ui-test: drives the menu on the tablet (ui/tablet.gd, the panel ui/pane.gd on its main pane) through the same
## path the controllers use. For each control: its pixel -> the world point on the pane quad -> a ray from the camera
## -> Pane.ray_hit() (checked against the pixel) -> pointer_move / pointer_button / pointer_scroll. Then checks the
## app's state. A tab other than Source shows one section at a time: a control on another section's card is out of
## the tree, so the finders pick its section first (_find_button(), _reveal()). The tablet's time bar is hit with
## Tablet.ray_hit() and grabbed through UILayer.on_trigger(). The stick focus goes through UILayer.on_stick() /
## on_trigger() as the controllers' would. Prints PASS / FAIL lines and quits with the number of failures as the exit
## code. Runs headless.

const VideoMode := preload("res://scripts/video_mode.gd")
const PaneUI := preload("res://ui/pane_ui.gd")
const Tablet := preload("res://ui/tablet.gd")
const W := preload("res://ui/pane_widgets.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const DirectoryLister := preload("res://scripts/net/directory_lister.gd")
const Remote := preload("res://scripts/remote/remote.gd")
const PCAudio := preload("res://scripts/dev/pc_audio.gd")

var main: Node
var _failures := 0
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	var ui: PaneUI = main.ui.ui
	main.ui.show_panel()
	await _seconds(0.3)
	_check("the panel starts open in front, the right controller pointing", main.ui.is_open() and main.ui.docked
			and main.ui.panel.visible and main.menu_shown and main.ui.pointer_hand == main.right_hand)
	await _panel_checks(ui)

	# Files: the "Test patterns" place, then a pattern from the list.
	await _click(_find_button(ui, "Test patterns"))
	_check("places button opens the test patterns", ui.files.current == "stub://")
	await _click(ui.files.row_button("180° mono"))
	await _frames(5)
	_check("row click opens stub://180_mono", main.current_path == "stub://180_mono")
	_check("pattern mode applied (180 mono)", main.mode.to_id() == "180_mono")
	await _seconds(0.3)
	_check("the panel closes after opening a file", not main.ui.is_open() and not main.ui.panel.visible)

	# Picture tab.
	main.ui.show_panel()
	await _seconds(0.3)
	_check("panel: with a file open, the header has the time left and the end (%s)" % ui.status_line_text(),
			ui.status_line_text().contains(" left, ends "))
	await _rail(ui, PaneUI.Tab.PICTURE)
	_check("rail click selects Picture, a section on show and marked (%s)" % ui.section_shown(),
			ui.current_tab == PaneUI.Tab.PICTURE and ui.picture.is_visible_in_tree() and ui.section_shown() != ""
			and ui.tablet_tab_buttons[PaneUI.Tab.PICTURE].button_pressed and ui.section_buttons().any(
				func(b: Button) -> bool: return b.button_pressed and b.text == ui.section_shown()))
	await _section_click_checks(ui)
	await _click(_find_diagram(ui, "SBS"))
	_check("layout diagram sets side by side", main.mode.layout == VideoMode.Layout.SBS and main.mode_source == "user")
	await _click(_find_diagram(ui, "360°"))
	_check("projection diagram sets 360", main.mode.projection == VideoMode.Proj.EQUIRECT_360)
	await _click(_find_button(ui, "Auto"))
	_check("auto restores the pattern's mode", main.mode.to_id() == "180_mono")
	_check("footer says how the mode was chosen (%s)" % ui._footer_text.text, ui._footer_text.text != "")

	await _tablet_bar_checks(ui)
	var pos: float = main.player.get_position()
	await _click(_find_button(ui, "+10 s"))
	_check("+10 s button", absf(main.player.get_position() - pos - 10.0) < 1.0)

	# Picture tab on a flat pattern: drag the size slider. Room tab: pick the cinema.
	main.open_path("stub://flat_sbs", false)
	await _frames(5)
	main.ui.show_panel()
	await _seconds(0.3)
	await _rail(ui, PaneUI.Tab.PICTURE)
	var width_slider: HSlider = W.slider_of(ui.picture._rows["width"])
	await _reveal(ui, width_slider)
	await _bring_on_pane(width_slider)
	await _frames(2)
	var before: float = main.screen_width
	var wr := width_slider.get_global_rect()
	var ratio := (width_slider.value - width_slider.min_value) / (width_slider.max_value - width_slider.min_value)
	var start := wr.position + Vector2(6 + (wr.size.x - 12) * ratio, wr.size.y * 0.5)
	await _drag(start, start + Vector2(120, 0))
	_check("dragging the size slider widens the screen (%.2f -> %.2f m)" % [before, main.screen_width],
			main.screen_width > before + 0.5)
	await _rail(ui, PaneUI.Tab.ROOM)
	# The room groups start closed: open Cinemas first.
	await _click(ui.room._groups["Cinemas"]["head"])
	await _frames(2)
	await _click(_find_button(ui, "Cinema"))
	_check("environment button loads the cinema", main.env_id == "cinema" and main.env.display_name == "Cinema")

	# Files tab: wheel scrolling on the list.
	await _rail(ui, PaneUI.Tab.FILES)
	ui.files.open_folder("stub://")
	await _frames(3)
	var scroll: ScrollContainer = ui.files.list_scroll()
	var sb := scroll.get_v_scroll_bar()
	if sb.max_value > sb.page:
		var hit := _hit_for_pixel(scroll.get_global_rect().get_center())
		main.ui.panel.pointer_move(hit["pixel"])
		main.ui.panel.pointer_scroll(hit["pixel"], -4)
		await _frames(2)
		_check("wheel scrolls the file list (scroll %d)" % scroll.scroll_vertical, scroll.scroll_vertical > 0)
		scroll.scroll_vertical = 0
	else:
		print("SKIP wheel scroll: the list fits without scrolling")

	# Previous / Next buttons walk the playlist (the test patterns here).
	await _click(ui.files.row_button("Flat"))
	await _frames(3)
	main.ui.show_panel()
	await _seconds(0.3)
	var at: int = main.playlist_index
	await _click(_find_button(ui, "Next"))
	_check("Next button opens the next pattern (%s)" % main.current_path, main.playlist_index == at + 1
			and main.current_path == main.playlist[at + 1])
	await _click(_find_button(ui, "Previous"))
	_check("Previous button goes back", main.playlist_index == at)

	await _docked_focus_checks(ui)

	# Keyboard (desktop), pane hidden: V cycles the projection, N / P next / previous file, Up farther, Tab the overlay.
	main.ui.hide_panel()
	await _frames(2)
	var proj: int = main.mode.projection
	await _key(KEY_V)
	_check("key V cycles the projection", int(main.mode.projection) == (proj + 1) % VideoMode.Proj.size())
	await _key(KEY_N)
	_check("key N: next file", main.playlist_index == at + 1)
	await _key(KEY_P)
	_check("key P: previous file", main.playlist_index == at)
	var distance: float = main.screen_distance
	await _key(KEY_UP)
	_check("key Up: screen farther (%.2f -> %.2f m)" % [distance, main.screen_distance], main.screen_distance > distance)
	var overlay_was: bool = main.overlay_on
	await _key(KEY_TAB)
	_check("key Tab toggles the overlay (hidden while the pane is open)", main.overlay_on != overlay_was
			and main.overlay.visible == (main.overlay_on and not main.menu_shown))
	await _key(KEY_TAB)
	await _key(KEY_M)
	await _seconds(0.3)
	_check("key M opens the panel", main.ui.is_open() and main.ui.panel.visible)

	# Desktop mouse path: real mouse events on the window, at the projection of the Pause/Play button.
	var playing: bool = main.player.is_playing()
	var play_button := _find_button(ui, "Pause" if playing else "Play")
	var screen_pos := _pixel_to_screen(play_button.get_global_rect().get_center())
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = screen_pos
		ev.global_position = screen_pos
		Input.parse_input_event(ev)
		await _frames(2)
	_check("mouse click on the window toggles play/pause", main.player.is_playing() != playing)

	await _network_checks(ui)
	await _places_checks(ui)
	await _layout_checks(ui)
	await _help_and_curve_checks(ui)

	await _card_checks()
	await _push_to_talk_checks(ui)
	await _hwvideo_checks(ui)

	# Controller battery (#75): in the footer while the pane is open, in the world while it is closed.
	main.ui.show_panel()
	await _seconds(0.3)
	main.ui.controller_battery._fake = {"left": 12}
	main.ui.controller_battery.poll()
	_check("low controller battery: a footer toast while open (%s)" % ui._toast_label.text,
			ui._toast.visible and ui._toast_label.text.contains("Left controller battery 12"))
	ui.hide_toast()
	main.ui.hide_panel()
	await _seconds(0.3)
	main.ui.controller_battery._fake = {"left": 4}
	main.ui.controller_battery.poll()
	_check("lower still: a world toast while closed", main.ui.world_toast.visible
			and main.ui.world_toast.text.contains("4 %"))
	main.ui.controller_battery._fake = {}
	main.ui.show_panel()
	await _seconds(0.3)
	await _key(KEY_ESCAPE)
	await _seconds(0.3)
	_check("Esc closes the panel", not main.ui.is_open() and not main.ui.panel.visible and not main.menu_shown)

	await _focus_checks()

	print("UI input test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	main.get_tree().quit(_failures)


## The tablet, the one menu (ui/tablet.gd, docs/ui-design.md): either controller's menu button opens it with that
## controller as the pointer, placed from the head (ahead and below, tilted up to the eyes, the panel on its main
## pane), a short press closes it, a hold recentres it; it stays put in the room when the head turns; looking up
## doesn't lift it (it goes by the heading only); the stick nudges a slider under the laser; the dev link's `menu`
## command picks the pointer.
func _panel_checks(ui: PaneUI) -> void:
	const DevCommands := preload("res://scripts/dev/dev_commands.gd")
	var cam: Camera3D = main.camera
	var tablet: Tablet = main.ui.tablet
	# The first moments after launch place it again as the head settles (ui_layer.gd): past them.
	main.ui._replace_left = 0.0
	var tp: Vector3 = tablet.global_position
	var to_eye: Vector3 = (cam.global_position - tp).normalized()
	var ahead: float = (tp - cam.global_position).dot(-cam.global_basis.z)
	_check("tablet: shown, placed for the head (%s)" % tp, tablet.is_shown() and _tablet_in_front())
	_check("tablet: ahead of and below the eyes, its face tilted up to them (%.2f m ahead, %.2f m down, %.1f° off)"
			% [ahead, cam.global_position.y - tp.y, rad_to_deg(tablet.global_basis.z.angle_to(to_eye))],
			ahead > 0.25 and tp.y < cam.global_position.y - 0.2
			and tablet.global_basis.z.angle_to(to_eye) < deg_to_rad(15.0) and absf(tablet.global_basis.x.y) < 0.001)
	_check("tablet: the panel is the menu on its main pane", _panel_on_tablet())
	await _seconds(0.2)
	_check("panel: the header shows the clock (%s)" % ui.status_line_text(), ui.status_line_text().contains(":")
			and not ui.status_line_text().contains(" left"))
	_check("panel: the transport on the band over the rail", ui._transport.is_visible_in_tree() and ui._play_button.is_visible_in_tree()
			and ui._transport.get_global_rect().end.y <= ui._tablet_row.get_global_rect().position.y + 1.0)
	_check("panel: the rail, a row per tab (%s)" % [ui.tablet_tab_buttons.map(func(b: Button) -> String: return b.text)],
			ui.tablet_tab_buttons.size() == PaneUI.TAB_NAMES.size()
			and ui.tablet_tab_buttons.all(func(b: Button) -> bool: return b.is_visible_in_tree()))
	# All of it on the pane: the rail's last row and the footer too, or the laser can't reach them.
	var last_row: Rect2 = ui.tablet_tab_buttons[-1].get_global_rect()
	_check("panel: the menu fits the tablet's main pane (%d of %d px; the rail ends at %d, the footer at %d)"
			% [ui.get_combined_minimum_size().y, main.ui.panel.resolution.y, last_row.end.y,
			ui._footer_count.get_global_rect().end.y], ui.get_combined_minimum_size().y <= main.ui.panel.resolution.y
			and last_row.end.y <= main.ui.panel.resolution.y)
	main.on_menu(main.right_hand, true)
	await _frames(2)
	main.on_menu(main.right_hand, false)
	await _seconds(0.3)
	_check("menu (right), a short press: the panel and the tablet close", not main.ui.is_open()
			and not main.ui.panel.visible and not main.menu_shown and not tablet.is_shown())
	main.on_menu(main.left_hand, true)
	await _frames(2)
	main.on_menu(main.left_hand, false)
	await _seconds(0.3)
	_check("menu (left): opens with the left controller pointing", main.ui.is_open() and main.ui.panel.visible
			and tablet.is_shown() and main.ui.pointer_hand == main.left_hand and main.ui.other_hand == main.right_hand)
	main.ui._replace_left = 0.0
	var before: Transform3D = tablet.global_transform
	var panel_before: Transform3D = main.ui.panel.global_transform
	main._look = Vector2(60, 0)
	main._apply_look()
	await _frames(10)
	_check("fixed in the room: a 60° head turn leaves the tablet and the panel where they were",
			tablet.global_transform.is_equal_approx(before) and main.ui.panel.global_transform.is_equal_approx(panel_before)
			and not _tablet_in_front())
	main.on_menu(main.right_hand, true)
	await _seconds(0.3)
	_check("menu (right) held 0.3 s: nothing yet", tablet.global_transform.is_equal_approx(before)
			and main.ui.pointer_hand == main.left_hand)
	await _seconds(0.45)
	_check("menu (right) held 0.75 s: recentred for the turned head, the right controller pointing", main.ui.is_open()
			and _tablet_in_front() and _panel_on_tablet() and main.ui.pointer_hand == main.right_hand)
	main.on_menu(main.right_hand, false)
	await _frames(2)
	_check("released after the hold: the panel stays open", main.ui.is_open() and tablet.is_shown())
	# Looking up: M held (the desktop's menu button) recentres by the heading only, so the tablet stays below.
	main._look = Vector2(0, 85)
	main._apply_look()
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	Input.parse_input_event(key)
	await _seconds(0.75)
	var up := InputEventKey.new()
	up.keycode = KEY_M
	Input.parse_input_event(up)
	await _frames(2)
	var level := Transform3D(Basis(Vector3.UP, cam.global_rotation.y), cam.global_position)
	_check("looking up: M held recentres it, below the eyes as for a level head (%s)" % tablet.global_position,
			main.ui.is_open() and _tablet_in_front() and tablet.global_transform.is_equal_approx(Tablet.pose(level))
			and tablet.global_position.y < cam.global_position.y - 0.2)
	_check("the M key keeps the pointer it had", main.ui.pointer_hand == main.right_hand)
	main._look = Vector2.ZERO
	main._apply_look()
	main.ui.show_panel(main.right_hand)
	await _seconds(0.3)
	# The stick on a slider under the laser nudges it (right: more); the list under it scrolls (checked below).
	await _rail(ui, PaneUI.Tab.PICTURE)
	var slider: HSlider = W.slider_of(ui.picture._rows["width"])
	await _reveal(ui, slider)
	await _bring_on_pane(slider)
	await _frames(2)
	var hit := _hit_for_pixel(slider.get_global_rect().get_center())
	main.ui._pointed = true
	main.ui._hit = hit
	main.ui.panel.pointer_move(hit["pixel"])
	await _frames(2)
	var was: float = slider.value
	for i in 10:
		main.ui.on_stick(main.right_hand, Vector2(1, 0), 0.05)
	_check("stick right on a slider under the laser nudges it up (%.2f -> %.2f)" % [was, slider.value], slider.value > was)
	main.ui._pointed = false
	main.ui._hit = {}
	main.ui.panel.pointer_exit()
	slider.value = was
	await _rail(ui, PaneUI.Tab.FILES)
	# The dev link's menu command: hand = left makes the left controller the pointer.
	preload("res://scripts/dev/command_host.gd").ensure(main.get_tree())
	await _frames(2)
	var r: Dictionary = await DevCommands.execute("menu", {"shown": true, "hand": "left"}, false)
	_check("dev menu command, hand left: open, the left controller pointing (%s)" % r, main.ui.is_open()
			and main.ui.pointer_hand == main.left_hand)
	await DevCommands.execute("menu", {"shown": false}, false)
	_check("dev menu command, shown false: closed", not main.ui.is_open() and not tablet.is_shown())
	main.ui.show_panel(main.right_hand)
	await _seconds(0.3)


## The tablet where Tablet.pose() puts it for the head as it is now.
func _tablet_in_front() -> bool:
	return main.ui.tablet.global_transform.is_equal_approx(Tablet.pose(main.camera.global_transform))


## The panel on the tablet's main pane (Tablet.panel_transform()), its size.
func _panel_on_tablet() -> bool:
	var tablet: Tablet = main.ui.tablet
	return (main.ui.panel.global_transform.is_equal_approx(tablet.panel_transform())
			and main.ui.panel.size_m.is_equal_approx(tablet.panel_rect().size))


## Picture's sections column: a click on a section's button shows that section's card alone; another, that one.
func _section_click_checks(ui: PaneUI) -> void:
	var names: Array = ui.section_buttons().map(func(b: Button) -> String: return b.text)
	_check("Picture: a sections column, Mode first (%s)" % [names], ui._sections_scroll.is_visible_in_tree()
			and names.size() >= 3 and names[0] == "Mode" and names.has("Screen"))
	var cards: Array = ui.cards(PaneUI.Tab.PICTURE)
	var on_show := func() -> Array: return cards.filter(func(c: Control) -> bool:
		return c.get_parent() != null and c.is_visible_in_tree()).map(func(c: Control) -> String:
			return W.card_section(c))
	for want: String in ["Screen", "Mode"]:
		var b: Button = null
		for s in ui.section_buttons():
			if s.text == want:
				b = s
		await _click(b)
		await _frames(2)
		_check("Picture: clicking %s shows its card alone (%s)" % [want, on_show.call()], ui.section_shown() == want
				and on_show.call() == [want] and b != null and b.button_pressed)
	# The other tabs with sections of their own.
	for spec: Array in [[PaneUI.Tab.OBJECTS, ["Built-in objects", "Your objects", "Pictures", "Surfaces",
			"In this room"]],
			[PaneUI.Tab.MIXED_REALITY, ["Areas", "Settings"]]]:
		await _rail(ui, spec[0])
		await _frames(2)
		var got: Array = ui.section_buttons().map(func(s: Button) -> String: return s.text)
		_check("%s: its sections (%s)" % [PaneUI.TAB_NAMES[spec[0]], got], ui.current_tab == spec[0] and got == spec[1])
	await _rail(ui, PaneUI.Tab.PICTURE)


## The tablet's time bar, by the laser and by a grab, through ui_layer.gd's trigger path: a ray from the eyes at a
## point on the bar finds it there; the trigger there skips to it; held and moved along it, the film goes where it is
## let go. The chapters' ticks on it and the chapter in the header; the trick speed by the time.
func _tablet_bar_checks(ui: PaneUI) -> void:
	var tablet: Tablet = main.ui.tablet
	var dur: float = main.player.get_duration()
	var bar: Rect2 = tablet.bar_rect()
	var eye: Vector3 = main.camera.global_position
	var at := func(f: float) -> Vector3:
		return tablet.now_playing.to_global(Vector3(bar.position.x + bar.size.x * f, bar.get_center().y, 0))
	var hit: Dictionary = tablet.ray_hit(eye, ((at.call(0.25) as Vector3) - eye).normalized())
	_check("tablet bar: a ray at a quarter along finds it there (%s)" % hit.get("fraction"),
			hit.get("pane") == "now_playing" and absf(float(hit.get("fraction", -1.0)) - 0.25) < 0.01)
	var hand = main.ui.pointer_hand
	main.ui._tablet_hit = hit
	main.ui.on_trigger(hand, true)
	_check("tablet bar: the trigger on it grabs the time", tablet.is_grabbing())
	main.ui.on_trigger(hand, false)
	main.ui._tablet_hit = {}
	await _frames(3)
	var pos: float = main.player.get_position()
	_check("tablet bar: let go at once, the film is at ~25%% (%.1f s of %.0f)" % [pos, dur], not tablet.is_grabbing()
			and absf(pos - dur * 0.25) < dur * 0.05)
	# Grabbed at 20 %, moved to 60 % along the tablet's plane, let go there.
	var p20: Variant = tablet.plane_point(eye, ((at.call(0.2) as Vector3) - eye).normalized())
	var p60: Variant = tablet.plane_point(eye, ((at.call(0.6) as Vector3) - eye).normalized())
	_check("tablet bar: grabbed at 20 %", p20 != null and tablet.grab(p20))
	tablet.grab_move(p60)
	_check("tablet bar: the time follows the grab at once (%s)" % tablet.time_label.text,
			absf(tablet._scrub - 0.6) < 0.01 and tablet.time_label.text.begins_with(W.clock(tablet._scrub * dur)))
	_check("tablet bar: let go at 60 %", tablet.release())
	await _frames(3)
	pos = main.player.get_position()
	_check("tablet bar: the film is at ~60%% (%.1f s)" % pos, absf(pos - dur * 0.6) < dur * 0.05)
	# Chapters: a tick on the bar at each start but the first; the header names the one playing.
	var Chapters := preload("res://scripts/play/chapters.gd")
	var ch: Node = main.features.chapters
	ch.chapters = Chapters.normalise([{"start": 0.0, "title": "One"}, {"start": dur * 0.25, "title": "Two"},
			{"start": dur * 0.5, "title": "Three"}], dur)
	ch._update_current()
	await _frames(2)
	ui.tick()
	_check("tablet bar: a tick at each chapter (%d)" % tablet.tick_count(), tablet.tick_count() == 2)
	_check("header: the chapter playing (%s)" % ui._now.text, ui._now.text == "Chapter 3/3 Three")
	ch.chapters = Chapters.normalise([], dur)
	ch._update_current()
	await _frames(2)
	ui.tick()
	_check("no chapters: no ticks, no chapter in the header", tablet.tick_count() == 0 and ui._now.text == "")
	# The test pattern's own five chapters.
	ch.reload()
	await _frames(2)
	ui.tick()
	_check("the pattern's chapters: four ticks, the chapter in the header (%d, %s)" % [tablet.tick_count(), ui._now.text],
			tablet.tick_count() == 4 and ui._now.text.begins_with("Chapter ") and ui._now.text.contains("/5 "))
	# Trick play's speed by the time.
	var trick: Node = main.features.trick
	trick.speed = 4.0
	await _frames(2)
	_check("tablet time: the trick speed after it (%s)" % tablet.time_label.text, tablet.time_label.text.ends_with("4x"))
	trick.speed = 0.0
	await _frames(2)


## Panel open, the pointer controller's stick moves the focus and its trigger activates the focused control, without
## aiming.
func _docked_focus_checks(ui: PaneUI) -> void:
	main.ui.hide_panel()
	await _frames(2)
	main.ui.show_panel()
	await _seconds(0.3)
	var hand = main.ui.pointer_hand
	_check("stick focus: nothing has the focus on opening", ui.default_focus() == null
			and main.ui.panel.focus_owner() == null)
	# The first push with nothing focused: the tab's row on the rail.
	main.ui.on_stick(hand, Vector2(0, -1), 0.016)
	main.ui.on_stick(hand, Vector2.ZERO, 0.016)
	await _frames(2)
	_check("stick focus: the first push focuses the tab's row on the rail",
			main.ui.panel.focus_owner() == ui.tablet_tab_buttons[ui.current_tab])
	var play: Control = ui._play_button
	play.grab_focus()
	await _frames(2)
	_check("stick focus: the play button has the focus", main.ui.panel.focus_owner() == play)
	main.ui.on_stick(hand, Vector2(1, 0), 0.016)
	main.ui.on_stick(hand, Vector2.ZERO, 0.016)
	await _frames(2)
	var focus: Control = main.ui.panel.focus_owner()
	_check("stick focus: stick right moves the focus to Stop (%s)" % (focus.get_meta("label", "") if focus != null
			else "none"), focus is Button and str((focus as Button).get_meta("label", "")) == "Stop")
	main.ui.on_stick(hand, Vector2(1, 0), 0.016)
	main.ui.on_stick(hand, Vector2.ZERO, 0.016)
	await _frames(2)
	focus = main.ui.panel.focus_owner()
	_check("stick focus: and on to +10 s (%s)" % (focus.get_meta("label", "") if focus != null
			else "none"), focus is Button and str((focus as Button).get_meta("label", "")) == "+10 s")
	var pos: float = main.player.get_position()
	main.ui.on_trigger(hand, true)
	main.ui.on_trigger(hand, false)
	await _frames(3)
	_check("stick focus: the trigger activates the focused control", absf(main.player.get_position() - pos - 10.0) < 1.0)
	_check("stick focus: the stick is the panel's, not the seek", main.ui.on_stick(hand, Vector2(1, 0), 0.016))
	main.ui.on_stick(hand, Vector2.ZERO, 0.016)
	_check("stick focus: the other controller keeps its own bindings", not main.ui.on_stick(main.ui.other_hand,
			Vector2(1, 0), 0.016) and not main.ui.on_trigger(main.ui.other_hand, true))
	main.ui.on_trigger(main.ui.other_hand, false)


## Network: add a host with the on-pane keyboard, browse its (simulated, without MediaBrowser) shares on worker
## threads, open a file from a share; an unreachable host; desktop typing into a field.
func _network_checks(ui: PaneUI) -> void:
	var files = ui.files
	ui.show_tab(PaneUI.Tab.FILES)
	await _frames(2)
	await _click(_find_button(ui, "Network"))
	_check("Network place opens the host list", files.current == "network://" and files.row_button("+ Add host") != null)
	await _click(files.row_button("+ Add host"))
	var form = files.get_form()
	_check("add-host form opens over the list and the rail", form.visible and not files.list_scroll().is_visible_in_tree()
			and not ui._rail_scroll.visible)
	await _frames(2)
	_check("the host form and keyboard fit the pane (%d of %d px)" % [ui.get_combined_minimum_size().y,
			main.ui.panel.resolution.y], ui.get_combined_minimum_size().y <= main.ui.panel.resolution.y)
	await _type_on_keyboard(ui, "nas.local")
	await _click(form.get_field("user"))
	await _type_on_keyboard(ui, "viewer")
	await _click(form.get_field("password"))
	await _type_on_keyboard(ui, "pw")
	_check("on-pane keyboard types into the focused fields (%s / %s)" % [form.get_field("host").text,
			form.get_field("user").text], form.get_field("host").text == "nas.local"
			and form.get_field("user").text == "viewer" and form.get_field("password").text == "pw")
	await _click(_find_button(ui, "Save"))
	var hosts: Array = NetworkHosts.hosts
	_check("Save stores the host", hosts.size() == 1 and hosts[0]["host"] == "nas.local" and hosts[0]["user"] == "viewer"
			and files.list_scroll().is_visible_in_tree() and ui._rail_scroll.visible)

	await _click(files.row_button("smb://nas.local"))
	_check("host listing runs in the background (busy right after the click)", files.is_busy())
	await _wait_listing(files)
	if DirectoryLister.has_media_browser():
		# A real SMB client: nas.local doesn't exist here, so its listing is an error row. The simulated shares below
		# need an engine build without MediaBrowser.
		_check("a host that doesn't resolve shows its error (%s)" % ", ".join(files.row_texts()), _has_error_row(files))
		print("SKIP simulated share browsing: this engine build has a real MediaBrowser")
	else:
		await _simulated_share_checks(files)

	NetworkHosts.save_host(-1, {"host": "offline.invalid"})
	files.open_folder("smb://offline.invalid")
	await _wait_listing(files)
	_check("an unreachable host shows its error", _has_error_row(files))

	# Desktop keyboard into a field: the key types, the shortcut (X = swap eyes) doesn't fire.
	files.open_folder("network://")
	await _frames(2)
	await _click(files.row_button("+ Add host"))
	var swap: bool = main.mode.swap
	var ev := InputEventKey.new()
	ev.keycode = KEY_X
	ev.unicode = "x".unicode_at(0)
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	_check("desktop keys type into the focused field, not the shortcuts", form.get_field("host").text.ends_with("x")
			and main.mode.swap == swap)
	await _click(_find_button(ui, "Cancel"))
	NetworkHosts.hosts.clear()


## Without MediaBrowser the lister simulates shares (scripts/net/directory_lister.gd): browse and open from them.
func _simulated_share_checks(files: Node) -> void:
	_check("host lists its shares (%s)" % ", ".join(files.row_texts()), files.row_button("Movies/") != null
			and files.row_button("Public/") != null)
	await _click(files.row_button("Movies/"))
	await _wait_listing(files)
	await _click(files.row_button("3D/"))
	await _wait_listing(files)
	_check("share folders list (%s)" % files.current, files.current == "smb://nas.local/Movies/3D"
			and files.get_video_paths().size() == 2)
	var row: Button = files.row_button("Animated.Feature")
	_check("the share's 3D file row has a mode chip", row != null and _has_chip(row))
	await _click(row)
	await _frames(5)
	_check("smb:// file opens like a local one, half SBS guessed (%s)" % main.mode.to_id(),
			str(main.current_path).begins_with("smb://nas.local/Movies/3D/Animated.Feature") and main.mode.to_id() == "flat_sbs_half")
	_check("playlist is the share folder's videos", main.playlist.size() == 2)
	main.ui.show_panel()
	await _seconds(0.3)
	await _click(files.row_button(".."))
	await _wait_listing(files)
	_check("up goes to the parent folder on the share", files.current == "smb://nas.local/Movies")


func _has_error_row(files: Node) -> bool:
	for t: String in files.row_texts():
		if t.begins_with("(Can't"):
			return true
	return false

func _has_chip(row: Control) -> bool:
	for c in row.find_children("*", "Label", true, false):
		if (c as Label).theme_type_variation == &"ChipLabel":
			return true
	return false


## The runtime's dashboard / headset off, simulated: focus loss pauses, focus back resumes after a short delay,
## but never a film the user paused.
func _focus_checks() -> void:
	var player: Node = main.player
	main.on_session_state("session_focussed")
	if not player.is_playing():
		player.play()
	await _frames(3)
	main.on_session_state("session_visible")
	_check("dashboard (focus lost) pauses", not player.is_playing() and main.auto_paused)
	main.on_session_state("session_focussed")
	await _seconds(0.1)
	_check("focus back: still paused during the grace delay", not player.is_playing())
	await _seconds(0.4)
	_check("focus back: resumed after the delay", player.is_playing() and not main.auto_paused)
	# Headset off (synchronized) and on again.
	main.on_session_state("session_visible")
	main.on_session_state("session_synchronized")
	_check("headset off pauses", not player.is_playing() and main.auto_paused)
	main.on_session_state("session_visible")
	main.on_session_state("session_focussed")
	await _seconds(0.5)
	_check("headset on again resumes", player.is_playing())
	# Paused by the user: stays paused.
	player.pause()
	main.on_session_state("session_visible")
	_check("user pause: no automatic pause recorded", not main.auto_paused)
	main.on_session_state("session_focussed")
	await _seconds(0.5)
	_check("user pause: stays paused when focus comes back", not player.is_playing())
	# Auto-paused, then the user presses play / pause meanwhile: that wins.
	player.play()
	main.on_session_state("session_visible")
	player.play()
	player.pause()
	main.on_session_state("session_focussed")
	await _seconds(0.5)
	_check("user action while auto-paused cancels the resume", not player.is_playing())
	player.play()


func _seconds(s: float) -> void:
	await main.get_tree().create_timer(s).timeout


func _wait_listing(files: Node) -> void:
	for i in 300:
		if not files.is_busy():
			await _frames(1)
			return
		await _frames(1)
	_check("listing finished within 300 frames", false)


func _type_on_keyboard(ui: PaneUI, text: String) -> void:
	for ch in text:
		var key: Button = null
		for b: Button in ui.find_children("*", "Button", true, false):
			if b.text == ch and b.is_visible_in_tree():
				key = b
		if key == null:
			_check("key '%s' on the keyboard" % ch, false)
			return
		await _click(key)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = pressed
		Input.parse_input_event(key)
		await _frames(2)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])


## A visible button with this text; on the pane, failing that, one on another section's card of the tab on show,
## whose section is then picked (the tablet shows one section at a time; the others' cards are out of the tree).
func _find_button(root: Node, text: String) -> Button:
	# The transport's buttons are icons, their names in meta "label".
	var b := _find_where(root, func(c: Button) -> bool: return c.text == text or str(c.get_meta("label", "")) == text)
	if b == null:
		push_error("No button '%s'" % text)
	return b


func _find_diagram(root: Node, word: String) -> Button:
	var b := _find_where(root, func(c: Button) -> bool: return c.has_meta("word") and str(c.get_meta("word")) == word)
	if b == null:
		push_error("No mode diagram '%s'" % word)
	return b


func _find_where(root: Node, pred: Callable) -> Button:
	# Not the sections column's buttons: a section is often named as its main switch (Slideshow, Spatial sound).
	var column: Node = (root as PaneUI)._sections_box if root is PaneUI else null
	for c in root.find_children("*", "Button", true, false):
		if pred.call(c) and (c as Button).is_visible_in_tree() and not (column != null and column.is_ancestor_of(c)):
			return c
	if root is PaneUI:
		var ui := root as PaneUI
		for card: Control in ui.cards(ui.current_tab):
			if card.get_parent() != null and card.is_visible_in_tree():
				continue
			for c in card.find_children("*", "Button", true, false):
				if pred.call(c) and _shown_in(c as Control, card):
					ui.show_section(W.card_section(card))
					return c
	return null


## Shown once its card is: itself and everything up to the card visible.
func _shown_in(c: Control, card: Control) -> bool:
	var n: Node = c
	while n != null and n != card:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		n = n.get_parent()
	return n == card


## Picks the tab and the section a control is in (the tablet shows one section of a tab at a time), so it is in the
## tree and can be seen. Then a couple of frames for the layout.
func _reveal(ui: PaneUI, c: Control) -> void:
	for t in ui.tabs.size():
		if ui.tabs[t].is_ancestor_of(c) and ui.current_tab != t:
			ui.show_tab(t)
	for t in ui.tabs.size():
		for card: Control in ui.cards(t):
			if card.is_ancestor_of(c):
				if ui.current_tab != t:
					ui.show_tab(t)
				ui.show_section(W.card_section(card))
	await _frames(3)


func _pixel_to_screen(pixel: Vector2) -> Vector2:
	return (main.camera as Camera3D).unproject_position(main.ui.panel.pixel_to_world(pixel))


## The ray from the camera through the pane pixel, intersected by the pane as a controller's ray would be.
func _hit_for_pixel(pixel: Vector2) -> Dictionary:
	var world: Vector3 = main.ui.panel.pixel_to_world(pixel)
	var origin: Vector3 = main.camera.global_position
	var hit: Dictionary = main.ui.panel.ray_hit(origin, (world - origin).normalized())
	if hit.is_empty() or (hit["pixel"] as Vector2).distance_to(pixel) > 1.0:
		_check("ray hits the pane at pixel %s (got %s)" % [pixel, hit.get("pixel")], false)
	return hit if not hit.is_empty() else {"pixel": pixel}


func _click(control: Control) -> void:
	if control == null:
		_check("control found", false)
		return
	# A section just picked (_find_button()) is laid out over the next frames.
	await _frames(2)
	if not control.is_visible_in_tree():
		_check("control %s visible" % (control.get("text") if control is Button else control.name), false)
	await _bring_on_pane(control)
	await _click_pixel(control.get_global_rect().get_center())


## A tab by its row on the rail, clicked as the laser would. A row past the pane's lower edge can't be: the tab is
## shown directly then, as "the menu fits the tablet's main pane" fails for it once rather than at every click.
func _rail(ui: PaneUI, tab: int) -> void:
	var b: Button = ui.tablet_tab_buttons[tab]
	if b.get_global_rect().end.y <= main.ui.panel.resolution.y:
		await _click(b)
	else:
		ui.show_tab(tab)
		await _frames(3)


## Scrolls the control's list so it is in view, as a drag or the stick would.
func _bring_on_pane(control: Control) -> void:
	var p := control.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if not (p is ScrollContainer):
		return
	# Twice: a tab just shown may still be settling its height, which limits the first scroll.
	for i in 2:
		(p as ScrollContainer).ensure_control_visible(control)
		await _frames(2)
	# The list may reach past the pane's lower edge (see "the menu fits the tablet's main pane"): scroll on until the
	# control is on the pane, where it can be.
	var below: float = control.get_global_rect().end.y - (main.ui.panel.resolution.y - 4.0)
	if below > 0.0:
		(p as ScrollContainer).scroll_vertical += ceili(below)
		await _frames(2)


func _click_pixel(pixel: Vector2) -> void:
	var hit := _hit_for_pixel(pixel)
	main.ui.panel.pointer_move(hit["pixel"])
	await _frames(1)
	main.ui.panel.pointer_button(hit["pixel"], true)
	await _frames(1)
	main.ui.panel.pointer_button(hit["pixel"], false)
	await _frames(2)


## A press at `from`, moved to `to` and let go there. Both are kept on the pane: past its edge a controller's ray
## misses it and the pane hears nothing more.
func _drag(from: Vector2, to: Vector2) -> void:
	var res := Vector2(main.ui.panel.resolution)
	from = from.clamp(Vector2.ONE, res - Vector2.ONE * 2.0)
	to = to.clamp(Vector2.ONE, res - Vector2.ONE * 2.0)
	main.ui.panel.pointer_move(_hit_for_pixel(from)["pixel"])
	await _frames(1)
	main.ui.panel.pointer_button(_hit_for_pixel(from)["pixel"], true)
	for i in range(1, 11):
		await _frames(1)
		main.ui.panel.pointer_move(_hit_for_pixel(from.lerp(to, i / 10.0))["pixel"])
	main.ui.panel.pointer_button(_hit_for_pixel(to)["pixel"], false)
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Queue, Favourites and Search places (#78, #76), the speed choice (#69) and the frame buttons (#80).
func _places_checks(ui: PaneUI) -> void:
	var files = ui.files
	ui.show_tab(PaneUI.Tab.FILES)
	files.open_folder("stub://")
	await _frames(2)
	await _click(files.row_button("Flat 3D, side by side (full)"))
	await _frames(3)
	main.ui.show_panel()
	await _seconds(0.3)
	await _click(_find_button(ui, "Queue"))
	_check("Queue place lists the playlist with the playing file (%d rows)" % files.row_texts().size(),
			files.current == "queue://" and files.row_button("Playing: ") != null)
	var at: int = main.playlist_index
	await _click(files.row_button("stub://flat_mono"))
	await _frames(3)
	_check("a queue row jumps there", main.playlist_index != at and str(main.current_path) == "stub://flat_mono")
	main.ui.show_panel()
	await _seconds(0.3)
	await _click(_find_button(ui, "Favourites"))
	await _click(files.row_button("+ Add the playing file"))
	_check("the playing file becomes a favourite", main.features.library.is_favourite(main.current_path)
			and files.row_button("stub://flat_mono") != null)
	await _click(_find_button(ui, "Search"))
	await _click(files.row_button("Search:"))
	var form = files.get_search_form()
	_check("the search form opens with the keyboard", form.visible)
	_check("the search form fits the pane (%d px)" % ui.get_combined_minimum_size().y,
			ui.get_combined_minimum_size().y <= main.ui.panel.resolution.y)
	await _type_on_keyboard(ui, "mono")
	await _click(_find_button(ui, "Search"))
	await _frames(3)
	_check("search finds the favourite (%s)" % ", ".join(files.row_texts()), files.row_button("stub://flat_mono") != null)
	main.features.library.remove_favourite(main.current_path)
	await _rail(ui, PaneUI.Tab.SOUND)
	await _click(_find_button(ui, "1.5x"))
	_check("Sound: the speed choice sets 1.5x", is_equal_approx(main.features.speed.speed, 1.5))
	main.features.speed.reset()
	# Director mode (#8) in the Subtitles tab: the find form, the keyboard, an answer.
	await _rail(ui, PaneUI.Tab.SUBTITLES)
	await _click(_find_button(ui, "Inside the picture"))
	_check("Subtitles: Inside the picture moves the band (%s)" % main.features.subtitles.display.position_mode,
			str(main.features.subtitles.display.position_mode) == "inside")
	await _click(_find_button(ui, "Below the picture"))
	await _click(_find_button(ui, "Find a line"))
	var find = ui.subtitles._find_form
	_check("Subtitles: Find a line opens the form with the keyboard", find.is_visible_in_tree() and not ui._rail_scroll.visible)
	if find.is_visible_in_tree():
		await _type_on_keyboard(ui, "line")
		await _click(_find_button(ui, "Search"))
		for i in 120:
			if ui.subtitles._script_label.text != "Searching..." and ui.subtitles._script_label.text != "":
				break
			await _frames(1)
		_check("Subtitles: the search answers (%s)" % ui.subtitles._script_label.text, not find.is_visible_in_tree()
				and ui._rail_scroll.visible and ui.subtitles._script_label.text != "")
	else:
		# Put the tab back as Cancel would, so what follows is not hidden too.
		ui.subtitles._hide_find()
		print("SKIP Subtitles search: the find form did not show")
	# The script's track picker: rows only when there is a choice; a pick searches that track.
	var st = ui.subtitles
	st._set_script_tracks([{"id": "t2", "label": "English"}, {"id": "t3", "label": "French"}], "t2")
	await _frames(1)
	var french := _find_button(ui, "Script from: French")
	_check("Subtitles: two script tracks show two rows, the chosen one marked", st._script_tracks.get_child_count() == 2
			and (st._script_tracks.get_child(0) as Button).button_pressed and french != null)
	await _click(french)
	_check("Subtitles: picking French searches that track (%s)" % st._script_track, st._script_track == "t3")
	st._set_script_tracks([{"id": "t2", "label": "English"}], "t2")
	await _frames(1)
	_check("Subtitles: one track, no rows", st._script_tracks.get_child_count() == 0)
	# While the engine reads the whole film for its subtitles, the line says how long so far.
	var Director := preload("res://scripts/director/director.gd")
	var key := "%s|t2" % main.current_path
	Director._building[key] = {"started": Time.get_ticks_msec() - 12000, "source": "engine"}
	st._indexing = true
	st.tick()
	_check("Subtitles: reading the film shows its time (%s)" % st._script_label.text,
			st._script_label.text == "Reading the film for its subtitles: 12 s")
	Director._building.erase(key)
	st._indexing = false
	st._script_track = ""
	await _rail(ui, PaneUI.Tab.PICTURE)
	var before: float = main.player.get_position()
	await _click(_find_button(ui, "Frame forward"))
	await _frames(3)
	_check("Picture: Frame forward pauses and steps (%.3f -> %.3f)" % [before, main.player.get_position()],
			not main.player.is_playing())
	main.player.play()
	await _picture_checks(ui)
	await _picture_batch_checks(ui)
	await _room_batch_checks(ui)
	await _media_server_checks(ui)
	await _share_checks(ui)
	_check("Sound: no Play on a PC section (a dev tool, --pc-audio)", _find_where(ui, func(c: Button) -> bool: return c.text == "Play sound on a PC") == null)
	await _speakers_and_jog_checks(ui)
	await _batch3_checks(ui)
	await _stream_checks(ui)
	await _second_session_checks(ui)
	ui.show_tab(PaneUI.Tab.FILES)


## The second decoder session's features: Gapless next to Play on (#44), "In corner" (#87) and the corner film's
## group, seek-bar thumbnails (#40) and their switch, crossfade sliders (#94).
func _second_session_checks(ui: PaneUI) -> void:
	var f: Node = main.features
	ui.show_tab(PaneUI.Tab.FILES)
	ui.files.open_folder("queue://")
	await _frames(2)
	var gapless_was: bool = f.gapless.enabled
	await _click(_find_button(ui, "Gapless"))
	_check("Files, Queue: Gapless next to Play on", bool(f.gapless.enabled) != gapless_was)
	f.gapless.set_enabled(gapless_was)
	ui.files.open_folder(ProjectSettings.globalize_path("user://ui_test_pictures"))
	await _frames(3)
	_check("Files: In corner in a folder", ui.files._in_corner.is_visible_in_tree())
	ui.files._in_corner.set_pressed_no_signal(true)
	_check("Files: In corner with a picture opens it as usual and disarms",
			not ui.files._open_in_corner("/x/Beach.png") and not ui.files._in_corner.button_pressed)
	ui.files.open_folder("stub://")
	await _frames(2)
	_check("Files: no In corner for test patterns", not ui.files._in_corner.visible)
	_check("Picture: no Corner film group without one", not ui.picture._pip_box.visible)
	# Thumbnails: a seeded picture shows over the tablet's bar where the laser is on it; gone when it leaves.
	main.ui.show_panel()
	await _frames(2)
	var tablet: Tablet = main.ui.tablet
	var dur: float = main.player.get_duration()
	var thumbs: Node = f.thumbs
	thumbs.enabled = true
	thumbs.state = "opening"
	var img := Image.create_empty(16, 9, false, Image.FORMAT_RGB8)
	var tex := ImageTexture.create_from_image(img)
	thumbs._cache.append({"t": dur * 0.5, "asked": dur * 0.5, "tex": tex})
	tablet.hover_bar(0.5)
	await _frames(2)
	_check("Tablet bar: a picture over the bar at the laser's time (%s)" % tablet.thumb_label.text, tablet.thumb.visible
			and tablet.thumb_label.visible and tablet.thumb_label.text == W.clock(dur * 0.5)
			and (tablet.thumb.material_override as StandardMaterial3D).albedo_texture == tex)
	tablet.hover_bar(-1.0)
	await _frames(2)
	_check("Tablet bar: gone when the laser leaves", not tablet.thumb.visible and not tablet.thumb_label.visible)
	thumbs._cache.clear()
	thumbs._pending = -1.0
	thumbs.enabled = false
	thumbs.state = "off"
	tablet.hover_bar(0.5)
	await _frames(2)
	_check("Tablet bar: no picture with them off", not tablet.thumb.visible)
	tablet.hover_bar(-1.0)
	await _rail(ui, PaneUI.Tab.SYSTEM)
	_check("System: a Seek bar pictures switch, off", _find_button(ui, "Seek bar pictures") != null
			and not ui.system._thumbs.button_pressed)
	await _rail(ui, PaneUI.Tab.ROOM)
	await _reveal(ui, ui.room._crossfade_music)
	_check("Room: crossfade sliders", ui.room._crossfade_music.is_visible_in_tree()
			and ui.room._crossfade_video.is_visible_in_tree())


## Streams and trick play: the URL form plays media URLs and opens the rest as pages; Play as video plays anything;
## a source that can't seek hides the skips and shows LIVE by the tablet's time; 4x / 8x only where trick play works.
func _stream_checks(ui: PaneUI) -> void:
	var files = ui.files
	var got: Array = []
	var catch := func(p: String) -> void: got.append(p)
	files.file_selected.disconnect(main.ui._on_file_selected)
	files.file_selected.connect(catch)
	var form = files.get_url_form()
	form.open_requested.emit("  udp://@:1234 ")
	form.open_requested.emit("https://example.com/films/clip.ts?x=1")
	form.open_requested.emit("example.com")
	form.play_requested.emit("http://cam.local/stream")
	files.file_selected.disconnect(catch)
	files.file_selected.connect(main.ui._on_file_selected)
	_check("URL form: media URLs play, pages open as pages (%s)" % [got], got.size() == 4
			and got[0] == "udp://@:1234" and got[1] == "https://example.com/films/clip.ts?x=1"
			and str(got[2]).begins_with("browser://") and got[3] == "http://cam.local/stream")
	# Live: no skips or trick play on the pane, LIVE by the tablet's time; the skips back when it can seek.
	main.ui.show_panel()
	var tablet: Tablet = main.ui.tablet
	var live: Node = main.features.live
	var live_was := bool(live.live)
	live.live = true
	ui.set_playback(12.0, 0.0, true, false)
	tablet._update_now_playing()
	_check("Live: no skip or 4x / 8x buttons, LIVE by the tablet's time (%s)" % tablet.time_label.text,
			not ui._skip_buttons[0].visible and not ui._skip_buttons[1].visible and not ui._trick_buttons[0].visible
			and tablet.time_label.text.begins_with("LIVE"))
	live.live = live_was
	ui.set_playback(12.0, 600.0, true, true)
	tablet._update_now_playing()
	_check("Seekable again: the skips are back, no LIVE (%s)" % tablet.time_label.text, ui._skip_buttons[0].visible
			and not tablet.time_label.text.begins_with("LIVE"))
	var trick: Node = main.features.trick
	_check("Transport: 4x and 8x only where trick play works (%s)" % trick.available(),
			ui._trick_buttons.size() == 2 and ui._trick_buttons[0].visible == bool(trick.available()))
	await _rail(ui, PaneUI.Tab.SOUND)
	await _reveal(ui, ui.sound._live_delay)
	_check("Sound: a Live delay slider", ui.sound._live_delay.is_visible_in_tree())


## app-features' batch 3: auto crop and its footer line (#42), HDR brightness (#85), film grain (#92), Calibrate and
## night mode (#24, #26), the room's effects (#29, #81, #92, #84), the music chip (#64), the zoom lens (#38).
func _batch3_checks(ui: PaneUI) -> void:
	var f: Node = main.features
	await _rail(ui, PaneUI.Tab.PICTURE)
	var was_mode: VideoMode = main.mode.copy()
	main.set_video_mode(VideoMode.new(), false)
	await _frames(1)
	await _click(_find_button(ui, "Auto crop bars"))
	await _frames(3)
	ui.tick()
	_check("Picture: Auto crop bars on, the footer says what it found (%s)" % ui._footer_text.text,
			bool(f.auto_crop.enabled) and ui._footer_text.text.contains("  ·  ")
			and ui.picture._crop_grow.is_visible_in_tree())
	f.auto_crop.set_enabled(false)
	await _frames(3)
	main.set_video_mode(was_mode, false)
	_check("Picture: HDR brightness and film grain sliders", ui.picture._rows.has("hdr_target")
			and ui.picture._rows.has("grain") and ui.picture._rows.has("weave"))
	await _rail(ui, PaneUI.Tab.SOUND)
	_check("Sound: Calibrate next to the A/V offset", _find_button(ui, "Calibrate") != null)
	_check("Sound: night mode only when the engine has it (%s)" % f.night.available(),
			ui.sound._night_box.visible == bool(f.night.available()))
	await _rail(ui, PaneUI.Tab.ROOM)
	var bias_was: bool = f.bias.enabled
	await _click(_find_button(ui, "Bias light"))
	_check("Room: Bias light switches, with its strength", bool(f.bias.enabled) != bias_was
			and ui.room._bias_strength.visible == bool(f.bias.enabled))
	f.bias.set_enabled(bias_was)
	await _click(_find_button(ui, "React to the film"))
	_check("Room: React to the film switches", bool(f.react.enabled) and ui.room._react_strength.visible)
	f.react.set_enabled(false)
	_check("Room: time of day only in rooms that have it", ui.room._time_box.visible
			== (main.env != null and main.env.has_method("set_time_of_day")))
	ui.room.sync()
	# Music files list with a MUSIC chip.
	var dir := ProjectSettings.globalize_path("user://ui_test_pictures")
	FileAccess.open(dir.path_join("Song.mp3"), FileAccess.WRITE).store_string("not really music")
	ui.show_tab(PaneUI.Tab.FILES)
	ui.files.open_folder(dir)
	for i in 60:
		if ui.files.count_text() != "":
			break
		await _frames(1)
	var chip := false
	for row: Dictionary in ui.files._rows:
		if row["text"] == "Song.mp3" and row["button"] != null:
			for l in (row["button"] as Node).find_children("*", "Label", true, false):
				chip = chip or (l as Label).text == "MUSIC"
	_check("Files: a music file has a MUSIC chip", chip)
	ui.files.open_folder("stub://")
	await _rail(ui, PaneUI.Tab.SYSTEM)
	var lens_was: bool = f.zoom_lens.enabled
	await _click(_find_button(ui, "Zoom lens"))
	_check("System: the Zoom lens switch", bool(f.zoom_lens.enabled) != lens_was
			and ui.system._magnification.visible == bool(f.zoom_lens.enabled))
	f.zoom_lens.set_enabled(lens_was)
	ui.system.sync()


## Sound, Speakers (#21, #47): the switch and its line; System, Controllers: the jog wheel (#63).
func _speakers_and_jog_checks(ui: PaneUI) -> void:
	await _rail(ui, PaneUI.Tab.SOUND)
	var speakers: Node = main.features.speakers
	var was: bool = speakers.enabled
	if was:
		speakers.set_enabled(false)
	ui.sound.sync()
	await _click(_find_button(ui, "Spatial sound"))
	await _frames(3)
	_check("Sound: Spatial sound switches on, with its line (%s)" % ui.sound._speakers_status.text,
			bool(speakers.enabled) and ui.sound._lfe.is_visible_in_tree() and ui.sound._speakers_status.text != "")
	speakers.set_enabled(was)
	await _frames(3)
	await _rail(ui, PaneUI.Tab.SYSTEM)
	var jog: Node = main.features.jog
	var jog_was: bool = jog.enabled
	await _click(_find_button(ui, "Jog wheel"))
	_check("System: the Jog wheel switch", bool(jog.enabled) != jog_was
			and ui.system._jog_turn.visible == bool(jog.enabled))
	jog.set_enabled(jog_was)
	ui.system.sync()


## Sound, Play on a PC (#9): with no address the switch asks for one; Save starts the stream (no sink here: it keeps
## connecting); off stops it.
func _pc_audio_checks(ui: PaneUI) -> void:
	await _rail(ui, PaneUI.Tab.SOUND)
	var st = ui.sound
	main.settings.set_value("pc_audio", "host", "")
	st.sync()
	await _click(_find_button(ui, "Play sound on a PC"))
	_check("PC audio: no address yet, the switch asks for one", st._pc_form.is_visible_in_tree()
			and not ui._rail_scroll.visible)
	if not st._pc_form.is_visible_in_tree():
		# Put the tab back as Cancel would, so what follows is not hidden too.
		st._hide_form()
		main.settings.set_value("pc_audio", "host", "")
		print("SKIP PC audio's Save and off: the address form did not show")
		return
	st._pc_form.get_field().text = "127.0.0.1:47899"
	await _click(_find_button(ui, "Save"))
	await _frames(2)
	ui.tick()
	var n := PCAudio.instance()
	_check("PC audio: Save starts the stream (%s)" % st._pc_status.text, n != null
			and st._pc_toggle.button_pressed and st._pc_status.text.begins_with("Connecting to 127.0.0.1:47899")
			and st._pc_address.text == "PC: 127.0.0.1:47899")
	await _click(_find_button(ui, "Play sound on a PC"))
	await _frames(2)
	_check("PC audio: off stops it", PCAudio.instance() == null and not st._pc_toggle.button_pressed)
	main.settings.set_value("pc_audio", "host", "")


## System, Share files (docs/share.md): the switch starts the server for sharing only; its address shows without the
## pairing code, the QR code holds it; the phone remote's own address stays hidden; off stops the server.
func _share_checks(ui: PaneUI) -> void:
	await _rail(ui, PaneUI.Tab.SYSTEM)
	var sys = ui.system
	if sys._remote_toggle.button_pressed:
		print("SKIP share checks: the phone remote is on in these settings")
		return
	await _click(_find_button(ui, "Share this headset's files"))
	for i in 30:
		await _frames(1)
		ui.tick()
		if sys._share_url.visible:
			break
	_check("Share files: the address shows without the code (%s)" % sys._share_url.text, sys._share_url.visible
			and sys._share_url.text.ends_with("/share") and not sys._share_url.text.contains("k=")
			and sys._share_qr.visible)
	_check("Share files: the phone remote stays off", not sys._remote_toggle.button_pressed
			and not sys._remote_qr.visible)
	await _click(_find_button(ui, "Share this headset's files"))
	await _frames(2)
	sys._sync_remote()
	_check("Share files: off stops the server and hides the code", Remote.instance() == null
			and not sys._share_url.visible and not sys._share_qr.visible)


## Picture tab, app-features' second batch: size in degrees and its presets (#55), head follow (#33), deinterlace
## (#95), sharpen (#90); the lens (#73) and HDR (#85) groups only when they apply; the folder rule line (#83).
func _picture_batch_checks(ui: PaneUI) -> void:
	await _rail(ui, PaneUI.Tab.PICTURE)
	var pt = ui.picture
	var f: Node = main.features
	# The size presets and head follow are for a flat screen.
	var was_mode: VideoMode = main.mode.copy()
	main.set_video_mode(VideoMode.new(), false)
	await _frames(1)
	await _click(_find_button(ui, "Living room"))
	_check("Picture: the Living room preset (%.0f°, %s)" % [f.angle.angle(), f.angle.matching_preset()],
			f.angle.matching_preset() == "living_room" and absf(W.slider_of(pt._rows["angle"]).value - 32.0) < 1.0)
	await _click(_find_button(ui, "Follow my head"))
	_check("Picture: Follow my head unpins the screen", bool(f.pose.follow))
	await _click(_find_button(ui, "Follow my head"))
	_check("Picture: and again pins it", not bool(f.pose.follow))
	main.reset_screen()
	await _click(_find_button(ui, "Bob"))
	_check("Picture: Deinterlace Bob", str(f.deinterlace.mode) == "bob")
	await _click(_find_button(ui, "Off"))
	_check("Picture: Deinterlace Off", str(f.deinterlace.mode) == "off")
	if pt._rows.has("pc_sharpen"):
		await _reveal(ui, pt._rows["pc_sharpen"])
	_check("Picture: a Sharpen slider", pt._rows.has("pc_sharpen") and (pt._rows["pc_sharpen"] as Control).is_visible_in_tree())
	_check("Picture: no lens or HDR group for a flat SDR picture", not pt._lens_box.visible and not pt._hdr_box.visible)
	_check("Picture: Use for this folder is off for a test pattern (%s)" % main.current_path, pt._use_folder.disabled)
	# A folder rule for the open file's folder shows its line, and Clear removes it.
	var saved_path: String = main.current_path
	main.current_path = "/videos/vr/clip.mp4"
	f.folder_modes.set_rule("/videos/vr", "180_sbs")
	await _frames(1)
	_check("Picture: the folder rule line (%s)" % pt._folder_label.text, pt._folder_label.visible
			and pt._folder_label.text.contains("/videos/vr/") and not pt._clear_folder.disabled)
	await _click(_find_button(ui, "Clear folder rule"))
	_check("Picture: Clear folder rule", f.folder_modes.rules().is_empty() and not pt._folder_label.visible)
	main.current_path = saved_path
	main.set_video_mode(was_mode, false)
	pt.sync()


## Room tab, app-features' second batch: environment rows (every room, photo and glTF rooms included), seats in the
## cinema (#19), the floor reflection where there is a floor (#62), up next (#34) and intermission (#39).
func _room_batch_checks(ui: PaneUI) -> void:
	await _rail(ui, PaneUI.Tab.ROOM)
	var room = ui.room
	var f: Node = main.features
	var was_env := str(main.env_id)
	# The rows: the rooms that ship, then the viewer's own and the showrooms under their own headings.
	_check("Room: one row per environment (%d of %d)" % [room._env_rows.size(), main.get_environment_list().size()],
			room._env_rows.size() == main.get_environment_list().size() and room._envs.get_child_count() > 0)
	# The groups fold, all closed at first; opening one closes the others.
	room.open_group("")
	await _frames(2)
	var closed := true
	for t: String in room._groups:
		closed = closed and not (room._groups[t]["body"] as Control).visible
	_check("Room: the room groups are all closed", closed)
	await _click(room._groups["Cinemas"]["head"])
	await _frames(2)
	_check("Room: clicking Cinemas opens it", (room._groups["Cinemas"]["body"] as Control).is_visible_in_tree())
	await _click(_find_button(ui, "Cinema"))
	await _frames(2)
	_check("Room: the Cinema row opens the cinema, marked", str(main.env_id) == "cinema"
			and room._env_rows[room._env_ids.find("cinema")].button_pressed)
	room.open_group("Television")
	await _frames(2)
	_check("Room: opening Television closes Cinemas, whose heading names the room in use (%s)"
			% (room._groups["Cinemas"]["head"] as Button).text, not (room._groups["Cinemas"]["body"] as Control).visible
			and (room._groups["Television"]["body"] as Control).visible
			and (room._groups["Cinemas"]["head"] as Button).text.contains("·"))
	room.open_group("")
	await _reveal(ui, room._seat_box)
	_check("Room: the cinema has seats (%s)" % room._seat_label.text, room._seat_box.is_visible_in_tree())
	# The plan: a click on a seat's dot sits there; Default seat goes back to the room's own spot.
	var plan: Control = room._seat_plan
	await _frames(2)
	var dot: Vector2 = plan.point_of(3)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = dot
	plan._gui_input(press)
	await _seconds(0.6)
	_check("Room: a seat on the plan sits there (%s)" % room._seat_label.text, int(f.seat.seat) == 3)
	await _click(_find_button(ui, "Default seat"))
	await _seconds(0.6)
	_check("Room: Default seat, the room's own spot again", int(f.seat.seat) == -1)
	# Pointing at a seat (the layer's seat picking): a ray towards seat 5 aims at it; the trigger takes it.
	var seat5: Vector3 = main.env.global_transform * (f.seat.seats()[5] as Vector3)
	var from := seat5 + Vector3(0.3, 1.2, 2.0)
	var aim: Dictionary = main.ui.aimed_seat(from, (seat5 - from).normalized())
	_check("Room: a ray towards a seat aims at it (%s)" % aim.get("index", -1), int(aim.get("index", -1)) == 5)
	_check("Room: a ray at the ceiling aims at none", main.ui.aimed_seat(from, Vector3.UP).is_empty())
	main.ui.start_seat_pick()
	_check("Room: Pick a seat starts picking", main.ui.is_picking_seat())
	main.ui._show_seat_ring(aim)
	_check("Room: the aimed seat gets a ring on the floor", main.ui.seat_ring_shown())
	_check("Room: the trigger takes the aimed seat", main.ui.pick_seat(aim) and int(f.seat.seat) == 5
			and not main.ui.is_picking_seat() and not main.ui.seat_ring_shown())
	main.ui.start_seat_pick()
	var docked_before: bool = main.ui.docked
	main.on_menu(main.right_hand, true)
	main.on_menu(main.right_hand, false)
	_check("Room: the menu button cancels seat picking, the panel stays as it was", not main.ui.is_picking_seat()
			and main.ui.docked == docked_before and int(f.seat.seat) == 5)
	main.ui.start_seat_pick()
	_check("Room: B cancels seat picking", main.ui.on_back(main.right_hand) and not main.ui.is_picking_seat())
	_check("Room: B means previous file again when not picking", not main.ui.on_back(main.right_hand))
	_check("Room: the floor is 1.5 m down a ray from 1.5 m pointing straight down",
			is_equal_approx(main.ui.floor_distance(Vector3(0, 1.5, 0), Vector3.DOWN), 1.5))
	f.seat.choose_seat(-1)
	main.ui.show_panel()
	await _frames(2)
	await _rail(ui, PaneUI.Tab.ROOM)
	_check("Room: the reflection shows only where the room has a floor for it",
			room._reflection_box.visible == bool(f.reflection.available()))
	var up_was: bool = f.up_next.enabled
	await _click(_find_button(ui, "Up next countdown"))
	_check("Room: Up next countdown switches", bool(f.up_next.enabled) != up_was)
	f.up_next.set_enabled(up_was)
	await _click(_find_button(ui, "Intermission"))
	room.tick()
	_check("Room: Intermission on shows its length and a note (%s)" % room._intermission_note.text,
			bool(f.intermission.enabled) and room._intermission_minutes.visible and room._intermission_note.visible)
	f.intermission.set_enabled(false)
	main.set_environment(was_env)
	room.sync()


## Media servers (UPnP): the place exists; a server's listing (fed here, no network) gives folders by their upnp://
## paths, videos by their http:// URLs with the server's duration, and ".." to the parent the listing names.
func _media_server_checks(ui: PaneUI) -> void:
	ui.show_tab(PaneUI.Tab.FILES)
	var files = ui.files
	_check("Files: a Media servers place", files.get_places().any(func(p: Dictionary) -> bool:
		return p["path"] == "upnp://" and p["label"] == "Media servers"))
	var p := "upnp://uuid-1/64"
	files.current = p
	files._request += 1
	files._on_listed(files._request, p, {"error": "", "parent": "upnp://uuid-1/", "entries": [
		{"name": "Films", "is_dir": true, "size": 3, "path": "upnp://uuid-1/64%241"},
		{"name": "Trip_180_SBS", "is_dir": false, "size": 1000, "path": "http://192.168.1.5:8200/MediaItems/7.mkv",
				"duration": 3725.0}]})
	await _frames(1)
	var by_kind := {}
	for row: Dictionary in files._rows:
		by_kind[row["kind"]] = row
	_check("Media servers: .. goes to the parent the server named", by_kind.has("up")
			and by_kind["up"]["path"] == "upnp://uuid-1/")
	_check("Media servers: a folder keeps its upnp:// path", by_kind.has("dir")
			and by_kind["dir"]["path"] == "upnp://uuid-1/64%241")
	_check("Media servers: a video is its http:// URL, with the server's duration, in the playlist",
			by_kind.has("file") and files.get_video_paths() == ["http://192.168.1.5:8200/MediaItems/7.mkv"]
			and float(by_kind["file"].get("duration", 0.0)) == 3725.0)
	files.current = "upnp://"
	files._request += 1
	files._on_listed(files._request, "upnp://", {"error": "no media server answered on the LAN", "parent": "",
			"entries": []})
	await _frames(1)
	_check("Media servers: none found says so and offers to look again",
			files.row_button("Look again for media servers") != null
			and files.row_texts().has("(no media server answered on the LAN)"))
	files.open_folder("stub://")


## Pictures (#22): a folder lists them with a PICTURE chip; Picture, Slideshow turns it on and shows its timing.
func _picture_checks(ui: PaneUI) -> void:
	var dir := ProjectSettings.globalize_path("user://ui_test_pictures")
	DirAccess.make_dir_recursive_absolute(dir)
	Image.create_empty(8, 8, false, Image.FORMAT_RGB8).save_png(dir.path_join("Beach.png"))
	FileAccess.open(dir.path_join("notes.txt"), FileAccess.WRITE).store_string("not media")
	ui.show_tab(PaneUI.Tab.FILES)
	ui.files.open_folder(dir)
	for i in 60:
		if ui.files.count_text() != "":
			break
		await _frames(1)
	var texts: Array = []
	var chip := false
	for row: Dictionary in ui.files._rows:
		texts.append(row["text"])
		if row["text"] == "Beach.png" and row["button"] != null:
			for l in (row["button"] as Node).find_children("*", "Label", true, false):
				chip = chip or (l as Label).text == "PICTURE"
	_check("Files: a picture is listed with its chip, other files are not (%s)" % ", ".join(texts),
			texts.has("Beach.png") and not texts.has("notes.txt") and chip)
	await _rail(ui, PaneUI.Tab.PICTURE)
	var slideshow: Node = main.features.slideshow
	var was: bool = slideshow.enabled
	if was:
		slideshow.set_enabled(false)
	_check("Picture: Slideshow off hides its timing", not ui.picture._slide_seconds.visible)
	await _click(_find_button(ui, "Slideshow"))
	_check("Picture: Slideshow turns it on and shows its timing", slideshow.enabled and ui.picture._slide_seconds.visible
			and ui.picture._crossfade.visible)
	slideshow.set_enabled(was)


## Help lines under the Picture and Sound tabs' controls (ui/help_texts.gd), and the Curvature slider as a percentage
## (0 flat, 100 % = a radius equal to the screen distance).
func _help_and_curve_checks(ui: PaneUI) -> void:
	main.open_path("stub://flat_mono", false)
	main.set_video_mode(VideoMode.from_id("flat_mono"), false)
	await _frames(3)
	main.ui.show_panel()
	await _seconds(0.3)
	await _rail(ui, PaneUI.Tab.PICTURE)
	var curve_row: Control = ui.picture._rows["curve"]
	var help := _help_after(curve_row)
	_check("Picture: a help line under Curvature (%s)" % (help.text if help != null else "none"), help != null
			and help.text.contains("100 %") and help.visible == curve_row.visible)
	var weave := _help_after(ui.picture._rows["weave"])
	_check("Picture: a help line under Gate weave", weave != null and weave.text.contains("wobble"))
	# On every card of the tab, those of the sections not on show too.
	var helps := _tab_nodes(ui, PaneUI.Tab.PICTURE).filter(func(n: Node) -> bool: return n is Label and n.has_meta("help"))
	_check("Picture: help lines for most controls (%d)" % helps.size(), helps.size() >= 25)
	var auto_lines := helps.filter(func(n: Node) -> bool: return (n as Label).text.begins_with("Auto: "))
	_check("Picture: the Deinterlace choice Auto gets no 3D-mode help", auto_lines.size() <= 1)
	var sound_helps := _tab_nodes(ui, PaneUI.Tab.SOUND).filter(func(n: Node) -> bool:
		return n is Label and n.has_meta("help"))
	var boost := sound_helps.filter(func(n: Node) -> bool: return (n as Label).text.contains("5.1 sound"))
	_check("Sound: help lines, one for dialogue boost (%d lines)" % sound_helps.size(), sound_helps.size() >= 6
			and boost.size() == 1)
	var slider: HSlider = W.slider_of(curve_row)
	await _reveal(ui, slider)
	await _bring_on_pane(slider)
	await _frames(2)
	var r := slider.get_global_rect()
	# Drag past each end (the pointer keeps the slider while held), so the value is exactly 100 and 0.
	var mid := r.get_center()
	await _drag(mid, Vector2(r.end.x + 40.0, mid.y))
	await _frames(2)
	var curve: Node = main.features.curve
	_check("Curvature at 100 %%: radius = the screen distance (%.2f m at %.2f m)" % [curve.radius, main.screen_distance],
			is_equal_approx(curve.amount, 1.0) and is_equal_approx(curve.radius, main.screen_distance))
	await _drag(mid, Vector2(r.position.x - 60.0, mid.y))
	await _frames(2)
	_check("Curvature at 0 %: flat", curve.radius == 0.0 and (ui.picture._rows["curve"].get_meta("value_label") as Label).text == "flat")
	_check("no Curve to distance button (100 % is that)",
			_buttons_or_labels(ui, PaneUI.Tab.PICTURE, ["Curve to distance"]).is_empty())
	ui.show_tab(PaneUI.Tab.FILES)


## The help line right after a control row, or null.
func _help_after(row: Control) -> Label:
	var parent := row.get_parent()
	var i := row.get_index() + 1
	if i < parent.get_child_count() and parent.get_child(i).has_meta("help"):
		return parent.get_child(i) as Label
	return null


## System, Panel: the recentre hold applies at once; left-handed picks the left pointer; Larger panel makes the menu's
## text larger; reset. The front panel's size, distance and head follow are gone with it.
func _layout_checks(ui: PaneUI) -> void:
	await _rail(ui, PaneUI.Tab.SYSTEM)
	var tablet: Tablet = main.ui.tablet
	_check("System: no Size, Distance, Follow my head or Tablet menu: the tablet is the only menu",
			_buttons_or_labels(ui, PaneUI.Tab.SYSTEM, ["Size", "Distance", "Follow my head", "Tablet menu"]).is_empty())
	_check("Panel: the tablet's menu, its size (%s m)" % main.ui.panel.size_m, _panel_on_tablet())
	main.settings.set_value("pane", "recentre_hold", 1.0)
	ui.system.layout_changed.emit()
	_check("recentre_hold 1 s applies", is_equal_approx(main.ui.menu.hold, 1.0))
	await _click(_find_button(ui, "Left-handed"))
	_check("Left-handed: the left hand points", main.ui.pointer_hand == main.left_hand
			and bool(main.features.access.get_value("left_handed")))
	var text_was: float = ui.text_scale
	main.features.access.set_value("ui_scale", 1.5)
	await _frames(2)
	_check("Larger panel 1.5x: the menu's text half as big again (%.2f -> %.2f)" % [text_was, ui.text_scale],
			is_equal_approx(ui.text_scale, tablet.panel_text_scale() * 1.5) and ui.text_scale > text_was)
	await _click(_find_button(ui, "Reset layout"))
	await _frames(2)
	_check("Reset layout: right hand, 0.6 s, the text size, in front of the head", main.ui.pointer_hand == main.right_hand
			and is_equal_approx(main.ui.menu.hold, 0.6) and is_equal_approx(ui.text_scale, tablet.panel_text_scale())
			and main.ui.is_open() and _tablet_in_front() and _panel_on_tablet())
	ui.show_tab(PaneUI.Tab.FILES)


## The Buttons and Labels of a tab, its detached cards too, with one of these texts.
func _buttons_or_labels(ui: PaneUI, tab: int, texts: Array) -> Array:
	return _tab_nodes(ui, tab).filter(func(c: Node) -> bool:
		return (c is Button or c is Label) and str(c.get("text")) in texts)


## Every node of a tab, those on its cards out of the tree (sections not on show) too.
func _tab_nodes(ui: PaneUI, tab: int) -> Array:
	var roots: Array = [ui.tabs[tab]]
	roots.append_array(ui.cards(tab))
	var seen := {}
	for r: Node in roots:
		for c in r.find_children("*", "", true, false):
			seen[c] = true
	return seen.keys()


## The watch-along card (#54) through the dev registry's `card` command, as the PC link would send it.
func _card_checks() -> void:
	const DevCommands := preload("res://scripts/dev/dev_commands.gd")
	main.ui.hide_panel()
	main.open_path("stub://flat_mono", false)
	main.set_video_mode(VideoMode.from_id("flat_mono"), false)
	await _frames(3)
	var png := Image.create_empty(32, 16, false, Image.FORMAT_RGB8)
	png.fill(Color.WHITE)
	var r: Dictionary = await DevCommands.execute("card", {"text": "The actor is the one from the earlier scene.",
			"title": "Who is that", "image": Marshalls.raw_to_base64(png.save_png_to_buffer())}, false)
	await _frames(3)
	var card = main.ui.card
	# Beside the picture as seen from the head: the card's left edge right of the screen's top-right corner. (Not in
	# metres: a far screen's card comes no further than WatchCard.NEAR_DISTANCE.)
	var head: Vector3 = main.camera.global_position
	var yaw := func(p: Vector3) -> float: return rad_to_deg(atan2(p.x - head.x, -(p.z - head.z)))
	var corner_yaw: float = yaw.call(main.screen.top_right_corner())
	var left_yaw: float = yaw.call(card.global_position - card.global_basis.x * card.size_m.x * 0.5)
	_check("card command shows a card beside the screen (%s; left edge at %.1f°, the screen's corner at %.1f°)"
			% [r.get("result"), left_yaw, corner_yaw], bool(r.get("ok", false)) and card.is_showing()
			and left_yaw > corner_yaw and card._image.visible)
	var events: Array = []
	card.dismissed.connect(func(id: String, how: String) -> void: events.append(how))
	var origin: Vector3 = main.camera.global_position
	var dir: Vector3 = (card.global_position - origin).normalized()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main.ui.on_mouse(click, [origin, dir])
	await _seconds(0.3)
	_check("a click on the card dismisses it", not card.visible and events == ["user"])
	await DevCommands.execute("card", {"text": "short", "seconds": 0.3}, false)
	await _seconds(0.7)
	_check("a card times out", not card.visible and events == ["user", "timeout"])
	var big := PackedByteArray()
	big.resize(300 * 1024)
	r = await DevCommands.execute("card", {"text": "x", "image": Marshalls.raw_to_base64(big)}, false)
	_check("an image over 256 KB is refused (%s)" % r.get("error", ""), not bool(r.get("ok", true)))


## Push-to-talk (#14): with a stand-in for dev-plumbing's node under a DevHost, the pointer hand's bumper records and
## the other keeps the labels; "Listening" shows while recording.
func _push_to_talk_checks(ui: PaneUI) -> void:
	var fake_script := GDScript.new()
	fake_script.source_code = "\n".join(["extends Node", "signal recording_changed(on: bool)", "var calls: Array = []",
			"func begin() -> bool:", "\tcalls.append(\"begin\")", "\trecording_changed.emit(true)", "\treturn true",
			"func end() -> float:", "\tcalls.append(\"end\")", "\trecording_changed.emit(false)", "\treturn 1.0", ""])
	fake_script.reload()
	var host := Node.new()
	host.name = "DevHost"
	var ptt: Node = fake_script.new()
	ptt.name = "PushToTalk"
	host.add_child(ptt)
	main.get_tree().root.add_child(host)
	main.ui.show_panel()
	await _seconds(1.2)
	_check("push-to-talk: the right hand's bumper talks", main.ui.talk_hand() == main.right_hand)
	var down: bool = main.ui.on_bumper(main.right_hand, true)
	ui.tick()
	_check("push-to-talk: bumper down records, Listening in the header (%s)" % ui.status_line_text(), down
			and ptt.calls == ["begin"] and ui.status_line_text().ends_with("Listening"))
	main.ui.on_bumper(main.right_hand, false)
	ui.tick()
	_check("push-to-talk: bumper up sends, Listening goes", ptt.calls == ["begin", "end"]
			and not ui.status_line_text().contains("Listening"))
	_check("push-to-talk: the left bumper is not the talk button", not main.ui.on_bumper(main.left_hand, true))
	main.ui.on_bumper(main.left_hand, false)
	host.queue_free()
	await _seconds(1.2)
	_check("push-to-talk: gone with the dev link", main.ui.talk_hand() == null)



## Hardware 10-bit video (scripts/play/hw_video.gd): the System row says which way 10-bit plays, read-only, with
## Details; there is no setup card, password field or installer; the overlay's decode text; the read command; and the
## dev link's rule for a masked field (the SMB host form's password).
func _hwvideo_checks(ui: PaneUI) -> void:
	var hw: Node = main.features.hwvideo
	var t0 := Time.get_ticks_msec()
	while not hw.probed and Time.get_ticks_msec() - t0 < 10000:
		await _frames(1)
	main.ui.show_panel()
	await _seconds(0.3)
	ui.show_tab(PaneUI.Tab.SYSTEM)
	await _frames(2)
	var s: Dictionary = hw.status()
	_check("hwvideo: the status says the path (%s)" % [s], hw.probed and s["path"] in ["p010", "q10c", "software"]
			and s["text"] == hw.PATH_TEXTS[s["path"]] and s.has("p010") and s.has("q10c") and s.has("hw_vp9"))
	_check("hwvideo: P010 first, as the engine takes it", s["path"] != "q10c" or not s["p010"])
	var row: Node = ui.system.find_child("HwVideoRow", true, false)
	for card: Control in ui.cards(PaneUI.Tab.SYSTEM):
		if row == null:
			row = card.find_child("HwVideoRow", true, false)
	if row != null:
		await _reveal(ui, row)
	_check("hwvideo: the System row says it (%s)" % (row._label.text if row != null else "no row"), row != null
			and row._label.text == "Hardware 10-bit video: " + s["text"])
	var setup_buttons := _buttons_or_labels(ui, PaneUI.Tab.SYSTEM, ["Set up", "Remove the setup", "Restart headset"]) \
			.filter(func(b: Node) -> bool: return b is Button)
	_check("hwvideo: no setup anywhere: no Set up, Remove the setup or password field (%s)" % [setup_buttons],
			row != null and setup_buttons.is_empty() and ui.find_child("HeadsetPassword", true, false) == null
			and ui.get("hw_card") == null)
	await _click(row._details_button)
	_check("hwvideo: Details tells the status in words (%s)" % row._details.text, row._details.is_visible_in_tree()
			and row._details.text.contains("P010") and row._details.text.contains("Q10C")
			and row._details.text.contains("VP9 in hardware"))
	await _click(row._details_button)

	# The overlay's decode path.
	var HwVideo := preload("res://scripts/play/hw_video.gd")
	_check("hwvideo: the overlay says hardware (10-bit) for a 10-bit hardware session",
			HwVideo.decode_text("hw", {"bit_depth": 10}, {"decode_path": "hardware"}) == "hardware (10-bit)"
			and HwVideo.decode_text("hw", {"bit_depth": 8}, {"decode_path": "hardware"}) == "hardware"
			and HwVideo.decode_text("hw", {"bit_depth": 10}, {"decode_path": "software"}) == "software (10-bit)"
			and HwVideo.decode_text("stub", {}, {}) == "stub")
	_check("hwvideo: the overlay says hardware (VP9) for a VP9 hardware session",
			HwVideo.decode_text("hw", {"bit_depth": 8, "codec": "vp9"}, {"decode_path": "hardware"}) == "hardware (VP9)"
			and HwVideo.decode_text("hw", {"bit_depth": 10, "codec": "vp9"}, {"decode_path": "hardware"}) == "hardware (VP9, 10-bit)"
			and HwVideo.decode_text("hw", {"bit_depth": 8, "codec": "vp9"}, {"decode_path": "software"}) == "software")
	_check("hwvideo: the overlay names the codec that only software decodes",
			HwVideo.decode_text("hw", {"bit_depth": 8, "codec": "msmpeg4v3"}, {"decode_path": "software"}) == "software (DivX 3)"
			and HwVideo.decode_text("hw", {"bit_depth": 8, "codec": "mpeg4"}, {"decode_path": "software"}) == "software (MPEG-4)"
			and HwVideo.decode_text("hw", {"bit_depth": 10, "codec": "av1"}, {"decode_path": "software"}) == "software (AV1, 10-bit)"
			and HwVideo.decode_text("hw", {"bit_depth": 8, "codec": "foo"}, {"decode_path": "software"}) == "software (FOO)")

	# The read command, and nothing left of the setup.
	var DevCommands := preload("res://scripts/dev/dev_commands.gd")
	_check("hwvideo: the status is a read command, and the setup's is gone", DevCommands.has_command("hwvideo_status")
			and DevCommands.assistant_level("hwvideo_status") == "read" and not DevCommands.has_command("hwsetup_status"))

	# The dev link never reads a masked field's text (the SMB host form's password).
	var BuiltinCommands := preload("res://scripts/dev/builtin_commands.gd")
	var masked := LineEdit.new()
	masked.secret = true
	masked.text = "example"
	_check("hwvideo: the dev link can't read a masked field", BuiltinCommands.is_secret_field(masked, "text")
			and BuiltinCommands.is_secret_field(masked, "get_text")
			and not BuiltinCommands.node_properties(masked).has("text"))
	masked.free()
	ui.show_tab(PaneUI.Tab.FILES)
