extends "res://scripts/env/systems/kit/builder.gd"

## The kit (docs/environments.md, "The kit"): modular pieces placed along a builder's slots. A document lists the
## pieces; each names a piece, a slot of the room's builder (or none: then `at` is in the room's frame), which of the
## slot's places (or every one), and an offset, a turn, a scale and a size in it. Pieces (kit/pieces.gd): balcony
## fronts, niches holding an urn, a lion or an obelisk (never a figure), urns, lions, obelisks, columns, courtyard
## façades, a castle gate round the screen, a tin booth, a neon snack bar, a drive-in's screen tower, bougainvillea,
## ivy, ferns, a swirling carpet over the builder's floor, a plasterboard partition, curved bands on a wall; and
## furniture (kit/furniture.gd): a desk, a computer, a video recorder whose clock flashes 12:00, a sideboard, a
## standard lamp, a rug, a coffee table; and the TV rooms' dressing (kit/dressing.gd): bunting, a tea set, sandwiches,
## a stool, a channel dial, a soundbar, a floor lamp, a glass table (its top in PieceGlass, see-through), a media unit;
## and the moderne hall's (kit/streamline.gd, since 2026-11-08): its walls and coved ceiling, a stepped proscenium, an
## organ console (its coves in PieceCove, its clock in PieceClock); and the Palace of Culture's (kit/palace_culture.gd,
## since 2026-11-08): its board-marked concrete hall, wall mosaics, coffered ceiling and field of globes; and the
## Flagship's (kit/flagship.gd, since 2026-11-08): its faceted acoustic hall, starlight ceiling and the rows' arms; and
## the Pink Palace's (kit/pink_palace.gd, since 2026-11-08): a hall inside a great shell, its fluted vault and
## scalloped rings lit from hidden lamps (PieceCove), mirrors, a buttoned balcony, a sunburst dome with a chandelier.
## All the pieces share a few meshes, one surface a material: a baked one (PieceStatic), an unbaked one for rounded
## shapes and leaves (PieceSoft), the lamp shades (PieceLamps), the glows (windows, a booth's window, the video
## recorders' clocks: PieceDisplay) and each neon sign. The builder's slots come
## from its slots(); the auditorium has none of its own, so the kit works them out from its parameters (side_walls,
## proscenium, screen, rear_wall, floor, corners, ceiling, balcony).
## Its physics boxes exist once it is built (they follow the builder's slots): collision_shapes(), no static form.

const Pieces := preload("res://scripts/env/systems/kit/pieces.gd")
const Courtyard := preload("res://scripts/env/systems/kit/courtyard.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const WINDOW_SHADER := preload("res://shaders/env_courtyard_window.gdshader")
const WATER_SHADER := preload("res://shaders/env_fountain_water.gdshader")

static func spec() -> Dictionary:
	return {
		"kind": "kit",
		"description": "Modular pieces along a builder's slots: balcony fronts, niches with an urn, a lion or an "
				+ "obelisk, columns, courtyard façades, a castle gate round the screen, a tin booth, a neon snack bar, "
				+ "a Mediterranean courtyard (houses with balconies, towers, loggias and lit windows, a palace gate "
				+ "with drapes, lanterns, a lion on a pedestal, cypresses, palms and pines), a 1930s moderne hall (a "
				+ "ceiling of glowing coves, faience and chrome speed bands, a stepped proscenium round a rising sun, "
				+ "organ grilles, a clock, an illuminated organ console on its lift), a ruined picture house open to the "
				+ "moonlit sky (broken roof and trusses, fallen plaster, a gilt proscenium with a torn curtain, a fallen "
				+ "chandelier, a birch, ivy, ferns and wildflowers), a 1970s palace of culture's hall (board-marked "
				+ "concrete, wall mosaics of glass and gold tesserae, a coffered ceiling, a field of opal globes, oak "
				+ "acoustic slats), a modern premium auditorium (faceted acoustic walls washed in amber, a ceiling of "
				+ "baffles with starlight, a velvet-masked curved screen in a slatted proscenium, armrests with "
				+ "cupholders, lit row letters, a glass balustrade), a dream palace inside a great scallop shell (a "
				+ "fluted vault fanning from a sunburst dome with a chandelier of glass shells, scalloped rings round "
				+ "the screen, mirrors, a wave frieze, a buttoned velvet balcony), "
				+ "a screen tower, bougainvillea, ivy, ferns, a swirling carpet, a plasterboard partition, curved bands; "
				+ "furniture: a desk, a computer, a video recorder flashing 12:00, a sideboard, a standard lamp, a rug, "
				+ "a coffee table; dressing: bunting, a tea set, sandwiches, a stool, a channel dial, a soundbar, a "
				+ "floor lamp, a glass table, a media unit.",
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
	# Since 2026-11-08, for the courtyard's pieces (kit/courtyard.gd): which of a piece's parts it has, and its own
	# seed so two houses of one recipe differ.
	"features": {"type": "list", "max": 16, "of": {"type": "enum", "values": Courtyard.FEATURES},
			"description": "a courtyard piece's parts (a house: balcony, loggia, tower, pergola, oriel, exit, ...)"},
	"seed": {"type": "int", "min": 0, "max": 100000, "description": "the piece's own variation (a house's windows)"},
	# Since 2026-11-08 (the Streamline 1937's aisles): which pattern a carpet shows (the swirls by default).
	"pattern": {"type": "enum", "values": Procedural.PATTERNS, "description": "a carpet's pattern (swirl_carpet if none)"},
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
			"description": "a rug, a soundbar's cloth front"},
	"china": {"type": "material", "default": {"library": "white_marble", "color": [0.94, 0.92, 0.88]},
			"description": "a tea set, plates (each part coloured on it)"},
	"cloth": {"type": "material", "default": {"library": "linen", "color": [1.0, 1.0, 1.0]},
			"description": "bunting, sandwiches (each pennant, the bread and the filling coloured on it)"},
	"glass_colour": {"type": "color", "default": [0.62, 0.74, 0.74], "description": "a glass table's top"},
	"lamp_colour": {"type": "color", "default": [1.0, 0.76, 0.48], "description": "a standard lamp's shade, lit"},
	"display_colour": {"type": "color", "default": [0.35, 1.0, 0.78],
			"description": "a video recorder's clock (it flashes 12:00; Flickering lights off holds it lit)"},
	"leaves": {"type": "color", "default": [0.2, 0.36, 0.13], "description": "leaves (ivy darker, ferns lighter)"},
	"flowers": {"type": "color", "default": [0.8, 0.12, 0.48], "description": "bougainvillea's bracts"},
	"neon": {"type": "color", "default": [1.0, 0.32, 0.5], "description": "a neon sign's colour"},
	"window_colour": {"type": "color", "default": [1.0, 0.72, 0.42], "description": "lit windows' colour"},
	"glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
			"description": "how bright the lit windows, the booth's window and neon signs are"},
	# Since 2026-11-08, for the Atmospheric 1928's courtyard (kit/courtyard.gd); the other rooms keep their defaults.
	"gilt": {"type": "material", "default": {"library": "brass", "color": [0.78, 0.6, 0.3]},
			"description": "gilding: a palace gate's mouldings, an organ's grille, finials"},
	"drapes": {"type": "material", "default": {"library": "velvet", "color": [0.42, 0.06, 0.07], "pleats": 3.0,
			"pleat_depth": 0.6}, "description": "a palace gate's drapes and swags"},
	"bake_lamps": {"type": "int", "min": 0, "max": 24, "default": 4,
			"description": "how many of the pieces' lamps light the room (a stand-in lamp while there is room for one, "
			+ "a hidden light for the bake)"},
	"night": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
			"description": "the courtyard's houses going to bed: 0 every window lit, 1 most of them down to an ember; "
			+ "each window goes out at its own moment (a cue moves it over some seconds)"},
	"ember": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.15, "live": true, "brightness": true,
			"description": "what a courtyard window that has gone out still shows (a lamp turned low behind a curtain)"},
	"water_motion": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "motion": {"max": 1.0},
			"description": "how fast a fountain's water runs and ripples (the Motion setting scales it)"},
	# Since 2026-11-08, for the Ice cinema's candles (kit/ice_hall.gd); the other rooms' pieces keep steady.
	"flicker": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "flicker": true,
			"steady": 0.0, "brightness": true,
			"description": "how much the pieces' candle flames waver (slowly; Flickering lights holds them)"},
	# Since 2026-11-08, for the Streamline 1937's moderne hall (kit/streamline.gd); the other rooms keep their
	# defaults. Coves: plaster washed by hidden lamps (shaders/env_cove.gdshader), their colour live.
	"cove": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
			"description": "how bright the coves' hidden lamps are (times the house lamps' level)"},
	"cove_colour": {"type": "color", "default": [1.0, 0.74, 0.42], "live": true,
			"description": "the coves' light (a setting or a cue moves it)"},
	"cove_film_colour": {"type": "color", "default": [1.0, 0.74, 0.42], "live": true,
			"description": "the coves' light in the film (bind it to film.colour)"},
	"cove_film": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
			"description": "0: the coves in cove_colour; 1: in cove_film_colour"},
	"faience": {"type": "material", "default": {"library": "white_marble", "color": [0.9, 0.84, 0.68]},
			"description": "glazed faience: bands, a balcony front, a console's body (it shines: a clear glaze)"},
	"chrome": {"type": "material", "default": {"library": "brushed_steel", "color": [0.82, 0.82, 0.84]},
			"description": "chrome or nickel trim: rails, bands, brackets (it reflects the room)"},
	"group": {"type": "string", "max": 32, "default": "",
			"description": "the pieces' meshes under one node of this name (a motion system moves them together: an "
			+ "organ console on its lift); empty: each in the room"},
	# Since 2026-11-08, for the Palace of Culture 1974's mosaics (kit/palace_culture.gd); the other rooms have none.
	"mosaic": {"type": "material", "default": {"library": "white_marble", "color": [1.0, 1.0, 1.0], "tiling": 0.6},
			"description": "a wall mosaic's bed: its maps under the tesserae (the mosaic shader draws the tesserae)"},
	"mosaic_glint": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
			"description": "how much the mosaics' tesserae glint (the lamps' and the picture's light, as the head moves)"},
	"mosaic_wash": {"type": "float", "min": 0.0, "max": 4.0, "default": 1.6,
			"description": "the lamp line's wash down the mosaics (times the house lamps' level)"},
	# Since 2026-11-08, for the Flagship's starlight ceiling (kit/flagship.gd); the other rooms have none (0).
	"starlight": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
			"description": "a starlight ceiling's pinholes before the film (0: off); they fade with the house lamps"},
	"starlight_film": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
			"description": "the share of the starlight kept while the film plays (the house lamps out)"},
	# Since 2026-11-08, for the Pink Palace (kit/pink_palace.gd): the gilt and the mirrors see a rose hall, not the
	# Streamline's walnut and jade. The defaults are the Streamline's.
	"reflect_wall": {"type": "color", "default": [0.16, 0.12, 0.09],
			"description": "what the reflecting materials see round their horizon (the walls), at full house light"},
	"reflect_ground": {"type": "color", "default": [0.02, 0.03, 0.025],
			"description": "what they see below (the floor), at full house light"},
}
## Pieces that take their slot's size when the entry gives none (the others keep their own size).
const FILLS: Array[String] = ["facade", "curves", "ivy", "bougainvillea", "balcony_front", "partition"]


## What the pieces draw into (pieces.gd's ctx).
class Ctx:
	const P := preload("res://scripts/env/systems/kit/pieces.gd")
	const Proc := preload("res://scripts/env/systems/kit/procedural.gd")
	const Refl := preload("res://scripts/env/systems/kit/reflect.gd")
	var kit: Node
	var s: RefCounted
	var u: RefCounted
	var lit: RefCounted
	## Glass (a glass table's top): see-through, unbaked.
	var glass: RefCounted
	var shapes: Array = []
	var glows := {}
	var signs: Array = []
	var lamps: Array = []
	var carpeted: Array = []
	var screen := {}
	var room: Node3D
	var rng := RandomNumberGenerator.new()
	var _mats := {}
	## The courtyard's pieces (kit/courtyard.gd, since 2026-11-08): the floor under a point of the room (the builder's
	## stage, pit and stepped aisles; an invalid Callable: the piece's own foot), the builder's parameters, the lit
	## windows of the houses (a baked mesh: their glow lights the reveals and sills in the bake) and a fountain's water.
	var ground := Callable()
	var builder_params := {}
	var windows: RefCounted
	var water: RefCounted
	## Floodlights for the bake only: [from, towards, colour, energy, reach, half angle (degrees)] (a palace gate lit
	## from the stage's lip).
	var spots: Array = []
	## The Ice cinema's hall (kit/ice_hall.gd, since 2026-11-08): its meshes and candles over its pieces, or null.
	var ice: Object = null
	## Reclaimed's ruined hall (kit/reclaimed.gd, since 2026-11-08): its meshes over its pieces, or null.
	var ruin: Object = null
	## The moderne hall's pieces (kit/streamline.gd, since 2026-11-08): the coves' plaster (vertex colour: its colour,
	## alpha the cove's light on it), clock faces ([centre, half across, half up, facing]), footlights (stand-in lamps
	## round the stage in the cove's colour, live: [at, cone cosine (-1 all round), strength]), and lights for the bake
	## only ([at, colour, energy, reach]).
	var cove: RefCounted
	var clocks: Array = []
	var footlights: Array = []
	var glow_lights: Array = []
	## Halls that draw meshes of their own over their pieces (kit/palace_culture.gd, since 2026-11-08): each an object
	## with finish(kit), called once every piece has drawn, and tick(delta).
	var halls: Array = []

	## A soft (unbaked) tinted material that reflects (kit/reflect.gd): metal 0 a clear glaze or lacquer, 1 chrome.
	func shiny(key: String, metal: float, amount: float, roughness := 0.1) -> Material:
		var k := "shiny %s %s %s %s" % [key, metal, amount, roughness]
		if _mats.has(k):
			return _mats[k]
		var d: Dictionary = (kit.params[key] as Dictionary).duplicate()
		d["color"] = [1.0, 1.0, 1.0]
		var m: ShaderMaterial = kit._light.from_param(d, true)
		m.set_shader_parameter("instance_tint", true)
		Refl.make(m, metal, amount, roughness)
		kit._reflect.append(m)
		_mats[k] = m
		return m

	## The floor's height under a point of the room (the piece's foot when the builder gives none).
	func ground_at(p: Vector3, fallback: float) -> float:
		return float(ground.call(p)) if ground.is_valid() else fallback

	## An unbaked part's material: it keeps the fill and the stand-in lamps once a lightmap is on (the light system's
	## instanced materials), coloured per vertex (RoomMesh.colour, linear; white: the parameter's own colour) when
	## tinted. pattern: procedural.gd's, over the library's maps.
	func soft(key: String, tinted := true, pattern := "") -> Material:
		return _variant(key, true, tinted, pattern)

	## A baked part's material coloured per vertex (RoomMesh.colour, linear), with a pattern of procedural.gd.
	func tinted(key: String, pattern := "") -> Material:
		return _variant(key, false, true, pattern)

	func _variant(key: String, unbaked: bool, tinted_: bool, pattern: String) -> Material:
		var k := "%s %s %s %s" % ["soft" if unbaked else "baked", key, tinted_, pattern]
		if _mats.has(k):
			return _mats[k]
		var d: Dictionary
		if key == "leaves":
			d = {"library": "felt", "color": [1.0, 1.0, 1.0]}
		else:
			d = (kit.params[key] as Dictionary).duplicate()
		if tinted_:
			d["color"] = [1.0, 1.0, 1.0]
		var m: ShaderMaterial = kit._light.from_param(d, unbaked)
		# Tinted: the maps' mean is white (the library's colour option, Procedural.apply's), so the vertex colour is
		# the colour shown on average, the pattern's detail kept.
		if pattern != "":
			Proc.apply(m, pattern, Color(1, 1, 1) if tinted_ else RoomSchemaRef.to_color(d.get("color", "#b0b0b0")))
		if tinted_:
			m.set_shader_parameter("instance_tint", true)
		_mats[k] = m
		return m

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
## The courtyard's windows and a fountain's water (kit/courtyard.gd), when a piece has drawn them.
var _window_m: ShaderMaterial
var _water_m: ShaderMaterial
## The water's own clock (seconds x water_motion x the Motion setting), so a still setting stops it where it is.
var _water_t := 0.0
## The moderne hall's (kit/streamline.gd): the coves' material, the clocks' face, the reflecting materials (glaze,
## lacquer, chrome: their world is set each frame), the footlights' stand-in lamps ([index, strength]), the node the
## meshes go under (`group`), and the seconds since the clock's hands were last set.
var _cove_m: ShaderMaterial
var _clock_m: ShaderMaterial
var _reflect: Array[ShaderMaterial] = []
var _footlights: Array = []
var _group_node: Node3D
var _clock_t := 1.0
var _footlight_key := Color(-1, -1, -1)
var _footlight_wait := 0.0
const Reflect := preload("res://scripts/env/systems/kit/reflect.gd")
const COVE_SHADER := preload("res://shaders/env_cove.gdshader")
const CLOCK_SHADER := preload("res://shaders/env_clock.gdshader")
const SkySys := preload("res://scripts/env/systems/sky.gd")
## The footlights' energy (stand-in lamps: they light the festoon and the console in the cove's colour).
const FOOTLIGHT_ENERGY := 5.0
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
	_ctx.glass = RoomMesh.new()
	_ctx.room = room
	_ctx.rng.seed = 1928
	_ctx.windows = RoomMesh.new()
	_ctx.water = RoomMesh.new()
	_ctx.cove = RoomMesh.new()
	_window_m = null
	_water_m = null
	_cove_m = null
	_clock_m = null
	_reflect.clear()
	_footlights.clear()
	var b := _builder()
	if b != null:
		_ctx.builder_params = b.params
		if b.get_script() == Auditorium:
			var l := Auditorium.layout(b.params)
			var stage_end := l.lo.z + float(b.params["stage_depth"])
			var stage_top := float(b.params["stage_top"])
			_ctx.ground = func(p: Vector3) -> float:
				return stage_top if p.z < stage_end else l.aisle_floor(p.z)
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
	_add_glass("PieceGlass", _ctx.glass, color_param("glass_colour"), 0.22)
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
	# A projection booth's ports in a courtyard house (kit/courtyard.gd): the projector's, its lens glowing in the dark
	# booth, and the viewing ports beside it, dim (the booth group: the signs' level).
	if _ctx.glows.has("port"):
		var mi := _add_picture("PiecePort", _ctx.glows["port"], Auditorium.port_picture(true), Color(1, 1, 1),
				1.3 * glow, "booth")
		_glow_m.append([mi.mesh.surface_get_material(0), 1.3])
	if _ctx.glows.has("port_dim"):
		var mi := _add_picture("PiecePortDim", _ctx.glows["port_dim"], Auditorium.port_picture(false), Color(1, 1, 1),
				1.3 * glow, "booth")
		_glow_m.append([mi.mesh.surface_get_material(0), 1.3])
	_add_moderne_meshes()
	var neon := color_param("neon")
	for k in _ctx.signs.size():
		var sg: Array = _ctx.signs[k]
		var mi := _add_picture("Sign%d" % k, [sg[0]], Procedural.letters(str(sg[1]), neon, Color(0.02, 0.02, 0.03)),
				Color(1, 1, 1), 1.8 * glow, "signs")
		_glow_m.append([mi.mesh.surface_get_material(0), 1.8])
	for k in mini(_ctx.lamps.size(), int(params["bake_lamps"])):
		var l: Array = _ctx.lamps[k]
		var strength := float(l[2]) if l.size() > 2 else 1.0
		_light.add_lamp(l[0], (l[1] as Color) * float(_light.params["lamp_energy"]) * 0.5 * strength, -1.0)
		_bake_omni("KitLamp%d" % k if id == "kit" else "KitLamp%d_%s" % [k, id], l[0], 5.0 * sqrt(strength),
				0.6 * strength, l[1])
	for k in _ctx.spots.size():
		var sp: Array = _ctx.spots[k]
		var l := SpotLight3D.new()
		l.name = "KitSpot%d" % k if id == "kit" else "KitSpot%d_%s" % [k, id]
		var from: Vector3 = sp[0]
		var dir: Vector3 = (sp[1] as Vector3) - from
		l.transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.normalized().y) < 0.99
				else Vector3.FORWARD), from)
		l.light_color = sp[2]
		l.light_energy = float(sp[3])
		l.spot_range = float(sp[4])
		l.spot_angle = float(sp[5])
		_light.add_bake_light(l)
	_add_courtyard_meshes()
	if _ctx.ice != null:
		_ctx.ice.finish(self)
	if _ctx.ruin != null:
		_ctx.ruin.finish(self)
	for h: Object in _ctx.halls:
		h.call("finish", self)


## The courtyard's lit windows (baked: their glow lights the reveals, sills and shutters round them in the bake) and
## a fountain's water (kit/courtyard.gd). Each window's size, kind and moment of going out ride in its vertex colour.
func _add_courtyard_meshes() -> void:
	if _window_m != null:
		_add_static("PieceRoomWindows", _ctx.windows)
	if _water_m != null:
		_add_unbaked("PieceWater", _ctx.water)


## The moderne hall's meshes (kit/streamline.gd): the coves (PieceCove: their own shader, never baked), the clocks
## (PieceClock), the footlights (stand-in lamps first, so they always have a place), the bake's own lights.
func _add_moderne_meshes() -> void:
	if _cove_m != null:
		_add_unbaked("PieceCove", _ctx.cove)
		_update_cove()
	if not _ctx.clocks.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for q: Array in _ctx.clocks:
			var c: Vector3 = q[0]
			var u: Vector3 = q[1]
			var v: Vector3 = q[2]
			var n: Vector3 = q[3]
			# A round face: a fan of 32 (UV 0..1 over the square round it).
			var sides := 32
			for k in sides:
				var a0 := TAU * k / sides
				var a1 := TAU * (k + 1) / sides
				var pts := [Vector2.ZERO, Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1))]
				# Godot draws the side where the corners run clockwise.
				if u.cross(v).dot(n) > 0.0:
					pts = [pts[0], pts[2], pts[1]]
				for p: Vector2 in pts:
					st.set_normal(n)
					st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 - p.y * 0.5))
					st.add_vertex(c + u * p.x + v * p.y)
		_clock_m = ShaderMaterial.new()
		_clock_m.shader = CLOCK_SHADER
		_clock_m.set_shader_parameter("house_reference", float(room.get("ambient_level")))
		var mesh := st.commit()
		mesh.surface_set_material(0, _clock_m)
		var mi := _add_mesh("PieceClock", mesh)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_set_clock()
	for f: Array in _ctx.footlights:
		var i: int = _light.add_lamp(f[0], Color(0, 0, 0), float(f[1]))
		if i >= 0:
			_footlights.append([i, float(f[2])])
	_update_footlights()
	for k in _ctx.glow_lights.size():
		var g: Array = _ctx.glow_lights[k]
		_bake_omni("KitGlow%d" % k if id == "kit" else "KitGlow%d_%s" % [k, id], g[0], float(g[3]), float(g[2]), g[1])


## The coves' plaster (shaders/env_cove.gdshader), made when a piece first draws a cove.
func cove_material() -> ShaderMaterial:
	if _cove_m == null:
		_cove_m = ShaderMaterial.new()
		_cove_m.shader = COVE_SHADER
		_cove_m.set_shader_parameter("house_reference", float(room.get("ambient_level")))
		# The coves are high and pale: they take less of the film's spill than the walls, or the ceiling would glow in
		# the picture's colours over the film.
		_cove_m.set_shader_parameter("spill", float(_light.params["spill"]) * 0.6)
		_cove_m.set_shader_parameter("mottle", SkySys.noise_texture())
		var t: Array = _light.params["fill_top"]
		var b: Array = _light.params["fill_bottom"]
		_cove_m.set_shader_parameter("sky_top", Vector3(float(t[0]), float(t[1]), float(t[2])))
		_cove_m.set_shader_parameter("sky_bottom", Vector3(float(b[0]), float(b[1]), float(b[2])))
	return _cove_m


## The coves' colour now: cove_colour toward cove_film_colour by cove_film.
func cove_colour_now() -> Color:
	return color_param("cove_colour").lerp(color_param("cove_film_colour"), clampf(float(params["cove_film"]), 0.0, 1.0))


func _update_cove() -> void:
	if _cove_m == null:
		return
	_cove_m.set_shader_parameter("glow_colour", cove_colour_now())
	_cove_m.set_shader_parameter("glow", float(params["cove"]) * _group_level("house"))


## The footlights' stand-in lamps in the cove's colour, at the house lamps' level.
func _update_footlights() -> void:
	if _footlights.is_empty():
		return
	var c := cove_colour_now() * FOOTLIGHT_ENERGY * float(params["cove"]) * _group_level("house")
	for f: Array in _footlights:
		_light.set_lamp(int(f[0]), c * float(f[1]))


## The clocks' hands from the real time (the room's own clock: the system's).
func _set_clock() -> void:
	if _clock_m == null:
		return
	var t := Time.get_time_dict_from_system()
	var minutes := float(t["minute"]) + float(t["second"]) / 60.0
	var hours := fmod(float(t["hour"]), 12.0) + minutes / 60.0
	_clock_m.set_shader_parameter("minute_angle", TAU * minutes / 60.0)
	_clock_m.set_shader_parameter("hour_angle", TAU * hours / 12.0)
	_clock_m.set_shader_parameter("energy", 1.3 * _group_level("house"))


## The clock's hands now, radians clockwise from twelve: [hour, minute] (tests).
func clock_hands() -> Array:
	if _clock_m == null:
		return []
	return [float(_clock_m.get_shader_parameter("hour_angle")), float(_clock_m.get_shader_parameter("minute_angle"))]


## The coves now (tests): {colour, glow}.
func cove_state() -> Dictionary:
	if _cove_m == null:
		return {}
	return {"colour": _cove_m.get_shader_parameter("glow_colour"), "glow": float(_cove_m.get_shader_parameter("glow"))}


## The reflecting materials' world (kit/reflect.gd): an indoor one, the plaster's warm tone round the horizon, the
## coves' light above, the carpet below, the screen with the picture, and one glint: the proscenium's glow.
func _update_reflect() -> void:
	if _reflect.is_empty() or _ctx == null:
		return
	var house := _group_level("house")
	var cove := cove_colour_now() * float(params["cove"]) * house
	var wall := color_param("reflect_wall") * (0.15 + 0.85 * house)
	var screen: Dictionary = _ctx.screen
	var xf: Transform3D = screen.get("xf", Transform3D())
	var size: Vector2 = screen.get("size", Vector2(12, 5))
	var sc := xf.origin
	var playing: bool = host != null and str(host.timeline.state) in ["playing", "starting", "credits"]
	# The picture in the chrome at a third: a full one glints in the colours of every cut at the edge of vision.
	Reflect.update(_reflect, null, room, xf, size, sc + Vector3(0.0, size.y * 0.5 + 2.2, 0.6), cove * 0.6,
			Vector2(size.x * 0.8, 1.2), 0.33 if playing else 0.0)
	for m: ShaderMaterial in _reflect:
		m.set_shader_parameter("refl_zenith", cove * 0.35 + wall * 0.3)
		m.set_shader_parameter("refl_horizon", wall)
		m.set_shader_parameter("refl_ground", color_param("reflect_ground") * (0.3 + 0.7 * house))


## The pieces' meshes under one node when `group` is given (an organ console on its lift moves as one).
func _add_mesh(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var g := str(params.get("group", ""))
	if g == "":
		return super(node_name, mesh)
	if _group_node == null or not is_instance_valid(_group_node):
		_group_node = Node3D.new()
		_group_node.name = g
		own(_group_node)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_group_node.add_child(mi)
	return mi


## The windows' material (the light system's lamp material, house group, on the courtyard window shader), made when
## a piece first draws a window.
func window_material() -> ShaderMaterial:
	if _window_m == null:
		_window_m = _light.lamp_material(color_param("window_colour"), 1.0, 0.0, "house")
		_window_m.shader = WINDOW_SHADER
		_window_m.set_shader_parameter("house_reference", float(room.get("ambient_level")))
		_window_m.set_shader_parameter("night", float(params["night"]))
		_window_m.set_shader_parameter("ember", float(params["ember"]))
		_window_m.set_shader_parameter("glow", float(params["glow"]))
	return _window_m


## A fountain's water (its own shader: dark water, ripples, the jet's streaks), made when a piece first draws water.
func water_material() -> ShaderMaterial:
	if _water_m == null:
		_water_m = ShaderMaterial.new()
		_water_m.shader = WATER_SHADER
		_water_m.set_shader_parameter("house_reference", float(room.get("ambient_level")))
		_water_m.set_shader_parameter("motion", float(params["water_motion"]))
	return _water_m


## The clocks flash 12:00: lit half a second, dark half a second, each change eased (no hard cut); held lit while
## the room's Flickering lights is off.
func tick(delta: float) -> void:
	super(delta)
	if _ctx != null and _ctx.ice != null:
		_ctx.ice.tick(delta)
	if _ctx != null and _ctx.ruin != null:
		_ctx.ruin.tick(delta)
	if _ctx != null:
		for h: Object in _ctx.halls:
			h.call("tick", delta)
	if _water_m != null:
		_water_t += delta * float(params["water_motion"])
		_water_m.set_shader_parameter("clock", _water_t)
	if _cove_m != null or not _footlights.is_empty() or not _reflect.is_empty():
		# The house lamps' level moves without telling the kit (a cue on the light system): follow it here, the
		# footlights only when they change (each change re-places every lamp).
		_update_cove()
		_update_reflect()
		var key := cove_colour_now() * float(params["cove"]) * _group_level("house")
		_footlight_wait -= delta
		if _footlight_wait <= 0.0 and not key.is_equal_approx(_footlight_key):
			# At most ten times a second: a colour's fade is seconds long.
			_footlight_wait = 0.1
			_footlight_key = key
			_update_footlights()
	if _clock_m != null:
		_clock_t += delta
		if _clock_t >= 1.0:
			_clock_t = 0.0
			_set_clock()
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
	if slot_name == "" or piece in ["castle_gate", "screen_tower", "carpet", "palace_gate"]:
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
	if _window_m != null and param in ["night", "ember", "glow"]:
		_window_m.set_shader_parameter(param, float(value))


## The courtyard's windows now (tests): {night, ember, glow, energy}.
func window_state() -> Dictionary:
	if _window_m == null:
		return {}
	return {"night": float(_window_m.get_shader_parameter("night")),
			"ember": float(_window_m.get_shader_parameter("ember")),
			"energy": float(_window_m.get_shader_parameter("energy"))}
