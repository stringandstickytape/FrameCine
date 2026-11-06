extends VBoxContainer

## The Objects tab (ui/objects_tab.gd; docs/assistant.md "Objects", docs/USAGE.md "Objects"), in three sections: Built-in
## objects and Your objects, the library as thumbnails with names, each with its own Place (which hands the laser to
## ui/object_placer.gd), Your objects with Delete (asked first, in the footer, as the panel's other choices are) and
## Fab's downloads; and In this room, what this room has from the library: pick one for its parts, each with its colour, a palette, the picture on show as its picture, a material
## from the material library (a picker: each material's swatch and name, filtered by kind), an effect from the effect
## library (a picker: each effect's preview and name, filtered by group, its options at their defaults), and Reset;
## and Move and Remove (asked first). Everything here calls what the commands call
## (scripts/assistant/object_commands.gd), so a change has the same undo, cost limits and checks.
##
## Languages (docs/i18n.md): the built-in objects' names are keys (object_builtins.gd) and translate; the viewer's own
## objects, the names placed in the room, their parts and Fab's assets are content. The material and effect
## libraries' names (and the effects' descriptions) show as content, in English, for now. The errors the commands
## return are an assistant's English and show as they are.

const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const FabImport := preload("res://scripts/assistant/fab_import.gd")
const WebPages := preload("res://scripts/net/web_pages.gd")
## Visit Fab: the store's free scanned objects (the user's choice of page, 2026-11-05).
const FAB_URL := "https://www.fab.com/sellers/Quixel%20Megascans?is_free=1"

const COLUMNS := 4
## Pixels on the pane: the thumbnail as drawn, and the name under it. A tile's minimum is TILE_MIN wide; the grid's
## columns share what is left of its width (each tile expands), and a tile is as tall as it is wide, plus the name
## (_size_tile()). So four always fit the card, whatever its width, and the grid's minimum never follows the tiles.
## TILE_MIN keeps a grid wider than half the tab, so its card has a row of its own (W.refresh_cards()).
const THUMB := Vector2i(120, 120)
const TILE_MIN := 88
const CARD_TEXT := 26
const SWATCH := Vector2(28, 28)
## The colours a part can take from the palette, as text (the panel's own colours are the theme's).
const PALETTE := ["#f4f1ea", "#c8a27a", "#8b5a3c", "#3b2a1e", "#222222", "#7d7d7d", "#b5653d", "#c0392b",
		"#e8a33c", "#4f8a3c", "#2f6f8f", "#3366cc", "#6b4c9a", "#d98cb3"]
const ASSISTANT_ROOM := "res://scripts/assistant/assistant_room.gd"
## The material picker's kinds: their labels, and the library's tag of each ("" all).
const MATERIAL_KIND_NAMES := ["All", "Floors", "Walls", "Fabric", "Wood", "Leather", "Metal", "Stone"] # i18n
const MATERIAL_KIND_TAGS := ["", "floor", "wall", "fabric", "wood", "leather", "metal", "stone"]
## The effect library's groups (scripts/effects/catalogue/<group>.gd), as the picker names them.
# i18n: begin
const EFFECT_GROUPS := {"classic": "Classic", "energy": "Energy", "nature": "Nature", "reactive": "Reactive",
		"skies": "Skies", "stylised": "Stylised", "transitions": "Transitions", "materials": "Materials"}
# i18n: end
## Where an object goes (its manifest's mount), as the picked object's line says it.
const MOUNT_WORDS := {"free": "free", "wall": "wall", "floor": "floor"} # i18n
const MATERIAL_COLUMNS := 3
## The swatch on a material's button (its mean colour, from the catalogue: nothing is loaded to show it).
const MATERIAL_SWATCH := 22
## The effect picker's swatches: each effect's preview made small (tools/fx_swatches.gd), shipped with the app.
const EFFECT_SWATCHES := "res://textures/fx/swatches"
const EFFECT_SWATCH := 32

## scripts/main.gd
var app: Node
## The built-in objects' tiles, then the viewer's own (imported, or kept from a room) under their own heading, so it is
## plain which came with the app and which are this install's (the user, 2026-11-05).
var _grid: GridContainer
var _yours_label: Label
var _yours_grid: GridContainer
var _tiles := {}
var _ids: Array = []
var _selected := ""
## Built-in objects' line and Place; Your objects' line, Place and Delete (one pick across both: the other says
## to pick).
var _chosen: Label
var _place: Button
var _delete: Button
var _yours_chosen: Label
var _yours_place: Button
var _yours_empty: Label
var _placed_box: VBoxContainer
var _placed_names: Array = []
var _picked := ""
var _parts_box: VBoxContainer
## Tidy up: every object that was moved by hand back where it was placed (object physics).
var _tidy: Button
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
## Fab downloads in the Downloads folder not in the library yet (fab_import.gd): a button each to add it.
var _fab_box: VBoxContainer
var _fab_buttons: VBoxContainer
var _fab_paths: Array = []
var _adding := false


func bind(p_app: Node) -> void:
	app = p_app
	add_theme_constant_override("separation", PaneStyle.constant(&"gap"))
	add_child(W.section("Built-in objects"))
	_grid = _tile_grid()
	add_child(_grid)
	_chosen = W.ellipsis(W.label("", &"MutedLabel"))
	W.content(_chosen)
	_chosen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place = W.button("Place", _start_place)
	add_child(W.hbox([_chosen, _place]))
	add_child(W.help("Place: point at a wall or the floor, trigger to set it. Stick: turn and size. B cancels."))

	add_child(W.section("Your objects"))
	_yours_label = W.label("Imported, or kept from a room.", &"MutedLabel")
	add_child(_yours_label)
	_yours_empty = W.label("None yet: add one from Fab below.", &"MutedLabel")
	# Both wrap: a longer language fits the card.
	_yours_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_yours_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_yours_empty)
	_yours_grid = _tile_grid()
	add_child(_yours_grid)
	_yours_chosen = W.ellipsis(W.label("", &"MutedLabel"))
	W.content(_yours_chosen)
	_yours_chosen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yours_place = W.button("Place", _start_place)
	_delete = W.button("Delete", _ask_delete)
	add_child(W.hbox([_yours_chosen, _yours_place, _delete]))
	_fab_box = W.vbox()
	# An ellipsis where it is narrow (a longer language): the button keeps its room.
	var fab_label := W.ellipsis(W.label("In Downloads, from Fab", &"MutedLabel"))
	_fab_box.add_child(W.hbox([fab_label]))
	# The card's width, its text cut short where a longer language would not fit.
	var visit := W.button("Visit Fab to download objects", _visit_fab)
	visit.clip_text = true
	visit.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	visit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fab_box.add_child(W.hbox([visit]))
	_fab_buttons = W.vbox()
	_fab_buttons.visible = false
	_fab_box.add_child(_fab_buttons)
	add_child(_fab_box)

	add_child(W.section("In this room"))
	_empty = W.label("Nothing from the library yet.", &"MutedLabel")
	add_child(_empty)
	_placed_box = VBoxContainer.new()
	_placed_box.add_theme_constant_override("separation", 0)
	add_child(_placed_box)
	# Object physics (docs/physics.md): what was picked up, dropped or thrown goes back where it was placed.
	_tidy = W.button("Tidy up", _tidy_up)
	add_child(W.hbox([_tidy]))
	add_child(W.help("Pick up: point at an object and hold the grip. Let go to drop it, or throw it. Tidy up puts "
			+ "everything back."))
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
		# Text and particles are made from their options (an assistant's): not placed from here.
		var list := ObjectLibrary.list().filter(func(m: Dictionary) -> bool: return not m.has("generator"))
		for m: Dictionary in list:
			ObjectLibrary.thumbnail(str(m["id"]))
		return {"list": list, "fab": FabImport.downloads()})
	_loading = false
	if not r["done"] or not is_instance_valid(self):
		return
	var list: Array = r["result"]["list"]
	_sync_fab(r["result"]["fab"])
	var ids: Array = list.map(func(m: Dictionary) -> String: return str(m["id"]))
	if ids != _ids:
		_ids = ids
		_tiles.clear()
		for g in [_grid, _yours_grid]:
			for c in g.get_children():
				g.remove_child(c)
				c.queue_free()
		var group := ButtonGroup.new()
		for m: Dictionary in list:
			_tile(m, group)
		_yours_grid.visible = _yours_grid.get_child_count() > 0
		_yours_label.visible = _yours_grid.visible
		_yours_empty.visible = not _yours_grid.visible
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
	var img := ObjectLibrary.thumbnail(id)
	if img != null:
		var art := TextureRect.new()
		art.texture = ImageTexture.create_from_image(img)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.name = "Art"
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
	var title := W.ellipsis(W.label(str(m["name"])))
	# A built-in's name is a key (object_builtins.gd); the viewer's own object's is content.
	if not ObjectLibrary.is_builtin(id):
		W.content(title)
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(title)
	b.pressed.connect(func() -> void:
		_selected = id
		_sync_chosen()
		_show_place())
	var grid := _grid if str(m.get("source", "user")) == "builtin" else _yours_grid
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(TILE_MIN, TILE_MIN + CARD_TEXT)
	b.resized.connect(_size_tile.bind(b))
	grid.add_child(b)
	_tiles[id] = b


## A tile's thumbnail and name for its width (the grid's share), and its height: square, plus the name.
func _size_tile(b: Button) -> void:
	var side := b.size.x
	if absf(b.custom_minimum_size.y - (side + CARD_TEXT)) > 0.5:
		b.custom_minimum_size.y = side + CARD_TEXT
	var art := b.get_node_or_null("Art") as Control
	if art != null:
		art.position = Vector2.ZERO
		art.size = Vector2(side, side)
	var title := b.get_node("Title") as Control
	title.position = Vector2(4, side + 2)
	title.size = Vector2(side - 8, 20)


## A button for each Fab zip in Downloads; pressing it adds the asset as one of the viewer's objects.
func _sync_fab(found: Array) -> void:
	var paths: Array = found.map(func(f: Dictionary) -> String: return str(f["path"]))
	if paths == _fab_paths:
		# The same downloads: only their words again (the language may have changed).
		for b in _fab_buttons.get_children():
			(b as Button).text = tr("Add %s") % b.get_meta("fab_name", "")
		return
	_fab_paths = paths
	for c in _fab_buttons.get_children():
		_fab_buttons.remove_child(c)
		c.queue_free()
	for f: Dictionary in found:
		var path := str(f["path"])
		var b := W.button(tr("Add %s") % f["name"], func() -> void: _add_fab(path), &"RowButton")
		W.content(b)
		b.set_meta("fab_name", str(f["name"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_fab_buttons.add_child(b)
	_fab_buttons.visible = not found.is_empty()


## The store's page in the Browser source (as the dev link's open_url): the panel goes so it shows.
func _visit_fab() -> void:
	var url := WebPages.normalized(FAB_URL)
	WebPages.set_last_url(url)
	app.ui.hide_panel()
	app.open_path("browser://" + url)


## On the main thread, behind a notice (as a room's first lightmap bake, room_lightmaps.gd): the notice is drawn, then
## the import holds the frames for its second or so and the headset shows its own waiting view. On a worker it ran
## alongside the frames and broke the picture up while it went (the user, 2026-11-05).
func _add_fab(path: String) -> void:
	if _adding:
		return
	_adding = true
	app.ui.notify(tr("Adding %s: a moment.") % _fab_name(path))
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	var out := FabImport.import_zip(path)
	_adding = false
	if out.get("ok") == true:
		_selected = str(out["manifest"]["id"])
		app.ui.notify(tr("%s is in your objects.") % out["manifest"]["name"])
	else:
		# The import's own reason (English, as an assistant reads it), else a word of ours.
		app.ui.notify(str(out["error"]) if str(out.get("error", "")) != "" else tr("That didn't work."))
	sync_objects()


func _fab_name(path: String) -> String:
	for b in _fab_buttons.get_children():
		if b.has_meta("fab_name") and _fab_paths.find(path) == b.get_index():
			return str(b.get_meta("fab_name"))
	return path.get_file()


func _tile_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = COLUMNS
	g.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	g.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func _sync_chosen() -> void:
	var m := ObjectLibrary.get_object(_selected) if _selected != "" else {}
	var yours: bool = not m.is_empty() and m["source"] == "user"
	var line := ""
	if not m.is_empty():
		var n := (m.get("parts", []) as Array).size()
		# A built-in's name in the menus' language; the viewer's own as it is.
		var shown := tr(str(m["name"])) if ObjectLibrary.is_builtin(_selected) else str(m["name"])
		var mount := str(m["mount"])
		line = "%s  ·  %s  ·  %s" % [shown, tr(MOUNT_WORDS[mount]) if MOUNT_WORDS.has(mount) else mount,
				tr_n("%d part", "%d parts", n) % n]
	_chosen.text = line if not m.is_empty() and not yours else tr("Pick an object, then Place.")
	_place.disabled = m.is_empty() or yours
	_yours_chosen.text = line if yours else tr("Pick one, then Place.")
	_yours_place.disabled = not yours
	_delete.visible = yours


## The panel scrolls so that Place shows: it sits under the grid, often below the visible part of the tab.
func _show_place() -> void:
	var p: Node = get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		var yours := _selected != "" and str(ObjectLibrary.get_object(_selected).get("source", "")) == "user"
		(p as ScrollContainer).ensure_control_visible(_yours_place if yours else _place)


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
	# A kept room that places it keeps it in the library (rooms are made of objects): said instead of asked.
	var using := ObjectLibrary.rooms_using(id)
	if not using.is_empty():
		app.ui.notify(tr("%s is in %s: remove it there first.") % [m["name"], ", ".join(using)])
		return
	app.ui.ui.show_choice(tr("Delete %s from the library?") % m["name"], tr("Delete"), func() -> void:
		var r := ObjectLibrary.delete(id)
		if r.get("ok") == true:
			ObjectLibrary.purge(id)
			_selected = ""
		else:
			app.ui.notify(str(r.get("error", "")))
		sync_objects()
		app.ui.ui.hide_toast(), tr("Keep"), func() -> void: app.ui.ui.hide_toast(), 15.0)


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
			# What the room calls it (its placement's name): content.
			W.content(b)
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
	_tidy.disabled = not names.any(func(n: String) -> bool: return ObjectCommands.moved(app.env, n))
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
	var row_buttons: Array = [W.button("Move", func() -> void: app.ui.start_object_move(name)),
			W.button("Remove", func() -> void: _ask_remove(name))]
	var generated := RoomSchema.kind_of({"object": str(entry["object"])}) in RoomSchema.GENERATORS
	var attached := _attached_to(name)
	if generated:
		# A text or particles area follows an object (object physics): Attach picks which; Detach leaves it here.
		row_buttons.append(W.button("Attach", func() -> void:
			_palette_for = "attach:" + name if _palette_for != "attach:" + name else ""
			_sync_parts()))
		if attached != "":
			row_buttons.append(W.button("Detach", func() -> void: _attach(name, "")))
	else:
		var back := W.button("Put back", func() -> void: _put_back(name))
		back.disabled = not ObjectCommands.moved(app.env, name)
		row_buttons.append(back)
	_parts_box.add_child(W.hbox(row_buttons))
	if attached != "":
		var follows := W.ellipsis(W.label(tr("Follows %s") % attached, &"MutedLabel"))
		W.content(follows)
		_parts_box.add_child(follows)
	if _palette_for == "attach:" + name:
		_parts_box.add_child(_attach_picker(name, attached))
	var materials := _materials()
	for part: Dictionary in entry["parts"]:
		var target := "%s/%s" % [name, part["name"]]
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = SWATCH
		swatch.color = RoomSchema.to_color(str(part["color"]) if str(part["color"]) != "" else "#7d7d7d")
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shows := str(part.get("material", ""))
		var effect := str(part.get("effect", ""))
		# The part's name and the libraries' names: content; "changed" in the menus' language.
		var label := W.ellipsis(W.label(str(part["name"]) + ("  ·  " + _material_name(shows) if shows != "" else "")
				+ ("  ·  " + _effect_name(effect) if effect != "" else "")
				+ ("  " + tr("(changed)") if part.get("recolour") != null else "")))
		W.content(label)
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
	var kinds := W.choices(MATERIAL_KIND_NAMES, func(i: int) -> void:
		_material_tag = MATERIAL_KIND_TAGS[i]
		_sync_parts())
	W.set_choice(kinds, MATERIAL_KIND_TAGS.find(_material_tag))
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
		# The library's name, in English for now (content: not a key yet).
		W.content(b)
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
		var b := W.button("All" if g == "" else str(EFFECT_GROUPS.get(g, g.capitalize())), Callable())
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
		# The library's name and description, in English for now (content: not keys yet).
		W.content(b)
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
		app.ui.notify(tr("Open a picture on the headset first (Files); then Picture puts it on the part."))
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > int(RoomSchema.LIMITS["image_bytes"]):
		app.ui.notify(tr("That picture is too big for a part (at most %d MB).") % (int(RoomSchema.LIMITS["image_bytes"])
				/ (1024 * 1024)))
		return
	_apply(target, {"texture": Marshalls.raw_to_base64(bytes)})


## A part's colour, picture or material (null: back to its own), with Undo in the footer.
func _apply(target: String, material: Variant) -> void:
	var r: Dictionary = await ObjectCommands.recolour_part(get_tree(), null, target, material)
	_palette_for = ""
	var said := tr("its own colour") if material == null else tr("changed")
	if material is Dictionary and (material as Dictionary).has("library_material"):
		said = _material_name(str(material["library_material"]))
	elif material is Dictionary and (material as Dictionary).get("effect") is Dictionary:
		said = _effect_name(str(material["effect"].get("name", "")))
	_toast(r, "%s: %s" % [target.get_slice("/", 1), said])
	sync_objects()


# --- Object physics (docs/physics.md) --------------------------------------------------------------------------

## The placement a text or particles area follows, or "".
func _attached_to(name: String) -> String:
	var doc: Dictionary = app.env.get("doc") if app.env != null and app.env.get("doc") is Dictionary else {}
	for p: Dictionary in doc.get("parts", []):
		if str(p.get("name", "")) == name:
			return str(p.get("attach", ""))
	return ""


## The objects a text or particles area can follow (every other placement that isn't one too), a button each; the
## one it follows is pressed.
func _attach_picker(name: String, attached: String) -> Control:
	var box := W.vbox()
	box.add_child(W.label("Follows:", &"MutedLabel"))
	var grid := GridContainer.new()
	grid.columns = MATERIAL_COLUMNS
	grid.add_theme_constant_override("h_separation", PaneStyle.constant(&"gap"))
	grid.add_theme_constant_override("v_separation", PaneStyle.constant(&"gap"))
	for p: Dictionary in _placed():
		var to := str(p["name"])
		if to == name or RoomSchema.kind_of({"object": str(p["object"])}) in RoomSchema.GENERATORS:
			continue
		var b := W.button(to, func() -> void: _attach(name, to), &"RowButton")
		# What the room calls it: content.
		W.content(b)
		b.toggle_mode = true
		b.set_pressed_no_signal(to == attached)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	box.add_child(grid)
	return box


func _attach(name: String, to: String) -> void:
	var r: Dictionary = await ObjectCommands.attach(get_tree(), null, name, to)
	_palette_for = ""
	_toast(r, tr("%s follows %s") % [name, to] if to != "" else tr("%s stays where it is") % name)
	sync_objects()


func _put_back(name: String) -> void:
	var r: Dictionary = await ObjectCommands.put_back(get_tree(), null, [name])
	_toast(r, tr("%s is back where it was placed") % name)
	sync_objects()


func _tidy_up() -> void:
	var r: Dictionary = await ObjectCommands.put_back(get_tree(), null, [])
	var n := (r.get("result", {}).get("put_back", []) as Array).size() if r.get("ok") == true else 0
	_toast(r, tr_n("Tidied up: %d object back", "Tidied up: %d objects back", n) % n)
	sync_objects()


func _ask_remove(name: String) -> void:
	app.ui.ui.show_choice(tr("Remove %s from the room?") % name, tr("Remove"), func() -> void:
		app.ui.ui.hide_toast()
		var r: Dictionary = await ObjectCommands.remove_placed(get_tree(), null, name)
		_toast(r, tr("Removed %s") % name), tr("Keep"), func() -> void: app.ui.ui.hide_toast(), 15.0)


## done: in the menus' language already. A command's error is an assistant's English and shows as it is.
func _toast(r: Dictionary, done: String) -> void:
	if r.get("ok") == true:
		app.ui.ui.show_toast(done, tr("Undo") if r.get("undo") is Callable else "", r.get("undo", Callable()), 8.0)
	else:
		app.ui.notify(str(r["error"]) if str(r.get("error", "")) != "" else tr("That didn't work."))
