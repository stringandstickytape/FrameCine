extends "res://scripts/env/systems/kit/builder.gd"

## The kit (docs/environments.md, "The kit"): modular pieces placed along a builder's slots. A document lists the
## pieces; each names a piece, a slot of the room's builder (or none: then `at` is in the room's frame), which of the
## slot's places (or every one), and an offset, a turn, a scale and a size in it. Pieces (kit/pieces.gd): balcony
## fronts, niches holding an urn, a lion or an obelisk (never a figure), urns, lions, obelisks, columns, courtyard
## façades, a castle gate round the screen, a tin booth, a neon snack bar, a drive-in's screen tower, bougainvillea,
## ivy, ferns, a swirling carpet over the builder's floor, a plasterboard partition, curved bands on a wall; and
## furniture (kit/furniture.gd): a desk, a computer, a video recorder whose clock flashes 12:00, a sideboard, a
## standard lamp, a rug, a coffee table.
## All the pieces share a few meshes, one surface a material: a baked one (PieceStatic), an unbaked one for rounded
## shapes and leaves (PieceSoft), the lamp shades (PieceLamps), the glows (windows, a booth's window, the video
## recorders' clocks: PieceDisplay) and each neon sign. The builder's slots come
## from its slots(); the auditorium has none of its own, so the kit works them out from its parameters (side_walls,
## proscenium, screen, rear_wall, floor, corners, ceiling, balcony).
## Its physics boxes exist once it is built (they follow the builder's slots): collision_shapes(), no static form.

const Pieces := preload("res://scripts/env/systems/kit/pieces.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")

static func spec() -> Dictionary:
	return {
		"kind": "kit",
		"description": "Modular pieces along a builder's slots: balcony fronts, niches with an urn, a lion or an "
				+ "obelisk, columns, courtyard façades, a castle gate round the screen, a tin booth, a neon snack bar, "
				+ "a screen tower, bougainvillea, ivy, ferns, a swirling carpet, a plasterboard partition, curved bands; "
				+ "furniture: a desk, a computer, a video recorder flashing 12:00, a sideboard, a standard lamp, a rug, "
				+ "a coffee table.",
		"params": PARAMS,
		"requires": ["light"],
		"provides": ["collision", "bake"],
		"cost": {"draws": 12, "triangles": 25000, "lights": 0, "particles": 0, "texture_mb": 12},
	}


const PIECE_FIELDS := {
	"piece": {"type": "enum", "values": Pieces.PIECES, "description": "which piece"},
	"slot": {"type": "string", "max": 32, "description": "the builder's slot (none: `at` is in the room's frame)"},
	"index": {"type": "int", "min": -1, "max": 64, "description": "which of the slot's places; -1: every one"},
	"at": {"type": "vec3", "min": -200.0, "max": 200.0, "description": "an offset in the slot's frame (or the room's)"},
	"yaw": {"type": "float", "min": -360.0, "max": 360.0, "description": "a turn about the vertical, degrees"},
	"scale": {"type": "float", "min": 0.2, "max": 5.0, "description": "a scale"},
	"size": {"type": "vec3", "min": 0.0, "max": 60.0, "description": "width, height, depth (0: the slot's or its own)"},
	"holds": {"type": "enum", "values": ["urn", "lion", "obelisk", "none"],
			"description": "what a niche holds (a computer: none leaves out its monitor, a telly is its screen)"},
	"colour": {"type": "color", "description": "the piece's main colour"},
	"accent": {"type": "color",
			"description": "a second colour (curves' second band, a snack bar's canopy, a rug's border, a lamp's pole)"},
	"text": {"type": "string", "max": 12,
			"description": "a neon sign's words (our letters: A B C D E F I K L N O P R S T U W, space)"},
	"target": {"type": "string", "max": 32, "description": "the carpet's node (the builder's Floor by default)"},
}
const PARAMS := {
	"builder": {"type": "string", "max": 32, "default": "",
			"description": "the id of the builder whose slots the pieces use (empty: the room's first builder)"},
	"pieces": {"type": "list", "max": 48, "default": [], "of": {"type": "object", "fields": PIECE_FIELDS},
			"description": "the pieces: {piece, slot, index, at, yaw, scale, size, holds, colour, accent, text, target}"},
	"stone": {"type": "material", "default": {"library": "smooth_concrete", "color": [0.7, 0.64, 0.54]},
			"description": "statues, columns, the castle gate"},
	"plaster": {"type": "material", "default": {"library": "rough_plaster", "color": [0.8, 0.68, 0.52]},
			"description": "façades, niches, balcony fronts, the snack bar, the partition, curves"},
	"wood": {"type": "material", "default": {"library": "oak_veneer", "color": [0.36, 0.22, 0.12]},
			"description": "shutters, rails, posts, doors"},
	"tin": {"type": "material", "default": {"library": "brushed_steel", "color": [0.58, 0.58, 0.56], "tiling": 0.5},
			"description": "the booth (corrugated), canopies"},
	"roof": {"type": "material", "default": {"library": "red_brick", "color": [0.62, 0.32, 0.2]},
			"description": "a façade's roof tiles"},
	"iron": {"type": "material", "default": {"library": "dark_metal", "color": [0.07, 0.07, 0.07]},
			"description": "balcony rails, the portcullis, arrow slits, handles, a video recorder, a lamp's base"},
	"plastic": {"type": "material", "default": {"library": "pale_laminate", "color": [0.78, 0.74, 0.64]},
			"description": "a computer's case, monitor and keyboard"},
	"fabric": {"type": "material", "default": {"library": "woven_carpet", "color": [0.5, 0.22, 0.14]},
			"description": "a rug"},
	"lamp_colour": {"type": "color", "default": [1.0, 0.76, 0.48], "description": "a standard lamp's shade, lit"},
	"display_colour": {"type": "color", "default": [0.35, 1.0, 0.78],
			"description": "a video recorder's clock (it flashes 12:00; Flickering lights off holds it lit)"},
	"leaves": {"type": "color", "default": [0.2, 0.36, 0.13], "description": "leaves (ivy darker, ferns lighter)"},
	"flowers": {"type": "color", "default": [0.8, 0.12, 0.48], "description": "bougainvillea's bracts"},
	"neon": {"type": "color", "default": [1.0, 0.32, 0.5], "description": "a neon sign's colour"},
	"window_colour": {"type": "color", "default": [1.0, 0.72, 0.42], "description": "lit windows' colour"},
	"glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
			"description": "how bright the lit windows, the booth's window and neon signs are"},
}
## Pieces that take their slot's size when the entry gives none (the others keep their own size).
const FILLS: Array[String] = ["facade", "curves", "ivy", "bougainvillea", "balcony_front", "partition"]


## What the pieces draw into (pieces.gd's ctx).
class Ctx:
	const P := preload("res://scripts/env/systems/kit/pieces.gd")
	const Proc := preload("res://scripts/env/systems/kit/procedural.gd")
	var kit: Node
	var s: RefCounted
	var u: RefCounted
	var lit: RefCounted
	var shapes: Array = []
	var glows := {}
	var signs: Array = []
	var lamps: Array = []
	var carpeted: Array = []
	var screen := {}
	var room: Node3D
	var rng := RandomNumberGenerator.new()
	var _mats := {}

	## A material of the kit's (a material parameter, or a colour parameter for leaves and flowers), in this colour
	## (null: the parameter's), with a pattern of procedural.gd; made once each.
	func mat(key: String, colour: Variant = null, pattern := "") -> Material:
		var c: Color = colour_of(key) if colour == null else P._to_color(colour)
		var k := "%s %s %s" % [key, c, pattern]
		if _mats.has(k):
			return _mats[k]
		var d: Dictionary
		if key == "leaves":
			d = {"library": "felt"}
		elif key == "flowers":
			d = {"library": "velvet"}
		else:
			d = (kit.params[key] as Dictionary).duplicate()
		d["color"] = [c.r, c.g, c.b]
		var m: ShaderMaterial = kit._light.from_param(d)
		if pattern != "":
			Proc.apply(m, pattern, c)
		_mats[k] = m
		return m

	## A lamp shade's glow in this colour (the light system's lamp material, house group: the ritual dims it), made
	## once a colour.
	func shade(colour: Color) -> Material:
		var k := "shade %s" % colour
		if not _mats.has(k):
			_mats[k] = kit._lamp(colour, 1.1, 1.0, "house")
		return _mats[k]

	func colour_of(key: String) -> Color:
		var v: Variant = kit.params[key]
		if v is Dictionary:
			return P._to_color((v as Dictionary).get("color", [0.5, 0.5, 0.5]))
		return P._to_color(v)


var _ctx: Ctx
var _glow_m: Array = []
var _problems: Array[String] = []
## The video recorders' clocks: their material, the flash's time, the level now (0 dark .. 1 lit).
var _display_m: ShaderMaterial
var _blink_t := 0.0
var _blink := 1.0
## The clock flashes once a second, each change eased over about a fifth of a second (slower than the
## photosensitivity ceiling's fade, env_checks.gd MIN_FADE).
const BLINK_HZ := 1.0
const DISPLAY_ENERGY := 1.6


static func seat_slots_for(_p: Dictionary) -> Array:
	return []


func slots() -> Dictionary:
	return {}


func screen() -> Dictionary:
	return {}


## The pieces' physics boxes (once built: they follow the builder's slots).
func collision_shapes() -> Array:
	return _ctx.shapes if _ctx != null else []


## What could not be placed (an unknown slot, an index past the slot's places), for the assistant and the tests.
func problems() -> Array[String]:
	return _problems


func _builder() -> Node:
	var bid := str(params["builder"])
	if bid != "":
		return host.system(bid)
	return host.system_of_kind("builder")


## The builder's slots: its own, or the auditorium's worked out here.
func builder_slots() -> Dictionary:
	var b := _builder()
	if b == null:
		return {}
	if b.has_method("slots"):
		return b.slots()
	if b.get_script() == Auditorium:
		return _auditorium_slots(b.params)
	return {}


func _auditorium_slots(p: Dictionary) -> Dictionary:
	var l := Auditorium.layout(p)
	var stage_top := float(p["stage_top"])
	var out := {}
	var walls: Array = []
	var z := l.lo.z + 3.0
	while z < l.hi.z - 1.5:
		var y := l.aisle_floor(z)
		for s: float in [-1.0, 1.0]:
			var into := Vector3(-s, 0, 0)
			walls.append({"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into),
					Vector3(l.hi.x if s > 0.0 else l.lo.x, y, z)), "size": [2.0, l.hi.y - y, 0.3]})
		z += 2.5
	out["side_walls"] = walls
	var width := l.hi.x - l.lo.x
	out["proscenium"] = [{"transform": Transform3D(Basis(), Vector3(0, stage_top, l.lo.z)),
			"size": [width, l.hi.y - stage_top, 1.0]}]
	var back_y := l.row_floor(-l.rows_back)
	out["rear_wall"] = [{"transform": Transform3D(Basis(Vector3.UP, PI), Vector3(0, back_y, l.hi.z)),
			"size": [width, l.hi.y - back_y, 0.3]}]
	var front_z := l.lo.z + float(p["stage_depth"]) + 0.8
	var corners: Array = []
	for s: float in [-1.0, 1.0]:
		var into := Vector3(-s, 0, 0.4).normalized()
		corners.append({"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into),
				Vector3(s * (l.hi.x - 0.8), l.lo.y, front_z)), "size": [1.0, 1.0, 1.0]})
	out["corners"] = corners
	out["floor"] = [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, l.lo.y, front_z)),
			"size": [width, 2.0, 0.0]}]
	out["ceiling"] = [{"transform": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, l.hi.y, (l.lo.z + l.hi.z) * 0.5)),
			"size": [width, l.hi.z - l.lo.z, 0.0]}]
	var rows: Array = Auditorium._balcony_rows(p, l)
	if not rows.is_empty():
		var bz := float(rows[0][0]) - l.depth * 0.5
		out["balcony"] = [{"transform": Transform3D(Basis(Vector3.UP, PI), Vector3(0, float(rows[0][1]), bz - 0.17)),
				"size": [width - 0.2, 1.0, 0.25]}]
	return out


## The room's screen: its transform in the room, its size, the floor under it (the builder's proscenium slot).
func _screen_info(slots: Dictionary) -> Dictionary:
	var anchor: Transform3D = room.call("get_screen_anchor") if room.has_method("get_screen_anchor") else Transform3D()
	var size := Vector2(float(room.get("default_screen_width")), float(room.get("default_screen_width")) * 9.0 / 16.0)
	var d: Variant = room.get("doc")
	if d is Dictionary and (d as Dictionary).get("screen") is Dictionary:
		var s: Array = d["screen"].get("size", [])
		if s.size() > 1:
			size = Vector2(float(s[0]), float(s[1]))
	var out := {"xf": anchor, "size": size}
	if slots.has("proscenium") and not (slots["proscenium"] as Array).is_empty():
		out["floor"] = (slots["proscenium"][0]["transform"] as Transform3D).origin.y
	return out


func build() -> void:
	_ctx = Ctx.new()
	_ctx.kit = self
	_ctx.s = RoomMesh.new()
	_ctx.u = RoomMesh.new()
	_ctx.lit = RoomMesh.new()
	_ctx.room = room
	_ctx.rng.seed = 1928
	var slots := builder_slots()
	_ctx.screen = _screen_info(slots)
	for i in (params["pieces"] as Array).size():
		var e: Dictionary = params["pieces"][i]
		var piece := str(e.get("piece", ""))
		if not (piece in Pieces.PIECES):
			_problems.append("piece %d: unknown piece %s" % [i, piece])
			continue
		for xf_size: Array in _placements(i, e, piece, slots):
			Pieces.build(piece, _ctx, xf_size[0], xf_size[1], e)
	_add_static("PieceStatic", _ctx.s)
	_add_unbaked("PieceSoft", _ctx.u)
	_add_lamps("PieceLamps", _ctx.lit)
	var glow := float(params["glow"])
	if _ctx.glows.has("display"):
		var c := color_param("display_colour")
		var mi := _add_picture("PieceDisplay", _ctx.glows["display"], Procedural.gradient(c, c), Color(1, 1, 1),
				DISPLAY_ENERGY * glow, "accent")
		_display_m = mi.mesh.surface_get_material(0)
	if _ctx.glows.has("window"):
		var c := color_param("window_colour")
		var mi := _add_picture("PieceWindows", _ctx.glows["window"], Procedural.gradient(c * 0.6, c), Color(1, 1, 1),
				0.9 * glow, "accent")
		_glow_m.append([mi.mesh.surface_get_material(0), 0.9])
	if _ctx.glows.has("booth"):
		var mi := _add_picture("PieceBooth", _ctx.glows["booth"], Procedural.gradient(Color(0.9, 0.85, 0.7),
				Color(0.5, 0.45, 0.35)), Color(1, 1, 1), 1.2 * glow, "booth")
		_glow_m.append([mi.mesh.surface_get_material(0), 1.2])
	var neon := color_param("neon")
	for k in _ctx.signs.size():
		var sg: Array = _ctx.signs[k]
		var mi := _add_picture("Sign%d" % k, [sg[0]], Procedural.letters(str(sg[1]), neon, Color(0.02, 0.02, 0.03)),
				Color(1, 1, 1), 1.8 * glow, "signs")
		_glow_m.append([mi.mesh.surface_get_material(0), 1.8])
	for k in mini(_ctx.lamps.size(), 4):
		var l: Array = _ctx.lamps[k]
		var strength := float(l[2]) if l.size() > 2 else 1.0
		_light.add_lamp(l[0], (l[1] as Color) * float(_light.params["lamp_energy"]) * 0.5 * strength, -1.0)
		_bake_omni("KitLamp%d" % k, l[0], 5.0 * sqrt(strength), 0.6 * strength, l[1])


## The clocks flash 12:00: lit half a second, dark half a second, each change eased (no hard cut); held lit while
## the room's Flickering lights is off.
func tick(delta: float) -> void:
	super(delta)
	if _display_m == null:
		return
	_blink_t += delta
	var steady: bool = host != null and host.has_method("setting") and host.setting("flicker") == false
	_blink = 1.0 if steady else clampf(0.5 + 0.8 * sin(TAU * BLINK_HZ * _blink_t), 0.0, 1.0)
	_display_m.set_shader_parameter("energy", DISPLAY_ENERGY * float(params["glow"]) * _group_level("accent") * _blink)


## The clocks' level now: 1 lit, 0 dark (tests).
func clock_level() -> float:
	return _blink


## Where a piece goes: [transform, size] for each place (one, or every place of its slot).
func _placements(i: int, e: Dictionary, piece: String, slots: Dictionary) -> Array:
	var out: Array = []
	var own := U.v3(Pieces.SIZES[piece])
	var given := U.v3(e.get("size", [0, 0, 0]))
	var at := U.v3(e.get("at", [0, 0, 0]))
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(float(e.get("yaw", 0.0)))), at)
	var k := float(e.get("scale", 1.0))
	var slot_name := str(e.get("slot", ""))
	if slot_name == "" or piece in ["castle_gate", "screen_tower", "carpet"]:
		var size := Vector3(given.x if given.x > 0.0 else own.x, given.y if given.y > 0.0 else own.y,
				given.z if given.z > 0.0 else own.z)
		out.append([turn.scaled_local(Vector3.ONE * k), size])
		return out
	if not slots.has(slot_name):
		_problems.append("piece %d (%s): the builder has no slot %s (it has %s)" % [i, piece, slot_name,
				", ".join(slots.keys())])
		return out
	var places: Array = slots[slot_name]
	var index := int(e.get("index", 0))
	var chosen: Array = places if index < 0 else ([places[index]] if index < places.size() else [])
	if chosen.is_empty():
		_problems.append("piece %d (%s): %s has %d places, not %d" % [i, piece, slot_name, places.size(), index + 1])
	for place: Dictionary in chosen:
		var ss := U.v3(place.get("size", [0, 0, 0]))
		var fill := piece in FILLS
		var size := Vector3(given.x if given.x > 0.0 else (ss.x if fill and ss.x > 0.0 else own.x),
				given.y if given.y > 0.0 else (ss.y if fill and ss.y > 0.0 else own.y),
				given.z if given.z > 0.0 else (ss.z if fill and ss.z > 0.0 else own.z))
		out.append([((place["transform"] as Transform3D) * turn).scaled_local(Vector3.ONE * k), size])
	return out


func _param_changed(param: String, value: Variant) -> void:
	if param == "glow":
		for g: Array in _glow_m:
			(g[0] as ShaderMaterial).set_shader_parameter("energy", float(g[1]) * float(value))
