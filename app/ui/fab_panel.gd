extends VBoxContainer

## Objects → Your objects → Fab (scripts/assistant/fab_store.gd; docs/features.md "Fab in the app", docs/USAGE.md
## "The Objects tab"): Quixel Megascans' free 3D objects searched and imported from Fab, no browser.
##
## Until the viewer accepts Fab's licence: a short summary of it, Read Fab's licence (the full text in the headset's
## browser) and Accept. Only this Accept accepts it: no command can. Then: Search Fab (the on-pane keyboard's form,
## as the Sound tab's PC address), the results as thumbnails with names (filling the card as the object tiles do:
## object_section.gd _size_tile()), More for the next page (asked for only then), a pick's line with Import, and
## while it comes in its progress and Cancel. Errors and Fab's back-off say so in a line. Last, the day it was
## accepted, Clear Fab's cache and Withdraw.
##
## Languages (docs/i18n.md): Fab's titles, categories and tags are content (English, as Fab gives them); the lines
## are built with tr(); an error's English detail (an import's reason) shows as it is.

const W := preload("res://ui/pane_widgets.gd")
const FabStore := preload("res://scripts/assistant/fab_store.gd")
const SearchForm := preload("res://ui/search_form.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")

const COLUMNS := 4
## As object_section.gd's tiles: a tile's minimum width, and the name's line under the square.
const TILE_MIN := 88
const CARD_TEXT := 26
const MB := 1024.0 * 1024.0

## scripts/main.gd
var app: Node
## The tab's box (object_section.gd): the search form takes its place while it shows.
var box: VBoxContainer
## (tile: Button) -> void: the object tiles' sizing (object_section.gd _size_tile()).
var size_tile: Callable
## (object id) -> void: an import came in (the Objects tab picks it, ready to place).
var on_imported: Callable
var store: Node

var _licence: VBoxContainer
var _accepted: VBoxContainer
var _query_label: Label
var _status: Label
var _grid: GridContainer
var _group := ButtonGroup.new()
var _more: Button
var _picked_label: Label
var _import: Button
var _cancel: Button
var _progress: Label
var _accepted_label: Label
var _form: SearchForm

var _query := ""
var _next := ""
var _results: Array = []
var _picked := ""
var _searching := false
var _error := {}
## The import's error when Import was refused at once (another under way, ...).
var _import_error := {}
## Each new search: what an older one's awaits find stale.
var _gen := 0
var _thumbs_running := false
## Listing uid -> object id: the results in the library (worked out per search and after each import).
var _have := {}
var _job_state := ""


func bind(p_app: Node, p_box: VBoxContainer) -> void:
	app = p_app
	box = p_box
	store = FabStore.ensure(app.get_tree())
	add_theme_constant_override("separation", box.get_theme_constant("separation"))
	add_child(W.caps("Fab"))

	_licence = W.vbox()
	var summary := W.label("Search and import Quixel Megascans' free 3D objects from Fab here. Fab's licence (its "
			+ "EULA) covers what you download: you may use the objects; you may not pass the files on. Read it, then "
			+ "accept it to start.", &"MutedLabel")
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_licence.add_child(summary)
	_licence.add_child(W.flow([W.button("Read Fab's licence", _read_eula), W.button("Accept", _accept)]))
	add_child(_licence)

	_accepted = W.vbox()
	_accepted.add_child(W.flow([W.button("Search Fab", _ask_search)]))
	_query_label = W.ellipsis(W.label("", &"MutedLabel"))
	W.content(_query_label)
	_accepted.add_child(_query_label)
	_status = W.label("", &"MutedLabel")
	W.content(_status)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_accepted.add_child(_status)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", box.get_theme_constant("separation"))
	_grid.add_theme_constant_override("v_separation", box.get_theme_constant("separation"))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accepted.add_child(_grid)
	_more = W.button("More", func() -> void: _fetch(_next))
	_accepted.add_child(W.flow([_more]))
	_picked_label = W.ellipsis(W.label(""))
	W.content(_picked_label)
	_picked_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_import = W.button("Import", _start_import)
	_cancel = W.button("Cancel", func() -> void: store.cancel())
	_accepted.add_child(W.hbox([_picked_label, _import, _cancel]))
	_progress = W.label("", &"MutedLabel")
	W.content(_progress)
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_accepted.add_child(_progress)
	_accepted_label = W.label("", &"MutedLabel")
	W.content(_accepted_label)
	_accepted_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_accepted.add_child(_accepted_label)
	_accepted.add_child(W.flow([W.button("Read Fab's licence", _read_eula), W.button("Clear Fab's cache", _clear),
			W.button("Withdraw", _withdraw)]))
	add_child(_accepted)

	_form = SearchForm.new()
	# The form's title, button and hint translate themselves (keys).
	_form.set_texts("Search Fab's free Megascans", "Search", "words in English, such as rock or chair") # i18n
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


## The words and what shows, again (the tab's sync(), a language change, the store's changes).
func sync() -> void:
	if store == null:
		return
	var accepted: bool = store.eula_accepted()
	_licence.visible = not accepted
	_accepted.visible = accepted
	var active: bool = store.job_active()
	set_process(active or store.backoff_left() > 0.0)
	if not accepted:
		return
	_query_label.text = (tr("Results for “%s”") % _query) if _query != "" \
			else tr("Search for an object by its name, in English.")
	var line := ""
	if store.backoff_left() > 0.0:
		line = _error_text({"error": "backoff", "wait": ceili(store.backoff_left())})
	elif _searching:
		line = tr("Searching Fab...")
	elif not _error.is_empty():
		line = _error_text(_error)
	elif _query != "" and _results.is_empty():
		line = tr("Nothing found. Try other words, in English.")
	_status.text = line
	_status.visible = line != ""
	_grid.visible = _grid.get_child_count() > 0
	_more.get_parent().visible = _next != "" and not _searching
	var job: Dictionary = store.job_state()
	var e := _result(_picked)
	var said := ""
	if active:
		_picked_label.text = str(job["title"])
		said = _job_text(job)
	elif not e.is_empty():
		_picked_label.text = "%s  ·  %s" % [e["title"], e["category"]] if str(e["category"]) != "" else str(e["title"])
		if _have.has(_picked):
			said = tr("It is in your objects already.")
		elif not bool(e.get("importable", true)):
			said = _error_text({"error": "no_file"})
		elif not _import_error.is_empty():
			said = _error_text(_import_error)
		elif str(job.get("uid", "")) == _picked:
			said = _job_text(job)
	else:
		_picked_label.text = tr("Pick one, then Import.")
	_import.visible = not active
	_import.disabled = e.is_empty() or _have.has(_picked) or not bool(e.get("importable", true))
	_cancel.visible = active
	_progress.text = said
	_progress.visible = said != ""
	_accepted_label.text = tr("You accepted Fab's licence on %s.") % store.eula_date()
	# Thumbnails left when the tab was hidden or Fab was busy.
	if is_visible_in_tree() and not _thumbs_running and _grid.get_child_count() > 0 and store.backoff_left() <= 0.0:
		_load_thumbs()


## While an import is under way or Fab's back-off lasts: its progress and the seconds left.
func _process(_delta: float) -> void:
	if is_visible_in_tree():
		sync()


func _on_changed() -> void:
	var job: Dictionary = store.job_state()
	var state := str(job.get("state", ""))
	if state != _job_state:
		_job_state = state
		if state in ["done", "already"]:
			var id := str(job["object"].get("id", ""))
			_have[str(job["uid"])] = id
			if on_imported.is_valid() and id != "":
				on_imported.call(id)
	if not store.eula_accepted() and _query != "":
		_clear_results()
		_query = ""
	sync()


# --- Search --------------------------------------------------------------------------------------------------------

func _ask_search() -> void:
	W.show_form(box, _form, true)
	var p: Node = box.get_parent()
	if p is ScrollContainer:
		(p as ScrollContainer).scroll_vertical = 0
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


## A page of results (the first, or the one after `cursor`), its tiles added.
func _fetch(cursor: String) -> void:
	if _searching or _query == "":
		return
	_searching = true
	_error = {}
	sync()
	var gen := _gen
	var r: Dictionary = await store.search(_query, cursor)
	if not is_instance_valid(self) or gen != _gen:
		return
	_searching = false
	if not bool(r.get("ok", false)):
		_error = r
		sync()
		return
	_next = str(r["next"])
	for e: Dictionary in r["results"]:
		_results.append(e)
		if str(e.get("in_library", "")) != "":
			_have[str(e["uid"])] = str(e["in_library"])
		_add_tile(e)
	sync()
	_load_thumbs()


func _clear_results() -> void:
	_gen += 1
	_results.clear()
	_next = ""
	_picked = ""
	_error = {}
	_import_error = {}
	_searching = false
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()


func _result(uid: String) -> Dictionary:
	for e: Dictionary in _results:
		if e["uid"] == uid:
			return e
	return {}


## A result's tile: its thumbnail (when it comes) and its title; pressing it picks it for Import.
func _add_tile(e: Dictionary) -> void:
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.toggle_mode = true
	b.button_group = _group
	# Fab's title and category: content.
	W.content(b)
	b.tooltip_text = str(e["category"])
	var title := W.ellipsis(W.label(str(e["title"])))
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(title)
	b.set_meta("uid", str(e["uid"]))
	b.set_meta("thumb", str(e["thumb"]))
	var uid := str(e["uid"])
	b.pressed.connect(func() -> void:
		_picked = uid
		_import_error = {}
		sync())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(TILE_MIN, TILE_MIN + CARD_TEXT)
	if size_tile.is_valid():
		b.resized.connect(size_tile.bind(b))
	_grid.add_child(b)


## The tiles' thumbnails, one at a time in the store's turn (cached ones at once). Stops for a new search, a hidden
## tab or a back-off; _process() starts it again.
func _load_thumbs() -> void:
	if _thumbs_running:
		return
	_thumbs_running = true
	var gen := _gen
	while gen == _gen and is_visible_in_tree():
		var next: Button = null
		for c in _grid.get_children():
			if not c.has_node("Art") and str(c.get_meta("thumb", "")) != "" and not c.has_meta("thumb_tried"):
				next = c
				break
		if next == null:
			break
		var img: Image = await store.thumbnail(str(next.get_meta("thumb")))
		if not is_instance_valid(self) or not is_instance_valid(next) or gen != _gen:
			break
		if img == null:
			if store.backoff_left() > 0.0:
				break
			next.set_meta("thumb_tried", true)
			continue
		var art := TextureRect.new()
		art.texture = ImageTexture.create_from_image(img)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.name = "Art"
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		next.add_child(art)
		next.move_child(art, 0)
		if size_tile.is_valid():
			size_tile.call(next)
	if is_instance_valid(self):
		_thumbs_running = false


# --- Import --------------------------------------------------------------------------------------------------------

func _start_import() -> void:
	var e := _result(_picked)
	if e.is_empty():
		return
	var r: Dictionary = store.start_import(_picked, str(e["title"]))
	_import_error = {} if bool(r.get("ok", false)) else r
	if r.get("state") == "already":
		_have[_picked] = str(r["object"]["id"])
		if on_imported.is_valid():
			on_imported.call(str(r["object"]["id"]))
	sync()


func _job_text(job: Dictionary) -> String:
	var title := str(job.get("title", ""))
	match str(job.get("state", "")):
		"files", "link":
			return tr("Asking Fab for %s...") % title
		"download":
			var total := int(job.get("total", -1))
			if total > 0:
				return tr("Downloading %s: %.1f of %.1f MB") % [title, int(job["bytes"]) / MB, total / MB]
			return tr("Downloading %s: %.1f MB") % [title, int(job["bytes"]) / MB]
		"import":
			return tr("Adding %s: a moment.") % title
		"done":
			return tr("%s is in your objects.") % job["object"].get("name", title)
		"already":
			return tr("It is in your objects already.")
		"cancelled":
			return tr("Cancelled.")
		"failed":
			return _error_text({"error": job.get("error", ""), "message": job.get("message", "")})
	return ""


## What went wrong, in the menu's language (the store's codes); an import's own reason as it is (English).
func _error_text(r: Dictionary) -> String:
	match str(r.get("error", "")):
		"backoff":
			return tr("Fab is busy: the app waits %d s before it asks again.") % int(r.get("wait", 0))
		"network":
			return tr("Fab can't be reached. Is the headset online?")
		"http":
			return tr("Fab answered with an error (HTTP %d). Try again later.") % int(r.get("http", 0))
		"shape":
			return tr("Fab's answer was not as expected. Try again later.")
		"no_file":
			return tr("This object has no download the app can use.")
		"too_big":
			return tr("This object's download is too big for the headset.")
		"busy":
			return tr("A download is under way.")
		"import":
			return tr("The import failed: %s") % r.get("message", "")
		"cancelled":
			return tr("Cancelled.")
		"query":
			return tr("Search for an object by its name, in English.")
	return str(r.get("message", ""))


# --- The licence ---------------------------------------------------------------------------------------------------

## Fab's licence in full, in the Browser source: the panel goes so it shows.
func _read_eula() -> void:
	var url := WebPages.normalized(FabStore.EULA_URL)
	WebPages.set_last_url(url)
	app.ui.hide_panel()
	app.open_path("browser://" + url)


func _accept() -> void:
	store.accept_eula()
	app.ui.notify(tr("Fab's licence accepted. Search Fab to find objects."))
	sync()


func _withdraw() -> void:
	store.withdraw_eula()
	_clear_results()
	_query = ""
	app.ui.notify(tr("Fab's licence withdrawn: the app asks Fab nothing until you accept it again."))
	sync()


func _clear() -> void:
	store.clear_cache()
	app.ui.notify(tr("Fab's cache is cleared."))
