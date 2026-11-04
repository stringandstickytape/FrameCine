extends SceneTree

## Tests for the tablet prototype (ui/tablet.gd) in the real main scene: where it goes for a head pose (ahead and
## below, tilted up towards the eyes, by the head's heading only), the setting, and the menu button showing it with
## the front panel where the head is, keeping it there while the head moves, and hiding it with the panel; the two
## panes; the style document (its defaults valid, partial changes from outside, bad values refused with their paths,
## only the changes kept, reset); the now playing pane (title, played / total, the bar and its hit area, a long
## title cut; the text and bar centred as one); the laser's ray, a touch, skipping and dragging the bar; the
## old menu on the main pane in its tablet layout (lists down the left, one section at a time), dragging its lists;
## the fades.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_tablet.gd

const Tablet := preload("res://ui/tablet.gd")
const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	# The pose, for a head at 1.6 m looking down -Z.
	var head := Transform3D(Basis(), Vector3(0, 1.6, 0))
	var p := Tablet.pose(head)
	var to_eye := (head.origin - p.origin).normalized()
	_check("ahead and below the eyes (%s)" % p.origin, p.origin.z < -0.3 and p.origin.y < 1.35 and absf(p.origin.x) < 0.001)
	_check("its face points back towards the eyes (%.1f° off)" % rad_to_deg(p.basis.z.angle_to(to_eye)),
			p.basis.z.angle_to(to_eye) < deg_to_rad(15.0))
	_check("tilted TILT° from vertical", absf(rad_to_deg(p.basis.z.angle_to(Vector3.BACK)) - Tablet.TILT) < 0.1)
	_check("level side to side", absf(p.basis.x.y) < 0.001)
	_check("its top edge leans away", p.basis.y.z < 0.0 and p.basis.y.y > 0.0)
	var down := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-50)), head.origin)
	_check("looking down doesn't move it", Tablet.pose(down).is_equal_approx(p))
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(90)), head.origin)
	var q := Tablet.pose(turned)
	_check("turned 90° left: it goes round with the heading (%s)" % q.origin, q.origin.x < -0.3 and absf(q.origin.z) < 0.001)

	# The setting and the menu button.
	var layer: Node = main.ui
	var tablet: Tablet = layer.tablet
	_check("off by default", not tablet.enabled and not tablet.is_shown())
	tablet.set_enabled(true)
	_check("on: saved", main.settings.get_value("pane", "tablet", false) == true)
	main.camera.global_transform = head
	layer.hide_panel() # Open at launch.
	await _frames(1)
	layer.on_menu(null, true)
	layer.on_menu(null, false)
	await _frames(1)
	_check("menu: shown in front of the head", tablet.is_shown() and tablet.global_transform.is_equal_approx(p))
	_check("menu: the front panel opens too", layer.is_open())
	# The first seconds after launch place it again as the head settles (ui_layer.gd _replace_left): past them.
	layer._replace_left = 0.0
	main.camera.global_transform = turned
	await _frames(2)
	_check("the head turns: it stays where it was", tablet.global_transform.is_equal_approx(p))
	layer.on_menu(null, true)
	layer.on_menu(null, false)
	_check("menu again: hidden with the panel", not tablet.is_shown() and not layer.is_open())
	tablet.set_enabled(false)
	_check("off: the key goes", not main.settings.has_value("pane", "tablet"))
	layer.on_menu(null, true)
	layer.on_menu(null, false)
	_check("off: the menu opens only the front panel", layer.is_open() and not tablet.is_shown())

	# Two panes: a short now playing one on top, the main one below, a gap between, filling the tablet.
	var r: Dictionary = Tablet.pane_rects()
	var np: Rect2 = r["now_playing"]
	var mp: Rect2 = r["main"]
	_check("now playing on top, short", np.position.y > mp.end.y and np.size.y < mp.size.y * 0.5)
	_check("a gap of %.0f mm between them" % ((np.position.y - mp.end.y) * 1000.0),
			is_equal_approx(np.position.y - mp.end.y, Tablet.GAP))
	_check("the top edge where it was (%.3f), the main pane 25 %% deeper (%.4f)" % [np.end.y, mp.size.y],
			is_equal_approx(np.end.y, 0.13) and is_equal_approx(mp.size.y, 0.19 * 1.25))
	_check("together they fill the tablet", is_equal_approx(np.end.y - mp.position.y, Tablet.SIZE.y)
			and is_equal_approx(np.size.x, Tablet.SIZE.x) and is_equal_approx(mp.size.x, Tablet.SIZE.x))
	_check("the pane nodes sit there", tablet.now_playing.position.is_equal_approx(Vector3(0, np.get_center().y, 0))
			and tablet.main_pane.position.is_equal_approx(Vector3(0, mp.get_center().y, 0)))
	var top_mat: ShaderMaterial = tablet.now_playing.material_override
	_check("each pane's backdrop is its own size", (top_mat.get_shader_parameter("size") as Vector2).is_equal_approx(np.size))

	# The style: one JSON document, the defaults from ui/themes/tablet.json, changed from outside in part.
	var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string(Tablet.STYLE_PATH))
	_check("the default document is valid", defaults is Dictionary and Tablet.validate(defaults).is_empty())
	var st := tablet.style()
	_check("in use: the defaults", st == defaults)
	# The palette: plum and gold first; the panes take its plate and edge, the menu its colours.
	var pal: Dictionary = tablet.palette()
	_check("plum and gold by default (%s)" % tablet.palette_id(), tablet.palette_id() == "plum_gold"
			and pal["name"] == "Plum & gold" and tablet.palette_names().size() >= 6
			and tablet.palette_names()[0]["id"] == "plum_gold")
	var fill: Color = pal["plate"]
	_check("the plate: a dark plum, mostly opaque (%s)" % fill, fill.r > fill.g and fill.b > fill.g and fill.a > 0.6)
	_check("pane border: a hairline at 10 %", is_equal_approx(float(st["pane"]["border_width"]), 0.0009)
			and absf((pal["edge"] as Color).a - 0.1) < 0.01)
	var mat: ShaderMaterial = tablet.main_pane.material_override
	_check("both panes' shaders have it", (mat.get_shader_parameter("fill_color") as Color).is_equal_approx(fill)
			and (top_mat.get_shader_parameter("fill_color") as Color).is_equal_approx(fill)
			and is_equal_approx(float(mat.get_shader_parameter("corner_radius")), 0.024))
	_check("the menu's colours from the palette", tablet.menu_colours()["accent"] == pal["accent"]
			and tablet.menu_colours()["text"] == pal["ink"])
	_check("the time bar: the accent, the track the ink at 14 %",
			(tablet._bar_played.material_override as ShaderMaterial).get_shader_parameter("fill_color") == pal["accent"]
			and absf(((tablet._bar_track.material_override as ShaderMaterial).get_shader_parameter("fill_color") as Color).a - 0.14) < 0.01)
	_check("another palette: the plate and accent follow", tablet.set_style({"palette": "ink_sky"}, false).is_empty()
			and tablet.palette_id() == "ink_sky"
			and (mat.get_shader_parameter("fill_color") as Color).is_equal_approx(tablet.palette()["plate"])
			and tablet.menu_colours()["accent"] == tablet.palette()["accent"])
	_check("an unknown palette name falls back to the first", tablet.set_style({"palette": "neon"}, false).is_empty()
			and tablet.palette_id() == "plum_gold")
	_check("a palette can be added from outside", tablet.set_style({"palettes": {"test": {"name": "Test", "plate": "#000000cc",
			"edge": "#ffffff1a", "ink": "#ffffff", "ink2": "#ffffff99", "accent": "#ff0000", "accent_ink": "#000000"}},
			"palette": "test"}, false).is_empty() and tablet.palette()["accent"] == Color.RED
			and tablet.palette_names().size() >= 7)
	tablet.reset_style()
	var errors: Array = tablet.set_style({"pane": {"fill": "#ff000080"}, "now_playing": {"title": {"size": 0.02}}})
	_check("a partial change: no errors, the rest stays (%s)" % [errors], errors.is_empty()
			and tablet.style()["pane"]["fill"] == "#ff000080" and tablet.style()["pane"]["border_width"] == st["pane"]["border_width"]
			and is_equal_approx(float(tablet.style()["now_playing"]["title"]["size"]), 0.02))
	_check("it takes effect", (mat.get_shader_parameter("fill_color") as Color).is_equal_approx(Color.html("#ff000080"))
			and is_equal_approx(tablet.title_label.pixel_size, 0.02 / Tablet.FONT_PX))
	_check("only the changes are kept", main.settings.get_value("pane", "tablet_style", {}) == {
			"pane": {"fill": "#ff000080"}, "now_playing": {"title": {"size": 0.02}}})
	errors = tablet.set_style({"pane": {"border": "not a colour", "border_width": 0.5}, "shadow": 1,
			"now_playing": {"time": {"font": "comic"}}})
	_check("bad values: four errors with their paths, nothing changed (%s)" % [errors], errors.size() == 4
			and errors.any(func(e: Dictionary) -> bool: return e["path"] == "pane/border_width")
			and errors.any(func(e: Dictionary) -> bool: return e["path"] == "now_playing/time/font")
			and tablet.style()["pane"]["fill"] == "#ff000080")
	tablet.set_style({"pane": {"fill": null}})
	_check("null: back to the default for that value", not tablet.style()["pane"].has("fill")
			and (mat.get_shader_parameter("fill_color") as Color).is_equal_approx(fill)
			and is_equal_approx(float(tablet.style()["now_playing"]["title"]["size"]), 0.02))
	tablet.reset_style()
	_check("reset: the defaults again, nothing kept", tablet.style() == st
			and not main.settings.has_value("pane", "tablet_style"))

	# Now playing: the title, played / total, and the bar.
	tablet.set_enabled(true, false)
	main.open_path("stub://flat_mono")
	await _frames(3)
	tablet.show_at(head)
	await _frames(2)
	var dur: float = main.player.get_duration()
	_check("the title is the display title (%s)" % tablet.title_label.text, tablet.title_label.text != ""
			and main.display_title().begins_with(tablet.title_label.text.trim_suffix("…")))
	_check("the time reads played / total (%s)" % tablet.time_label.text, dur <= 0.0
			or tablet.time_label.text.ends_with(" / " + W.clock(dur)))
	var bar: Rect2 = tablet.bar_rect()
	var np_rect: Rect2 = Tablet.pane_rects()["now_playing"]
	_check("the bar runs along the lower half inside the padding", bar.position.y < 0.0 and bar.size.x > np_rect.size.x * 0.8)
	var stl := tablet.style()
	var block: float = Tablet._block_height(stl)
	var text_h: float = Tablet._text_height(stl)
	var title_size := float(stl["now_playing"]["title"]["size"])
	var ff: Font = tablet.title_label.font
	var box_mid := (ff.get_ascent(Tablet.FONT_PX) - ff.get_descent(Tablet.FONT_PX)) * 0.5 * tablet.title_label.pixel_size
	var caps_mid := tablet.title_label.position.y + box_mid - title_size * Tablet.CAP_MIDDLE
	_check("text and bar centred together: the block's top and bottom the same distance from the middle (%.4f, %.4f)"
			% [caps_mid + text_h * 0.5, bar.position.y], absf((caps_mid + text_h * 0.5) + bar.position.y) < 0.0005
			and is_equal_approx(bar.position.y, -block * 0.5))
	_check("the title above the bar, on the left; the time on the right", tablet.title_label.position.y > bar.end.y
			and tablet.title_label.position.x < 0.0 and tablet.time_label.position.x > 0.0)
	var on_bar := tablet.now_playing.to_global(Vector3(bar.position.x + bar.size.x * 0.25, bar.get_center().y, 0))
	_check("a point a quarter along the bar: 0.25", is_equal_approx(tablet.bar_fraction(on_bar), 0.25))
	var near := tablet.now_playing.to_global(Vector3(bar.end.x - 0.001, bar.get_center().y + Tablet.BAR_HIT.y * 0.9, 0))
	_check("just above it still counts", tablet.bar_fraction(near) > 0.99)
	var off := tablet.now_playing.to_global(Vector3(0, np_rect.size.y * 0.4, 0))
	_check("the title row is not the bar", tablet.bar_fraction(off) < 0.0)
	tablet.title_label.text = ""
	tablet.set("_title_full", "A very long title " .repeat(8))
	tablet.set("_title_fit", -1.0)
	tablet.call("_fit_title")
	_check("a long title is cut with an ellipsis to fit beside the time", tablet.title_label.text.ends_with("…")
			and tablet.call("_text_width", tablet.title_label, tablet.title_label.text) < np_rect.size.x * 0.8)

	# Input: the laser's ray, a touch, and skipping.
	var eye := head.origin
	var bar_mid := tablet.now_playing.to_global(Vector3(bar.position.x + bar.size.x * 0.75, bar.get_center().y, 0))
	var hit: Dictionary = tablet.ray_hit(eye, (bar_mid - eye).normalized())
	_check("a ray at the bar: the now playing pane, 0.75 along (%s)" % hit.get("fraction"), hit.get("pane") == "now_playing"
			and absf(float(hit["fraction"]) - 0.75) < 0.01 and absf(float(hit["distance"]) - eye.distance_to(bar_mid)) < 0.001)
	var main_mid := tablet.main_pane.global_position
	hit = tablet.ray_hit(eye, (main_mid - eye).normalized())
	_check("a ray at the main pane: that pane, off the bar", hit.get("pane") == "main" and float(hit["fraction"]) < 0.0)
	_check("a ray past the tablet: nothing", tablet.ray_hit(eye, Vector3.FORWARD).is_empty())

	# The menu on the tablet: the old panel on the main pane in its tablet layout (the tabs and their parts as lists
	# down the left, the tab beside them); its lists are dragged.
	var keep := tablet.global_transform
	layer.show_panel()
	await _frames(2)
	var panel: Node3D = layer.panel
	var pui: Node = layer.ui
	var pr := tablet.panel_rect()
	_check("on: the panel is the tablet's menu, its size and resolution, no halo (%s m, %s px)"
			% [panel.size_m, panel.resolution], panel.size_m.is_equal_approx(pr.size)
			and panel.resolution == tablet.panel_pixels() and not panel.halo_shown and pui.tablet_layout
			and panel.viewport.size == Vector2i((Vector2(panel.resolution) * tablet.panel_render_scale()).round())
			and panel.viewport.size_2d_override == panel.resolution
			and pr.size.x > mp.size.x - 0.02 and pr.size.y > mp.size.y - 0.02)
	var body_size: int = PaneStyle.theme().get_font_size(&"font_size", &"Label")
	_check("the text times the tablet's text_scale (%d px, the front panel's %d)"
			% [pui.tabs[0].get_theme_font_size(&"font_size", &"Label"), body_size],
			pui.text_scale == tablet.panel_text_scale()
			and pui.tabs[0].get_theme_font_size(&"font_size", &"Label") == roundi(body_size * tablet.panel_text_scale()))
	var row_b: Button = pui.tablet_tab_buttons[0]
	var borders := 0
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := row_b.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var f := sb as StyleBoxFlat
			borders += f.border_width_left + f.border_width_top + f.border_width_right + f.border_width_bottom
	_check("the list rows have no borders, the focus no ring (%d px)" % borders, borders == 0)
	_check("on the main pane, a little in front", panel.global_transform.is_equal_approx(tablet.panel_transform())
			and (panel.global_transform.origin - tablet.main_pane.global_position).length() < 0.005)
	_check("the header, seek bar, transport and tab bar give way", not pui._title.is_visible_in_tree()
			and not pui.seek.is_visible_in_tree() and not pui._transport.is_visible_in_tree()
			and not pui._tabs_box.is_visible_in_tree())
	_check("the tabs as a list down the left, Source first", pui.tablet_tab_buttons.size() == 7
			and pui.tablet_tab_buttons[0].text == "Source" and pui.tablet_tab_buttons[0].is_visible_in_tree()
			and pui.tablet_tab_buttons[0].get_global_rect().position.x < 60.0)
	pui.tablet_tab_buttons[0].pressed.emit()
	var place_buttons: Array = pui.files._places_box.get_children().filter(func(c: Node) -> bool:
		return c is Button and not c.is_queued_for_deletion())
	var names: Array = place_buttons.map(func(b: Button) -> String: return b.text)
	_check("Source's places as a list beside the rail, Library first, Test patterns last (%s)" % [names],
			names[0] == "Library" and names[-1] == "Test patterns" and names.has("Network")
			and pui.files._places_scroll.is_visible_in_tree())
	var patterns_button: Button = place_buttons[-1]
	patterns_button.pressed.emit()
	await _frames(2)
	_check("a place opens there and its row is marked", pui.files.current == "stub://" and patterns_button.button_pressed)
	_check("the view selector sits in the footer by the count", pui._views.is_visible_in_tree()
			and pui._views.get_parent() == pui._footer_count.get_parent())
	_check("the tab takes the rest of the width (%.0f of %d px)" % [pui._body.size.x, panel.resolution.x],
			pui._body.size.x > panel.resolution.x - pui.TABLET_TABS_WIDTH - 120)
	_check("the rail has icons", pui.tablet_tab_buttons.all(func(b: Button) -> bool: return b.icon != null)
			and pui.tablet_tab_buttons[0].icon.get_width() == pui.RAIL_ICON_PX)
	_check("a view selector: details, list, grid, details first", pui._view_buttons.size() == 3
			and pui.view == "details" and pui._view_buttons[0].button_pressed and pui._view_buttons[2].icon != null)
	pui._view_buttons[2].pressed.emit()
	_check("picking the grid: remembered", pui.view == "grid" and main.settings.get_value("browser", "view", "") == "grid"
			and pui._view_buttons[2].button_pressed and not pui._view_buttons[0].button_pressed)
	await _frames(2)
	var tiles: Array = pui.files._rows.filter(func(r: Dictionary) -> bool:
		return r["button"] != null and r["button"].get_parent() is HFlowContainer)
	_check("the grid view: the test patterns as tiles (%d of %d)" % [tiles.size(), pui.files._rows.size()],
			tiles.size() > 2 and tiles.size() == pui.files._rows.size() and pui.files.view == "grid")
	pui._view_buttons[1].pressed.emit()
	await _frames(2)
	var list_row: Button = pui.files._rows[0]["button"]
	_check("the list view: shorter rows, no tiles", pui.files.view == "list" and list_row.get_parent() == pui.files._list
			and list_row.custom_minimum_size.y < 40.0)
	pui._view_buttons[0].pressed.emit()
	await _frames(2)
	_check("details again: full rows", pui.files.view == "details"
			and (pui.files._rows[0]["button"] as Button).custom_minimum_size.y >= 40.0)
	pui.tablet_tab_buttons[1].pressed.emit()
	await _frames(2)
	var cards: Array = pui.cards(1)
	var pic_box: VBoxContainer = pui.tabs[1].box
	var holder: Node = pic_box.get_node("Cards")
	var pairs: Array = holder.get_children().filter(func(r: Node) -> bool: return r is HBoxContainer)
	var both := pairs.any(func(r: Node) -> bool:
		return r.get_child_count() == 2 and r.get_child(0).get_child_count() > 0 and r.get_child(1).get_child_count() > 0)
	var shape: Array = holder.get_children().map(func(r: Node) -> String:
		return "%s:%s" % [r.get_class(), r.get_children().map(func(c: Node) -> int: return c.get_child_count())])
	_check("Picture's sections as cards in two columns (%d cards, %d runs: %s)" % [cards.size(), pairs.size(), shape],
			cards.size() >= 6 and both and cards[0] is PanelContainer
			and cards[0].get_child(0).get_meta("section") == "Mode" and not pui._views.is_visible_in_tree())
	pui.tablet_tab_buttons[5].pressed.emit()
	await _frames(2)
	var object_cards: Array = pui.cards(5)
	_check("the Objects tab's one card (its heading inside the section node) is on show (%d)" % object_cards.size(),
			object_cards.size() == 1 and (object_cards[0] as Control).get_parent() != null
			and (object_cards[0] as Control).is_visible_in_tree())
	pui.tablet_tab_buttons[1].pressed.emit()
	await _frames(2)
	_check("a card whose section has nothing to show is left out (3D, for a flat film)", cards.any(
			func(c: Control) -> bool: return c.get_child(0).get_meta("section") == "3D" and c.get_parent() == null))
	_check("no card is wider than the tab (%.0f)" % pui.tabs[1].size.x, cards.all(func(c: Control) -> bool:
			return c.get_parent() == null or c.get_combined_minimum_size().x <= pui.tabs[1].size.x))
	tablet.set_enabled(false, false)
	_check("off: the front panel again, the sections back in their box", not pui.tablet_layout and panel.halo_shown
			and panel.viewport.size_2d_override == Vector2i.ZERO and panel.viewport.size == panel.resolution
			and pui._tabs_box.visible and pui.files._places_scroll.visible
			and not pic_box.has_node("Cards") and pic_box.get_child(0).get_meta("section") == "Mode")
	tablet.set_enabled(true, false)
	await _frames(1)
	_check("on again: the tablet layout", pui.tablet_layout and pui._tablet_row.visible)

	# Dragging a list: a press moved up or down scrolls it instead of clicking; a press that hardly moves clicks.
	pui.tablet_tab_buttons[0].pressed.emit()
	await _frames(1)
	var sc: ScrollContainer = pui.files.list_scroll()
	var lst: Control = sc.get_child(0)
	lst.custom_minimum_size.y = 3000
	await _frames(2)
	var at: Vector2 = sc.get_global_rect().get_center()
	var clicks := [0]
	for b: Node in lst.get_children():
		if b is Button:
			(b as Button).pressed.connect(func() -> void: clicks[0] += 1)
	var slop: float = panel.DRAG_SLOP / panel.size_m.x * panel.resolution.x
	panel.pointer_button(at, true)
	_check("a press on it finds the list", panel.scroll_under(panel.hovered_control()) == sc)
	panel.pointer_move(at + Vector2(0, -slop * 0.5))
	_check("within %.0f px: not a drag yet" % slop, not panel.dragging and sc.scroll_vertical == 0)
	panel.pointer_move(at + Vector2(0, -40))
	panel.pointer_move(at + Vector2(0, -80))
	_check("moved up 80 px: the list moves with it (%d)" % sc.scroll_vertical, panel.dragging
			and sc.scroll_vertical == 80)
	panel.pointer_button(at + Vector2(0, -80), false)
	_check("let go: no click", clicks[0] == 0 and not panel.dragging and not panel.is_pressed())
	await _frames(8)
	_check("it carries on a little (%d)" % sc.scroll_vertical, sc.scroll_vertical > 80)
	await _frames(60)
	sc.scroll_vertical = 0
	await _frames(1)
	# In the middle of a row, so the small move stays on it.
	var first_row: Control = null
	for b: Node in lst.get_children():
		if b is Button:
			first_row = b
			break
	var tap: Vector2 = first_row.get_global_rect().get_center()
	panel.pointer_button(tap, true)
	panel.pointer_move(tap + Vector2(0, 3))
	panel.pointer_button(tap + Vector2(0, 3), false)
	_check("a press that hardly moves is a click (%d clicks, scroll %d)" % [clicks[0], sc.scroll_vertical],
			clicks[0] == 1 and sc.scroll_vertical == 0)
	lst.custom_minimum_size.y = 0
	layer.hide_panel()
	tablet.show_at(head)
	tablet.global_transform = keep
	await _frames(1)
	var face: Vector3 = tablet.global_transform.basis.z
	var probe: Dictionary = tablet.poke_probe(bar_mid + face * 0.003)
	_check("a tip 3 mm over the bar: its depth and place", absf(float(probe["depth"]) - 0.003) < 0.0005
			and absf(float(probe["fraction"]) - 0.75) < 0.01)
	if main.player.can_seek() and dur > 0.0:
		_check("skipping to 0.5", tablet.seek_to(0.5))
		await _frames(3)
		_check("the film is half way (%.1f of %.1f)" % [main.player.get_position(), dur],
				absf(main.player.get_position() - dur * 0.5) < maxf(2.0, dur * 0.02))
		# Dragging: the bar and time follow at once, the film every SCRUB_SEEK, exactly where it is let go.
		var tol := maxf(2.0, dur * 0.02)
		var laser_at: Variant = tablet.plane_point(eye, (bar_mid - eye).normalized())
		_check("a ray meets the plane at the bar", laser_at != null and (laser_at as Vector3).distance_to(bar_mid) < 0.001
				and absf(tablet.along_bar(laser_at) - 0.75) < 0.01)
		var beside := tablet.now_playing.to_global(Vector3(bar.position.x + bar.size.x * 0.4, bar.position.y + 0.05, 0))
		_check("along the bar counts beside it too (dragging)", absf(tablet.along_bar(beside) - 0.4) < 0.01)
		_check("dragging starts", tablet.begin_scrub(0.2) and tablet.scrubbing)
		tablet.scrub(0.6)
		_check("the time follows the drag at once (%s)" % tablet.time_label.text,
				tablet.time_label.text.begins_with(W.clock(dur * 0.6)))
		await create_timer(Tablet.SCRUB_SEEK + 0.15).timeout
		_check("the film follows within SCRUB_SEEK (%.1f)" % main.player.get_position(),
				absf(main.player.get_position() - dur * 0.6) < tol)
		tablet.scrub(0.8)
		tablet.end_scrub()
		await _frames(3)
		_check("let go: exactly there (%.1f)" % main.player.get_position(), not tablet.scrubbing
				and absf(main.player.get_position() - dur * 0.8) < tol)
		tablet.begin_scrub(0.1)
		tablet.hide_tablet()
		_check("hiding ends a drag", not tablet.scrubbing)
		tablet.show_at(head)
		await _frames(1)

	# Fades.
	_check("showing fades in", tablet.visible)
	await create_timer(float(st["fade"]["in"]) + 0.15).timeout
	_check("faded in", is_equal_approx(float(top_mat.get_shader_parameter("opacity")), 1.0)
			and absf(tablet.title_label.modulate.a - (pal["ink"] as Color).a) < 0.01)
	tablet.hide_tablet()
	_check("hiding: not shown at once, still visible while it fades", not tablet.is_shown() and tablet.visible)
	await create_timer(float(st["fade"]["out"]) + 0.15).timeout
	_check("faded out: hidden", not tablet.visible and float(top_mat.get_shader_parameter("opacity")) < 0.01)
	print("test_tablet: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
