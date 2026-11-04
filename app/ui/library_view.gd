extends RefCounted

## Draws the Library place (scripts/library/library_index.gd) into the Files tab's list: a poster grid of shows and films,
## a show's page with its seasons, a season's episodes as rows with thumbnail, number, title and short plot, a film's page.
## Rows go through the tab (add_library_row), so one click opens, the playlist is the rows on show, and focus and tests
## work as in any folder. What was watched comes from the resume data, shown by marks that update in place.
## Pictures come from scripts/library/library_images.gd: nothing here touches a file.

const LibraryImages := preload("res://scripts/library/library_images.gd")
const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")

## Pixels on the pane, which are the pictures' cached sizes too.
const POSTER := Vector2i(130, 195)
const SMALL_POSTER := Vector2i(110, 165)
const THUMB := Vector2i(120, 68)
## The grid view's episode tile: the thumbnail drawn larger (the cached picture is THUMB).
const TILE_THUMB := Vector2i(180, 101)
const HERO := Vector2i(550, 190)
const EPISODE_ROW := 92
const SEASON_ROW := 48
const CARD_TEXT := 46
const HERO_PLOT_LINES := 5
const ROW_PLOT_LINES := 2
## How far the fanart shows through behind a page's title.
const FANART_ALPHA := 0.32
const EMPTY_TEXT := "Nothing here yet. Ask an agent on the headset to fill it, or add folders to %s"

var tab: Control
var images: Node
## How long the last draw() took on the main thread, microseconds (tests).
var last_draw_usec := 0
## [{keys: [...], label: Label, bar: Control or null}]: what update_marks() goes through.
var _marks: Array[Dictionary] = []


func _init(p_tab: Control, p_images: Node) -> void:
	tab = p_tab
	images = p_images


func draw(data: Dictionary) -> void:
	var begun := Time.get_ticks_usec()
	_marks.clear()
	images.forget_waiting()
	match str(data["view"]):
		"home":
			_draw_home(data)
		"shelf":
			_up(data)
			_grid(data["cards"])
			_plain(data)
			_files(data.get("files", []))
		"show":
			_up(data)
			_draw_show(data)
		"season":
			_up(data)
			_draw_season(data)
		"movie":
			_up(data)
			_draw_film(data["film"])
	update_marks()
	last_draw_usec = Time.get_ticks_usec() - begun


func _draw_home(data: Dictionary) -> void:
	var shows: Array = data["shows"]
	var films: Array = data["films"]
	if not shows.is_empty():
		tab.add_library_control(W.section("TV shows"))
		_grid(shows)
	if not films.is_empty():
		tab.add_library_control(W.section("Films"))
		_grid(films)
	if shows.is_empty() and films.is_empty() and (data["plain"] as Array).is_empty():
		var l := _plot(EMPTY_TEXT % tab.current, HERO_PLOT_LINES)
		l.custom_minimum_size.y = PaneStyle.constant(&"row_height") * 2
		tab.add_library_control(l)
	_plain(data)
	_files(data.get("files", []))


func _up(data: Dictionary) -> void:
	tab.add_library_up(str(data["parent"]))


func _plain(data: Dictionary) -> void:
	for f: Dictionary in data.get("plain", []):
		tab.add_library_folder(str(f["name"]), str(f["path"]))


## The episodes (or a shelf's loose files): rows, or tiles in the grid view.
func _files(files: Array) -> void:
	var flow: Control = null
	if tab.view == "grid" and not files.is_empty():
		flow = W.flow()
		tab.add_library_control(flow)
	for e: Dictionary in files:
		_episode_row(e, flow)


## The cards of a shelf: posters that flow to the width (details), smaller ones without a caption (grid), or rows
## of titles (list).
func _grid(cards: Array) -> void:
	if cards.is_empty():
		return
	if tab.view == "list":
		for c: Dictionary in cards:
			var b := _row(SEASON_ROW)
			var line := W.hbox()
			_fill(b, line)
			line.add_child(_mouseless(W.ellipsis(W.label(str(c["title"])))))
			var mark := _mouseless(W.label("", &"MutedLabel"))
			line.add_child(mark)
			_marks.append({"keys": c["keys"], "label": mark, "bar": null, "year": int(c["year"]), "show": c["kind"] == "show"})
			tab.add_library_row(b, {"kind": "dir", "path": str(c["path"]), "text": str(c["title"])})
		return
	var grid := W.flow()
	tab.add_library_control(grid)
	for c: Dictionary in cards:
		_card(grid, c)


## A poster, its title and a line under it (the grid view: the poster alone, smaller). A show says how much was
## watched, a film whether it was.
func _card(grid: Control, c: Dictionary) -> void:
	var captioned: bool = tab.view != "grid"
	var size: Vector2i = POSTER if captioned else SMALL_POSTER
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.custom_minimum_size = Vector2(size.x, size.y + (CARD_TEXT if captioned else 0))
	var art := _picture(str(c["poster"]), size, Rect2(Vector2.ZERO, size), str(c["title"]))
	b.add_child(art)
	var title := W.ellipsis(W.label(str(c["title"])))
	title.set_position(Vector2(4, size.y + 2))
	title.size = Vector2(size.x - 8, 20)
	title.custom_minimum_size = Vector2(size.x - 8, 0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.visible = captioned
	b.add_child(title)
	var line := W.label(str(c["year"]) if int(c["year"]) > 0 else "", &"MutedLabel")
	line.set_position(Vector2(4, size.y + 22))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.visible = captioned
	b.add_child(line)
	var bar := _bar(b, Rect2(0, size.y - 3, size.x, 3))
	_marks.append({"keys": c["keys"], "label": line, "bar": bar, "year": int(c["year"]), "show": c["kind"] == "show"})
	tab.add_library_row(b, {"kind": "dir", "path": str(c["path"]), "text": str(c["title"])}, grid)


## A page's head: the fanart dim behind the poster, the title, a line of facts and the plot.
func _hero(title: String, facts: String, plot: String, poster: String, fanart: String) -> void:
	var hero := Control.new()
	hero.custom_minimum_size = Vector2(0, HERO.y)
	hero.clip_contents = true
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_library_control(hero)
	if fanart != "":
		var art := _picture(fanart, HERO, Rect2(Vector2.ZERO, HERO), "")
		art.modulate.a = FANART_ALPHA
		hero.add_child(art)
	var at := PaneStyle.constant(&"gap") * 2
	var text_x := at
	if poster != "":
		hero.add_child(_picture(poster, SMALL_POSTER, Rect2(Vector2(at, (HERO.y - SMALL_POSTER.y) / 2),
				SMALL_POSTER), ""))
		text_x += SMALL_POSTER.x + at
	var box := VBoxContainer.new()
	box.set_position(Vector2(text_x, at))
	box.size = Vector2(HERO.x - text_x - at, HERO.y - at * 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(box)
	box.add_child(W.ellipsis(W.label(title, &"TitleLabel")))
	if facts != "":
		box.add_child(W.ellipsis(W.label(facts, &"CapsLabel")))
	if plot != "":
		box.add_child(_plot(plot, HERO_PLOT_LINES))


func _draw_show(data: Dictionary) -> void:
	var c: Dictionary = data["card"]
	var seasons: Array = data["seasons"]
	var facts: PackedStringArray = []
	if int(c["year"]) > 0:
		facts.append(str(c["year"]))
	if seasons.size() > 0:
		facts.append("%d season%s" % [seasons.size(), "" if seasons.size() == 1 else "s"])
	for g: String in (c["genre"] as Array).slice(0, 2):
		facts.append(g)
	if tab.view != "list":
		_hero(str(c["title"]), "  ".join(facts).to_upper(), str(c["plot"]), str(c["poster"]), str(c["fanart"]))
	for s: Dictionary in seasons:
		var b := _row(SEASON_ROW)
		var line := W.hbox()
		_fill(b, line)
		line.add_child(_mouseless(W.ellipsis(W.label(str(s["title"])))))
		var mark := _mouseless(W.label("", &"MutedLabel"))
		line.add_child(mark)
		_marks.append({"keys": s["keys"], "label": mark, "bar": null, "show": true, "year": 0})
		tab.add_library_row(b, {"kind": "dir", "path": str(s["path"]), "text": str(s["title"])})
	_files(data["episodes"])


func _draw_season(data: Dictionary) -> void:
	tab.set_library_title("%s, %s" % [data["show"], data["title"]])
	_files(data["episodes"])


func _draw_film(f: Dictionary) -> void:
	var facts: PackedStringArray = []
	if int(f["year"]) > 0:
		facts.append(str(f["year"]))
	if int(f["runtime"]) > 0:
		facts.append("%d min" % int(f["runtime"]))
	for g: String in (f["genre"] as Array).slice(0, 2):
		facts.append(g)
	if tab.view != "list":
		_hero(str(f["title"]), "  ".join(facts).to_upper(), str(f["plot"]), str(f["poster"]), str(f["fanart"]))
	var b := _row(SEASON_ROW)
	var line := W.hbox()
	_fill(b, line)
	line.add_child(_mouseless(W.ellipsis(W.label("Play"))))
	var mark := _mouseless(W.label("", &"MutedLabel"))
	line.add_child(mark)
	_marks.append({"keys": f["keys"], "label": mark, "bar": null, "show": false, "year": 0, "runtime": f["runtime"]})
	tab.add_library_row(b, {"kind": "file", "path": str(f["video"]), "text": "Play"})


## Thumbnail, S01E01, title and on the right how far it was watched; the short plot under them. The list view: the
## number, the title and the mark on one short row. The grid view: a tile in `flow`, the thumbnail over the title.
func _episode_row(e: Dictionary, flow: Control = null) -> void:
	var title := str(e["title"]) if str(e["title"]) != "" else str(e["path"]).get_file()
	if tab.view == "list":
		var short := _row(SEASON_ROW)
		var line := W.hbox()
		_fill(short, line)
		if str(e["label"]) != "":
			line.add_child(_mouseless(W.label(str(e["label"]), &"ChipLabel")))
		var short_title := _mouseless(W.ellipsis(W.label(title)))
		line.add_child(short_title)
		var short_mark := _mouseless(W.label("", &"MutedLabel"))
		line.add_child(short_mark)
		_marks.append({"keys": [e["key"]], "label": short_mark, "bar": null, "show": false, "year": 0, "runtime": e["runtime"]})
		tab.add_library_row(short, {"kind": "file", "path": str(e["path"]), "text": title, "title_label": short_title})
		return
	if tab.view == "grid" and flow != null:
		var tile := _row(TILE_THUMB.y + CARD_TEXT)
		tile.size_flags_horizontal = Control.SIZE_FILL
		tile.custom_minimum_size.x = TILE_THUMB.x
		tile.add_child(_picture(str(e["thumb"]), THUMB, Rect2(Vector2.ZERO, TILE_THUMB), ""))
		var tile_bar := _bar(tile, Rect2(0, TILE_THUMB.y - 3, TILE_THUMB.x, 3))
		var head := W.hbox()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.set_position(Vector2(4, TILE_THUMB.y + 2))
		head.size = Vector2(TILE_THUMB.x - 8, 20)
		tile.add_child(head)
		if str(e["label"]) != "":
			head.add_child(_mouseless(W.label(str(e["label"]), &"ChipLabel")))
		var tile_title := _mouseless(W.ellipsis(W.label(title)))
		head.add_child(tile_title)
		var tile_mark := _mouseless(W.label("", &"MutedLabel"))
		tile_mark.set_position(Vector2(4, TILE_THUMB.y + 22))
		tile.add_child(tile_mark)
		_marks.append({"keys": [e["key"]], "label": tile_mark, "bar": tile_bar, "show": false, "year": 0, "runtime": e["runtime"]})
		tab.add_library_row(tile, {"kind": "file", "path": str(e["path"]), "text": title, "title_label": tile_title}, flow)
		return
	var b := _row(EPISODE_ROW)
	var pad := Vector2(PaneStyle.constant(&"gap"), (EPISODE_ROW - THUMB.y) / 2)
	b.add_child(_picture(str(e["thumb"]), THUMB, Rect2(pad, THUMB), ""))
	var bar := _bar(b, Rect2(pad.x, pad.y + THUMB.y - 3, THUMB.x, 3))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = pad.x * 2 + THUMB.x
	box.offset_right = -pad.x
	box.offset_top = 6
	b.add_child(box)
	var head := W.hbox()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	if str(e["label"]) != "":
		head.add_child(_mouseless(W.label(str(e["label"]), &"ChipLabel")))
	var title_label := _mouseless(W.ellipsis(W.label(title)))
	head.add_child(title_label)
	var mark := _mouseless(W.label("", &"MutedLabel"))
	head.add_child(mark)
	if str(e["plot"]) != "":
		box.add_child(_plot(str(e["plot"]), ROW_PLOT_LINES))
	_marks.append({"keys": [e["key"]], "label": mark, "bar": bar, "show": false, "year": 0, "runtime": e["runtime"]})
	tab.add_library_row(b, {"kind": "file", "path": str(e["path"]), "text": title, "title_label": title_label})


## A plot, wrapped, the last line it has room for ending in dots if there is more.
func _plot(text: String, lines: int) -> Label:
	var l := W.label(text, &"MutedLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = lines
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _row(height: int) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true
	return b


func _fill(b: Button, c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 12
	c.offset_right = -12
	b.add_child(c)


func _mouseless(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A picture's place: a quiet block at once (with the name when there is no picture at all), the picture when it comes.
func _picture(path: String, cached_size: Vector2i, at: Rect2, name_on_it: String) -> Control:
	var back := ColorRect.new()
	back.color = PaneStyle.color(&"field")
	back.position = at.position
	back.size = at.size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(tex)
	if path == "" and name_on_it != "":
		var l := _plot(name_on_it, HERO_PLOT_LINES)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(l)
	images.request(path, cached_size, func(t: Texture2D) -> void:
		if is_instance_valid(tex):
			tex.texture = t)
	return back


## How far along: a thin line in the accent colour, over its track.
func _bar(parent: Control, at: Rect2) -> Control:
	var track := ColorRect.new()
	track.color = PaneStyle.color(&"seek_track")
	track.position = at.position
	track.size = at.size
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.visible = false
	var done := ColorRect.new()
	done.color = PaneStyle.color(&"seek_played")
	done.size = Vector2(0, at.size.y)
	done.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(done)
	parent.add_child(track)
	return track


## The marks from the resume data: dictionary lookups, no file is read. Safe to call whenever that data changes.
func update_marks() -> void:
	var resume: Object = tab.resume_data()
	if resume == null:
		return
	for m: Dictionary in _marks:
		var label: Label = m["label"]
		if not is_instance_valid(label):
			continue
		var keys: Array = m["keys"]
		var seen := 0
		var progress := 0.0
		var position := 0.0
		for k: String in keys:
			var e: Dictionary = resume.entry_by_key(k)
			if bool(e.get("finished", false)):
				seen += 1
			elif float(e.get("position", 0.0)) > 0.0:
				progress = float(e.get("progress", 0.0))
				position = float(e["position"])
		var total := keys.size()
		var text := str(m.get("year", 0)) if int(m.get("year", 0)) > 0 else ""
		var words := ""
		if bool(m.get("show", false)):
			if seen >= total and total > 0:
				words = "Watched"
			elif seen > 0:
				words = "%d of %d" % [seen, total]
			elif text == "" and total > 0:
				words = "%d episode%s" % [total, "" if total == 1 else "s"]
		elif seen > 0:
			words = "Watched"
		elif position > 0.0:
			words = "%s ▶" % W.short_clock(position)
		elif int(m.get("runtime", 0)) > 0:
			words = "%d min" % int(m["runtime"])
		label.text = "  ".join(PackedStringArray([text, words])).strip_edges() if text != "" else words
		label.theme_type_variation = &"AccentLabel" if seen > 0 or position > 0.0 else label.theme_type_variation
		var bar: Control = m["bar"]
		if bar != null and is_instance_valid(bar):
			bar.visible = seen == 0 and position > 0.0
			(bar.get_child(0) as Control).size.x = bar.size.x * progress
