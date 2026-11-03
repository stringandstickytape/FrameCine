extends VBoxContainer

## The Objects tab (ui/objects_tab.gd; docs/assistant.md "Objects", docs/USAGE.md "Objects"): the object library as
## thumbnails with names, built in and imported; Place, which hands the laser to ui/object_placer.gd; Delete for an
## imported one (asked first, in the footer, as the panel's other choices are). Under them, what this room has from the
## library: pick one for its parts, each with its colour, a palette, the picture on show as its picture, a material
## from the material library (a picker: each material's swatch and name, filtered by kind), an effect from the effect
## library (a picker: each effect's preview and name, filtered by group, its options at their defaults), and Reset;
## and Move and Remove (asked first). Everything here calls what the commands call
## (scripts/assistant/object_commands.gd), so a change has the same undo, cost limits and checks.

const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")

const COLUMNS := 4
## Pixels on the pane: the thumbnail, and the name under it.
const THUMB := Vector2i(120, 120)
const CARD_TEXT := 26
const SWATCH := Vector2(28, 28)
## The colours a part can take from the palette, as text (the panel's own colours are the theme's).
const PALETTE := ["#f4f1ea", "#c8a27a", "#8b5a3c", "#3b2a1e", "#222222", "#7d7d7d", "#b5653d", "#c0392b",
		"#e8a33c", "#4f8a3c", "#2f6f8f", "#3366cc", "#6b4c9a", "#d98cb3"]
const ASSISTANT_ROOM := "res://scripts/assistant/assistant_room.gd"
## The material picker's kinds: [label, the library's tag ("" all)].
const MATERIAL_KINDS := [["All", ""], ["Floors", "floor"], ["Walls", "wall"], ["Fabric", "fabric"], ["Wood", "wood"],
		["Leather", "leather"], ["Metal", "metal"], ["Stone", "stone"]]
const MATERIAL_COLUMNS := 3
## The swatch on a material's button (its mean colour, from the catalogue: nothing is loaded to show it).
const MATERIAL_SWATCH := 22
## The effect picker's swatches: each effect's preview made small (tools/fx_swatches.gd), shipped with the app.
const EFFECT_SWATCHES := "res://textures/fx/swatches"
const EFFECT_SWATCH := 32

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
## The part whose palette is open, or "" ("material:<part>", "effect:<part>": its material or effect picker).
var _palette_for := ""
## The material picker's kind (a library tag, "" all).
var _material_tag := ""
## The effect picker's group ("" all).
var _effect_group := ""
static var _swatches := {}
static var _effect_swatches := {}
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


## The picked object's parts: a swatch of each one's colour, Colour (the palette under it), Picture, Material, Effect,
## Reset; and Move and Remove.
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
		var shows := str(part.get("material", ""))
		var effect := str(part.get("effect", ""))
		var label := W.ellipsis(W.label(str(part["name"]) + ("  ·  " + _material_name(shows) if shows != "" else "")
				+ ("  ·  " + _effect_name(effect) if effect != "" else "")
				+ ("  (changed)" if part.get("recolour") != null else "")))
		var row: Array = [swatch, label, W.button("Colour", func() -> void:
			_palette_for = target if _palette_for != target else ""
			_sync_parts())]
		row.append(W.button("Picture", func() -> void: _picture(target)))
		if not materials.is_empty():
			row.append(W.button("Material", func() -> void:
				_palette_for = "material:" + target if _palette_for != "material:" + target else ""
				_sync_parts()))
		row.append(W.button("Effect", func() -> void:
			_palette_for = "effect:" + target if _palette_for != "effect:" + target else ""
			_sync_parts()))
		var reset := W.button("Reset", func() -> void: _apply(target, null))
		reset.disabled = part.get("recolour") == null
		row.append(reset)
		_parts_box.add_child(W.hbox(row))
		if _palette_for == target:
			_parts_box.add_child(_palette(target))
		elif _palette_for == "material:" + target:
			_parts_box.add_child(_material_picker(target, shows, materials))
		elif _palette_for == "effect:" + target:
			_parts_box.add_child(_effect_picker(target, effect))


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


## The material library's materials ([{id, name, tags, swatch, ...}], by name; scripts/env/material_library.gd).
static func _materials() -> Array:
	return MaterialLibrary.list()


static func _material_name(id: String) -> String:
	return str(MaterialLibrary.entry(id).get("name", id))


## The material picker under a part: a row of kinds (All, Floors, Walls, Fabric, Wood, Leather, Metal, Stone), then
## the materials of that kind, each a button with its swatch and name; the one the part shows is pressed. Choosing
## one puts it on the part (with Undo in the footer); the stick's focus and the trigger reach every button.
func _material_picker(target: String, shows: String, materials: Array) -> Control:
	var box := W.vbox()
	var kinds := W.choices(MATERIAL_KINDS.map(func(k: Array) -> String: return k[0]), func(i: int) -> void:
		_material_tag = MATERIAL_KINDS[i][1]
		_sync_parts())
	W.set_choice(kinds, MATERIAL_KINDS.map(func(k: Array) -> String: return k[1]).find(_material_tag))
	box.add_child(kinds)
	var grid := GridContainer.new()
	grid.columns = MATERIAL_COLUMNS
	grid.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	grid.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	for mat: Dictionary in materials:
		if _material_tag != "" and not (_material_tag in mat.get("tags", [])):
			continue
		var id := str(mat["id"])
		var b := W.button(str(mat.get("name", id)), func() -> void: _apply(target, {"library_material": id}),
				&"RowButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_pressed_no_signal(id == shows)
		b.icon = swatch_icon(str(mat.get("swatch", "#808080")))
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "%s: %s" % [id, ", ".join(mat.get("tags", []))]
		b.set_meta("material", id)
		grid.add_child(b)
	box.add_child(grid)
	return box


static func _effect_name(id: String) -> String:
	return str(EffectLibrary.entry(id).get("name", id))


## The effect picker under a part: a row of groups (All, then the library's: Classic, Energy, Nature, ...; the skies'
## are for the sky only), then that group's effects, each a button with its preview and name (its description as the
## tooltip); the one the part shows is pressed. Choosing one puts it on the part with its options at their defaults
## (with Undo in the footer); over a library material only those that layer keep the material under them. The room's
## checks apply as for any change: the photosensitivity ceiling (the defaults are within it) and the cost limit.
func _effect_picker(target: String, shows: String) -> Control:
	var box := W.vbox()
	# The groups with part effects (the skies' are for the sky).
	var groups: Array = [""]
	for id in EffectLibrary.ids():
		var e := EffectLibrary.entry(id)
		if str(e["surfaces"]) == "any" and not (str(e["group"]) in groups):
			groups.append(str(e["group"]))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	row.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	var group := ButtonGroup.new()
	for g: String in groups:
		var b := W.button("All" if g == "" else g.capitalize(), Callable())
		b.toggle_mode = true
		b.button_group = group
		b.set_pressed_no_signal(g == _effect_group)
		b.set_meta("effect_group", g)
		b.pressed.connect(func() -> void:
			_effect_group = g
			_sync_parts())
		row.add_child(b)
	box.add_child(row)
	var grid := GridContainer.new()
	grid.columns = MATERIAL_COLUMNS
	grid.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	grid.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	for id in EffectLibrary.ids():
		var e := EffectLibrary.entry(id)
		if str(e["surfaces"]) != "any" or (_effect_group != "" and str(e["group"]) != _effect_group):
			continue
		var b := W.button(str(e.get("name", id)), func() -> void: _apply(target, {"effect": {"name": id}}),
				&"RowButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_pressed_no_signal(id == shows)
		b.icon = effect_icon(id)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = str(e.get("description", ""))
		b.set_meta("effect", id)
		grid.add_child(b)
	box.add_child(grid)
	return box


## An effect's preview, small (textures/fx/swatches/<id>.png, read once; the app runs from its folder, so the PNG is
## read as it is); an empty square when it is missing.
static func effect_icon(id: String) -> Texture2D:
	if not _effect_swatches.has(id):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(EFFECT_SWATCHES.path_join(id + ".png"))) != OK:
			img = Image.create_empty(EFFECT_SWATCH, EFFECT_SWATCH, false, Image.FORMAT_RGBA8)
		if img.get_width() != EFFECT_SWATCH:
			img.resize(EFFECT_SWATCH, EFFECT_SWATCH, Image.INTERPOLATE_BILINEAR)
		_effect_swatches[id] = ImageTexture.create_from_image(img)
	return _effect_swatches[id]


## A square of the material's mean colour, for its button's icon (made once per colour).
static func swatch_icon(hex: String) -> Texture2D:
	if not _swatches.has(hex):
		var img := Image.create_empty(MATERIAL_SWATCH, MATERIAL_SWATCH, false, Image.FORMAT_RGBA8)
		img.fill(RoomSchema.to_color(hex))
		_swatches[hex] = ImageTexture.create_from_image(img)
	return _swatches[hex]


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
	var said := "its own colour" if material == null else "changed"
	if material is Dictionary and (material as Dictionary).has("library_material"):
		said = _material_name(str(material["library_material"]))
	elif material is Dictionary and (material as Dictionary).get("effect") is Dictionary:
		said = _effect_name(str(material["effect"].get("name", "")))
	_toast(r, "%s: %s" % [target.get_slice("/", 1), said])
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
