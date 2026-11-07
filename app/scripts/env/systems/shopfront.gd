extends "res://scripts/env/systems/kit/builder.gd"

## The shopfront builder (docs/environments.md, "The builders"): a narrow picture house of about 1906 made in a shop.
## A long hall with a wooden dado, pressed tin on the walls above it and on the ceiling (procedural.gd's pressed_tin
## over a library metal, or the library's own maps), a cornice, a small raised screen end with a framed sheet, the
## shop window and its door behind the viewer with the street's glow beyond, gas lamps on brackets along both walls
## (they flicker, slowly), and room for folding chairs in rows with aisles along the walls.
##   Floor, Stage, Dado, Tin (walls above the dado, cornice, ceiling), ScreenWall, Trim (the sheet's frame, the
##   window's frame, the door), Brass (the lamps' brackets), GasLamps, Window (glass), Street, Seats
## Slots for the kit: booth (the floor at the back corner), side_walls, screen, proscenium, rear_wall, ceiling, floor.

static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "A narrow shopfront picture house of about 1906: a long hall, a wooden dado with pressed tin "
				+ "above it and on the ceiling, a small raised screen end with a framed sheet, the shop window and "
				+ "door behind the seats with the street's glow beyond, gas lamps that flicker slowly, folding "
				+ "chairs in rows. Slots for a tin booth and other kit pieces.",
		"params": PARAMS,
		"requires": ["light"],
		"provides": ["seats", "collision", "sound_room", "bake", "slots"],
		"cost": {"draws": 13, "triangles": 6000, "lights": 0, "particles": 0, "texture_mb": 30},
	}


const PARAMS := {
	"width": {"type": "float", "min": 3.0, "max": 12.0, "default": 5.6, "description": "the hall's width, metres"},
	"height": {"type": "float", "min": 2.6, "max": 8.0, "default": 3.7, "description": "the ceiling's height"},
	"screen_wall_z": {"type": "float", "min": -40.0, "max": -3.0, "default": -10.0,
			"description": "z of the wall the screen stands at"},
	"front_z": {"type": "float", "min": 1.0, "max": 30.0, "default": 6.5,
			"description": "z of the shop window behind the viewer"},
	"rows_front": {"type": "int", "min": 0, "max": 20, "default": 7, "description": "rows in front of the viewer's"},
	"rows_back": {"type": "int", "min": 0, "max": 20, "default": 3, "description": "rows behind the viewer's"},
	"row_pitch": {"type": "float", "min": 0.75, "max": 2.0, "default": 0.95, "description": "metres a row"},
	"chairs_per_row": {"type": "int", "min": 1, "max": 21, "default": 7,
			"description": "chairs along a row (odd: one in the middle, the viewer's)"},
	"chair_pitch": {"type": "float", "min": 0.45, "max": 1.0, "default": 0.56, "description": "chair centres, metres"},
	"seat_model": {"type": "enum", "values": ["folding", "director", "plush"], "default": "folding",
			"description": "the plain chair drawn when the room has no seats system"},
	"chair_wood": {"type": "material", "default": {"library": "oak_veneer", "color": [0.42, 0.28, 0.16]},
			"description": "the chairs' slats"},
	"chair_frame": {"type": "material", "default": {"library": "dark_metal", "color": [0.12, 0.12, 0.12]},
			"description": "the chairs' frames"},
	"stage_depth": {"type": "float", "min": 0.0, "max": 4.0, "default": 1.4, "description": "the raised end, deep"},
	"stage_height": {"type": "float", "min": 0.0, "max": 1.2, "default": 0.55, "description": "the raised end, high"},
	"screen_size": {"type": "vec2", "min": 1.0, "max": 12.0, "default": [3.6, 2.025],
			"description": "the sheet's picture, width and height"},
	"screen_bottom": {"type": "float", "min": 0.6, "max": 4.0, "default": 1.12,
			"description": "the picture's bottom edge over the floor"},
	"sheet_frame": {"type": "bool", "default": true, "description": "a wooden frame round the sheet"},
	"dado_height": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.1,
			"description": "the wooden dado's height (0: tin to the floor)"},
	"tin_pattern": {"type": "enum", "values": ["pressed_tin", "plain"], "default": "pressed_tin",
			"description": "the walls' and ceiling's pattern: pressed tin, or the library material's own"},
	"tin": {"type": "material", "default": {"library": "brushed_steel", "color": [0.74, 0.7, 0.6], "tiling": 0.61},
			"description": "the pressed tin (its tiling is one tile)"},
	"tin_walls": {"type": "bool", "default": true, "description": "tin on the walls above the dado too"},
	"walls": {"type": "material", "default": {"library": "rough_plaster", "color": [0.55, 0.5, 0.42]},
			"description": "the walls above the dado without tin"},
	"floor": {"type": "material", "default": {"library": "rustic_planks", "color": [0.3, 0.2, 0.13]},
			"description": "the floor boards and the raised end"},
	"dado": {"type": "material", "default": {"library": "wood_panelling", "color": [0.28, 0.17, 0.1]},
			"description": "the dado"},
	"trim": {"type": "material", "default": {"library": "walnut_veneer", "color": [0.22, 0.13, 0.08]},
			"description": "the sheet's frame, the window frame and the door"},
	"screen_wall": {"type": "material", "default": {"library": "felt", "color": [0.05, 0.045, 0.045], "spill": 1.0},
			"description": "the wall behind the sheet"},
	"brass": {"type": "material", "default": {"library": "brass", "color": [0.55, 0.42, 0.22]},
			"description": "the gas lamps' brackets"},
	"window": {"type": "bool", "default": true, "description": "the shop window and its door behind the seats"},
	"street_colour": {"type": "color", "default": [0.35, 0.3, 0.26],
			"description": "the street's glow through the window"},
	"street_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.35, "live": true, "brightness": true,
			"description": "how bright the street is"},
	"lamps_per_side": {"type": "int", "min": 0, "max": 4, "default": 3, "description": "gas lamps along each wall"},
	"lamp_height": {"type": "float", "min": 1.5, "max": 4.0, "default": 2.3, "description": "the lamps' height"},
	"lamp_colour": {"type": "color", "default": [1.0, 0.78, 0.5], "description": "the gas flames' glow"},
	"flicker": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.6, "live": true, "flicker": true,
			"steady": 0.0, "brightness": true,
			"description": "how much the gas lamps waver (slowly; the room's Flickering lights setting holds them)"},
}


# --- From parameters alone ----------------------------------------------------------------------------------------

static func _box(p: Dictionary) -> AABB:
	var hw := float(p["width"]) * 0.5
	var lo := Vector3(-hw, 0.0, float(p["screen_wall_z"]))
	return AABB(lo, Vector3(hw * 2.0, float(p["height"]), float(p["front_z"]) - lo.z))


static func seat_slots_for(p: Dictionary) -> Array:
	var out: Array = []
	for r in range(-int(p["rows_back"]), int(p["rows_front"]) + 1):
		out.append_array(U.row(-r * float(p["row_pitch"]), 0.0, int(p["chairs_per_row"]), float(p["chair_pitch"]),
				r, "chair"))
	return out


static func layout(p: Dictionary) -> SeatList:
	return SeatList.new(seat_slots_for(p))


static func screen_for(p: Dictionary) -> Dictionary:
	var s := U.v2(p["screen_size"])
	return {"center": [0.0, float(p["screen_bottom"]) + s.y * 0.5, float(p["screen_wall_z"]) + 0.06],
			"size": [s.x, s.y]}


static func collision_shapes_for(p: Dictionary, with_seats := true) -> Array:
	var box := _box(p)
	var out := U.shell_boxes(box.position, box.end)
	var depth := float(p["stage_depth"])
	var h := float(p["stage_height"])
	if depth > 0.0 and h > 0.0:
		out.append(PhysicsShapes.box(Vector3(0.0, h * 0.5, box.position.z + depth * 0.5), Vector3(box.size.x, h, depth)))
	if with_seats:
		out.append_array(U.seat_boxes(seat_slots_for(p), str(p["seat_model"])))
	return out


static func slots_for(p: Dictionary) -> Dictionary:
	var box := _box(p)
	var hw := box.size.x * 0.5
	var back := box.end.z
	var walls: Array = []
	var z := box.position.z + 2.0
	while z < back - 1.0:
		for s: float in [-1.0, 1.0]:
			var into := Vector3(-s, 0.0, 0.0)
			walls.append({"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into),
					Vector3(s * hw, float(p["dado_height"]), z)), "size": [2.0, box.size.y - float(p["dado_height"]), 0.3]})
		z += 2.5
	var sc: Dictionary = screen_for(p)
	var ss := U.v2(sc["size"])
	var booth_x := hw - 1.3
	return {
		"booth": [{"transform": Transform3D(Basis(Vector3.UP, PI), Vector3(booth_x, 0.0, back - 1.2)),
				"size": [2.2, minf(2.4, box.size.y - 0.3), 2.0]}],
		"side_walls": walls,
		"screen": [{"transform": Transform3D(Basis(), U.v3(sc["center"])), "size": [ss.x, ss.y, 0.1]}],
		"proscenium": [{"transform": Transform3D(Basis(), Vector3(0.0, float(p["stage_height"]), box.position.z)),
				"size": [box.size.x, box.size.y - float(p["stage_height"]), 0.5]}],
		"rear_wall": [{"transform": Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, back)),
				"size": [box.size.x, box.size.y, 0.3]}],
		"ceiling": [{"transform": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, box.size.y, box.get_center().z)),
				"size": [box.size.x, box.size.z, 0.2]}],
		"floor": [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, box.get_center().z)),
				"size": [box.size.x, box.size.z, 0.0]}],
	}


func sound_room() -> Dictionary:
	return {"box": _box(params), "surround_height": 2.4, "array": 2, "array_spacing": 3.0}


# --- Building -----------------------------------------------------------------------------------------------------

func build() -> void:
	var box := _box(params)
	var lo := box.position
	var hi := box.end
	var hw := box.size.x * 0.5
	var dado_h := float(params["dado_height"])
	var stage_d := float(params["stage_depth"])
	var stage_h := float(params["stage_height"])
	var floor_m := _mat("floor")
	# The floor and the raised end.
	var fl := RoomMesh.new()
	fl.surface(floor_m)
	fl.face([Vector3(-hw, 0.0, lo.z + stage_d), Vector3(hw, 0.0, lo.z + stage_d), Vector3(hw, 0.0, hi.z),
			Vector3(-hw, 0.0, hi.z)], Vector3.UP)
	if stage_d > 0.0 and stage_h > 0.0:
		fl.box(Vector3(0.0, stage_h * 0.5, lo.z + stage_d * 0.5), Vector3(box.size.x, stage_h, stage_d), Basis(),
				[RoomMesh.LEFT, RoomMesh.RIGHT, RoomMesh.DOWN, RoomMesh.FRONT])
	_add_static("Floor", fl)
	# The dado: panelling along the side walls and the back, with a rail on top.
	var dado := RoomMesh.new()
	dado.surface(_mat("dado"))
	if dado_h > 0.0:
		for s: float in [-1.0, 1.0]:
			var x := s * (hw - 0.02)
			var from := lo.z + (stage_d if stage_h > 0.0 else 0.0)
			dado.box(Vector3(x, dado_h * 0.5, (from + hi.z) * 0.5), Vector3(0.04, dado_h, hi.z - from), Basis(),
					[Vector3(s, 0, 0), RoomMesh.DOWN])
			dado.box(Vector3(s * (hw - 0.04), dado_h + 0.03, (from + hi.z) * 0.5), Vector3(0.08, 0.06, hi.z - from),
					Basis(), [Vector3(s, 0, 0)])
	_add_static("Dado", dado)
	# Pressed tin: the walls above the dado, a cornice, the ceiling.
	var tin := RoomMesh.new()
	var pattern := str(params["tin_pattern"])
	var tin_m := _patterned("tin", pattern)
	var wall_m := tin_m if bool(params["tin_walls"]) else _mat("walls")
	_wall_m = wall_m
	tin.surface(wall_m)
	for s: float in [-1.0, 1.0]:
		var x := s * hw
		tin.face([Vector3(x, dado_h, lo.z), Vector3(x, dado_h, hi.z), Vector3(x, hi.y, hi.z), Vector3(x, hi.y, lo.z)],
				Vector3(-s, 0, 0))
		if dado_h > 0.0:
			# Behind the dado's boards (seen at the raised end, where the dado stops).
			tin.face([Vector3(x, 0.0, lo.z), Vector3(x, 0.0, lo.z + stage_d + 0.01), Vector3(x, dado_h, lo.z + stage_d + 0.01),
					Vector3(x, dado_h, lo.z)], Vector3(-s, 0, 0))
	if not bool(params["window"]):
		tin.face([Vector3(-hw, 0.0, hi.z), Vector3(hw, 0.0, hi.z), Vector3(hw, hi.y, hi.z), Vector3(-hw, hi.y, hi.z)],
				Vector3.FORWARD)
	tin.surface(tin_m)
	tin.face([Vector3(-hw, hi.y, lo.z), Vector3(hw, hi.y, lo.z), Vector3(hw, hi.y, hi.z), Vector3(-hw, hi.y, hi.z)],
			Vector3.DOWN)
	# The cornice: a 45-degree cove where the walls meet the ceiling.
	var cove := 0.22
	for s: float in [-1.0, 1.0]:
		tin.face([Vector3(s * hw, hi.y - cove, lo.z), Vector3(s * hw, hi.y - cove, hi.z),
				Vector3(s * (hw - cove), hi.y, hi.z), Vector3(s * (hw - cove), hi.y, lo.z)],
				Vector3(-s, -1.0, 0.0).normalized())
	_add_static("Tin", tin)
	_build_screen_end(lo, hi, hw)
	if bool(params["window"]):
		_build_front(hi, hw)
	_build_lamps(lo, hi, hw)
	var model := str(params["seat_model"])
	_build_seat_multimesh(model, _mat("chair_wood", true), _mat("chair_frame", true), seat_slots_for(params), 1906)


func _build_screen_end(lo: Vector3, hi: Vector3, hw: float) -> void:
	var wall := RoomMesh.new()
	wall.surface(_mat("screen_wall"))
	wall.face([Vector3(-hw, 0.0, lo.z), Vector3(hw, 0.0, lo.z), Vector3(hw, hi.y, lo.z), Vector3(-hw, hi.y, lo.z)],
			Vector3.BACK)
	_add_static("ScreenWall", wall)
	if not bool(params["sheet_frame"]):
		return
	var sc := screen_for(params)
	var c := U.v3(sc["center"])
	var size := U.v2(sc["size"])
	var trim := RoomMesh.new()
	trim.surface(_mat("trim"))
	var t := 0.12
	var z := lo.z + 0.05
	var half := size * 0.5 + Vector2(0.08, 0.08)
	for s: float in [-1.0, 1.0]:
		trim.box(Vector3(s * (half.x + t * 0.5), c.y, z), Vector3(t, half.y * 2.0 + t * 2.0, 0.1), Basis(),
				[RoomMesh.FRONT])
		trim.box(Vector3(0.0, c.y + s * (half.y + t * 0.5), z), Vector3(half.x * 2.0, t, 0.1), Basis(),
				[RoomMesh.FRONT])
	_add_static("Trim", trim)


## The shop window (glass in a wooden frame with a stall riser under it), the door beside it, a transom, the street's
## glow beyond.
func _build_front(hi: Vector3, hw: float) -> void:
	var z := hi.z
	var door_w := 0.95
	var door_x0 := -hw + 0.25
	var door_x1 := door_x0 + door_w
	var win_x0 := door_x1 + 0.25
	var win_x1 := hw - 0.25
	var sill := 0.75
	var top := minf(2.75, hi.y - 0.5)
	var trim := RoomMesh.new()
	trim.surface(_mat("trim"))
	var walls := RoomMesh.new()
	walls.surface(_wall_m)
	# The front's wall round the openings, the stall riser under the window, the door's leaf.
	walls.face([Vector3(-hw, top, z), Vector3(hw, top, z), Vector3(hw, hi.y, z), Vector3(-hw, hi.y, z)], Vector3.FORWARD)
	trim.box(Vector3((win_x0 + win_x1) * 0.5, sill * 0.5, z - 0.03), Vector3(win_x1 - win_x0, sill, 0.06), Basis(),
			[RoomMesh.BACK])
	for x_pair: Vector2 in [Vector2(-hw, door_x0), Vector2(door_x1, win_x0), Vector2(win_x1, hw)]:
		trim.box(Vector3((x_pair.x + x_pair.y) * 0.5, top * 0.5, z - 0.04), Vector3(x_pair.y - x_pair.x, top, 0.08),
				Basis(), [RoomMesh.BACK])
	trim.box(Vector3(0.0, top + 0.05, z - 0.05), Vector3(hw * 2.0, 0.1, 0.1), Basis(), [RoomMesh.BACK])
	trim.box(Vector3((win_x0 + win_x1) * 0.5, sill + 0.03, z - 0.06), Vector3(win_x1 - win_x0, 0.06, 0.12))
	# Glazing bars: two uprights in the window, a bar across the door's glass.
	for k in 2:
		var x := lerpf(win_x0, win_x1, (k + 1) / 3.0)
		trim.box(Vector3(x, (sill + top) * 0.5, z - 0.03), Vector3(0.05, top - sill, 0.05))
	var door_glass := 1.2
	trim.box(Vector3((door_x0 + door_x1) * 0.5, door_glass * 0.5, z - 0.02), Vector3(door_w, door_glass, 0.05), Basis(),
			[RoomMesh.BACK])
	trim.box(Vector3(door_x1 - 0.1, 1.0, z - 0.07), Vector3(0.04, 0.12, 0.05))
	_add_static("Front", walls)
	_add_static("Shopfront", trim)
	var glass := RoomMesh.new()
	glass.surface(GLASS)
	Shapes.quad(glass, Vector3((win_x0 + win_x1) * 0.5, (sill + top) * 0.5, z - 0.02),
			Vector3((win_x1 - win_x0) * 0.5, 0, 0), Vector3(0, (top - sill) * 0.5, 0), Vector3.FORWARD)
	Shapes.quad(glass, Vector3((door_x0 + door_x1) * 0.5, (door_glass + top) * 0.5, z - 0.02),
			Vector3(door_w * 0.5, 0, 0), Vector3(0, (top - door_glass) * 0.5, 0), Vector3.FORWARD)
	_add_glass("Window", glass, Color(0.6, 0.66, 0.62), 0.08)
	# The street beyond: a dim, warm glow low down (lamplight on the pavement), dark above.
	var street := color_param("street_colour")
	var pic := Procedural.gradient(street * 0.25, street)
	var m := _add_picture("Street", [[Vector3(0.0, hi.y * 0.5, z + 2.5), Vector3(hw * 2.0, 0, 0),
			Vector3(0, hi.y * 0.7, 0), Vector3.FORWARD]], pic, Color(1, 1, 1), float(params["street_glow"]), "accent")
	_street = m.mesh.surface_get_material(0)


var _street: ShaderMaterial
var _wall_m: ShaderMaterial


func _param_changed(param: String, value: Variant) -> void:
	if param == "street_glow" and _street != null:
		_street.set_shader_parameter("energy", float(value) * _group_level("accent"))


## Gas lamps on brass brackets: a bracket arm, a glowing glass globe (house group, flickering), a stand-in lamp and a
## bake light each.
func _build_lamps(lo: Vector3, hi: Vector3, hw: float) -> void:
	var n := int(params["lamps_per_side"])
	if n <= 0:
		return
	var brass := RoomMesh.new()
	brass.surface(_mat("brass"))
	var globes := RoomMesh.new()
	globes.surface(_lamp(color_param("lamp_colour"), 1.5, 1.0, "house", true))
	var y := float(params["lamp_height"])
	var lamp_c: Color = color_param("lamp_colour") * float(_light.params["lamp_energy"])
	var cone := cos(deg_to_rad(float(_light.params["lamp_cone_deg"])))
	var i := 0
	for s: float in [-1.0, 1.0]:
		for k in n:
			var z := lerpf(lo.z + 2.5, hi.z - 1.8, (k + 0.5) / n)
			var at := Vector3(s * (hw - 0.3), y, z)
			brass.box(Vector3(s * (hw - 0.01), y - 0.05, z), Vector3(0.02, 0.22, 0.12))
			Shapes.beam(brass, Vector3(s * hw, y - 0.08, z), Vector3(s * (hw - 0.3), y - 0.12, z), Vector2(0.025, 0.025))
			brass.box(Vector3(at.x, y - 0.15, z), Vector3(0.06, 0.04, 0.06))
			Shapes.lathe(globes, [Vector2(0.03, -0.13), Vector2(0.08, -0.06), Vector2(0.085, 0.02),
					Vector2(0.05, 0.08), Vector2(0.02, 0.1)], at, 8)
			_light.add_lamp(at, lamp_c, cone)
			_bake_omni("Gas%d" % i, at, 4.0, 0.6, color_param("lamp_colour"))
			i += 1
	_add_static("Brass", brass)
	_add_lamps("GasLamps", globes)
