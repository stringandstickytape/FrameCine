extends ScrollContainer

## The Subtitles tab (docs/ui-design.md): track (Off or one of the file's), a second track above it (#65), the
## look (size, below or inside the picture, offset, depth toward the eyes, background; the renderer of #67), delay,
## and the catch-up replay ("Replay
## 10 s": back 10 s with subtitles on, #11), and subtitle files next to the video (#50): on or off, and which were
## loaded. Script (director mode, #8): find a line by its words with the on-pane keyboard, or list the lines around
## now; a row jumps there (0.5 s before the line). Subtitle depth comes when the feature exists.

const W := preload("res://ui/pane_widgets.gd")
const SoundTab := preload("res://ui/sound_tab.gd")
const SearchForm := preload("res://ui/search_form.gd")
const Director := preload("res://scripts/director/director.gd")

var app: Node
var box: VBoxContainer
var _tracks: VBoxContainer
var _size: VBoxContainer
var _delay: VBoxContainer
var _second: VBoxContainer
var _place: HFlowContainer
var _offset: VBoxContainer
var _depth: VBoxContainer
var _background: VBoxContainer
var _find_files: Button
var _files_label: Label
var _script_rows: VBoxContainer
var _script_label: Label
var _find_form: SearchForm
var _query := ""
## The script's track when the file has more than one ("" lets Director pick the track shown), and its rows.
var _script_track := ""
var _script_tracks: VBoxContainer
## What the Script section last showed (find or around now), run again when another track is picked.
var _script_again := Callable()
## An index is being read (Director.building()): the line under Script says how long so far, refreshed by tick().
var _indexing := false
var _indexing_text := ""


func _init() -> void:
	name = "Subtitles"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = W.vbox()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)


func bind(p_app: Node) -> void:
	app = p_app
	var subs: Node = app.features.subtitles
	box.add_child(W.flow([W.button("Replay 10 s", func() -> void: app.features.catch_up.replay())]))
	box.add_child(W.section("Track"))
	_tracks = VBoxContainer.new()
	_tracks.add_theme_constant_override("separation", 0)
	box.add_child(_tracks)
	box.add_child(W.section("Second track"))
	_second = VBoxContainer.new()
	_second.add_theme_constant_override("separation", 0)
	box.add_child(_second)
	box.add_child(W.section("Look and timing"))
	var display: Node = subs.display
	_size = W.slider_row("Size", 0.5, 3.0, 0.1, func(v: float) -> String: return "%.1fx" % v,
			func(v: float) -> void: display.set_scale_factor(v))
	box.add_child(_size)
	_place = W.choices(["Below the picture", "Inside the picture"], func(i: int) -> void:
		display.set_position_mode("below" if i == 0 else "inside"))
	box.add_child(_place)
	_offset = W.slider_row("Offset", -0.5, 0.5, 0.01, func(v: float) -> String: return "%+d %%" % roundi(v * 100.0),
			func(v: float) -> void: display.set_offset(v))
	box.add_child(_offset)
	_depth = W.slider_row("Nearer", 0.0, 2.0, 0.05, func(v: float) -> String: return "%.2f m" % v,
			func(v: float) -> void: display.set_depth(v))
	box.add_child(_depth)
	_background = W.slider_row("Background", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0),
			func(v: float) -> void: display.set_background(v))
	box.add_child(_background)
	var sub_delay: Node = app.features.sub_delay
	_delay = W.slider_row("Delay", -5.0, 5.0, 0.1, func(v: float) -> String: return "%+.1f s" % v,
			func(v: float) -> void: sub_delay.set_delay(v))
	box.add_child(_delay)
	box.add_child(W.flow([W.button("Reset delay", func() -> void: sub_delay.reset())]))
	box.add_child(W.section("Subtitle files"))
	var sub_files: Node = app.features.sub_files
	_find_files = W.toggle("Find files next to the video", func(on: bool) -> void: sub_files.set_enabled(on))
	box.add_child(W.hbox([_find_files]))
	_files_label = W.label("", &"MutedLabel")
	_files_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_files_label)
	sub_files.loaded_changed.connect(func(_l: Array) -> void:
		Director.clear_cache()
		sync())

	box.add_child(W.section("Script"))
	box.add_child(W.flow([W.button("Find a line", _show_find), W.button("Lines around now", _around_now)]))
	_script_tracks = W.vbox()
	_script_tracks.add_theme_constant_override("separation", 0)
	box.add_child(_script_tracks)
	_script_label = W.label("", &"MutedLabel")
	_script_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_script_label)
	_script_rows = VBoxContainer.new()
	_script_rows.add_theme_constant_override("separation", 0)
	box.add_child(_script_rows)
	_find_form = SearchForm.new()
	_find_form.title_text = "Find a line by its words (\"quoted phrases\" too)"
	_find_form.visible = false
	_find_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_find_form.search_requested.connect(func(q: String) -> void:
		_hide_find()
		_find(q))
	_find_form.cancelled.connect(_hide_find)
	box.add_child(_find_form)
	app.file_opened.connect(func(_p: String) -> void:
		_script_track = ""
		_script_again = Callable()
		_set_script_tracks([], "")
		_clear_script())
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree() and _find_form.visible:
			_hide_find())
	subs.tracks_changed.connect(func(_t: Array) -> void: sync())
	subs.secondary_changed.connect(func(_i: int) -> void: sync())
	subs.track_changed.connect(func(_i: int, _e: bool) -> void: sync())
	sub_delay.changed.connect(func(_d: float) -> void: sync())
	sync()


func sync() -> void:
	var subs: Node = app.features.subtitles
	for c in _tracks.get_children():
		_tracks.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	var off := _row("Off", func() -> void: subs.set_enabled(false), group)
	off.set_pressed_no_signal(not subs.enabled)
	var tracks: Array = subs.tracks
	if tracks.is_empty():
		_tracks.add_child(W.label("This file has no subtitle tracks", &"MutedLabel"))
	for t: Dictionary in tracks:
		var parts: Array[String] = []
		for key: String in ["title", "language", "codec"]:
			if str(t.get(key, "")) != "":
				parts.append(str(t[key]))
		for flag in SoundTab.track_flags(t):
			if flag != "default":
				parts.append(flag)
		if bool(t.get("external", false)):
			parts.append("file")
		if bool(t.get("bitmap", false)):
			parts.append("picture")
		var index := int(t.get("index", 0))
		var b := _row(" / ".join(parts) if not parts.is_empty() else "Track %d" % index,
				func() -> void: subs.select_track(index), group)
		b.set_pressed_no_signal(subs.enabled and int(subs.track) == index)
	var display: Node = subs.display
	W.set_slider(_size, float(display.scale_factor))
	W.set_choice(_place, 1 if str(display.position_mode) == "inside" else 0)
	W.set_slider(_offset, float(display.offset))
	W.set_slider(_depth, float(display.depth))
	W.set_slider(_background, float(display.background))
	_sync_second()
	W.set_slider(_delay, float(app.features.sub_delay.delay))
	var sub_files: Node = app.features.sub_files
	W.set_on(_find_files, bool(sub_files.enabled))
	var names: Array[String] = []
	for f: Dictionary in sub_files.loaded:
		names.append(str(f.get("path", "")).get_file())
	_files_label.text = ("Loaded: " + ", ".join(names)) if not names.is_empty() else "No subtitle files found for this video"


func _row(text: String, on_pressed: Callable, group: ButtonGroup) -> Button:
	var b := W.button(text, on_pressed, &"RowButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_group = group
	_tracks.add_child(b)
	return b


## The find form takes the tab's place (and the pane hides its seek bar and transport meanwhile).
func _show_find() -> void:
	W.show_form(box, _find_form, true)
	scroll_vertical = 0
	_find_form.edit(_query)
	(app.ui.ui as Node).call("set_form_mode", true)


func _hide_find() -> void:
	W.show_form(box, _find_form, false)
	sync()
	(app.ui.ui as Node).call("set_form_mode", false)


func _find(q: String) -> void:
	_query = q
	_script_again = _find.bind(q)
	_script_label.text = "Searching..."
	var idx: Dictionary = await _script_index()
	if int(idx.get("count", 0)) == 0:
		_show_lines([], "No script for this file: %s" % idx.get("error", "no subtitle text"))
		return
	var hits := Director.search(idx, q, 50)
	_show_lines(hits, "%d line%s with \"%s\"" % [hits.size(), "" if hits.size() == 1 else "s", q])


func _around_now() -> void:
	_script_again = _around_now
	_script_label.text = "Reading the script..."
	var idx: Dictionary = await _script_index()
	if int(idx.get("count", 0)) == 0:
		_show_lines([], "No script for this file: %s" % idx.get("error", "no subtitle text"))
		return
	var at := Director.line_at(idx, app.player.get_position())
	_show_lines(Director.lines(idx, maxi(0, at - 4), 12), "Lines around %s" % W.clock(app.player.get_position()), at)


## The index for the chosen track; refreshes the "Script from" rows when the file has more than one track.
func _script_index() -> Dictionary:
	_indexing = true
	_indexing_text = _script_label.text
	var idx: Dictionary = await Director.index(app, _script_track)
	_indexing = false
	# A track that failed comes back with no track list: keep the rows, so another can be picked.
	if not (idx.get("tracks", []) as Array).is_empty():
		_set_script_tracks(idx["tracks"], str(idx.get("track", "")))
	return idx


## A few times a second while the tab shows: how long the index read has taken (a track inside the film means reading
## the whole film, which takes a while on a big one).
func tick() -> void:
	if not _indexing:
		return
	var b: Dictionary = Director.building(app)
	if b.is_empty():
		return
	var s := roundi(float(b.get("seconds", 0.0)))
	_script_label.text = "Reading the film for its subtitles: %d s" % s if str(b.get("source", "")) == "engine" 			else "%s %d s" % [_indexing_text, s]


## One row per track ("Script from: English"), only when there is a choice.
func _set_script_tracks(tracks: Array, chosen: String) -> void:
	for c in _script_tracks.get_children():
		_script_tracks.remove_child(c)
		c.queue_free()
	if tracks.size() < 2:
		return
	var group := ButtonGroup.new()
	for t: Dictionary in tracks:
		var id := str(t.get("id", ""))
		var b := W.button("Script from: %s" % t.get("label", id), func() -> void: _pick_script_track(id), &"RowButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.toggle_mode = true
		b.button_group = group
		b.set_pressed_no_signal(id == chosen)
		_script_tracks.add_child(b)


func _pick_script_track(id: String) -> void:
	_script_track = id
	if _script_again.is_valid():
		_script_again.call()
	else:
		_around_now()


## Rows "0:42:17  the line"; a row jumps there. now: the index of the line being said, marked.
func _show_lines(entries: Array, heading: String, now := -1) -> void:
	_clear_script()
	_script_label.text = heading
	for e: Dictionary in entries:
		var b := W.button("%s  %s" % [W.clock(float(e.get("start", 0.0))), str(e.get("text", "")).replace("\n", " ")],
				Callable(), &"RowButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.toggle_mode = true
		b.set_pressed_no_signal(int(e.get("i", -2)) == now)
		var entry := e
		b.pressed.connect(func() -> void: Director.jump(app, entry))
		_script_rows.add_child(b)


func _clear_script() -> void:
	for c in _script_rows.get_children():
		_script_rows.remove_child(c)
		c.queue_free()
	_script_label.text = ""


## The second track (#65): Off, or a subtitle file next to the video other than the main track.
func _sync_second() -> void:
	var subs: Node = app.features.subtitles
	for c in _second.get_children():
		_second.remove_child(c)
		c.queue_free()
	var options: Array = subs.secondary_tracks()
	if options.is_empty():
		var note := W.label("A second track needs a subtitle file next to the video", &"MutedLabel")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_second.add_child(note)
		return
	var group := ButtonGroup.new()
	var off := _row_in(_second, "Off", func() -> void: subs.select_secondary(-1), group)
	off.set_pressed_no_signal(int(subs.secondary) < 0)
	for t: Dictionary in options:
		var parts: Array[String] = []
		for key: String in ["title", "language"]:
			if str(t.get(key, "")) != "":
				parts.append(str(t[key]))
		var index := int(t.get("index", 0))
		var b := _row_in(_second, " / ".join(parts) if not parts.is_empty() else "Track %d" % index,
				func() -> void: subs.select_secondary(index), group)
		b.set_pressed_no_signal(int(subs.secondary) == index)


func _row_in(parent: Container, text: String, on_pressed: Callable, group: ButtonGroup) -> Button:
	var b := W.button(text, on_pressed, &"RowButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_group = group
	parent.add_child(b)
	return b
