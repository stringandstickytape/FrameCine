extends VBoxContainer

## The Room tab's objects (ui/room_tab.gd; docs/assistant.md "Objects", docs/USAGE.md "Room"): the object library as
## thumbnails with names, built in and imported; Place, which hands the laser to ui/object_placer.gd; Delete for an
## imported one (asked first, in the footer, as the panel's other choices are). Under them, what this room has from the
## library: pick one for its parts, each with its colour, a palette, the picture on show as its picture, a library
## material when the app has a material library, and Reset; and Move and Remove (asked first). Everything here calls
## what the commands call (scripts/assistant/object_commands.gd), so a change has the same undo.

const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")

const COLUMNS := 4
## Pixels on the pane: the thumbnail, and the name under it.
const THUMB := Vector2i(120, 120)
const CARD_TEXT := 26
const SWATCH := Vector2(28, 28)
## The colours a part can take from the palette, as text (the panel's own colours are the theme's).
const PALETTE := ["#f4f1ea", "#c8a27a", "#8b5a3c", "#3b2a1e", "#222222", "#7d7d7d", "#b5653d", "#c0392b",
		"#e8a33c", "#4f8a3c", "#2f6f8f", "#3366cc", "#6b4c9a", "#d98cb3"]
const ASSISTANT_ROOM := "res://scripts/assistant/assistant_room.gd"

## scripts/main.gd
var app: Node
var _grid: GridContainer
var _tiles := {}
var _ids: Array = []
var _selected := ""
var _chosen: Label
var _place: Button
var _delete: Button
var _placed_box: VBoxContainer
var _placed_names: Array = []
var _picked := ""
var _parts_box: VBoxContainer
## The part whose palette is open, or "".
var _palette_for := ""
var _loading := false
var _empty: Label


func bind(p_app: Node) -> void:
	app = p_app
	add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	add_child(W.section("Objects"))
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	_grid.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	add_child(_grid)
	_chosen = W.ellipsis(W.label("", &"MutedLabel"))
	_place = W.button("Place", _start_place)
	_delete = W.button("Delete", _ask_delete)
	add_child(W.hbox([_chosen, _place, _delete]))
	add_child(W.help("Place: point at a wall or the floor, trigger to set it. Stick: turn and size. B cancels."))
	add_child(W.label("In this room", &"MutedLabel"))
	_empty = W.label("Nothing from the library yet.", &"MutedLabel")
	add_child(_empty)
	_placed_box = VBoxContainer.new()
	_placed_box.add_theme_constant_override("separation", 0)
	add_child(_placed_box)
	_parts_box = W.vbox()
	add_child(_parts_box)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			sync_objects())


## Reads the library and the room again (the tab's sync(), and after each change).
func sync_objects() -> void:
	if app == null:
		return
	if is_visible_in_tree():
		_sync_library()
	_sync_placed()


# --- The library -------------------------------------------------------------------------------------------------

## The catalogue on a worker thread (built-ins are made and every thumbnail drawn there), then the tiles.
func _sync_library() -> void:
	if _loading:
		return
	_loading = true
	var r: Dictionary = await WorkerTask.run(get_tree(), func() -> Variant:
		var list := ObjectLibrary.list()
		for m: Dictionary in list:
			ObjectLibrary.thumbnail(str(m["id"]))
		return list)
	_loading = false
	if not r["done"] or not is_instance_valid(self):
		return
	var list: Array = r["result"]
	var ids: Array = list.map(func(m: Dictionary) -> String: return str(m["id"]))
	if ids != _ids:
		_ids = ids
		_tiles.clear()
		for c in _grid.get_children():
			_grid.remove_child(c)
			c.queue_free()
		var group := ButtonGroup.new()
		for m: Dictionary in list:
			_tile(m, group)
	if not (_selected in _ids):
		_selected = ""
	for id: String in _tiles:
		(_tiles[id] as Button).set_pressed_no_signal(id == _selected)
	_sync_chosen()


## A thumbnail and its name; pressing it picks the object for Place.
func _tile(m: Dictionary, group: ButtonGroup) -> void:
	var id := str(m["id"])
	var b := Button.new()
	b.theme_type_variation = &"RowButton"
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(THUMB.x, THUMB.y + CARD_TEXT)
	var img := ObjectLibrary.thumbnail(id)
	if img != null:
		var art := TextureRect.new()
		art.texture = ImageTexture.create_from_image(img)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.position = Vector2.ZERO
		art.size = Vector2(THUMB)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
	var title := W.ellipsis(W.label(str(m["name"])))
	title.position = Vector2(4, THUMB.y + 2)
	title.size = Vector2(THUMB.x - 8, 20)
	title.custom_minimum_size = Vector2(THUMB.x - 8, 0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(title)
	b.pressed.connect(func() -> void:
		_selected = id
		_sync_chosen()
		_show_place())
	_grid.add_child(b)
	_tiles[id] = b


func _sync_chosen() -> void:
	var m := ObjectLibrary.get_object(_selected) if _selected != "" else {}
	if m.is_empty():
		_chosen.text = "Pick an object, then Place."
	else:
		var n := (m.get("parts", []) as Array).size()
		_chosen.text = "%s  ·  %s  ·  %d part%s%s" % [m["name"], m["mount"], n, "" if n == 1 else "s",
				"  ·  imported" if m["source"] == "user" else ""]
	_place.disabled = m.is_empty()
	_delete.visible = not m.is_empty() and m["source"] == "user"


## The panel scrolls so that Place shows: it sits under the grid, often below the visible part of the tab.
func _show_place() -> void:
	var p: Node = get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		(p as ScrollContainer).ensure_control_visible(_place)


func _start_place() -> void:
	if _selected == "":
		return
	app.ui.start_object_place(_selected)


## Delete asks first, in the footer.
func _ask_delete() -> void:
	var id := _selected
	var m := ObjectLibrary.get_object(id)
	if m.is_empty():
		return
	app.ui.ui.show_choice("Delete %s from the library? Copies in rooms stay." % m["name"], "Delete", func() -> void:
		ObjectLibrary.delete(id)
		ObjectLibrary.purge(id)
		_selected = ""
		sync_objects()
		app.ui.ui.hide_toast(), "Keep", func() -> void: app.ui.ui.hide_toast(), 15.0)


# --- What this room has --------------------------------------------------------------------------------------------

func _placed() -> Array:
	return (load(ASSISTANT_ROOM) as GDScript).call("placed_objects", app.env)


func _sync_placed() -> void:
	var placed := _placed()
	var names: Array = placed.map(func(p: Dictionary) -> String: return str(p["name"]))
	if not (_picked in names):
		_picked = ""
		_palette_for = ""
	if names != _placed_names:
		_placed_names = names
		for c in _placed_box.get_children():
			_placed_box.remove_child(c)
			c.queue_free()
		var group := ButtonGroup.new()
		for n: String in names:
			var b := W.button(n, Callable(), &"RowButton")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.button_group = group
			var name := n
			b.pressed.connect(func() -> void:
				_picked = name
				_palette_for = ""
				_sync_parts())
			_placed_box.add_child(b)
	for i in _placed_box.get_child_count():
		(_placed_box.get_child(i) as Button).set_pressed_no_signal(names[i] == _picked)
	_empty.visible = names.is_empty()
	_sync_parts()


## The picked object's parts: a swatch of each one's colour, Colour (the palette under it), Picture, Material, Reset;
## and Move and Remove.
func _sync_parts() -> void:
	for c in _parts_box.get_children():
		_parts_box.remove_child(c)
		c.queue_free()
	if _picked == "":
		return
	var entry := {}
	for p: Dictionary in _placed():
		if p["name"] == _picked:
			entry = p
	if entry.is_empty():
		return
	var name := _picked
	_parts_box.add_child(W.hbox([W.button("Move", func() -> void: app.ui.start_object_move(name)),
			W.button("Remove", func() -> void: _ask_remove(name))]))
	var materials := _materials()
	for part: Dictionary in entry["parts"]:
		var target := "%s/%s" % [name, part["name"]]
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = SWATCH
		swatch.color = RoomSchema.to_color(str(part["color"]) if str(part["color"]) != "" else "#7d7d7d")
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := W.ellipsis(W.label(str(part["name"]) + ("  (changed)" if part.get("recolour") != null else "")))
		var row: Array = [swatch, label, W.button("Colour", func() -> void:
			_palette_for = target if _palette_for != target else ""
			_sync_parts())]
		row.append(W.button("Picture", func() -> void: _picture(target)))
		if not materials.is_empty():
			row.append(W.button("Material", func() -> void:
				_palette_for = "material:" + target if _palette_for != "material:" + target else ""
				_sync_parts()))
		var reset := W.button("Reset", func() -> void: _apply(target, null))
		reset.disabled = part.get("recolour") == null
		row.append(reset)
		_parts_box.add_child(W.hbox(row))
		if _palette_for == target:
			_parts_box.add_child(_palette(target))
		elif _palette_for == "material:" + target:
			var buttons: Array = []
			for mat: Dictionary in materials:
				var id := str(mat.get("id", ""))
				buttons.append(W.button(str(mat.get("name", id)), func() -> void: _apply(target, {"library_material": id})))
			_parts_box.add_child(W.hbox(buttons))


## A row of colour buttons: each a swatch on a button, so the stick's focus and the trigger reach it.
func _palette(target: String) -> Control:
	var grid := GridContainer.new()
	grid.columns = PALETTE.size() / 2
	grid.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	grid.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	for hex: String in PALETTE:
		var b := W.button("", func() -> void: _apply(target, {"color": hex}))
		b.custom_minimum_size = Vector2(PaneStyle.constant(&"button_height"), PaneStyle.constant(&"button_height"))
		b.tooltip_text = hex
		var dot := ColorRect.new()
		dot.color = RoomSchema.to_color(hex)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		b.add_child(dot)
		grid.add_child(b)
	return grid


## The material library's materials ({id, name}) when the app has one (assistant_room.gd MATERIAL_LIBRARY), else [].
static func _materials() -> Array:
	var path: String = (load(ASSISTANT_ROOM) as GDScript).get_script_constant_map().get("MATERIAL_LIBRARY", "")
	if path == "" or not ResourceLoader.exists(path):
		return []
	var s := load(path) as GDScript
	if s == null or not s.get_script_method_list().any(func(f: Dictionary) -> bool: return f["name"] == "list"):
		return []
	var list: Variant = s.call("list")
	return list if list is Array else []


## The picture on show (a picture file on the headset) as the part's picture.
func _picture(target: String) -> void:
	var path := str(app.current_path)
	if not bool(app.features.slideshow.is_picture()) or path.contains("://") or not FileAccess.file_exists(path):
		app.ui.notify("Open a picture on the headset first (Files); then Picture puts it on the part.")
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > int(RoomSchema.LIMITS["image_bytes"]):
		app.ui.notify("That picture is too big for a part (at most %d MB)." % (int(RoomSchema.LIMITS["image_bytes"])
				/ (1024 * 1024)))
		return
	_apply(target, {"texture": Marshalls.raw_to_base64(bytes)})


## A part's colour, picture or material (null: back to its own), with Undo in the footer.
func _apply(target: String, material: Variant) -> void:
	var r: Dictionary = await ObjectCommands.recolour_part(get_tree(), null, target, material)
	_palette_for = ""
	_toast(r, "%s: %s" % [target.get_slice("/", 1), "its own colour" if material == null else "changed"])
	sync_objects()


func _ask_remove(name: String) -> void:
	app.ui.ui.show_choice("Remove %s from the room?" % name, "Remove", func() -> void:
		app.ui.ui.hide_toast()
		var r: Dictionary = await ObjectCommands.remove_placed(get_tree(), null, name)
		_toast(r, "Removed %s" % name), "Keep", func() -> void: app.ui.ui.hide_toast(), 15.0)


func _toast(r: Dictionary, done: String) -> void:
	if r.get("ok") == true:
		app.ui.ui.show_toast(done, "Undo" if r.get("undo") is Callable else "", r.get("undo", Callable()), 8.0)
	else:
		app.ui.notify(str(r.get("error", "That didn't work.")))
