extends VBoxContainer

## Objects → Surfaces (scripts/env/surface_store.gd, material_library.gd; docs/features.md "Surfaces", docs/USAGE.md
## "The Objects tab"): one search over Megascans (through Fab, behind its licence), Poly Haven and ambientCG, each
## result with its source's badge and the sources' credit line under them ("Powered by Poly Haven"); Import into
## your materials; and the materials, bundled and your own, to pick one and Apply to a part (the laser puts it on a
## wall, the floor, a seat, an object's part; the stick sizes and turns its pattern: ui/object_placer.gd).
##
## Languages (docs/i18n.md): the sources' titles and the materials' names are content (English, as given); the
## lines are tr(); the sources' credits are their own words (content).

const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const SearchForm := preload("res://ui/search_form.gd")
const SurfaceStore := preload("res://scripts/env/surface_store.gd")
const SurfaceImport := preload("res://scripts/env/surface_import.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

const COLUMNS := 4
const TILE_MIN := 88
const CARD_TEXT := 26
const MATERIAL_COLUMNS := 3
const MATERIAL_SWATCH := 22
const MB := 1024.0 * 1024.0
## The materials list: all of them, or only your own.
const SHOW_NAMES := ["All", "Yours"] # i18n

var app: Node
var box: VBoxContainer
var size_tile: Callable
var store: Node

var _query_label: Label
var _status: Label
var _grid: GridContainer
var _group := ButtonGroup.new()
var _credits: Label
var _more: Button
var _picked_label: Label
var _import: Button
var _progress: Label
var _materials: GridContainer
var _material_group := ButtonGroup.new()
var _material_label: Label
var _apply: Button
var _delete: Button
var _form: SearchForm
var _show_yours := false

var _query := ""
var _next := ""
var _results: Array = []
var _credit_lines: Array = []
var _errors := {}
var _picked := -1
var _searching := false
var _error := {}
var _gen := 0
var _thumbs_running := false
var _material := ""
var _material_ids: Array = []
var _job_state := ""


func bind(p_app: Node, p_box: VBoxContainer) -> void:
	app = p_app
	box = p_box
	store = SurfaceStore.ensure(app.get_tree())
	add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	add_child(W.flow([W.button("Find surfaces", _ask_search)]))
	_query_label = W.ellipsis(W.label("", &"MutedLabel"))
	W.content(_query_label)
	add_child(_query_label)
	_status = W.label("", &"MutedLabel")
	W.content(_status)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	_grid.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_grid)
	# Where the results come from, beside them (Poly Haven's terms ask for it; no endorsement is claimed).
	_credits = W.label("", &"MutedLabel")
	W.content(_credits)
	_credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_credits)
	_more = W.button("More", func() -> void: _fetch(_next))
	add_child(W.flow([_more]))
	_picked_label = W.ellipsis(W.label(""))
	W.content(_picked_label)
	_picked_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_import = W.button("Import", _start_import)
	add_child(W.hbox([_picked_label, _import]))
	_progress = W.label("", &"MutedLabel")
	W.content(_progress)
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_progress)

	var kinds := W.choices(SHOW_NAMES, func(i: int) -> void:
		_show_yours = i == 1
		_sync_materials())
	W.set_choice(kinds, 0)
	add_child(kinds)
	_materials = GridContainer.new()
	_materials.columns = MATERIAL_COLUMNS
	_materials.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	_materials.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	_materials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_materials)
	_material_label = W.ellipsis(W.label("", &"MutedLabel"))
	W.content(_material_label)
	add_child(_material_label)
	_apply = W.button("Apply to a part", func() -> void:
		if _material != "":
			app.ui.start_part_apply({"material": _material}))
	_delete = W.button("Delete", _ask_delete)
	add_child(W.flow([_apply, _delete]))
	add_child(W.help("Apply: point at a wall, the floor, a seat or an object's part; the trigger puts it there. "
			+ "Stick: size and turn the pattern."))

	_form = SearchForm.new()
	_form.set_texts("Find surfaces", "Search", "words in English, such as brick or oak floor") # i18n
	_form.visible = false
	_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_form.search_requested.connect(func(q: String) -> void:
		_hide_form()
		_search(q))
	_form.cancelled.connect(_hide_form)
	add_child(_form)
	box.visibility_changed.connect(func() -> void:
		if not box.is_visible_in_tree() and _form.visible:
			_hide_form())
	store.changed.connect(_on_changed)
	set_process(false)
	sync()


func sync() -> void:
	if store == null:
		return
	var active: bool = store.job_active()
	set_process(active)
	_query_label.text = (tr("Results for “%s”") % _query) if _query != "" \
			else tr("Search for a surface by its name, in English.")
	var line := ""
	if _searching:
		line = tr("Searching...")
	elif not _error.is_empty():
		line = _error_text(_error)
	elif _query != "" and _results.is_empty():
		line = tr("Nothing found. Try other words, in English.")
	if not _errors.is_empty() and line == "":
		var parts: Array = []
		for s: String in _errors:
			parts.append(_source_name(s) + ": " + _error_text(_errors[s]))
		line = "\n".join(parts)
	_status.text = line
	_status.visible = line != ""
	_grid.visible = _grid.get_child_count() > 0
	_credits.text = "  ·  ".join(_credit_lines)
	_credits.visible = _grid.visible and not _credit_lines.is_empty()
	_more.get_parent().visible = _next != "" and not _searching
	var e: Dictionary = _results[_picked] if _picked >= 0 and _picked < _results.size() else {}
	var job: Dictionary = store.job_state()
	var said := ""
	_picked_label.get_parent().visible = not _results.is_empty() or active
	if active:
		_picked_label.text = str(job.get("title", ""))
		said = _job_text(job)
	elif not e.is_empty():
		_picked_label.text = "%s  ·  %s" % [e["title"], _source_name(str(e["source"]))]
		if str(e.get("in_library", "")) != "":
			said = tr("It is in your materials already.")
		elif str(job.get("id", "")) == str(e["id"]):
			said = _job_text(job)
	else:
		_picked_label.text = tr("Pick one, then Import.")
	_import.disabled = active or e.is_empty() or str(e.get("in_library", "")) != "" \
			or not bool(e.get("importable", true))
	_progress.text = said
	_progress.visible = said != ""
	_sync_materials()
	if is_visible_in_tree() and not _thumbs_running and _grid.get_child_count() > 0:
		_load_thumbs()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		sync()


func _on_changed() -> void:
	var job: Dictionary = store.job_state()
	var state := str(job.get("state", ""))
	if state != _job_state:
		_job_state = state
		if state in ["done", "already"]:
			var id := str(job.get("material", {}).get("id", ""))
			for r: Dictionary in _results:
				if str(r["id"]) == str(job.get("id", "")):
					r["in_library"] = id
			if id != "":
				_material = id
	sync()


static func _source_name(s: String) -> String:
	return str(SurfaceImport.SITES.get(s, {}).get("name", s))


# --- Search ----------------------------------------------------------------------------------------------------------

func _ask_search() -> void:
	W.show_form(box, _form, true)
	var sc: Node = box.get_parent()
	if sc is ScrollContainer:
		(sc as ScrollContainer).scroll_vertical = 0
	_form.edit(_query)
	(app.ui.ui as Node).call("set_form_mode", true)


func _hide_form() -> void:
	W.show_form(box, _form, false)
	(app.ui.ui as Node).call("set_form_mode", false)
	sync()


func _search(q: String) -> void:
	_clear_results()
	_query = q.strip_edges()
	await _fetch("")


func _fetch(cursor: String) -> void:
	if _searching or _query == "":
		return
	_searching = true
	_error = {}
	sync()
	var gen := _gen
	var r: Dictionary = await store.search(_query, "", cursor)
	if not is_instance_valid(self) or gen != _gen:
		return
	_searching = false
	if not bool(r.get("ok", false)):
		_error = r
		sync()
		return
	_next = str(r["next"])
	_errors = r["errors"]
	for c: String in r["credits"]:
		if not (c in _credit_lines):
			_credit_lines.append(c)
	for e: Dictionary in r["results"]:
		_results.append(e)
		_add_tile(e, _results.size() - 1)
	sync()
	_load_thumbs()


func _clear_results() -> void:
	_gen += 1
	_results.clear()
	_credit_lines.clear()
	_errors = {}
	_next = ""
	_picked = -1
	_error = {}
	_searching = false
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()


## A result's tile: its thumbnail (when it comes), its title and its source's badge.
func _add_tile(e: Dictionary, index: int) -> void:
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.toggle_mode = true
	b.button_group = _group
	W.content(b)
	b.tooltip_text = _source_name(str(e["source"]))
	var title := W.ellipsis(W.label(str(e["title"])))
	W.content(title)
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(title)
	var badge := W.label(str(SurfaceStore.BADGES.get(str(e["source"]), "?")), &"MutedLabel")
	W.content(badge)
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(4, 2)
	b.add_child(badge)
	b.set_meta("result", index)
	b.pressed.connect(func() -> void:
		_picked = index
		sync())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(TILE_MIN, TILE_MIN + CARD_TEXT)
	if size_tile.is_valid():
		b.resized.connect(size_tile.bind(b))
	_grid.add_child(b)


func _load_thumbs() -> void:
	if _thumbs_running:
		return
	_thumbs_running = true
	var gen := _gen
	while gen == _gen and is_visible_in_tree():
		var next: Button = null
		for c in _grid.get_children():
			if not c.has_node("Art") and not c.has_meta("thumb_tried"):
				next = c
				break
		if next == null:
			break
		next.set_meta("thumb_tried", true)
		var e: Dictionary = _results[int(next.get_meta("result"))]
		var img: Image = await store.thumbnail(e)
		if not is_instance_valid(self) or not is_instance_valid(next) or gen != _gen:
			break
		if img == null:
			continue
		var art := TextureRect.new()
		art.texture = ImageTexture.create_from_image(img)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.name = "Art"
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		next.add_child(art)
		next.move_child(art, 0)
		if size_tile.is_valid():
			size_tile.call(next)
	if is_instance_valid(self):
		_thumbs_running = false


# --- Import ----------------------------------------------------------------------------------------------------------

func _start_import() -> void:
	if _picked < 0 or _picked >= _results.size():
		return
	var e: Dictionary = _results[_picked]
	var r: Dictionary = store.start_import(str(e["source"]), str(e["id"]))
	if not bool(r.get("ok", false)):
		_error = r
	elif r.get("state") == "already":
		e["in_library"] = str(r["material"]["id"])
		_material = str(r["material"]["id"])
	sync()


func _job_text(job: Dictionary) -> String:
	var title := str(job.get("title", ""))
	match str(job.get("state", "")):
		"files":
			return tr("Asking for %s...") % title
		"download":
			var total := int(job.get("total", -1))
			if total > 0:
				return tr("Downloading %s: %.1f of %.1f MB") % [title, int(job["bytes"]) / MB, total / MB]
			return tr("Downloading %s: %.1f MB") % [title, int(job["bytes"]) / MB]
		"import":
			return tr("Adding %s: a moment.") % title
		"done":
			return tr("%s is in your materials.") % str(job.get("material", {}).get("name", title))
		"already":
			return tr("It is in your materials already.")
		"cancelled":
			return tr("Cancelled.")
		"failed":
			return _error_text({"error": job.get("error", ""), "message": job.get("message", "")})
	return ""


func _error_text(r: Dictionary) -> String:
	match str(r.get("error", "")):
		"eula":
			return tr("Accept Fab's licence in Your objects first.")
		"backoff":
			return tr("The site is busy: the app waits %d s before it asks again.") % int(r.get("wait", 0))
		"network":
			return tr("The site can't be reached. Is the headset online?")
		"http":
			return tr("The site answered with an error (HTTP %d). Try again later.") % int(r.get("http", 0))
		"shape":
			return tr("The site's answer was not as expected. Try again later.")
		"no_file":
			return tr("This surface has no download the app can use.")
		"too_big":
			return tr("This surface's download is too big for the headset.")
		"busy":
			return tr("A download is under way.")
		"import":
			return tr("The import failed: %s") % r.get("message", "")
		"query":
			return tr("Search for a surface by its name, in English.")
	return str(r.get("message", ""))


# --- The materials ---------------------------------------------------------------------------------------------------

## The materials (bundled and the user's), each a button with its swatch and name; the picked one is pressed.
func _sync_materials() -> void:
	var list := MaterialLibrary.list().filter(func(m: Dictionary) -> bool:
		return not _show_yours or bool(m.get("user", false)))
	var ids: Array = list.map(func(m: Dictionary) -> String: return str(m["id"]))
	if ids != _material_ids:
		_material_ids = ids
		for c in _materials.get_children():
			_materials.remove_child(c)
			c.queue_free()
		for m: Dictionary in list:
			var id := str(m["id"])
			var b := W.button(str(m.get("name", id)), func() -> void:
				_material = id
				_sync_materials(), &"RowButton")
			W.content(b)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.button_group = _material_group
			b.icon = _swatch(str(m.get("swatch", "#808080")))
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.tooltip_text = "%s · %s" % [id, _source_name(str(m.get("source", "bundled")))] if bool(m.get("user",
					false)) else id
			b.set_meta("material", id)
			_materials.add_child(b)
	if not MaterialLibrary.has(_material):
		_material = ""
	for c in _materials.get_children():
		(c as Button).set_pressed_no_signal(str(c.get_meta("material", "")) == _material)
	var e := MaterialLibrary.entry(_material) if _material != "" else {}
	if e.is_empty():
		_material_label.text = tr("Pick a material, then Apply to a part.")
	elif bool(e.get("user", false)):
		_material_label.text = "%s  ·  %s  ·  %s" % [e.get("name", _material), _source_name(str(e["source"].get("site",
				""))), tr("%.1f m a repeat") % float(e.get("tiling", 1.0))]
	else:
		_material_label.text = "%s  ·  %s" % [e.get("name", _material), tr("%.1f m a repeat") % float(e.get("tiling",
				1.0))]
	_apply.disabled = e.is_empty()
	_delete.visible = bool(e.get("user", false))
	_materials.visible = _materials.get_child_count() > 0


static var _swatches := {}


static func _swatch(hex: String) -> Texture2D:
	if not _swatches.has(hex):
		var img := Image.create_empty(MATERIAL_SWATCH, MATERIAL_SWATCH, false, Image.FORMAT_RGBA8)
		img.fill(RoomSchema.to_color(hex))
		_swatches[hex] = ImageTexture.create_from_image(img)
	return _swatches[hex]


func _ask_delete() -> void:
	var id := _material
	var e := MaterialLibrary.entry(id)
	if not bool(e.get("user", false)):
		return
	app.ui.ui.show_choice(tr("Delete %s from your materials?") % e.get("name", id), tr("Delete"), func() -> void:
		SurfaceImport.delete(id)
		SurfaceImport.loaded()
		_material = ""
		for r: Dictionary in _results:
			if str(r.get("in_library", "")) == id:
				r["in_library"] = ""
		app.ui.ui.hide_toast()
		sync(), tr("Keep"), func() -> void: app.ui.ui.hide_toast(), 15.0)
