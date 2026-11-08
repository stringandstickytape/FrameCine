extends RefCounted

## The Palace of Culture's hall (docs/environments.md, "Room: Palace of Culture 1974"; since 2026-11-08: "continue
## working on the environments one-by-one like you did with the bathysphere, really improving their quality,
## imagination, delight, detail, lighting and so on. Better to do a smaller number of incredible superb ones than a
## large number not so", the user, 2026-11-08). The cinema hall of a 1970s civic palace of culture, invented and
## unnamed, dressed over an auditorium builder's floor, seats, stage and doors:
##   - board-marked concrete everywhere (procedural.gd board_concrete: the timber's grain, tie holes, panel seams)
##   - two great wall mosaics of our own (kit/mosaics.gd: the cosmos on the left, dawn over the fields on the right) in
##     glass, gold and stone tesserae (shaders/room_material_house_mosaic.gdshader), framed in bronze, washed from a
##     lamp line under a deep concrete cornice, glinting as the head moves
##   - a coffered concrete ceiling, and in its coffers a field of opal globes on rods, hung lower towards the middle of
##     the hall; each lights its coffer (PieceCove: the light per vertex, live, down with the house lamps)
##   - the back of the roof open to the winter night between deep edge beams, the coffers' grid going on over it as
##     bare beams with snow lying on them, on the cornices and on the walls' tops
##   - a bold concrete proscenium: stepped reveals edged in bronze, ribbed side panels, an ochre valance inside
##   - the rear wall in warm oak acoustic slats round the projection booth's ports, a clock over them
## Everything is ours, drawn from boxes, strips and grids; no figure, no emblem.
##
## Pieces (pieces.gd dispatches here): culture_hall (no slot), globe_field (no slot). Both read the auditorium's
## layout (its parameters) and the room's screen (the document's).
##
## Cost: the concrete, bronze, slats and snow go into the kit's baked mesh (PieceStatic) by material; the mosaics are
## one mesh of their own (Mosaic: one draw, baked, two quads); the coffers PieceCove; the globes the kit's lamp mesh
## (PieceLamps: one surface); the rods and roses the unbaked mesh (PieceSoft).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const Mosaics := preload("res://scripts/env/systems/kit/mosaics.gd")
const MOSAIC_SHADER := preload("res://shaders/room_material_house_mosaic.gdshader")

## The mosaics: where they run along the side walls (z, from the screen's end to the back), their foot and top, and a
## tessera's size (4.5 cm: about four pixels across from the seats, where the grout still reads).
const MURAL_FROM := -13.6
const MURAL_TO := 0.8
const MURAL_FOOT := 1.0
const MURAL_TOP := 8.2
const TESSERA := 0.045
## The cornice over the mosaics: its underside, its height, how far it stands out from the wall.
const CORNICE_Y := 8.4
const CORNICE_H := 0.34
const CORNICE_D := 0.6
## The coffers: across the hall in ten, from the proscenium to the opening in seven; the beams' width and depth.
const COFFERS_X := 10
const COFFERS_Z := 7
const BEAM_W := 0.3
const BEAM_D := 0.7
## The opening in the roof (z) between its edge beams, and the edge beams' depth.
const OPEN_FROM := 1.2
const OPEN_TO := 5.2
const EDGE_W := 0.45
const EDGE_D := 1.25
## The proscenium: its face this far in front of the screen; its opening this much wider than the picture each side
## and higher over its top; the first reveal's step and depth, the second's depth.
const FRAME_OUT := 0.8
const OPEN_SIDE := 1.1
const OPEN_TOP := 1.3
const STEP := 0.32
const STEP_DEPTH := 0.36
const REVEAL_DEPTH := 1.0
## The globes: radius, and the light each gives its coffer (per vertex: it falls off as exp(-d / GLOBE_REACH), so a
## coffer is lit by its own globe, not by the field: pools, and dark concrete between them).
const GLOBE_R := 0.2
const GLOBE_REACH := 0.55
const GLOBE_LIGHT := 3.0
## The slats: from the rear walkway to this height; their pitch, width and depth.
const SLAT_TOP := 5.0
const SLAT_PITCH := 0.075
const SLAT_W := 0.045
const SLAT_D := 0.04

const CONCRETE := Color(0.62, 0.6, 0.56)
const CONCRETE_DARK := Color(0.52, 0.5, 0.47)
const BRONZE := Color(0.46, 0.33, 0.2)
const OAK := Color(0.6, 0.4, 0.22)
const SNOW := Color(0.9, 0.92, 0.96)
const FELT := Color(0.05, 0.045, 0.045)
const GLOBE := Color(1.0, 0.86, 0.66)
const GLOBE_ENERGY := 1.5


## The hall's own meshes and materials (kept on the kit's ctx.halls; kit.gd calls finish() and tick()).
class Hall:
	var kit: Node
	var mosaic := RoomMesh.new()
	var mosaic_m: ShaderMaterial
	var globe_m: ShaderMaterial
	var wash := Color(1.0, 0.8, 0.56)

	func finish(k: Node) -> void:
		if mosaic.triangle_count() > 0:
			var mi: MeshInstance3D = k._add_static("Mosaic", mosaic)
			_mural_uv(mi)
		var clock: Variant = k.get("_clock_m")
		if clock is ShaderMaterial:
			(clock as ShaderMaterial).set_shader_parameter("style", 1)
			(clock as ShaderMaterial).set_shader_parameter("colour", Color(0.95, 0.9, 0.8))
			(clock as ShaderMaterial).set_shader_parameter("mark_colour", Color(0.05, 0.05, 0.06))

	func tick(_delta: float) -> void:
		pass

	## The mosaic's UVs over the atlas (kit/mosaics.gd): the left wall's cosmos in its upper half, read from the back
	## of the hall towards the screen; the right wall's earth in its lower half, read from the screen to the back.
	static func _mural_uv(mi: MeshInstance3D) -> void:
		var mesh := mi.mesh as ArrayMesh
		var arrays := mesh.surface_get_arrays(0)
		var m := mesh.surface_get_material(0)
		var hint := mesh.lightmap_size_hint
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs := PackedVector2Array()
		uvs.resize(verts.size())
		var length := MURAL_TO - MURAL_FROM
		var height := MURAL_TOP - MURAL_FOOT
		for i in verts.size():
			var p := verts[i]
			var v := 0.5 * clampf((MURAL_TOP - p.y) / height, 0.0, 1.0)
			if p.x < 0.0:
				uvs[i] = Vector2(clampf((MURAL_TO - p.z) / length, 0.0, 1.0), v)
			else:
				uvs[i] = Vector2(clampf((p.z - MURAL_FROM) / length, 0.0, 1.0), 0.5 + v)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.clear_surfaces()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, m)
		mesh.lightmap_size_hint = hint


static func build(piece: String, c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	match piece:
		"culture_hall":
			_hall(c, e)
		"globe_field":
			_globe_field(c, e)
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove]:
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

static func _lin(colour: Color, alpha := 1.0) -> Color:
	var l := colour.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _layout(c: Object) -> Auditorium.Layout:
	return Auditorium.layout(c.builder_params)


## The room's screen from its document: {centre, size}.
static func _screen(c: Object) -> Dictionary:
	var d: Variant = c.room.get("doc")
	var s: Dictionary = (d as Dictionary).get("screen", {}) if d is Dictionary else {}
	var ce: Array = s.get("center", [0.0, 1.5, -15.3])
	var sz: Array = s.get("size", [13.0, 5.4])
	return {"centre": Vector3(float(ce[0]), float(ce[1]), float(ce[2])), "size": Vector2(float(sz[0]), float(sz[1]))}


static func _solid(c: Object, centre: Vector3, size: Vector3) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, Basis()))


## The proscenium's face (z) for this room.
static func frame_z(c: Object) -> float:
	return float(_screen(c)["centre"].z) + FRAME_OUT


## The coffers' grid lines across the hall (x) and along it (z, from the proscenium's face to the opening).
static func _grid_x(l: Auditorium.Layout) -> Array[float]:
	var out: Array[float] = []
	for i in COFFERS_X + 1:
		out.append(lerpf(l.lo.x, l.hi.x, float(i) / COFFERS_X))
	return out


static func _grid_z(fz: float) -> Array[float]:
	var out: Array[float] = []
	for j in COFFERS_Z + 1:
		out.append(lerpf(fz, OPEN_FROM, float(j) / COFFERS_Z))
	return out


## Where the globes hang: one in each coffer but the first row's (over the stage), lower towards the middle of the
## field, so the field reads as a hanging cloud from the seats; never under 6.6 m (the picture's top is 4.2).
static func globes(l: Auditorium.Layout, fz: float) -> Array[Vector3]:
	var xs := _grid_x(l)
	var zs := _grid_z(fz)
	var mid_z := (zs[1] + zs[-1]) * 0.5
	var out: Array[Vector3] = []
	for j in range(1, COFFERS_Z):
		for i in COFFERS_X:
			var x := (xs[i] + xs[i + 1]) * 0.5
			var z := (zs[j] + zs[j + 1]) * 0.5
			var bell := exp(-pow(x / 7.5, 2.0) - pow((z - mid_z) / 6.0, 2.0))
			var y := l.hi.y - BEAM_D - 0.25 - 1.5 * bell + 0.12 * sin(i * 2.1 + j * 1.3)
			out.append(Vector3(x, maxf(y, 6.6), z))
	return out


## The globes' light at a point of the ceiling facing n (0..1).
static func _globe_w(p: Vector3, n: Vector3, pts: Array[Vector3]) -> float:
	var w := 0.0
	for g in pts:
		var d := g - p
		var dl := d.length()
		if dl > 3.5:
			continue
		var k := maxf(n.dot(d / maxf(dl, 0.001)), 0.0)
		w += GLOBE_LIGHT * pow(k, 0.6) * exp(-dl / GLOBE_REACH)
	return clampf(w, 0.0, 1.0)


## A patch of the cove mesh: a grid between corners a (u 0, v 0), b (u 1), d (v 1), nu x nv cells, each point's light
## from the globes.
static func _patch(b: RoomMesh, a: Vector3, u: Vector3, v: Vector3, nu: int, nv: int, n: Vector3, base: Color,
		pts: Array[Vector3]) -> void:
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for j in nv + 1:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for i in nu + 1:
			var p := a + u * (float(i) / nu) + v * (float(j) / nv)
			row.append(p)
			nrow.append(n)
			crow.append(Color(base.r, base.g, base.b, _globe_w(p, n, pts)))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	b.grid(rows, norms, cols)


# --- The hall ---------------------------------------------------------------------------------------------------------

static func _hall(c: Object, _e: Dictionary) -> void:
	var h := hall(c)
	var l := _layout(c)
	var fz := frame_z(c)
	# The walls are large: a coarser lightmap keeps the atlas small and the bake quick.
	c.s.texel = 0.16
	var pts := globes(l, fz)
	_walls(c, l, fz)
	_murals(c, h, l)
	_cornices(c, l, fz)
	_coffers(c, l, fz, pts)
	_opening(c, l)
	_proscenium(c, l, fz)
	_rear(c, l)
	_hall_lights(c, l, fz)


## The side and rear walls in board-marked concrete, round the mosaics and the slats; the screen wall behind the
## proscenium is the auditorium's.
static func _walls(c: Object, l: Auditorium.Layout, fz: float) -> void:
	var stone: Material = c.tinted("stone", "board_concrete")
	c.s.surface(stone)
	c.s.colour = _lin(CONCRETE)
	var len := l.hi.z - fz
	var height := l.hi.y - l.lo.y
	for s: float in [-1.0, 1.0]:
		var x := l.hi.x * s
		# Along the wall from the proscenium's face to the rear wall (left wall: from the back; the face's own axes).
		var origin := Vector3(x, l.lo.y, fz if s > 0.0 else l.hi.z)
		var u := Vector3(0, 0, 1) if s > 0.0 else Vector3(0, 0, -1)
		var m0 := (MURAL_FROM - fz) if s > 0.0 else (l.hi.z - MURAL_TO)
		var hole := Rect2(m0, MURAL_FOOT - l.lo.y, MURAL_TO - MURAL_FROM, MURAL_TOP - MURAL_FOOT)
		Shapes.wall(c.s, origin, u, Vector3(-s, 0, 0), len, height, [hole])
	var walk := l.row_floor(-l.rows_back)
	c.s.colour = _lin(CONCRETE)
	# The rear wall: concrete over the slats and either side of them, the felt behind the slats is its own.
	var span := l.hi.x - 1.6 - 0.9 - 0.15
	Shapes.wall(c.s, Vector3(l.hi.x, walk, l.hi.z), Vector3.LEFT, Vector3.FORWARD, l.hi.x * 2.0, l.hi.y - walk,
			[Rect2(l.hi.x - span, 0.0, span * 2.0, SLAT_TOP - walk)])


## The mosaics: one face a wall, a hair proud of it, in a bronze frame; the mosaic shader's material.
static func _murals(c: Object, h: Hall, l: Auditorium.Layout) -> void:
	var light: Node = c.kit._light
	var d: Dictionary = (c.kit.params["mosaic"] as Dictionary).duplicate()
	d["color"] = [1.0, 1.0, 1.0]
	var m: ShaderMaterial = light.from_param(d)
	m.shader = MOSAIC_SHADER
	m.set_shader_parameter("mosaic_map", Mosaics.atlas(MURAL_TO - MURAL_FROM, MURAL_TOP - MURAL_FOOT, TESSERA))
	m.set_shader_parameter("normal_strength", 0.3)
	m.set_shader_parameter("mosaic_grout", _lin(Color(0.3, 0.29, 0.27)))
	m.set_shader_parameter("mosaic_glint_sharp", 70.0)
	m.set_shader_parameter("mosaic_glint", float(c.kit.params["mosaic_glint"]))
	var lamp := _lin(GLOBE)
	m.set_shader_parameter("mosaic_glint_colour", Vector3(lamp.r, lamp.g, lamp.b) * 1.4)
	m.set_shader_parameter("mosaic_glint_pos", Vector3(0.0, 7.4, -6.0))
	var wash := _lin(h.wash) * float(c.kit.params["mosaic_wash"])
	m.set_shader_parameter("mosaic_wash", Vector4(wash.r, wash.g, wash.b, 2.4))
	m.set_shader_parameter("mosaic_wash_y", CORNICE_Y)
	h.mosaic_m = m
	h.mosaic.texel = 0.16
	h.mosaic.surface(m)
	var bronze: Material = c.tinted("gilt")
	for s: float in [-1.0, 1.0]:
		var x := l.hi.x * s - s * 0.02
		var n := Vector3(-s, 0, 0)
		h.mosaic.face([Vector3(x, MURAL_FOOT, MURAL_FROM), Vector3(x, MURAL_FOOT, MURAL_TO), Vector3(x, MURAL_TOP, MURAL_TO),
				Vector3(x, MURAL_TOP, MURAL_FROM)], n)
		# The mosaic's bed between it and the wall, and the bronze frame round it.
		c.s.surface(c.tinted("stone", "board_concrete"))
		c.s.colour = _lin(CONCRETE_DARK)
		var xw := l.hi.x * s
		for z: float in [MURAL_FROM, MURAL_TO]:
			c.s.face([Vector3(xw, MURAL_FOOT, z), Vector3(x, MURAL_FOOT, z), Vector3(x, MURAL_TOP, z),
					Vector3(xw, MURAL_TOP, z)], Vector3(0, 0, -1.0 if z == MURAL_FROM else 1.0))
		c.s.surface(bronze)
		c.s.colour = _lin(BRONZE)
		var fx := l.hi.x * s - s * 0.035
		for y: float in [MURAL_FOOT - 0.03, MURAL_TOP + 0.03]:
			c.s.box(Vector3(fx, y, (MURAL_FROM + MURAL_TO) * 0.5), Vector3(0.07, 0.06, MURAL_TO - MURAL_FROM + 0.12),
					Basis(), [Vector3(s, 0, 0)])
		for z: float in [MURAL_FROM - 0.03, MURAL_TO + 0.03]:
			c.s.box(Vector3(fx, (MURAL_FOOT + MURAL_TOP) * 0.5, z), Vector3(0.07, MURAL_TOP - MURAL_FOOT, 0.06), Basis(),
					[Vector3(s, 0, 0)])


## The cornices over the mosaics: a deep concrete ledge from the proscenium to the rear wall, its lip hiding the lamp
## line that washes the mosaic; its underside lit by that line (PieceCove), snow on it under the open roof.
static func _cornices(c: Object, l: Auditorium.Layout, fz: float) -> void:
	var stone: Material = c.tinted("stone", "board_concrete")
	var cove: RoomMesh = c.cove
	cove.surface(c.kit.cove_material())
	for s: float in [-1.0, 1.0]:
		var wx := l.hi.x * s
		var ox := wx - s * CORNICE_D
		c.s.surface(stone)
		c.s.colour = _lin(CONCRETE)
		# The fascia and the top.
		c.s.face([Vector3(ox, CORNICE_Y, fz), Vector3(ox, CORNICE_Y, l.hi.z), Vector3(ox, CORNICE_Y + CORNICE_H, l.hi.z),
				Vector3(ox, CORNICE_Y + CORNICE_H, fz)], Vector3(-s, 0, 0))
		c.s.face([Vector3(ox, CORNICE_Y + CORNICE_H, fz), Vector3(wx, CORNICE_Y + CORNICE_H, fz),
				Vector3(wx, CORNICE_Y + CORNICE_H, l.hi.z), Vector3(ox, CORNICE_Y + CORNICE_H, l.hi.z)], Vector3.UP)
		# The lip (a downstand at the front of the underside) and the underside, lit from the lamp line behind it.
		var lip := ox + s * 0.06
		c.s.face([Vector3(lip, CORNICE_Y - 0.12, fz), Vector3(lip, CORNICE_Y - 0.12, l.hi.z), Vector3(ox, CORNICE_Y - 0.12,
				l.hi.z), Vector3(ox, CORNICE_Y - 0.12, fz)], Vector3.DOWN)
		c.s.face([Vector3(ox, CORNICE_Y - 0.12, fz), Vector3(ox, CORNICE_Y - 0.12, l.hi.z), Vector3(ox, CORNICE_Y, l.hi.z),
				Vector3(ox, CORNICE_Y, fz)], Vector3(-s, 0, 0))
		c.s.face([Vector3(lip, CORNICE_Y - 0.12, fz), Vector3(lip, CORNICE_Y, fz), Vector3(lip, CORNICE_Y, l.hi.z),
				Vector3(lip, CORNICE_Y - 0.12, l.hi.z)], Vector3(s, 0, 0))
		# The underside and the wall above the mosaic: cove-lit by the line (a lamp along z at the wall's foot of it).
		var lamp_x := wx - s * 0.2
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		var base := _lin(CONCRETE * 0.95)
		for k in 4:
			var x := lerpf(lip, wx, float(k) / 3.0)
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for z: float in [fz, MURAL_FROM, MURAL_TO, l.hi.z]:
				row.append(Vector3(x, CORNICE_Y, z))
				nrow.append(Vector3.DOWN)
				var on := 1.0 if z >= MURAL_FROM - 0.5 and z <= MURAL_TO + 0.5 else 0.25
				crow.append(Color(base.r, base.g, base.b, on * (0.18 + 0.5 * absf(x - lip) / CORNICE_D)))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		cove.grid(rows, norms, cols)
		cove.colour = Color(base.r, base.g, base.b, 0.85)
		cove.face([Vector3(wx, MURAL_TOP + 0.06, fz), Vector3(wx, MURAL_TOP + 0.06, l.hi.z), Vector3(wx, CORNICE_Y, l.hi.z),
				Vector3(wx, CORNICE_Y, fz)], Vector3(-s, 0, 0))
		cove.colour = Color.WHITE
		_solid(c, Vector3(wx - s * CORNICE_D * 0.5, CORNICE_Y + CORNICE_H * 0.5 - 0.06, (fz + l.hi.z) * 0.5),
				Vector3(CORNICE_D, CORNICE_H + 0.12, l.hi.z - fz))
		# Snow lying on the ledge under the open roof, drifted against the wall.
		_snow(c, Vector3(wx - s * CORNICE_D * 0.5, CORNICE_Y + CORNICE_H, OPEN_FROM - 0.15),
				Vector3(wx - s * CORNICE_D * 0.5, CORNICE_Y + CORNICE_H, OPEN_TO + 0.15), CORNICE_D - 0.04, 0.11, 7 + int(s))


## The coffered ceiling: soffits and the beams' sides and undersides, each point lit by the globes near it.
static func _coffers(c: Object, l: Auditorium.Layout, fz: float, pts: Array[Vector3]) -> void:
	var b: RoomMesh = c.cove
	var cm: ShaderMaterial = c.kit.cove_material()
	# The coffers take little of the hall's fill: they read dark between the pools their globes lay on them.
	for k: String in ["sky_top", "sky_bottom"]:
		cm.set_shader_parameter(k, (cm.get_shader_parameter(k) as Vector3) * 0.45)
	b.surface(cm)
	var xs := _grid_x(l)
	var zs := _grid_z(fz)
	var top := l.hi.y
	var low := top - BEAM_D
	var hw := BEAM_W * 0.5
	var base := _lin(CONCRETE)
	var beam := _lin(CONCRETE * 0.96)
	for j in COFFERS_Z:
		for i in COFFERS_X:
			# The cell between the beams (the walls and the proscenium have none).
			var x0 := xs[i] + (hw if i > 0 else 0.0)
			var x1 := xs[i + 1] - (hw if i < COFFERS_X - 1 else 0.0)
			var z0 := zs[j] + (hw if j > 0 else 0.0)
			var z1 := zs[j + 1] - (hw if j < COFFERS_Z - 1 else EDGE_W * 0.5)
			_patch(b, Vector3(x0, top, z0), Vector3(x1 - x0, 0, 0), Vector3(0, 0, z1 - z0), 5, 5, Vector3.DOWN, base, pts)
			# The beams' sides round the cell, facing into it.
			if i > 0:
				_patch(b, Vector3(x0, low, z0), Vector3(0, 0, z1 - z0), Vector3(0, BEAM_D, 0), 4, 2, Vector3.RIGHT, beam,
						pts)
			if i < COFFERS_X - 1:
				_patch(b, Vector3(x1, low, z0), Vector3(0, 0, z1 - z0), Vector3(0, BEAM_D, 0), 4, 2, Vector3.LEFT, beam,
						pts)
			if j > 0:
				_patch(b, Vector3(x0, low, z0), Vector3(x1 - x0, 0, 0), Vector3(0, BEAM_D, 0), 4, 2, Vector3.BACK, beam,
						pts)
			var zb := z1
			var dz := BEAM_D if j < COFFERS_Z - 1 else EDGE_D
			_patch(b, Vector3(x0, top - dz, zb), Vector3(x1 - x0, 0, 0), Vector3(0, dz, 0), 4, 3, Vector3.FORWARD, beam,
					pts)
	# The beams' undersides: across the hall (between the proscenium and the edge beam) and along it.
	for j in range(1, COFFERS_Z):
		_patch(b, Vector3(l.lo.x, low, zs[j] - hw), Vector3(l.hi.x - l.lo.x, 0, 0), Vector3(0, 0, BEAM_W), 30, 1,
				Vector3.DOWN, beam, pts)
	for i in range(1, COFFERS_X):
		for j in COFFERS_Z:
			var z0 := zs[j] + (hw if j > 0 else 0.0)
			var z1 := zs[j + 1] - (hw if j < COFFERS_Z - 1 else EDGE_W * 0.5)
			_patch(b, Vector3(xs[i] - hw, low, z0), Vector3(BEAM_W, 0, 0), Vector3(0, 0, z1 - z0), 1, 3, Vector3.DOWN,
					beam, pts)
	b.colour = Color.WHITE


## The opening over the back rows: deep edge beams front and back, the coffers' grid going on as bare beams with snow
## on them, the rear strip's soffit over the walkway, snow on the walls' tops.
static func _opening(c: Object, l: Auditorium.Layout) -> void:
	var stone: Material = c.tinted("stone", "board_concrete")
	c.s.surface(stone)
	c.s.colour = _lin(CONCRETE)
	var top := l.hi.y
	var w := l.hi.x
	var xs := _grid_x(l)
	# The edge beams (their faces towards the coffers are the coffers' own: PieceCove).
	for ez: float in [OPEN_FROM, OPEN_TO]:
		var front := ez == OPEN_FROM
		c.s.box(Vector3(0.0, top - EDGE_D * 0.5, ez), Vector3(w * 2.0, EDGE_D, EDGE_W), Basis(),
				[RoomMesh.FRONT] if front else [])
		_snow(c, Vector3(-w, top, ez), Vector3(w, top, ez), EDGE_W, 0.2, 11 if front else 13)
	# The rear strip's soffit over the walkway and the booth.
	c.s.face([Vector3(-w, top, OPEN_TO + EDGE_W * 0.5), Vector3(w, top, OPEN_TO + EDGE_W * 0.5), Vector3(w, top, l.hi.z),
			Vector3(-w, top, l.hi.z)], Vector3.DOWN)
	# The grid over the opening: beams along it on the coffers' lines, one across its middle.
	var z0 := OPEN_FROM + EDGE_W * 0.5
	var z1 := OPEN_TO - EDGE_W * 0.5
	var mid := (OPEN_FROM + OPEN_TO) * 0.5
	for i in range(1, COFFERS_X):
		c.s.box(Vector3(xs[i], top - BEAM_D * 0.5, (z0 + z1) * 0.5), Vector3(BEAM_W, BEAM_D, z1 - z0), Basis(),
				[RoomMesh.FRONT, RoomMesh.BACK])
		_snow(c, Vector3(xs[i], top, z0), Vector3(xs[i], top, z1), BEAM_W, 0.17, 17 + i)
	c.s.box(Vector3(0.0, top - BEAM_D * 0.5, mid), Vector3(w * 2.0, BEAM_D, BEAM_W), Basis(), [RoomMesh.LEFT,
			RoomMesh.RIGHT])
	_snow(c, Vector3(-w, top, mid), Vector3(w, top, mid), BEAM_W, 0.17, 31)
	# The walls' tops round the opening (0.4 m thick), snow on them.
	for s: float in [-1.0, 1.0]:
		c.s.surface(stone)
		c.s.colour = _lin(CONCRETE)
		c.s.box(Vector3(s * (w + 0.2), top - 0.3, (OPEN_FROM + OPEN_TO) * 0.5), Vector3(0.4, 0.6, OPEN_TO - OPEN_FROM),
				Basis(), [Vector3(-s, 0, 0), RoomMesh.DOWN])
		_snow(c, Vector3(s * (w + 0.2), top, OPEN_FROM - 0.2), Vector3(s * (w + 0.2), top, OPEN_TO + 0.2), 0.46, 0.18,
				41 + int(s))


## A cap of snow along a line (a beam's top, a ledge) `width` wide: rounded across, its depth wandering along it, and
## draped a hand's breadth down both sides (seen from below, a white line along each beam's top edge); unbaked. prof: [across (a share of the half width; past 1 the drape's outside), up (a share of the depth; under 0
## metres down the side)].
static func _snow(c: Object, a: Vector3, b2: Vector3, width: float, depth: float, seed_value: int) -> void:
	var along := b2 - a
	var len := along.length()
	var dir := along / len
	var across := Vector3.UP.cross(dir).normalized()
	var n_along := maxi(2, int(len / 0.5))
	var half := width * 0.5 + 0.025
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bumps: Array[float] = []
	for k in n_along + 1:
		bumps.append(rng.randf_range(0.7, 1.15))
	for k in n_along + 1:
		var f := float(k) / n_along
		# Thinner at the ends (blown off the beam's end).
		var end := smoothstep(0.0, 0.08, f) * smoothstep(1.0, 0.92, f)
		var hgt := depth * bumps[k] * lerpf(0.4, 1.0, end)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		var drape := -0.15 * bumps[(k + 3) % bumps.size()] * lerpf(0.5, 1.0, end)
		for pr: Vector2 in [Vector2(-1.0, drape), Vector2(-1.0, 0.0), Vector2(-0.75, hgt * 0.62), Vector2(-0.35, hgt * 0.93),
				Vector2(0.0, hgt), Vector2(0.35, hgt * 0.93), Vector2(0.75, hgt * 0.62), Vector2(1.0, 0.0),
				Vector2(1.0, drape)]:
			row.append(a + dir * len * f + across * pr.x * half + Vector3.UP * pr.y)
			var up := 0.0 if pr.y <= 0.0 else (1.0 - absf(pr.x) * 0.6)
			nrow.append((Vector3.UP * up + across * signf(pr.x) * (1.0 if pr.y <= 0.0 else absf(pr.x))).normalized())
			crow.append(_lin(SNOW))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	# Unbaked: the snow keeps the hall's fill (the warm light rising through the opening) and stands out white.
	c.u.surface(c.soft("plaster"))
	c.u.grid(rows, norms, cols)


## The proscenium: a bold concrete frame on the stage, its opening stepped twice into the depth, a bronze edge on the
## first step, ribs on its side panels, an ochre valance inside its head.
static func _proscenium(c: Object, l: Auditorium.Layout, fz: float) -> void:
	var sc: Dictionary = _screen(c)
	var centre: Vector3 = sc["centre"]
	var size: Vector2 = sc["size"]
	var st := float(c.builder_params.get("stage_top", -2.1))
	var w := l.hi.x
	var top := l.hi.y
	var ox := size.x * 0.5 + OPEN_SIDE
	var oy := centre.y + size.y * 0.5 + OPEN_TOP
	var stone: Material = c.tinted("stone", "board_concrete")
	c.s.surface(stone)
	c.s.colour = _lin(CONCRETE)
	# The face: round the outer opening.
	var o1 := ox + STEP
	var t1 := oy + STEP
	Shapes.wall(c.s, Vector3(-w, st, fz), Vector3.RIGHT, Vector3.BACK, w * 2.0, top - st,
			[Rect2(w - o1, 0.0, o1 * 2.0, t1 - st)])
	# The first reveal and the step's face, the second reveal.
	for s: float in [-1.0, 1.0]:
		c.s.face([Vector3(s * o1, st, fz), Vector3(s * o1, t1, fz), Vector3(s * o1, t1, fz - STEP_DEPTH),
				Vector3(s * o1, st, fz - STEP_DEPTH)], Vector3(-s, 0, 0))
		c.s.face([Vector3(s * ox, st, fz - STEP_DEPTH), Vector3(s * o1, st, fz - STEP_DEPTH),
				Vector3(s * o1, t1, fz - STEP_DEPTH), Vector3(s * ox, t1, fz - STEP_DEPTH)], Vector3.BACK)
		c.s.colour = _lin(CONCRETE_DARK)
		c.s.face([Vector3(s * ox, st, fz - STEP_DEPTH), Vector3(s * ox, oy, fz - STEP_DEPTH),
				Vector3(s * ox, oy, fz - REVEAL_DEPTH), Vector3(s * ox, st, fz - REVEAL_DEPTH)], Vector3(-s, 0, 0))
		c.s.colour = _lin(CONCRETE)
	c.s.face([Vector3(-o1, t1, fz), Vector3(o1, t1, fz), Vector3(o1, t1, fz - STEP_DEPTH), Vector3(-o1, t1,
			fz - STEP_DEPTH)], Vector3.DOWN)
	c.s.face([Vector3(-ox, oy, fz - STEP_DEPTH), Vector3(ox, oy, fz - STEP_DEPTH), Vector3(ox, t1, fz - STEP_DEPTH),
			Vector3(-ox, t1, fz - STEP_DEPTH)], Vector3.BACK)
	c.s.colour = _lin(CONCRETE_DARK)
	c.s.face([Vector3(-ox, oy, fz - STEP_DEPTH), Vector3(ox, oy, fz - STEP_DEPTH), Vector3(ox, oy, fz - REVEAL_DEPTH),
			Vector3(-ox, oy, fz - REVEAL_DEPTH)], Vector3.DOWN)
	# Ribs on the side panels: fins standing out of the face, the film's light grazing them.
	c.s.colour = _lin(CONCRETE)
	var x := o1 + 0.55
	while x < w - 0.35:
		for s: float in [-1.0, 1.0]:
			c.s.box(Vector3(s * x, (st + top) * 0.5, fz + 0.08), Vector3(0.12, top - st, 0.16), Basis(),
					[RoomMesh.BACK, RoomMesh.DOWN, RoomMesh.UP])
		x += 0.42
	# A band over the opening's head across the face (a deep horizontal groove line).
	c.s.colour = _lin(CONCRETE_DARK)
	c.s.box(Vector3(0.0, t1 + 0.9, fz + 0.03), Vector3(o1 * 2.0, 0.08, 0.06), Basis(), [RoomMesh.FRONT])
	# The bronze edge round the first step.
	c.s.surface(c.tinted("gilt"))
	c.s.colour = _lin(BRONZE)
	for s: float in [-1.0, 1.0]:
		c.s.box(Vector3(s * (o1 - 0.025), (st + t1) * 0.5, fz + 0.02), Vector3(0.05, t1 - st, 0.05), Basis(),
				[RoomMesh.FRONT])
	c.s.box(Vector3(0.0, t1 - 0.025, fz + 0.02), Vector3(o1 * 2.0, 0.05, 0.05), Basis(), [RoomMesh.FRONT])
	# The valance inside the head: ochre velvet, pleated, behind the second reveal.
	c.s.surface(c.mat("drapes"))
	c.s.colour = Color.WHITE
	c.s.box(Vector3(0.0, oy - 0.45, fz - REVEAL_DEPTH - 0.06), Vector3(ox * 2.0, 0.9, 0.1), Basis(),
			[RoomMesh.FRONT, RoomMesh.UP])
	for s: float in [-1.0, 1.0]:
		_solid(c, Vector3(s * (w + o1) * 0.5, (st + top) * 0.5, fz - 0.5), Vector3(w - o1, top - st, 1.0))
	_solid(c, Vector3(0.0, (t1 + top) * 0.5, fz - 0.5), Vector3(o1 * 2.0, top - t1, 1.0))


## The rear wall: oak acoustic slats on dark felt from the walkway, round the booth's ports, a bronze rail over them;
## the clock over the booth.
static func _rear(c: Object, l: Auditorium.Layout) -> void:
	var walk := l.row_floor(-l.rows_back)
	var rz := l.hi.z
	var span := l.hi.x - 1.6 - 0.9 - 0.15
	var booth := Rect2(-2.25, 3.25 - walk, 4.5, 1.5)
	# The felt behind, round the booth's band; the band itself concrete, the ports in it.
	c.s.surface(c.tinted("fabric"))
	c.s.colour = _lin(FELT)
	Shapes.wall(c.s, Vector3(span, walk, rz - 0.004), Vector3.LEFT, Vector3.FORWARD, span * 2.0, SLAT_TOP - walk,
			[Rect2(span + booth.position.x, booth.position.y, booth.size.x, booth.size.y)])
	c.s.surface(c.tinted("stone", "board_concrete"))
	c.s.colour = _lin(CONCRETE)
	c.s.face([Vector3(booth.end.x, walk + booth.position.y, rz - 0.003), Vector3(booth.position.x,
			walk + booth.position.y, rz - 0.003), Vector3(booth.position.x, walk + booth.end.y, rz - 0.003),
			Vector3(booth.end.x, walk + booth.end.y, rz - 0.003)], Vector3.FORWARD)
	# The slats: oak battens, stopping round the booth's ports.
	c.s.surface(c.tinted("wood"))
	var x := -span + SLAT_PITCH * 0.5
	var k := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1974
	while x < span:
		c.s.colour = _lin(OAK * rng.randf_range(0.9, 1.08))
		var y0 := walk
		var y1 := SLAT_TOP
		if absf(x) < 2.3:
			# Under and over the booth's band.
			c.s.box(Vector3(x, (walk + walk + booth.position.y) * 0.5, rz - SLAT_D * 0.5 - 0.005),
					Vector3(SLAT_W, booth.position.y, SLAT_D), Basis(), [RoomMesh.BACK, RoomMesh.DOWN])
			y0 = walk + booth.end.y
		if y1 > y0:
			c.s.box(Vector3(x, (y0 + y1) * 0.5, rz - SLAT_D * 0.5 - 0.005), Vector3(SLAT_W, y1 - y0, SLAT_D), Basis(),
					[RoomMesh.BACK, RoomMesh.DOWN])
		x += SLAT_PITCH
		k += 1
	# The bronze rail over the slats and round the booth's band.
	c.s.surface(c.tinted("gilt"))
	c.s.colour = _lin(BRONZE)
	c.s.box(Vector3(0.0, SLAT_TOP + 0.03, rz - 0.035), Vector3(span * 2.0 + 0.1, 0.06, 0.07), Basis(), [RoomMesh.BACK])
	for y: float in [walk + booth.position.y, walk + booth.end.y]:
		c.s.box(Vector3(0.0, y, rz - 0.035), Vector3(4.6, 0.05, 0.07), Basis(), [RoomMesh.BACK])
	# The clock over the booth: a dark dial with lit bars (the kit's clock, the 1970s face), in a bronze ring.
	var cc := Vector3(0.0, SLAT_TOP + 1.65, rz - 0.06)
	var r := 0.6
	c.clocks.append([cc, Vector3.LEFT * r, Vector3.UP * r, Vector3.FORWARD])
	Shapes.lathe(c.s, [Vector2(r, 0.0), Vector2(r + 0.06, 0.0), Vector2(r + 0.06, 0.06), Vector2(r, 0.06)],
			Vector3(0.0, cc.y, rz), 32, Basis(Vector3.RIGHT, -PI * 0.5))


## The hall's light in the bake: the globes' light over the seats, the lamp lines down the mosaics, the winter sky's
## cold light through the opening, two footlights on the drapes; stand-in lamps among the globes until a bake.
static func _hall_lights(c: Object, l: Auditorium.Layout, fz: float) -> void:
	var warm := Color(1.0, 0.8, 0.56)
	for p: Vector3 in [Vector3(-4.4, 7.2, -9.5), Vector3(4.4, 7.2, -9.5), Vector3(-4.4, 7.2, -3.0),
			Vector3(4.4, 7.2, -3.0), Vector3(-8.0, 7.6, -6.5), Vector3(8.0, 7.6, -6.5), Vector3(0.0, 7.0, -6.2),
			Vector3(0.0, 7.4, -12.0)]:
		c.lamps.append([p, warm, 1.6])
	for p: Vector3 in [Vector3(-6.6, 7.4, -12.0), Vector3(6.6, 7.4, -12.0), Vector3(-6.6, 7.4, -1.0),
			Vector3(6.6, 7.4, -1.0), Vector3(0.0, 7.2, -1.0)]:
		c.glow_lights.append([p, warm, 1.3, 14.0])
	# The lamp lines under the cornices, aimed down the mosaics (the shader's wash is live; this is their bounce).
	for s: float in [-1.0, 1.0]:
		for z: float in [-10.5, -6.0, -1.5]:
			var at := Vector3(s * (l.hi.x - 0.35), CORNICE_Y - 0.1, z)
			c.spots.append([at, at + Vector3(s * 0.25, -3.0, 0.0), warm, 0.9, 7.5, 70.0])
	# The night through the opening: cold, from high over it.
	c.spots.append([Vector3(0.0, l.hi.y + 7.0, (OPEN_FROM + OPEN_TO) * 0.5), Vector3(0.0, 0.0, 4.0),
			Color(0.55, 0.66, 0.95), 0.7, 22.0, 45.0])
	# Footlights on the drapes and the valance from the stage's lip.
	var st := float(c.builder_params.get("stage_top", -2.1))
	for s: float in [-1.0, 1.0]:
		c.spots.append([Vector3(s * 4.0, st + 0.1, fz + 0.3), Vector3(s * 7.0, 3.0, fz - 1.4), warm, 1.2, 10.0, 30.0])
		# Uplights in the pit grazing the proscenium's ribbed side panels.
		c.spots.append([Vector3(s * 9.4, st - 0.7, fz + 1.4), Vector3(s * 9.4, 8.5, fz), warm, 2.2, 15.0, 22.0])


# --- The globes -------------------------------------------------------------------------------------------------------

## The field of globes: an opal sphere on a thin rod from a small rose in its coffer, each its own height; the globes'
## glow is the house lamps' (they go down for the film), brightest low in the sphere where the lamp sits.
static func _globe_field(c: Object, _e: Dictionary) -> void:
	var l := _layout(c)
	var fz := frame_z(c)
	var pts := globes(l, fz)
	# A little of the glow stays down to the film's level (the opal glass catches the hall's light: never black).
	var glow: ShaderMaterial = c.kit._lamp(GLOBE, GLOBE_ENERGY, 0.93, "house")
	glow.set_shader_parameter("use_vertex_colour", true)
	glow.set_shader_parameter("rim", 1.0)
	var iron: Material = c.soft("iron")
	for g in pts:
		c.lit.surface(glow)
		_sphere(c.lit, g, GLOBE_R)
		c.u.surface(iron)
		c.u.colour = Color.WHITE
		var rod_top := l.hi.y
		var rod_bottom := g.y + GLOBE_R * 0.92
		c.u.box(Vector3(g.x, (rod_top + rod_bottom) * 0.5, g.z), Vector3(0.016, rod_top - rod_bottom, 0.016), Basis(),
				[RoomMesh.UP, RoomMesh.DOWN])
		# The rose at the soffit and the gallery holding the glass.
		c.u.box(Vector3(g.x, rod_top - 0.02, g.z), Vector3(0.12, 0.04, 0.12), Basis(), [RoomMesh.UP])
		c.u.box(Vector3(g.x, g.y + GLOBE_R * 0.95, g.z), Vector3(0.08, 0.05, 0.08), Basis(), [RoomMesh.UP])


## An opal globe: rings of latitude with the glow per vertex, brighter low (the lamp sits below the middle) and a
## little darker at the gallery.
static func _sphere(b: RoomMesh, centre: Vector3, r: float) -> void:
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	var rings := 8
	var sides := 12
	for j in rings + 1:
		var lat := PI * 0.5 - PI * float(j) / rings
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for i in sides + 1:
			var a := TAU * float(i) / sides
			var n := Vector3(cos(lat) * cos(a), sin(lat), cos(lat) * sin(a))
			row.append(centre + n * r)
			nrow.append(n)
			var k := lerpf(1.12, 0.72, smoothstep(-0.6, 0.9, n.y))
			crow.append(Color(k, k, k))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	b.grid(rows, norms, cols)
