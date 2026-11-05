extends SceneTree

## Writes the showrooms (docs/showrooms.md; scripts/env/showrooms.gd lists them): room documents that show what the
## room system can do, made from the libraries as they are now, so run it again when a library grows:
##   godot --headless --xr-mode off --path app --script res://tools/showrooms.gd [-- --check]
## --check writes nothing and exits 1 when the files differ from what it would write (tests/test_showrooms.gd).
##
##   Effects gallery   every effect of the effect library on a sphere, by group (the skies in their own rooms)
##   Material wall     every library material on a flat panel and a sphere, by kind
##   Objects           the parts a room document places: shapes, text, surfaces and pictures, widgets, motion, the
##                     object library's built-in objects (no user objects; no particles: see docs/showrooms.md)
##   Lights            the key light with its shadows, the sky fill, the film's light, a point and a spot light
##   <name> sky        one room per sky effect
##
## Each sample has a printed name beside it. A room may hold LIMITS.texts (16) text parts, so the labels of a column
## of samples are one text part whose lines are spaced to the rows (blank lines hold a word joiner: the engine drops
## empty lines, and draws no glyph for this one). A room that would go over BUDGET is split in two ("Effects gallery
## 2"), by group, then within a group.

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectBuiltins := preload("res://scripts/assistant/object_builtins.gd")
const Showrooms := preload("res://scripts/env/showrooms.gd")

const INDEX_VERSION := 1
## What one showroom may use: the room's cost units (RoomSchema.COSTS; LIMITS.cost is 120), text parts, draw calls
## and triangles as estimated by budget(), and lights. For a mobile GPU drawing two eyes at 72 Hz with a film playing.
const BUDGET := {"cost": 100.0, "texts": 16, "draws": 150, "triangles": 250000, "lights": 3}

## The labels: a line this high (metres), LINES_PER_ROW lines from one row of samples to the next.
const LINE := 0.055
const LINES_PER_ROW := 7
const PITCH := LINE * LINES_PER_ROW
const ROWS := 4
## The top row's centre; the rows go down from it, a group's title one row above it.
const ROW_TOP := 1.7
## Between a sample and its label, between columns, between groups (metres along the ring).
const LABEL_GAP := 0.06
const COLUMN_GAP := 0.2
const GROUP_GAP := 0.45
## The ring round the seat: at least RING_MIN m away, from ARC_FROM degrees right of ahead, round the back, over at
## most ARC_SPAN degrees (the screen ahead is kept clear).
const RING_MIN := 2.4
const ARC_FROM := 40.0
const ARC_SPAN := 280.0
## The note that opens a room: its width and line height.
const INTRO_WIDTH := 0.9
const INTRO_LINE := 0.045
## A blank label line: U+2060 WORD JOINER, a line of its own height that draws nothing.
const BLANK := "⁠"
const LABEL_COLOUR := "#e6e6e6"
const FLOOR_COLOUR := "#1b1d22"
## The gallery's light: brighter than the stock rooms, so the samples read.
const GALLERY_LIGHT := {"ambient": 0.7, "screen_glow": 0.3, "contact_shadows": false}
## The effect samples' own colour (the previews' too: effect_lab.gd BASE_COLOR) and size.
const FX_BASE := "#8a6e4b"
const FX_SPHERE := 0.3
## Options the room builder fills in from the part's size (assistant_room.gd fit_effect): not taken from the previews.
const FX_SIZED := ["size", "base", "height"]
## The material kinds, by tag (or a word in the id), in this order: a material goes to the first kind that names one;
## the rest to "Other".
const MATERIAL_KINDS := [
	["Wood", ["wood", "planks", "veneer", "parquet", "laminate"]],
	["Stone and concrete", ["stone", "marble", "concrete", "terrazzo", "tiles"]],
	["Walls", ["brick", "plaster", "paint", "painted", "acoustic", "foam"]],
	["Metal", ["metal", "brass", "steel"]],
	["Leather", ["leather"]],
	["Fabric and carpet", ["fabric", "carpet", "upholstery", "velvet", "linen", "felt", "wicker"]],
]


func _initialize() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var rooms := build()
	var diff := differences(rooms)
	if check:
		for d: String in diff:
			print("showrooms: " + d)
		print("showrooms: %s" % ("up to date" if diff.is_empty() else "%d difference(s); run tools/showrooms.gd"
				% diff.size()))
		quit(0 if diff.is_empty() else 1)
		return
	var err := write(rooms)
	if err != "":
		push_error("showrooms: " + err)
		quit(1)
		return
	for r: Dictionary in rooms:
		print("showrooms: %s (%s): %s" % [r["file"], r["name"], JSON.stringify(r["budget"])])
	quit(0)


# --- The rooms -------------------------------------------------------------------------------------------------------

## Every showroom: [{id, name, file, description, shows, budget, doc (as saved: model_file, texture_file), files:
## {file name: bytes}}], in the Room tab's order.
static func build() -> Array:
	var out: Array = []
	out.append_array(_split("effects", "Effects gallery", _effect_groups(), _effects_room))
	out.append_array(_split("materials", "Material wall", _material_groups(), _materials_room))
	out.append(_objects_room())
	out.append(_lights_room())
	for id in EffectLibrary.ids():
		if str(EffectLibrary.entry(id)["surfaces"]) == "sky":
			out.append(_sky_room(id))
	for r: Dictionary in out:
		r["budget"] = budget(r["doc"])
	return out


## Groups into as few rooms as BUDGET allows: [room, ...], the first called `name`, the next "<name> 2".
static func _split(id: String, name: String, groups: Array, make: Callable) -> Array:
	var packed: Array = []
	var current: Array = []
	var queue := groups.duplicate()
	while not queue.is_empty():
		var g: Dictionary = queue.pop_front()
		if fits(make.call(current + [g], name)["doc"]):
			current.append(g)
		elif not current.is_empty():
			packed.append(current)
			current = []
			queue.push_front(g)
		elif (g["items"] as Array).size() > 1:
			# One group alone is too much: in halves, each keeping the title.
			var items: Array = g["items"]
			var half := items.size() / 2
			queue.push_front({"title": g["title"], "items": items.slice(half)})
			queue.push_front({"title": g["title"], "items": items.slice(0, half)})
		else:
			current.append(g)
	if not current.is_empty():
		packed.append(current)
	var out: Array = []
	for i in packed.size():
		var room_name := name if i == 0 else "%s %d" % [name, i + 1]
		var r: Dictionary = make.call(packed[i], room_name)
		r["id"] = id if i == 0 else "%s_%d" % [id, i + 1]
		r["file"] = r["id"] + ".room.json"
		out.append(r)
	return out


static func _effect_groups() -> Array:
	var out: Array = []
	for g in EffectLibrary.groups():
		var items: Array = []
		for id in EffectLibrary.ids():
			var e := EffectLibrary.entry(id)
			if str(e["group"]) != g or str(e["surfaces"]) == "sky":
				continue
			var fx := {"name": id}
			var preview: Dictionary = e.get("preview_options", {})
			for k: String in preview:
				if not k in FX_SIZED:
					fx[k] = preview[k]
			items.append({"label": str(e["name"]), "id": id, "width": FX_SPHERE, "parts": [{"name": "fx " + id,
					"type": "sphere", "size": [FX_SPHERE], "material": {"color": FX_BASE, "effect": fx}}]})
		if not items.is_empty():
			out.append({"title": g, "items": items})
	return out


static func _sky_names() -> Array:
	var out: Array = []
	for id in EffectLibrary.ids():
		if str(EffectLibrary.entry(id)["surfaces"]) == "sky":
			out.append(str(EffectLibrary.entry(id)["name"]))
	return out


static func _effects_room(groups: Array, name: String) -> Dictionary:
	var n := 0
	var ids: Array = []
	for g: Dictionary in groups:
		n += (g["items"] as Array).size()
		for it: Dictionary in g["items"]:
			ids.append(it["id"])
	var skies := _sky_names()
	var intro := "%s\n%d effects of the effect library, each on a sphere with its preview's options." % [name, n]
	if not skies.is_empty():
		intro += " The skies have showrooms of their own: %s." % ", ".join(skies)
	var parts := _gallery(groups, intro)
	return _room(name, "Every effect of the effect library on a sphere, by group", GALLERY_LIGHT, parts,
			{"effects": ids})


static func _material_groups() -> Array:
	var kinds := {}
	for k: Array in MATERIAL_KINDS:
		kinds[k[0]] = []
	kinds["Other"] = []
	for m: Dictionary in MaterialLibrary.list():
		var kind := "Other"
		for k: Array in MATERIAL_KINDS:
			if (m["tags"] as Array).any(func(t: Variant) -> bool: return str(t) in k[1]) \
					or (k[1] as Array).any(func(w: String) -> bool: return str(m["id"]).contains(w)):
				kind = k[0]
				break
		kinds[kind].append({"label": str(m["name"]), "id": str(m["id"]), "width": 0.63, "parts": [
				{"name": "mat %s panel" % m["id"], "type": "box", "size": [0.3, 0.3, 0.02], "position": [-0.165, 0, 0],
					"material": {"library_material": m["id"]}},
				{"name": "mat %s sphere" % m["id"], "type": "sphere", "size": [0.26], "position": [0.17, 0, 0],
					"material": {"library_material": m["id"]}}]})
	var out: Array = []
	for k: String in kinds:
		if not (kinds[k] as Array).is_empty():
			out.append({"title": k, "items": kinds[k]})
	return out


static func _materials_room(groups: Array, name: String) -> Dictionary:
	var n := 0
	var ids: Array = []
	for g: Dictionary in groups:
		n += (g["items"] as Array).size()
		for it: Dictionary in g["items"]:
			ids.append(it["id"])
	var parts := _gallery(groups, "%s\n%d materials of the material library, each on a flat panel and a sphere, at "
			% [name, n] + "its own scale (tiling).")
	return _room(name, "Every library material on a flat panel and a sphere, by kind", GALLERY_LIGHT, parts,
			{"materials": ids})


## The parts a room document can place, unlit (lights have their own room).
static func _objects_room() -> Dictionary:
	var shapes := [
		_item("Box", [{"type": "box", "size": [0.24, 0.24, 0.24], "rotation": [20, 30, 0],
				"material": {"color": "#6f8fb0"}}]),
		_item("Sphere", [{"type": "sphere", "size": [0.3], "material": {"color": "#b07a5a"}}]),
		_item("Cylinder", [{"type": "cylinder", "size": [0.22, 0.3], "rotation": [15, 0, 0],
				"material": {"color": "#7aa070"}}]),
		_item("Plane", [{"type": "plane", "size": [0.3, 0.3], "rotation": [60, 0, 0],
				"material": {"color": "#a0a0a8"}}]),
		_item("Text", [{"type": "text", "text": "Words", "size": [0.1],
				"text_options": {"weight": "bold", "background": "#2a3442"}}], 0.34),
	]
	var picture := _picture(false)
	var cutout := _picture(true)
	var surfaces := [
		_item("Colour", [{"type": "box", "size": [0.26, 0.26, 0.26], "rotation": [15, 25, 0],
				"material": {"color": "#c06a3a"}}]),
		_item("Glow (emission)", [{"type": "sphere", "size": [0.26], "material": {"color": "#402010",
				"emission": "#ff9040", "emission_strength": 1.5}}]),
		_item("See-through", [{"type": "sphere", "size": [0.28], "material": {"color": [0.55, 0.8, 1.0, 0.45]}}]),
		_item("Picture, atlas", [{"type": "box", "size": [0.26, 0.26, 0.26], "rotation": [15, 25, 0],
				"material": {"texture_file": picture, "uv": "atlas"}}]),
		_item("Picture, each face", [{"type": "box", "size": [0.26, 0.26, 0.26], "rotation": [15, 25, 0],
				"material": {"texture_file": picture, "uv": "each_face"}}]),
		_item("Picture, front only", [{"type": "box", "size": [0.26, 0.26, 0.26], "rotation": [15, 25, 0],
				"material": {"texture_file": picture, "uv": "front_only", "color": "#505860"}}]),
		_item("Cut-out picture", [{"type": "box", "size": [0.3, 0.3, 0.01],
				"material": {"texture_file": cutout, "uv": "front_only", "alpha": "cutout"}}]),
	]
	var panel := func(w: float, h: float) -> Dictionary:
		return {"type": "box", "size": [w, h, 0.03], "material": {"color": "#1c1c1c"}}
	var widgets := [
		_item("Clock", [{"type": "cylinder", "size": [0.28, 0.03], "rotation": [90, 0, 0],
				"material": {"color": "#e8e4dc"}, "widget": "clock",
				"widget_options": {"style": "analog", "color": "#202020", "background": "#e8e4dc"}}]),
		_item("Film progress, bar", [_with(panel.call(0.34, 0.1), {"widget": "film_progress",
				"widget_options": {"style": "bar"}})], 0.34),
		_item("Film progress, ring", [_with(panel.call(0.24, 0.24), {"widget": "film_progress",
				"widget_options": {"style": "ring"}})]),
		_item("Now playing", [_with(panel.call(0.34, 0.12), {"widget": "now_playing"})], 0.34),
		_item("End time", [_with(panel.call(0.3, 0.12), {"widget": "end_time"})]),
		_item("Battery", [_with(panel.call(0.3, 0.14), {"widget": "battery"})]),
		_item("Screen glow", [{"type": "sphere", "size": [0.26], "material": {"color": "#ffffff"},
				"widget": "screen_glow", "widget_options": {"style": "shimmer"}}]),
	]
	var motion := [
		_item("Spin", [{"type": "box", "size": [0.2, 0.2, 0.2], "rotation": [20, 0, 20],
				"material": {"color": "#d0a040"}, "motion": {"type": "spin", "axis": [0, 1, 0], "speed": 40}}]),
		_item("Bob", [{"type": "sphere", "size": [0.2], "material": {"color": "#60a0d0"},
				"motion": {"type": "bob", "height": 0.1, "period": 3}}]),
		_item("Sway", [{"type": "box", "size": [0.06, 0.3, 0.06], "material": {"color": "#a070c0"},
				"motion": {"type": "sway", "angle": 20, "period": 4, "axis": [0, 0, 1]}}]),
		_item("Orbit", [{"type": "sphere", "size": [0.08], "material": {"color": "#808080"}},
				{"type": "sphere", "size": [0.08], "position": [0.12, 0, 0], "material": {"color": "#e0e0e0"},
					"motion": {"type": "orbit", "center": [0, 0, 0], "axis": [0, 0, 1], "radius": 0.12,
						"period": 6}}]),
		_item("Flap", [{"type": "box", "size": [0.26, 0.02, 0.12], "position": [0.13, 0, 0],
				"material": {"color": "#c05050"}, "motion": {"type": "flap", "angle": 30, "period": 2,
					"axis": [0, 0, 1], "hinge": [-0.13, 0, 0]}}]),
	]
	var objects: Array = []
	var files := {picture: _png(false), cutout: _png(true)}
	var ids: Array = []
	for e: Dictionary in ObjectBuiltins.ENTRIES:
		if e.get("primitive", false) or e.has("generator"):
			continue  # the shapes and the text: shown above as the shapes a document sends
		var id := str(e["id"])
		var m := ObjectLibrary.get_object(id)
		var bytes := ObjectLibrary.glb(id)
		if m.is_empty() or bytes.is_empty():
			continue
		var file := "%s.glb" % id
		files[file] = bytes
		ids.append(id)
		var b := ObjectLibrary.bounds_of(m)
		var k := minf(1.0, minf(0.34 / maxf(b.size.y, 0.01), 0.5 / maxf(b.size.x, 0.01)))
		var at := -b.get_center() * k
		var part := {"type": "model", "object": id, "model_file": file, "position": [at.x, at.y, at.z],
				"scale": snappedf(k, 0.001)}
		if m.has("widget"):
			part["widget"] = m["widget"]
			part["widget_options"] = m.get("widget_options", {})
		objects.append(_item(str(m["name"]), [part], b.size.x * k))
	var groups := [{"title": "Shapes", "items": shapes}, {"title": "Surfaces", "items": surfaces},
			{"title": "Widgets", "items": widgets}, {"title": "Motion", "items": motion},
			{"title": "Library objects", "items": objects}]
	var parts := _gallery(groups, "Objects\nWhat a room document places: shapes and text, surfaces and pictures, "
			+ "widgets, motion and the object library's built-in objects. Lights: the Lights showroom. Particles are "
			+ "not shown here.")
	var r := _room("Objects", "The parts a room document places: shapes, text, surfaces, widgets, motion, objects",
			GALLERY_LIGHT, parts, {"objects": ids, "types": ["box", "sphere", "cylinder", "plane", "text", "model"],
			"widgets": RoomSchema.WIDGETS.keys()})
	r["files"] = files
	r["id"] = "objects"
	r["file"] = "objects.room.json"
	return r


## Real lighting: the key light (the sun) with its shadows, the sky fill and the film's light; a flickering point
## light and a spot light, over a few things standing on the floor.
static func _lights_room() -> Dictionary:
	# The key light low from ahead and to the right: long shadows to the back left.
	var light := {"ambient": 0.2, "screen_glow": 0.4, "contact_shadows": true,
			"key": {"elevation": 40, "azimuth": 60, "energy": 0.8, "shadows": true},
			"sky": {"energy": 0.35}, "screen": {"energy": 0.6}}
	var parts: Array = [
		{"name": "Floor", "type": "plane", "size": [9, 9], "position": [0, 0, 0], "material": {"color": "#6d6862"}},
		# Left: under the point light.
		{"name": "Ball", "type": "sphere", "size": [0.5], "position": [-2.3, 0.25, -0.6],
			"material": {"color": "#d8d0c4"}},
		{"name": "Drum", "type": "cylinder", "size": [0.4, 0.6], "position": [-2.2, 0.3, 0.3],
			"material": {"color": "#5a7890"}},
		# Right: under the spot light.
		{"name": "Crate", "type": "box", "size": [0.5, 0.5, 0.5], "position": [2.3, 0.25, -0.5], "rotation": [0, 25, 0],
			"material": {"color": "#b08a5a"}},
		{"name": "Pillar", "type": "box", "size": [0.25, 1.4, 0.25], "position": [2.0, 0.7, 0.6],
			"material": {"color": "#c8c8c8"}},
		# Behind: an arch, its shadow across the floor.
		{"name": "Arch left", "type": "box", "size": [0.2, 1.6, 0.2], "position": [-0.6, 0.8, 2.4],
			"material": {"color": "#a09080"}},
		{"name": "Arch right", "type": "box", "size": [0.2, 1.6, 0.2], "position": [0.6, 0.8, 2.4],
			"material": {"color": "#a09080"}},
		{"name": "Arch top", "type": "box", "size": [1.4, 0.2, 0.2], "position": [0, 1.7, 2.4],
			"material": {"color": "#a09080"}},
	]
	var files := {}
	var ids: Array = []
	var plant := ObjectLibrary.get_object("pot_plant")
	if not plant.is_empty():
		files["pot_plant.glb"] = ObjectLibrary.glb("pot_plant")
		ids.append("pot_plant")
		parts.append({"name": "Plant", "type": "model", "object": "pot_plant", "model_file": "pot_plant.glb",
				"position": [2.6, 0.0, 0.4]})
	parts.append(_facing({"name": "About", "type": "text", "text": "Lights\nThe key light (the sun) with its "
			+ "shadows, the sky's fill light and the film's light on the room; a flickering point light on the left, a "
			+ "spot light on the right.", "size": [0.06], "text_options": {"color": LABEL_COLOUR, "max_width": 1.2}},
			Vector3(1.7, 1.6, -1.7)))
	parts.append(_facing({"name": "Point light label", "type": "text", "text": "Point light, flickering",
			"size": [0.06], "text_options": {"color": LABEL_COLOUR}}, Vector3(-2.0, 1.2, -0.15)))
	parts.append(_facing({"name": "Spot light label", "type": "text", "text": "Spot light", "size": [0.06],
			"text_options": {"color": LABEL_COLOUR}}, Vector3(2.0, 1.45, 0.05)))
	var doc := {"lights": [
		{"name": "Point", "type": "point", "position": [-2.2, 1.4, -0.2], "color": "#ffb060", "energy": 1.5,
			"range": 3.0, "flicker": {"rate": 1.2, "swing": 0.25}},
		{"name": "Spot", "type": "spot", "position": [2.2, 2.2, 0.0], "direction": [0, -1, 0], "angle": 35,
			"color": "#a8c4ff", "energy": 3.0, "range": 4.0}]}
	var r := _room("Lights", "Real lighting: the key light with shadows, sky fill, the film's light, a point and a "
			+ "spot light", light, parts, {"objects": ids})
	(r["doc"] as Dictionary).merge(doc)
	r["files"] = files
	r["id"] = "lights"
	r["file"] = "lights.room.json"
	return r


## One sky effect as the whole sky, with its name and description.
static func _sky_room(id: String) -> Dictionary:
	var e := EffectLibrary.entry(id)
	var a := deg_to_rad(50.0)
	var parts := [_facing({"name": "About", "type": "text", "text": "%s\n%s" % [e["name"], e["description"]],
			"size": [0.06], "text_options": {"color": LABEL_COLOUR, "max_width": 1.2}},
			Vector3(sin(a) * 2.5, 1.3, -cos(a) * 2.5))]
	var r := _room(str(e["name"]), "%s as the whole sky" % e["name"], {"ambient": 0.3, "contact_shadows": false},
			parts, {"effects": [id]})
	r["doc"]["sky"] = {"effect": {"name": id}}
	r["id"] = id
	r["file"] = id + ".room.json"
	return r


## A part at `at`, turned to face the seat.
static func _facing(p: Dictionary, at: Vector3) -> Dictionary:
	var q := p.duplicate(true)
	q["position"] = _r3(at)
	q["rotation"] = [0, snappedf(-rad_to_deg(atan2(at.x, -at.z)), 0.1), 0]
	return q


static func _item(label: String, parts: Array, width := 0.3) -> Dictionary:
	return {"label": label, "width": width, "parts": parts}


static func _with(d: Dictionary, more: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out.merge(more, true)
	return out


## A showroom is a document in schema 2, its parts as an assistant sends them (shapes, the app's own pictures and the
## built-ins' .glb beside it): shipped read-only under res://, it is never converted into the viewer's object library
## (rooms are made of objects only once kept: assistant_room.gd load_saved, room_keep.gd).
const SHOWROOM_SCHEMA := 2


static func _room(name: String, description: String, light: Dictionary, parts: Array, shows: Dictionary) -> Dictionary:
	var doc := {"schema": SHOWROOM_SCHEMA, "name": name, "base": "void", "light": light.duplicate(true),
			"parts": parts, "recolour": []}
	var c := shows.duplicate(true)
	c["parts"] = parts.size()
	return {"name": name, "description": description, "doc": doc, "files": {}, "shows": c}


# --- Layout ----------------------------------------------------------------------------------------------------------

## Groups of samples on a ring round the seat, each sample facing it with its label to its right: [part, ...], the
## floor and the opening note included. groups: [{title, items: [{label, width, parts: [part in the sample's frame:
## x right along the ring, y up, z towards the seat]}]}].
static func _gallery(groups: Array, intro: String) -> Array:
	var columns: Array = []
	for g: Dictionary in groups:
		var items: Array = g["items"]
		for c in range(0, items.size(), ROWS):
			var chunk := items.slice(c, c + ROWS)
			var w := 0.0
			for it: Dictionary in chunk:
				w = maxf(w, float(it["width"]))
			var lines := _label_lines(chunk, str(g["title"]).to_upper() if c == 0 else "")
			columns.append({"items": chunk, "width": w, "title": c == 0, "text": "\n".join(lines),
					"label_width": _text_width(lines), "last": c + ROWS >= items.size()})
	var length := INTRO_WIDTH + GROUP_GAP
	for col: Dictionary in columns:
		length += float(col["width"]) + LABEL_GAP + float(col["label_width"]) \
				+ (GROUP_GAP if col["last"] else COLUMN_GAP)
	var radius := maxf(RING_MIN, length / deg_to_rad(ARC_SPAN))
	var parts: Array = [{"name": "Floor", "type": "plane", "size": [2.0 * radius + 2.4, 2.0 * radius + 2.4],
			"position": [0, 0, 0], "material": {"color": FLOOR_COLOUR}}]
	var s := INTRO_WIDTH * 0.5
	parts.append(_placed({"name": "About", "type": "text", "text": intro, "size": [INTRO_LINE],
			"text_options": {"color": LABEL_COLOUR, "max_width": INTRO_WIDTH}}, s, radius,
			Vector3(0, ROW_TOP - PITCH, 0)))
	s = INTRO_WIDTH + GROUP_GAP
	var names := {}
	for i in columns.size():
		var col: Dictionary = columns[i]
		var w := float(col["width"])
		var items: Array = col["items"]
		for r in items.size():
			var it: Dictionary = items[r]
			for p: Dictionary in it["parts"]:
				var q := p.duplicate(true)
				q["name"] = _unique(str(p.get("name", it["label"])), names)
				parts.append(_placed(q, s + w * 0.5, radius, Vector3(0, ROW_TOP - r * PITCH, 0)))
		# The column's labels, one text part, left-aligned: rows -1 (the title) or 0 to the last.
		var first := -1 if col["title"] else 0
		var y := ROW_TOP - (first + items.size() - 1) * 0.5 * PITCH
		parts.append(_placed({"name": _unique("Labels %d" % (i + 1), names), "type": "text", "text": col["text"],
				"size": [LINE], "text_options": {"color": LABEL_COLOUR, "align": "left"}}, s + w + LABEL_GAP, radius,
				Vector3(0, y, 0)))
		s += w + LABEL_GAP + float(col["label_width"]) + (GROUP_GAP if col["last"] else COLUMN_GAP)
	return parts


## A column's label lines: the title (if any), then each sample's name, LINES_PER_ROW lines apart.
static func _label_lines(items: Array, title: String) -> Array:
	var out: Array = []
	var gap: Array = []
	for i in LINES_PER_ROW - 1:
		gap.append(BLANK)
	if title != "":
		out.append(title)
		out.append_array(gap)
	for i in items.size():
		out.append(str(items[i]["label"]))
		if i < items.size() - 1:
			out.append_array(gap)
	return out


## The widest line in metres, at the labels' size (assistant_room.gd _text's font and scale).
static func _text_width(lines: Array) -> float:
	var font := AssistantRoom.text_font(false)
	var px := LINE / maxf(font.get_height(AssistantRoom.TEXT_FONT_PX), 1.0)
	var w := 0.0
	for l: String in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, AssistantRoom.TEXT_FONT_PX).x * px)
	return snappedf(w + 0.02, 0.01)


## A part from its sample's frame into the room's: `along` metres along the ring of `radius` from ARC_FROM, facing the
## seat; `offset` within that frame (the row's height). An orbit's centre and axis go along.
static func _placed(p: Dictionary, along: float, radius: float, offset: Vector3) -> Dictionary:
	var a := deg_to_rad(ARC_FROM) + along / radius
	var frame := Basis(Vector3.UP, -a)
	var origin := Vector3(sin(a) * radius, 0, -cos(a) * radius) + frame * offset
	var q := p.duplicate(true)
	var local: Array = p.get("position", [0, 0, 0])
	var at := origin + frame * Vector3(float(local[0]), float(local[1]), float(local[2]))
	q["position"] = _r3(at)
	var rot: Array = p.get("rotation", [0, 0, 0])
	var basis := frame * Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])),
			deg_to_rad(float(rot[2]))))
	var e := basis.get_euler()
	q["rotation"] = _r3(Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)))
	if q.get("motion") is Dictionary and str(q["motion"].get("type", "")) == "orbit":
		var c: Array = q["motion"]["center"]
		var ax: Array = q["motion"]["axis"]
		q["motion"]["center"] = _r3(origin + frame * Vector3(float(c[0]), float(c[1]), float(c[2])))
		q["motion"]["axis"] = _r3(frame * Vector3(float(ax[0]), float(ax[1]), float(ax[2])))
	return q


static func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## A part name the schema takes (letters, digits, space, - and _), not used before in the room.
static func _unique(n: String, names: Dictionary) -> String:
	var base := ""
	for c in n:
		if c.is_valid_identifier() or c.is_valid_int() or c in " -_":
			base += c
	base = base.strip_edges().left(36)
	var out := base
	var i := 2
	while names.has(out):
		out = "%s %d" % [base, i]
		i += 1
	names[out] = true
	return out


## The pictures on the Surfaces samples, made here: four coloured quarters with a white arrow pointing up (which way
## up each face shows it), or a ring on transparent pixels (a cut-out).
static func _picture(cut: bool) -> String:
	return "cutout.png" if cut else "picture.png"


static func _png(cut: bool) -> PackedByteArray:
	var n := 128
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var quarters := [Color("#d05a4a"), Color("#4a8ad0"), Color("#5ab070"), Color("#d0b04a")]
	for y in n:
		for x in n:
			var c: Color
			if cut:
				var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length()
				c = Color("#f0e0b0") if d < n * 0.46 and d > n * 0.26 else Color(0, 0, 0, 0)
			else:
				c = quarters[(1 if x >= n / 2 else 0) + (2 if y >= n / 2 else 0)]
				# The arrow: a triangle over a stem, pointing up.
				var u := absf(x - n * 0.5 + 0.5)
				if (y >= 24 and y < 64 and u < (y - 24) * 0.7) or (y >= 64 and y < 104 and u < 10):
					c = Color.WHITE
			img.set_pixel(x, y, c)
	return img.save_png_to_buffer()


# --- Budget ----------------------------------------------------------------------------------------------------------

## What a room uses, estimated: cost units (as the room editor counts them), draw calls (a mesh each, a second pass, a
## box's second surface, a model's parts, a text and its panel, a widget's quad, the sky, contact shadows, and the
## shadow casters again with the key light's shadows), triangles, text parts, widgets, lights.
static func budget(doc: Dictionary) -> Dictionary:
	var cost := RoomSchema.room_cost(doc)
	var draws := 0
	var triangles := 0
	var texts := 0
	var widgets := 0
	var casters := 0
	var contact := 0
	var light: Dictionary = doc.get("light", {})
	for p: Dictionary in doc.get("parts", []):
		var type := str(p["type"])
		var m: Dictionary = p.get("material", {}) if p.get("material") is Dictionary else {}
		var tris := 0
		var n := 1
		var model_parts := 1
		match type:
			"model":
				var o := ObjectLibrary.get_object(str(p.get("object", "")))
				tris = int(o.get("triangles", 0))
				model_parts = maxi((o.get("parts", []) as Array).size(), 1)
				n = model_parts
			"text":
				texts += 1
				tris = str(p["text"]).replace(BLANK, "").replace("\n", "").replace(" ", "").length() * 2
				if (p.get("text_options", {}) as Dictionary).get("background") != null:
					n += 1
					tris += 2
			_:
				tris = _mesh_triangles(p)
		if str(m.get("uv", "")) == "front_only":
			n += 1
		var fx: Variant = m.get("effect")
		if fx is Dictionary and int(EffectLibrary.entry(str(fx.get("name", ""))).get("passes", 1)) > 1:
			n += 1
		if p.has("widget"):
			widgets += 1
			if str(p["widget"]) != "screen_glow":
				n += 1
		cost += RoomSchema.part_cost(p, tris if type == "model" else 0, model_parts)
		draws += n
		triangles += tris
		if type != "text" and not (fx is Dictionary and str(EffectLibrary.entry(str(fx["name"]))["blend"]) in
				["alpha", "add"]):
			casters += n
		if bool(light.get("contact_shadows", true)) and RoomSchema.stands_on_floor(p):
			contact += 1
	draws += contact
	if (doc.get("sky", {}) as Dictionary).size() > 0:
		draws += 1
		triangles += _mesh_triangles({"type": "sphere", "size": [AssistantRoom.SKY_RADIUS * 2.0]})
	var lights := (doc.get("lights", []) as Array).size()
	if light.get("key") is Dictionary:
		lights += 1
		if bool(light["key"].get("shadows", true)):
			draws += casters
	return {"cost": snappedf(cost, 0.1), "draws": draws, "triangles": triangles, "texts": texts, "widgets": widgets,
			"lights": lights, "parts": (doc.get("parts", []) as Array).size()}


static func fits(doc: Dictionary) -> bool:
	var b := budget(doc)
	for k: String in BUDGET:
		if float(b[k]) > float(BUDGET[k]):
			return false
	return b["widgets"] <= int(RoomSchema.LIMITS["widgets"]) and b["parts"] <= int(RoomSchema.LIMITS["parts"])


## The triangles of a shape as the room builder makes it (the engine's primitive meshes, their default detail).
static func _mesh_triangles(p: Dictionary) -> int:
	var size: Array = p.get("size", [1.0])
	var mesh: PrimitiveMesh
	match str(p["type"]):
		"box":
			mesh = BoxMesh.new()
		"sphere":
			var sp := SphereMesh.new()
			sp.radius = float(size[0]) * 0.5
			sp.height = float(size[0])
			mesh = sp
		"cylinder":
			mesh = CylinderMesh.new()
		"plane":
			mesh = PlaneMesh.new()
		_:
			return 0
	var a := mesh.get_mesh_arrays()
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	return idx.size() / 3 if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


# --- Files -----------------------------------------------------------------------------------------------------------

## The index the Room tab reads (scripts/env/showrooms.gd).
static func index(rooms: Array) -> Dictionary:
	var rows: Array = []
	for r: Dictionary in rooms:
		rows.append({"id": r["id"], "name": r["name"], "file": r["file"], "description": r["description"],
				"shows": r["shows"], "budget": r["budget"]})
	return {"version": INDEX_VERSION, "budget": BUDGET, "made_by": "tools/showrooms.gd", "showrooms": rows}


static func _json(v: Variant) -> String:
	return JSON.stringify(v, "\t") + "\n"


## {path relative to Showrooms.DIR: bytes} for everything written.
static func outputs(rooms: Array) -> Dictionary:
	# .gdignore: the editor leaves the folder alone (the app reads the files as they are).
	var out := {Showrooms.INDEX: _json(index(rooms)).to_utf8_buffer(), ".gdignore": PackedByteArray()}
	for r: Dictionary in rooms:
		out[str(r["file"])] = _json(r["doc"]).to_utf8_buffer()
		var dir := str(r["file"]).trim_suffix(".room.json") + ".files"
		for f: String in r["files"]:
			out[dir.path_join(f)] = r["files"][f]
	return out


## What differs between the folder and `rooms`: files missing, changed or no longer made. The JSON files' line ends
## don't count (a Windows checkout may have made them CRLF).
static func differences(rooms: Array) -> Array[String]:
	var out: Array[String] = []
	var want := outputs(rooms)
	for rel: String in want:
		var path := Showrooms.DIR.path_join(rel)
		var have := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
		if rel.ends_with(".json"):
			have = have.get_string_from_utf8().replace("\r\n", "\n").to_utf8_buffer()
		if not FileAccess.file_exists(path):
			out.append("missing %s" % rel)
		elif have != want[rel]:
			out.append("changed %s" % rel)
	for rel: String in _on_disk():
		if not want.has(rel):
			out.append("no longer made %s" % rel)
	return out


static func _on_disk() -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(Showrooms.DIR):
		return out
	for f in DirAccess.get_files_at(Showrooms.DIR):
		if f.ends_with(".json") or f == ".gdignore":
			out.append(f)
	for d in DirAccess.get_directories_at(Showrooms.DIR):
		for f in DirAccess.get_files_at(Showrooms.DIR.path_join(d)):
			out.append(d.path_join(f))
	return out


## Writes every file and removes the ones no longer made. "" or the error.
static func write(rooms: Array) -> String:
	DirAccess.make_dir_recursive_absolute(Showrooms.DIR)
	var want := outputs(rooms)
	for rel: String in _on_disk():
		if not want.has(rel):
			DirAccess.remove_absolute(Showrooms.DIR.path_join(rel))
	for rel: String in want:
		var path := Showrooms.DIR.path_join(rel)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return "can't write %s" % path
		f.store_buffer(want[rel])
		f.close()
	for d in DirAccess.get_directories_at(Showrooms.DIR):
		if DirAccess.get_files_at(Showrooms.DIR.path_join(d)).is_empty():
			DirAccess.remove_absolute(Showrooms.DIR.path_join(d))
	return ""
