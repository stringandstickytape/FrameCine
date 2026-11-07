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
## Every parameter marked "auto" (an enum's "auto", 0 or -1 for a number, {} for a material, [0, 0] for a size) takes
## the style's value (STYLE_DEFAULTS); a document sets only what it changes.
##   Floor, Walls, Ceiling, Trim, Window (glass), Outside, Door, Fireplace, Fire, Radiator, Lamps, Screen (the screen's
##   own parts), Painting, Telly, Bed, Fort, FortSheet, FairyLights, Seats or Cushions
## Slots for the kit: side_walls, screen, proscenium, floor, ceiling, corners, window, vista, mantel, fort_opening.

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
	"flicker": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.6, "live": true, "flicker": true,
			"steady": 0.0, "brightness": true,
			"description": "how much the fire, candles and fairy lights waver (slowly; Flickering lights holds them)"},
	"fort": {"type": "enum", "values": ["auto", "on", "off"], "default": "auto",
			"description": "a pillow fort of cushions and a bedsheet round the viewer's seat"},
	"fairy_lights": {"type": "enum", "values": ["auto", "on", "off"], "default": "auto",
			"description": "fairy lights along the fort's front (or the front wall's top without a fort)"},
	"fairy_colour": {"type": "color", "default": [1.0, 0.82, 0.55], "description": "the fairy lights' glow"},
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
			"description": "skirting, frames, the door, the chest of drawers, the bed's frame"},
	"surround": {"type": "material", "default": AUTO_MAT, "description": "the fireplace and its hearth"},
	"radiator_material": {"type": "material", "default": AUTO_MAT, "description": "the radiator"},
	"screen_surface": {"type": "material", "default": AUTO_MAT, "description": "the screen's white"},
	"telly_material": {"type": "material", "default": AUTO_MAT, "description": "the telly's cabinet"},
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
	for k: String in s:
		if _auto(k, p.get(k)):
			out[k] = s[k]
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
			if _fort(p) and bool(p["opening_screen"]):
				# The telly fills the fort's opening: the picture as big as fits in it (its own shape kept), just
				# beyond it.
				var open := Vector2(FORT_HALF * 2.0 - 0.3, FORT_TOP_FRONT - 0.2 - 0.35)
				var k := minf(open.x / size.x, open.y / size.y)
				size *= k
				return [Vector3(0.0, 0.35 + open.y * 0.5, FORT_FRONT - 0.35), size]
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


## The telly's cabinet round the picture and the chest under it: [[centre, size]...].
static func _telly_boxes(p: Dictionary) -> Array:
	var pic := _picture(p)
	var c: Vector3 = pic[0]
	var s: Vector2 = pic[1]
	var bezel := Vector2(maxf(0.06, s.x * 0.1), maxf(0.06, s.y * 0.12))
	var outer := Vector2(s.x + bezel.x * 2.0, s.y + bezel.y * 2.6)
	var depth := clampf(s.x * 0.75, 0.35, 1.2)
	var mid_y := c.y - bezel.y * 0.3
	var out: Array = [[Vector3(0.0, mid_y, c.z - depth * 0.5), Vector3(outer.x, outer.y, depth)]]
	var foot := mid_y - outer.y * 0.5
	if foot > 0.05:
		out.append([Vector3(0.0, foot * 0.5, c.z - depth * 0.5 - 0.02), Vector3(maxf(outer.x + 0.3, 0.9), foot,
				depth + 0.1)])
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
	trim.surface(_m("trim"))
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
	_bake_spot("Ceiling", Vector3(0, h + rise - 0.1, (fz + bz) * 0.5), true, 75.0, h + rise + 1.0, 0.35,
			color_param("lamp_colour"))


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


## The telly on a chest of drawers: a deep cabinet round the picture (wider at the bottom for its controls), the
## chest's drawers.
func _build_telly(trim: RoomMesh) -> void:
	var pic := _picture(_p)
	var c: Vector3 = pic[0]
	var s: Vector2 = pic[1]
	var boxes := _telly_boxes(_p)
	var tv := RoomMesh.new()
	tv.surface(_m("telly_material"))
	var cab: Array = boxes[0]
	var centre: Vector3 = cab[0]
	var size: Vector3 = cab[1]
	# The front's bezel round the picture (the picture's own face is the screen), the body tapering behind.
	var front := c.z
	var fr := Vector2(size.x * 0.5, size.y * 0.5)
	var bottom := centre.y - fr.y
	var top := centre.y + fr.y
	var holes := [Rect2(fr.x - s.x * 0.5, c.y - s.y * 0.5 - bottom, s.x, s.y)]
	Shapes.wall(tv, Vector3(-fr.x, bottom, front), Vector3.RIGHT, Vector3.BACK, size.x, top - bottom, holes)
	var back_z := front - size.z
	tv.box(Vector3(0, centre.y, front - 0.05), Vector3(size.x, size.y, 0.1), Basis(), [RoomMesh.BACK])
	tv.box(Vector3(0, centre.y + 0.02, (front - 0.1 + back_z) * 0.5), Vector3(size.x * 0.7, size.y * 0.75,
			size.z - 0.1), Basis(), [RoomMesh.BACK])
	# A dark glass behind the picture's plane (the screen draws the film in front of it).
	tv.surface(_light.library("dark_metal", Color(0.03, 0.035, 0.035)))
	Shapes.quad(tv, Vector3(c.x, c.y, front - 0.03), Vector3(s.x * 0.5, 0, 0), Vector3(0, s.y * 0.5, 0), Vector3.BACK)
	# Its buttons under the picture.
	for k in 4:
		tv.box(Vector3(fr.x - 0.06 - k * 0.05, bottom + (c.y - s.y * 0.5 - bottom) * 0.5, front + 0.006),
				Vector3(0.03, 0.015, 0.012))
	_add_static("Telly", tv)
	if boxes.size() > 1:
		var chest: Array = boxes[1]
		var cc: Vector3 = chest[0]
		var cs: Vector3 = chest[1]
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
	for side: float in [-1.0, 1.0]:
		for j in nz:
			var a := PackedVector3Array()
			var c := PackedVector3Array()
			var ns := PackedVector3Array()
			for i in nx + 1:
				a.append(grid[j][i])
				c.append(grid[j + 1][i])
				ns.append(Vector3.DOWN * side)
			sheet.strip(a, c, ns)
		# The sides: hanging from the canopy's edges to the cushions' tops, a little outside them.
		for e: float in [-1.0, 1.0]:
			var a := PackedVector3Array()
			var c := PackedVector3Array()
			var ns := PackedVector3Array()
			for j in nz + 1:
				var edge: Vector3 = grid[j][0 if e < 0.0 else nx]
				a.append(edge)
				c.append(Vector3(e * (hx + 0.08), FORT_WALL, edge.z))
				ns.append(Vector3(-e * side, 0, 0))
			sheet.strip(a, c, ns)
		# A short hem over the opening.
		var a := PackedVector3Array()
		var c := PackedVector3Array()
		var ns := PackedVector3Array()
		for i in nx + 1:
			var top: Vector3 = grid[0][i]
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
	bulbs.surface(_lamp(colour, 1.3, 0.0, "accent", true))
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
	_light.add_lamp((from + to) * 0.5 + Vector3.DOWN * 0.2, colour * 0.6, -1.0)
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
