extends "res://scripts/env/systems/kit/builder.gd"

const NaveGothic := preload("res://scripts/env/systems/kit/nave_gothic.gd")

## The nave builder (docs/environments.md, "The builders"): a church-like nave to watch in. Two arcades of round
## columns with arches between them, side aisles beyond them, clerestory walls with dim windows, a barrel vault, a
## chancel up three steps where the screen stands under a chancel arch, a rose window in the end wall over the screen,
## candle stands either side of it (they flicker, slowly), and pews in rows (one slot a sitting place, the pews' ends
## at the aisles).
##   Floor, Stone (walls, arcades, the vault, the chancel arch), Columns, Hanging (behind the screen), Pews, Brass,
##   Candles, Rose, Clerestory
## Slots for the kit: niches (the aisles' walls), columns (the arcades' columns), screen, proscenium (the chancel
## arch), rear_wall, floor.

static func spec() -> Dictionary:
	return {
		"kind": "builder",
		"description": "A church-like nave: arcades of columns and arches, side aisles, clerestory walls with dim "
				+ "windows, a barrel vault, a chancel up three steps where the screen stands under a chancel arch, "
				+ "a rose window over it, candles that flicker slowly, pews in rows.",
		"params": PARAMS,
		"requires": ["light"],
		"provides": ["seats", "collision", "sound_room", "bake", "slots"],
		"cost": {"draws": 11, "triangles": 30000, "lights": 0, "particles": 0, "texture_mb": 30},
	}


const PARAMS := {
	"nave_width": {"type": "float", "min": 5.0, "max": 16.0, "default": 7.6,
			"description": "between the arcades' column centres"},
	"aisle_width": {"type": "float", "min": 0.0, "max": 6.0, "default": 2.6,
			"description": "each side aisle, from the columns to the outer wall (0: none)"},
	"rear_z": {"type": "float", "min": 2.0, "max": 40.0, "default": 7.5, "description": "z of the west wall behind"},
	"chancel_z": {"type": "float", "min": -40.0, "max": -4.0, "default": -9.0,
			"description": "z of the chancel's first step and its arch"},
	"chancel_depth": {"type": "float", "min": 2.5, "max": 15.0, "default": 5.0, "description": "the chancel, deep"},
	"chancel_rise": {"type": "float", "min": 0.0, "max": 1.5, "default": 0.54, "description": "three steps up"},
	"bay": {"type": "float", "min": 2.0, "max": 8.0, "default": 3.3, "description": "column to column along the nave"},
	"column_height": {"type": "float", "min": 2.5, "max": 12.0, "default": 4.2,
			"description": "the columns' height, where the arches spring"},
	"column_radius": {"type": "float", "min": 0.15, "max": 1.0, "default": 0.32, "description": "the columns' radius"},
	"wall_height": {"type": "float", "min": 6.0, "max": 30.0, "default": 10.5,
			"description": "the clerestory walls' top, where the vault starts"},
	"vault": {"type": "enum", "values": ["barrel", "flat", "rib"], "default": "barrel",
			"description": "the nave's ceiling: a barrel vault, flat, or (the gothic style's) a pointed rib vault"},
	# The gothic style: since 2026-11-08, the Nave's deep pass ("really improving their quality, imagination, delight,
	# detail, lighting", the user). kit/nave_gothic.gd draws it; the plain style is the nave as it was.
	"style": {"type": "enum", "values": ["plain", "gothic"], "default": "plain",
			"description": "plain: round columns and arches under a barrel vault; gothic: clustered piers, pointed "
			+ "arches, a triforium and a clerestory, rib vaults, aisles with coloured glass, a rose window"},
	"chancel_width": {"type": "float", "min": 0.0, "max": 16.0, "default": 0.0,
			"description": "the gothic chancel's width (0: the nave's and a little more)"},
	"window_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.3, "live": true, "brightness": true,
			"description": "how bright the gothic windows' glass shows (the Moon behind them)"},
	"moonlight": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.35,
			"description": "the Moon's light through the gothic windows, for the bake"},
	"coronae": {"type": "int", "min": 0, "max": 4, "default": 0,
			"description": "gothic: iron coronae of candles hung over the nave, one a bay from the chancel"},
	"coronae_lit": {"type": "bool", "default": true, "description": "gothic: the coronae's candles burn"},
	"votive": {"type": "bool", "default": false,
			"description": "gothic: a stand of small lights in coloured glass in the north aisle's east end"},
	"cloth": {"type": "material", "default": {"library": "felt", "color": [0.8, 0.8, 0.8]},
			"description": "gothic: the hassocks' wool and the hymn books' bindings (each its own colour)"},
	"iron": {"type": "material", "default": {"library": "dark_metal", "color": [0.12, 0.11, 0.1]},
			"description": "gothic: the candle stands and the coronae"},
	"rows_front": {"type": "int", "min": 0, "max": 20, "default": 6, "description": "pews in front of the viewer's"},
	"rows_back": {"type": "int", "min": 0, "max": 20, "default": 4, "description": "pews behind the viewer's"},
	"row_pitch": {"type": "float", "min": 0.8, "max": 2.0, "default": 1.0, "description": "metres a pew"},
	"places_per_pew": {"type": "int", "min": 1, "max": 21, "default": 9,
			"description": "sitting places along a pew (odd: one in the middle, the viewer's)"},
	"place_width": {"type": "float", "min": 0.45, "max": 1.0, "default": 0.6, "description": "a place's width"},
	"screen_size": {"type": "vec2", "min": 1.0, "max": 15.0, "default": [5.6, 3.15],
			"description": "the screen in the chancel, width and height"},
	"screen_bottom": {"type": "float", "min": 0.8, "max": 6.0, "default": 1.9,
			"description": "the picture's bottom edge over the nave's floor"},
	"rose_window": {"type": "bool", "default": true, "description": "a rose window in the end wall over the screen"},
	"rose_radius": {"type": "float", "min": 0.5, "max": 4.0, "default": 1.5, "description": "its radius"},
	"rose_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.45, "live": true, "brightness": true,
			"description": "how bright the rose window shows (dim: night outside)"},
	"clerestory_windows": {"type": "bool", "default": true, "description": "dim windows high in the nave's walls"},
	"candles": {"type": "int", "min": 0, "max": 4, "default": 2, "description": "candle stands either side of the screen"},
	"candle_colour": {"type": "color", "default": [1.0, 0.7, 0.38], "description": "the flames' glow"},
	"flicker": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.8, "live": true, "flicker": true,
			"steady": 0.0, "brightness": true,
			"description": "how much the candles waver (slowly; the room's Flickering lights setting holds them)"},
	"stone": {"type": "material", "default": {"library": "rough_plaster", "color": [0.52, 0.48, 0.42], "tiling": 2.0},
			"description": "the walls, arches and vault"},
	"columns": {"type": "material", "default": {"library": "white_marble", "color": [0.62, 0.58, 0.52]},
			"description": "the columns"},
	"floor": {"type": "material", "default": {"library": "checker_marble_tiles", "color": [0.35, 0.33, 0.3],
			"tiling": 1.2}, "description": "the floor and the chancel's steps"},
	"pews": {"type": "material", "default": {"library": "oak_planks", "color": [0.3, 0.19, 0.11]},
			"description": "the pews"},
	"hanging": {"type": "material", "default": {"library": "velvet", "color": [0.08, 0.04, 0.05], "spill": 1.0},
			"description": "the dark hanging behind the screen"},
	"brass": {"type": "material", "default": {"library": "brass", "color": [0.55, 0.42, 0.22]},
			"description": "the candle stands"},
	"webs": {"type": "material", "default": {"library": "rough_plaster", "color": [0.62, 0.58, 0.52], "tiling": 2.0},
			"description": "the gothic vaults' webs between the ribs (lime-washed)"},
}


# --- From parameters alone ----------------------------------------------------------------------------------------

static func _outer(p: Dictionary) -> float:
	return float(p["nave_width"]) * 0.5 + float(p["aisle_width"])


static func _end_z(p: Dictionary) -> float:
	return float(p["chancel_z"]) - float(p["chancel_depth"])


static func _box(p: Dictionary) -> AABB:
	var ow := _outer(p)
	var top := float(p["wall_height"]) + (float(p["nave_width"]) * 0.5 if str(p["vault"]) == "barrel" else 0.0)
	if str(p.get("style", "plain")) == "gothic" or str(p["vault"]) == "rib":
		top = float(p["wall_height"]) + float(p["nave_width"]) * NaveGothic.CROWN
	var lo := Vector3(-ow, 0.0, _end_z(p))
	return AABB(lo, Vector3(ow * 2.0, top, float(p["rear_z"]) - lo.z))


static func seat_slots_for(p: Dictionary) -> Array:
	var out: Array = []
	for r in range(-int(p["rows_back"]), int(p["rows_front"]) + 1):
		out.append_array(U.row(-r * float(p["row_pitch"]), 0.0, int(p["places_per_pew"]), float(p["place_width"]),
				r, "pew"))
	return out


static func layout(p: Dictionary) -> SeatList:
	return SeatList.new(seat_slots_for(p))


static func screen_for(p: Dictionary) -> Dictionary:
	var s := U.v2(p["screen_size"])
	return {"center": [0.0, float(p["screen_bottom"]) + s.y * 0.5, _end_z(p) + 0.45], "size": [s.x, s.y]}


## The columns' feet along each arcade (z), from the chancel back to the west wall.
static func _column_z(p: Dictionary) -> Array[float]:
	var out: Array[float] = []
	var z := float(p["chancel_z"])
	var bay := float(p["bay"])
	while z < float(p["rear_z"]) - bay * 0.5:
		out.append(z)
		z += bay
	return out


## A pew's parts from its run of slots: [seat centre, seat size, back centre, back size, end x's].
static func _pew(run: Array) -> Array:
	var a: Vector3 = (run[0]["transform"] as Transform3D).origin
	var c: Vector3 = (run[-1]["transform"] as Transform3D).origin
	var w := float(run[0]["width"])
	var x0 := a.x - w * 0.5
	var x1 := c.x + w * 0.5
	var z := a.z
	return [Vector3((x0 + x1) * 0.5, 0.43, z - 0.08), Vector3(x1 - x0, 0.05, 0.42),
			Vector3((x0 + x1) * 0.5, 0.72, z + 0.18), Vector3(x1 - x0, 0.5, 0.05), [x0 - 0.03, x1 + 0.03]]


static func collision_shapes_for(p: Dictionary, with_seats := true) -> Array:
	var box := _box(p)
	var out := U.shell_boxes(box.position, box.end)
	var cz := float(p["chancel_z"])
	var rise := float(p["chancel_rise"])
	var nh := float(p["nave_width"]) * 0.5
	if rise > 0.0:
		out.append(PhysicsShapes.box(Vector3(0.0, rise * 0.5, (cz + _end_z(p)) * 0.5),
				Vector3(nh * 2.0, rise, cz - _end_z(p))))
	var r := float(p["column_radius"])
	var h := float(p["column_height"])
	for z in _column_z(p):
		for s: float in [-1.0, 1.0]:
			out.append(PhysicsShapes.box(Vector3(s * nh, h * 0.5, z), Vector3(r * 2.0, h, r * 2.0)))
	if with_seats:
		for run: Array in U.runs(seat_slots_for(p)):
			var pew := _pew(run)
			out.append(PhysicsShapes.box(Vector3(pew[0].x, 0.23, pew[0].z), Vector3(pew[1].x, 0.46, pew[1].z)))
			out.append(PhysicsShapes.box(pew[2], pew[3]))
	return out


static func slots_for(p: Dictionary) -> Dictionary:
	var ow := _outer(p)
	var nh := float(p["nave_width"]) * 0.5
	var niches: Array = []
	var cols: Array = []
	var zs := _column_z(p)
	for i in zs.size():
		for s: float in [-1.0, 1.0]:
			cols.append({"transform": Transform3D(Basis(), Vector3(s * nh, 0.0, zs[i])),
					"size": [float(p["column_radius"]) * 2.0, float(p["column_height"]), float(p["column_radius"]) * 2.0]})
			if i + 1 < zs.size() and float(p["aisle_width"]) > 0.5:
				var into := Vector3(-s, 0.0, 0.0)
				niches.append({"transform": Transform3D(Basis(Vector3.UP.cross(into), Vector3.UP, into),
						Vector3(s * ow, 0.0, (zs[i] + zs[i + 1]) * 0.5)), "size": [1.4, 3.0, 0.5]})
	var sc := screen_for(p)
	var ss := U.v2(sc["size"])
	return {
		"niches": niches,
		"columns": cols,
		"screen": [{"transform": Transform3D(Basis(), U.v3(sc["center"])), "size": [ss.x, ss.y, 0.1]}],
		"proscenium": [{"transform": Transform3D(Basis(), Vector3(0.0, float(p["chancel_rise"]), float(p["chancel_z"]))),
				"size": [nh * 2.0, float(p["wall_height"]), 0.8]}],
		"rear_wall": [{"transform": Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, float(p["rear_z"]))),
				"size": [ow * 2.0, float(p["wall_height"]), 0.3]}],
		"floor": [{"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0,
				(float(p["chancel_z"]) + float(p["rear_z"])) * 0.5)),
				"size": [nh * 2.0, float(p["rear_z"]) - float(p["chancel_z"]), 0.0]}],
	}


func sound_room() -> Dictionary:
	return {"box": _box(params), "surround_height": 3.0, "array": 3, "array_spacing": 3.3}


# --- Building -----------------------------------------------------------------------------------------------------

func build() -> void:
	if str(params["style"]) == "gothic":
		church = NaveGothic.build(self)
		return
	var nh := float(params["nave_width"]) * 0.5
	var ow := _outer(params)
	var cz := float(params["chancel_z"])
	var ez := _end_z(params)
	var rz := float(params["rear_z"])
	var wall_h := float(params["wall_height"])
	var rise := float(params["chancel_rise"])
	var col_h := float(params["column_height"])
	var col_r := float(params["column_radius"])
	var aisle := float(params["aisle_width"])
	var half_t := col_r * 0.8
	# The nave's side of the walls over the arcades: the vault, the chancel and the end walls meet it.
	var inner := nh - half_t
	var zs := _column_z(params)
	var arch_r := float(params["bay"]) * 0.5 - col_r * 0.6
	var aisle_top := col_h + arch_r + 0.9
	# The floor, the chancel's three steps.
	var fl := RoomMesh.new()
	fl.surface(_mat("floor"))
	fl.face([Vector3(-ow, 0, cz), Vector3(ow, 0, cz), Vector3(ow, 0, rz), Vector3(-ow, 0, rz)], Vector3.UP)
	for k in 3:
		var y := rise * (k + 1) / 3.0
		var z0 := cz - k * 0.35
		var z1 := ez if k == 2 else cz - (k + 1) * 0.35
		fl.face([Vector3(-inner, y, z1), Vector3(inner, y, z1), Vector3(inner, y, z0), Vector3(-inner, y, z0)],
				Vector3.UP)
		fl.face([Vector3(-inner, y - rise / 3.0, z0), Vector3(inner, y - rise / 3.0, z0), Vector3(inner, y, z0),
				Vector3(-inner, y, z0)], Vector3.BACK)
	_add_static("Floor", fl)
	var stone := RoomMesh.new()
	stone.surface(_mat("stone"))
	for s: float in [-1.0, 1.0]:
		var x := s * nh
		for i in zs.size():
			var za: float = zs[i]
			var zb: float = zs[i + 1] if i + 1 < zs.size() else rz
			var mid := (za + zb) * 0.5
			var r := (zb - za) * 0.5 - col_r * 0.6
			var crown := col_h + r + 0.6
			# The arch's soffit, the spandrels either side filled up to over its crown.
			var basis := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0))
			Shapes.arch(stone, Vector3(x, col_h, mid), r, r + 0.01, half_t * 2.0, 12, basis, 0.0, PI, ["inner"])
			for face_s: float in [-1.0, 1.0]:
				var fx := x + face_s * half_t
				var n := Vector3(face_s, 0, 0)
				var arc := PackedVector3Array()
				var top := PackedVector3Array()
				var ns := PackedVector3Array()
				for k in 13:
					var t := PI * k / 12.0
					arc.append(Vector3(fx, col_h + sin(t) * r, mid + cos(t) * r))
					top.append(Vector3(fx, crown, mid + cos(t) * r))
					ns.append(n)
				stone.strip(arc, top, ns)
				# Over the column at the bay's start, between this arch and the one before.
				stone.face([Vector3(fx, col_h, za), Vector3(fx, col_h, mid - r), Vector3(fx, crown, mid - r),
						Vector3(fx, crown, za)], n)
				if i == zs.size() - 1:
					stone.face([Vector3(fx, col_h, mid + r), Vector3(fx, col_h, zb), Vector3(fx, crown, zb),
							Vector3(fx, crown, mid + r)], n)
				if i > 0:
					var prev_mid := (zs[i - 1] + za) * 0.5
					var prev_r := (za - zs[i - 1]) * 0.5 - col_r * 0.6
					stone.face([Vector3(fx, col_h, prev_mid + prev_r), Vector3(fx, col_h, za), Vector3(fx, crown, za),
							Vector3(fx, crown, prev_mid + prev_r)], n)
				# Above: to the clerestory's top on the nave's side, to the aisle's roof on the other.
				var up_to := wall_h if face_s == -s else (aisle_top if aisle > 0.0 else wall_h)
				if up_to > crown:
					stone.face([Vector3(fx, crown, za), Vector3(fx, crown, zb), Vector3(fx, up_to, zb),
							Vector3(fx, up_to, za)], n)
		# The chancel's walls, floor to the top.
		stone.face([Vector3(s * inner, 0, ez), Vector3(s * inner, 0, cz), Vector3(s * inner, wall_h, cz),
				Vector3(s * inner, wall_h, ez)], Vector3(-s, 0, 0))
		if aisle > 0.0:
			var ax := s * ow
			stone.face([Vector3(ax, 0, cz), Vector3(ax, 0, rz), Vector3(ax, aisle_top, rz), Vector3(ax, aisle_top, cz)],
					Vector3(-s, 0, 0))
			stone.face([Vector3(x, aisle_top, cz), Vector3(ax, aisle_top, cz), Vector3(ax, aisle_top, rz),
					Vector3(x, aisle_top, rz)], Vector3.DOWN)
			# The aisle's east end, beside the chancel.
			stone.face([Vector3(s * inner, 0, cz), Vector3(ax, 0, cz), Vector3(ax, aisle_top, cz),
					Vector3(s * inner, aisle_top, cz)], Vector3.BACK)
		if not zs.is_empty() and zs[0] > cz + 0.01:
			stone.face([Vector3(s * inner, 0, cz), Vector3(s * inner, 0, zs[0]), Vector3(s * inner, wall_h, zs[0]),
					Vector3(s * inner, wall_h, cz)], Vector3(-s, 0, 0))
	# The west wall (behind) and the east wall (behind the screen), the vault's half disc over each.
	var vault := str(params["vault"]) == "barrel"
	var low := aisle_top if aisle > 0.0 else wall_h
	stone.face([Vector3(-ow, 0, rz), Vector3(ow, 0, rz), Vector3(ow, low, rz), Vector3(-ow, low, rz)], Vector3.FORWARD)
	stone.face([Vector3(-inner, low, rz), Vector3(inner, low, rz), Vector3(inner, wall_h, rz), Vector3(-inner, wall_h, rz)],
			Vector3.FORWARD)
	stone.face([Vector3(-inner, 0, ez), Vector3(inner, 0, ez), Vector3(inner, wall_h, ez), Vector3(-inner, wall_h, ez)],
			Vector3.BACK)
	if vault:
		for end: Array in [[rz, Vector3.FORWARD], [ez, Vector3.BACK]]:
			var disc: Array = []
			for k in 17:
				var t := PI * k / 16.0
				disc.append(Vector3(cos(t) * inner, wall_h + sin(t) * inner, float(end[0])))
			stone.face(disc, end[1])
		Shapes.arch(stone, Vector3(0, wall_h, (ez + rz) * 0.5), inner, inner + 0.01, rz - ez, 16, Basis(), 0.0, PI,
				["inner"])
	else:
		stone.face([Vector3(-inner, wall_h, ez), Vector3(inner, wall_h, ez), Vector3(inner, wall_h, rz),
				Vector3(-inner, wall_h, rz)], Vector3.DOWN)
	# The chancel arch: piers either side and a deep arch ring over the nave.
	var ch_r := inner - 0.6
	var spring := minf(col_h + 1.2, wall_h - inner - 0.2)
	for s: float in [-1.0, 1.0]:
		stone.box(Vector3(s * (inner - 0.3), (spring + rise) * 0.5, cz - 0.4), Vector3(0.6, spring - rise, 0.8), Basis(),
				[RoomMesh.DOWN, Vector3(s, 0, 0)])
	Shapes.arch(stone, Vector3(0, spring, cz - 0.4), ch_r, inner, 0.8, 16, Basis(), 0.0, PI, ["front", "back", "inner"])
	_add_static("Stone", stone)
	# The columns: a plinth, a shaft, a capital.
	var cols := RoomMesh.new()
	cols.surface(_mat("columns"))
	for z in zs:
		for s: float in [-1.0, 1.0]:
			var at := Vector3(s * nh, 0, z)
			cols.box(at + Vector3(0, 0.15, 0), Vector3(col_r * 2.6, 0.3, col_r * 2.6), Basis(), [RoomMesh.DOWN])
			Shapes.lathe(cols, [Vector2(col_r * 1.15, 0.3), Vector2(col_r * 1.15, 0.38), Vector2(col_r, 0.46),
					Vector2(col_r, col_h - 0.5), Vector2(col_r * 0.92, col_h - 0.42), Vector2(col_r * 1.35, col_h - 0.12)],
					at, 12)
			cols.box(at + Vector3(0, col_h - 0.06, 0), Vector3(col_r * 2.9, 0.12, col_r * 2.9))
	_add_static("Columns", cols)
	# A dark hanging behind the screen.
	var sc := screen_for(params)
	var c := U.v3(sc["center"])
	var size := U.v2(sc["size"])
	var hang := RoomMesh.new()
	hang.surface(_mat("hanging"))
	hang.box(Vector3(0, (rise + c.y + size.y * 0.5 + 0.6) * 0.5, ez + 0.1),
			Vector3(minf(size.x + 1.6, inner * 2.0 - 0.2), c.y + size.y * 0.5 + 0.6 - rise, 0.06), Basis(), [RoomMesh.BACK])
	_add_static("Hanging", hang)
	_build_windows(c, size, ez, inner, ow, wall_h, aisle_top, zs, rz)
	_build_candles(c, size, ez, rise, inner)
	_build_pews()
	# Bake lights: the nave dimly lit from high up, the chancel a little brighter.
	var i := 0
	for z: float in [cz + 3.0, (cz + rz) * 0.5, rz - 3.0]:
		_bake_spot("Nave%d" % i, Vector3(0, wall_h - 0.5, z), true, 60.0, wall_h + 4.0, 0.8, Color(1.0, 0.85, 0.65))
		i += 1


func _build_windows(c: Vector3, size: Vector2, ez: float, nh: float, ow: float, wall_h: float, aisle_top: float,
		zs: Array[float], rz: float) -> void:
	if bool(params["rose_window"]):
		var r := float(params["rose_radius"])
		var at := Vector3(0, minf(c.y + size.y * 0.5 + 0.5 + r, wall_h - r - 0.2), ez + 0.05)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 32:
			var a0 := TAU * k / 32.0
			var a1 := TAU * (k + 1) / 32.0
			for p: Vector2 in [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]:
				st.set_normal(Vector3.BACK)
				st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 - p.y * 0.5))
				st.add_vertex(at + Vector3(p.x * r, p.y * r, 0))
		_rose = _lamp(Color(1, 1, 1), float(params["rose_glow"]), 0.0, "accent")
		_rose.set_shader_parameter("picture", Procedural.rose_window())
		_rose.set_shader_parameter("use_picture", true)
		var mesh := st.commit()
		mesh.surface_set_material(0, _rose)
		_add_mesh("Rose", mesh).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var frame := RoomMesh.new()
		frame.surface(_mat("columns"))
		Shapes.arch(frame, at + Vector3(0, 0, 0.1), r, r + 0.22, 0.3, 32, Basis(), 0.0, TAU, ["front", "inner"])
		_add_static("RoseFrame", frame)
	if bool(params["clerestory_windows"]):
		var quads: Array = []
		var top := wall_h - 0.8
		var bottom := maxf(aisle_top + 0.3, top - 2.4)
		for i in zs.size():
			var za: float = zs[i]
			var zb: float = zs[i + 1] if i + 1 < zs.size() else rz
			for s: float in [-1.0, 1.0]:
				quads.append([Vector3(s * (nh - 0.01), (top + bottom) * 0.5, (za + zb) * 0.5), Vector3(0, 0, 0.45),
						Vector3(0, (top - bottom) * 0.5, 0), Vector3(-s, 0, 0)])
		_add_picture("Clerestory", quads, Procedural.gradient(Color(0.05, 0.07, 0.14), Color(0.1, 0.12, 0.2)),
				Color(1, 1, 1), 0.6, "accent")


var _rose: ShaderMaterial
## The gothic style's window glass (one material for all the windows), the Moon's coloured pools on the floor, and
## what it built (kit/nave_gothic.gd).
var _windows: ShaderMaterial
var _pool: ShaderMaterial
var church = null


func _param_changed(param: String, value: Variant) -> void:
	# The gothic rose is in the steady signs group (the ritual moves accent: the candles), so its glow is its own.
	var group := "signs" if str(params["style"]) == "gothic" else "accent"
	if param == "rose_glow" and _rose != null:
		_rose.set_shader_parameter("energy", float(value) * _group_level(group))
	elif param == "window_glow" and _windows != null:
		_windows.set_shader_parameter("energy", float(value) * _group_level("signs"))
		if _pool != null:
			_pool.set_shader_parameter("energy", float(value) * NaveGothic.POOL_SHARE)


## Candle stands either side of the screen: a brass stand, three candles, the flames (flickering), a stand-in lamp.
func _build_candles(c: Vector3, size: Vector2, ez: float, rise: float, nh: float) -> void:
	var n := int(params["candles"])
	if n <= 0:
		return
	var brass := RoomMesh.new()
	brass.surface(_mat("brass"))
	var wax := RoomMesh.new()
	wax.surface(_lamp(Color(0.95, 0.9, 0.8), 0.25, 1.0, "house"))
	var flames := RoomMesh.new()
	var colour := color_param("candle_colour")
	flames.surface(_lamp(colour, 2.2, 0.0, "accent", true))
	var cone := cos(deg_to_rad(80.0))
	var i := 0
	for s: float in [-1.0, 1.0]:
		for k in n:
			var x := s * minf(size.x * 0.5 + 0.6 + k * 0.7, nh - 0.4)
			var foot := Vector3(x, rise, ez + 1.2 + k * 0.5)
			var h := 1.3 - k * 0.15
			Shapes.lathe(brass, [Vector2(0.18, 0.0), Vector2(0.16, 0.05), Vector2(0.03, 0.12), Vector2(0.025, h),
					Vector2(0.2, h + 0.02), Vector2(0.2, h + 0.05)], foot, 10)
			for j in 3:
				var at := foot + Vector3((j - 1) * 0.12, h + 0.05, 0.0)
				Shapes.cylinder(wax, at, 0.022, 0.2 - j % 2 * 0.05, 8)
				var top := at + Vector3(0, 0.2 - j % 2 * 0.05, 0)
				Shapes.lathe(flames, [Vector2(0.0, 0.0), Vector2(0.012, 0.015), Vector2(0.01, 0.04), Vector2(0.0, 0.065)],
						top, 6)
			_light.add_lamp(foot + Vector3(0, h + 0.3, 0), colour * 0.8, cone)
			_bake_omni("Candle%d" % i, foot + Vector3(0, h + 0.3, 0), 3.5, 0.5, colour)
			i += 1
	_add_static("CandleStands", brass)
	_add_lamps("Candles", wax)
	_add_lamps("Flames", flames)


## The pews: a seat board, a back board and an end either side, one pew a run of places.
func _build_pews() -> void:
	if draws_seats_elsewhere():
		return
	var b := RoomMesh.new()
	b.surface(_mat("pews"))
	for run: Array in U.runs(seat_slots_for(params)):
		var pew := _pew(run)
		b.box(pew[0], pew[1])
		b.box(pew[2], pew[3])
		b.box(Vector3(pew[0].x, 0.2, pew[0].z), Vector3(pew[1].x - 0.06, 0.4, 0.03), Basis(), [RoomMesh.DOWN])
		for x: float in pew[4]:
			b.box(Vector3(x, 0.5, pew[0].z + 0.06), Vector3(0.06, 1.0, 0.62), Basis(), [RoomMesh.DOWN])
	_add_static("Pews", b)
