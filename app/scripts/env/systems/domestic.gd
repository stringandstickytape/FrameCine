extends "res://scripts/env/systems/kit/builder.gd"

## The domestic builder (docs/environments.md, "The builders"): a room in a house. Four walls, a floor, a flat ceiling
## or a low vault, a window with the outside's glow beyond it (or a vista system's view), a door, a fireplace whose
## fire flickers slowly or a radiator under the window, wall lamps, and the screen as a pull-down screen, a screen on
## the wall, a framed painting that rises into the ceiling to show the screen, or a telly on a chest of drawers.
## Styles:
##   plain          a plain sitting room: club chairs, a pull-down screen, a radiator
##   walnut_1962    a private screening room: walnut panelling, a deep carpet, club chairs in two rows, a picture
##                  window (a pool beyond it: a vista), a brick fireplace, brass wall lamps, the painting over the screen
##   bedroom_1993   a child's bedroom: a pillow fort of cushions and a bedsheet on broom handles round the viewer's
##                  cushion, fairy lights along its front, a telly on a chest of drawers, a bed, a radiator under the
##                  window (rain on the pane: a weather system)
##   ice            a room of ice blocks under a low vault, hides on the floor, candles in the walls, the picture on
##                  a smoothed panel of ice, the doorway open to the night
## The telly (`telly`): a deep cabinet, a small portable (a carry handle, an aerial, its knobs at the side) or a thin
## flat panel (always 16:9, on a pedestal foot); on a stand (`telly_stand`): a chest of drawers, a radiogram, a desk, a
## tv_unit (an open shelf under its top for a video recorder) or the wall. The picture stays where screen_size and
## screen_bottom put it: the stand is as tall as the space under the set (stand_width, stand_shift: its width and its
## move sideways under the set).
## Every parameter marked "auto" (an enum's "auto", 0 or -1 for a number, {} for a material, [0, 0] for a size) takes
## the style's value (STYLE_DEFAULTS); a document sets only what it changes.
##   Floor, Walls, Ceiling, Trim, Window (glass), Outside, Door, Fireplace, Fire, Radiator, Lamps, Screen (the screen's
##   own parts), Painting, Telly, Lid and Mirror (a mirror-lid set: scripts/env/mirror_view.gd), Bed, Fort, FortSheet,
##   FairyLights, Seats or Cushions
## Slots for the kit: side_walls, screen, proscenium, floor, ceiling, corners, window, vista, mantel, fort_opening,
## telly_stand (the stand's top), telly_shelf (a video recorder's place under the set).

static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "A room in a house: walls, a window with the outside beyond, a door, a fireplace or a "
				+ "radiator, wall lamps, and the screen as a pull-down screen, a screen on the wall, a painting that "
				+ "rises into the ceiling, or a telly. Styles: a plain sitting room, a 1962 screening room in walnut, "
				+ "a 1993 bedroom with a pillow fort and fairy lights, a room of ice blocks.",
		"params": PARAMS,
		"requires": ["light"],
		"provides": ["seats", "collision", "sound_room", "bake", "slots"],
		"cost": {"draws": 18, "triangles": 13000, "lights": 0, "particles": 0, "texture_mb": 10},
	}


const AUTO_MAT := {}
const PARAMS := {
	"style": {"type": "enum", "values": ["plain", "walnut_1962", "bedroom_1993", "ice"], "default": "plain",
			"description": "the room's style; every parameter left on auto takes the style's value"},
	"half_width": {"type": "float", "min": 0.0, "max": 12.0, "default": 0.0,
			"description": "the room's half width, metres (0: the style's)"},
	"front_z": {"type": "float", "min": -30.0, "max": 0.0, "default": 0.0,
			"description": "z of the wall the screen is at (0: the style's)"},
	"back_z": {"type": "float", "min": 0.0, "max": 30.0, "default": 0.0,
			"description": "z of the wall behind the viewer (0: the style's)"},
	"height": {"type": "float", "min": 0.0, "max": 8.0, "default": 0.0,
			"description": "the walls' height (0: the style's)"},
	"vault_rise": {"type": "float", "min": -1.0, "max": 4.0, "default": -1.0,
			"description": "a low vault over the walls, its rise (0: a flat ceiling; -1: the style's)"},
	"screen": {"type": "enum", "values": ["auto", "projected", "wall", "painting", "telly"], "default": "auto",
			"description": "a pull-down screen, a screen on the wall, a painting that rises to show it, or a telly"},
	"screen_size": {"type": "vec2", "min": 0.0, "max": 8.0, "default": [0.0, 0.0],
			"description": "the picture, width and height ([0, 0]: the style's)"},
	"screen_bottom": {"type": "float", "min": 0.0, "max": 4.0, "default": 0.0,
			"description": "the picture's bottom edge over the floor (0: the style's)"},
	"painting_open": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true,
			"description": "the painting over the screen: 0 down over it, 1 risen into the ceiling (a cue fades it)"},
	"opening_screen": {"type": "bool", "default": false,
			"description": "the telly fills the pillow fort's opening (not live: the fort builds again)"},
	"telly": {"type": "enum", "values": ["cabinet", "portable", "flat_panel", "mirror_lid", "console",
			"rear_projection", "oled"], "default": "cabinet",
			"description": "the telly: a deep cabinet, a small portable, a thin flat panel (16:9), a 1937 mirror-lid "
			+ "set (its tube faces up, the picture seen in the mirror in its open lid), a 1960s console on splayed "
			+ "legs, a big rear projection set, or a very thin OLED panel (16:9). The last four but the OLED stand on "
			+ "the floor (telly_stand does not apply)"},
	"telly_aspect": {"type": "enum", "values": ["auto", "standard", "wide"], "default": "auto",
			"description": "the telly's picture: standard (4:3) or wide (16:9), its height from its width; auto: as "
			+ "screen_size gives it (a flat panel and an OLED always wide)"},
	"telly_doors": {"type": "bool", "default": false,
			"description": "a console's two doors, open and folded back beside the picture"},
	"telly_stand": {"type": "enum", "values": ["chest", "radiogram", "desk", "tv_unit", "wall"], "default": "chest",
			"description": "what the telly stands on: a chest of drawers, a radiogram, a desk, a tv unit with a shelf "
			+ "for a video recorder, or the wall (a flat panel hangs on it, a set sits on a shelf)"},
	"stand_width": {"type": "float", "min": 0.0, "max": 4.0, "default": 0.0,
			"description": "the stand's width, metres (0: its own, a little wider than the set)"},
	"stand_shift": {"type": "float", "min": -3.0, "max": 3.0, "default": 0.0,
			"description": "the stand moved sideways under the set, metres (room for a computer beside it)"},
	"window": {"type": "enum", "values": ["auto", "none", "left", "right", "back"], "default": "auto",
			"description": "the wall with the window"},
	"window_width": {"type": "float", "min": 0.0, "max": 8.0, "default": 0.0,
			"description": "the window's width (0: the style's)"},
	"outside": {"type": "enum", "values": ["glow", "none"], "default": "glow",
			"description": "beyond the window and an open doorway: a soft glow, or nothing (a vista or sky system's)"},
	"outside_top": {"type": "color", "default": [0.12, 0.2, 0.32], "description": "the outside's colour above"},
	"outside_bottom": {"type": "color", "default": [0.3, 0.42, 0.5], "description": "the outside's colour below"},
	"outside_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.5, "live": true, "brightness": true,
			"description": "how bright the outside shows"},
	"door": {"type": "enum", "values": ["auto", "none", "left", "right", "back"], "default": "auto",
			"description": "the wall with the door"},
	"heater": {"type": "enum", "values": ["auto", "none", "fireplace", "radiator"], "default": "auto",
			"description": "a fireplace (the wall across from the window) or a radiator (under the window)"},
	"fire": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true, "brightness": true,
			"description": "the fire's glow (0: not lit)"},
	"lamps": {"type": "int", "min": -1, "max": 4, "default": -1,
			"description": "wall lamps (or candles) on each side wall (-1: the style's)"},
	"lamp_colour": {"type": "color", "default": [1.0, 0.78, 0.52], "description": "the lamps' glow"},
	"ceiling_light": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.35,
			"description": "the ceiling light's baked energy (0: off; a pillow fort has none)"},
	"flicker": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.6, "live": true, "flicker": true,
			"steady": 0.0, "brightness": true,
			"description": "how much the fire, candles and fairy lights waver (slowly; Flickering lights holds them)"},
	"fort": {"type": "enum", "values": ["auto", "on", "off"], "default": "auto",
			"description": "a pillow fort of cushions and a bedsheet round the viewer's seat"},
	"fairy_lights": {"type": "enum", "values": ["auto", "on", "off"], "default": "auto",
			"description": "fairy lights along the fort's front (or the front wall's top without a fort)"},
	"fairy_colour": {"type": "color", "default": [1.0, 0.82, 0.55], "description": "the fairy lights' glow"},
	"fairy_glow": {"type": "float", "min": 0.0, "max": 1.5, "default": 1.0, "live": true, "brightness": true,
			"description": "how bright the fairy lights are, and the light they give (0: off); nothing else follows it"},
	"seat_model": {"type": "enum", "values": ["auto", "club", "cushion", "plush", "director", "folding"],
			"default": "auto", "description": "the seat drawn when the room has no seats system"},
	"rows_front": {"type": "int", "min": -1, "max": 6, "default": -1, "description": "rows in front of the viewer's"},
	"rows_back": {"type": "int", "min": -1, "max": 6, "default": -1, "description": "rows behind the viewer's"},
	"seats_per_row": {"type": "int", "min": 0, "max": 9, "default": 0,
			"description": "seats along a row (odd: one in the middle, the viewer's; 0: the style's)"},
	"seat_pitch": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.0, "description": "seat centres, metres"},
	"row_pitch": {"type": "float", "min": 0.0, "max": 3.0, "default": 0.0, "description": "metres a row"},
	"wall_pattern": {"type": "enum", "values": ["auto", "plain", "ice_blocks", "plasterboard"], "default": "auto",
			"description": "a pattern over the walls' material: none, ice blocks, plasterboard"},
	"walls": {"type": "material", "default": AUTO_MAT, "description": "the walls ({}: the style's)"},
	"floor": {"type": "material", "default": AUTO_MAT, "description": "the floor"},
	"ceiling": {"type": "material", "default": AUTO_MAT, "description": "the ceiling"},
	"trim": {"type": "material", "default": AUTO_MAT,
			"description": "skirting, frames, the door, the telly's stand, the bed's frame"},
	"surround": {"type": "material", "default": AUTO_MAT, "description": "the fireplace and its hearth"},
	"radiator_material": {"type": "material", "default": AUTO_MAT, "description": "the radiator"},
	"screen_surface": {"type": "material", "default": AUTO_MAT, "description": "the screen's white"},
	"telly_material": {"type": "material", "default": AUTO_MAT, "description": "the telly's cabinet or case"},
	"cushions": {"type": "material", "default": AUTO_MAT, "description": "the fort's cushions, the bed's duvet"},
	"sheet": {"type": "material", "default": AUTO_MAT, "description": "the fort's bedsheet"},
	"seat_cover": {"type": "material", "default": AUTO_MAT, "description": "the seats' cover (or the hides)"},
	"seat_frame": {"type": "material", "default": AUTO_MAT, "description": "the seats' frames"},
}

## Each style's values for the parameters left on auto.
const STYLE_DEFAULTS := {
	"plain": {"half_width": 2.6, "front_z": -3.8, "back_z": 2.4, "height": 2.5, "vault_rise": 0.0,
			"screen": "projected", "screen_size": [2.2, 1.24], "screen_bottom": 0.85, "window": "left",
			"window_width": 1.4, "door": "back", "heater": "radiator", "lamps": 0, "fort": "off", "fairy_lights": "off",
			"seat_model": "club", "rows_front": 0, "rows_back": 1, "seats_per_row": 3, "seat_pitch": 0.95,
			"row_pitch": 1.5, "wall_pattern": "plain",
			"walls": {"library": "painted_wall", "color": [0.78, 0.75, 0.68]},
			"floor": {"library": "oak_planks", "color": [0.45, 0.33, 0.22]},
			"ceiling": {"library": "smooth_plaster", "color": [0.88, 0.86, 0.82], "spill": 1.0},
			"trim": {"library": "painted_wall", "color": [0.9, 0.89, 0.86]},
			"surround": {"library": "red_brick", "color": [0.45, 0.3, 0.22]},
			"radiator_material": {"library": "painted_wall", "color": [0.9, 0.9, 0.88]},
			"screen_surface": {"library": "painted_wall", "color": [0.86, 0.86, 0.84], "spill": 0.3},
			"telly_material": {"library": "dark_metal", "color": [0.1, 0.1, 0.1]},
			"cushions": {"library": "corduroy", "color": [0.55, 0.32, 0.25]},
			"sheet": {"library": "linen", "color": [0.78, 0.82, 0.88]},
			"seat_cover": {"library": "melange_fabric", "color": [0.36, 0.42, 0.36]},
			"seat_frame": {"library": "oak_veneer", "color": [0.35, 0.24, 0.15]}},
	"walnut_1962": {"half_width": 3.2, "front_z": -5.2, "back_z": 3.0, "height": 2.7, "vault_rise": 0.0,
			"screen": "painting", "screen_size": [2.6, 1.46], "screen_bottom": 0.95, "window": "left",
			"window_width": 2.6, "door": "back", "heater": "fireplace", "lamps": 2, "fort": "off",
			"fairy_lights": "off", "seat_model": "club", "rows_front": 0, "rows_back": 1, "seats_per_row": 3,
			"seat_pitch": 1.0, "row_pitch": 1.7, "wall_pattern": "plain",
			"walls": {"library": "walnut_veneer", "color": [0.34, 0.21, 0.12]},
			"floor": {"library": "plush_carpet", "color": [0.55, 0.48, 0.36]},
			"ceiling": {"library": "smooth_plaster", "color": [0.86, 0.8, 0.7], "spill": 1.0},
			"trim": {"library": "walnut_veneer", "color": [0.22, 0.13, 0.07]},
			"surround": {"library": "red_brick", "color": [0.5, 0.36, 0.28]},
			"radiator_material": {"library": "painted_wall", "color": [0.9, 0.9, 0.88]},
			"screen_surface": {"library": "painted_wall", "color": [0.86, 0.86, 0.84], "spill": 0.3},
			"telly_material": {"library": "walnut_veneer", "color": [0.3, 0.18, 0.1]},
			"cushions": {"library": "velvet", "color": [0.4, 0.3, 0.2]},
			"sheet": {"library": "linen", "color": [0.8, 0.76, 0.68]},
			"seat_cover": {"library": "brown_leather", "color": [0.36, 0.2, 0.11]},
			"seat_frame": {"library": "walnut_veneer", "color": [0.2, 0.12, 0.07]}},
	"bedroom_1993": {"half_width": 2.6, "front_z": -3.6, "back_z": 2.2, "height": 2.4, "vault_rise": 0.0,
			"screen": "telly", "screen_size": [0.6, 0.45], "screen_bottom": 0.62, "window": "left",
			"window_width": 1.2, "door": "back", "heater": "radiator", "lamps": 0, "fort": "on", "fairy_lights": "on",
			"seat_model": "cushion", "rows_front": 0, "rows_back": 0, "seats_per_row": 3, "seat_pitch": 0.7,
			"row_pitch": 1.0, "wall_pattern": "plain",
			"walls": {"library": "painted_wall", "color": [0.56, 0.66, 0.78]},
			"floor": {"library": "woven_carpet", "color": [0.36, 0.34, 0.42]},
			"ceiling": {"library": "smooth_plaster", "color": [0.88, 0.88, 0.86], "spill": 1.0},
			"trim": {"library": "painted_wall", "color": [0.9, 0.9, 0.88]},
			"surround": {"library": "red_brick", "color": [0.45, 0.3, 0.22]},
			"radiator_material": {"library": "painted_wall", "color": [0.92, 0.92, 0.9]},
			"screen_surface": {"library": "painted_wall", "color": [0.86, 0.86, 0.84], "spill": 0.3},
			"telly_material": {"library": "dark_metal", "color": [0.09, 0.09, 0.1]},
			"cushions": {"library": "corduroy", "color": [0.62, 0.3, 0.28]},
			"sheet": {"library": "linen", "color": [0.72, 0.8, 0.9]},
			"seat_cover": {"library": "melange_fabric", "color": [0.75, 0.6, 0.25]},
			"seat_frame": {"library": "melange_fabric", "color": [0.3, 0.45, 0.6]}},
	"ice": {"half_width": 3.0, "front_z": -6.0, "back_z": 3.0, "height": 2.2, "vault_rise": 1.3,
			"screen": "wall", "screen_size": [3.2, 1.8], "screen_bottom": 0.8, "window": "none",
			"window_width": 1.2, "door": "back", "heater": "none", "lamps": 2, "fort": "off", "fairy_lights": "off",
			"seat_model": "cushion", "rows_front": 1, "rows_back": 2, "seats_per_row": 5, "seat_pitch": 0.75,
			"row_pitch": 1.1, "wall_pattern": "ice_blocks",
			"walls": {"library": "white_marble", "color": [0.5, 0.6, 0.68], "tiling": 1.2},
			"floor": {"library": "rough_plaster", "color": [0.55, 0.6, 0.65]},
			"ceiling": {"library": "white_marble", "color": [0.46, 0.56, 0.64], "tiling": 1.2},
			"trim": {"library": "white_marble", "color": [0.85, 0.92, 0.97]},
			"surround": {"library": "white_marble", "color": [0.85, 0.92, 0.97]},
			"radiator_material": {"library": "white_marble", "color": [0.85, 0.92, 0.97]},
			"screen_surface": {"library": "smooth_plaster", "color": [0.88, 0.92, 0.95], "spill": 0.3},
			"telly_material": {"library": "dark_metal", "color": [0.1, 0.1, 0.1]},
			"cushions": {"library": "felt", "color": [0.45, 0.36, 0.28]},
			"sheet": {"library": "linen", "color": [0.8, 0.76, 0.68]},
			"seat_cover": {"library": "felt", "color": [0.42, 0.33, 0.25]},
			"seat_frame": {"library": "felt", "color": [0.5, 0.45, 0.4]}},
}
## Numbers whose auto is -1 (0 is a value of theirs); the others' auto is 0.
const AUTO_NEGATIVE: Array[String] = ["vault_rise", "lamps", "rows_front", "rows_back"]
## The fort round the viewer's seat: its half width, its front (the opening) and back, the sheet's height there.
const FORT_HALF := 1.3
const FORT_FRONT := -0.9
const FORT_BACK := 1.1
const FORT_TOP_FRONT := 1.55
const FORT_TOP_BACK := 1.35
const FORT_WALL := 0.56
const DOOR_SIZE := Vector2(0.86, 2.02)
## A form's picture when the document gives none (the style's is a cabinet's): a portable, a 32 inch flat panel, a
## mirror-lid set's 5:4 picture (a 15 inch tube), a 1960s console's 23 inch tube, a 50 inch rear projection (4:3; wide:
## REAR_WIDE), a 55 inch OLED.
const TELLY_SIZES := {"portable": [0.3, 0.225], "flat_panel": [0.8, 0.45], "mirror_lid": [0.3, 0.24],
		"console": [0.48, 0.36], "rear_projection": [1.016, 0.762], "oled": [1.21, 0.68]}
const REAR_WIDE := [1.107, 0.623]
## The forms that stand on the floor (no stand), and their picture's bottom when the document gives none.
const FLOOR_FORMS: Array[String] = ["mirror_lid", "console", "rear_projection"]
const TELLY_BOTTOMS := {"mirror_lid": 0.98, "console": 0.62, "rear_projection": 0.55}
## The mirror-lid set: the picture (the tube's reflection) this far out from the front wall, its bottom this far over
## the cabinet's top; the lid at 45 degrees, its frame's width; the top board's thickness, and how far under the top
## the tube's face lies (under the board, 3 mm clear). The hinge is TUBE_SINK further out than the picture and the
## tube TUBE_SINK further out still, so the sunken face's reflection is the picture's place (mirror_view.gd draws the
## film on the face and reflects it).
const MIRROR_HINGE := 0.07
const LID_GAP := 0.05
const LID_FRAME := 0.035
const TOP_BOARD := 0.025
const TUBE_SINK := TOP_BOARD + 0.003
## The OLED panel's depth (its electronics' bulge included) and its bezel.
const OLED_DEPTH := 0.03
const OLED_BEZEL := 0.008
## The rear projection's depth at the floor and over the picture's bottom (it slopes back).
const REAR_DEPTH := 0.62
const REAR_TOP_DEPTH := 0.36
## The flat panel: its depth, the speaker strip under the picture, the pedestal between it and its stand.
const FLAT_DEPTH := 0.07
const FLAT_STRIP := 0.05
const PEDESTAL := 0.1
## The stands under a set (but the chest, as it always was): [width beyond the set's, least width, least depth];
## their back against the front wall, their front at the set's (a flat panel's pedestal set back on it).
const STANDS := {"radiogram": [0.7, 1.5, 0.45], "desk": [0.6, 1.1, 0.7], "tv_unit": [0.3, 1.0, 0.45]}
const Furniture := preload("res://scripts/env/systems/kit/furniture.gd")
const MirrorView := preload("res://scripts/env/mirror_view.gd")


# --- From parameters alone ----------------------------------------------------------------------------------------

static func _auto(k: String, v: Variant) -> bool:
	if v is String:
		return v == "auto"
	if v is Dictionary:
		return (v as Dictionary).is_empty()
	if v is Array:
		return (v as Array).all(func(x: Variant) -> bool: return float(x) == 0.0)
	if v is float or v is int:
		return float(v) < 0.0 if k in AUTO_NEGATIVE else float(v) == 0.0
	return v == null


## The parameters with every auto one given the style's value.
static func resolved(p: Dictionary) -> Dictionary:
	var out := p.duplicate()
	var s: Dictionary = STYLE_DEFAULTS.get(str(p.get("style", "plain")), STYLE_DEFAULTS["plain"])
	var form := str(p.get("telly", "cabinet"))
	for k: String in s:
		if _auto(k, p.get(k)):
			out[k] = s[k]
			if k == "screen_size" and TELLY_SIZES.has(form):
				out[k] = TELLY_SIZES[form]
				if form == "rear_projection" and str(p.get("telly_aspect", "auto")) == "wide":
					out[k] = REAR_WIDE
	if str(out.get("screen", "")) == "telly" and TELLY_BOTTOMS.has(form) and _auto("screen_bottom", p.get("screen_bottom")):
		out["screen_bottom"] = TELLY_BOTTOMS[form]
	return out


static func _fort(p: Dictionary) -> bool:
	return str(p["fort"]) == "on"


static func _box(p: Dictionary) -> AABB:
	var hw := float(p["half_width"])
	var fz := float(p["front_z"])
	return AABB(Vector3(-hw, 0.0, fz), Vector3(hw * 2.0, float(p["height"]) + float(p["vault_rise"]),
			float(p["back_z"]) - fz))


## A wall's frame: [origin (its bottom corner), along (unit), normal (into the room), length].
static func _wall(p: Dictionary, side: String) -> Array:
	var hw := float(p["half_width"])
	var fz := float(p["front_z"])
	var bz := float(p["back_z"])
	match side:
		"left":
			return [Vector3(-hw, 0, fz), Vector3.BACK, Vector3.RIGHT, bz - fz]
		"right":
			return [Vector3(hw, 0, bz), Vector3.FORWARD, Vector3.LEFT, bz - fz]
		"back":
			return [Vector3(-hw, 0, bz), Vector3.RIGHT, Vector3.FORWARD, hw * 2.0]
	return [Vector3(-hw, 0, fz), Vector3.RIGHT, Vector3.BACK, hw * 2.0]


static func _on_wall(p: Dictionary, side: String, along: float, y: float, out := 0.0) -> Vector3:
	var w := _wall(p, side)
	return (w[0] as Vector3) + (w[1] as Vector3) * along + Vector3.UP * y + (w[2] as Vector3) * out


## The window: [side, Rect2(along, up)] or [] without one.
static func _window(p: Dictionary) -> Array:
	var side := str(p["window"])
	if side == "none":
		return []
	var w := float(p["window_width"])
	var length := float(_wall(p, side)[3])
	var centre := length * 0.5
	if side == "left":
		centre = (float(p["front_z"]) * 0.42) - float(p["front_z"])
	elif side == "right":
		centre = float(p["back_z"]) - float(p["front_z"]) * 0.42
	var sill := 0.9
	var top := minf(float(p["height"]) - 0.3, 2.2)
	if str(p["style"]) == "walnut_1962":
		sill = 0.6
	w = minf(w, length - 1.0)
	return [side, Rect2(centre - w * 0.5, sill, w, top - sill)]


static func _door(p: Dictionary) -> Array:
	var side := str(p["door"])
	if side == "none":
		return []
	var length := float(_wall(p, side)[3])
	var h := minf(DOOR_SIZE.y, float(p["height"]) - 0.15)
	var along := 0.5 + DOOR_SIZE.x * 0.5
	if side == "right":
		along = 0.6 + DOOR_SIZE.x * 0.5
	elif side == "left":
		along = length - 0.6 - DOOR_SIZE.x * 0.5
	return [side, Rect2(along - DOOR_SIZE.x * 0.5, 0.0, DOOR_SIZE.x, h)]


## The fireplace's wall: across from the window's.
static func _fire_side(p: Dictionary) -> String:
	return "left" if str(p["window"]) == "right" else "right"


## The chimney breast: [centre, size] in the room, and its wall's along coordinate.
static func _breast(p: Dictionary) -> Array:
	var side := _fire_side(p)
	var hw := float(p["half_width"])
	var z := float(p["front_z"]) * 0.32
	var x := (hw - 0.225) * (1.0 if side == "right" else -1.0)
	return [Vector3(x, float(p["height"]) * 0.5, z), Vector3(0.45, float(p["height"]), 1.6)]


static func _seat_style(p: Dictionary) -> String:
	match str(p["seat_model"]):
		"club":
			return "club"
		"cushion":
			return "cushion"
	return "chair"


static func seat_slots_for(given: Dictionary) -> Array:
	var p := resolved(given)
	var out: Array = []
	for r in range(-int(p["rows_back"]), int(p["rows_front"]) + 1):
		out.append_array(U.row(-r * float(p["row_pitch"]), 0.0, int(p["seats_per_row"]), float(p["seat_pitch"]), r,
				_seat_style(p)))
	return out


static func layout(p: Dictionary) -> SeatList:
	return SeatList.new(seat_slots_for(p))


## The picture's place: [centre, size].
static func _picture(p: Dictionary) -> Array:
	var size := U.v2(p["screen_size"])
	var fz := float(p["front_z"])
	var bottom := float(p["screen_bottom"])
	match str(p["screen"]):
		"telly":
			var form := str(p.get("telly", "cabinet"))
			var aspect := str(p.get("telly_aspect", "auto"))
			if aspect == "wide" or (aspect == "auto" and form in ["flat_panel", "oled"]):
				size.y = size.x * 9.0 / 16.0
			elif aspect == "standard":
				size.y = size.x * 0.75
			if form == "mirror_lid":
				# The picture is the tube's face seen in the lid's mirror: its reflection stands upright over the
				# hinge's line, LID_GAP over the cabinet's top.
				return [Vector3(0.0, bottom + size.y * 0.5, fz + MIRROR_HINGE), size]
			if form in FLOOR_FORMS:
				return [Vector3(0.0, bottom + size.y * 0.5, fz + 0.05 + _set_depth(form, size)), size]
			if _fort(p) and bool(p["opening_screen"]):
				# The telly fills the fort's opening: the picture as big as fits in it (its own shape kept), just
				# beyond it.
				var open := Vector2(FORT_HALF * 2.0 - 0.3, FORT_TOP_FRONT - 0.2 - 0.35)
				var k := minf(open.x / size.x, open.y / size.y)
				size *= k
				return [Vector3(0.0, 0.35 + open.y * 0.5, FORT_FRONT - 0.35), size]
			if str(p.get("telly_stand", "chest")) == "wall":
				# On the wall: the set's back against it (a flat panel's bracket, a set's shelf).
				return [Vector3(0.0, bottom + size.y * 0.5, fz + _set_depth(form, size) + 0.03), size]
			return [Vector3(0.0, bottom + size.y * 0.5, fz + 0.5), size]
		"projected":
			return [Vector3(0.0, bottom + size.y * 0.5, fz + 0.12), size]
		"painting":
			return [Vector3(0.0, bottom + size.y * 0.5, fz + 0.06), size]
	return [Vector3(0.0, bottom + size.y * 0.5, fz + 0.02), size]


static func screen_for(given: Dictionary) -> Dictionary:
	var p := resolved(given)
	var pic := _picture(p)
	var c: Vector3 = pic[0]
	var s: Vector2 = pic[1]
	return {"center": [c.x, c.y, c.z], "size": [s.x, s.y]}


## A set's depth front to back for its picture.
static func _set_depth(form: String, s: Vector2) -> float:
	match form:
		"portable":
			return clampf(s.x, 0.24, 0.42)
		"flat_panel":
			return FLAT_DEPTH
		"oled":
			return OLED_DEPTH
		"console":
			return clampf(s.x * 0.9, 0.4, 0.6)
		"rear_projection":
			return REAR_DEPTH
		"mirror_lid":
			# From the cabinet's back (3 cm behind the picture) to its front (the tube and a margin before it).
			return maxf(0.03 + TUBE_SINK + s.y + LID_GAP + 0.08, 0.42)
	return clampf(s.x * 0.75, 0.35, 1.2)


## The telly and its stand from the parameters alone: {pic [centre, size], form, stand, bezel, depth, foot (the set's
## bottom over the floor), top (the stand's top), body [centre, size] (the set's outer box), stand_box [centre, size]
## ([]: none), shelf [origin, room] (a video recorder's place: the middle of its foot, and the room there)}.
static func _telly(p: Dictionary) -> Dictionary:
	var pic := _picture(p)
	var c: Vector3 = pic[0]
	var s: Vector2 = pic[1]
	var form := str(p.get("telly", "cabinet"))
	var stand := str(p.get("telly_stand", "chest"))
	var depth := _set_depth(form, s)
	var bezel: Vector2
	var outer: Vector2
	var mid_y: float
	var cx := 0.0
	match form:
		"portable":
			# The knobs' panel on the picture's right.
			bezel = Vector2(maxf(0.035, s.x * 0.08), maxf(0.035, s.y * 0.1))
			var side := maxf(0.06, s.x * 0.22)
			outer = Vector2(s.x + bezel.x * 2.0 + side, s.y + bezel.y * 2.4)
			cx = side * 0.5
			mid_y = c.y - bezel.y * 0.2
		"flat_panel":
			bezel = Vector2(0.035, 0.035)
			outer = Vector2(s.x + bezel.x * 2.0, s.y + bezel.y * 2.0 + FLAT_STRIP)
			mid_y = c.y - FLAT_STRIP * 0.5
		"oled":
			bezel = Vector2(OLED_BEZEL, OLED_BEZEL)
			outer = s + bezel * 2.0
			mid_y = c.y
		"console":
			# The picture over a speaker's grille and the knobs, on splayed legs.
			bezel = Vector2(0.08, 0.06)
			outer = Vector2(s.x + bezel.x * 2.0, s.y + bezel.y + 0.26)
			mid_y = c.y + (bezel.y - 0.26) * 0.5
		"rear_projection":
			# From the floor to just over the picture.
			bezel = Vector2(0.06, 0.06)
			var top_y := c.y + s.y * 0.5 + bezel.y
			outer = Vector2(s.x + bezel.x * 2.0, top_y)
			mid_y = top_y * 0.5
		"mirror_lid":
			# A cabinet from the floor to the tube's face, its top.
			var face := c.y - s.y * 0.5 - LID_GAP
			bezel = Vector2.ZERO
			# Wide enough that its mirror shows the picture's corners to seats well to the side.
			outer = Vector2(maxf(s.x + 0.45, 0.7), face)
			mid_y = face * 0.5
		_:
			bezel = Vector2(maxf(0.06, s.x * 0.1), maxf(0.06, s.y * 0.12))
			outer = Vector2(s.x + bezel.x * 2.0, s.y + bezel.y * 2.6)
			mid_y = c.y - bezel.y * 0.3
	var floor_form := form in FLOOR_FORMS
	if floor_form:
		stand = "floor"
	var foot := mid_y - outer.y * 0.5
	var pedestal := form in ["flat_panel", "oled"] and stand != "wall"
	var top := foot - (PEDESTAL if pedestal else 0.0)
	var body_z := c.z - depth * 0.5
	if form == "mirror_lid":
		body_z = c.z - 0.03 + depth * 0.5
	var out := {"pic": pic, "form": form, "stand": stand, "bezel": bezel, "depth": depth, "foot": foot, "top": top,
			"pedestal": pedestal, "body": [Vector3(cx, mid_y, body_z), Vector3(outer.x, outer.y, depth)],
			"stand_box": [], "shelf": []}
	if form == "mirror_lid":
		# The tube's face in the cabinet's top, under its board (its picture's width, as deep as the picture is tall),
		# and the lid: hinged along the back of the top, open at 45 degrees, long enough that its mirror shows the
		# whole face. A face TUBE_SINK down reflects TUBE_SINK further back (a 45 degree mirror), so the hinge and the
		# face both stand TUBE_SINK further out, and the face's reflection is the picture again.
		out["tube"] = [Vector3(0.0, outer.y - TUBE_SINK, c.z + TUBE_SINK + LID_GAP + s.y * 0.5), s]
		out["lid"] = {"hinge": Vector3(0.0, outer.y, c.z + TUBE_SINK), "length": sqrt(2.0) * (s.y + LID_GAP) + 0.1,
				"width": outer.x - 0.02}
	if form == "console":
		# The legs' room under the body.
		out["legs"] = [Vector3(cx, foot * 0.5, body_z), Vector3(outer.x, foot, depth)]
	if floor_form:
		out["shelf"] = _shelf(out, cx, outer, c)
		return out
	var shift := float(p.get("stand_shift", 0.0))
	var given_w := float(p.get("stand_width", 0.0))
	var fz := float(p["front_z"])
	var set_back := 0.12 if pedestal else 0.0
	match stand:
		"chest":
			if top > 0.05:
				var cd := maxf(depth + 0.1, 0.4)
				out["stand_box"] = [Vector3(shift, top * 0.5, c.z + 0.03 + set_back - cd * 0.5),
						Vector3(given_w if given_w > 0.0 else maxf(outer.x + 0.3, 0.9), top, cd)]
		"radiogram", "desk", "tv_unit":
			if top > 0.05:
				var own: Array = STANDS[stand]
				var back := fz + 0.03
				var d := maxf(float(own[2]), c.z + set_back - back)
				out["stand_box"] = [Vector3(shift, top * 0.5, back + d * 0.5),
						Vector3(given_w if given_w > 0.0 else maxf(outer.x + float(own[0]), float(own[1])), top, d)]
		"wall":
			# A cabinet or a portable on a shelf on brackets; a flat panel hangs on its own bracket (behind it).
			if not pedestal and form != "flat_panel" and foot > 0.05:
				var d := c.z + 0.02 - fz
				out["stand_box"] = [Vector3(cx, foot - 0.015, fz + d * 0.5), Vector3(outer.x + 0.1, 0.03, d)]
	out["shelf"] = _shelf(out, cx, outer, c)
	return out


## Where a video recorder goes under the set: the tv_unit's shelf; a desk's or a radiogram's top beside the set when
## there is half a metre; else the floor in front of the stand (or under a set on the wall).
static func _shelf(t: Dictionary, cx: float, outer: Vector2, c: Vector3) -> Array:
	var sb: Array = t["stand_box"]
	var stand := str(t["stand"])
	if not sb.is_empty() and stand != "wall":
		var sc: Vector3 = sb[0]
		var ss: Vector3 = sb[1]
		var front := sc.z + ss.z * 0.5
		var y := Furniture.shelf_floor(float(t["top"]))
		if stand == "tv_unit" and y > 0.0:
			return [Vector3(sc.x, y, front - 0.17), Vector3(ss.x - 0.1, Furniture.SHELF_H, ss.z - 0.05)]
		if stand in ["desk", "radiogram"]:
			var right := (sc.x + ss.x * 0.5) - (cx + outer.x * 0.5)
			var left := (cx - outer.x * 0.5) - (sc.x - ss.x * 0.5)
			if maxf(right, left) >= 0.5:
				var x := (cx + outer.x * 0.5 + right * 0.5) if right >= left else (cx - outer.x * 0.5 - left * 0.5)
				return [Vector3(x, float(t["top"]), front - 0.17), Vector3(maxf(right, left), 0.4, ss.z)]
		return [Vector3(cx, 0.0, front + 0.2), Vector3(0.6, float(t["top"]), 0.4)]
	# The floor in front of the set (a set on the floor: before its front).
	var body: Array = t["body"]
	var set_front := (body[0] as Vector3).z + (body[1] as Vector3).z * 0.5
	return [Vector3(cx, 0.0, maxf(c.z, set_front) + 0.2), Vector3(0.6, float(t["foot"]), 0.4)]


## The telly's body round the picture and the stand under it: [[centre, size]...].
static func _telly_boxes(p: Dictionary) -> Array:
	var t := _telly(p)
	var out: Array = [t["body"]]
	if not (t["stand_box"] as Array).is_empty():
		out.append(t["stand_box"])
	if t.has("legs"):
		out.append(t["legs"])
	return out


## The fort's pillows: [centre, size, yaw] each (walls of two courses left, right and behind).
static func _pillows() -> Array:
	var out: Array = []
	for course in 2:
		var y := 0.14 + course * 0.28
		var shift := 0.15 * course
		var z := FORT_FRONT + 0.3 + shift
		while z < FORT_BACK - 0.2:
			for s: float in [-1.0, 1.0]:
				out.append([Vector3(s * (FORT_HALF + 0.05), y, z), Vector3(0.36, 0.28, 0.6), 0.0])
			z += 0.62
		var x := -FORT_HALF + 0.3 + shift
		while x < FORT_HALF - 0.1:
			out.append([Vector3(x, y, FORT_BACK + 0.1), Vector3(0.6, 0.28, 0.36), 0.0])
			x += 0.62
	return out


static func collision_shapes_for(given: Dictionary, with_seats := true) -> Array:
	var p := resolved(given)
	var box := _box(p)
	var out := U.shell_boxes(box.position, box.end)
	if str(p["heater"]) == "fireplace":
		var b := _breast(p)
		out.append(PhysicsShapes.box(b[0], b[1]))
	if str(p["screen"]) == "telly":
		for t: Array in _telly_boxes(p):
			out.append(PhysicsShapes.box(t[0], t[1]))
	if _fort(p):
		for pl: Array in _pillows():
			out.append(PhysicsShapes.box(pl[0], pl[1]))
	if str(p["style"]) == "bedroom_1993":
		var bed := _bed(p)
		out.append(PhysicsShapes.box(bed[0], bed[1]))
	if with_seats:
		out.append_array(U.seat_boxes(seat_slots_for(given), str(p["seat_model"])))
	return out


static func _bed(p: Dictionary) -> Array:
	var hw := float(p["half_width"])
	var bz := float(p["back_z"])
	var side := -1.0 if _fire_side(p) == "left" else 1.0
	if str(p["window"]) == "right":
		side = -1.0
	return [Vector3(side * (hw - 0.5), 0.25, bz - 1.05), Vector3(0.95, 0.5, 2.0)]


static func slots_for(given: Dictionary) -> Dictionary:
	var p := resolved(given)
	var box := _box(p)
	var hw := box.size.x * 0.5
	var h := float(p["height"])
	var walls: Array = []
	for side: String in ["left", "right"]:
		var w := _wall(p, side)
		var along := 1.0
		while along < float(w[3]) - 0.8:
			var n: Vector3 = w[2]
			walls.append({"transform": Transform3D(Basis(Vector3.UP.cross(n), Vector3.UP, n), _on_wall(p, side, along, 0.0)),
					"size": [1.5, h, 0.3]})
			along += 1.6
	var sc := screen_for(p)
	var ss := U.v2(sc["size"])
	var corners: Array = []
	for c: Vector2 in [Vector2(-hw, box.position.z), Vector2(hw, box.position.z), Vector2(-hw, box.end.z),
			Vector2(hw, box.end.z)]:
		var into := Vector3(-signf(c.x), 0, 0)
		corners.append({"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into),
				Vector3(c.x * 0.85, 0.0, c.y + (0.4 if c.y < 0 else -0.4))), "size": [0.8, h, 0.8]})
	var out := {
		"side_walls": walls,
		"corners": corners,
		"screen": [{"transform": Transform3D(Basis(), U.v3(sc["center"])), "size": [ss.x, ss.y, 0.1]}],
		"proscenium": [{"transform": Transform3D(Basis(), Vector3(0.0, 0.0, box.position.z)),
				"size": [box.size.x, h, 0.3]}],
		"floor": [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, box.get_center().z)),
				"size": [box.size.x, box.size.z, 0.0]}],
		"ceiling": [{"transform": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, box.end.y, box.get_center().z)),
				"size": [box.size.x, box.size.z, 0.0]}],
	}
	var win := _window(p)
	if not win.is_empty():
		var r: Rect2 = win[1]
		var w := _wall(p, win[0])
		var n: Vector3 = w[2]
		var basis := Basis(Vector3.UP.cross(n), Vector3.UP, n)
		var centre := _on_wall(p, win[0], r.get_center().x, r.get_center().y)
		# The window's pane (for a weather system's pane: centre, size, yaw) and the view beyond, facing in.
		out["window"] = [{"transform": Transform3D(basis, centre), "size": [r.size.x, r.size.y, 0.1]}]
		out["vista"] = [{"transform": Transform3D(basis, centre - n * 4.0), "size": [r.size.x * 6.0, r.size.y * 4.0, 60.0]}]
	if str(p["heater"]) == "fireplace":
		var b := _breast(p)
		var c: Vector3 = b[0]
		var into := Vector3(-signf(c.x), 0, 0)
		out["mantel"] = [{"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into),
				Vector3(c.x - signf(c.x) * 0.3, 1.18, c.z)), "size": [1.7, 0.6, 0.2]}]
	if _fort(p):
		out["fort_opening"] = [{"transform": Transform3D(Basis(), Vector3(0.0, 0.0, FORT_FRONT)),
				"size": [FORT_HALF * 2.0, FORT_TOP_FRONT, 0.1]}]
	if str(p["screen"]) == "telly":
		# The stand's top at its front middle (things on it go behind: -z); on the wall, the floor under the set.
		var t := _telly(p)
		var sb: Array = t["stand_box"]
		if str(t["form"]) in ["console", "rear_projection"]:
			# A set on the floor: its own top, at its front middle.
			var bc: Vector3 = (t["body"] as Array)[0]
			var bs: Vector3 = (t["body"] as Array)[1]
			var body_top := bc.y + bs.y * 0.5
			out["telly_stand"] = [{"transform": Transform3D(Basis(), Vector3(bc.x, body_top, bc.z + bs.z * 0.5)),
					"size": [bs.x, body_top, bs.z if str(t["form"]) == "console" else REAR_TOP_DEPTH]}]
		elif not sb.is_empty() and str(t["stand"]) != "wall":
			var bc: Vector3 = sb[0]
			var bs: Vector3 = sb[1]
			out["telly_stand"] = [{"transform": Transform3D(Basis(), Vector3(bc.x, float(t["top"]), bc.z + bs.z * 0.5)),
					"size": [bs.x, float(t["top"]), bs.z]}]
		else:
			var body: Array = t["body"]
			out["telly_stand"] = [{"transform": Transform3D(Basis(), Vector3((body[0] as Vector3).x, 0.0,
					float(p["front_z"]) + 0.02)), "size": [(body[1] as Vector3).x, float(t["foot"]), 0.0]}]
		var sh: Array = t["shelf"]
		var room_size: Vector3 = sh[1]
		out["telly_shelf"] = [{"transform": Transform3D(Basis(), sh[0]), "size": [room_size.x, room_size.y, room_size.z]}]
	return out


func sound_room() -> Dictionary:
	var p := resolved(params)
	return {"box": _box(p), "surround_height": 1.6 if not _fort(p) else 1.0, "array": 1}


# --- Building -----------------------------------------------------------------------------------------------------

var _p := {}
var _outside_m: Array[ShaderMaterial] = []
var _fire_m: Array = []
var _painting: MeshInstance3D
var _painting_travel := 0.0
var _wall_m: ShaderMaterial
var _trim_m: ShaderMaterial
## The fairy lights: their flicker entry (builder.gd _flickering) and their stand-in lamp, for fairy_glow.
var _fairy_flicker: Array = []
var _fairy_lamp := -1
const FAIRY_ENERGY := 1.3


func _m(key: String, instanced := false) -> ShaderMaterial:
	return _light.from_param(_p[key], instanced)


func build() -> void:
	_p = resolved(params)
	var p := _p
	var box := _box(p)
	var hw := box.size.x * 0.5
	var fz := box.position.z
	var bz := box.end.z
	var h := float(p["height"])
	var rise := float(p["vault_rise"])
	var ice := str(p["style"]) == "ice"
	# The floor.
	var fl := RoomMesh.new()
	fl.surface(_m("floor"))
	fl.face([Vector3(-hw, 0, fz), Vector3(hw, 0, fz), Vector3(hw, 0, bz), Vector3(-hw, 0, bz)], Vector3.UP)
	_add_static("Floor", fl)
	# The walls, with the window's and the door's holes; a vault's end walls up to it.
	var wall_m := _m("walls")
	var pattern := str(p["wall_pattern"])
	if pattern != "plain":
		Procedural.apply(wall_m, pattern, RoomSchemaRef.to_color(p["walls"].get("color", "#b0b0b0")))
	_wall_m = wall_m
	var walls := RoomMesh.new()
	walls.surface(wall_m)
	var win := _window(p)
	var door := _door(p)
	for side: String in ["left", "right", "back", "front"]:
		var holes: Array = []
		if not win.is_empty() and win[0] == side:
			holes.append(win[1])
		if not door.is_empty() and door[0] == side:
			holes.append(door[1])
		var w := _wall(p, side)
		Shapes.wall(walls, w[0], w[1], w[2], w[3], h, holes)
		if rise > 0.0 and side in ["front", "back"]:
			var cap: Array = []
			for k in 17:
				var t := PI * k / 16.0
				cap.append(Vector3(cos(t) * hw, h + sin(t) * rise, fz if side == "front" else bz))
			walls.face(cap, w[2])
	_add_static("Walls", walls)
	# The ceiling: flat, or a low vault (an ellipse's half across the room).
	var ceil := RoomMesh.new()
	var ceil_m := _m("ceiling")
	if pattern == "ice_blocks":
		Procedural.apply(ceil_m, pattern, RoomSchemaRef.to_color(p["ceiling"].get("color", "#b0b0b0")))
	ceil.surface(ceil_m)
	if rise > 0.0:
		var a := PackedVector3Array()
		var c := PackedVector3Array()
		var ns := PackedVector3Array()
		for k in 17:
			var t := PI * k / 16.0
			a.append(Vector3(cos(t) * hw, h + sin(t) * rise, fz))
			c.append(Vector3(cos(t) * hw, h + sin(t) * rise, bz))
			ns.append(-Vector3(cos(t) / hw, sin(t) / rise, 0.0).normalized())
		ceil.strip(a, c, ns)
	else:
		ceil.face([Vector3(-hw, h, fz), Vector3(hw, h, fz), Vector3(hw, h, bz), Vector3(-hw, h, bz)], Vector3.DOWN)
	_add_static("Ceiling", ceil)
	var trim := RoomMesh.new()
	_trim_m = _m("trim")
	trim.surface(_trim_m)
	if not ice:
		_build_skirting(trim, door)
	if not win.is_empty():
		_build_window(trim, win)
	if not door.is_empty():
		_build_door(trim, door, ice)
	match str(p["screen"]):
		"projected":
			_build_screen(trim, true)
		"wall":
			_build_screen(trim, false)
		"painting":
			_build_painting(trim)
		"telly":
			_build_telly(trim)
	if str(p["style"]) == "bedroom_1993":
		_build_bed(trim)
	match str(p["heater"]):
		"fireplace":
			_build_fireplace()
		"radiator":
			_build_radiator(win)
	if _fort(p):
		_build_fort(trim)
	_add_static("Trim", trim)
	if str(p["fairy_lights"]) == "on":
		_build_fairy_lights()
	_build_lamps(win)
	_build_seats()
	# The main light, off in a pillow fort: the film is watched by the fairy lights and the telly (the user,
	# 2026-11-07: far too bright inside the fort).
	if not _fort(p) and float(p.get("ceiling_light", 0.35)) > 0.0:
		_bake_spot("Ceiling", Vector3(0, h + rise - 0.1, (fz + bz) * 0.5), true, 75.0, h + rise + 1.0,
				float(p.get("ceiling_light", 0.35)), color_param("lamp_colour"))


func _build_skirting(trim: RoomMesh, door: Array) -> void:
	for side: String in ["left", "right", "back", "front"]:
		var w := _wall(_p, side)
		var spans: Array[Vector2] = [Vector2(0.0, w[3])]
		if not door.is_empty() and door[0] == side:
			var r: Rect2 = door[1]
			spans = [Vector2(0.0, r.position.x - 0.08), Vector2(r.end.x + 0.08, w[3])]
		for s: Vector2 in spans:
			if s.y - s.x < 0.05:
				continue
			var mid := _on_wall(_p, side, (s.x + s.y) * 0.5, 0.06, 0.01)
			var size := Vector3(s.y - s.x, 0.12, 0.02)
			var n: Vector3 = w[2]
			trim.box(mid, size, Basis(Vector3.UP.cross(n), Vector3.UP, n), [RoomMesh.DOWN, RoomMesh.FRONT])


## The window: a frame round the hole (deep enough to read as the wall's thickness), a sill board, a glazing bar,
## the glass, and the outside's glow beyond (unless a vista or sky shows there).
func _build_window(trim: RoomMesh, win: Array) -> void:
	var side: String = win[0]
	var r: Rect2 = win[1]
	var w := _wall(_p, side)
	var n: Vector3 = w[2]
	var basis := Basis(Vector3.UP.cross(n), Vector3.UP, n)
	var t := 0.07
	var depth := 0.2
	for k: Array in [[r.position.x - t * 0.5, r.get_center().y, t, r.size.y + t * 2.0],
			[r.end.x + t * 0.5, r.get_center().y, t, r.size.y + t * 2.0],
			[r.get_center().x, r.end.y + t * 0.5, r.size.x, t], [r.get_center().x, r.position.y - t * 0.5, r.size.x, t]]:
		trim.box(_on_wall(_p, side, k[0], k[1], -depth * 0.5 + 0.03), Vector3(k[2], k[3], depth), basis)
	trim.box(_on_wall(_p, side, r.get_center().x, r.position.y - 0.02, 0.08), Vector3(r.size.x + 0.2, 0.04, 0.2), basis)
	trim.box(_on_wall(_p, side, r.get_center().x, r.get_center().y, -0.06), Vector3(0.05, r.size.y, 0.05), basis)
	var glass := RoomMesh.new()
	glass.surface(GLASS)
	Shapes.quad(glass, _on_wall(_p, side, r.get_center().x, r.get_center().y, -0.07),
			basis.x * r.size.x * 0.5, Vector3(0, r.size.y * 0.5, 0), n)
	_add_glass("Window", glass, Color(0.62, 0.72, 0.78), 0.06)
	if str(_p["outside"]) == "glow":
		_outside_quad("Outside", _on_wall(_p, side, r.get_center().x, r.get_center().y, -2.0), basis,
				Vector2(r.size.x * 3.0, r.size.y * 3.0), n)


func _outside_quad(node_name: String, at: Vector3, basis: Basis, size: Vector2, n: Vector3) -> void:
	var pic := Procedural.gradient(color_param("outside_top"), color_param("outside_bottom"))
	var mi := _add_picture(node_name, [[at, basis.x * size.x * 0.5, Vector3(0, size.y * 0.5, 0), n]], pic,
			Color(1, 1, 1), float(_p["outside_glow"]), "accent")
	_outside_m.append(mi.mesh.surface_get_material(0))


## The door: an architrave round the hole and the leaf in it with a handle; in ice, an open doorway through the
## wall's thickness with the night's glow beyond.
func _build_door(trim: RoomMesh, door: Array, open: bool) -> void:
	var side: String = door[0]
	var r: Rect2 = door[1]
	var w := _wall(_p, side)
	var n: Vector3 = w[2]
	var basis := Basis(Vector3.UP.cross(n), Vector3.UP, n)
	if open:
		var walls := RoomMesh.new()
		walls.surface(_wall_m)
		var d := 0.7
		for s: float in [-1.0, 1.0]:
			var x := r.get_center().x + s * r.size.x * 0.5
			walls.face([_on_wall(_p, side, x, 0.0, 0.0), _on_wall(_p, side, x, 0.0, -d), _on_wall(_p, side, x, r.end.y, -d),
					_on_wall(_p, side, x, r.end.y, 0.0)], basis.x * -s)
		walls.face([_on_wall(_p, side, r.position.x, r.end.y, 0.0), _on_wall(_p, side, r.end.x, r.end.y, 0.0),
				_on_wall(_p, side, r.end.x, r.end.y, -d), _on_wall(_p, side, r.position.x, r.end.y, -d)], Vector3.DOWN)
		walls.face([_on_wall(_p, side, r.position.x, 0.0, 0.0), _on_wall(_p, side, r.end.x, 0.0, 0.0),
				_on_wall(_p, side, r.end.x, 0.0, -d), _on_wall(_p, side, r.position.x, 0.0, -d)], Vector3.UP)
		_add_static("Doorway", walls)
		if str(_p["outside"]) == "glow":
			_outside_quad("OutsideDoor", _on_wall(_p, side, r.get_center().x, r.get_center().y, -d - 0.6), basis,
					Vector2(r.size.x * 2.5, r.size.y * 1.6), n)
		return
	var t := 0.08
	for k: Array in [[r.position.x - t * 0.5, r.size.y * 0.5 + t * 0.5, t, r.size.y + t],
			[r.end.x + t * 0.5, r.size.y * 0.5 + t * 0.5, t, r.size.y + t], [r.get_center().x, r.end.y + t * 0.5, r.size.x, t]]:
		trim.box(_on_wall(_p, side, k[0], k[1], 0.01), Vector3(k[2], k[3], 0.03), basis, [RoomMesh.FRONT])
	var door_m := RoomMesh.new()
	door_m.surface(_m("trim"))
	door_m.box(_on_wall(_p, side, r.get_center().x, r.size.y * 0.5, -0.03), Vector3(r.size.x, r.size.y, 0.04), basis,
			[RoomMesh.FRONT])
	# Two panels' mouldings and the handle.
	for k in 2:
		var y := r.size.y * (0.3 if k == 0 else 0.72)
		door_m.box(_on_wall(_p, side, r.get_center().x, y, -0.005), Vector3(r.size.x - 0.24, r.size.y * 0.36, 0.012),
				basis, [RoomMesh.FRONT])
	door_m.box(_on_wall(_p, side, r.end.x - 0.1, 1.0, 0.03), Vector3(0.12, 0.025, 0.05), basis)
	_add_static("Door", door_m)


## A pull-down screen (a white sheet with black borders, its roller's case above) or a smoothed panel of the wall.
func _build_screen(trim: RoomMesh, pull_down: bool) -> void:
	var pic := _picture(_p)
	var c: Vector3 = pic[0]
	var s: Vector2 = pic[1]
	var b := RoomMesh.new()
	b.surface(_m("screen_surface"))
	var margin := Vector2(0.08, 0.08) if pull_down else Vector2(0.15, 0.15)
	Shapes.quad(b, Vector3(c.x, c.y, c.z - 0.01), Vector3(s.x * 0.5 + margin.x, 0, 0), Vector3(0, s.y * 0.5 + margin.y, 0),
			Vector3.BACK)
	if pull_down:
		var top := c.y + s.y * 0.5 + margin.y
		# The sheet's black border and its drop above the picture, the bottom bar, the case at the ceiling.
		var dark: ShaderMaterial = _light.library("felt", Color(0.03, 0.03, 0.03))
		b.surface(dark)
		var h := float(_p["height"])
		Shapes.quad(b, Vector3(c.x, (top + h - 0.12) * 0.5, c.z - 0.01), Vector3(s.x * 0.5 + margin.x, 0, 0),
				Vector3(0, (h - 0.12 - top) * 0.5, 0), Vector3.BACK)
		b.surface(_m("trim"))
		b.box(Vector3(c.x, c.y - s.y * 0.5 - margin.y - 0.015, c.z), Vector3(s.x + margin.x * 2.0 + 0.04, 0.03, 0.03))
		b.box(Vector3(c.x, h - 0.06, c.z - 0.02), Vector3(s.x + margin.x * 2.0 + 0.2, 0.12, 0.14), Basis(),
				[RoomMesh.UP])
	_add_static("Screen", b)


## The painting: a frame round the picture, and the canvas in it that rises into a slot in the ceiling
## (painting_open: 1 risen, the screen showing; a cue fades it for the ritual).
func _build_painting(trim: RoomMesh) -> void:
	var pic := _picture(_p)
	var c: Vector3 = pic[0]
	var s: Vector2 = pic[1]
	var h := float(_p["height"])
	var t := 0.1
	var half := s * 0.5 + Vector2(0.04, 0.04)
	var z := float(_p["front_z"]) + 0.04
	for sd: float in [-1.0, 1.0]:
		trim.box(Vector3(sd * (half.x + t * 0.5), c.y, z), Vector3(t, half.y * 2.0 + t * 2.0, 0.08), Basis(),
				[RoomMesh.FRONT])
		trim.box(Vector3(0.0, c.y + sd * (half.y + t * 0.5), z), Vector3(half.x * 2.0, t, 0.08), Basis(),
				[RoomMesh.FRONT])
	# The ceiling's slot the canvas rises into.
	var slot := RoomMesh.new()
	slot.surface(_light.library("felt", Color(0.02, 0.02, 0.02)))
	slot.face([Vector3(-half.x - 0.05, h - 0.003, z + 0.02), Vector3(half.x + 0.05, h - 0.003, z + 0.02),
			Vector3(half.x + 0.05, h - 0.003, z + 0.1), Vector3(-half.x - 0.05, h - 0.003, z + 0.1)], Vector3.DOWN)
	_add_static("PaintingSlot", slot)
	var art := Procedural.abstract(1962, [Color(0.82, 0.76, 0.62), Color(0.75, 0.32, 0.12), Color(0.12, 0.25, 0.35),
			Color(0.85, 0.62, 0.2), Color(0.2, 0.2, 0.18)])
	_painting = _add_picture("Painting", [[Vector3(c.x, c.y, c.z + 0.04), Vector3(half.x, 0, 0), Vector3(0, half.y, 0),
			Vector3.BACK]], art, Color(1, 1, 1), 0.45, "house")
	# Down, it stands in front of the picture: the film layer steps aside for it (film_layer.gd), up it is clear.
	_painting.add_to_group("env_in_front")
	_painting_travel = h - (c.y - half.y) + 0.05
	_place_painting()


func _place_painting() -> void:
	if _painting != null:
		_painting.position = Vector3(0, float(params["painting_open"]) * _painting_travel, 0)


## The telly (a cabinet, a portable or a flat panel) on its stand (in the trim's material).
func _build_telly(trim: RoomMesh) -> void:
	var t := _telly(_p)
	var tv := RoomMesh.new()
	tv.surface(_m("telly_material"))
	match str(t["form"]):
		"portable":
			_build_portable(tv, t)
		"flat_panel":
			_build_flat_panel(tv, t)
		"oled":
			_build_oled(tv, t)
		"console":
			_build_console(tv, t)
		"rear_projection":
			_build_rear_projection(tv, t)
		"mirror_lid":
			_build_mirror_lid(tv, t)
		_:
			_build_cabinet(tv, t)
	_add_static("Telly", tv)
	_build_stand(trim, t)


## The front round the picture (a face with the picture's hole: the picture's own face is the screen) over a body
## (its own face at the front left out), and a dark glass behind the picture's plane (the film is drawn in front).
func _telly_front(tv: RoomMesh, t: Dictionary, glass_back: float) -> Array:
	var c: Vector3 = (t["pic"] as Array)[0]
	var s: Vector2 = (t["pic"] as Array)[1]
	var centre: Vector3 = (t["body"] as Array)[0]
	var size: Vector3 = (t["body"] as Array)[1]
	var left := centre.x - size.x * 0.5
	var bottom := centre.y - size.y * 0.5
	var holes := [Rect2(c.x - s.x * 0.5 - left, c.y - s.y * 0.5 - bottom, s.x, s.y)]
	Shapes.wall(tv, Vector3(left, bottom, c.z), Vector3.RIGHT, Vector3.BACK, size.x, size.y, holes)
	return [c, s, centre, size, left, bottom, glass_back]


func _dark_glass(tv: RoomMesh, c: Vector3, s: Vector2, back: float) -> void:
	tv.surface(_light.library("dark_metal", Color(0.03, 0.035, 0.035)))
	Shapes.quad(tv, Vector3(c.x, c.y, c.z - back), Vector3(s.x * 0.5, 0, 0), Vector3(0, s.y * 0.5, 0), Vector3.BACK)


## A deep cabinet round the picture (wider at the bottom for its controls), the body tapering behind, buttons under
## the picture.
func _build_cabinet(tv: RoomMesh, t: Dictionary) -> void:
	var f := _telly_front(tv, t, 0.03)
	var c: Vector3 = f[0]
	var s: Vector2 = f[1]
	var centre: Vector3 = f[2]
	var size: Vector3 = f[3]
	var bottom: float = f[5]
	var front := c.z
	var back_z := front - size.z
	tv.box(Vector3(0, centre.y, front - 0.05), Vector3(size.x, size.y, 0.1), Basis(), [RoomMesh.BACK])
	tv.box(Vector3(0, centre.y + 0.02, (front - 0.1 + back_z) * 0.5), Vector3(size.x * 0.7, size.y * 0.75,
			size.z - 0.1), Basis(), [RoomMesh.BACK])
	_dark_glass(tv, c, s, 0.03)
	for k in 4:
		tv.box(Vector3(size.x * 0.5 - 0.06 - k * 0.05, bottom + (c.y - s.y * 0.5 - bottom) * 0.5, front + 0.006),
				Vector3(0.03, 0.015, 0.012))


## A portable: a small deep case, the picture on the left of its front and a panel of knobs and a speaker's slots on
## the right, a carry handle on top and a rod aerial leaning back.
func _build_portable(tv: RoomMesh, t: Dictionary) -> void:
	var f := _telly_front(tv, t, 0.03)
	var c: Vector3 = f[0]
	var s: Vector2 = f[1]
	var centre: Vector3 = f[2]
	var size: Vector3 = f[3]
	var front := c.z
	var top := centre.y + size.y * 0.5
	tv.box(Vector3(centre.x, centre.y, front - 0.04), Vector3(size.x, size.y, 0.08), Basis(), [RoomMesh.BACK])
	tv.box(Vector3(centre.x, centre.y + 0.005, front - 0.08 - (size.z - 0.08) * 0.5), Vector3(size.x * 0.86,
			size.y * 0.86, size.z - 0.08), Basis(), [RoomMesh.BACK])
	# The handle: two lugs and a bar over the top; the aerial from the back corner.
	for sd: float in [-1.0, 1.0]:
		tv.box(Vector3(centre.x + sd * size.x * 0.3, top + 0.02, centre.z), Vector3(0.022, 0.04, 0.03), Basis(),
				[RoomMesh.DOWN])
	tv.box(Vector3(centre.x, top + 0.045, centre.z), Vector3(size.x * 0.6 + 0.022, 0.018, 0.03))
	var foot := Vector3(centre.x + size.x * 0.36, top, centre.z - size.z * 0.3)
	tv.box(foot + Vector3(0, 0.01, 0), Vector3(0.025, 0.02, 0.025), Basis(), [RoomMesh.DOWN])
	Shapes.beam(tv, foot + Vector3(0, 0.02, 0), foot + Vector3(0.1, 0.4, -0.1), Vector2(0.005, 0.005))
	_dark_glass(tv, c, s, 0.03)
	# Knobs (short cylinders) and the speaker's slots on the panel.
	var panel_x := (c.x + s.x * 0.5 + float((t["bezel"] as Vector2).x) * 0.5 + centre.x + size.x * 0.5) * 0.5
	for k in 2:
		Shapes.cylinder(tv, Vector3(panel_x, c.y + s.y * (0.28 - k * 0.3), front), 0.016, 0.014, 8,
				Basis(Vector3.RIGHT, PI * 0.5))
	for k in 4:
		tv.box(Vector3(panel_x, c.y - s.y * 0.28 - k * 0.018, front + 0.002), Vector3(0.04, 0.005, 0.004), Basis(),
				[RoomMesh.BACK])


## A flat panel: a thin frame round the picture, a speaker strip under it, a shallow box at the back, and (not on
## the wall) a pedestal: a neck and a foot on the stand's top.
func _build_flat_panel(tv: RoomMesh, t: Dictionary) -> void:
	var f := _telly_front(tv, t, 0.008)
	var c: Vector3 = f[0]
	var s: Vector2 = f[1]
	var centre: Vector3 = f[2]
	var size: Vector3 = f[3]
	var bottom: float = f[5]
	var front := c.z
	tv.box(Vector3(centre.x, centre.y, front - size.z * 0.5), Vector3(size.x, size.y, size.z), Basis(), [RoomMesh.BACK])
	tv.box(Vector3(centre.x, centre.y + 0.02, front - size.z - 0.02), Vector3(size.x * 0.62, size.y * 0.6, 0.04),
			Basis(), [RoomMesh.BACK])
	if bool(t["pedestal"]):
		var stand_top := float(t["top"])
		tv.box(Vector3(centre.x, (stand_top + bottom) * 0.5 + 0.02, front - size.z * 0.6), Vector3(0.07,
				bottom - stand_top + 0.04, 0.04), Basis(), [RoomMesh.DOWN, RoomMesh.UP])
		tv.box(Vector3(centre.x, stand_top + 0.009, front - size.z * 0.6), Vector3(minf(0.42, size.x * 0.55), 0.018,
				0.24), Basis(), [RoomMesh.DOWN])
	_dark_glass(tv, c, s, 0.008)
	# The speaker strip's grille.
	tv.box(Vector3(centre.x, bottom + FLAT_STRIP * 0.5 + 0.008, front + 0.002), Vector3(s.x * 0.86, FLAT_STRIP * 0.4,
			0.004), Basis(), [RoomMesh.BACK])


## An OLED panel: a very thin panel (a hair's bezel round the picture), its electronics a shallow box low on its back,
## and (not on the wall) a slim pedestal: a thin neck and a flat plate on the stand's top. A true black glass.
func _build_oled(tv: RoomMesh, t: Dictionary) -> void:
	var f := _telly_front(tv, t, 0.004)
	var c: Vector3 = f[0]
	var s: Vector2 = f[1]
	var centre: Vector3 = f[2]
	var size: Vector3 = f[3]
	var bottom: float = f[5]
	var front := c.z
	tv.box(Vector3(centre.x, centre.y, front - 0.004), Vector3(size.x, size.y, 0.008), Basis(), [RoomMesh.BACK])
	tv.box(Vector3(centre.x, centre.y - size.y * 0.2, front - 0.008 - (OLED_DEPTH - 0.008) * 0.5),
			Vector3(size.x * 0.7, size.y * 0.45, OLED_DEPTH - 0.008), Basis(), [RoomMesh.BACK])
	if bool(t["pedestal"]):
		var stand_top := float(t["top"])
		tv.box(Vector3(centre.x, (stand_top + bottom) * 0.5 + 0.02, front - OLED_DEPTH * 0.7), Vector3(0.05,
				bottom - stand_top + 0.04, 0.012), Basis(), [RoomMesh.DOWN, RoomMesh.UP])
		tv.box(Vector3(centre.x, stand_top + 0.004, front - OLED_DEPTH * 0.7), Vector3(minf(0.5, size.x * 0.4), 0.008,
				0.2), Basis(), [RoomMesh.DOWN])
	tv.surface(_light.library("dark_metal", Color(0.004, 0.004, 0.005)))
	Shapes.quad(tv, Vector3(c.x, c.y, c.z - 0.004), Vector3(s.x * 0.5, 0, 0), Vector3(0, s.y * 0.5, 0), Vector3.BACK)


## A 1960s console: a wooden cabinet on four splayed legs, the 4:3 tube over a speaker's cloth grille, two knobs beside
## the grille; with telly_doors, two doors open and folded back beside the cabinet.
func _build_console(tv: RoomMesh, t: Dictionary) -> void:
	var f := _telly_front(tv, t, 0.03)
	var c: Vector3 = f[0]
	var s: Vector2 = f[1]
	var centre: Vector3 = f[2]
	var size: Vector3 = f[3]
	var bottom: float = f[5]
	var front := c.z
	tv.box(Vector3(centre.x, centre.y, front - size.z * 0.5), Vector3(size.x, size.y, size.z), Basis(), [RoomMesh.BACK])
	# A thin moulding round the picture's opening, and the top's lip.
	for sd: float in [-1.0, 1.0]:
		tv.box(Vector3(c.x + sd * (s.x * 0.5 + 0.012), c.y, front + 0.006), Vector3(0.024, s.y + 0.048, 0.012))
		tv.box(Vector3(c.x, c.y + sd * (s.y * 0.5 + 0.012), front + 0.006), Vector3(s.x, 0.024, 0.012))
	tv.box(Vector3(centre.x, centre.y + size.y * 0.5 + 0.01, front - size.z * 0.5 + 0.01), Vector3(size.x + 0.04, 0.02,
			size.z + 0.04))
	# The legs: tapered square legs splayed out from the body's corners to the floor.
	var foot := float(t["foot"])
	if foot > 0.05:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var top := Vector3(centre.x + sx * (size.x * 0.5 - 0.07), foot, front - size.z * 0.5 + sz * (size.z * 0.5
						- 0.07))
				var down := top + Vector3(sx * 0.07, -foot, sz * 0.05)
				Shapes.beam(tv, top, down, Vector2(0.035, 0.035))
	# The knobs beside the grille.
	var panel_y := (bottom + c.y - s.y * 0.5) * 0.5
	for k in 2:
		Shapes.cylinder(tv, Vector3(c.x + s.x * 0.5 - 0.03, panel_y + (0.05 - k * 0.1), front), 0.022, 0.02, 10,
				Basis(Vector3.RIGHT, PI * 0.5))
	if bool(_p.get("telly_doors", false)):
		# The doors, open about 160 degrees: each folded back beside the cabinet, its inside to the room.
		var dw := size.x * 0.5
		for sx: float in [-1.0, 1.0]:
			var dir := Vector3(sx * 0.94, 0.0, 0.34)
			var hinge := Vector3(centre.x + sx * size.x * 0.5, centre.y, front + 0.01)
			tv.box(hinge + dir * dw * 0.5, Vector3(dw, size.y - 0.02, 0.02), Basis(Vector3.UP, atan2(-dir.z, dir.x)))
	_dark_glass(tv, c, s, 0.03)
	# The speaker's cloth over the lower front.
	tv.surface(_light.library("felt", Color(0.24, 0.2, 0.15)))
	var gh := c.y - s.y * 0.5 - 0.05 - (bottom + 0.04)
	tv.box(Vector3(c.x - 0.04, bottom + 0.04 + gh * 0.5, front + 0.004), Vector3(s.x - 0.08, gh, 0.008), Basis(),
			[RoomMesh.FRONT])


## A big rear projection set of 2002: a deep cabinet from the floor, its lower part full depth (the projector and
## its mirror) and its upper part behind the screen shallower, a narrow frame round a grey-black screen, two speaker
## grilles in the band under it.
func _build_rear_projection(tv: RoomMesh, t: Dictionary) -> void:
	var f := _telly_front(tv, t, 0.008)
	var c: Vector3 = f[0]
	var s: Vector2 = f[1]
	var centre: Vector3 = f[2]
	var size: Vector3 = f[3]
	var front := c.z
	var lower := c.y - s.y * 0.5
	var top := centre.y + size.y * 0.5
	tv.box(Vector3(centre.x, lower * 0.5, front - REAR_DEPTH * 0.5), Vector3(size.x, lower, REAR_DEPTH), Basis(),
			[RoomMesh.BACK])
	tv.box(Vector3(centre.x, (lower + top) * 0.5, front - REAR_TOP_DEPTH * 0.5), Vector3(size.x, top - lower,
			REAR_TOP_DEPTH), Basis(), [RoomMesh.BACK, RoomMesh.DOWN])
	# The slope from the upper back down to the lower back.
	var ub := front - REAR_TOP_DEPTH
	var lb := front - REAR_DEPTH
	tv.face([Vector3(centre.x + size.x * 0.5, top, ub), Vector3(centre.x - size.x * 0.5, top, ub),
			Vector3(centre.x - size.x * 0.5, lower, lb), Vector3(centre.x + size.x * 0.5, lower, lb)],
			Vector3(0, ub - lb, -(top - lower)).normalized())
	# The plinth's shadow line.
	tv.box(Vector3(centre.x, 0.025, front - 0.02), Vector3(size.x - 0.04, 0.05, 0.02), Basis(), [RoomMesh.DOWN])
	tv.surface(_light.library("dark_metal", Color(0.045, 0.045, 0.05)))
	Shapes.quad(tv, Vector3(c.x, c.y, c.z - 0.008), Vector3(s.x * 0.5, 0, 0), Vector3(0, s.y * 0.5, 0), Vector3.BACK)
	tv.surface(_light.library("felt", Color(0.07, 0.07, 0.075)))
	var band := minf(lower - 0.1, 0.24)
	for sd: float in [-1.0, 1.0]:
		tv.box(Vector3(c.x + sd * s.x * 0.3, lower - 0.03 - band * 0.5, front + 0.004), Vector3(s.x * 0.32, band, 0.008),
				Basis(), [RoomMesh.FRONT])


## A 1937 mirror-lid set: a tall cabinet whose tube faces up in its top, and a lid hinged along the back of the top,
## open at 45 degrees, a mirror on its underside. The picture (the room's screen) is the tube's reflection, upright
## behind the mirror. The mirror is a true one (mirror_view.gd, "Mirror"): it reflects the room for each eye, the film
## lies on the tube's face under the top board, and the upright screen is hidden, so from above or the side the set
## looks as a real one would. The lid is its own mesh: its back is in the line of sight to the reflection (seen only
## from behind: see-through for the sight line, and in front of the picture for the film layer), its frame round the
## mirror.
func _build_mirror_lid(tv: RoomMesh, t: Dictionary) -> void:
	var s: Vector2 = (t["pic"] as Array)[1]
	var bc: Vector3 = (t["body"] as Array)[0]
	var bs: Vector3 = (t["body"] as Array)[1]
	var face := bs.y
	var tc: Vector3 = (t["tube"] as Array)[0]
	var back := bc.z - bs.z * 0.5
	var front := bc.z + bs.z * 0.5
	var hx := bs.x * 0.5
	var board := TOP_BOARD
	# The cabinet up to its top board, a plinth, and the top round the tube's opening.
	tv.box(Vector3(0.0, (face - board) * 0.5, bc.z), Vector3(bs.x, face - board, bs.z), Basis(), [RoomMesh.UP])
	tv.box(Vector3(0.0, 0.04, front + 0.01), Vector3(bs.x + 0.02, 0.08, 0.02), Basis(), [RoomMesh.DOWN])
	var hole := Rect2(-s.x * 0.5 - 0.02, tc.z - s.y * 0.5 - 0.02, s.x + 0.04, s.y + 0.04)
	var y := face - board * 0.5
	tv.box(Vector3(0.0, y, (back + hole.position.y) * 0.5), Vector3(bs.x, board, hole.position.y - back))
	tv.box(Vector3(0.0, y, (hole.end.y + front) * 0.5), Vector3(bs.x, board, front - hole.end.y))
	for sd: float in [-1.0, 1.0]:
		tv.box(Vector3(sd * (hx + hole.end.x) * 0.5, y, hole.get_center().y), Vector3(hx - hole.end.x, board,
				hole.size.y))
	# Three knobs on the front under the top.
	for k in 3:
		Shapes.cylinder(tv, Vector3((k - 1) * 0.1, face - 0.12, front), 0.02, 0.02, 10, Basis(Vector3.RIGHT, PI * 0.5))
	# The lid's frame and edges, in its own mesh.
	var lid: Dictionary = t["lid"]
	var hinge: Vector3 = lid["hinge"]
	var length := float(lid["length"])
	var width := float(lid["width"])
	var along := Vector3(0.0, sqrt(0.5), sqrt(0.5))
	var under := Vector3(0.0, -sqrt(0.5), sqrt(0.5))
	var w := width * 0.5
	var fw := LID_FRAME
	var lm := RoomMesh.new()
	lm.surface(_m("telly_material"))
	Shapes.quad(lm, hinge + along * length * 0.5 - under * board, Vector3(w, 0, 0), along * length * 0.5, -under)
	Shapes.quad(lm, hinge + along * length - under * board * 0.5, Vector3(w, 0, 0), under * board * 0.5, along)
	for sd: float in [-1.0, 1.0]:
		Shapes.quad(lm, hinge + along * length * 0.5 + Vector3(sd * w, 0, 0) - under * board * 0.5, along * length * 0.5,
				under * board * 0.5, Vector3(sd, 0, 0))
		Shapes.quad(lm, hinge + along * length * 0.5 + Vector3(sd * (w - fw * 0.5), 0, 0), Vector3(fw * 0.5, 0, 0),
				along * (length * 0.5 - fw), under)
	for e: float in [fw * 0.5, length - fw * 0.5]:
		Shapes.quad(lm, hinge + along * e, Vector3(w, 0, 0), along * fw * 0.5, under)
	var lid_mi := _add_static("Lid", lm)
	lid_mi.add_to_group(SEE_THROUGH)
	lid_mi.add_to_group("env_in_front")
	# The mirror (mirror_view.gd): a true reflection, the film on the tube's face, the upright screen hidden. In the
	# lid's own plane through the hinge (the frame's strips lie round it, not over it), so the tube's face reflects to
	# the picture's place exactly.
	var mirror := MirrorView.new()
	mirror.name = "Mirror"
	mirror.centre = hinge + along * length * 0.5
	mirror.half_right = Vector3(w - fw, 0, 0)
	mirror.half_up = along * (length * 0.5 - fw)
	mirror.find_flat = _screen_flat
	own(mirror)
	# The tube's dark face in the top, facing up, just under the film (TubePicture lies on the face's plane), reaching
	# under the board round the hole so no light shows through the gap between them.
	tv.surface(_light.library("dark_metal", Color(0.012, 0.014, 0.014)))
	Shapes.quad(tv, Vector3(0.0, tc.y - 0.002, tc.z), Vector3(s.x * 0.5 + 0.05, 0, 0), Vector3(0, 0,
			-(s.y * 0.5 + 0.05)), Vector3.UP)


## The app's screen's flat mesh (main.screen's Flat), or null (a room on its own: tests, tools).
func _screen_flat() -> MeshInstance3D:
	var main := main_node()
	if main == null or main.get("screen") == null:
		return null
	return (main.screen as Node).get_node_or_null("Flat") as MeshInstance3D


## The stand (the trim's material): a chest of drawers, a radiogram, a desk, a tv unit, or a shelf on the wall.
func _build_stand(trim: RoomMesh, t: Dictionary) -> void:
	var sb: Array = t["stand_box"]
	if sb.is_empty():
		return
	var cc: Vector3 = sb[0]
	var cs: Vector3 = sb[1]
	var at := Transform3D(Basis(), Vector3(cc.x, 0.0, cc.z))
	match str(t["stand"]):
		"radiogram", "desk", "tv_unit":
			Furniture.stand(str(t["stand"]), trim, at, cs, {"body": _trim_m})
		"wall":
			trim.box(cc, cs)
			for sd: float in [-1.0, 1.0]:
				trim.box(Vector3(cc.x + sd * (cs.x * 0.5 - 0.08), cc.y - 0.085, cc.z - cs.z * 0.25),
						Vector3(0.025, 0.14, cs.z * 0.5), Basis(), [RoomMesh.UP])
		_:
			trim.box(cc, cs, Basis(), [RoomMesh.DOWN])
			var rows := maxi(int(cs.y / 0.22), 1)
			for k in rows:
				var y := cc.y - cs.y * 0.5 + (k + 0.5) * cs.y / rows
				trim.box(Vector3(cc.x, y, cc.z + cs.z * 0.5 + 0.008), Vector3(cs.x - 0.06, cs.y / rows - 0.04, 0.016))
				trim.box(Vector3(cc.x, y, cc.z + cs.z * 0.5 + 0.025), Vector3(0.12, 0.02, 0.02))


func _build_bed(trim: RoomMesh) -> void:
	var bed := _bed(_p)
	var c: Vector3 = bed[0]
	var s: Vector3 = bed[1]
	trim.box(c + Vector3(0, -0.1, 0), Vector3(s.x, 0.3, s.z), Basis(), [RoomMesh.DOWN])
	trim.box(Vector3(c.x, 0.45, c.z + s.z * 0.5 + 0.02), Vector3(s.x, 0.9, 0.04))
	var duvet := RoomMesh.new()
	duvet.surface(_m("cushions"))
	duvet.rounded_box(c + Vector3(0, 0.12, -0.15), Vector3(s.x + 0.04, 0.16, s.z - 0.3), 0.06, Transform3D(), 1)
	duvet.surface(_m("sheet"))
	duvet.rounded_box(Vector3(c.x, 0.15 + 0.12 + 0.07, c.z + s.z * 0.5 - 0.3), Vector3(s.x - 0.25, 0.14, 0.4), 0.06,
			Transform3D(), 1)
	_add_unbaked("Bed", duvet)


## A brick (or other) chimney breast on a side wall: the firebox's opening with soot inside, a hearth, a mantel
## shelf, logs and a fire whose flames flicker slowly (accent group, the room's Flickering lights holds them).
func _build_fireplace() -> void:
	var b := _breast(_p)
	var c: Vector3 = b[0]
	var size: Vector3 = b[1]
	var sx := signf(c.x)
	var into := Vector3(-sx, 0, 0)
	var face_x := c.x - sx * size.x * 0.5
	var m := RoomMesh.new()
	m.surface(_m("surround"))
	var open := Rect2(size.z * 0.5 - 0.42, 0.15, 0.84, 0.72)
	# The breast's face, along from its front-most end.
	var origin := Vector3(face_x, 0, c.z + size.z * 0.5 * sx)
	Shapes.wall(m, origin, Vector3(0, 0, -sx), into, size.z, size.y, [open])
	for e: float in [-1.0, 1.0]:
		var z := c.z + e * size.z * 0.5
		m.face([Vector3(face_x, 0, z), Vector3(c.x + sx * size.x * 0.5, 0, z), Vector3(c.x + sx * size.x * 0.5, size.y, z),
				Vector3(face_x, size.y, z)], Vector3(0, 0, e))
	m.box(Vector3(face_x - sx * 0.25, 0.025, c.z), Vector3(0.5, 0.05, 1.5), Basis(), [RoomMesh.DOWN])
	m.box(Vector3(face_x - sx * 0.1, 1.18, c.z), Vector3(0.24, 0.06, 1.8))
	_add_static("Fireplace", m)
	var soot := RoomMesh.new()
	soot.surface(_light.library("dark_metal", Color(0.04, 0.035, 0.03)))
	soot.box(Vector3(face_x + sx * 0.18, open.get_center().y, c.z), Vector3(0.36, open.size.y, open.size.x), Basis(),
			[into], true)
	# Logs across the grate.
	for k in 2:
		var z := c.z + (k - 0.5) * 0.12
		Shapes.cylinder(soot, Vector3(face_x + sx * (0.12 + k * 0.08), 0.22, z - 0.25), 0.05, 0.5, 6,
				Basis(Vector3.RIGHT, PI * 0.5))
	_add_static("Firebox", soot)
	var fire_at := Vector3(face_x + sx * 0.15, 0.36, c.z)
	var quads: Array = []
	for k in 3:
		var a := PI * (k / 3.0)
		var across := Vector3(sin(a) * 0.5, 0, cos(a)).normalized() * 0.2
		quads.append([fire_at + Vector3(0, 0.12, (k - 1) * 0.08), across, Vector3(0, 0.2, 0), across.cross(Vector3.UP)])
	var fire := _add_glow("Fire", quads, Procedural.flame(), Color(1.0, 0.7, 0.4), 1.4 * float(_p["fire"]), "accent",
			true)
	_fire_m.append(fire.mesh.surface_get_material(0))
	_bake_omni("Fire", fire_at + into * 0.5 + Vector3(0, 0.2, 0), 4.0, 0.9 * float(_p["fire"]), Color(1.0, 0.6, 0.3))
	_light.add_lamp(fire_at + into * 0.4, Color(1.0, 0.55, 0.25) * 1.2 * float(_p["fire"]), -1.0)


## A column radiator under the window (or on the wall without one), off the wall on its brackets.
func _build_radiator(win: Array) -> void:
	var side := "left"
	var along := 1.5
	var width := 1.0
	if not win.is_empty():
		side = win[0]
		along = (win[1] as Rect2).get_center().x
		width = minf((win[1] as Rect2).size.x, 1.4)
	var w := _wall(_p, side)
	var n: Vector3 = w[2]
	var basis := Basis(Vector3.UP.cross(n), Vector3.UP, n)
	var r := RoomMesh.new()
	r.surface(_m("radiator_material"))
	var cols := int(width / 0.07)
	for k in cols:
		var a := along - width * 0.5 + (k + 0.5) * width / cols
		r.box(_on_wall(_p, side, a, 0.45, 0.1), Vector3(0.045, 0.56, 0.09), basis, [RoomMesh.DOWN])
	r.box(_on_wall(_p, side, along, 0.72, 0.1), Vector3(width, 0.035, 0.07), basis)
	r.box(_on_wall(_p, side, along, 0.18, 0.1), Vector3(width, 0.035, 0.07), basis)
	r.box(_on_wall(_p, side, along - width * 0.5 - 0.04, 0.2, 0.1), Vector3(0.03, 0.03, 0.03), basis)
	_add_static("Radiator", r)


## The fort round the viewer's cushion: walls of two courses of cushions left, right and behind, broom handles at the
## corners, and a bedsheet over them sagging in the middle, hanging down the sides to the cushions, with a short hem
## over the opening.
func _build_fort(trim: RoomMesh) -> void:
	var pillows := RoomMesh.new()
	pillows.surface(_m("cushions"))
	for pl: Array in _pillows():
		pillows.rounded_box(pl[0], pl[1], 0.09, Transform3D(), 1)
	_add_unbaked("Fort", pillows)
	for c: Vector2 in [Vector2(-FORT_HALF - 0.12, FORT_FRONT), Vector2(FORT_HALF + 0.12, FORT_FRONT),
			Vector2(-FORT_HALF - 0.12, FORT_BACK + 0.12), Vector2(FORT_HALF + 0.12, FORT_BACK + 0.12)]:
		var top := FORT_TOP_FRONT if c.y < 0.0 else FORT_TOP_BACK
		trim.box(Vector3(c.x, top * 0.5, c.y), Vector3(0.03, top, 0.03), Basis(), [RoomMesh.DOWN])
	var sheet := RoomMesh.new()
	sheet.surface(_m("sheet"))
	var nx := 12
	var nz := 10
	var hx := FORT_HALF + 0.12
	# The canopy: rows across, each a strip; both sides (seen from inside and from over the top).
	var grid: Array = []
	for j in nz + 1:
		var t := float(j) / nz
		var z := lerpf(FORT_FRONT, FORT_BACK + 0.12, t)
		var line: Array = []
		for i in nx + 1:
			var u := float(i) / nx
			var x := lerpf(-hx, hx, u)
			var y := lerpf(FORT_TOP_FRONT, FORT_TOP_BACK, t) - 0.16 * sin(u * PI) * sin(t * PI) - 0.04 * sin(u * PI)
			line.append(Vector3(x, y, z))
		grid.append(line)
	# The inside face a little inside the outside one: two faces in one place let the bake light the inside from
	# above (the sheet's underside came out near white).
	const INSIDE := 0.012
	for side: float in [-1.0, 1.0]:
		var drop := Vector3(0, -INSIDE, 0) if side > 0.0 else Vector3.ZERO
		for j in nz:
			var a := PackedVector3Array()
			var c := PackedVector3Array()
			var ns := PackedVector3Array()
			for i in nx + 1:
				a.append(grid[j][i] + drop)
				c.append(grid[j + 1][i] + drop)
				ns.append(Vector3.DOWN * side)
			sheet.strip(a, c, ns)
		# The sides: hanging from the canopy's edges to the cushions' tops, a little outside them.
		for e: float in [-1.0, 1.0]:
			var a := PackedVector3Array()
			var c := PackedVector3Array()
			var ns := PackedVector3Array()
			for j in nz + 1:
				var edge: Vector3 = grid[j][0 if e < 0.0 else nx]
				var inward := Vector3(-e * INSIDE, 0, 0) if side > 0.0 else Vector3.ZERO
				a.append(edge + drop + inward)
				c.append(Vector3(e * (hx + 0.08), FORT_WALL, edge.z) + inward)
				ns.append(Vector3(-e * side, 0, 0))
			sheet.strip(a, c, ns)
		# A short hem over the opening.
		var a := PackedVector3Array()
		var c := PackedVector3Array()
		var ns := PackedVector3Array()
		for i in nx + 1:
			var top: Vector3 = grid[0][i] + (Vector3(0, 0, INSIDE) if side > 0.0 else Vector3.ZERO)
			a.append(top)
			c.append(top + Vector3(0, -0.1, -0.01))
			ns.append(Vector3.BACK * side)
		sheet.strip(a, c, ns)
	# In front of part of the picture on purpose (the hem): the film layer steps aside for it (film_layer.gd).
	_add_static("FortSheet", sheet).add_to_group("env_in_front")


## Fairy lights: small warm bulbs on a wire sagging along the fort's hem (or along the front wall's top), flickering
## a little and slowly (accent group: they stay on in the film).
func _build_fairy_lights() -> void:
	var wire := RoomMesh.new()
	wire.surface(_light.library("dark_metal", Color(0.08, 0.1, 0.08)))
	var bulbs := RoomMesh.new()
	var colour := color_param("fairy_colour")
	var glow := float(_p["fairy_glow"])
	bulbs.surface(_lamp(colour, FAIRY_ENERGY * glow, 0.0, "accent", true))
	_fairy_flicker = _flickering[-1]
	var from: Vector3
	var to: Vector3
	var sag := 0.08
	if _fort(_p):
		from = Vector3(-FORT_HALF - 0.12, FORT_TOP_FRONT - 0.12, FORT_FRONT - 0.02)
		to = Vector3(FORT_HALF + 0.12, FORT_TOP_FRONT - 0.12, FORT_FRONT - 0.02)
	else:
		var hw := float(_p["half_width"])
		var y := float(_p["height"]) - 0.12
		from = Vector3(-hw + 0.1, y, float(_p["front_z"]) + 0.05)
		to = Vector3(hw - 0.1, y, float(_p["front_z"]) + 0.05)
		sag = 0.25
	var n := 24
	var prev := from
	for k in range(1, n + 1):
		var t := float(k) / n
		var pt := from.lerp(to, t) + Vector3.DOWN * sag * sin(t * PI)
		Shapes.beam(wire, prev, pt, Vector2(0.006, 0.006))
		if k < n:
			Shapes.lathe(bulbs, [Vector2(0.0, -0.03), Vector2(0.012, -0.02), Vector2(0.01, 0.0)], pt, 5)
		prev = pt
	_add_unbaked("FairyWire", wire)
	_add_lamps("FairyLights", bulbs)
	_fairy_lamp = _light.add_lamp((from + to) * 0.5 + Vector3.DOWN * 0.2, colour * 0.6 * glow, -1.0)
	_bake_omni("Fairy", (from + to) * 0.5 + Vector3(0, -0.2, 0.3), 2.5, 0.3, colour)


## Wall lamps on the side walls, clear of the window, the door and the fireplace: brass sconces with glowing shades
## (house group), or in ice, candles on ledges whose flames flicker (accent).
func _build_lamps(win: Array) -> void:
	var n := int(_p["lamps"])
	if n <= 0:
		return
	var ice := str(_p["style"]) == "ice"
	var mount := RoomMesh.new()
	mount.surface(_m("trim") if ice else _light.library("brass", Color(0.6, 0.45, 0.22)))
	var shades := RoomMesh.new()
	var colour := color_param("lamp_colour")
	shades.surface(_lamp(colour, 1.4, 1.0, "house"))
	var flames: Array = []
	var y := 1.7 if not ice else 1.3
	var count := 0
	for side: String in ["left", "right"]:
		var w := _wall(_p, side)
		var length: float = w[3]
		var blocked: Array[Vector2] = []
		if not win.is_empty() and win[0] == side:
			var r: Rect2 = win[1]
			blocked.append(Vector2(r.position.x - 0.3, r.end.x + 0.3))
		if str(_p["heater"]) == "fireplace" and _fire_side(_p) == side:
			var b := _breast(_p)
			var along := ((b[0] as Vector3) - (w[0] as Vector3)).dot(w[1])
			blocked.append(Vector2(along - 1.1, along + 1.1))
		var d := _door(_p)
		if not d.is_empty() and d[0] == side:
			blocked.append(Vector2((d[1] as Rect2).position.x - 0.3, (d[1] as Rect2).end.x + 0.3))
		# Places along the wall clear of the openings, n of them spread out.
		var clear: Array[float] = []
		for k in 24:
			var a := lerpf(0.8, length - 0.8, (k + 0.5) / 24.0)
			if not blocked.any(func(bl: Vector2) -> bool: return a > bl.x and a < bl.y):
				clear.append(a)
		if clear.is_empty():
			continue
		var picks: Array[float] = []
		for i in n:
			var a := clear[int(round(lerpf(0.0, clear.size() - 1.0, (i + 0.5) / n)))]
			if not (a in picks):
				picks.append(a)
		for along in picks:
			var nrm: Vector3 = w[2]
			var basis := Basis(Vector3.UP.cross(nrm), Vector3.UP, nrm)
			var at := _on_wall(_p, side, along, y, 0.0)
			if ice:
				mount.box(at + nrm * 0.1, Vector3(0.3, 0.06, 0.2), basis)
				Shapes.cylinder(shades, at + nrm * 0.12 + Vector3(0, 0.03, 0), 0.03, 0.14, 8)
				flames.append([at + nrm * 0.12 + Vector3(0, 0.22, 0), basis.x * 0.025, Vector3(0, 0.05, 0), nrm])
				flames.append([at + nrm * 0.12 + Vector3(0, 0.22, 0), nrm * 0.025, Vector3(0, 0.05, 0), basis.x])
			else:
				mount.box(at + nrm * 0.01, Vector3(0.12, 0.2, 0.02), basis)
				Shapes.beam(mount, at + nrm * 0.02, at + nrm * 0.16 + Vector3(0, 0.05, 0), Vector2(0.02, 0.02))
				Shapes.lathe(shades, [Vector2(0.09, 0.0), Vector2(0.07, 0.18)], at + nrm * 0.18, 10)
			var lamp_at := at + nrm * 0.25 + Vector3(0, 0.1, 0)
			_light.add_lamp(lamp_at, colour * float(_light.params["lamp_energy"]) * (0.4 if ice else 0.6),
					cos(deg_to_rad(float(_light.params["lamp_cone_deg"]))))
			_bake_omni("Lamp%d" % count, lamp_at, 3.5, 0.4, colour)
			count += 1
	_add_static("LampMounts", mount)
	_add_lamps("Lamps", shades)
	if not flames.is_empty():
		_add_glow("Candles", flames, Procedural.flame(), Color(1.0, 0.75, 0.45), 1.5, "accent", true)


## The seats in the slots when the room has no seats system: single seats as a MultiMesh; cushions (and hides) as one
## static mesh (unbaked: rounded).
func _build_seats() -> void:
	if draws_seats_elsewhere():
		return
	var slots := seat_slots_for(params)
	var model := str(_p["seat_model"])
	if model != "cushion":
		_build_seat_multimesh(model, _m("seat_cover", true), _m("seat_frame", true), slots, 1962)
		return
	var b := RoomMesh.new()
	var cover := _m("seat_cover")
	var back := _m("seat_frame")
	for s: Dictionary in slots:
		var xf: Transform3D = s["transform"]
		b.surface(cover)
		b.rounded_box(Vector3(0.0, 0.1, -0.05), Vector3(0.66, 0.2, 0.66), 0.08, xf, 2)
		b.surface(back)
		b.rounded_box(Vector3.ZERO, Vector3(0.6, 0.55, 0.18), 0.08,
				xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(18.0)), Vector3(0.0, 0.42, 0.32)), 2)
	_add_unbaked("Cushions", b)


func _param_changed(param: String, value: Variant) -> void:
	match param:
		"outside_glow":
			for m in _outside_m:
				m.set_shader_parameter("energy", float(value) * _group_level("accent"))
		"painting_open":
			_place_painting()
		"fire":
			for e: Array in _flickering:
				if e[0] in _fire_m:
					e[1] = 1.4 * float(value)
		"fairy_glow":
			if not _fairy_flicker.is_empty():
				_fairy_flicker[1] = FAIRY_ENERGY * float(value)
				(_fairy_flicker[0] as ShaderMaterial).set_shader_parameter("energy", FAIRY_ENERGY * float(value)
						* _group_level("accent"))
				_light.set_lamp(_fairy_lamp, color_param("fairy_colour") * 0.6 * float(value))
