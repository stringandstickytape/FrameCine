extends ScrollContainer

## The System tab (docs/ui-design.md): the info overlay and the stats view; the panel's layout (size, distance,
## recentre hold, follow the head, left-handed, reset) so the numbers can be tuned in the headset; accessibility (#74);
## test patterns, calibration cards and the bandwidth meter (#48); the benchmark (#82); hardware 10-bit video (which way
## it plays, read-only, ui/hw_video_row.gd); foveation (D22) and the film layer (#70, a prototype); the controllers' look
## and haptics; the phone remote with its address and QR code (#13); the assistant (ui/assistant_row.gd); the dev tools
## when dev mode is on (theme, remote changes and their undo); about.
##
## Hooks used: scripts/dev/stats.gd (made here while the stats view is on, freed when it goes off or the tab hides),
## DevHost.instance().permissions (scripts/dev/permission_ring.gd), scripts/remote/remote.gd,
## scripts/dev/test_lab.gd, scripts/dev/benchmark.gd, main.features.access.

const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const DevHost := preload("res://scripts/dev/dev_host.gd")
const Remote := preload("res://scripts/remote/remote.gd")
const QrCode := preload("res://scripts/remote/qr_code.gd")
const StatsScript := preload("res://scripts/dev/stats.gd")
const TestLab := preload("res://scripts/dev/test_lab.gd")
const Benchmark := preload("res://scripts/dev/benchmark.gd")
const Tour := preload("res://scripts/dev/tour.gd")
const HwVideoRow := preload("res://ui/hw_video_row.gd")
const AssistantRow := preload("res://ui/assistant_row.gd")
const ControllerLook := preload("res://scripts/xr/controller_look.gd")
const ObjectSection := preload("res://ui/object_section.gd")

## Open a place of the Files tab (test patterns, network hosts).
signal open_place(path: String)
## A [pane] layout setting or the left-handed setting changed (the UI layer applies them).
signal layout_changed
## Back to the doc's layout.
signal reset_layout_requested
## Reload the theme file.
signal reload_theme_requested

const REMOTE_MODES := ["ask", "allow", "deny"]
const REMOTE_WORDS := ["Ask", "Allow", "Deny"]
## main.gd's FOVEATION_LEVELS, in order.
const FOVEATION_WORDS := ["Off", "Low", "Medium", "High"]
const FOVEATION_HELP := "Saves GPU time at the edges of your view. High can look blocky."
const FOVEATION_UNAVAILABLE := "Foveation isn't available: this build starts without it."
const LOOK_COLUMNS := 3
const LOOK_HELP := "Both controllers. The labels change ink, or get a dark outline, to stay readable."

var app: Node
var box: VBoxContainer
var _overlay: Button
var _stats_toggle: Button
var _stats_label: Label
var _stats: Node
## The controllers' look: the presets, the colour palette and the speed slider for a look that takes them.
var _look_grid: GridContainer
var _look_colours: GridContainer
var _look_speed: HBoxContainer
var _haptics: Button
var _strength: HBoxContainer
var _jog: Button
var _thumbs: Button
var _jog_turn: HBoxContainer
var _zoom_lens: Button
var _magnification: HBoxContainer
var _left_handed: Button
var _foveation: HBoxContainer
var _foveation_help: Label
var _foveation_sharp: Button
var _film_layer: Button
var _film_layer_help: Label
## [pane] world_locked off: the panel follows the head lazily.
var _follow_head: Button
var _layout_rows := {}
var _ui_scale: HBoxContainer
var _monocular: Button
var _monocular_eye: HBoxContainer
var _subs_always: Button
var _lab_path: LineEdit
var _lab_result: Label
var _lab_busy := false
var _bench_label: Label
var _bench: Node
var _tour_box: HBoxContainer
var _tour_label: Label
var _remote_toggle: Button
var _remote_url: Label
var _remote_qr: TextureRect
var _remote_server: Node
## Sharing the headset's files (docs/share.md): the same server; its own address and QR code (the code stays on screen).
var _share_toggle: Button
var _share_url: Label
var _share_qr: TextureRect
## Assistant (docs/assistant.md).
var assistant_row: AssistantRow
var _dev_box: VBoxContainer
var _dev_status: Label
var _remote_mode: HBoxContainer
var _changes: VBoxContainer
var _ring: Node
## The stats view refreshes at 2 Hz (stats.gd's collect() is meant for 1 to 4 Hz).
var _stats_next_msec := 0


func _init() -> void:
	name = "System"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = W.vbox()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_stop_stats())


func bind(p_app: Node) -> void:
	app = p_app
	box.add_child(W.section("Views"))
	_overlay = W.toggle("Info overlay", func(on: bool) -> void: app.set_overlay(on))
	_stats_toggle = W.toggle("Stats", func(on: bool) -> void:
		if on:
			_start_stats()
		else:
			_stop_stats())
	box.add_child(W.hbox([_overlay, _stats_toggle]))
	_stats_label = W.label("", &"MutedLabel")
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.visible = false
	box.add_child(_stats_label)

	box.add_child(W.section("Panel"))
	var set_layout := func(key: String, v: Variant) -> void:
		app.settings.set_value("pane", key, v)
		layout_changed.emit()
	_layout_rows["scale"] = W.slider_row("Size", 0.5, 3.0, 0.05,
			func(v: float) -> String: return "%d cm" % roundi(24.0 * v), func(v: float) -> void: set_layout.call("scale", v))
	_layout_rows["distance"] = W.slider_row("Distance", 0.4, 2.0, 0.05,
			func(v: float) -> String: return "%.2f m" % v, func(v: float) -> void: set_layout.call("distance", v))
	_layout_rows["recentre_hold"] = W.slider_row("Hold menu to recentre", 0.3, 1.5, 0.05,
			func(v: float) -> String: return "%.2f s" % v, func(v: float) -> void: set_layout.call("recentre_hold", v))
	for key in ["scale", "distance", "recentre_hold"]:
		box.add_child(_layout_rows[key])
	var access: Node = app.features.access
	_follow_head = W.toggle("Follow my head", func(on: bool) -> void: set_layout.call("world_locked", not on))
	_left_handed = W.toggle("Left-handed", func(on: bool) -> void: access.set_value("left_handed", on))
	box.add_child(W.hbox([_follow_head, _left_handed, W.button("Reset layout", func() -> void:
		reset_layout_requested.emit()
		sync())]))

	box.add_child(W.section("Accessibility"))
	_ui_scale = W.slider_row("Larger panel", 1.0, 2.0, 0.05, func(v: float) -> String: return "%.2fx" % v,
			func(v: float) -> void: access.set_value("ui_scale", v))
	box.add_child(_ui_scale)
	_monocular = W.toggle("One eye for 3D", func(on: bool) -> void: access.set_value("monocular", on))
	_monocular_eye = W.choices(["Left eye", "Right eye"], func(i: int) -> void: access.set_value("monocular_eye", i))
	box.add_child(W.hbox([_monocular, _monocular_eye]))
	_subs_always = W.toggle("Subtitles always on", func(on: bool) -> void: access.set_value("subtitles_always", on))
	box.add_child(W.hbox([_subs_always]))
	access.changed.connect(func(_k: String, _v: Variant) -> void: sync())

	box.add_child(W.section("Test and setup"))
	box.add_child(W.hbox([W.button("Test patterns", func() -> void: open_place.emit("stub://")),
			W.button("Network hosts", func() -> void: open_place.emit("network://"))]))
	var cards := W.hbox()
	for card: Dictionary in TestLab.cards():
		var card_path: String = card["path"]
		cards.add_child(W.button(str(card["label"]), func() -> void: app.open_path(card_path, false)))
	box.add_child(W.label("Calibration cards", &"MutedLabel"))
	var cards_scroll := ScrollContainer.new()
	cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cards_scroll.custom_minimum_size = Vector2(0, PaneStyle.constant(&"button_height") + 10)
	cards_scroll.add_child(cards)
	box.add_child(cards_scroll)
	_lab_path = LineEdit.new()
	_lab_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lab_path.virtual_keyboard_enabled = false
	_lab_path.placeholder_text = "a file on a share, e.g. smb://host/share/film.mkv"
	box.add_child(W.hbox([_lab_path, W.button("Measure bandwidth", _measure)]))
	_lab_result = W.label("", &"MutedLabel")
	_lab_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lab_result)
	box.add_child(W.hbox([W.button("Run benchmark", _run_benchmark)]))
	_bench_label = W.label("", &"MutedLabel")
	_bench_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_bench_label)
	app.file_opened.connect(func(p: String) -> void:
		if p.begins_with("smb://") and not _lab_busy:
			_lab_path.text = p)

	_tour_label = W.ellipsis(W.label("", &"MutedLabel"))
	_tour_box = W.hbox([_tour_label, W.button("Stop tour", func() -> void:
		Tour.stop()
		_sync_tour())])
	_tour_box.visible = false
	box.add_child(_tour_box)

	# Hardware 10-bit video (scripts/play/hw_video.gd): P010, Q10C or software, and Details. Read-only.
	if app.features.get("hwvideo") != null:
		box.add_child(W.section("Hardware video"))
		var hw_row := HwVideoRow.new()
		box.add_child(hw_row)
		hw_row.bind(app.features.hwvideo)

	# Foveation (D22): main.gd's [view] foveation and foveation_sharp_panel; both apply at once.
	box.add_child(W.section("Rendering"))
	_foveation = W.choices(FOVEATION_WORDS, func(i: int) -> void: app.set_foveation(app.FOVEATION_LEVELS[i]))
	box.add_child(W.hbox([W.label("Foveation"), _foveation]))
	_foveation_help = W.help(FOVEATION_HELP)
	box.add_child(_foveation_help)
	_foveation_sharp = W.toggle("Sharp while the panel shows", func(on: bool) -> void:
		app.set_foveation_sharp_panel(on))
	box.add_child(W.hbox([_foveation_sharp]))
	# Film layer (#70, a prototype): the flat film drawn by the headset's compositor, for comparison.
	var film_layer: Node = app.features.film_layer
	_film_layer = W.toggle("Film drawn by the headset (test)", func(on: bool) -> void:
		film_layer.set_enabled(on)
		_film_layer_help.text = film_layer.status())
	box.add_child(W.hbox([_film_layer]))
	_film_layer_help = W.help(film_layer.status())
	box.add_child(_film_layer_help)

	box.add_child(W.section("Controllers"))
	_build_look()
	var haptics: Node = app.features.haptics
	_haptics = W.toggle("Haptic ticks", func(on: bool) -> void: haptics.set_enabled(on))
	box.add_child(W.hbox([_haptics]))
	_strength = W.slider_row("Tick strength", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0),
			func(v: float) -> void: haptics.set_strength(v))
	box.add_child(_strength)
	# Jog wheel (#63): circle a stick round its rim to scrub.
	var jog: Node = app.features.jog
	_jog = W.toggle("Jog wheel", func(on: bool) -> void:
		jog.set_enabled(on)
		_jog_turn.visible = on)
	box.add_child(W.hbox([_jog]))
	_jog_turn = W.slider_row("One turn", 10.0, 600.0, 10.0, func(v: float) -> String: return W.short_clock(v),
			func(v: float) -> void: jog.set_seconds_per_turn(v))
	box.add_child(_jog_turn)
	# Seek-bar thumbnails (#40): a second decoder session, about 150 MB at 2160p, so off by default.
	var thumbs: Node = app.features.thumbs
	_thumbs = W.toggle("Seek bar pictures", func(on: bool) -> void: thumbs.set_enabled(on))
	box.add_child(W.hbox([_thumbs]))
	# Zoom lens (#38): in 180 / 360, hold the grip and pull the trigger for a magnifier.
	var zoom_lens: Node = app.features.zoom_lens
	_zoom_lens = W.toggle("Zoom lens (grip and trigger in 180 / 360)", func(on: bool) -> void:
		zoom_lens.set_enabled(on)
		_magnification.visible = on)
	box.add_child(W.hbox([_zoom_lens]))
	_magnification = W.slider_row("Magnification", 1.5, 8.0, 0.5, func(v: float) -> String: return "%.1fx" % v,
			func(v: float) -> void: zoom_lens.set_magnification(v))
	box.add_child(_magnification)

	box.add_child(W.section("Phone remote"))
	_remote_toggle = W.toggle("Phone remote", func(on: bool) -> void:
		if on:
			Remote.start(app, true)
		else:
			Remote.stop(app, true)
			if _live_server() == null:
				_remote_server = null
		_sync_remote())
	box.add_child(W.hbox([_remote_toggle, W.button("Unpair phones", func() -> void:
		var server := Remote.instance()
		if server != null:
			server.new_key()
			_show_address())]))
	_remote_url = W.label("", &"TimeLabel")
	box.add_child(_remote_url)
	_remote_qr = TextureRect.new()
	_remote_qr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_remote_qr.custom_minimum_size = Vector2(0, 0)
	box.add_child(_remote_qr)

	box.add_child(W.section("Share files"))
	_share_toggle = W.toggle("Share this headset's files", func(on: bool) -> void:
		if on:
			Remote.start_share(app, true)
		else:
			Remote.stop_share(app, true)
			if _live_server() == null:
				_remote_server = null
		_sync_remote())
	box.add_child(W.hbox([_share_toggle]))
	var share_note := W.label("Phones and computers on this network can download and upload files. Scan the code: "
			+ "it holds the pairing code, which is shown nowhere else.", &"MutedLabel")
	share_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(share_note)
	_share_url = W.label("", &"TimeLabel")
	box.add_child(_share_url)
	_share_qr = TextureRect.new()
	_share_qr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	box.add_child(_share_qr)

	box.add_child(W.section("Assistant"))
	assistant_row = AssistantRow.new()
	box.add_child(assistant_row)
	assistant_row.bind(app)

	_dev_box = W.vbox()
	box.add_child(_dev_box)
	_dev_box.add_child(W.section("Dev tools"))
	_dev_status = W.label("", &"MutedLabel")
	_dev_box.add_child(_dev_status)
	_dev_box.add_child(W.hbox([W.button("Reload theme", func() -> void: reload_theme_requested.emit())]))
	_dev_box.add_child(W.label("Remote changes"))
	_remote_mode = W.choices(REMOTE_WORDS, func(i: int) -> void:
		app.settings.set_value("dev", "remote_changes", REMOTE_MODES[i])
		_sync_dev())
	_dev_box.add_child(_remote_mode)
	_dev_box.add_child(W.hbox([W.button("Allow for an hour", func() -> void:
				if _ring != null:
					_ring.allow_for(3600.0)
				_sync_dev()),
			W.button("Revoke", func() -> void:
				if _ring != null:
					_ring.revoke()
				_sync_dev())]))
	_changes = VBoxContainer.new()
	_changes.add_theme_constant_override("separation", 0)
	_dev_box.add_child(_changes)

	box.add_child(W.section("About"))
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	box.add_child(W.label("VR Video Player%s" % ((" " + version) if version != "" else "")))
	box.add_child(W.label("Engine %s, %s" % [Engine.get_version_info().get("string", ""),
			str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))], &"MutedLabel"))
	app.audio_settings_changed.connect(sync)
	sync()


func sync() -> void:
	W.set_on(_overlay, app.overlay_on)
	W.set_on(_stats_toggle, _stats != null)
	var haptics: Node = app.features.haptics
	W.set_on(_haptics, haptics.enabled)
	W.set_slider(_strength, haptics.strength)
	W.set_on(_thumbs, bool(app.features.thumbs.enabled))
	W.set_on(_film_layer, bool(app.features.film_layer.enabled))
	_film_layer_help.text = app.features.film_layer.status()
	var jog: Node = app.features.jog
	W.set_on(_jog, bool(jog.enabled))
	W.set_slider(_jog_turn, float(jog.seconds_per_turn))
	_jog_turn.visible = bool(jog.enabled)
	var zoom_lens: Node = app.features.zoom_lens
	W.set_on(_zoom_lens, bool(zoom_lens.enabled))
	W.set_slider(_magnification, float(zoom_lens.magnification))
	_magnification.visible = bool(zoom_lens.enabled)
	var access: Node = app.features.access
	W.set_on(_left_handed, bool(access.get_value("left_handed")))
	var locked: bool = app.ui == null or not app.ui.has_method("layout_value") or bool(app.ui.layout_value("world_locked"))
	W.set_on(_follow_head, not locked)
	for key: String in _layout_rows:
		W.set_slider(_layout_rows[key], float(app.ui.layout_value(key)) if app.ui != null and app.ui.has_method("layout_value")
				else 1.0)
	W.set_slider(_ui_scale, float(access.get_value("ui_scale")))
	W.set_on(_monocular, bool(access.get_value("monocular")))
	W.set_choice(_monocular_eye, int(access.get_value("monocular_eye")))
	_monocular_eye.visible = bool(access.get_value("monocular"))
	W.set_on(_subs_always, bool(access.get_value("subtitles_always")))
	_sync_foveation()
	_sync_look()
	_sync_benchmark()
	_sync_remote()
	_sync_dev()


## A few times a second while the tab shows.
func tick() -> void:
	if _stats != null and Time.get_ticks_msec() >= _stats_next_msec:
		_stats_next_msec = Time.get_ticks_msec() + 500
		_stats_label.text = "\n".join(StatsScript.summary_lines(_stats.collect()))
	if (_remote_toggle.button_pressed or _share_toggle.button_pressed) and _remote_server == null:
		_sync_remote()
	if _ring != null and float(_ring.allowed_seconds()) > 0.0:
		_sync_dev()
	_sync_tour()
	_film_layer_help.text = app.features.film_layer.status()
	assistant_row.tick()


func _start_stats() -> void:
	if _stats != null:
		return
	_stats = StatsScript.new()
	_stats.name = "PaneStats"
	_stats.main = app
	add_child(_stats)
	_stats_label.visible = true
	_stats_label.text = "..."


func _stop_stats() -> void:
	if _stats != null:
		_stats.queue_free()
		_stats = null
	if _stats_label != null:
		_stats_label.visible = false
	if _stats_toggle != null:
		W.set_on(_stats_toggle, false)


## Without a foveated swapchain (xr/openxr/foveation_level 0 at start) the row says so and takes no input.
func _sync_foveation() -> void:
	var available: bool = app.foveation_available()
	W.set_choice(_foveation, app.FOVEATION_LEVELS.find(app.foveation) if available else -1)
	W.set_on(_foveation_sharp, bool(app.foveation_sharp_panel))
	for b: Button in _foveation.get_children():
		b.disabled = not available
	_foveation_sharp.disabled = not available
	_foveation_help.text = FOVEATION_HELP if available else FOVEATION_UNAVAILABLE


## The remote and the file share are one server (remote_server.gd); each switch shows its own part of it.
## The controllers' look (scripts/xr/controller_look.gd): every preset as a button with its swatch or the effect's
## preview, three to a row; under them, for a look that takes them, a palette for its colour and a slider for its
## speed. The controllers in your hands are the preview: a choice shows on them at once.
func _build_look() -> void:
	box.add_child(W.label("Look"))
	_look_grid = GridContainer.new()
	_look_grid.columns = LOOK_COLUMNS
	_look_grid.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	_look_grid.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	for id in ControllerLook.ids():
		var e := ControllerLook.entry(id)
		var b := W.button(str(e["name"]), func() -> void:
			app.set_controller_look(id, {})
			_sync_look(), &"RowButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.icon = _look_icon(id)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = str(e["description"])
		b.set_meta("look", id)
		_look_grid.add_child(b)
	box.add_child(_look_grid)
	_look_colours = GridContainer.new()
	_look_colours.columns = ObjectSection.PALETTE.size() / 2
	_look_colours.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	_look_colours.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	for hex: String in ObjectSection.PALETTE:
		var b := W.button("", func() -> void: _set_look_option("color", hex))
		b.custom_minimum_size = Vector2(PaneStyle.constant(&"button_height"), PaneStyle.constant(&"button_height"))
		b.tooltip_text = hex
		var dot := ColorRect.new()
		dot.color = Color.html(hex)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		b.add_child(dot)
		_look_colours.add_child(b)
	box.add_child(_look_colours)
	_look_speed = W.slider_row("Speed", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0),
			func(v: float) -> void: _set_look_option("speed", v))
	box.add_child(_look_speed)
	box.add_child(W.help(LOOK_HELP))


## One option of the look on show, over the others it has.
func _set_look_option(key: String, value: Variant) -> void:
	var options: Dictionary = (app.controller_look_options as Dictionary).duplicate()
	options[key] = value
	app.set_controller_look(app.controller_look, options)
	_sync_look()


func _sync_look() -> void:
	if _look_grid == null:
		return
	var id := str(app.controller_look)
	for b: Button in _look_grid.get_children():
		b.set_pressed_no_signal(str(b.get_meta("look")) == id)
	var specs := ControllerLook.option_specs(id)
	_look_colours.visible = specs.has("color")
	_look_speed.visible = specs.has("speed")
	if specs.has("speed"):
		W.set_slider(_look_speed, float(ControllerLook.options_of(id, app.controller_look_options).get("speed",
				specs["speed"]["default"])))


## A look's picker icon: the effect's preview, or a square of the plastic's or the metal's colour.
static func _look_icon(id: String) -> Texture2D:
	var e := ControllerLook.entry(id)
	if e.has("effect"):
		return ObjectSection.effect_icon(str(e["effect"]))
	return ObjectSection.swatch_icon("#" + ControllerLook.body_colour(id).to_html(false))


func _sync_remote() -> void:
	var server := _live_server()
	W.set_on(_remote_toggle, bool(server.remote_enabled) if server != null
			else bool(app.settings.get_value("remote", "enabled", false)))
	W.set_on(_share_toggle, bool(server.share_enabled) if server != null
			else bool(app.settings.get_value("share", "enabled", false)))
	if server != null and server != _remote_server:
		_remote_server = server
		server.address_changed.connect(func(_url: String, _qr: Image) -> void: _show_address())
	_show_address()


func _show_address() -> void:
	var server: Node = _live_server() if _remote_server != null and is_instance_valid(_remote_server) else null
	var remote_url: String = server.get_url() if server != null and bool(server.remote_enabled) else ""
	# The pairing code is in the QR code; the address alone is easier to read.
	_show_code(_remote_url, _remote_qr, remote_url, server.get_qr_modules() if remote_url != "" else [])
	var share_url: String = server.get_share_url() if server != null and bool(server.share_enabled) \
			and str(server.get_url()) != "" else ""
	_show_code(_share_url, _share_qr, share_url, QrCode.encode(share_url, "M") if share_url != "" else [])


## The server, unless it is going away (it stays in the tree until the end of the frame).
static func _live_server() -> Node:
	var server := Remote.instance()
	return server if server != null and not server.is_queued_for_deletion() else null


## An address without its pairing code, and the QR code of the whole address; hidden when there is none.
func _show_code(label: Label, qr: TextureRect, url: String, modules: Array) -> void:
	label.text = url.get_slice("?", 0)
	label.visible = url != ""
	if modules.is_empty():
		qr.texture = null
		qr.visible = false
		return
	var img := QrCode.to_image(modules, 4, 4, PaneStyle.color(&"qr_dark"), PaneStyle.color(&"qr_light"))
	qr.texture = ImageTexture.create_from_image(img)
	qr.custom_minimum_size = Vector2(img.get_width(), img.get_height())
	qr.visible = true


func _sync_dev() -> void:
	var dev := DevHost.instance()
	_dev_box.visible = dev != null
	if dev == null:
		return
	var ring: Node = dev.get("permissions")
	if ring != null and ring != _ring:
		_ring = ring
		ring.remote_change.connect(func(_e: Dictionary) -> void: _sync_changes())
	var reload := "hot-reload on" if dev.get("hot_reload") != null else "hot-reload off"
	var allowed := float(_ring.allowed_seconds()) if _ring != null else 0.0
	_dev_status.text = "%s; remote changes allowed for %d more min" % [reload, ceili(allowed / 60.0)] if allowed > 0.0 \
			else reload
	var m := str(_ring.mode()) if _ring != null else "ask"
	W.set_choice(_remote_mode, REMOTE_MODES.find(m))
	_sync_changes()


## The latest remote changes, newest first, each with Undo while it can be undone.
func _sync_changes() -> void:
	for c in _changes.get_children():
		_changes.remove_child(c)
		c.queue_free()
	if _ring == null:
		return
	var hist: Array = _ring.status()["history"]
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 6), -1):
		var e: Dictionary = hist[i]
		var line := W.ellipsis(W.label("%s (%s)" % [e["summary"], e["state"]], &"MutedLabel"))
		var row := W.hbox([line])
		if bool(e.get("undoable", false)):
			var id := int(e["id"])
			row.add_child(W.button("Undo", func() -> void: _ring.undo(id)))
		_changes.add_child(row)


## The bandwidth meter (test lab, #48): reads the file for 8 s on a worker thread.
func _measure() -> void:
	var path := _lab_path.text.strip_edges()
	if path == "" or _lab_busy:
		return
	_lab_busy = true
	_lab_result.text = "Measuring %s ..." % path.get_file()
	var r: Dictionary = await TestLab.measure_async(get_tree(), path, 8.0)
	_lab_busy = false
	if r.has("error"):
		_lab_result.text = "Can't measure: %s" % r["error"]
	else:
		_lab_result.text = "%.0f Mbit/s average, %.0f peak, opened in %d ms, %.0f MB read" % [float(r.get("mbps_avg", 0.0)),
				float(r.get("mbps_peak", 0.0)), int(r.get("open_ms", 0)), float(r.get("megabytes", 0.0))]


## The benchmark (#82): decode the biggest video for 10 s; progress and the result (saved in the settings).
func _run_benchmark() -> void:
	if Benchmark.running() != null:
		return
	_bench = Benchmark.start(app)
	if _bench == null:
		_bench_label.text = "This engine build can't run the benchmark."
		return
	_bench.progress.connect(func(_f: float, text: String) -> void: _bench_label.text = text)
	_bench.finished.connect(func(_r: Dictionary) -> void:
		_bench = null
		_sync_benchmark())


func _sync_benchmark() -> void:
	if Benchmark.running() != null:
		return
	var r := Benchmark.saved(app.settings)
	_bench_label.text = str(r.get("summary", "")) if not r.is_empty() else ""


## A scripted tour (#91) running: its name, round and step, and Stop.
func _sync_tour() -> void:
	var t := Tour.running()
	_tour_box.visible = t != null
	if t == null:
		return
	var st: Dictionary = t.status()
	_tour_label.text = "Tour %s%s: round %d, step %d of %d" % [st.get("name", ""),
			" (kiosk)" if bool(st.get("kiosk", false)) else "", int(st.get("round", 0)), int(st.get("step", 0)) + 1,
			int(st.get("steps", 0))]
