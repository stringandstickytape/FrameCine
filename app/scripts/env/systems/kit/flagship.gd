extends RefCounted

## The Flagship's hall (docs/environments.md, "Room: Flagship"; since 2026-11-08: "continue working on the
## environments one-by-one like you did with the bathysphere, really improving their quality, imagination, delight,
## detail, lighting and so on. Better to do a smaller number of incredible superb ones than a large number not so",
## the user, 2026-11-08). The finest modern hall in a capital city, invented and unnamed: understated luxury, its
## delight in restraint and craft. Dressed over an auditorium builder's tiers, seats, stage and doors:
##   - side walls of folded acoustic panels in charcoal felt (a sawtooth in plan: broad faces turned to the seats,
##     short returns turned to the screen), a bronze fin on every ridge, a walnut dado below them following the rake
##     and, between dado and panels, a warm light slot washing up the folds (per vertex: brightest low in the folds)
##   - a ceiling of long acoustic baffles running to the screen, a band of cool light along each wall from a cove
##     ledge, and between the baffles a faint starlight of pinholes (static; kit `starlight`, a setting)
##   - the curved screen in black velvet masking that follows its curve, a slim champagne-bronze frame round it, and
##     beyond the frame a proscenium of walnut slats on black, washed from the stage's lip and from over the frame
##   - the stage's front a perforated grille (the speakers behind it), surround speakers on the walls, the
##     projection port glowing in a walnut band on the rear wall among slats
## flagship_rows: the rows' furniture round the recliners (seats.gd `recliner`): fixed armrests between the seats, each
## with a brushed-steel cupholder ring and the seat's number on a small plate, lit row letters on the end arms,
## brushed-steel nosings on the aisle steps, a frameless glass balustrade with a lit cap rail at the front row.
## Everything is ours, drawn from boxes, strips and grids; no figure, no brand.
##
## The wash: the light slot's and the coves' light is worked out per vertex when the hall is built (the vertex
## colour's alpha) and shown by the house shader's `vertex_light` (room_material.gdshaderinc), which this hall sets
## each frame from the kit's cove_colour, `cove` and the house lamps' level: amber before the film, out in the film.
## In a bake the washed surfaces are emitters, so their light reaches the floor and the steps.
##
## Cost: the walls, ceiling, front and rear go into the kit's baked mesh (PieceStatic) by material; the slats, fins,
## arms and rings into the unbaked mesh (PieceSoft); the light lines into PieceLamps; the stars, the seat numbers and
## the row letters are a mesh each (Starlight, SeatNumbers, RowLetters); the balustrade's glass PieceGlass.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const LAMP_SHADER := preload("res://shaders/room_lamp.gdshader")
const ProcCache := preload("res://scripts/env/proc_cache.gd")

## The side walls' folded panels: a bay's length (about), how far a ridge stands out, where in the bay the fold
## meets the wall (the broad face turned to the seats before it, the return after); the panels' top (under the cove
## ledge); the dado's top over the steps' noses.
const BAY := 1.24
const FOLD_DEPTH := 0.22
const FOLD_AT := 0.74
const PANEL_TOP := 8.6
const DADO := 1.05
## The cove ledge round the top of the walls: how far it stands out, its fascia's height.
const LEDGE_D := 0.4
const LEDGE_H := 0.25
## The ceiling's baffles: pitch across, depth, thickness; the band along each wall left clear for the cove's light.
const BAFFLE_PITCH := 0.7
const BAFFLE_D := 0.55
const BAFFLE_W := 0.05
const BAFFLE_X := 11.9
## The starlight: pinholes in the ceiling between the baffles.
const STARS := 1100
const STAR_ENERGY := 2.2
## The masking round the picture (metres past its edges), the frame round the masking (face width, depth), the
## slats of the proscenium (pitch, width, depth).
const MASK := 0.65
const FRAME_W := 0.07
const FRAME_D := 0.12
## (Bold and few: thin slats close together shimmered in a moire from the seats, 18 m off.)
const SLAT_PITCH := 0.28
const SLAT_W := 0.11
const SLAT_D := 0.08
## The handrail along the stepped aisles, over the steps' noses.
const RAIL_Y := 0.85
## The armrests between the recliners: width (seats.gd RECLINER_ARM), height, depth, their middle's z in a seat's frame;
## the cupholder ring's radius and place.
const ARM_W := 0.14
const ARM_H := 0.66
const ARM_D := 0.6
const ARM_Z := -0.08
const CUP_R := 0.044
const CUP_Z := -0.3
## The wash: the light slot's (warm: the kit's cove_colour) and the ceiling coves' (cool) energy on the washed faces.
const WASH := 2.4
const COOL := Color(0.62, 0.74, 1.0)
const COOL_WASH := 1.1
## The light lines' glow: the slots, the rail's underside, the balustrade's cap (one material, one draw).
const SLOT_ENERGY := 1.6

## The surfaces' colours (sRGB, as a material parameter's): deep charcoal felt (dark enough to vanish in the film,
## light enough for the wash to show its folds), dark walnut, champagne bronze.
const FELT := Color(0.14, 0.135, 0.13)
const WALNUT := Color(0.3, 0.19, 0.12)
const BRONZE := Color(0.55, 0.46, 0.34)


## The hall's own meshes and materials (kept on the kit's ctx.halls; kit.gd calls finish() and tick()).
class Hall:
	var kit: Node
	## Materials the warm wash (the slot, the stage's lip) and the cool wash (the coves) light: their vertex_light.
	var warm: Array[ShaderMaterial] = []
	var cool: Array[ShaderMaterial] = []
	## The starlight: its mesh's arrays (built with the hall), its material, its level now (eased).
	var stars := {}
	var star_m: ShaderMaterial
	var star_level := -1.0
	## The seat numbers and the row letters: quads [centre, right, up, normal, cell].
	var numbers: Array = []
	var letters: Array = []
	## The balustrade's glass (its own mesh: clearer than the kit's glass).
	var glass := RoomMesh.new()
	## The warm light lines' glow (the slots, the rail's underside, the balustrade's cap): one material, one draw.
	var line_m: ShaderMaterial
	var _key := Color(-1, -1, -1)

	func line(k: Node) -> ShaderMaterial:
		if line_m == null:
			line_m = k._lamp(k.cove_colour_now(), SLOT_ENERGY, 0.0, "house")
		return line_m

	func finish(k: Node) -> void:
		if glass.triangle_count() > 0:
			var gi: MeshInstance3D = k._add_glass("Balustrade", glass, Color(0.2, 0.23, 0.25), 0.025)
			# Clear glass: only a faint edge where the view grazes it (the kit's rim greyed it from the aisles).
			(gi.material_override as ShaderMaterial).set_shader_parameter("rim", 0.07)
		if not stars.is_empty():
			star_m = ShaderMaterial.new()
			star_m.shader = LAMP_SHADER
			star_m.set_shader_parameter("use_vertex_colour", true)
			star_m.set_shader_parameter("house_reference", float(k.room.get("ambient_level")))
			star_m.set_shader_parameter("energy", 0.0)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = stars["v"]
			arrays[Mesh.ARRAY_NORMAL] = stars["n"]
			arrays[Mesh.ARRAY_COLOR] = stars["c"]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, star_m)
			var mi: MeshInstance3D = k._add_mesh("Starlight", mesh)
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if not numbers.is_empty():
			# Engraved numbers on brushed steel, lit as the room is (the fill, the lamps, the film's spill).
			var m: ShaderMaterial = k._light.from_param({"library": "brushed_steel", "color": [0.72, 0.7, 0.66]}, true)
			m.set_shader_parameter("albedo_map", Glyphs.atlas(false))
			m.set_shader_parameter("use_mesh_uv", true)
			m.set_shader_parameter("uv_repeat", Vector2.ONE)
			m.set_shader_parameter("normal_strength", 0.2)
			var mi: MeshInstance3D = k._add_mesh("SeatNumbers", _quads(numbers, m))
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if not letters.is_empty():
			# The row letters glow on the end arms (the steps' group: at a whisper in the film).
			var m: ShaderMaterial = k._lamp(Color(0.72, 0.84, 1.0), 1.2, 0.0, "steps")
			m.set_shader_parameter("picture", Glyphs.atlas(true))
			m.set_shader_parameter("use_picture", true)
			var mi: MeshInstance3D = k._add_mesh("RowLetters", _quads(letters, m))
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_update(0.0, true)

	func tick(delta: float) -> void:
		_update(delta, false)

	## The washes' light and the stars now: the kit's cove colour and level times the house lamps'; the stars ease
	## toward their level over about a second (a setting jumps; their light never does).
	func _update(delta: float, now: bool) -> void:
		var house: float = kit._group_level("house")
		var c: Color = kit.cove_colour_now() * float(kit.params["cove"]) * house
		if not c.is_equal_approx(_key):
			_key = c
			for m in warm:
				m.set_shader_parameter("vertex_light", Vector3(c.r, c.g, c.b) * WASH)
			var k := float(kit.params["cove"]) * house * COOL_WASH
			for m in cool:
				m.set_shader_parameter("vertex_light", Vector3(COOL.r, COOL.g, COOL.b) * k)
		if star_m == null:
			return
		var target := float(kit.params["starlight"]) * lerpf(float(kit.params["starlight_film"]), 1.0, house)
		star_level = target if now or star_level < 0.0 else move_toward(star_level, target, delta * 1.0)
		star_m.set_shader_parameter("energy", STAR_ENERGY * star_level)

	## The starlight's level now (tests): 0 out .. 1 as bright as it goes.
	func starlight_level() -> float:
		return maxf(star_level, 0.0)

	## Quads with their own cells of the glyph atlas: [centre, half right, half up, normal, cell].
	static func _quads(qs: Array, m: Material) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for q: Array in qs:
			var c: Vector3 = q[0]
			var r: Vector3 = q[1]
			var u: Vector3 = q[2]
			var n: Vector3 = q[3]
			var cell: Rect2 = Glyphs.cell(int(q[4]))
			var corners := [c - r + u, c + r + u, c + r - u, c - r - u]
			var uvs := [cell.position, Vector2(cell.end.x, cell.position.y), cell.end, Vector2(cell.position.x,
					cell.end.y)]
			var order := [0, 1, 2, 0, 2, 3]
			if (corners[2] - corners[0]).cross(corners[1] - corners[0]).dot(n) < 0.0:
				order = [0, 2, 1, 0, 3, 2]
			for i: int in order:
				st.set_normal(n)
				st.set_uv(uvs[i])
				st.add_vertex(corners[i])
		var mesh := st.commit()
		mesh.surface_set_material(0, m)
		return mesh


## The seat numbers (1 to 25) and the row letters (A to M) in a 5 x 7 face of our own, one atlas.
class Glyphs:
	const FONT := {
		"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
		"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
		"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
		"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
		"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
		"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
		"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
		"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
		"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
		"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
		"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
		"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
		"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
		"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
		"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
		"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
		"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
		"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
		"I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
		"J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
		"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
		"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
		"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	}
	## The atlas: 8 x 5 cells; cells 0..24 the numbers 1..25, 25..38 the letters A..N. A font pixel is SCALE texels.
	const COLS := 8
	const ROWS := 5
	const SCALE := 3
	const CELL := Vector2i(16, 10)
	const LETTERS := "ABCDEFGHIJKLMN"
	static var _atlas := {}

	static func text_of(cell_index: int) -> String:
		return str(cell_index + 1) if cell_index < 25 else LETTERS[cell_index - 25]

	static func cell(i: int) -> Rect2:
		return Rect2(Vector2(float(i % COLS) / COLS, float(i / COLS) / ROWS), Vector2(1.0 / COLS, 1.0 / ROWS))

	## lit: light glyphs on black (the row letters' glow); else dark engraving on a pale plate (the seat numbers).
	static func atlas(lit: bool) -> Texture2D:
		if _atlas.has(lit):
			return _atlas[lit]
		var img := ProcCache.image("flagship.gd:_atlas:" + str(lit), func() -> Image: return _draw_atlas(lit))
		_atlas[lit] = ImageTexture.create_from_image(img)
		return _atlas[lit]

	static func _draw_atlas(lit: bool) -> Image:
		var w := COLS * CELL.x * SCALE
		var h := ROWS * CELL.y * SCALE
		var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
		var ground := Color(0.02, 0.02, 0.025) if lit else Color(0.78, 0.77, 0.74)
		var ink := Color(1.0, 1.0, 1.0) if lit else Color(0.06, 0.06, 0.065)
		img.fill(ground)
		for i in 25 + LETTERS.length():
			var t := text_of(i)
			var width := t.length() * 6 - 1
			var ox := (i % COLS) * CELL.x + (CELL.x - width) / 2
			var oy := (i / COLS) * CELL.y + (CELL.y - 7) / 2
			for ch_i in t.length():
				var rows: Array = FONT[t[ch_i]]
				for y in 7:
					var line: String = rows[y]
					for x in 5:
						if line[x] == "1":
							img.fill_rect(Rect2i((ox + ch_i * 6 + x) * SCALE, (oy + y) * SCALE, SCALE, SCALE), ink)
		img.generate_mipmaps()
		return img


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, e: Dictionary) -> void:
	match piece:
		"flagship_hall":
			_hall(c, e)
		"flagship_rows":
			_rows(c, e)
	for b: RoomMesh in [c.s, c.u, c.lit]:
		b.colour = Color.WHITE


## The hall on the kit's ctx (made with the first piece).
static func hall(c: Object) -> Hall:
	for h: Object in c.halls:
		if h is Hall:
			return h
	var h := Hall.new()
	h.kit = c.kit
	c.halls.append(h)
	return h


# --- Helpers ----------------------------------------------------------------------------------------------------------

static func _lin(colour: Color, alpha := 0.0) -> Color:
	var l := colour.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _layout(c: Object) -> Auditorium.Layout:
	return Auditorium.layout(c.builder_params)


## The screen's arc (the document's screen and curve: the picture is a cylinder's part round a point in front of it,
## its radius the seat's distance over the curve, as curved_screen.gd makes it): {r, cz (the axis' z), half (the
## picture's half arc), bottom, top}. Flat: a radius so large the arc is a plane.
static func arc(c: Object) -> Dictionary:
	var d: Variant = c.room.get("doc")
	var s: Dictionary = (d as Dictionary).get("screen", {}) if d is Dictionary else {}
	var ce: Array = s.get("center", [0.0, 1.2, -18.2])
	var sz: Array = s.get("size", [20.0, 8.4])
	var curve := float(s.get("curve", 0.0))
	var dist := absf(float(ce[2]))
	var r := dist / curve if curve > 0.01 else 100000.0
	return {"r": r, "cz": float(ce[2]) + r, "half": float(sz[0]) * 0.5, "bottom": float(ce[1]) - float(sz[1]) * 0.5,
			"top": float(ce[1]) + float(sz[1]) * 0.5}


## A point on the arc: at angle phi from the middle, height y, d metres behind the picture's surface.
static func ap(a: Dictionary, phi: float, y: float, d := 0.0) -> Vector3:
	var r := float(a["r"]) + d
	return Vector3(sin(phi) * r, y, float(a["cz"]) - cos(phi) * r)


## The arc's normal at phi (towards the seats).
static func an(phi: float) -> Vector3:
	return Vector3(-sin(phi), 0.0, cos(phi))


## The arc's angle where it meets x, d behind the picture.
static func phi_at(a: Dictionary, x: float, d := 0.0) -> float:
	return asin(clampf(x / (float(a["r"]) + d), -1.0, 1.0))


static func _basis_at(phi: float) -> Basis:
	return Basis(Vector3(cos(phi), 0.0, sin(phi)), Vector3.UP, an(phi))


static func _stage_front(c: Object, l: Auditorium.Layout) -> float:
	return l.lo.z + float(c.builder_params.get("stage_depth", 1.9))


## The steps' noses along the side aisles (piecewise, through every nose): the floor's line on the rake. In the pit,
## its floor; past the back row, the walkway's.
static func nose_y(l: Auditorium.Layout, z: float) -> float:
	var pts := _noses(l)
	if z <= pts[0].x:
		return pts[0].y
	for i in range(1, pts.size()):
		if z <= pts[i].x:
			return lerpf(pts[i - 1].y, pts[i].y, (z - pts[i - 1].x) / maxf(pts[i].x - pts[i - 1].x, 0.0001))
	return pts[-1].y


static func _noses(l: Auditorium.Layout) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var zf0 := l.arc_z(l.row_radius(l.rows_front) - l.depth * 0.5, l.block_x)
	out.append(Vector2(zf0 - 0.6, l.lo.y))
	for row in range(l.rows_front, -l.rows_back - 1, -1):
		var zf := l.arc_z(l.row_radius(row) - l.depth * 0.5, l.block_x)
		var zb := l.arc_z(l.row_radius(row) + l.depth * 0.5, l.block_x)
		out.append(Vector2(zf, l.row_floor(row) - l.rise * 0.5))
		out.append(Vector2((zf + zb) * 0.5, l.row_floor(row)))
	return out


## The front exits on the side walls (the builder's): [z from, z to, top] with their frames and signs.
static func _front_door(c: Object, l: Auditorium.Layout) -> Array:
	if not bool(c.builder_params.get("doors", true)):
		return []
	var ds: Array = c.builder_params.get("door_size", [1.8, 2.35])
	var fz := (_stage_front(c, l) + l.arc_z(l.row_radius(l.rows_front) - l.depth * 0.5, l.block_x)) * 0.5
	var half := float(ds[0]) * 0.5 + 0.2
	return [fz - half, fz + half, l.lo.y + float(ds[1]) + 0.75]


## A column of vertical faces (a slat, a fin): its front and two sides as grids, rows at ys, each row's light (the
## alpha) from wash(y). base: the column's foot at its middle; basis: x along the wall, z out to the room.
static func _column(b: RoomMesh, base: Vector3, basis: Basis, w: float, depth: float, ys: Array[float],
		colour: Color, wash: Callable, baked := false) -> void:
	var hw := w * 0.5
	for side in 3:
		var p0: Vector3
		var p1: Vector3
		var n: Vector3
		match side:
			0:
				p0 = Vector3(-hw, 0.0, depth)
				p1 = Vector3(hw, 0.0, depth)
				n = Vector3.BACK
			1:
				p0 = Vector3(-hw, 0.0, 0.0)
				p1 = Vector3(-hw, 0.0, depth)
				n = Vector3.LEFT
			_:
				p0 = Vector3(hw, 0.0, depth)
				p1 = Vector3(hw, 0.0, 0.0)
				n = Vector3.RIGHT
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		var wn := (basis * n).normalized()
		for y in ys:
			var a := float(wash.call(y))
			rows.append(PackedVector3Array([base + basis * p0 + Vector3.UP * y, base + basis * p1 + Vector3.UP * y]))
			norms.append(PackedVector3Array([wn, wn]))
			cols.append(PackedColorArray([Color(colour.r, colour.g, colour.b, a), Color(colour.r, colour.g, colour.b,
					a)]))
		if baked:
			b.sheet(rows, norms, cols, (basis * (p1 - p0)).normalized(), Vector3.UP)
		else:
			b.grid(rows, norms, cols)


## Heights for a washed column from y0 to y1: close together low, where the wash changes, far apart high.
static func _rows_y(y0: float, y1: float) -> Array[float]:
	var out: Array[float] = []
	for h: float in [0.0, 0.3, 0.7, 1.2, 1.9, 2.8, 4.0, 5.6]:
		if y0 + h < y1 - 0.05:
			out.append(y0 + h)
	out.append(y1)
	return out


# --- The hall ---------------------------------------------------------------------------------------------------------

static func _hall(c: Object, _e: Dictionary) -> void:
	var h := hall(c)
	var l := _layout(c)
	var a := arc(c)
	# The walls are large and dark: a coarse lightmap keeps the atlas small and the bake quick.
	c.s.texel = 0.22
	var fabric: ShaderMaterial = c.tinted("fabric")
	var wood_baked: ShaderMaterial = c.tinted("wood")
	var wood: ShaderMaterial = c.soft("wood")
	var fins: ShaderMaterial = c.tinted("gilt")
	var ceiling: ShaderMaterial = c.tinted("plaster")
	for m: ShaderMaterial in [fabric, wood_baked, wood, fins, c.soft("wood")]:
		if not (m in h.warm):
			h.warm.append(m)
	if not (ceiling in h.cool):
		h.cool.append(ceiling)
	_front(c, l, a)
	_side_walls(c, l, a)
	_rear(c, l)
	_ceiling(c, h, l, a)
	_speakers(c, l)
	_hall_lights(c, l, a)


## Where the side walls begin: the proscenium's arc at the wall.
static func _wall_start(l: Auditorium.Layout, a: Dictionary) -> float:
	return ap(a, phi_at(a, l.hi.x, 0.08), 0.0, 0.08).z + 0.02


## The front: black velvet masking following the picture's curve, a champagne-bronze frame round it, walnut slats on
## black beyond it to the walls and the ceiling, washed from the stage's lip and from a line hidden in the frame's
## head; the stage's front a perforated grille.
static func _front(c: Object, l: Auditorium.Layout, a: Dictionary) -> void:
	var r := float(a["r"])
	var st := float(c.builder_params.get("stage_top", -2.1))
	var top := float(a["top"])
	var bottom := float(a["bottom"])
	var phi_p := float(a["half"]) / r
	var phi_m := (float(a["half"]) + MASK) / r
	var phi_f := phi_m + FRAME_W / r
	var phi_w := phi_at(a, l.hi.x, 0.08)
	var mask_top := top + MASK
	var frame_top := mask_top + FRAME_W
	# The masking: bands behind the picture's plane, overlapping its edges a little.
	c.s.surface(c.mat("drapes"))
	c.s.colour = Color.WHITE
	_arc_strip(c.s, a, -phi_m, phi_m, top - 0.04, mask_top, 0.08, 24)
	_arc_strip(c.s, a, -phi_m, phi_m, st, bottom + 0.04, 0.08, 24)
	for s: float in [-1.0, 1.0]:
		var p0 := s * (phi_p - 0.04 / r)
		_arc_strip(c.s, a, minf(p0, s * phi_m), maxf(p0, s * phi_m), bottom + 0.04, top - 0.04, 0.08, 1)
	# The frame: posts either side, a bar over the top, standing out of the masking.
	# (Dark: close to the picture it catches its light, and a bright edge round the film read as a television's bezel.)
	c.s.surface(c.tinted("gilt"))
	c.s.colour = _lin(BRONZE * 0.45)
	for s: float in [-1.0, 1.0]:
		var ph := s * (phi_m + phi_f) * 0.5
		var h := frame_top - st
		c.s.box(ap(a, ph, st + h * 0.5, 0.08 - FRAME_D * 0.5), Vector3(FRAME_W, h, FRAME_D), _basis_at(ph),
				[RoomMesh.FRONT, RoomMesh.DOWN])
	var n := 24
	for i in n:
		var p0 := lerpf(-phi_m, phi_m, float(i) / n)
		var p1 := lerpf(-phi_m, phi_m, float(i + 1) / n)
		var ph := (p0 + p1) * 0.5
		var len := (p1 - p0) * (r + 0.08) + 0.004
		c.s.box(ap(a, ph, mask_top + FRAME_W * 0.5, 0.08 - FRAME_D * 0.5), Vector3(len, FRAME_W, FRAME_D),
				_basis_at(ph), [RoomMesh.FRONT, RoomMesh.LEFT, RoomMesh.RIGHT])
	# The dark behind the slats, washed as the slats are (it shows between them), near their tone so the rhythm
	# reads as relief, not as hard stripes.
	var fabric: ShaderMaterial = c.tinted("fabric")
	c.s.surface(fabric)
	var wing := func(y: float) -> float: return _front_wash(y, st, frame_top, false)
	var head := func(y: float) -> float: return _front_wash(y, st, frame_top, true)
	var behind := _lin(WALNUT * 0.55)
	for s: float in [-1.0, 1.0]:
		_arc_sheet(c.s, a, s * phi_f, s * phi_w, _rows_y(st, l.hi.y), 0.08, behind, wing, 3)
	_arc_sheet(c.s, a, -phi_f, phi_f, _rows_y(frame_top, l.hi.y), 0.08, behind, head, 16)
	# The slats.
	c.u.surface(c.soft("wood"))
	var span := phi_w * (r + 0.08)
	var count := int(floor(span * 2.0 / SLAT_PITCH))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in count + 1:
		var s_arc := -span + (span * 2.0 - count * SLAT_PITCH) * 0.5 + i * SLAT_PITCH
		var ph := s_arc / (r + 0.08)
		if absf(ph) > phi_w - SLAT_W * 0.6 / r:
			continue
		var tone := _lin(WALNUT * rng.randf_range(0.88, 1.1))
		var over := absf(ph) < phi_f + (SLAT_W * 0.5 + 0.02) / r
		var y0 := frame_top if over else st
		var wash := head if over else wing
		_column(c.u, ap(a, ph, 0.0, 0.08), _basis_at(ph), SLAT_W, SLAT_D, _rows_y(y0, l.hi.y), tone, wash)
	# The stage's front: a perforated grille over the speakers, a dark toe under it.
	var sf := _stage_front(c, l)
	c.s.surface(c.mat("tin"))
	c.s.face([Vector3(l.lo.x, l.lo.y + 0.1, sf + 0.006), Vector3(l.hi.x, l.lo.y + 0.1, sf + 0.006),
			Vector3(l.hi.x, st - 0.14, sf + 0.006), Vector3(l.lo.x, st - 0.14, sf + 0.006)], Vector3.BACK)
	c.s.surface(fabric)
	c.s.colour = _lin(FELT)
	c.s.face([Vector3(l.lo.x, l.lo.y, sf + 0.004), Vector3(l.hi.x, l.lo.y, sf + 0.004), Vector3(l.hi.x, l.lo.y + 0.1,
			sf + 0.004), Vector3(l.lo.x, l.lo.y + 0.1, sf + 0.004)], Vector3.BACK)
	# The proscenium's wings stand on the stage; a solid for object physics.
	for s: float in [-1.0, 1.0]:
		var x0 := s * (float(a["half"]) + MASK + FRAME_W)
		c.shapes.append(PhysicsShapes.box(Vector3((x0 + s * l.hi.x) * 0.5, (st + l.hi.y) * 0.5, sf - 0.6),
				Vector3(absf(l.hi.x - absf(x0)), l.hi.y - st, 1.0)))


## The front's wash at height y: the wings from the stage's lip (a long soft rise), the head from the line in the
## frame's head (shorter); a little of the head's on the wings over the frame.
static func _front_wash(y: float, st: float, frame_top: float, over: bool) -> float:
	var head := exp(-maxf(y - frame_top, 0.0) / 1.1) * 0.4 if y >= frame_top - 0.01 else 0.0
	if over:
		return head
	return clampf(exp(-(y - st) / 2.0) * 0.6 + head * 0.4, 0.0, 1.0)


## A band of the arc between angles phi0 and phi1, y0 to y1, d behind the picture: one strip (a chart).
static func _arc_strip(b: RoomMesh, a: Dictionary, phi0: float, phi1: float, y0: float, y1: float, d: float,
		segments: int) -> void:
	var la := PackedVector3Array()
	var lb := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in segments + 1:
		var ph := lerpf(phi0, phi1, float(i) / segments)
		la.append(ap(a, ph, y0, d))
		lb.append(ap(a, ph, y1, d))
		ns.append(an(ph))
	b.strip(la, lb, ns)


## A sheet of the arc (one chart), rows at ys, each point's alpha the wash at its height.
static func _arc_sheet(b: RoomMesh, a: Dictionary, phi0: float, phi1: float, ys: Array[float], d: float, base: Color,
		wash: Callable, segments: int) -> void:
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for y in ys:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		var w := float(wash.call(y))
		for i in segments + 1:
			var ph := lerpf(phi0, phi1, float(i) / segments)
			row.append(ap(a, ph, y, d))
			nrow.append(an(ph))
			crow.append(Color(base.r, base.g, base.b, w))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	var mid := (phi0 + phi1) * 0.5
	b.sheet(rows, norms, cols, Vector3(cos(mid), 0.0, sin(mid)), Vector3.UP)


## The side walls: folded felt panels over a walnut dado, a bronze fin on each ridge, the light slot between dado and
## panels (its glow in PieceLamps, its light on the folds per vertex), the handrail on the stepped part, the cove
## ledge at the top.
static func _side_walls(c: Object, l: Auditorium.Layout, a: Dictionary) -> void:
	var z0 := _wall_start(l, a)
	var z1 := l.hi.z
	var bays := maxi(int(round((z1 - z0) / BAY)), 1)
	var bay := (z1 - z0) / bays
	var door := _front_door(c, l)
	var fabric: ShaderMaterial = c.tinted("fabric")
	var dado_m: ShaderMaterial = c.tinted("wood")
	var slot: ShaderMaterial = hall(c).line(c.kit)
	var bottom := func(z: float) -> float: return nose_y(l, z) + DADO
	for s: float in [-1.0, 1.0]:
		var xw := l.hi.x * s
		var ridge_x := xw - s * FOLD_DEPTH
		var fold_x := xw - s * 0.02
		for i in bays:
			var za := z0 + i * bay
			var zb := za + bay
			var zc := za + bay * FOLD_AT
			var at_door := not door.is_empty() and zb > float(door[0]) and za < float(door[1])
			var ya := float(door[2]) if at_door else float(bottom.call(za))
			var yc := float(door[2]) if at_door else float(bottom.call(zc))
			var yb := float(door[2]) if at_door else float(bottom.call(zb))
			var ra := Vector3(ridge_x, ya, za)
			var fc := Vector3(fold_x, yc, zc)
			var rb := Vector3(ridge_x, yb, zb)
			c.s.surface(fabric)
			_facet(c.s, ra, fc, s, l.hi.x, 1.0)
			_facet(c.s, fc, rb, s, l.hi.x, 0.5)
			# The folds' underside over the slot: lit from below.
			c.s.colour = _lin(FELT, 0.9)
			c.s.face([Vector3(xw, ya, za), ra, fc], Vector3.DOWN)
			c.s.face([fc, rb, Vector3(xw, yb, zb)], Vector3.DOWN)
			# The dado under the panels, down to the floor (the floor's steps cover its foot): the slot's light on its top.
			c.s.surface(dado_m)
			var dx := xw - s * 0.01
			var rows: Array = []
			var norms: Array = []
			var cols: Array = []
			var wn := Vector3(-s, 0.0, 0.0)
			var lo_y := l.lo.y
			for f: float in [0.0, 0.7, 0.9, 1.0]:
				var y_a := lerpf(lo_y, ya, f)
				var y_b := lerpf(lo_y, yb, f)
				rows.append(PackedVector3Array([Vector3(dx, y_a, za), Vector3(dx, y_b, zb)]))
				norms.append(PackedVector3Array([wn, wn]))
				var al := 0.0 if at_door else 0.18 * pow(f, 6.0)
				var cw := _lin(WALNUT, al)
				cols.append(PackedColorArray([cw, cw]))
			c.s.sheet(rows, norms, cols, Vector3(0, 0, 1), Vector3.UP)
			# The slot's glow (none over the door: the panels start over its sign).
			if not at_door:
				var sx := xw - s * 0.012
				c.lit.surface(slot)
				c.lit.face([Vector3(sx, ya, za), Vector3(sx, yb, zb), Vector3(sx, yb + 0.035, zb),
						Vector3(sx, ya + 0.035, za)], wn)
			# The fin on the ridge: a bronze edge from the slot to the ledge, washed with the folds.
			var fin_wash := func(y: float) -> float: return 0.55 * exp(-(y - ya) / 2.6)
			c.s.surface(c.tinted("gilt"))
			var fb := Basis(Vector3(0, 0, -s), Vector3.UP, Vector3(-s, 0, 0))
			_column(c.s, Vector3(ridge_x - s * 0.001, 0.0, za), fb, 0.03, 0.035, _rows_y(ya, PANEL_TOP),
					_lin(BRONZE), fin_wash, true)
		# The handrail on the stepped part: brushed steel on brackets, a warm line under it on the steps.
		_handrail(c, l, s)
		# The cove ledge round the top: its fascia and underside; the cool line on it is hidden.
		c.s.surface(fabric)
		c.s.colour = _lin(FELT)
		var lx := xw - s * LEDGE_D
		c.s.face([Vector3(lx, PANEL_TOP, z0), Vector3(lx, PANEL_TOP, z1), Vector3(lx, PANEL_TOP + LEDGE_H, z1),
				Vector3(lx, PANEL_TOP + LEDGE_H, z0)], Vector3(-s, 0, 0))
		c.s.face([Vector3(lx, PANEL_TOP, z0), Vector3(xw, PANEL_TOP, z0), Vector3(xw, PANEL_TOP, z1),
				Vector3(lx, PANEL_TOP, z1)], Vector3.DOWN)
		c.s.face([Vector3(lx, PANEL_TOP + LEDGE_H, z0), Vector3(xw, PANEL_TOP + LEDGE_H, z0),
				Vector3(xw, PANEL_TOP + LEDGE_H, z1), Vector3(lx, PANEL_TOP + LEDGE_H, z1)], Vector3.UP)
		# Over the ledge to the ceiling: the wall, in the cove's cool light.
		c.s.surface(c.tinted("plaster"))
		var rows2: Array = []
		var norms2: Array = []
		var cols2: Array = []
		for y: float in [PANEL_TOP + LEDGE_H, l.hi.y]:
			rows2.append(PackedVector3Array([Vector3(xw, y, z0), Vector3(xw, y, z1)]))
			norms2.append(PackedVector3Array([Vector3(-s, 0, 0), Vector3(-s, 0, 0)]))
			var cw := _lin(FELT, 0.7 if y < l.hi.y - 0.1 else 0.5)
			cols2.append(PackedColorArray([cw, cw]))
		c.s.sheet(rows2, norms2, cols2, Vector3(0, 0, 1), Vector3.UP)
		c.shapes.append(PhysicsShapes.box(Vector3(xw - s * 0.11, (l.lo.y + l.hi.y) * 0.5, (z0 + z1) * 0.5),
				Vector3(0.22, l.hi.y - l.lo.y, z1 - z0)))


## One folded panel's face from p (its bottom at p.y) to q (its bottom at q.y), up to the top: a sheet with rows
## close together low; each point's alpha the slot's light (brightest low, in the fold by the wall, k for a return).
static func _facet(b: RoomMesh, p: Vector3, q: Vector3, s: float, wall: float, k: float) -> void:
	var along := Vector3(q.x - p.x, 0.0, q.z - p.z)
	var n := Vector3.UP.cross(along).normalized()
	if n.x * s > 0.0:
		n = -n
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	var base := _lin(FELT)
	var steps: Array[float] = [0.0, 0.15, 0.35, 0.6, 0.85, 1.0]
	for f: float in steps:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for e: float in [0.0, 1.0]:
			var y0 := lerpf(p.y, q.y, e)
			var y := lerpf(y0, PANEL_TOP, f)
			var pt := Vector3(lerpf(p.x, q.x, e), y, lerpf(p.z, q.z, e))
			# In the fold (by the wall) the light gathers; at the ridge it is thinner.
			var fold := 1.0 - clampf((wall - absf(pt.x) - 0.02) / (FOLD_DEPTH - 0.02), 0.0, 1.0)
			var h := y - y0
			var w := k * (0.35 + 0.65 * fold) * (exp(-h / 2.2) + 0.05 * exp(-(PANEL_TOP - y) / 0.8))
			row.append(pt)
			nrow.append(n)
			crow.append(Color(base.r, base.g, base.b, clampf(w, 0.0, 1.0)))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	b.sheet(rows, norms, cols, along.normalized(), Vector3.UP)


## The handrail along the stepped aisle at the wall: a brushed-steel bar on brackets from the dado, a warm line on its
## underside lighting the steps.
static func _handrail(c: Object, l: Auditorium.Layout, s: float) -> void:
	var pts := _noses(l)
	var x := s * (l.hi.x - 0.13)
	var line: ShaderMaterial = hall(c).line(c.kit)
	var steel: Material = c.mat("chrome")
	# Through the noses' line, smoothed: one bar a few rows long.
	var from := pts[1].x - 0.2
	var to := l.hi.z - 0.35
	var segs := 8
	for i in segs:
		var za := lerpf(from, to, float(i) / segs)
		var zb := lerpf(from, to, float(i + 1) / segs)
		var a := Vector3(x, nose_y(l, za) + RAIL_Y, za)
		var b := Vector3(x, nose_y(l, zb) + RAIL_Y, zb)
		c.s.surface(steel)
		c.s.colour = Color.WHITE
		Shapes.beam(c.s, a, b + (b - a).normalized() * 0.01, Vector2(0.05, 0.045))
		var dir := (b - a).normalized()
		var down := dir.cross(Vector3(s, 0, 0)).normalized()
		if down.y > 0.0:
			down = -down
		c.lit.surface(line)
		var off := down * 0.0235
		var hw := Vector3(0.012, 0, 0)
		c.lit.face([a + off - hw, b + off - hw, b + off + hw, a + off + hw], down)
		# A bracket back to the dado at the segment's start.
		c.s.surface(steel)
		c.s.box(Vector3((x + s * (l.hi.x - 0.01)) * 0.5, a.y - 0.06, za + 0.1), Vector3(0.12, 0.025, 0.025))


## The rear wall: walnut slats on black felt, a walnut band round the projection port and the booth's windows, the
## doors left clear; the cove ledge across its top.
static func _rear(c: Object, l: Auditorium.Layout) -> void:
	var walk := l.row_floor(-l.rows_back)
	var z := l.hi.z
	var fabric: ShaderMaterial = c.tinted("fabric")
	var lens: Array = c.builder_params.get("lens", [0.0, 3.45, 6.15])
	var ly := float(lens[1])
	var band := Rect2(-2.7, ly - 0.75, 5.4, 1.5)
	var doors: Array[Rect2] = []
	if bool(c.builder_params.get("doors", true)):
		for s: float in [-1.0, 1.0]:
			doors.append(Rect2(s * (l.hi.x - 1.6) - 1.05, walk, 2.1, 2.95))
	# The felt behind, the band and the doors left out.
	c.s.surface(fabric)
	c.s.colour = _lin(FELT, 0.12)
	var holes: Array = [Rect2(l.hi.x - band.end.x, band.position.y - walk, band.size.x, band.size.y)]
	for d: Rect2 in doors:
		holes.append(Rect2(l.hi.x - d.end.x, 0.0, d.size.x, d.size.y))
	Shapes.wall(c.s, Vector3(l.hi.x, walk, z - 0.004), Vector3.LEFT, Vector3.FORWARD, l.hi.x * 2.0, PANEL_TOP - walk,
			holes)
	# The band round the port: walnut, the windows cut out of it (the builder's frames and glow are in them).
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT * 0.9)
	var wins: Array = [Rect2(band.end.x - 0.65, ly - 0.375 - band.position.y, 1.3, 0.75)]
	for s: float in [-1.0, 1.0]:
		wins.append(Rect2(band.end.x - (s * 1.5 + 0.275), ly - 0.2 - band.position.y, 0.55, 0.4))
	Shapes.wall(c.s, Vector3(band.end.x, band.position.y, z - 0.006), Vector3.LEFT, Vector3.FORWARD, band.size.x,
			band.size.y, wins)
	# The slats: thin, close to the wall (the back row's seats stand near it), washed a little from the walkway.
	c.u.surface(c.soft("wood"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var wash := func(y: float) -> float: return 0.5 * exp(-(y - walk) / 1.6)
	var x := -l.hi.x + 0.3
	while x < l.hi.x - 0.25:
		var tone := _lin(WALNUT * rng.randf_range(0.88, 1.1))
		var spans: Array = [[walk, PANEL_TOP]]
		if absf(x) < band.end.x + 0.05:
			spans = [[walk, band.position.y - 0.05], [band.end.y + 0.05, PANEL_TOP]]
		for d: Rect2 in doors:
			if x > d.position.x - 0.05 and x < d.end.x + 0.05:
				spans = [[d.end.y + 0.05, PANEL_TOP]]
		for sp: Array in spans:
			var y0 := float(sp[0])
			var y1 := float(sp[1])
			if y1 - y0 < 0.1:
				continue
			_column(c.u, Vector3(x, 0.0, z - 0.005), Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), 0.04, 0.02,
					_rows_y(y0, y1), tone, wash)
		x += 0.2
	# The ledge.
	c.s.surface(fabric)
	c.s.colour = _lin(FELT)
	var lz := z - LEDGE_D
	c.s.face([Vector3(l.lo.x, PANEL_TOP, lz), Vector3(l.hi.x, PANEL_TOP, lz), Vector3(l.hi.x, PANEL_TOP + LEDGE_H, lz),
			Vector3(l.lo.x, PANEL_TOP + LEDGE_H, lz)], Vector3.FORWARD)
	c.s.face([Vector3(l.lo.x, PANEL_TOP, lz), Vector3(l.hi.x, PANEL_TOP, lz), Vector3(l.hi.x, PANEL_TOP, z),
			Vector3(l.lo.x, PANEL_TOP, z)], Vector3.DOWN)
	c.s.surface(c.tinted("plaster"))
	c.s.colour = _lin(FELT, 0.95)
	c.s.face([Vector3(l.lo.x, PANEL_TOP + LEDGE_H, z), Vector3(l.hi.x, PANEL_TOP + LEDGE_H, z), Vector3(l.hi.x, l.hi.y, z),
			Vector3(l.lo.x, l.hi.y, z)], Vector3.FORWARD)


## The ceiling: the slab in the coves' cool light along the walls, the baffles running to the screen, the starlight
## between them.
static func _ceiling(c: Object, h: Hall, l: Auditorium.Layout, a: Dictionary) -> void:
	var top := l.hi.y
	var front := ap(a, 0.0, top, 0.08).z
	var z1 := l.hi.z
	# The slab: columns close together by the walls (where the cove's light falls off), rows along the hall.
	c.s.surface(c.tinted("plaster"))
	var xs: Array[float] = []
	for d: float in [0.0, 0.4, 0.9, 1.6, 2.6, 4.0, 6.5, 9.5]:
		xs.append(l.lo.x + d)
	for d: float in [9.5, 6.5, 4.0, 2.6, 1.6, 0.9, 0.4, 0.0]:
		if l.hi.x - d > xs[-1] + 0.01:
			xs.append(l.hi.x - d)
	var zs: Array[float] = []
	var n := 8
	for j in n + 1:
		zs.append(lerpf(front, z1 - 2.2, float(j) / n))
	for d: float in [1.4, 0.8, 0.4, 0.0]:
		zs.append(z1 - d)
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	var base := _lin(FELT)
	for z in zs:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for x in xs:
			var to_wall := minf(l.hi.x - absf(x), (z1 - z) + 0.2)
			row.append(Vector3(x, top, z))
			nrow.append(Vector3.DOWN)
			crow.append(Color(base.r, base.g, base.b, clampf(0.9 * exp(-maxf(to_wall - LEDGE_D, 0.0) / 1.2), 0.0, 1.0)))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	c.s.sheet(rows, norms, cols, Vector3.RIGHT, Vector3(0, 0, 1))
	# The baffles: charcoal felt fins along the hall, from the proscenium's head to the rear ledge, a little of the
	# coves' cool light on them (so the field reads as fins round the stars, not as a black sky).
	c.s.surface(c.tinted("plaster"))
	c.s.colour = _lin(FELT, 0.2)
	var count := int(floor(BAFFLE_X * 2.0 / BAFFLE_PITCH))
	var x0 := -count * BAFFLE_PITCH * 0.5
	var baffles: Array[float] = []
	for i in count + 1:
		var x := x0 + i * BAFFLE_PITCH
		baffles.append(x)
		var zf := ap(a, phi_at(a, x, 0.08), top, 0.08).z + 0.02
		var zb := z1 - LEDGE_D - 0.02
		c.s.box(Vector3(x, top - BAFFLE_D * 0.5, (zf + zb) * 0.5), Vector3(BAFFLE_W, BAFFLE_D, zb - zf), Basis(),
				[RoomMesh.UP, RoomMesh.FRONT])
	# The starlight: pinholes between the baffles, a soft point each (bright in the middle, nothing at its rim),
	# mostly cool white, a few warmer; never twinkling.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var placed := 0
	var tries := 0
	while placed < STARS and tries < STARS * 6:
		tries += 1
		var x := rng.randf_range(x0 + 0.05, -x0 - 0.05)
		var gap := fposmod(x - x0, BAFFLE_PITCH)
		if gap < 0.08 or gap > BAFFLE_PITCH - 0.08:
			continue
		var zf := ap(a, phi_at(a, x, 0.08), top, 0.08).z + 0.4
		var z := rng.randf_range(zf, z1 - LEDGE_D - 0.3)
		# Never under 1.8 cm: a smaller point is under two pixels in the headset from the seats and would crawl as
		# the head moves.
		var r := lerpf(0.018, 0.035, pow(rng.randf(), 3.0))
		var bright := lerpf(0.35, 1.0, pow(rng.randf(), 2.0)) * (r / 0.035 * 0.5 + 0.5)
		var col := Color(0.82, 0.9, 1.0).lerp(Color(1.0, 0.88, 0.7), 1.0 if rng.randf() < 0.15 else 0.0) * bright
		var centre := Vector3(x, top - 0.003, z)
		for k in 4:
			var a0 := TAU * k / 4.0 + 0.4
			var a1 := TAU * (k + 1) / 4.0 + 0.4
			var p1 := centre + Vector3(cos(a0), 0.0, sin(a0)) * r
			var p2 := centre + Vector3(cos(a1), 0.0, sin(a1)) * r
			# Facing down: clockwise as seen from below.
			var tri := [centre, p1, p2]
			if (p2 - centre).cross(p1 - centre).dot(Vector3.DOWN) < 0.0:
				tri = [centre, p2, p1]
			for p: Vector3 in tri:
				v.append(p)
				nn.append(Vector3.DOWN)
				cc.append(col if p == centre else Color(0, 0, 0))
		placed += 1
	h.stars = {"v": v, "n": nn, "c": cc}


## Surround speakers: cabinets on the side walls in front of the folds and two on the rear wall, each turned down
## towards the middle of the seats, a perforated front, a bracket to the wall.
static func _speakers(c: Object, l: Auditorium.Layout) -> void:
	var at: Array = []
	for s: float in [-1.0, 1.0]:
		for z: float in [-11.0, -5.5, 0.0, 5.0]:
			at.append([Vector3(s * (l.hi.x - FOLD_DEPTH - 0.19), nose_y(l, z) + DADO + 3.0, z), Vector3(s * l.hi.x, 0, 0)])
	var walk := l.row_floor(-l.rows_back)
	for x: float in [-6.5, 6.5]:
		at.append([Vector3(x, walk + 4.3, l.hi.z - 0.22), Vector3(0, 0, l.hi.z)])
	for e: Array in at:
		var p: Vector3 = e[0]
		var wall: Vector3 = e[1]
		# Square to its wall, tipped down 15 degrees towards the seats.
		var out := Vector3(-signf(wall.x), 0.0, 0.0) if wall.x != 0.0 else Vector3(0, 0, -1)
		var aim := (out * cos(deg_to_rad(15.0)) + Vector3.DOWN * sin(deg_to_rad(15.0))).normalized()
		var basis := Basis.looking_at(aim, Vector3.UP)
		c.s.surface(c.mat("iron"))
		c.s.colour = Color.WHITE
		c.s.box(p, Vector3(0.36, 0.52, 0.3), basis, [RoomMesh.BACK])
		c.s.surface(c.mat("tin"))
		var f := p + aim * 0.152
		c.s.face([f + basis.x * 0.165 + basis.y * 0.245, f - basis.x * 0.165 + basis.y * 0.245,
				f - basis.x * 0.165 - basis.y * 0.245, f + basis.x * 0.165 - basis.y * 0.245], aim)
		# The bracket.
		var to := Vector3(wall.x if wall.x != 0.0 else p.x, p.y, wall.z if wall.z != 0.0 else p.z)
		c.s.surface(c.mat("iron"))
		Shapes.beam(c.s, p - aim * 0.1, to, Vector2(0.06, 0.06))


## The hall's light in the bake, and stand-in lamps until a bake: warm by the light slots and the rails, the
## proscenium's wings from the stage's lip, the coves' cool light along the ceiling's edges.
static func _hall_lights(c: Object, l: Auditorium.Layout, a: Dictionary) -> void:
	var warm := Color(1.0, 0.7, 0.42)
	var st := float(c.builder_params.get("stage_top", -2.1))
	var sf := _stage_front(c, l)
	for s: float in [-1.0, 1.0]:
		for z: float in [-8.5, -1.5, 5.0]:
			c.lamps.append([Vector3(s * (l.hi.x - 0.7), nose_y(l, z) + 1.5, z), warm, 0.55])
	for s: float in [-1.0, 1.0]:
		c.lamps.append([Vector3(s * (l.hi.x - 0.7), nose_y(l, -13.0) + 1.5, -13.0), warm, 0.45])
	# The slots' light along the walls (the bake: pools on the steps and the dado, the folds' glow bouncing).
	for s: float in [-1.0, 1.0]:
		for z: float in [-13.5, -8.0, -2.5, 3.0, 7.0]:
			c.glow_lights.append([Vector3(s * (l.hi.x - 0.3), nose_y(l, z) + DADO + 0.2, z), warm, 0.5, 3.2])
		c.glow_lights.append([Vector3(s * (l.hi.x - 0.25), PANEL_TOP + LEDGE_H + 0.15, -2.0), COOL, 0.6, 7.0])
	c.glow_lights.append([Vector3(0.0, PANEL_TOP + LEDGE_H + 0.15, l.hi.z - 0.25), COOL, 0.5, 7.0])
	# The wings and the head of the proscenium from the stage's lip.
	for s: float in [-1.0, 1.0]:
		c.spots.append([Vector3(s * (float(a["half"]) + 1.3), st + 0.05, sf - 0.2),
				Vector3(s * (float(a["half"]) + 1.6), 6.0, sf - 0.9), warm, 0.5, 10.0, 28.0])


# --- The rows -----------------------------------------------------------------------------------------------------------

## The rows' furniture: fixed armrests between the recliners (and at the rows' ends) with their cupholders and seat
## numbers, the row letters on the end arms, the aisle steps' nosings and the front row's glass balustrade.
static func _rows(c: Object, _e: Dictionary) -> void:
	var h := hall(c)
	var l := _layout(c)
	var leather: Material = c.soft("plastic", false)
	var steel: Material = c.soft("chrome", false)
	var dark: Material = leather
	var half := (l.per_row - 1) / 2
	for row in range(-l.rows_back, l.rows_front + 1):
		var r := l.row_radius(row)
		var y := l.row_floor(row)
		var letter := 25 + (l.rows_front - row)
		for k in range(-half, l.per_row - half + 1):
			# The arm on seat k's left (the last one on the row's right end).
			var ang := (k - 0.5) * l.pitch / r
			var xf := Transform3D(Basis(Vector3.UP, ang), Vector3(r * sin(ang), y, -l.radius + r * cos(ang)))
			c.u.surface(leather)
			c.u.colour = Color.WHITE
			c.u.rounded_box(Vector3(0.0, ARM_H * 0.5, ARM_Z), Vector3(ARM_W, ARM_H, ARM_D), 0.03, xf, 1, Vector3i.ZERO,
					0.0, [RoomMesh.DOWN])
			# The cupholder: a brushed ring at the arm's front, dark inside.
			var cup := xf * Vector3(0.0, ARM_H, CUP_Z)
			c.u.surface(steel)
			Shapes.lathe(c.u, [Vector2(CUP_R - 0.009, 0.0), Vector2(CUP_R - 0.009, 0.007), Vector2(CUP_R + 0.002, 0.006)],
					cup, 9, xf.basis)
			c.u.surface(dark)
			var disc: Array = []
			for i in 9:
				var t := TAU * i / 9.0
				disc.append(cup + xf.basis * Vector3(sin(t), 0.0045, cos(t)) * Vector3(CUP_R - 0.009, 1.0, CUP_R - 0.009))
			c.u.face(disc, Vector3.UP)
			# The seat's number on a plate behind the cupholder (the seat on the arm's right; none past the row).
			if k < l.per_row - half:
				var pc := xf * Vector3(0.0, ARM_H + 0.0015, -0.16)
				h.numbers.append([pc, xf.basis.x * 0.028, -xf.basis.z * 0.014, Vector3.UP, k + half])
			# The row letter on the end arms' outer faces, toward the aisle.
			if k == -half or k == l.per_row - half:
				var side := -1.0 if k == -half else 1.0
				var nrm := (xf.basis.x * side).normalized()
				var lc := xf * Vector3(side * (ARM_W * 0.5 + 0.002), 0.47, -0.18)
				h.letters.append([lc, Vector3.UP.cross(nrm) * 0.04, Vector3.UP * 0.04, nrm, letter])
	_nosings(c, l)
	_balustrade(c, l)


## Brushed-steel nosings on the aisle steps' edges (the builder's blue line glows in the riser under each).
static func _nosings(c: Object, l: Auditorium.Layout) -> void:
	c.s.surface(c.mat("chrome"))
	c.s.colour = Color.WHITE
	for row in range(-l.rows_back, l.rows_front + 1):
		var zf := l.arc_z(l.row_radius(row) - l.depth * 0.5, l.block_x)
		var zm := (zf + l.arc_z(l.row_radius(row) + l.depth * 0.5, l.block_x)) * 0.5
		for nose: Vector2 in [Vector2(zm, l.row_floor(row)), Vector2(zf, l.row_floor(row) - l.rise * 0.5)]:
			for s: float in [-1.0, 1.0]:
				var x0 := s * (l.block_x + 0.05)
				var x1 := s * (l.hi.x - 0.02)
				c.s.box(Vector3((x0 + x1) * 0.5, nose.y + 0.005, nose.x + 0.025), Vector3(absf(x1 - x0), 0.01, 0.05),
						Basis(), [RoomMesh.DOWN, RoomMesh.LEFT, RoomMesh.RIGHT, RoomMesh.BACK])


## The front row's balustrade: frameless glass on its tier's edge, a brushed-steel shoe and cap rail, a warm line
## under the cap (it goes out with the house lamps).
static func _balustrade(c: Object, l: Auditorium.Layout) -> void:
	var row := l.rows_front
	var r := l.row_radius(row) - l.depth * 0.5 + 0.05
	var y := l.row_floor(row)
	var reach := asin(clampf((l.block_x - 0.1) / r, -1.0, 1.0))
	var panels := 12
	var h := 0.88
	var line: ShaderMaterial = hall(c).line(c.kit)
	var glass: RoomMesh = hall(c).glass
	glass.surface(c.mat("chrome"))
	for i in panels:
		var a0 := lerpf(-reach, reach, float(i) / panels)
		var a1 := lerpf(-reach, reach, float(i + 1) / panels)
		var p0 := Vector3(r * sin(a0), y, -l.radius + r * cos(a0))
		var p1 := Vector3(r * sin(a1), y, -l.radius + r * cos(a1))
		var t := (p1 - p0).normalized()
		var n := Vector3.UP.cross(t).normalized()
		if n.z < 0.0:
			n = -n
		var g := 0.006
		glass.face([p0 + t * g + Vector3.UP * 0.04, p1 - t * g + Vector3.UP * 0.04, p1 - t * g + Vector3.UP * (h - 0.03),
				p0 + t * g + Vector3.UP * (h - 0.03)], n)
		var mid := (p0 + p1) * 0.5
		var len := p0.distance_to(p1) + 0.004
		var basis := Basis(t, Vector3.UP, n)
		c.s.surface(c.mat("chrome"))
		c.s.colour = Color.WHITE
		c.s.box(mid + Vector3.UP * 0.02, Vector3(len, 0.04, 0.05), basis, [RoomMesh.DOWN])
		c.s.box(mid + Vector3.UP * (h - 0.015), Vector3(len, 0.03, 0.055), basis, [])
		c.lit.surface(line)
		# Under the cap, towards the seats: 2.5 cm (a thinner line breaks into dashes from the rows behind).
		var ly := h - 0.056
		c.lit.face([p0 + Vector3.UP * ly + n * 0.0285, p1 + Vector3.UP * ly + n * 0.0285,
				p1 + Vector3.UP * (ly + 0.025) + n * 0.0285, p0 + Vector3.UP * (ly + 0.025) + n * 0.0285], n)
		c.shapes.append(PhysicsShapes.box(mid + Vector3.UP * h * 0.5, Vector3(len, h, 0.06), basis))
