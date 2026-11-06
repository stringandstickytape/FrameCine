extends PanelContainer

## The pane's contents (docs/ui-design.md, "Inside the pane"), 740 x 600 px in the pane's SubViewport (ui/pane.gd).
##
## Top to bottom: header ("Now playing" and, on the right, the clock, time left with the end time, and the battery;
## then the title and the time in tabular numerals), seek bar with chapter ticks, transport (previous, -10 s, play /
## pause ringed, +10 s, next), tabs (Files, Picture, Sound, Subtitles, Room, Objects, Mixed reality (MR on the front
## panel's bar), System), the tab's body, and a footer line (the mode and how it was
## chosen, or a short toast with an action such as Undo; the item count on the right). The panel has one view: the
## glance view of the hand-held pane is gone, its lines are in the header (docs/ui-design.md, "Revision 2").
##
## Everything looks the way the theme says (ui/pane_style.gd); this file sets no colour and no font. The tabs talk to
## the app directly; the transport and seek bar emit signals that ui_layer.gd turns into app calls.
##
## The tablet layout (set_tablet_layout(); ui/tablet.gd, the user 2026-11-04: the old menu moved onto the tablet and
## reshaped): the header, seek bar and transport go (the tablet's now playing pane shows the title, time and bar);
## down the left a rail of the tabs, an icon (ui/icons.gd) and the name each, Files called Source; the tab in the
## rest of the width. Source: the places as chips over the files tab (FilesTab.places_in_order(); the tab's own
## places column goes), with a view selector at the right (details, list, grid: `view`, [browser] view; the views
## themselves are to come). Any other tab: its sections as cards, two to a row (W.card_layout()). The footer under
## it all. No backdrop of its own: the tablet's pane shows through. Lists are dragged to scroll (ui/pane.gd).

const PaneStyle := preload("res://ui/pane_style.gd")
const W := preload("res://ui/pane_widgets.gd")
const SeekBar := preload("res://ui/seek_bar.gd")
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
signal seek_requested(seconds: float)
signal skip_requested(delta_seconds: float)

enum Tab { FILES, PICTURE, SOUND, SUBTITLES, ROOM, OBJECTS, MIXED_REALITY, SYSTEM }
const TAB_NAMES: Array[String] = ["Files", "Picture", "Sound", "Subtitles", "Room", "Objects", "Mixed reality", "System"]
## The front panel's tab bar shares one row: the long names shortened there.
const TAB_CAPTIONS := {"Mixed reality": "MR"}
## The tablet layout's names and icons for the tabs, the rail's width and its icons' size (pixels), and the views.
const TABLET_TAB_NAMES: Array[String] = ["Source", "Picture", "Sound", "Subtitles", "Room", "Objects", "Mixed reality",
		"System"]
const TABLET_TAB_ICONS: Array[String] = ["source", "picture", "sound", "subtitles", "room", "objects", "mixed-reality",
		"system"]
const TABLET_TABS_WIDTH := 190
const RAIL_ICON_PX := 30
const VIEWS: Array[String] = ["details", "list", "grid"]
const Icons := preload("res://ui/icons.gd")

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
var tab_buttons: Array[Button] = []
var current_tab := 0

var _content: VBoxContainer
var _open: VBoxContainer
var _title: Label
## "Now playing", or "Now playing  ·  chapter 3/12 Title".
var _now: Label
var _time: Label
## The header's right side: clock, time left and end, battery (and low controllers, "Listening").
var _status_line: Label
var seek: SeekBar
var _transport: HBoxContainer
var _play_button: Button
## Trick play (#46): hold 4x or 8x to scan with pictures; let go and it plays on. The skip buttons and the trick
## buttons hide when the source can't seek (live streams, #86).
var _trick_buttons: Array[Button] = []
## Seek-bar thumbnails (#40, features.thumbs, off by default): a picture under the bar at the hovered or scrubbed time.
var _thumb: VBoxContainer
var _thumb_image: TextureRect
var _thumb_label: Label
var _thumb_time := -1.0
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
## The tablet layout: on or not; its row (the rail and the body), the rail's buttons, Source's chips and view
## selector, and the view chosen.
var tablet_layout := false
var view := "details"
## Every font size times this (set_text_scale(): the tablet's, from its style; 1 on the front panel), and the
## tablet's own theme (set_tablet_theme(); null: the front panel's).
var text_scale := 1.0
var _tablet_theme: Theme
var _tabs_box: VBoxContainer
var _tablet_row: HBoxContainer
var tablet_tab_buttons: Array[Button] = []
## The browser's view selector (VIEWS), in the footer on the tablet while Source shows.
var _views: HBoxContainer
var _view_buttons: Array[Button] = []


func _ready() -> void:
	theme = PaneStyle.theme()
	theme_type_variation = &"PaneRoot"
	PaneStyle.holder().changed.connect(apply_style)
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
		# The stick focus: a ring on the front panel; the tablet's theme is flat, its own focus look stays.
		_content.theme = null if _tablet_theme != null else PaneStyle.docked_focus_theme()
	if _tablet_row != null:
		_refresh_rail()
	if files != null:
		files.set_places_width(PaneStyle.constant(&"places_width") * text_scale)
	queue_redraw()


func _build_open() -> void:
	var gap := PaneStyle.constant(&"gap")
	_open = VBoxContainer.new()
	_open.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open.add_theme_constant_override("separation", gap)
	_content.add_child(_open)

	_now = W.ellipsis(W.caps("Now playing"))
	_status_line = W.label("", &"MutedLabel")
	_status_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_open.add_child(W.hbox([_now, _status_line]))
	_title = W.ellipsis(W.label("Nothing playing", &"TitleLabel"))
	_time = W.label("", &"TimeLabel")
	_open.add_child(W.hbox([_title, _time]))

	seek = SeekBar.new()
	seek.seek_requested.connect(func(t: float) -> void: seek_requested.emit(t))
	seek.scrub_changed.connect(func(t: float) -> void:
		_time.text = _time_text(t, seek.duration)
		_thumb_at(t))
	seek.hover_changed.connect(_thumb_at)
	seek.seek_requested.connect(func(_t: float) -> void: _thumb_at(-1.0))
	_open.add_child(seek)
	_thumb = W.vbox()
	_thumb.top_level = true
	_thumb.visible = false
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb_image = TextureRect.new()
	_thumb_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb_image.custom_minimum_size = Vector2(192, 108)
	_thumb_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.add_child(_thumb_image)
	_thumb_label = W.label("", &"TimeLabel")
	_thumb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thumb.add_child(_thumb_label)
	add_child(_thumb)

	_transport = W.hbox()
	_transport.alignment = BoxContainer.ALIGNMENT_CENTER
	var bh := PaneStyle.constant(&"button_height")
	for spec: Array in [["Previous", func() -> void: previous_requested.emit()],
			["−10 s", func() -> void: skip_requested.emit(-10.0)], ["play", Callable()],
			["+10 s", func() -> void: skip_requested.emit(10.0)], ["Next", func() -> void: next_requested.emit()]]:
		if spec[0] == "play":
			var ps := PaneStyle.constant(&"play_size")
			_play_button = W.button("Play", func() -> void: play_pause_pressed.emit(), &"PlayButton")
			_play_button.custom_minimum_size = Vector2(ps + 24, ps)
			_transport.add_child(_play_button)
		else:
			var b := W.button(spec[0], spec[1], &"TransportButton")
			b.custom_minimum_size = Vector2(bh * 2, bh)
			_transport.add_child(b)
			if str(spec[0]).ends_with(" s"):
				_skip_buttons.append(b)
	for speed: float in [4.0, 8.0]:
		var b := W.button("%dx" % roundi(speed), Callable(), &"TransportButton")
		b.custom_minimum_size = Vector2(bh * 1.4, bh)
		b.button_down.connect(func() -> void: _trick(speed))
		b.button_up.connect(func() -> void: _trick(0.0))
		_transport.add_child(b)
		_trick_buttons.append(b)
	_open.add_child(_transport)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	for i in TAB_NAMES.size():
		# Buttons have no uppercase flag: the caption is the name in capitals (the theme letter-spaces it).
		var b := W.button(str(TAB_CAPTIONS.get(TAB_NAMES[i], TAB_NAMES[i])).to_upper(), func() -> void: show_tab(i),
				&"TabButton")
		b.custom_minimum_size = Vector2(0, PaneStyle.constant(&"tab_height"))
		b.set_meta("tab", TAB_NAMES[i])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(b)
		tab_buttons.append(b)
	_tabs_box = VBoxContainer.new()
	_tabs_box.add_theme_constant_override("separation", 0)
	_tabs_box.add_child(bar)
	_tabs_box.add_child(HSeparator.new())
	_open.add_child(_tabs_box)

	_body = PanelContainer.new()
	_body.theme_type_variation = &"BodyPanel"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open.add_child(_body)

	_open.add_child(HSeparator.new())
	var footer := W.hbox()
	_footer_text = W.ellipsis(W.label("", &"MutedLabel"))
	footer.add_child(_footer_text)
	_toast_label = W.ellipsis(W.label(""))
	_toast_button = W.button("", func() -> void:
		var action := _toast_action
		hide_toast()
		if action.is_valid():
			action.call())
	_toast_button.custom_minimum_size.y = 0
	_toast_button2 = W.button("", func() -> void:
		var action := _toast_action2
		hide_toast()
		if action.is_valid():
			action.call())
	_toast_button2.custom_minimum_size.y = 0
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
	footer.add_child(_footer_count)
	_open.add_child(footer)


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
	room.find_requested.connect(func(q: String) -> void:
		show_tab(Tab.FILES)
		files.search_for(q))
	show_tab(Tab.FILES)


## The thumbnail for `t` seconds (-1: hide): asks features.thumbs for it (it throttles; the newest wins) and shows
## the nearest picture it has, centred under that point of the bar.
func _thumb_at(t: float) -> void:
	_thumb_time = t
	var thumbs: Node = app.features.get("thumbs") if app != null and app.get("features") != null else null
	if t < 0.0 or thumbs == null or not bool(thumbs.enabled) or not seek.is_visible_in_tree():
		_thumb.visible = false
		return
	thumbs.request(t)
	if not thumbs.thumbnail_ready.is_connected(_on_thumbnail_ready):
		thumbs.thumbnail_ready.connect(_on_thumbnail_ready)
	_show_thumb(thumbs.thumbnail_for(t))


func _on_thumbnail_ready(_seconds: float, _texture: Texture2D) -> void:
	if _thumb_time >= 0.0:
		var thumbs: Node = app.features.get("thumbs")
		_show_thumb(thumbs.thumbnail_for(_thumb_time))


func _show_thumb(tex: Texture2D) -> void:
	_thumb_image.texture = tex
	_thumb_label.text = W.clock(_thumb_time)
	_thumb.visible = true
	_thumb.reset_size()
	var x := seek.global_position.x + seek.x_of(_thumb_time) - _thumb.size.x * 0.5
	x = clampf(x, global_position.x, global_position.x + size.x - _thumb.size.x)
	_thumb.global_position = Vector2(x, seek.global_position.y + seek.size.y + 4.0)


func thumb_shown() -> bool:
	return _thumb.visible


## A form with the keyboard is open: the seek bar and transport make room for it.
func set_form_mode(on: bool) -> void:
	_form_mode = on
	seek.visible = not on and _seekable and not tablet_layout
	_transport.visible = not on and not tablet_layout


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
		tab_buttons[i].set_pressed_no_signal(i == current_tab)
	for i in tablet_tab_buttons.size():
		tablet_tab_buttons[i].set_pressed_no_signal(i == current_tab)
	if _views != null:
		_views.visible = tablet_layout and current_tab == Tab.FILES
	if tablet_layout:
		_refresh_rail()
		if current_tab != Tab.FILES:
			W.card_layout(tabs[current_tab].get("box"), true)
			_pack_cards()
	_update_footer()


## The control that takes the stick focus first when the panel opens: none on the tablet (it is pointed at or
## touched; a focused row would look selected beside the selected one), until the stick moves.
func default_focus() -> Control:
	return null if tablet_layout else _play_button


## Where the stick starts when nothing has the focus: the tab's row on the tablet.
func stick_focus() -> Control:
	return tablet_tab_buttons[current_tab] if tablet_layout else _play_button


# --- The tablet layout ----------------------------------------------------------------------------------------------

func set_text_scale(s: float) -> void:
	if is_equal_approx(s, text_scale):
		return
	text_scale = s
	apply_style()


## The tablet's theme (PaneStyle.tablet_theme()), or null for the front panel's.
func set_tablet_theme(t: Theme) -> void:
	if t == _tablet_theme:
		return
	_tablet_theme = t
	apply_style()


func set_tablet_layout(on: bool) -> void:
	if on == tablet_layout or _body == null:
		return
	tablet_layout = on
	if on and _tablet_row == null:
		_build_tablet_row()
	for c: Control in [_now.get_parent(), _title.get_parent(), _tabs_box]:
		c.visible = not on
	set_form_mode(_form_mode)
	seek.visible = _seekable and not _form_mode and not on
	_tablet_row.visible = on
	var home: Container = _tablet_row.get_node("Content") if on else _open
	_body.get_parent().remove_child(_body)
	home.add_child(_body)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not on:
		_open.move_child(_body, _tablet_row.get_index())
	if _views != null:
		_views.visible = on and current_tab == Tab.FILES
	if on:
		# No backdrop: the tablet's pane shows through (its own margins kept).
		add_theme_stylebox_override("panel", _clear(get_theme_stylebox("panel")))
		_body.add_theme_stylebox_override("panel", _clear(_body.get_theme_stylebox("panel")))
		show_tab(current_tab)
	else:
		remove_theme_stylebox_override("panel")
		_body.remove_theme_stylebox_override("panel")
		for t in tabs:
			var box: Variant = t.get("box")
			if box is VBoxContainer:
				W.card_layout(box, false)


func _build_tablet_row() -> void:
	_tablet_row = W.hbox()
	_tablet_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open.add_child(_tablet_row)
	_open.move_child(_tablet_row, _body.get_index())
	var group := ButtonGroup.new()
	var rail := VBoxContainer.new()
	rail.name = "Rail"
	rail.add_theme_constant_override("separation", 2)
	rail.custom_minimum_size.x = TABLET_TABS_WIDTH
	for i in TABLET_TAB_NAMES.size():
		var b := W.button(TABLET_TAB_NAMES[i], func() -> void: show_tab(i), &"RailButton")
		b.custom_minimum_size.y = PaneStyle.constant(&"button_height") + 4
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.set_meta("icon", TABLET_TAB_ICONS[i])
		rail.add_child(b)
		tablet_tab_buttons.append(b)
	_tablet_row.add_child(rail)
	_tablet_row.add_child(VSeparator.new())
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	_tablet_row.add_child(content)
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
		b.tooltip_text = v.capitalize()
		_views.add_child(b)
		_view_buttons.append(b)
	# In the footer, at the right by the count: the title row has no room for it at the tablet's text size.
	_footer_count.get_parent().add_child(_views)
	_footer_count.get_parent().move_child(_views, _footer_count.get_index())
	if app != null:
		view = str(app.settings.get_value("browser", "view", "details"))
		if not view in VIEWS:
			view = "details"
		if files != null:
			files.set_view(view)
	_refresh_rail()


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


## Packs the tab's cards for the body's width (W.refresh_cards()): the tab fills the body, and the body is always
## laid out, where a tab just shown still has the size it last had.
func _pack_cards() -> void:
	W.refresh_cards(tabs[current_tab].get("box"), _body.size.x - 16.0)


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


func set_title(text: String) -> void:
	_title.text = text if text != "" else "Nothing playing"


## The header's right side, as shown.
func status_line_text() -> String:
	return _status_line.text


## The header's right side: "21:42  ·  1:12 left, ends 22:54  ·  battery 74 %", then low controllers and
## "Listening". Empty parts are left out.
static func status_text(clock: String, remaining_text: String, end_text: String, battery_percent: int,
		charging: bool, extra := "", p_listening := false) -> String:
	var parts: Array[String] = [clock]
	if remaining_text != "":
		parts.append(remaining_text + ((", " + end_text) if end_text != "" else ""))
	if battery_percent >= 0:
		parts.append("battery %d %%%s" % [battery_percent, ", charging" if charging else ""])
	if extra != "":
		parts.append(extra)
	if p_listening:
		parts.append("Listening")
	return "  ·  ".join(parts.filter(func(s: String) -> bool: return s != ""))


## A lasting status line in the footer ("Connecting...", "Starting the browser..."), or "" for the mode line.
func set_status(text: String) -> void:
	_status = text
	_update_footer()


## A short line in the footer with an optional action button ("Undo", "Start over"), for `seconds`.
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


## A line in the footer with two buttons (Keep / Undo), until one is pressed or `seconds` pass.
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
	if _toast_label.text == "Listening":
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


func _time_text(position_s: float, duration: float) -> String:
	if duration <= 0.0:
		return W.clock(position_s) if position_s > 0.0 else ""
	return "%s / %s" % [W.clock(position_s), W.clock(duration)]


## The playback state, a few times a second while the pane shows.
func set_playback(position_s: float, duration: float, playing: bool, can_seek: bool) -> void:
	_play_button.text = "Pause" if playing else "Play"
	seek.set_state(position_s, duration, can_seek and duration > 0.0)
	# A live stream (or HTTP without ranges) can't seek: no seek bar or skips, and LIVE by the time.
	_seekable = can_seek
	seek.visible = can_seek and not _form_mode and not tablet_layout
	for b in _skip_buttons:
		b.visible = can_seek
	var f: Node = app.features if app != null and app.get("features") != null else null
	var trick: Node = f.get("trick") if f != null else null
	var trick_ok := trick != null and bool(trick.available()) and can_seek
	for b in _trick_buttons:
		b.visible = trick_ok
	if not seek.scrubbing:
		var t := _time_text(position_s, duration)
		var live: Node = f.get("live") if f != null else null
		if live != null and bool(live.live):
			t = "LIVE" + (("  " + t) if t != "" else "")
		if trick != null and float(trick.speed) > 0.0:
			t += "  ·  %dx" % roundi(float(trick.speed))
		_time.text = t


## Refreshes the header's status line and the per-second parts of the panel.
func tick() -> void:
	if app == null:
		return
	var f: Node = app.features
	var remaining: float = f.remaining()
	var forecast: Dictionary = f.battery.get_forecast() if f.get("battery") != null else {}
	var available := bool(forecast.get("available", false))
	_status_line.text = status_text(EndTime.clock_at(Time.get_unix_time_from_system()),
			EndTime.format_remaining(remaining), f.end_text() if remaining > 0.0 else "",
			int(forecast.get("percent", -1)) if available else -1, available and bool(forecast.get("charging", false)),
			header_extra, listening)
	seek.set_ticks(PackedFloat32Array(f.chapters.tick_positions()))
	var chapter: String = f.chapters.title_text() if int(f.chapters.current) >= 0 else ""
	_now.text = "Now playing" + (("  ·  chapter " + chapter) if chapter != "" else "")
	_update_footer()
	if tablet_layout and current_tab != Tab.FILES:
		_pack_cards()
	if current_tab == Tab.ROOM:
		room.tick()
	elif current_tab == Tab.SOUND:
		sound.tick()
	elif current_tab == Tab.SUBTITLES:
		subtitles.tick()
	elif current_tab == Tab.SYSTEM:
		system.tick()
