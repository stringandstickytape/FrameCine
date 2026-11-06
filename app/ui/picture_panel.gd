extends VBoxContainer

## Objects → Pictures (scripts/pictures/picture_library.gd; docs/features.md "Pictures", docs/USAGE.md "The Objects
## tab"): Find pictures (the on-pane keyboard's form, as Fab's search) opens Google Images in the browser on the big
## screen, where the viewer browses themselves and keeps what they like (the right stick click on an image, Copy
## image, a save to Downloads: picture_keeper.gd). Here: the kept pictures as tiles (filling the card as the object
## tiles do: object_section.gd _size_tile()), a pick's line, Place as a poster, framed, a canvas or a cut-out (each
## made to the picture's shape, picture_objects.gd, then Place with the laser), Apply to a part (the laser puts it on
## a wall, a seat, an object's part: ui/object_placer.gd) and Delete (asked first).
##
## Languages (docs/i18n.md): the pictures' titles are content (the pages' own words); the rest tr().

const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const SearchForm := preload("res://ui/search_form.gd")
const PictureLibrary := preload("res://scripts/pictures/picture_library.gd")
const PictureObjects := preload("res://scripts/pictures/picture_objects.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")

const COLUMNS := 4
const TILE_MIN := 88
const CARD_TEXT := 26

## scripts/main.gd
var app: Node
## The tab's box (object_section.gd): the search form takes its place while it shows.
var box: VBoxContainer
## (tile: Button) -> void: the object tiles' sizing (object_section.gd _size_tile()).
var size_tile: Callable
## (object id) -> void: an object made from a picture (the tab picks it).
var on_made: Callable

var _grid: GridContainer
var _group := ButtonGroup.new()
var _empty: Label
var _picked_label: Label
var _actions: VBoxContainer
var _form: SearchForm
var _ids: Array = []
var _picked := ""
var _query := ""


func bind(p_app: Node, p_box: VBoxContainer) -> void:
	app = p_app
	box = p_box
	add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	add_child(W.flow([W.button("Find pictures", _ask_search)]))
	var how := W.help("Browse yourself. On an image, the right stick click keeps it; Copy image and saving to "
			+ "Downloads keep it too.")
	add_child(how)
	_empty = W.label("None yet.", &"MutedLabel")
	add_child(_empty)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	_grid.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_grid)
	_picked_label = W.ellipsis(W.label("", &"MutedLabel"))
	W.content(_picked_label)
	_picked_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_picked_label)
	_actions = W.vbox()
	_actions.add_child(W.flow([W.label("Place as:", &"MutedLabel"),
			W.button("Poster", func() -> void: _place("poster")),
			W.button("Framed", func() -> void: _place("framed")),
			W.button("Canvas", func() -> void: _place("canvas")),
			W.button("Cut-out", func() -> void: _place("cutout"))]))
	_actions.add_child(W.flow([W.button("Apply to a part", _apply), W.button("Delete", _ask_delete)]))
	add_child(_actions)
	var own := W.help("Kept pictures stay on this headset, for your own use: the app never uploads or shares them.")
	add_child(own)
	_form = SearchForm.new()
	_form.set_texts("Find pictures", "Search", "words to search for, such as autumn forest") # i18n
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
	sync()


## The library again (the tab's sync(), after a keep, a delete, a language change).
func sync() -> void:
	if app == null:
		return
	var list := PictureLibrary.list()
	var ids: Array = list.map(func(p: Dictionary) -> String: return str(p["id"]))
	if ids != _ids:
		_ids = ids
		for c in _grid.get_children():
			_grid.remove_child(c)
			c.queue_free()
		for p: Dictionary in list:
			_tile(p)
	if not (_picked in _ids):
		_picked = ""
	for c in _grid.get_children():
		(c as Button).set_pressed_no_signal(str(c.get_meta("picture", "")) == _picked)
	_empty.visible = _ids.is_empty()
	_grid.visible = not _ids.is_empty()
	var p := PictureLibrary.get_picture(_picked) if _picked != "" else {}
	_picked_label.visible = not _ids.is_empty()
	_picked_label.text = "%s  ·  %d × %d" % [p["title"], int(p["width"]), int(p["height"])] if not p.is_empty() \
			else tr("Pick a picture, then place it or apply it.")
	_actions.visible = not p.is_empty()


func _tile(p: Dictionary) -> void:
	var id := str(p["id"])
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.toggle_mode = true
	b.button_group = _group
	W.content(b)
	var img := PictureLibrary.thumbnail(id)
	if img != null:
		var art := TextureRect.new()
		art.texture = ImageTexture.create_from_image(img)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.name = "Art"
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
	# The page's own words: content.
	var title := W.ellipsis(W.label(str(p["title"])))
	W.content(title)
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(title)
	b.set_meta("picture", id)
	b.pressed.connect(func() -> void:
		_picked = id
		sync())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(TILE_MIN, TILE_MIN + CARD_TEXT)
	if size_tile.is_valid():
		b.resized.connect(size_tile.bind(b))
	_grid.add_child(b)


# --- Find pictures -------------------------------------------------------------------------------------------------

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


## Google Images for the words, in the browser on the big screen: the viewer browses it themselves.
func _search(q: String) -> void:
	_query = q.strip_edges()
	if _query == "":
		return
	PictureLibrary.open_search(PictureLibrary.search_url(_query))
	app.ui.notify(tr("On an image, the right stick click keeps it."))


# --- Place, apply, delete --------------------------------------------------------------------------------------------

## The picture as an object of that kind (made once), then Place with the laser.
func _place(kind: String) -> void:
	if _picked == "":
		return
	var r := PictureObjects.object_for(_picked, kind)
	if not bool(r.get("ok", false)):
		app.ui.notify(str(r.get("error", tr("That didn't work."))))
		return
	if on_made.is_valid():
		on_made.call(str(r["id"]))
	app.ui.start_object_place(str(r["id"]))


func _apply() -> void:
	if _picked != "":
		app.ui.start_part_apply({"picture": _picked})


func _ask_delete() -> void:
	var id := _picked
	var p := PictureLibrary.get_picture(id)
	if p.is_empty():
		return
	app.ui.ui.show_choice(tr("Delete %s from your pictures?") % p["title"], tr("Delete"), func() -> void:
		var r := PictureLibrary.delete(id)
		app.ui.ui.hide_toast()
		if not bool(r.get("ok", false)):
			app.ui.notify(tr("%s is in %s: remove it there first.") % [p["title"], ", ".join(r.get("rooms", []))]
					if r.has("rooms") else str(r.get("error", "")))
		_picked = ""
		var oc := load("res://scripts/assistant/object_commands.gd") as GDScript
		oc.call("_sync_tab"), tr("Keep"), func() -> void: app.ui.ui.hide_toast(), 15.0)
