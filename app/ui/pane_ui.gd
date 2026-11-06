extends PanelContainer

## The menu on the tablet's main pane (ui/tablet.gd; the user, 2026-11-06: the front panel, the first UI, is gone),
## in the pane's SubViewport (ui/pane.gd).
##
## Top to bottom: a band over the tablet's now playing pane (the panel reaches up into it, ui/tablet.gd menu_band();
## the user, 2026-11-06): the transport on the left as icons (previous, -10 s, play / pause, +10 s, next; hold 4x / 8x
## for trick play; the skips and the trick buttons hide when the source can't seek) and on the right the picture's
## toggles (Steady detail: the footprint filter; Smooth banding: the deband). A see-through spacer over the gap
## between the panes. Then a row: down the left a rail
## of the tabs (Source, Picture, Sound, Subtitles, Room, Objects, Mixed reality, System), an icon (ui/icons.gd) and
## the name each; beside it Source's places (the files tab's own column) or any other tab's sections (the user,
## 2026-11-06: every tab its own list), the section picked as a card the full width (W.card_layout(),
## W.refresh_cards()); a section with nothing to show (3D for a flat film) leaves the column. Then a footer line (the
## mode and how it was chosen, or a short toast with an action such as Undo; the item count and Source's view
## selector on the right). The title, the time and the time bar are on the tablet's now playing pane, and so is the
## header (the chapter; the clock, time left with the end time, the battery, low controllers and "Listening": made
## here, chapter_text() and status_line_text(), and shown there; the user, 2026-11-06: the menu must fit its pane).
##
## Everything looks the way the theme says (ui/pane_style.gd, the tablet's theme); this file sets no colour and no
## font. No backdrop of its own: the tablet's pane shows through. The tabs talk to the app directly; the transport
## emits signals that ui_layer.gd turns into app calls. Lists are dragged to scroll (ui/pane.gd).
##
## Languages (docs/i18n.md): the rail, the transport and the section buttons are given the English and translate it
## themselves. The header, the footer and the toasts show text as it is given (W.content()): the callers of
## show_toast(), show_choice() and set_status() translate it (tr()), and names in it stay as they are. When the
## language changes, each tab's sync() runs and the header and the footer are built again.

const PaneStyle := preload("res://ui/pane_style.gd")
const W := preload("res://ui/pane_widgets.gd")
const FilesTab := preload("res://ui/files_tab.gd")
const PictureTab := preload("res://ui/picture_tab.gd")
const SoundTab := preload("res://ui/sound_tab.gd")
const SubtitlesTab := preload("res://ui/subtitles_tab.gd")
const RoomTab := preload("res://ui/room_tab.gd")
const ObjectsTab := preload("res://ui/objects_tab.gd")
const MixedRealityTab := preload("res://ui/mixed_reality_tab.gd")
const SystemTab := preload("res://ui/system_tab.gd")
const EndTime := preload("res://scripts/play/end_time.gd")

signal play_pause_pressed
signal previous_requested
signal next_requested
signal skip_requested(delta_seconds: float)

enum Tab { FILES, PICTURE, SOUND, SUBTITLES, ROOM, OBJECTS, MIXED_REALITY, SYSTEM }
const TAB_NAMES: Array[String] = ["Files", "Picture", "Sound", "Subtitles", "Room", "Objects", "Mixed reality", "System"]
## The rail's names and icons for the tabs (Files is called Source there), its width and its icons' size (pixels), and
## Source's views.
## The transport buttons' names, in order (tooltips and meta "label"; "Play" turns "Pause" while playing).
const TRANSPORT_NAMES: Array[String] = ["Previous", "−10 s", "Play", "+10 s", "Next"] # i18n
const TABLET_TAB_NAMES: Array[String] = ["Source", "Picture", "Sound", "Subtitles", "Room", "Objects", "Mixed reality", # i18n
		"System"] # i18n
const TABLET_TAB_ICONS: Array[String] = ["source", "picture", "sound", "subtitles", "room", "objects", "mixed-reality",
		"system"]
const TABLET_TABS_WIDTH := 190
const RAIL_ICON_PX := 30
## The rail's rows, pixels.
const RAIL_ROW := 44
const VIEWS: Array[String] = ["details", "list", "grid"]
## The view buttons' tooltips (keys: the buttons translate them).
const VIEW_NAMES := {"details": "Details", "list": "List", "grid": "Grid"} # i18n
const Icons := preload("res://ui/icons.gd")
const I18n := preload("res://scripts/i18n.gd")

var app: Node
var files: FilesTab
var picture: PictureTab
var sound: SoundTab
var subtitles: SubtitlesTab
var room: RoomTab
var objects: ObjectsTab
var mixed_reality: MixedRealityTab
var system: SystemTab
var tabs: Array[Control] = []
var current_tab := 0

var _content: VBoxContainer
var _open: VBoxContainer
## The header: "Chapter 3/12 Title" (or nothing) on the left; on the right the clock, time left and end, battery (and
## low controllers, "Listening").
var _now: Label
var _status_line: Label
## The band's row (the transport and the toggles), the spacer under it, the transport's icon buttons, the toggles.
var _band: HBoxContainer
var _band_gap: Control
var _transport_icons: Array[Button] = []
var _steady_toggle: Button
var _banding_toggle: Button
var _transport: HBoxContainer
var _play_button: Button
## Trick play (#46): hold 4x or 8x to scan with pictures; let go and it plays on. The skip buttons and the trick
## buttons hide when the source can't seek (live streams, #86).
var _trick_buttons: Array[Button] = []
var _skip_buttons: Array[Button] = []
var _form_mode := false
var _seekable := true
var _body: PanelContainer
var _footer_text: Label
var _footer_count: Label
var _toast: HBoxContainer
var _toast_label: Label
var _toast_button: Button
var _toast_action: Callable
## A second button for a choice (show_choice(): Keep / Undo for an assistant's room change).
var _toast_button2: Button
var _toast_action2: Callable
var _toast_left := 0.0
var _status := ""
## An extra header item set by the layer (low controller batteries), or "".
var header_extra := ""
## Push-to-talk is recording: "Listening" in the header and the footer.
var listening := false
## Source's view (VIEWS).
var view := "details"
## Every font size times this (set_text_scale(): the tablet's, from its style), and the tablet's own theme
## (set_tablet_theme(); null until the layer sets it: the default theme).
var text_scale := 1.0
var _tablet_theme: Theme
var _tablet_row: HBoxContainer
## The rail's scroll and the rule beside it (hidden while a keyboard form is open).
var _rail_scroll: ScrollContainer
var _rail_rule: VSeparator
var tablet_tab_buttons: Array[Button] = []
## The tablet's sections column (any tab but Source): its scroll, buttons and rule, the section picked on each tab
## (tab -> section; the first shown when none, or when the one picked has nothing to show), and what it lists.
var _sections_scroll: ScrollContainer
var _sections_box: VBoxContainer
var _sections_rule: VSeparator
var _section_of := {}
var _sections_key := ""
## The browser's view selector (VIEWS), in the footer on the tablet while Source shows.
var _views: HBoxContainer
var _view_buttons: Array[Button] = []


func _ready() -> void:
	theme = PaneStyle.theme()
	theme_type_variation = &"PaneRoot"
	PaneStyle.holder().changed.connect(apply_style)
	I18n.holder().changed.connect(_on_language_changed)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 0)
	add_child(_content)
	_build_open()
	apply_style()


## The theme, and the focus boxes with their 1 px accent outline (the stick focus works whenever the panel is open).
func apply_style() -> void:
	var base: Theme = _tablet_theme if _tablet_theme != null else PaneStyle.theme()
	theme = base if is_equal_approx(text_scale, 1.0) else PaneStyle.scaled_theme(text_scale, base)
	if _content != null:
		# The stick focus: the tablet's theme is flat, its own focus look stays (a ring with the default theme).
		_content.theme = null if _tablet_theme != null else PaneStyle.docked_focus_theme()
	if _tablet_row != null:
		_refresh_rail()
	_refresh_transport()
	if files != null:
		files.set_places_width(PaneStyle.constant(&"places_width") * text_scale)
	if _sections_scroll != null:
		_sections_scroll.custom_minimum_size.x = PaneStyle.constant(&"places_width") * text_scale
	# No backdrop: the tablet's pane shows through (the theme's margins kept, but a small one on top: the band's row
	# sits on the now playing pane's band).
	remove_theme_stylebox_override("panel")
	var clear := _clear(get_theme_stylebox("panel"))
	clear.content_margin_top = 2.0
	add_theme_stylebox_override("panel", clear)
	if _body != null:
		_body.remove_theme_stylebox_override("panel")
		_body.add_theme_stylebox_override("panel", _clear(_body.get_theme_stylebox("panel")))
	queue_redraw()


func _build_open() -> void:
	var gap := PaneStyle.constant(&"gap")
	_open = VBoxContainer.new()
	_open.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Half the gap between the menu's rows: the transport, the rail and the footer fill the tablet's main pane.
	_open.add_theme_constant_override("separation", gap / 2)
	_content.add_child(_open)

	_now = W.ellipsis(W.label("", &"MutedLabel"))
	W.content(_now)
	_now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_line = W.label("", &"MutedLabel")
	W.content(_status_line)
	_status_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Made here, shown on the tablet's now playing pane (ui_layer.gd): kept out of the menu's height.
	var header := W.hbox([_now, _status_line])
	header.visible = false
	_open.add_child(header)

	_band = W.hbox()
	_transport = W.hbox()
	var bh := PaneStyle.constant(&"button_height")
	# Icons; each button's name in its tooltip and meta "label" (what it does, for the stick focus and tests). The
	# tooltip translates itself; the meta stays English.
	var names := TRANSPORT_NAMES
	for spec: Array in [["previous", names[0], func() -> void: previous_requested.emit()],
			["back-10", names[1], func() -> void: skip_requested.emit(-10.0)], ["play", names[2], Callable()],
			["forward-10", names[3], func() -> void: skip_requested.emit(10.0)],
			["next", names[4], func() -> void: next_requested.emit()]]:
		var b: Button
		if spec[0] == "play":
			_play_button = W.button("", func() -> void: play_pause_pressed.emit(), &"PlayButton")
			b = _play_button
		else:
			b = W.button("", spec[2], &"TransportButton")
			if str(spec[1]).ends_with(" s"):
				_skip_buttons.append(b)
		b.custom_minimum_size = Vector2(bh * 1.3, bh)
		b.set_meta("icon", spec[0])
		b.set_meta("label", spec[1])
		b.tooltip_text = spec[1]
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_transport.add_child(b)
		_transport_icons.append(b)
	for speed: float in [4.0, 8.0]:
		var b := W.button("%dx" % roundi(speed), Callable(), &"TransportButton")
		W.content(b)
		b.custom_minimum_size = Vector2(bh * 1.4, bh)
		b.button_down.connect(func() -> void: _trick(speed))
		b.button_up.connect(func() -> void: _trick(0.0))
		_transport.add_child(b)
		_trick_buttons.append(b)
	_band.add_child(_transport)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(fill)
	_steady_toggle = W.toggle("Steady detail", func(on: bool) -> void:
		if app != null:
			app.features.picture.set_steady(on))
	_steady_toggle.tooltip_text = "Fine detail filtered where the picture is shrunk, so it doesn't shimmer."
	_banding_toggle = W.toggle("Smooth banding", func(on: bool) -> void:
		if app != null:
			app.features.picture.set_banding(on))
	_banding_toggle.tooltip_text = "Hides the steps in dark gradients (8-bit video)."
	_band.add_child(_steady_toggle)
	_band.add_child(_banding_toggle)
	_open.add_child(_band)
	# Over the gap between the tablet's panes: nothing, so the gap shows.
	_band_gap = Control.new()
	_band_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open.add_child(_band_gap)

	_body = PanelContainer.new()
	_body.theme_type_variation = &"BodyPanel"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open.add_child(_body)

	_open.add_child(HSeparator.new())
	var footer := W.hbox()
	_footer_text = W.ellipsis(W.label("", &"MutedLabel"))
	W.content(_footer_text)
	footer.add_child(_footer_text)
	_toast_label = W.ellipsis(W.label(""))
	W.content(_toast_label)
	_toast_button = W.button("", func() -> void:
		var action := _toast_action
		hide_toast()
		if action.is_valid():
			action.call())
	_toast_button.custom_minimum_size.y = 0
	W.content(_toast_button)
	_toast_button2 = W.button("", func() -> void:
		var action := _toast_action2
		hide_toast()
		if action.is_valid():
			action.call())
	_toast_button2.custom_minimum_size.y = 0
	W.content(_toast_button2)
	_toast_button2.visible = false
	_toast = W.hbox([_toast_label, _toast_button, _toast_button2])
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast.visible = false
	var toast_panel := PanelContainer.new()
	toast_panel.theme_type_variation = &"ToastPanel"
	toast_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast_panel.add_child(_toast)
	toast_panel.visible = false
	_toast.visibility_changed.connect(func() -> void: toast_panel.visible = _toast.visible)
	footer.add_child(toast_panel)
	_footer_count = W.label("", &"MutedLabel")
	W.content(_footer_count)
	footer.add_child(_footer_count)
	_open.add_child(footer)
	_build_tablet_row()


## Makes the tabs (they need the app). Called once by ui_layer.gd.
func bind(p_app: Node) -> void:
	app = p_app
	files = FilesTab.new()
	files.name = "Files"
	files.app = app
	picture = PictureTab.new()
	sound = SoundTab.new()
	subtitles = SubtitlesTab.new()
	room = RoomTab.new()
	objects = ObjectsTab.new()
	mixed_reality = MixedRealityTab.new()
	system = SystemTab.new()
	tabs = [files, picture, sound, subtitles, room, objects, mixed_reality, system]
	for t in tabs:
		t.visible = false
		_body.add_child(t)
	for t in [picture, sound, subtitles, room, objects, mixed_reality, system]:
		t.bind(app)
	files.form_shown.connect(set_form_mode)
	files.listing_changed.connect(_update_footer)
	system.open_place.connect(func(p: String) -> void:
		show_tab(Tab.FILES)
		files.open_folder(p))
	view = str(app.settings.get_value("browser", "view", "details"))
	if not view in VIEWS:
		view = "details"
	files.set_view(view)
	_refresh_rail()
	app.features.picture.changed.connect(func(_v: Dictionary) -> void: sync_toggles())
	sync_toggles()
	show_tab(Tab.FILES)


## A form with the keyboard is open: the rail makes room for it (the form has the main pane's width; Cancel or Save
## bring it back). The transport stays, on the now playing pane.
func set_form_mode(on: bool) -> void:
	_form_mode = on
	if _rail_scroll != null:
		_rail_scroll.visible = not on
		_rail_rule.visible = not on


## Trick play from a held 4x / 8x button: start on press, plain playback on release.
func _trick(speed: float) -> void:
	var trick: Node = app.features.get("trick") if app != null and app.get("features") != null else null
	if trick == null:
		return
	if speed > 0.0:
		trick.start(speed)
	else:
		trick.stop()


func show_tab(index: int) -> void:
	current_tab = clampi(index, 0, tabs.size() - 1)
	for i in tabs.size():
		tabs[i].visible = i == current_tab
	for i in tablet_tab_buttons.size():
		tablet_tab_buttons[i].set_pressed_no_signal(i == current_tab)
	if _views != null:
		_views.visible = current_tab == Tab.FILES
	if _sections_scroll != null:
		_sections_scroll.visible = current_tab != Tab.FILES
		_sections_rule.visible = _sections_scroll.visible
	if _tablet_row != null:
		_refresh_rail()
	if current_tab != Tab.FILES and _body != null:
		W.card_layout(tabs[current_tab].get("box"), true)
		_pack_cards()
	_update_footer()


## The control that takes the stick focus first when the panel opens: none (it is pointed at or touched; a focused
## row would look selected beside the selected one), until the stick moves.
func default_focus() -> Control:
	return null


## Where the stick starts when nothing has the focus: the tab's row on the rail.
func stick_focus() -> Control:
	return tablet_tab_buttons[current_tab]


# --- Layout ---------------------------------------------------------------------------------------------------------

func set_text_scale(s: float) -> void:
	if is_equal_approx(s, text_scale):
		return
	text_scale = s
	apply_style()


## The tablet's theme (PaneStyle.tablet_theme(), in the tablet's colours).
func set_tablet_theme(t: Theme) -> void:
	if t == _tablet_theme:
		return
	_tablet_theme = t
	apply_style()


func _build_tablet_row() -> void:
	_tablet_row = W.hbox()
	_tablet_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open.add_child(_tablet_row)
	_open.move_child(_tablet_row, _body.get_index())
	var group := ButtonGroup.new()
	var rail := VBoxContainer.new()
	rail.name = "Rail"
	rail.add_theme_constant_override("separation", 0)
	rail.custom_minimum_size.x = TABLET_TABS_WIDTH
	for i in TABLET_TAB_NAMES.size():
		var b := W.button(TABLET_TAB_NAMES[i], func() -> void: show_tab(i), &"RailButton")
		# Eight rows, the transport and the footer in the main pane's height (ui/tablet.gd panel_pixels()).
		b.custom_minimum_size.y = RAIL_ROW
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.set_meta("icon", TABLET_TAB_ICONS[i])
		rail.add_child(b)
		tablet_tab_buttons.append(b)
	# In its own scroll: with larger text (accessibility) the rail scrolls rather than push the footer off the pane.
	_rail_scroll = ScrollContainer.new()
	_rail_scroll.name = "RailScroll"
	_rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rail_scroll.custom_minimum_size.x = TABLET_TABS_WIDTH
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail_scroll.add_child(rail)
	_tablet_row.add_child(_rail_scroll)
	_rail_rule = VSeparator.new()
	_tablet_row.add_child(_rail_rule)
	# The sections column: as the files tab's places column, the same width and buttons.
	_sections_scroll = ScrollContainer.new()
	_sections_scroll.name = "Sections"
	_sections_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sections_scroll.custom_minimum_size.x = PaneStyle.constant(&"places_width") * text_scale
	_sections_box = VBoxContainer.new()
	_sections_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections_box.add_theme_constant_override("separation", 0)
	_sections_scroll.add_child(_sections_box)
	_tablet_row.add_child(_sections_scroll)
	_sections_rule = VSeparator.new()
	_tablet_row.add_child(_sections_rule)
	_sections_scroll.visible = false
	_sections_rule.visible = false
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	_tablet_row.add_child(content)
	_body.get_parent().remove_child(_body)
	content.add_child(_body)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The view selector, at the right of the files tab's title row.
	_views = HBoxContainer.new()
	_views.add_theme_constant_override("separation", 2)
	_views.visible = false
	var view_group := ButtonGroup.new()
	for v in VIEWS:
		var b := W.button("", func() -> void: set_view(v), &"ViewButton")
		b.toggle_mode = true
		b.button_group = view_group
		b.set_meta("icon", "view-" + v)
		b.tooltip_text = VIEW_NAMES[v]
		_views.add_child(b)
		_view_buttons.append(b)
	# In the footer, at the right by the count: the title row has no room for it at the tablet's text size.
	_footer_count.get_parent().add_child(_views)
	_footer_count.get_parent().move_child(_views, _footer_count.get_index())


## The menu's top rows on the tablet's band and gap (pixels, Tablet.menu_band()): the band's row just fills the band
## under the panel's top margin; the spacer takes the rest down to the main pane's inside.
func set_band(band_px: int, gap_px: int) -> void:
	if _band == null:
		return
	var top := get_theme_stylebox("panel").get_margin(SIDE_TOP)
	var sep := _open.get_theme_constant("separation")
	_band.custom_minimum_size.y = maxf(band_px - top, 0.0)
	_band_gap.custom_minimum_size.y = maxf(gap_px - 2 * sep, 0.0)


## The picture toggles as the settings have them (the picture controls' changed signal).
func sync_toggles() -> void:
	if app == null or _steady_toggle == null:
		return
	var pc: Node = app.features.picture
	W.set_on(_steady_toggle, bool(pc.steady))
	W.set_on(_banding_toggle, float(pc.values.get("deband", 0.0)) > 0.0)


## The transport's icons in the theme's text colour.
func _refresh_transport() -> void:
	var px := roundi(PaneStyle.constant(&"button_height") * 0.62)
	for b in _transport_icons:
		b.icon = Icons.texture(str(b.get_meta("icon")), px, PaneStyle.color(&"text"))


## The rail's and the view selector's icons in the theme's colours (the chosen one bright or in the accent).
func _refresh_rail() -> void:
	for b in tablet_tab_buttons:
		var colour := PaneStyle.color(&"accent" if b.button_pressed else &"muted")
		b.icon = Icons.texture(str(b.get_meta("icon")), RAIL_ICON_PX, colour)
	for b in _view_buttons:
		var on := str(b.get_meta("icon")) == "view-" + view
		b.set_pressed_no_signal(on)
		b.icon = Icons.texture(str(b.get_meta("icon")), RAIL_ICON_PX - 6, PaneStyle.color(&"text" if on else &"muted"))


## The browser's view (VIEWS), remembered in [browser] view. The views themselves are to come: details is what
## the files tab draws now.
func set_view(v: String) -> void:
	if not v in VIEWS:
		return
	view = v
	if app != null:
		app.settings.set_value("browser", "view", v if v != "details" else null)
	if files != null:
		files.set_view(v)
	_refresh_rail()


## Packs the tab's card for the body's width (W.refresh_cards()): the section picked in the column alone. The tab
## fills the body, and the body is always laid out, where a tab just shown still has the size it last had.
func _pack_cards() -> void:
	var box: VBoxContainer = tabs[current_tab].get("box")
	var names := W.shown_sections(box)
	var picked := section_shown()
	_sync_sections(names, picked)
	W.refresh_cards(box, _body.size.x - 16.0, picked)


## The section on show in the current tab on the tablet: the one picked, while it has something to show, else the
## first that has.
func section_shown() -> String:
	var box: Variant = tabs[current_tab].get("box")
	if not (box is VBoxContainer):
		return ""
	var names := W.shown_sections(box)
	var picked := str(_section_of.get(current_tab, ""))
	return picked if picked in names else (names[0] if not names.is_empty() else "")


## Picks a section of the current tab (the column's buttons; tests).
func show_section(section: String) -> void:
	_section_of[current_tab] = section
	_pack_cards()
	# The tab's scroll back to the top: a new card, not the old one's place in it.
	var t: Control = tabs[current_tab]
	if t is ScrollContainer:
		(t as ScrollContainer).scroll_vertical = 0


## The column's buttons, built again only when the tab or its sections change.
func _sync_sections(names: Array[String], picked: String) -> void:
	if _sections_box == null:
		return
	var key := "%d:%s" % [current_tab, "|".join(names)]
	if key != _sections_key:
		_sections_key = key
		for c in _sections_box.get_children():
			_sections_box.remove_child(c)
			c.queue_free()
		for n in names:
			var s := n
			var b := W.button(n, func() -> void: show_section(s), &"PlaceButton")
			b.custom_minimum_size.y = PaneStyle.constant(&"row_height")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.toggle_mode = true
			b.set_meta("section", n)
			_sections_box.add_child(b)
	for b in _sections_box.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(str(b.get_meta("section")) == picked)


## The sections column's buttons (tests).
func section_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _sections_box != null:
		for b in _sections_box.get_children():
			if b is Button and not b.is_queued_for_deletion():
				out.append(b)
	return out


## A tab's cards on the tablet (PanelContainers, W.card_layout()); none for the files tab.
func cards(tab: int) -> Array:
	var box: Variant = tabs[tab].get("box")
	return W.cards(box) if box is VBoxContainer else []


## A copy of a backdrop with nothing drawn (its margins kept).
static func _clear(sb: StyleBox) -> StyleBox:
	if not (sb is StyleBoxFlat):
		return StyleBoxEmpty.new()
	var c := sb.duplicate() as StyleBoxFlat
	c.bg_color.a = 0.0
	c.border_color.a = 0.0
	c.shadow_size = 0
	return c


## The header's right side (shown on the tablet).
func status_line_text() -> String:
	return _status_line.text


## The header's left side, "Chapter 3/12 Title" or "" (shown on the tablet).
func chapter_text() -> String:
	return _now.text


## The header's right side: "21:42  ·  1:12 left, ends 22:54  ·  battery 74 %", then low controllers and
## "Listening". Empty parts are left out. In the menus' language (the times and `extra` come translated).
static func status_text(clock: String, remaining_text: String, end_text: String, battery_percent: int,
		charging: bool, extra := "", p_listening := false) -> String:
	var parts: Array[String] = [clock]
	if remaining_text != "":
		# "1:12 left, ends 22:54"
		parts.append(TranslationServer.translate("%s, %s") % [remaining_text, end_text] if end_text != ""
				else remaining_text)
	if battery_percent >= 0:
		parts.append((TranslationServer.translate("battery %d %%, charging") if charging
				else TranslationServer.translate("battery %d %%")) % battery_percent)
	if extra != "":
		parts.append(extra)
	if p_listening:
		parts.append(TranslationServer.translate("Listening"))
	return "  ·  ".join(parts.filter(func(s: String) -> bool: return s != ""))


## A lasting status line in the footer ("Connecting...", "Starting the browser..."), or "" for the mode line. The
## caller translates it (tr()); it shows as given.
func set_status(text: String) -> void:
	_status = text
	_update_footer()


## A short line in the footer with an optional action button ("Undo", "Start over"), for `seconds`. The caller
## translates both texts (tr("Undo")); they show as given, so a name in them stays as it is.
func show_toast(text: String, action_text := "", action := Callable(), seconds := 6.0) -> void:
	_toast_label.text = text
	_toast_button.text = action_text
	_toast_button.visible = action_text != ""
	_toast_action = action
	_toast_button2.visible = false
	_toast_action2 = Callable()
	_toast_left = seconds
	_toast.visible = true
	_footer_text.visible = false


## A line in the footer with two buttons (Keep / Undo), until one is pressed or `seconds` pass. Translated by the
## caller, as show_toast().
func show_choice(text: String, first_text: String, first: Callable, second_text: String, second: Callable,
		seconds := INF) -> void:
	show_toast(text, first_text, first, seconds)
	_toast_button2.text = second_text
	_toast_button2.visible = true
	_toast_action2 = second


## Push-to-talk (#14): "Listening" shows in the panel's header while recording. No floating toast any more: the
## conversation card's live line and its dancing dots show it (the user, in the headset, 2026-10-31).
func set_listening(on: bool) -> void:
	listening = on
	if _toast_label.text == tr("Listening"):
		hide_toast()


func hide_toast() -> void:
	_toast.visible = false
	_toast_action = Callable()
	_toast_action2 = Callable()
	_footer_text.visible = true


func toast_button() -> Button:
	return _toast_button if _toast.visible and _toast_button.visible else null


func _process(delta: float) -> void:
	if _toast.visible:
		_toast_left -= delta
		if _toast_left <= 0.0:
			hide_toast()


func _update_footer() -> void:
	if _footer_text == null:
		return
	if _status != "":
		_footer_text.text = _status
	elif picture != null:
		var crop: String = picture.crop_text()
		_footer_text.text = picture.mode_text() + (("  ·  " + crop) if crop != "" else "")
	_footer_count.text = files.count_text() if files != null and current_tab == Tab.FILES else ""


## The playback state, a few times a second while the pane shows (the time is on the tablet's now playing pane).
func set_playback(_position_s: float, _duration: float, playing: bool, can_seek: bool) -> void:
	var label := "Pause" if playing else "Play" # i18n
	if str(_play_button.get_meta("label", "")) != label:
		_play_button.set_meta("label", label)
		_play_button.set_meta("icon", "pause" if playing else "play")
		_play_button.tooltip_text = label
		_refresh_transport()
	# A live stream (or HTTP without ranges) can't seek: no skips or trick play (LIVE by the tablet's time).
	_seekable = can_seek
	for b in _skip_buttons:
		b.visible = can_seek
	var f: Node = app.features if app != null and app.get("features") != null else null
	var trick: Node = f.get("trick") if f != null else null
	var trick_ok := trick != null and bool(trick.available()) and can_seek
	for b in _trick_buttons:
		b.visible = trick_ok


## The language changed (scripts/i18n.gd): fixed words translate themselves; the texts the tabs build come again from
## their sync(), the header and the footer from tick().
func _on_language_changed(_code: String) -> void:
	if app == null:
		return
	for t in tabs:
		if t.has_method("sync"):
			t.sync()
	tick()


## Refreshes the header's status line and the per-second parts of the panel.
func tick() -> void:
	if app == null:
		return
	var f: Node = app.features
	var remaining: float = f.remaining()
	var forecast: Dictionary = f.battery.get_forecast() if f.get("battery") != null else {}
	var available := bool(forecast.get("available", false))
	_status_line.text = status_text(EndTime.clock_at(Time.get_unix_time_from_system()),
			EndTime.format_remaining(remaining, true), f.end_text(true) if remaining > 0.0 else "",
			int(forecast.get("percent", -1)) if available else -1, available and bool(forecast.get("charging", false)),
			header_extra, listening)
	# "Chapter 3/12 Title": the chapter's title as the file has it.
	var chapter: String = f.chapters.title_text() if int(f.chapters.current) >= 0 else ""
	_now.text = tr("Chapter %s") % chapter if chapter != "" else ""
	_update_footer()
	if current_tab != Tab.FILES:
		_pack_cards()
	if current_tab == Tab.ROOM:
		room.tick()
	elif current_tab == Tab.SOUND:
		sound.tick()
	elif current_tab == Tab.SUBTITLES:
		subtitles.tick()
	elif current_tab == Tab.SYSTEM:
		system.tick()
