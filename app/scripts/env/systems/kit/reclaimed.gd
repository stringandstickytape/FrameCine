extends RefCounted

## Reclaimed's ruined picture house (docs/environments.md, "The kit" and "Room: Reclaimed"; since 2026-11-08, the deep
## pass: "continue working on the environments one-by-one like you did with the bathysphere, really improving their
## quality, imagination, delight, detail, lighting and so on. Better to do a smaller number of incredible superb ones
## than a large number not so", the user, 2026-11-08). A picture house of about 1912 taken back by nature on a
## September night: the back half of its roof fallen in, the Moon high behind the viewer laying its light through the
## trusses onto the stalls and the pit, the front half still roofed and dark, the film the one warm light.
## Everything is ours, drawn here; no figure anywhere.
##
## The auditorium builder (shell "kit") draws the tiers, the side aisles, the rear walkway and the seats; this draws
## the rest round them (pieces.gd dispatches here):
##   ruin_shell    the walls: brick under plaster fallen in sheets (damp, tide marks, faded paint above and below a
##                 dado), pilasters, a cornice; the proscenium (a plaster arch with faded gilt, grilles of lattice
##                 over the organ chambers, a cartouche and swags); the stage; the screen in its frame with its
##                 masking, stained round the picture, never on it; a torn curtain hanging at the left, the other
##                 fallen on the stage; the pit's boards rotted through in two places; the booth's ports; two
##                 doorways the deer uses
##   ruin_roof     the front half's plaster ceiling (coffered, holes to the laths, a chandelier's rose broken), its
##                 broken edge (snapped joists, dangling laths), the trusses over the open half against the sky (one
##                 broken), purlins, a patch of rafters with slates slid and caught, the front roof's broken end, the
##                 rear gable broken down
##   ruin_growth   ivy pouring over the wall tops and the ceiling's edge in masses, a young birch through the side
##                 aisle, ferns, grass and wildflowers in the moonlight's pool, moss on the seats and the stage, leaf
##                 litter, leaves on the puddle
##   ruin_stalls   the fallen chandelier in the pit (brass, crystals catching the moonlight), its broken chain, fallen
##                 plaster, laths, slates and bricks, the aisles' carpet rotted to the boards, leaves on the seats
##
## Materials (the light system's house materials, tinted per vertex): RuinBrick (red_brick), RuinPlaster
## (rough_plaster: walls, ceiling, mouldings, gilt by colour, rubble, the screen's sheet), RuinWood (rustic_planks:
## boards, timbers, laths, slates by colour, the voids nearly black), RuinCloth (velvet: curtains, masking, carpet),
## all baked; RuinBrass (unbaked), RuinCrystal (emission, the accent group), RuinLeaves (unbaked felt), RuinPort (the
## projector's lens, the booth group).
## The light: the Moon and the sky over the opening, traced here per vertex (moon_light(), sky_light()) as the room is
## built, since the run-time lightmapper threw no shadows (a box under a spot, under lavapipe, 2026-11-08). The baked
## meshes carry it in their vertex colours' alpha and the house shader adds it (vertex_light; in the bake too, as an
## emitter, so it bounces); the unbaked parts carry it in their vertex colours (_lit()); the seats in their instance
## colours. The film's spill on top. No live light, no bake light.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")

const PIECES: Array[String] = ["ruin_shell", "ruin_roof", "ruin_growth", "ruin_stalls"]

## The walls' tops (the eaves: the tie beams rest on them) and the ridge over the middle.
const TOP := 8.05
const RIDGE := 11.3
## The ceiling's underside, and where its broken edge runs on average (it wanders a metre either way: edge_z()).
const CEIL := 7.5
const EDGE_Z := -2.6
## The proscenium: its face, its thickness, the opening's half width, where its arch springs and its crown.
const PROS_Z := -9.15
const PROS_T := 0.3
const OPEN_HALF := 4.7
const OPEN_SPRING := 5.0
const OPEN_CROWN := 6.15
## The organ chambers' grilles either side of the opening: their middle (x), width, foot and where the round head
## starts.
const GRILLE_X := 6.35
const GRILLE_W := 1.7
const GRILLE_Y0 := 1.5
const GRILLE_Y1 := 5.3
## A hole through the front roof and its ceiling over the hall's left (the ceiling's in x, z; its radius): the Moon
## comes through it in a narrow shaft onto the pit's floor under the front roof, a pool of moonlight in the dark below
## the picture (on the stage's narrow apron it hardly showed from the seats; the second pass, 2026-11-08); from the
## seats a few stars show through it. The roof's hole sits up the Moon's ray from the ceiling's, and is larger.
const HOLE := Vector2(-6.74, -4.14)
const HOLE_R := 0.62
## The trusses over the open half (z), the one over the edge first.
const TRUSSES: Array[float] = [-2.9, 0.3, 3.1]
## Towards the Moon (the sky system's moon_bearing 246 and moon_altitude 45 with facing 0: behind the viewer and
## to the left), and its light's colour. Its light falls through the open roof over the left wall's broken top onto
## the right half of the stalls and the pit and the right wall, striped by the trusses; the left wall's top throws its
## ragged shadow across the pit; the stage and the screen stay in the front roof's shadow but for the shaft through
## its hole (HOLE).
const MOON_DIR := Vector3(-0.648, 0.707, 0.283)
const MOON_COLOUR := Color(0.62, 0.72, 1.0)
## The Moon's light in the vertex colours of the unbaked parts (leaves, brass): a lit leaf this much brighter.
const MOON_GAIN := 1.5
## The Moon's light on the baked parts (the shader's vertex_light, linear: a moonlit surface's colour times this; a
## cold pool you can read, never a floodlight: the film is the star), and the sky's share beside it.
const MOON_LIGHT := Vector3(0.62, 0.72, 1.0) * 0.55
const SKY_SHARE := 0.22
## Metres a lightmap texel covers, by mesh: brick, plaster, timber, cloth. The Moon's shadows ride in the vertices,
## so the lightmap carries only the soft bounce and the sky's fill; the headset bakes the room when it is first
## chosen, and these keep the atlases near 700,000 texels.
const TEXELS := {"brick": 0.12, "plaster": 0.14, "wood": 0.13, "cloth": 0.15}
## The walls' thickness (their outer faces: the Moon's shadows need them).
const WALL_T := 0.45
## Plaster stands this far out of the brick; its broken edges show this much (a lip you can read from the seats).
const PLASTER := 0.035
## The marching squares' cell on walls and the ceiling (metres).
const CELL := 0.2

## Colours (linear: the vertex colour is the colour shown).
const CREAM := Color(0.25, 0.235, 0.165)
const OXBLOOD := Color(0.12, 0.028, 0.02)
const GILT := Color(0.36, 0.22, 0.06)
const CEILING_WHITE := Color(0.42, 0.4, 0.34)
const DAMP_GREEN := Color(0.05, 0.075, 0.03)
## Brick: darker than the plaster over it, so a hole reads as a hole (the second pass, 2026-11-08: paler brick in
## the moonlight read as paper stuck on the wall).
const BRICK := Color(0.2, 0.125, 0.095)
## Plaster freshly broken: paler than its painted face (the lip round a hole).
const PLASTER_BREAK := Color(0.4, 0.38, 0.32)
const TIMBER := Color(0.42, 0.38, 0.33)
const BOARD := Color(0.36, 0.3, 0.25)
const VOID := Color(0.012, 0.011, 0.01)
const SLATE := Color(0.06, 0.065, 0.075)
const VELVET := Color(0.2, 0.035, 0.03)
const MASKING := Color(0.012, 0.012, 0.014)
const SHEET := Color(0.5, 0.48, 0.42)
const IVY := Color(0.018, 0.042, 0.012)
const LEAF := Color(0.07, 0.11, 0.03)
const MOSS := Color(0.07, 0.11, 0.02)
const LITTER: Array[Color] = [Color(0.16, 0.08, 0.025), Color(0.25, 0.13, 0.03), Color(0.11, 0.06, 0.03),
		Color(0.32, 0.22, 0.04), Color(0.2, 0.05, 0.02), Color(0.07, 0.05, 0.03)]
const BARK := Color(0.55, 0.53, 0.49)


## The ruin, kept on the kit's ctx (ctx.ruin) while its pieces draw, and what finish() adds.
class Ruin:
	var kit: Node
	var p := {}
	var L = null
	var lo := Vector3(-8, -0.4, -10)
	var hi := Vector3(8, 7.5, 5.6)
	var stage_front := -8.5
	var stage_top := 0.15
	var rng := RandomNumberGenerator.new()
	var brick := RoomMesh.new()
	var plaster := RoomMesh.new()
	var wood := RoomMesh.new()
	var cloth := RoomMesh.new()
	var brass := RoomMesh.new()
	var crystal := RoomMesh.new()
	var leaves := RoomMesh.new()
	var port := RoomMesh.new()
	## The room's seats (the auditorium's), and those drawn tipped up or broken (the seats system's lists).
	var seats: Array[Transform3D] = []
	var skip_seats: Array = []
	## Where things already lie on the pit's floor ([centre (x, z), radius]): litter and flowers keep off them.
	var taken: Array = []
	## The fallen chandelier's place on the floor and the puddle's (from the weather system).
	var chandelier := Vector3(3.7, -0.4, -3.55)
	var puddle := Rect2(-2.2, -4.9, 4.4, 2.6)
	## Holes rotted through the pit's boards: [centre (x, z), half size (x, z)].
	var holes: Array = [[Vector2(-3.5, -6.1), Vector2(0.75, 0.42)], [Vector2(5.6, -7.2), Vector2(0.5, 0.36)]]
	var shapes: Array = []
	var done := {}
	## The outer script's moon_light() and moon_alpha() (an inner class reaches them this way).
	var moon_fn: Callable
	var alpha_fn: Callable
	var sky_fn: Callable
	var vertex_fn: Callable

	func finish(k: Node) -> void:
		var cast := func(mi: MeshInstance3D) -> void:
			if mi != null:
				# The ruin shadows what the bake lights (the Moon's light in the vertices, an emitter in the bake):
				# the lightmapper leaves out meshes that cast no shadow. No live light casts one, so it costs nothing.
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for b: RoomMesh in [brick, plaster, wood, cloth]:
			alpha_fn.call(b)
		cast.call(k._add_static("RuinBrick", brick))
		cast.call(k._add_static("RuinPlaster", plaster))
		cast.call(k._add_static("RuinWood", wood))
		cast.call(k._add_static("RuinCloth", cloth))
		k._add_unbaked("RuinBrass", brass)
		k._add_lamps("RuinCrystal", crystal)
		k._add_unbaked("RuinLeaves", leaves)
		k._add_lamps("RuinPort", port)
		_tint_seats(k)
		_tint_floor(k)

	## The tiers' floor (the auditorium's mesh) takes the Moon in its vertices too.
	func _tint_floor(k: Node) -> void:
		var b: Node = k._builder()
		if b == null:
			return
		for n: Node in b.call("owned"):
			if n is MeshInstance3D and n.name == &"Floor":
				var mesh := (n as MeshInstance3D).mesh as ArrayMesh
				var out := ArrayMesh.new()
				for si in mesh.get_surface_count():
					var arrays := mesh.surface_get_arrays(si)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null \
							else PackedColorArray()
					cols.resize(verts.size())
					for i in verts.size():
						var c: Color = cols[i] if cols[i] != Color(0, 0, 0, 0) else Color.WHITE
						c.a = float(vertex_fn.call(verts[i], norms[i]))
						cols[i] = c
					arrays[Mesh.ARRAY_COLOR] = cols
					var m := mesh.surface_get_material(si) as ShaderMaterial
					out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					if m != null:
						m.set_shader_parameter("vertex_light", MOON_LIGHT)
						out.surface_set_material(si, m)
				out.lightmap_size_hint = mesh.lightmap_size_hint
				(n as MeshInstance3D).mesh = out

	## The seats under the Moon: their velvet a little brighter where it falls (a MultiMesh is never baked).
	func _tint_seats(k: Node) -> void:
		var b: Node = k._builder()
		if b == null:
			return
		for n: Node in b.call("owned"):
			if n is MultiMeshInstance3D and n.name == &"Seats":
				var mm := (n as MultiMeshInstance3D).multimesh
				var count := int(n.get_meta("instances", mm.instance_count))
				for i in mini(count, seats.size()):
					var st := seats[i]
					var lit := 0.0
					for q: Vector3 in [Vector3(0, 0.5, -0.1), Vector3(0, 0.75, 0.3), Vector3(-0.2, 0.6, 0.0),
							Vector3(0.2, 0.6, 0.0)]:
						lit += float(moon_fn.call(st * q)) * 0.25
					var c := mm.get_instance_color(i)
					mm.set_instance_color(i, c * (1.0 + 1.6 * lit))

	func tick(_delta: float) -> void:
		pass


## The ruin on the kit's ctx (made with the first piece), its layout from the auditorium's parameters.
static func ruin(c: Object) -> Ruin:
	if c.ruin != null:
		return c.ruin
	var r := Ruin.new()
	r.kit = c.kit
	r.moon_fn = moon_light
	r.alpha_fn = moon_alpha
	r.sky_fn = sky_light
	r.vertex_fn = vertex_light
	r.rng.seed = 1912
	r.p = c.builder_params
	if not r.p.is_empty():
		r.L = Auditorium.layout(r.p)
		r.lo = r.L.lo
		r.hi = r.L.hi
		r.stage_front = r.lo.z + float(r.p["stage_depth"])
		r.stage_top = float(r.p["stage_top"])
		r.seats = r.L.seat_transforms()
	var light: Node = c.kit._light
	var mat := func(library: String, spill: float, tiling := 0.0) -> ShaderMaterial:
		var d := {"library": library, "color": [1.0, 1.0, 1.0], "spill": spill}
		if tiling > 0.0:
			d["tiling"] = tiling
		var m: ShaderMaterial = light.from_param(d)
		m.set_shader_parameter("instance_tint", true)
		# The Moon's and the sky's light, worked out per vertex (moon_alpha()), in the vertex colours' alpha.
		m.set_shader_parameter("vertex_light", MOON_LIGHT)
		return m
	var soft := func(library: String, spill: float) -> ShaderMaterial:
		var m: ShaderMaterial = light.from_param({"library": library, "color": [1.0, 1.0, 1.0], "spill": spill}, true)
		m.set_shader_parameter("instance_tint", true)
		return m
	# Their share of the film's light: a tint, never a light (the second pass, 2026-11-08: the test picture's warm and
	# cool halves split the hall in two at twice these).
	r.brick.surface(mat.call("red_brick", 0.06, 1.3))
	r.plaster.surface(mat.call("rough_plaster", 0.09, 1.6))
	r.wood.surface(mat.call("rustic_planks", 0.08, 1.6))
	r.cloth.surface(mat.call("velvet", 0.12))
	r.brass.surface(soft.call("brass", 0.12))
	var leaf_m: ShaderMaterial = soft.call("felt", 0.05)
	leaf_m.set_shader_parameter("tiling", 0.2)
	r.leaves.surface(leaf_m)
	var crystal_m: ShaderMaterial = light.lamp_material(Color(0.8, 0.88, 1.0), 1.0, 1.0, "accent")
	crystal_m.set_shader_parameter("use_vertex_colour", true)
	r.crystal.surface(crystal_m)
	r.port.surface(light.lamp_material(Color(1.0, 0.92, 0.75), 1.1, 0.0, "accent"))
	r.brick.texel = TEXELS["brick"]
	r.plaster.texel = TEXELS["plaster"]
	r.wood.texel = TEXELS["wood"]
	r.cloth.texel = TEXELS["cloth"]
	# Which seats the seats system draws tipped up or broken: no moss or leaves on a seat that is not there.
	var seats_sys: Node = c.kit.host.system("seats") if c.kit.host != null else null
	if seats_sys != null:
		r.skip_seats = (seats_sys.params.get("broken", []) as Array) + (seats_sys.params.get("up", []) as Array)
	var w: Node = c.kit.host.system("weather") if c.kit.host != null else null
	if w != null and bool(w.params.get("puddle", false)):
		var pc: Array = w.params["puddle_center"]
		var ps: Array = w.params["puddle_size"]
		r.puddle = Rect2(float(pc[0]) - float(ps[0]) * 0.5, float(pc[2]) - float(ps[1]) * 0.5, float(ps[0]),
				float(ps[1]))
	r.taken.append([Vector2(r.chandelier.x, r.chandelier.z), 0.95])
	c.ruin = r
	return r


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	var r := ruin(c)
	if r.done.has(piece):
		return
	r.done[piece] = true
	match piece:
		"ruin_shell":
			_walls(r)
			_proscenium(r)
			_stage(r)
			_screen(r)
			_curtains(r)
			_pit(r)
			_booth(r)
			_doorways(r)
		"ruin_roof":
			_ceiling(r)
			_edge(r)
			_trusses(r)
			_roof(r)
		"ruin_growth":
			_ivy_all(r)
			_birch(r, Vector3(7.25, 0.0, 3.35))
			_ferns_all(r)
			_meadow(r)
			_moss(r)
			_litter(r)
		"ruin_stalls":
			_chandelier(r)
			_rubble(r)
			_carpet(r)
			_seat_leaves(r)
	for b: RoomMesh in [r.brick, r.plaster, r.wood, r.cloth, r.brass, r.crystal, r.leaves]:
		b.colour = Color.WHITE


# --- The layout ------------------------------------------------------------------------------------------------------

## Where the ceiling's broken edge runs at x: the ceiling covers z under it.
static func edge_z(x: float) -> float:
	return EDGE_Z + 0.5 * sin(0.8 * x + 0.4) + 0.28 * sin(2.1 * x + 2.0) + 0.14 * sin(5.3 * x + 0.7)


## The roof's slope over x (the trusses' rafters' line, their top).
static func roof_y(x: float) -> float:
	return TOP + (RIDGE - TOP) * clampf(1.0 - absf(x) / 8.25, 0.0, 1.0)


## A side wall's top at z: whole under the front roof, broken down in bites under the open half.
static func wall_top(side: float, z: float) -> float:
	var open := smoothstep(edge_z(side * 8.0) - 0.6, edge_z(side * 8.0) + 0.8, z)
	var bite := maxf(0.0, _n(z * 0.9, side * 3.1, 3) * 1.4 - 0.15) + maxf(0.0, _n(z * 3.1, side, 5) - 0.3) * 0.5
	return TOP - open * bite


## The rear gable's top at x: the roof's line, its apex fallen in.
static func gable_top(x: float) -> float:
	var y := roof_y(x) + 0.25
	var fallen := 1.7 * (1.0 - smoothstep(0.4, 3.4, absf(x + 0.6))) + maxf(0.0, _n(x * 1.3, 7.0, 9)) * 0.7
	return maxf(y - fallen, TOP - 0.3)


## The floor's height along the side walls at z (the pit, then the aisle's steps, then the rear walkway).
static func floor_at(r: Ruin, z: float) -> float:
	if r.L == null:
		return r.lo.y
	if z < r.stage_front:
		return r.stage_top
	return r.L.aisle_floor(z)


## The front row's riser (its arc) at x: the pit ends there.
static func riser_z(r: Ruin, x: float) -> float:
	if r.L == null:
		return -0.6
	var rad: float = r.L.row_radius(r.L.rows_front) - r.L.depth * 0.5
	return r.L.arc_z(rad, clampf(x, -r.L.block_x, r.L.block_x))


## How much of the Moon's light reaches p (room frame), 0..1: the ray towards the Moon leaves through the open roof
## (between the ceiling's broken edge and the rear wall, over the walls' broken tops and the gable), past the trusses
## and the slates still on the right. For the parts left out of the bake, so they agree with it.
static func moon_light(p: Vector3) -> float:
	if p.y > RIDGE + 0.5:
		return 1.0
	return _moon_trusses(p) * _moon_open(p)


## The trusses' shadow on p (1: none): each member a soft band, its penumbra widening with the distance to it (wider
## than the Moon's own, so the shadow falls across the vertices smoothly instead of in steps; the second pass,
## 2026-11-08).
static func _moon_trusses(p: Vector3) -> float:
	var d := MOON_DIR.normalized()
	var lit := 1.0
	for tz: float in TRUSSES:
		if (tz - p.z) * d.z <= 0.0:
			continue
		var t := (tz - p.z) / d.z
		var q := p + d * t
		if absf(q.x) > 8.3:
			continue
		var soft := 0.05 + 0.035 * t
		var hit := _band(q.y, TOP - 0.3, TOP + 0.02, soft)
		if not (tz > 3.0 and q.x < -3.4):
			hit = maxf(hit, _band(q.y, roof_y(q.x) - 0.32, roof_y(q.x) + 0.02, soft))
		hit = maxf(hit, _band(q.x, -0.12, 0.12, soft) * _band(q.y, TOP - 0.3, RIDGE, soft))
		lit *= 1.0 - 0.88 * hit
	return lit


## 1 between a and b, 0 outside, soft by s either side.
static func _band(x: float, a: float, b: float, s: float) -> float:
	return smoothstep(a - s, a + s, x) * (1.0 - smoothstep(b - s, b + s, x))


## The Moon at p past the walls, the gables, the front roof (its hole) and the slates (0..1).
static func _moon_open(p: Vector3) -> float:
	var d := MOON_DIR.normalized()
	# Where it crosses the walls' tops (y = TOP) or a wall below them.
	var t_top := (TOP - p.y) / d.y if p.y < TOP else 0.0
	var at := p + d * t_top
	if at.z > 5.6:
		# Out through the rear wall's plane first: over the gable, or blocked.
		var t := (5.6 - p.z) / d.z
		var g := p + d * t
		return smoothstep(-0.25, 0.25, g.y - gable_top(g.x))
	if at.x < -8.0:
		var t := (-8.0 - p.x) / d.x
		var g := p + d * t
		return smoothstep(-0.2, 0.2, g.y - wall_top(-1.0, g.z))
	if at.z < edge_z(at.x) + 0.15:
		# Under the front roof: only through its hole.
		if p.y < CEIL:
			var hq := p + d * ((CEIL - p.y) / d.y)
			return 1.0 - smoothstep(HOLE_R - 0.25, HOLE_R, Vector2(hq.x, hq.z).distance_to(HOLE))
		return 0.0
	# The slates and rafters still on the right slope.
	if at.x > 3.0:
		var k := (RIDGE - TOP) / 8.25
		var t2 := (RIDGE - p.y - k * p.x) / (d.y + k * d.x)
		var s := p + d * t2
		if s.x > 4.3 and s.x < 8.2 and s.z > 0.5 and s.z < 5.6:
			var cover := smoothstep(-0.12, 0.12, _n(s.x * 1.7, s.z * 1.3, 21) + 0.15 + (s.x - 5.2) * 0.12) \
					* smoothstep(5.05, 5.35, s.x)
			return (1.0 - 0.92 * cover) * smoothstep(edge_z(at.x) + 0.15, edge_z(at.x) + 0.45, at.z)
	return smoothstep(edge_z(at.x) + 0.15, edge_z(at.x) + 0.45, at.z)


## Whether a slate is still on the right slope at (x, z) (the roof's lower courses, with gaps).
static func _slate_left(x: float, z: float) -> bool:
	if x < 5.2:
		return false
	return _n(x * 1.7, z * 1.3, 21) > -0.15 - (x - 5.2) * 0.12


# --- Noise and helpers ---------------------------------------------------------------------------------------------------

static var _noises := {}


## Smooth noise, -1..1 (about), one feature a unit.
static func _n(x: float, y: float, seed_value: int) -> float:
	var fn: FastNoiseLite = _noises.get(seed_value)
	if fn == null:
		fn = FastNoiseLite.new()
		fn.seed = seed_value
		fn.noise_type = FastNoiseLite.TYPE_PERLIN
		fn.frequency = 1.0
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 3
		_noises[seed_value] = fn
	return fn.get_noise_2d(x, y) * 1.6


static func _n3(p: Vector3, seed_value: int) -> float:
	var fn: FastNoiseLite = _noises.get(seed_value + 100000)
	if fn == null:
		fn = FastNoiseLite.new()
		fn.seed = seed_value
		fn.noise_type = FastNoiseLite.TYPE_PERLIN
		fn.frequency = 1.0
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 2
		_noises[seed_value + 100000] = fn
	return fn.get_noise_3dv(p) * 1.6


## A layer over a plane where f(a, v) > 0 (a along u_axis, v along v_axis from origin, metres), by marching squares
## over cells of `cell`, lifted `off` along n; its cut edges get a side `depth` deep back towards the plane. One chart
## (its coordinates a and v). col(a, v) -> Color (linear) for each point. `lip` (its alpha the share): the cut edges'
## sides take this colour and the face's points on the cut edge half of it (broken plaster, paler than its face);
## alpha 0: the sides a little darker than the face.
static func _masked(b: RoomMesh, origin: Vector3, u_axis: Vector3, v_axis: Vector3, n: Vector3, a0: float,
		a1: float, v0: float, v1: float, cell: float, f: Callable, col: Callable, off: float, depth: float,
		chart := true, lip := Color(0, 0, 0, 0)) -> void:
	var nx := maxi(ceili((a1 - a0) / cell), 1)
	var ny := maxi(ceili((v1 - v0) / cell), 1)
	var da := (a1 - a0) / nx
	var dv := (v1 - v0) / ny
	var vals := PackedFloat32Array()
	vals.resize((nx + 1) * (ny + 1))
	for j in ny + 1:
		for i in nx + 1:
			vals[j * (nx + 1) + i] = float(f.call(a0 + i * da, v0 + j * dv))
	if chart:
		b._begin_chart()
	var keep := b.colour
	var lift := n * off
	var back := -n * depth
	for j in ny:
		for i in nx:
			var corners: Array[Vector2] = [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
			var vs: Array[float] = []
			var inside := 0
			for cc: Vector2 in corners:
				var v := vals[int(cc.y) * (nx + 1) + int(cc.x)]
				vs.append(v)
				if v > 0.0:
					inside += 1
			if inside == 0:
				continue
			var poly: Array[Vector2] = []
			var on_cut: Array[bool] = []
			var cuts: Array[Vector2] = []
			for k in 4:
				var ca := corners[k]
				var cb := corners[(k + 1) % 4]
				var va := vs[k]
				var vb := vs[(k + 1) % 4]
				if va > 0.0:
					poly.append(ca)
					on_cut.append(false)
				if (va > 0.0) != (vb > 0.0):
					var t := va / (va - vb)
					var pt := ca.lerp(cb, t)
					poly.append(pt)
					on_cut.append(true)
					cuts.append(pt)
			var pts: Array[Vector3] = []
			var base: int = b._current.verts.size()
			for qi in poly.size():
				var q := poly[qi]
				var a := a0 + q.x * da
				var vv := v0 + q.y * dv
				var w := origin + u_axis * a + v_axis * vv + lift
				pts.append(w)
				b.colour = col.call(a, vv)
				if on_cut[qi] and lip.a > 0.0:
					b.colour = b.colour.lerp(Color(lip.r, lip.g, lip.b), lip.a * 0.35)
				b._vertex(w, n, Vector2(a, vv))
			for k in range(1, pts.size() - 1):
				b._triangle(base, base + k, base + k + 1, pts[0], pts[k], pts[k + 1], n)
			# The cut edges: a side back to the plane, facing out of the layer.
			if depth > 0.0:
				for k in range(0, cuts.size() - 1, 2):
					var c0 := cuts[k]
					var c1 := cuts[k + 1]
					var g := Vector2(vs[1] - vs[0] + vs[2] - vs[3], vs[3] - vs[0] + vs[2] - vs[1])
					var side := -(u_axis * g.x * dv + v_axis * g.y * da).normalized()
					var e0 := origin + u_axis * (a0 + c0.x * da) + v_axis * (v0 + c0.y * dv) + lift
					var e1 := origin + u_axis * (a0 + c1.x * da) + v_axis * (v0 + c1.y * dv) + lift
					var uv0 := Vector2(a0 + c0.x * da, v0 + c0.y * dv)
					var uv1 := Vector2(a0 + c1.x * da, v0 + c1.y * dv)
					var s0: int = b._current.verts.size()
					b.colour = (col.call(uv0.x, uv0.y) as Color) * 0.8
					if lip.a > 0.0:
						b.colour = (col.call(uv0.x, uv0.y) as Color).lerp(Color(lip.r, lip.g, lip.b), lip.a)
					b._vertex(e0, side, uv0)
					b._vertex(e1, side, uv1)
					b._vertex(e1 + back, side, uv1)
					b._vertex(e0 + back, side, uv0)
					b._triangle(s0, s0 + 1, s0 + 2, e0, e1, e1 + back, side)
					b._triangle(s0, s0 + 2, s0 + 3, e0, e1 + back, e0 + back, side)
	b.colour = keep
	if chart:
		b._end_chart()


## A grid over a plane between a bottom line and a top line (bottom(a), top(a), metres along v from origin), one
## chart, colours from col(a, v).
static func _sheet(b: RoomMesh, origin: Vector3, u_axis: Vector3, v_axis: Vector3, n: Vector3, a0: float, a1: float,
		bottom: Callable, top: Callable, da: float, rows: int, col: Callable) -> void:
	var nx := maxi(ceili((a1 - a0) / da), 1)
	b._begin_chart()
	var keep := b.colour
	var base: int = b._current.verts.size()
	var grid: Array = []
	for i in nx + 1:
		var a := lerpf(a0, a1, float(i) / nx)
		var y0 := float(bottom.call(a))
		var y1 := float(top.call(a))
		var col_pts: Array[Vector3] = []
		for j in rows + 1:
			var v := lerpf(y0, y1, float(j) / rows)
			var w := origin + u_axis * a + v_axis * v
			col_pts.append(w)
			b.colour = col.call(a, v)
			b._vertex(w, n, Vector2(a, v))
		grid.append(col_pts)
	for i in nx:
		for j in rows:
			var k := base + i * (rows + 1) + j
			var p0: Vector3 = grid[i][j]
			var p1: Vector3 = grid[i + 1][j]
			var p2: Vector3 = grid[i + 1][j + 1]
			var p3: Vector3 = grid[i][j + 1]
			b._triangle(k, k + rows + 1, k + rows + 2, p0, p1, p2, n)
			b._triangle(k, k + rows + 2, k + 1, p0, p2, p3, n)
	b.colour = keep
	b._end_chart()


## A box with its own colour (each face a chart).
static func _box(b: RoomMesh, centre: Vector3, size: Vector3, basis := Basis(), colour := Color.WHITE,
		skip: Array = []) -> void:
	var keep := b.colour
	b.colour = colour
	b.box(centre, size, basis, skip)
	b.colour = keep


## A beam from a to c, `w` across and `h` deep (up the `up` side), coloured.
static func _beam(b: RoomMesh, a: Vector3, c: Vector3, w: float, h: float, colour: Color, up := Vector3.UP) -> void:
	var dir := (c - a).normalized()
	var side := up.cross(dir)
	if side.length() < 0.01:
		side = Vector3.RIGHT.cross(dir)
	side = side.normalized()
	var upn := dir.cross(side).normalized()
	_box(b, (a + c) * 0.5, Vector3(w, h, a.distance_to(c)), Basis(side, upn, dir), colour)


## A swept profile along a path (each profile segment a strip: a chart): path points, the profile [Vector2(out, up)]
## in the frame of `outward` and `up`, the colour of each profile segment.
static func _sweep(b: RoomMesh, path: Array[Vector3], outward: Array[Vector3], up: Vector3, profile: Array[Vector2],
		colours: Array[Color]) -> void:
	var keep := b.colour
	for k in profile.size() - 1:
		var la := PackedVector3Array()
		var lb := PackedVector3Array()
		var ns := PackedVector3Array()
		var pa := profile[k]
		var pb := profile[k + 1]
		var seg := pb - pa
		var pn := Vector2(seg.y, -seg.x).normalized()
		for i in path.size():
			var o := outward[i]
			la.append(path[i] + o * pa.x + up * pa.y)
			lb.append(path[i] + o * pb.x + up * pb.y)
			ns.append((o * pn.x + up * pn.y).normalized())
		b.colour = colours[mini(k, colours.size() - 1)]
		b.strip(la, lb, ns)
	b.colour = keep


## A flat leaf (single sided, facing `normal`): a pointed oval along `along`, `width` across, in two triangles.
static func _leaf(b: RoomMesh, at: Vector3, along: Vector3, width: float, normal: Vector3, colour: Color,
		double := false) -> void:
	var across := normal.cross(along).normalized() * width * 0.5
	var tip := at + along
	var mid := at + along * 0.45
	var keep := b.colour
	b.colour = colour
	var base: int = b._current.verts.size()
	for q: Vector3 in [at, mid + across, tip, mid - across]:
		b._vertex(q, normal, Vector2.ZERO)
	b._triangle(base, base + 1, base + 2, at, mid + across, tip, normal)
	b._triangle(base, base + 2, base + 3, at, tip, mid - across, normal)
	if double:
		var nb := -normal
		var bb: int = b._current.verts.size()
		b.colour = colour * 0.7
		for q: Vector3 in [at, mid + across, tip, mid - across]:
			b._vertex(q, nb, Vector2.ZERO)
		b._triangle(bb, bb + 1, bb + 2, at, mid + across, tip, nb)
		b._triangle(bb, bb + 2, bb + 3, at, tip, mid - across, nb)
	b.colour = keep


## A tube along points (radius at each), `sides` round, coloured per point; no chart (unbaked parts).
static func _tube(b: RoomMesh, pts: Array[Vector3], radii: Array[float], sides: int, cols: Array[Color]) -> void:
	if pts.size() < 2:
		return
	var keep := b.colour
	var rings: Array = []
	var prev_side := Vector3.ZERO
	for i in pts.size():
		var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := t.cross(Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT).normalized()
		if prev_side != Vector3.ZERO and side.dot(prev_side) < 0.0:
			side = -side
		prev_side = side
		var up := side.cross(t).normalized()
		var ring: Array[Vector3] = []
		for s in sides:
			var a := TAU * s / sides
			ring.append(side * cos(a) + up * sin(a))
		rings.append(ring)
	for i in pts.size() - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s in sides:
			var s1 := (s + 1) % sides
			var n0: Vector3 = r0[s]
			var n1: Vector3 = r0[s1]
			var m0: Vector3 = r1[s]
			var m1: Vector3 = r1[s1]
			var a := pts[i] + n0 * radii[i]
			var c := pts[i] + n1 * radii[i]
			var d := pts[i + 1] + m1 * radii[i + 1]
			var e := pts[i + 1] + m0 * radii[i + 1]
			var base: int = b._current.verts.size()
			b.colour = cols[i]
			b._vertex(a, n0, Vector2.ZERO)
			b._vertex(c, n1, Vector2.ZERO)
			b.colour = cols[i + 1]
			b._vertex(d, m1, Vector2.ZERO)
			b._vertex(e, m0, Vector2.ZERO)
			var fn := (n0 + n1 + m0 + m1).normalized()
			b._triangle(base, base + 1, base + 2, a, c, d, fn)
			b._triangle(base, base + 2, base + 3, a, d, e, fn)
	b.colour = keep


## A colour lit by the Moon at p (the unbaked parts: their vertex colours carry its light).
static func _lit(colour: Color, p: Vector3) -> Color:
	var k := 1.0 + MOON_GAIN * moon_light(p) + 0.6 * sky_light(p, Vector3.UP)
	return Color(colour.r * k, colour.g * k, colour.b * k, colour.a)


# --- The shell -------------------------------------------------------------------------------------------------------

## The walls: brick, plaster over it fallen in sheets, a dado, pilasters, the cornice under the ceiling.
static func _walls(r: Ruin) -> void:
	for side: float in [-1.0, 1.0]:
		var x := side * r.hi.x
		var n := Vector3(-side, 0, 0)
		var origin := Vector3(x, 0, 0)
		var door := side < 0.0
		# The brick: a sheet from under the floor to the broken top, round the doorway at the left's front.
		var bottom := func(_a: float) -> float: return r.lo.y - 0.05
		var top := func(a: float) -> float: return wall_top(side, a)
		var bcol := func(a: float, v: float) -> Color: return _brick_colour(r, side, a, v)
		if door:
			_sheet(r.brick, origin, Vector3.BACK, Vector3.UP, n, r.lo.z, -8.05, bottom, top, 0.3, 28, bcol)
			_sheet(r.brick, origin, Vector3.BACK, Vector3.UP, n, -8.05, -6.85, func(_a: float) -> float: return 2.0,
					top, 0.4, 8, bcol)
			_sheet(r.brick, origin, Vector3.BACK, Vector3.UP, n, -6.85, r.hi.z, bottom, top, 0.3, 28, bcol)
		else:
			_sheet(r.brick, origin, Vector3.BACK, Vector3.UP, n, r.lo.z, r.hi.z, bottom, top, 0.3, 28, bcol)
		var mask := func(a: float, v: float) -> float: return _wall_plaster(r, side, a, v)
		var pcol := func(a: float, v: float) -> Color: return _plaster_colour(r, side, a, v)
		_masked(r.plaster, origin, Vector3.BACK, Vector3.UP, n, PROS_Z, r.hi.z, r.lo.y, TOP, CELL, mask, pcol,
				PLASTER, PLASTER, true, Color(PLASTER_BREAK, 0.75))
		# Pilasters: under the front roof whole, under the open half broken off.
		for pz: float in [-6.6, -4.0, -0.9, 2.2]:
			_pilaster(r, side, pz)
		_dado(r, side)
		_cornice_side(r, side)
	_rear_wall(r)
	_wall_backs(r)


static func _brick_colour(r: Ruin, side: float, z: float, y: float) -> Color:
	var c := BRICK * (0.85 + 0.25 * _n(z * 0.7, y * 0.7, 31))
	# In a hole: darker near the plaster's edge (its lip shades it, the dirt collects), the brick's own colour deeper
	# in.
	c *= _hole_shade(_wall_plaster(r, side, z, y))
	var fl := floor_at(r, z)
	# Rising damp at the foot, darker; green where the rain runs down from the broken top.
	c = c.lerp(c * 0.45, 1.0 - smoothstep(0.0, 1.4, y - fl))
	var open := smoothstep(edge_z(side * 8.0) - 0.5, edge_z(side * 8.0) + 1.0, z)
	var streak := maxf(0.0, _n(z * 2.6, 0.3 * side, 33)) * open * smoothstep(3.0, 7.5, y)
	c = c.lerp(Color(0.12, 0.16, 0.07), clampf(streak * 1.2, 0.0, 0.8))
	return c


## The plaster on a side wall: most of it on under the front roof, fallen in sheets where the rain comes in and where
## the damp rises, none over the doorway or above the cornice.
static func _wall_plaster(r: Ruin, side: float, z: float, y: float) -> float:
	var fl := floor_at(r, z)
	var open := smoothstep(edge_z(side * 8.0) - 1.0, edge_z(side * 8.0) + 1.5, z)
	var top := wall_top(side, z) - 0.25 - 0.35 * open
	var v := 0.42 - 0.95 * maxf(0.0, _n(z * 0.42, y * 0.42 + side * 5.0, 41))
	v -= 0.55 * maxf(0.0, _n(z * 1.3, y * 1.3, 43)) * (0.5 + open)
	v -= 0.5 * open * smoothstep(-0.2, 0.5, _n(z * 0.6 + 3.0, y * 0.35, 45))
	v -= 0.6 * (1.0 - smoothstep(0.15, 0.7, y - fl)) * (0.5 + 0.5 * _n(z * 1.7, 1.0, 47))
	v = minf(v, top - y)
	v = minf(v, y - (fl - 0.02))
	if side < 0.0:
		# The doorway at the left's front, its plaster broken back round it.
		var dz := maxf(absf(z + 7.45) - 0.6, 0.0)
		var dy := maxf(y - 1.95, 0.0)
		v = minf(v, Vector2(dz, dy).length() - 0.12 - 0.12 * _n(z * 4.0, y * 4.0, 49))
	return v


static func _plaster_colour(r: Ruin, side: float, z: float, y: float) -> Color:
	var fl := floor_at(r, z)
	var h := y - fl
	var c := CREAM if h > 1.3 else OXBLOOD
	if h > 1.22 and h < 1.3:
		c = GILT * 0.6
	c = c * (0.82 + 0.3 * _n(z * 0.9, y * 0.9, 51))
	# Damp: a tide mark at about 0.9 m (a pale salt line over a darker band), brown blooms, green streaks from the top
	# under the open roof.
	var tide := 0.9 + 0.15 * _n(z * 0.5, 2.0, 53)
	if h < tide:
		c *= 0.62
	elif h < tide + 0.07:
		c = c.lerp(Color(0.36, 0.33, 0.26), 0.55)
	var bloom := maxf(0.0, _n(z * 0.35, y * 0.35, 55) - 0.2)
	c = c.lerp(c * Color(0.55, 0.45, 0.32), clampf(bloom * 1.5, 0.0, 0.7))
	var open := smoothstep(edge_z(side * 8.0) - 1.0, edge_z(side * 8.0) + 1.5, z)
	var streak := maxf(0.0, _n(z * 3.1, 9.0, 57)) * open * smoothstep(2.5, 7.0, y)
	c = c.lerp(DAMP_GREEN, clampf(streak * 1.4 + 0.1 * open, 0.0, 0.8))
	return c * (1.0 - 0.12 * open)


## How much of the brick's colour shows in a plaster hole by the plaster's mask there (negative in the hole): half
## at the edge, all of it 0.4 m in.
static func _hole_shade(mask: float) -> float:
	return lerpf(0.5, 1.0, smoothstep(0.0, -0.4, mask))


static func _pilaster(r: Ruin, side: float, z: float) -> void:
	var x := side * (r.hi.x - 0.11)
	var fl := floor_at(r, z)
	var under := z < edge_z(side * 8.0) - 0.2
	var top := 6.5 if under else 4.2 + 1.4 * fposmod(z * 1.37, 1.0)
	var c := CREAM * 0.6
	var b := r.plaster
	_box(b, Vector3(x, (fl + top) * 0.5, z), Vector3(0.22, top - fl, 0.6), Basis(), c, [Vector3(side, 0, 0)])
	_box(b, Vector3(side * (r.hi.x - 0.14), fl + 0.15, z), Vector3(0.28, 0.3, 0.68), Basis(), OXBLOOD * 0.7,
			[Vector3(side, 0, 0), Vector3.DOWN])
	if under:
		# The capital: stepped blocks, the gilt worn.
		_box(b, Vector3(side * (r.hi.x - 0.15), top + 0.08, z), Vector3(0.3, 0.16, 0.74), Basis(), GILT * 0.7,
				[Vector3(side, 0, 0)])
		_box(b, Vector3(side * (r.hi.x - 0.19), top + 0.24, z), Vector3(0.38, 0.16, 0.84), Basis(), c,
				[Vector3(side, 0, 0)])
	else:
		# Broken off: a jagged top and its pieces on the floor below.
		_box(b, Vector3(x, top + 0.06, z + 0.1), Vector3(0.2, 0.14, 0.32), Basis(Vector3.BACK, 0.4), c,
				[Vector3(side, 0, 0)])


## The dado rail along each side wall (a moulded timber rail at 1.25 m over the floor, broken where the plaster fell).
static func _dado(r: Ruin, side: float) -> void:
	var z := PROS_Z + 0.05
	var piece: Array[Vector3] = []
	var outs: Array[Vector3] = []
	var x := side * r.hi.x
	var n := Vector3(-side, 0, 0)
	while z < r.hi.z - 0.05:
		var fl := floor_at(r, z)
		var keep := _wall_plaster(r, side, z, fl + 1.26) > -0.05 and not (side < 0.0 and absf(z + 7.45) < 0.75)
		if keep:
			piece.append(Vector3(x, fl + 1.2, z))
			outs.append(n)
		if (not keep or z + 0.25 >= r.hi.z - 0.05) and piece.size() > 1:
			_sweep(r.wood, piece, outs, Vector3.UP, [Vector2(0.0, 0.0), Vector2(0.035, 0.005), Vector2(0.045, 0.04),
					Vector2(0.03, 0.06), Vector2(0.0, 0.07)], [TIMBER * 0.6])
			piece = []
			outs = []
		elif not keep:
			piece = []
			outs = []
		z += 0.25


## The cornice under the ceiling along a side wall: a cove with beads, gilt on one; it breaks off at the ceiling's
## edge.
static func _cornice_side(r: Ruin, side: float) -> void:
	var path: Array[Vector3] = []
	var outs: Array[Vector3] = []
	var end := edge_z(side * 8.0) - 0.15
	var z := PROS_Z + 0.02
	while z < end:
		path.append(Vector3(side * r.hi.x, CEIL, z))
		outs.append(Vector3(-side, 0, 0))
		z += 0.5
	path.append(Vector3(side * r.hi.x, CEIL, end))
	outs.append(Vector3(-side, 0, 0))
	_sweep(r.plaster, path, outs, Vector3.UP, _cornice_profile(), _cornice_colours())


static func _cornice_profile() -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(0.0, -0.62), Vector2(0.05, -0.62), Vector2(0.05, -0.56), Vector2(0.08, -0.54),
			Vector2(0.08, -0.5), Vector2(0.11, -0.48)]
	for k in 7:
		var a := PI * 0.5 * k / 6.0
		out.append(Vector2(0.11 + 0.36 * (1.0 - cos(a)), -0.48 + 0.36 * sin(a)))
	out.append(Vector2(0.5, -0.1))
	out.append(Vector2(0.56, -0.08))
	out.append(Vector2(0.56, 0.0))
	return out


static func _cornice_colours() -> Array[Color]:
	var c := CREAM * 0.85
	return [c, c, GILT * 0.8, GILT * 0.7, c, c, c, c, c, c, c, c, c, GILT * 0.6, c, c]


## The rear wall: brick to the broken gable, plaster below, the booth's ports, a doorway at the left. Its decay as the
## side walls' under the open roof (the second pass, 2026-11-08: "plain and dark"): plaster fallen in sheets from the
## top where the rain runs down, rising damp and a tide mark at the foot, brown blooms, green runs, soot over the
## ports where the lamps' heat came out.
static func _rear_wall(r: Ruin) -> void:
	var z := r.hi.z
	var origin := Vector3(0, 0, z)
	var n := Vector3.FORWARD
	var walk := floor_at(r, z - 0.1)
	var bcol := func(a: float, v: float) -> Color:
		var c := BRICK * (0.85 + 0.25 * _n(a * 0.7, v * 0.7, 61))
		c = c.lerp(c * 0.5, 1.0 - smoothstep(0.0, 1.2, v - walk))
		var streak := maxf(0.0, _n(a * 2.4, 4.0, 63)) * smoothstep(4.0, 9.0, v)
		c = c.lerp(Color(0.07, 0.09, 0.04), clampf(streak, 0.0, 0.7))
		return c * _hole_shade(_rear_plaster(r, a, v))
	var bottom := func(_a: float) -> float: return walk - 0.05
	var top := func(a: float) -> float: return gable_top(a)
	# The rear doorway (x -7.6..-6.4, to 3.15): the brick round it.
	_sheet(r.brick, origin, Vector3.RIGHT, Vector3.UP, n, r.lo.x, -7.6, bottom, top, 0.3, 30, bcol)
	_sheet(r.brick, origin, Vector3.RIGHT, Vector3.UP, n, -7.6, -6.4, func(_a: float) -> float: return walk + 2.25,
			top, 0.4, 12, bcol)
	_sheet(r.brick, origin, Vector3.RIGHT, Vector3.UP, n, -6.4, r.hi.x, bottom, top, 0.3, 30, bcol)
	var mask := func(a: float, v: float) -> float: return _rear_plaster(r, a, v)
	var pcol := func(a: float, v: float) -> Color: return _rear_colour(r, a, v)
	_masked(r.plaster, origin, Vector3.RIGHT, Vector3.UP, n, r.lo.x, r.hi.x, walk - 0.1, 7.2, CELL, mask, pcol,
			PLASTER, PLASTER, true, Color(PLASTER_BREAK, 0.75))
	# The dado rail across it, broken where the plaster fell, and round the doorway.
	var piece: Array[Vector3] = []
	var outs: Array[Vector3] = []
	var x := r.hi.x - 0.05
	while x > r.lo.x + 0.05:
		var keep := _rear_plaster(r, x, walk + 1.26) > -0.05 and not (x > -7.75 and x < -6.25)
		if keep:
			piece.append(Vector3(x, walk + 1.2, z))
			outs.append(n)
		if (not keep or x - 0.25 <= r.lo.x + 0.05) and piece.size() > 1:
			_sweep(r.wood, piece, outs, Vector3.UP, [Vector2(0.0, 0.0), Vector2(0.035, 0.005), Vector2(0.045, 0.04),
					Vector2(0.03, 0.06), Vector2(0.0, 0.07)], [TIMBER * 0.6])
			piece = []
			outs = []
		elif not keep:
			piece = []
			outs = []
		x -= 0.25
	_clock(r, Vector3(-7.0, walk + 2.85, z))


## The rear wall's plaster mask: more fallen high up where the rain ran down from the broken gable, at the foot
## where the damp rose; none round the doorway and the ports (their surrounds are their own).
static func _rear_plaster(r: Ruin, a: float, v: float) -> float:
	var walk := floor_at(r, r.hi.z - 0.1)
	var m := 0.42 - 0.95 * maxf(0.0, _n(a * 0.42, v * 0.42 + 9.0, 65))
	m -= 0.55 * maxf(0.0, _n(a * 1.3, v * 1.3, 67)) * 1.3
	m -= 0.5 * smoothstep(-0.2, 0.5, _n(a * 0.6 + 3.0, v * 0.35, 69)) * smoothstep(3.0, 6.0, v)
	m -= 0.6 * (1.0 - smoothstep(0.15, 0.7, v - walk)) * (0.5 + 0.5 * _n(a * 1.7, 1.0, 47))
	m = minf(m, 6.3 + 0.6 * _n(a * 0.5, 3.0, 69) - v)
	m = minf(m, v - walk + 0.02)
	var dz := maxf(absf(a + 7.0) - 0.68, 0.0)
	var dy := maxf(v - walk - 2.33, 0.0)
	m = minf(m, Vector2(dz, dy).length() - 0.08)
	for px: float in [-0.9, 0.0, 0.9]:
		m = minf(m, maxf(absf(a - px) - 0.36, absf(v - 3.2) - 0.31))
	return m


static func _rear_colour(r: Ruin, a: float, v: float) -> Color:
	var walk := floor_at(r, r.hi.z - 0.1)
	var h := v - walk
	var c := CREAM if h > 1.3 else OXBLOOD
	if h > 1.22 and h < 1.3:
		c = GILT * 0.6
	c = c * (0.82 + 0.3 * _n(a * 0.9, v * 0.9, 71))
	var tide := 0.9 + 0.15 * _n(a * 0.5, 2.0, 53)
	if h < tide:
		c *= 0.62
	elif h < tide + 0.07:
		c = c.lerp(Color(0.36, 0.33, 0.26), 0.55)
	var bloom := maxf(0.0, _n(a * 0.35, v * 0.35, 75) - 0.2)
	c = c.lerp(c * Color(0.55, 0.45, 0.32), clampf(bloom * 1.5, 0.0, 0.7))
	var streak := maxf(0.0, _n(a * 3.1, 19.0, 73)) * smoothstep(2.5, 6.4, v)
	c = c.lerp(DAMP_GREEN, clampf(streak * 1.4 + 0.1, 0.0, 0.8))
	# Soot over each port (the lamp's heat came out of it) and rust run down from its shutter's runners.
	for px: float in [-0.9, 0.0, 0.9]:
		var soot := 1.0 - smoothstep(0.15, 0.55, Vector2((a - px) * 1.2, (v - 3.62) * 0.8).length())
		c = c.lerp(Color(0.02, 0.018, 0.016), soot * 0.75)
		for s: float in [-1.0, 1.0]:
			var run := (1.0 - smoothstep(0.015, 0.05, absf(a - px - s * 0.3))) * smoothstep(1.6, 2.85, v) \
					* (1.0 - smoothstep(2.85, 2.95, v))
			c = c.lerp(Color(0.12, 0.05, 0.02), run * 0.6)
	return c * 0.88


## A stopped clock over the rear door: a brass bezel, its glass gone, a pale dial with the hours as bars (no
## numerals), its hands stopped at twenty to four.
static func _clock(r: Ruin, at: Vector3) -> void:
	var rad := 0.27
	var corners: Array = []
	for k in 24:
		var a := TAU * k / 24.0
		corners.append(at + Vector3(cos(a) * rad, sin(a) * rad, -0.045))
	var keep := r.plaster.colour
	r.plaster.colour = CEILING_WHITE * 0.8
	r.plaster.face(corners, Vector3.FORWARD)
	r.plaster.colour = keep
	var b := r.brass
	for k in 24:
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		var p0 := at + Vector3(cos(a0), sin(a0), 0) * (rad + 0.02)
		var p1 := at + Vector3(cos(a1), sin(a1), 0) * (rad + 0.02)
		_beam(b, p0 + Vector3(0, 0, -0.05), p1 + Vector3(0, 0, -0.05), 0.05, 0.04, _lit(GILT * 0.8, p0),
				Vector3.BACK)
	for k in 12:
		var a := TAU * k / 12.0
		var d := Vector3(cos(a), sin(a), 0)
		_beam(r.wood, at + d * (rad - 0.07) + Vector3(0, 0, -0.05), at + d * (rad - 0.025) + Vector3(0, 0, -0.05),
				0.018 if k % 3 == 0 else 0.009, 0.004, VOID * 3.0, Vector3.BACK)
	# Twenty to four: the hour hand past three, the minute hand at eight.
	var hour := deg_to_rad(90.0 - (3.0 + 40.0 / 60.0) * 30.0)
	var minute := deg_to_rad(90.0 - 40.0 * 6.0)
	_beam(r.wood, at + Vector3(0, 0, -0.055), at + Vector3(cos(hour), sin(hour), 0) * 0.15 + Vector3(0, 0, -0.055),
			0.02, 0.005, VOID * 3.0, Vector3.BACK)
	_beam(r.wood, at + Vector3(0, 0, -0.06), at + Vector3(cos(minute), sin(minute), 0) * 0.22
			+ Vector3(0, 0, -0.06), 0.014, 0.005, VOID * 3.0, Vector3.BACK)


## The proscenium: a plaster wall across the hall with the arched opening, an architrave of steps and beads in gilt
## round it, the organ chambers' grilles either side, a cartouche and swags over the arch, the cornice along its top.
static func _proscenium(r: Ruin) -> void:
	var origin := Vector3(0, 0, PROS_Z - PLASTER)
	var n := Vector3.BACK
	var opening := func(a: float, v: float) -> float: return _pros_holes(a, v)
	var bottom := r.stage_top - 0.02
	var bcol := func(a: float, v: float) -> Color:
		return BRICK * (0.7 + 0.2 * _n(a * 0.8, v * 0.8, 81)) * _hole_shade(_pros_plaster(r, a, v))
	_masked(r.brick, origin, Vector3.RIGHT, Vector3.UP, n, r.lo.x, r.hi.x, bottom, CEIL + 0.02, 0.25, opening, bcol,
			0.0, 0.0)
	var mask := func(a: float, v: float) -> float: return _pros_plaster(r, a, v)
	var pcol := func(a: float, v: float) -> Color:
		var c := CREAM * (0.85 + 0.25 * _n(a * 0.8, v * 0.8, 87))
		if v < r.stage_top + 1.0:
			c = OXBLOOD * (0.9 + 0.2 * _n(a, v, 89))
		var stain := maxf(0.0, _n(a * 0.4, v * 0.25 + 40.0, 91) - 0.1)
		c = c.lerp(c * Color(0.5, 0.42, 0.3), clampf(stain * 1.6, 0.0, 0.75))
		# Water run down from the cornice.
		var runs := maxf(0.0, _n(a * 2.8, 30.0, 93)) * smoothstep(3.0, 7.4, v)
		return c.lerp(c * Color(0.45, 0.4, 0.33), clampf(runs * 1.3, 0.0, 0.6))
	_masked(r.plaster, origin, Vector3.RIGHT, Vector3.UP, n, r.lo.x, r.hi.x, bottom, CEIL + 0.02, CELL, mask, pcol,
			PLASTER, PLASTER, true, Color(PLASTER_BREAK, 0.75))
	_architrave(r)
	_reveal(r)
	for s: float in [-1.0, 1.0]:
		_grille(r, s)
	_cartouche(r)
	# The cornice along its top, under the ceiling.
	var path: Array[Vector3] = []
	var outs: Array[Vector3] = []
	var x := r.lo.x
	while x <= r.hi.x + 0.01:
		path.append(Vector3(x, CEIL, PROS_Z))
		outs.append(Vector3.BACK)
		x += 0.5
	_sweep(r.plaster, path, outs, Vector3.UP, _cornice_profile(), _cornice_colours())


## The proscenium's plaster mask: on where positive, fallen where negative.
static func _pros_plaster(_r: Ruin, a: float, v: float) -> float:
	var m := _pros_holes(a, v) - 0.02
	var loss := maxf(0.0, _n(a * 0.5, v * 0.5 + 20.0, 83) - 0.25) * 1.2
	loss += maxf(0.0, _n(a * 1.6, v * 1.6, 85) - 0.45)
	# More fallen towards the left, where the curtain hangs torn and the rain blew in.
	loss *= 0.6 + 0.5 * smoothstep(2.0, -6.0, a)
	return minf(m, 0.4 - loss)


## Signed distance outside the opening and the grilles' openings (negative inside one).
static func _pros_holes(x: float, y: float) -> float:
	var d := _opening_sdf(x, y)
	for s: float in [-1.0, 1.0]:
		var gx := x - s * GRILLE_X
		var g: float
		if y < GRILLE_Y1:
			g = maxf(absf(gx) - GRILLE_W * 0.5, GRILLE_Y0 - y)
		else:
			g = Vector2(gx, y - GRILLE_Y1).length() - GRILLE_W * 0.5
		d = minf(d, g)
	return d


## Signed distance (metres, in the proscenium's plane: x, y) outside the opening: negative inside it.
static func _opening_sdf(x: float, y: float) -> float:
	# A segmental arch: a circle through the springing points and the crown.
	var half := OPEN_HALF
	var rise := OPEN_CROWN - OPEN_SPRING
	var rad := (half * half + rise * rise) / (2.0 * rise)
	var cy := OPEN_CROWN - rad
	var inside_x := absf(x) - half
	var d: float
	if y < OPEN_SPRING:
		d = inside_x
	else:
		d = maxf(Vector2(x, y - cy).length() - rad, inside_x)
	return d


## The opening's outline from the left foot round the arch to the right foot (points in x, y).
static func _opening_outline(r: Ruin, steps := 24) -> Array[Vector2]:
	var half := OPEN_HALF
	var rise := OPEN_CROWN - OPEN_SPRING
	var rad := (half * half + rise * rise) / (2.0 * rise)
	var cy := OPEN_CROWN - rad
	var a0 := atan2(OPEN_SPRING - cy, -half)
	var a1 := atan2(OPEN_SPRING - cy, half)
	var out: Array[Vector2] = [Vector2(-half, r.stage_top)]
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		out.append(Vector2(cos(a) * rad, cy + sin(a) * rad))
	out.append(Vector2(half, r.stage_top))
	return out


## The architrave round the opening: steps out from the wall and beads, the outer bead and the inner gilt.
static func _architrave(r: Ruin) -> void:
	var outline := _opening_outline(r)
	var path: Array[Vector3] = []
	var outs: Array[Vector3] = []
	for i in outline.size():
		var q := outline[i]
		var t := (outline[mini(i + 1, outline.size() - 1)] - outline[maxi(i - 1, 0)]).normalized()
		# Outward in the wall's plane: away from the opening.
		var o := Vector2(-t.y, t.x)
		path.append(Vector3(q.x, q.y, PROS_Z))
		outs.append(Vector3(o.x, o.y, 0.0))
	# Profile: out (in the wall's plane, away from the opening) and up (towards the room: +z).
	var prof: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.0, 0.07), Vector2(0.04, 0.1), Vector2(0.08, 0.07),
			Vector2(0.12, 0.07), Vector2(0.12, 0.13), Vector2(0.3, 0.13), Vector2(0.32, 0.17), Vector2(0.36, 0.18),
			Vector2(0.4, 0.15), Vector2(0.42, 0.09), Vector2(0.5, 0.09), Vector2(0.5, 0.0)]
	var c := CREAM * 0.95
	var g := GILT
	_sweep(r.plaster, path, outs, Vector3.BACK, prof, [c, g, g, c, c, c, g * 0.9, g, g, c, c, c])


## The opening's reveal (the wall's thickness round it) and its soffit.
static func _reveal(r: Ruin) -> void:
	var outline := _opening_outline(r)
	var la := PackedVector3Array()
	var lb := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in outline.size():
		var q := outline[i]
		var t := (outline[mini(i + 1, outline.size() - 1)] - outline[maxi(i - 1, 0)]).normalized()
		var o := Vector2(t.y, -t.x)
		la.append(Vector3(q.x, q.y, PROS_Z))
		lb.append(Vector3(q.x, q.y, PROS_Z - PROS_T))
		ns.append(Vector3(o.x, o.y, 0.0))
	var keep := r.plaster.colour
	r.plaster.colour = CREAM * 0.55
	r.plaster.strip(la, lb, ns)
	r.plaster.colour = keep


## An organ chamber's grille beside the opening: a moulded frame with a round head, a lattice of plaster lozenges,
## the dark chamber behind.
static func _grille(r: Ruin, s: float) -> void:
	var cx := s * GRILLE_X
	var w := GRILLE_W
	var y0 := GRILLE_Y0
	var y1 := GRILLE_Y1
	var z := PROS_Z
	# The chamber: a dark recess.
	_box(r.wood, Vector3(cx, (y0 + y1 + 0.85) * 0.5, z - 0.32), Vector3(w, y1 + 0.85 - y0, 0.04), Basis(), VOID)
	for k: float in [-1.0, 1.0]:
		_box(r.plaster, Vector3(cx + k * w * 0.5, (y0 + y1 + 0.85) * 0.5, z - 0.15), Vector3(0.02, y1 + 0.85 - y0, 0.3),
				Basis(), CREAM * 0.35)
	# The lattice: bars at 45 degrees, clipped to the frame (a round head over y1).
	var head := w * 0.5
	var pitch := 0.32
	for dir: float in [-1.0, 1.0]:
		var k := -8
		while k <= 8:
			var c0 := k * pitch
			var pts: Array[Vector3] = []
			var t := -6.0
			while t <= 6.0:
				var lx := c0 + t * 0.7071
				var ly := t * 0.7071 * dir
				var px := cx + lx
				var py := (y0 + y1) * 0.5 + ly
				var inside := absf(lx) < w * 0.5 - 0.03 and py > y0 + 0.03 and (py < y1 or Vector2(lx, py - y1).length()
						< head - 0.03)
				if inside:
					pts.append(Vector3(px, py, z - 0.12))
				elif pts.size() > 0:
					break
				t += 0.05
			if pts.size() > 1:
				var col := CREAM * (0.6 + 0.15 * _n(c0, dir, 95))
				# A few bars broken out of the left grille.
				if not (s < 0.0 and absf(k - 1) < 1 and dir > 0.0):
					_beam(r.plaster, pts[0], pts[-1], 0.045, 0.06, col, Vector3.BACK)
			k += 1
	# The frame: a moulding round it, the round head.
	var path: Array[Vector3] = []
	var outs: Array[Vector3] = []
	path.append(Vector3(cx - w * 0.5, y0, z))
	outs.append(Vector3.LEFT)
	path.append(Vector3(cx - w * 0.5, y1, z))
	outs.append(Vector3.LEFT)
	for k in 13:
		var a := PI - PI * k / 12.0
		path.append(Vector3(cx + cos(a) * head, y1 + sin(a) * head, z))
		outs.append(Vector3(cos(a), sin(a), 0))
	path.append(Vector3(cx + w * 0.5, y0, z))
	outs.append(Vector3.RIGHT)
	var prof: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.0, 0.06), Vector2(0.05, 0.09), Vector2(0.12, 0.09),
			Vector2(0.16, 0.05), Vector2(0.18, 0.0)]
	_sweep(r.plaster, path, outs, Vector3.BACK, prof, [CREAM, GILT, GILT * 0.8, CREAM * 0.9, CREAM * 0.9])
	# The sill under it.
	_box(r.plaster, Vector3(cx, y0 - 0.06, z + 0.07), Vector3(w + 0.4, 0.12, 0.14), Basis(), CREAM * 0.8)


## Over the arch: an oval cartouche (blank: its painted name long gone) in a gilt ring, swags of fruit and leaves to
## either side.
static func _cartouche(r: Ruin) -> void:
	var c := Vector3(0.0, OPEN_CROWN + 0.62, PROS_Z)
	var keep := r.plaster.colour
	# The oval's face, raised, and its ring (lathe profiles scaled into an oval).
	var b := r.plaster
	var basis := Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 1.35))
	b.colour = GILT * 0.85
	Shapes.lathe(b, [Vector2(0.42, 0.0), Vector2(0.42, 0.06), Vector2(0.38, 0.1), Vector2(0.34, 0.1)], c, 24,
			Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 1.35)))
	b.colour = CREAM * 0.7
	Shapes.lathe(b, [Vector2(0.34, 0.08), Vector2(0.2, 0.1), Vector2(0.0, 0.11)], c, 24, basis)
	# The swags: a sagging garland of lumps (fruit and leaves) from the cartouche to each side, gilt worn to plaster.
	for s: float in [-1.0, 1.0]:
		var a := c + Vector3(s * 0.42, 0.12, 0.05)
		var e := Vector3(s * 3.3, OPEN_CROWN + 0.5, PROS_Z + 0.05)
		for k in 15:
			var t := k / 14.0
			var p := a.lerp(e, t) + Vector3(0, -0.45 * sin(t * PI), 0.05)
			var rad := 0.09 + 0.05 * sin(t * PI)
			var col := GILT.lerp(CREAM * 0.8, clampf(0.5 + 0.6 * _n(t * 6.0, s, 97), 0.0, 1.0))
			b.colour = col
			Shapes.lathe(b, [Vector2(0.0, -rad), Vector2(rad * 0.8, -rad * 0.6), Vector2(rad, 0.0),
					Vector2(rad * 0.8, rad * 0.6), Vector2(0.0, rad)], p, 6, Basis(Vector3.BACK, t * 3.0))
		# A ribbon's end hanging at the far end.
		b.colour = GILT * 0.7
		_box(b, e + Vector3(0, -0.35, 0.02), Vector3(0.08, 0.6, 0.03), Basis(Vector3.BACK, s * 0.15), GILT * 0.7)
	b.colour = keep


## The stage: boards on a dark front, a bullnosed edge, moss along it (ruin_growth), the boards behind the arch.
static func _stage(r: Ruin) -> void:
	var y := r.stage_top
	var b := r.wood
	# The boards from the front wall to the stage's edge, across the whole hall (the proscenium hides the sides).
	_boards(r, Rect2(r.lo.x, r.lo.z, r.hi.x - r.lo.x, r.stage_front - r.lo.z), y, [], 0.12)
	# The front: a panelled riser, the nosing.
	var keep := b.colour
	b.colour = TIMBER * 0.45
	b.face([Vector3(r.lo.x, r.lo.y, r.stage_front), Vector3(r.hi.x, r.lo.y, r.stage_front), Vector3(r.hi.x, y - 0.04,
			r.stage_front), Vector3(r.lo.x, y - 0.04, r.stage_front)], Vector3.BACK)
	for k in 17:
		var x := lerpf(r.lo.x + 0.5, r.hi.x - 0.5, k / 16.0)
		_box(b, Vector3(x, (r.lo.y + y) * 0.5 - 0.02, r.stage_front + 0.02), Vector3(0.07, y - r.lo.y - 0.12, 0.04),
				Basis(), TIMBER * 0.35)
	_box(b, Vector3(0, y - 0.025, r.stage_front + 0.025), Vector3(r.hi.x - r.lo.x, 0.05, 0.07), Basis(), TIMBER * 0.6)
	b.colour = keep
	# The front wall behind the screen: dark brick.
	r.brick.colour = BRICK * 0.05
	r.brick.face([Vector3(r.lo.x, y, r.lo.z), Vector3(r.hi.x, y, r.lo.z), Vector3(r.hi.x, CEIL, r.lo.z),
			Vector3(r.lo.x, CEIL, r.lo.z)], Vector3.BACK)
	r.brick.colour = Color.WHITE


## Floor boards over a rectangle (x, z) at height y, running across the hall (along x), each its own shade and a few
## millimetres up or down; `holes` [[centre, half size]] rotted through (the boards end raggedly there). One chart.
static func _boards(r: Ruin, rect: Rect2, y: float, holes: Array, width: float, end_x := Callable()) -> void:
	var b := r.wood
	b._begin_chart()
	var keep := b.colour
	var z := rect.position.y
	var row := 0
	while z < rect.end.y - 0.001:
		var z1 := minf(z + width - 0.006, rect.end.y)
		var zm := (z + z1) * 0.5
		var x0 := rect.position.x
		var x1 := rect.end.x
		if end_x.is_valid():
			x1 = minf(x1, float(end_x.call(zm, 1.0)))
			x0 = maxf(x0, float(end_x.call(zm, -1.0)))
		# Cut where a hole crosses this board.
		var spans: Array[Vector2] = [Vector2(x0, x1)]
		for h: Array in holes:
			var hc: Vector2 = h[0]
			var hs: Vector2 = h[1]
			var dz := (zm - hc.y) / hs.y
			if absf(dz) >= 1.0:
				continue
			var hw := hs.x * sqrt(1.0 - dz * dz)
			var j0 := hc.x - hw + r.rng.randf_range(-0.15, 0.1)
			var j1 := hc.x + hw + r.rng.randf_range(-0.1, 0.15)
			var next: Array[Vector2] = []
			for sp: Vector2 in spans:
				if j1 <= sp.x or j0 >= sp.y:
					next.append(sp)
					continue
				if j0 > sp.x + 0.05:
					next.append(Vector2(sp.x, j0))
				if j1 < sp.y - 0.05:
					next.append(Vector2(j1, sp.y))
			spans = next
		var shade := 0.7 + 0.45 * r.rng.randf()
		var lift := r.rng.randf_range(-0.004, 0.004)
		for sp: Vector2 in spans:
			# A board is a few metres long: joints along it, each piece its own shade.
			var x := sp.x
			while x < sp.y - 0.001:
				var xe := minf(x + r.rng.randf_range(1.6, 3.6), sp.y)
				var weather := 1.0 - 0.35 * moon_light(Vector3((x + xe) * 0.5, y, zm))
				var c := BOARD * shade * (0.85 + 0.3 * r.rng.randf())
				c = c.lerp(Color(0.24, 0.24, 0.23), 0.3 * (1.0 - weather) * 2.0)
				b.colour = c
				var yy := y + lift
				# In segments of about 0.3 m: the Moon's light rides in the vertices (moon_alpha()).
				var segs := maxi(ceili((xe - 0.004 - x) / 0.3), 1)
				var base: int = b._current.verts.size()
				for k in segs + 1:
					var xx := lerpf(x, xe - 0.004, float(k) / segs)
					b._vertex(Vector3(xx, yy, z), Vector3.UP, Vector2(xx, z))
					b._vertex(Vector3(xx, yy, z1), Vector3.UP, Vector2(xx, z1))
				for k in segs:
					var i0 := base + k * 2
					var p0 := Vector3(lerpf(x, xe, float(k) / segs), yy, z)
					b._triangle(i0, i0 + 2, i0 + 3, p0, p0 + Vector3(0.3, 0, 0), p0 + Vector3(0.3, 0, z1 - z), Vector3.UP)
					b._triangle(i0, i0 + 3, i0 + 1, p0, p0 + Vector3(0.3, 0, z1 - z), p0 + Vector3(0, 0, z1 - z),
							Vector3.UP)
				x = xe
		z += width
		row += 1
	b.colour = keep
	b._end_chart()


## The screen: its sheet on a timber frame behind the picture, black masking round the picture (the top's right end
## come down at a slant), stains on the sheet beyond the masking, never on the picture.
static func _screen(r: Ruin) -> void:
	var doc: Variant = r.kit.room.get("doc")
	var c := Vector3(0, 2.4, -9.55)
	var size := Vector2(6.4, 3.6)
	if doc is Dictionary and (doc as Dictionary).get("screen") is Dictionary:
		var cc: Array = doc["screen"]["center"]
		c = Vector3(float(cc[0]), float(cc[1]), float(cc[2]))
		var ss: Array = doc["screen"]["size"]
		size = Vector2(float(ss[0]), float(ss[1]))
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	# The sheet, 0.35 m past the picture each way, behind it; stains and tide marks out at its edges.
	var sheet_z := c.z - 0.07
	var origin := Vector3(c.x, c.y, sheet_z)
	var col := func(a: float, v: float) -> Color:
		var edge := maxf(absf(a) - hw, absf(v) - hh)
		var s := SHEET * (0.9 + 0.15 * _n(a * 1.5, v * 1.5, 101))
		var stain := clampf(smoothstep(-0.05, 0.3, edge) * (0.6 + 0.6 * _n(a * 0.9, v * 0.9, 103)), 0.0, 1.0)
		s = s.lerp(Color(0.2, 0.15, 0.08), stain * 0.8)
		# A tide line where water stood.
		if absf(edge - 0.18 - 0.06 * _n(a * 2.0, v * 2.0, 105)) < 0.015:
			s *= 0.6
		return s
	var mask := func(a: float, v: float) -> float:
		var m := minf(hw + 0.35 - absf(a), hh + 0.35 - absf(v))
		# Torn at the top right: a flap gone.
		m = minf(m, Vector2(a - hw - 0.35, v - hh - 0.35).length() - 0.45 + 0.08 * _n(a * 5.0, v * 5.0, 107))
		return m
	_masked(r.plaster, origin, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -hw - 0.4, hw + 0.4, -hh - 0.4, hh + 0.4,
			0.1, mask, col, 0.0, 0.0)
	# The frame behind its edges and the lacing (dark cord) to it.
	for s: float in [-1.0, 1.0]:
		_beam(r.wood, Vector3(c.x + s * (hw + 0.5), r.stage_top, sheet_z - 0.05),
				Vector3(c.x + s * (hw + 0.5), c.y + hh + 0.55, sheet_z - 0.05), 0.1, 0.1, TIMBER * 0.5, Vector3.BACK)
		for k in 11:
			var y := c.y - hh - 0.25 + k * (size.y + 0.5) / 10.0
			_beam(r.wood, Vector3(c.x + s * (hw + 0.36), y, sheet_z - 0.01), Vector3(c.x + s * (hw + 0.47), y + 0.04,
					sheet_z - 0.04), 0.012, 0.012, VOID * 4.0, Vector3.BACK)
	_beam(r.wood, Vector3(c.x - hw - 0.55, c.y + hh + 0.5, sheet_z - 0.05), Vector3(c.x + hw + 0.55, c.y + hh + 0.5,
			sheet_z - 0.05), 0.1, 0.1, TIMBER * 0.5, Vector3.BACK)
	# The masking: black velvet, 0.25 m round the picture, 0.03 m behind it; the top's right end has come down.
	var mz := c.z - 0.03
	var cl := r.cloth
	var keep := cl.colour
	cl.colour = MASKING
	cl.face([Vector3(c.x - hw - 0.27, c.y - hh - 0.15, mz), Vector3(c.x - hw, c.y - hh - 0.15, mz),
			Vector3(c.x - hw, c.y + hh + 0.27, mz), Vector3(c.x - hw - 0.27, c.y + hh + 0.27, mz)], Vector3.BACK)
	cl.face([Vector3(c.x + hw, c.y - hh - 0.15, mz), Vector3(c.x + hw + 0.27, c.y - hh - 0.15, mz),
			Vector3(c.x + hw + 0.27, c.y + hh - 0.1, mz), Vector3(c.x + hw, c.y + hh - 0.1, mz)], Vector3.BACK)
	cl.face([Vector3(c.x - hw, c.y - hh - 0.15, mz), Vector3(c.x + hw, c.y - hh - 0.15, mz),
			Vector3(c.x + hw, c.y - hh, mz), Vector3(c.x - hw, c.y - hh, mz)], Vector3.BACK)
	# The top: whole over the left two thirds, its right end hanging down past the picture's corner, behind it.
	cl.face([Vector3(c.x - hw - 0.27, c.y + hh, mz), Vector3(c.x + hw * 0.35, c.y + hh, mz),
			Vector3(c.x + hw * 0.35, c.y + hh + 0.27, mz), Vector3(c.x - hw - 0.27, c.y + hh + 0.27, mz)],
			Vector3.BACK)
	var pivot := Vector3(c.x + hw * 0.35, c.y + hh + 0.27, mz - 0.01)
	var drop := Basis(Vector3.BACK, -0.32)
	var corners: Array = []
	for q: Vector3 in [Vector3(0, -0.27, 0), Vector3(hw * 0.68 + 0.27, -0.27, 0), Vector3(hw * 0.68 + 0.27, 0, 0),
			Vector3(0, 0, 0)]:
		corners.append(pivot + drop * q)
	cl.face(corners, Vector3.BACK)
	cl.colour = keep


## The curtains: at the left the house tabs hang in tatters from their rail behind the arch, mould at their hems; at
## the right they came down and lie in a heap at the stage's side; a tattered valance across the top.
static func _curtains(r: Ruin) -> void:
	var z := PROS_Z - PROS_T - 0.1
	var top := OPEN_CROWN - 0.15
	# The rail.
	_beam(r.wood, Vector3(-OPEN_HALF - 0.6, top + 0.05, z), Vector3(OPEN_HALF + 0.6, top + 0.05, z), 0.05, 0.05,
			VOID * 6.0)
	var cl := r.cloth
	# The left: strips (tatters) from the rail, each its own length, folded.
	var x := -OPEN_HALF - 0.4
	var k := 0
	while x < -3.3:
		var w := r.rng.randf_range(0.18, 0.36)
		var x1 := minf(x + w, -3.3)
		var length := r.rng.randf_range(2.2, top - r.stage_top + 0.1)
		if k == 1 or k == 4:
			length = top - r.stage_top + 0.25
		_tatter(r, x, x1, z + r.rng.randf_range(-0.05, 0.05), top, length, k)
		x = maxf(x1, x + 0.1) + r.rng.randf_range(-0.02, 0.05)
		k += 1
	# The valance: short tatters across the top, longer at the left where it sags.
	x = -OPEN_HALF - 0.4
	while x < OPEN_HALF + 0.4:
		var w := r.rng.randf_range(0.2, 0.42)
		var x1 := minf(x + w, OPEN_HALF + 0.4)
		var length := r.rng.randf_range(0.35, 0.7) + 0.35 * smoothstep(-1.0, -4.5, x)
		_tatter(r, x, x1, z + 0.15, top + 0.2, length, k + 40)
		x = maxf(x1 - 0.01, x + 0.1)
		k += 1
	# The right: a strip still up at the far side, the rest in a heap on the stage.
	_tatter(r, 4.2, 4.65, z, top, top - r.stage_top + 0.1, 77)
	var heap_c := Vector3(4.65, r.stage_top, z + 0.25)
	for i in 9:
		var a := r.rng.randf_range(-0.5, 0.5)
		var len := r.rng.randf_range(0.6, 1.3)
		var p := heap_c + Vector3(r.rng.randf_range(-0.45, 0.6), 0.0, r.rng.randf_range(-0.2, 0.35))
		var rows: Array = []
		var normals: Array = []
		var colours: Array = []
		for j in 7:
			var t := j / 6.0
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for m in 5:
				var u := m / 4.0
				var along := Vector3(cos(a), 0, sin(a)) * (t - 0.5) * len
				var across := Vector3(-sin(a), 0, cos(a)) * (u - 0.5) * 0.5
				var hgt := 0.05 + 0.22 * sin(u * PI) * (0.6 + 0.4 * sin(t * 7.0 + i)) * (1.0 - 0.6 * absf(t - 0.5))
				hgt *= 1.0 - i * 0.06
				row.append(p + along + across + Vector3(0, hgt, 0))
				nrow.append((Vector3(0, 1, 0) + across.normalized() * cos(u * PI) * 0.8).normalized())
				crow.append(VELVET * (0.6 + 0.5 * u) * (0.85 + 0.2 * _n(t * 3.0, i, 111)))
			rows.append(row)
			normals.append(nrow)
			colours.append(crow)
		cl.sheet(rows, normals, colours, Vector3(cos(a), 0, sin(a)), Vector3(-sin(a), 0, cos(a)))


## One tatter of velvet from x0..x1 at the rail (top), hanging `length`, folded (a few pleats), its hem ragged and
## mouldy.
static func _tatter(r: Ruin, x0: float, x1: float, z: float, top: float, length: float, seed_k: int) -> void:
	var rows: Array = []
	var normals: Array = []
	var colours: Array = []
	var nv := maxi(int(length / 0.3), 2)
	var nu := 4
	var sway := r.rng.randf_range(-0.08, 0.08)
	for j in nv + 1:
		var t := float(j) / nv
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		# Narrower towards a torn end.
		var narrow := 1.0 - 0.55 * smoothstep(0.55, 1.0, t) * (0.5 + 0.5 * sin(seed_k * 1.7))
		var mid := (x0 + x1) * 0.5 + sway * t * t
		for m in nu + 1:
			var u := float(m) / nu
			var x := mid + (u - 0.5) * (x1 - x0) * narrow
			var fold := sin(u * TAU * 1.0 + seed_k) * 0.06
			var y := top - t * length + (0.12 * sin(u * PI + seed_k) * t if t > 0.9 else 0.0)
			row.append(Vector3(x, maxf(y, r.stage_top + 0.01), z + fold))
			nrow.append(Vector3(-cos(u * TAU + seed_k) * 0.5, 0.0, 1.0).normalized())
			var c := VELVET * (0.75 + 0.35 * (0.5 + 0.5 * cos(u * TAU + seed_k)))
			# Faded higher up, mould and damp at the hem.
			c = c.lerp(Color(0.09, 0.08, 0.055), smoothstep(0.55, 1.0, t) * 0.7)
			crow.append(c * (0.85 + 0.25 * _n(u * 3.0 + seed_k, t * 4.0, 113)))
		rows.append(row)
		normals.append(nrow)
		colours.append(crow)
	r.cloth.sheet(rows, normals, colours, Vector3.RIGHT, Vector3.DOWN)
	# Its back, so the strip is not hollow from behind (a stage's dark).
	var back_rows: Array = []
	var back_n: Array = []
	var back_c: Array = []
	for j in rows.size():
		var row: PackedVector3Array = rows[j]
		var rr := PackedVector3Array()
		var nn := PackedVector3Array()
		var cc := PackedColorArray()
		for m in range(row.size() - 1, -1, -1):
			rr.append(row[m] + Vector3(0, 0, -0.01))
			nn.append(Vector3(0, 0, -1))
			cc.append(VELVET * 0.4)
		back_rows.append(rr)
		back_n.append(nn)
		back_c.append(cc)
	r.cloth.sheet(back_rows, back_n, back_c, Vector3.LEFT, Vector3.DOWN)


## The pit: boards from the stage to the front row, rotted through in two places (joists and the dark under them),
## the side aisles' fronts.
static func _pit(r: Ruin) -> void:
	var b := r.wood
	var end_x := func(zm: float, s: float) -> float:
		# The pit runs to the front row's riser (its arc); the side aisles start a little further back.
		if r.L == null:
			return s * r.hi.x
		var rad: float = r.L.row_radius(r.L.rows_front) - r.L.depth * 0.5
		var cz: float = -r.L.radius
		var dz := zm - cz
		if rad * rad - dz * dz <= 0.0:
			return 0.0
		var xr := sqrt(rad * rad - dz * dz) + 0.06
		if zm < riser_z(r, r.L.block_x):
			return s * r.hi.x
		return s * minf(xr, r.hi.x)
	var back := riser_z(r, 0.0) + 0.06
	_boards(r, Rect2(r.lo.x, r.stage_front, r.hi.x - r.lo.x, back - r.stage_front), r.lo.y, r.holes, 0.14, end_x)
	# Under the boards: the joists across (along z) and the dark beneath, seen through the gaps and the holes.
	var keep := b.colour
	b.colour = VOID
	b.face([Vector3(r.lo.x, r.lo.y - 0.3, r.stage_front), Vector3(r.hi.x, r.lo.y - 0.3, r.stage_front),
			Vector3(r.hi.x, r.lo.y - 0.3, back), Vector3(r.lo.x, r.lo.y - 0.3, back)], Vector3.UP)
	b.colour = keep
	for h: Array in r.holes:
		var hc: Vector2 = h[0]
		var hs: Vector2 = h[1]
		var jx := floorf((hc.x - hs.x - 0.3) / 0.45) * 0.45
		while jx < hc.x + hs.x + 0.3:
			_box(b, Vector3(jx, r.lo.y - 0.12, hc.y), Vector3(0.07, 0.18, hs.y * 2.0 + 0.6), Basis(),
					TIMBER * 0.35)
			jx += 0.45
		# Earth and a little water in the dark, a broken board's end hanging into it.
		_box(b, Vector3(hc.x + hs.x * 0.3, r.lo.y - 0.09, hc.y - hs.y * 0.4), Vector3(0.7, 0.025, 0.13),
				Basis(Vector3.BACK, 0.35) * Basis(Vector3.UP, 0.2), BOARD * 0.5)


## The booth's ports in the rear wall: the projector's (its lens lit, the beam comes from it) and two viewing ports,
## dark; frames of timber.
static func _booth(r: Ruin) -> void:
	var z := r.hi.z
	for i in 3:
		var px: float = [-0.9, 0.0, 0.9][i]
		_box(r.wood, Vector3(px, 3.2, z - 0.012), Vector3(0.44, 0.34, 0.01), Basis(), VOID, [Vector3.BACK])
		for s: float in [-1.0, 1.0]:
			_box(r.wood, Vector3(px + s * 0.24, 3.2, z - 0.02), Vector3(0.05, 0.44, 0.06), Basis(), TIMBER * 0.4)
			_box(r.wood, Vector3(px, 3.2 + s * 0.2, z - 0.02), Vector3(0.53, 0.05, 0.06), Basis(), TIMBER * 0.4)
		# A moulded plaster surround with a sill, stained by the soot; chipped on the left port.
		var sur := CREAM * 0.55
		_box(r.plaster, Vector3(px, 3.2 + 0.3, z - 0.05), Vector3(0.72, 0.07, 0.07), Basis(), sur, [Vector3.BACK])
		_box(r.plaster, Vector3(px, 3.2 - 0.29, z - 0.06), Vector3(0.78, 0.06, 0.1), Basis(), sur * 1.1,
				[Vector3.BACK])
		for s: float in [-1.0, 1.0]:
			if i == 0 and s < 0.0:
				_box(r.plaster, Vector3(px - 0.33, 3.33, z - 0.045), Vector3(0.07, 0.3, 0.06), Basis(), sur,
						[Vector3.BACK])
			else:
				_box(r.plaster, Vector3(px + s * 0.33, 3.2, z - 0.045), Vector3(0.07, 0.6, 0.06), Basis(), sur,
						[Vector3.BACK])
		# The fire shutter's runners either side, rusted; the shutter itself: the left port's down to halfway, the
		# right one fallen askew on one runner, the middle one up (the lit lens shows).
		for s: float in [-1.0, 1.0]:
			_box(r.wood, Vector3(px + s * 0.3, 3.45, z - 0.09), Vector3(0.025, 1.1, 0.03), Basis(),
					Color(0.09, 0.045, 0.025))
		var steel := Color(0.07, 0.065, 0.06)
		if i == 0:
			_box(r.wood, Vector3(px, 3.29, z - 0.1), Vector3(0.58, 0.2, 0.012), Basis(), steel)
		elif i == 2:
			_box(r.wood, Vector3(px - 0.04, 3.05, z - 0.13), Vector3(0.58, 0.4, 0.012), Basis(Vector3.BACK, 0.42)
					* Basis(Vector3.RIGHT, 0.12), steel)
		else:
			_box(r.wood, Vector3(px, 3.75, z - 0.1), Vector3(0.58, 0.4, 0.012), Basis(), steel)
	# The lens: a small disc glowing in the dark port.
	var corners: Array = []
	for k in 12:
		var a := TAU * k / 12.0
		corners.append(Vector3(cos(a) * 0.06, 3.2 + sin(a) * 0.06, z - 0.02))
	r.port.face(corners, Vector3.FORWARD)


## The doorways: at the left's front (the deer leaves by it) and at the rear's left (it comes in by it); reveals,
## a door hanging off its hinges, the night's dark beyond, a step outside.
static func _doorways(r: Ruin) -> void:
	# The left front doorway: z -8.05..-6.85, up to 2.0.
	var x := r.lo.x
	var keep := r.brick.colour
	r.brick.colour = BRICK * 0.5
	for zz: float in [-8.05, -6.85]:
		r.brick.face([Vector3(x, r.lo.y, zz), Vector3(x - 0.45, r.lo.y, zz), Vector3(x - 0.45, 2.0, zz),
				Vector3(x, 2.0, zz)], Vector3(0, 0, 1.0 if zz < -7.0 else -1.0))
	r.brick.face([Vector3(x, 2.0, -8.05), Vector3(x - 0.45, 2.0, -8.05), Vector3(x - 0.45, 2.0, -6.85),
			Vector3(x, 2.0, -6.85)], Vector3.DOWN)
	r.brick.colour = keep
	_box(r.wood, Vector3(x - 0.22, 2.05, -7.45), Vector3(0.5, 0.1, 1.5), Basis(), TIMBER * 0.5)
	# Beyond: the ground outside, dark, a wall of night.
	_box(r.wood, Vector3(x - 1.6, r.lo.y - 0.05, -7.45), Vector3(2.4, 0.1, 2.4), Basis(), BOARD * 0.03)
	r.wood.colour = VOID
	r.wood.face([Vector3(x - 2.6, r.lo.y, -9.0), Vector3(x - 2.6, r.lo.y, -5.9), Vector3(x - 2.6, 4.0, -5.9),
			Vector3(x - 2.6, 4.0, -9.0)], Vector3.RIGHT)
	r.wood.colour = Color.WHITE
	# The door: one leaf hanging open on its top hinge, leaning out.
	var leaf := Basis(Vector3.UP, -0.4) * Basis(Vector3.BACK, 0.06)
	_door_leaf(r, Vector3(x - 0.05, r.lo.y + 0.04, -6.9), leaf, 1.15, 1.92)
	# The rear doorway: x -7.6..-6.4 at the rear walkway.
	var z := r.hi.z
	var walk := floor_at(r, z - 0.1)
	r.brick.colour = BRICK * 0.5
	for xx: float in [-7.6, -6.4]:
		r.brick.face([Vector3(xx, walk, z), Vector3(xx, walk, z + 0.45), Vector3(xx, walk + 2.25, z + 0.45),
				Vector3(xx, walk + 2.25, z)], Vector3(1.0 if xx < -7.0 else -1.0, 0, 0))
	r.brick.face([Vector3(-7.6, walk + 2.25, z), Vector3(-6.4, walk + 2.25, z), Vector3(-6.4, walk + 2.25, z + 0.45),
			Vector3(-7.6, walk + 2.25, z + 0.45)], Vector3.DOWN)
	r.brick.colour = keep
	_box(r.wood, Vector3(-7.0, walk + 2.3, z + 0.22), Vector3(1.5, 0.1, 0.5), Basis(), TIMBER * 0.5)
	_box(r.wood, Vector3(-7.0, walk - 0.05, z + 1.4), Vector3(2.6, 0.1, 2.4), Basis(), BOARD * 0.03)
	r.wood.colour = VOID
	r.wood.face([Vector3(-8.6, walk - 0.1, z + 2.6), Vector3(-5.4, walk - 0.1, z + 2.6), Vector3(-5.4, walk + 4.0,
			z + 2.6), Vector3(-8.6, walk + 4.0, z + 2.6)], Vector3.FORWARD)
	r.wood.colour = Color.WHITE
	_door_leaf(r, Vector3(-6.45, walk + 0.03, z + 0.1), Basis(Vector3.UP, 1.25) * Basis(Vector3.FORWARD, 0.04), 1.1,
			2.15)


## A door's leaf (boarded, a rail top and bottom), its hinge side at `at`, turned by `basis`.
static func _door_leaf(r: Ruin, at: Vector3, basis: Basis, w: float, h: float) -> void:
	var b := r.wood
	for k in 6:
		var x := (k + 0.5) * w / 6.0
		_box(b, at + basis * Vector3(-x, h * 0.5 - 0.06 * (k % 2), 0.0), Vector3(w / 6.0 - 0.008, h - 0.12 * (k % 2),
				0.035), basis, TIMBER * (0.5 + 0.12 * (k % 3)))
	for y: float in [0.25, h - 0.3]:
		_box(b, at + basis * Vector3(-w * 0.5, y, -0.03), Vector3(w, 0.12, 0.03), basis, TIMBER * 0.45)


# --- The roof ----------------------------------------------------------------------------------------------------------

## The front half's ceiling: plaster on laths, coffered by cased beams, holes where it fell (the laths and the dark
## above them), water stains, the chandelier's rose broken; it ends at the broken edge.
static func _ceiling(r: Ruin) -> void:
	var origin := Vector3(0, CEIL, 0)
	var mask := func(x: float, z: float) -> float:
		var m := edge_z(x) - z
		m = minf(m, Vector2(x, z).distance_to(HOLE) - HOLE_R - 0.12 * _n(x * 3.0, z * 3.0, 119))
		var hole := maxf(0.0, _n(x * 0.38, z * 0.38 + 50.0, 121) - 0.05) * 1.5
		hole += maxf(0.0, _n(x * 1.1, z * 1.1, 123) - 0.3) * 0.9
		hole *= smoothstep(PROS_Z + 0.4, PROS_Z + 2.0, z)
		return minf(m, 0.3 - hole)
	var col := func(x: float, z: float) -> Color:
		var c := CEILING_WHITE * (0.85 + 0.25 * _n(x * 0.7, z * 0.7, 125))
		# Water stains: brown rings spreading from the edge and round the holes.
		var wet := smoothstep(-2.5, 0.0, z - edge_z(x)) + maxf(0.0, _n(x * 0.3, z * 0.3, 127)) * 0.8
		c = c.lerp(Color(0.2, 0.15, 0.08), clampf(wet * 0.55, 0.0, 0.7))
		var ring := absf(fposmod(wet * 4.0, 1.0) - 0.5)
		if wet > 0.25 and ring < 0.06:
			c *= 0.75
		return c
	_masked(r.plaster, origin, Vector3.RIGHT, Vector3.BACK, Vector3.DOWN, r.lo.x, r.hi.x, PROS_Z, EDGE_Z + 1.2, CELL,
			mask, col, 0.0, 0.03, true, Color(PLASTER_BREAK, 0.6))
	# Laths over the holes and past the edge: strips across (along x) at 3.6 cm, the dark of the roof's void above.
	var lath_y := CEIL + 0.035
	var z := PROS_Z + 0.2
	var keep := r.wood.colour
	r.wood._begin_chart()
	while z < EDGE_Z + 1.4:
		var x := r.lo.x + 0.05
		var run_start := INF
		while x < r.hi.x:
			var m: float = mask.call(x, z)
			var past := z > edge_z(x)
			var want := m < 0.03 and z < edge_z(x) + 0.12 + 0.35 * maxf(0.0, _n(x * 2.0, z, 129)) \
					and Vector2(x, z).distance_to(HOLE) > HOLE_R - 0.15 + 0.2 * _n(x * 4.0, z * 4.0, 127)
			if want and run_start == INF:
				run_start = x
			elif not want and run_start != INF:
				_lath(r, run_start, x, z, lath_y, past)
				run_start = INF
			x += 0.1
		if run_start != INF:
			_lath(r, run_start, r.hi.x - 0.05, z, lath_y, false)
		z += 0.036
	r.wood._end_chart()
	r.wood.colour = VOID
	var vh := HOLE + Vector2(MOON_DIR.x, MOON_DIR.z) / MOON_DIR.y * 0.3
	var hr := HOLE_R + 0.15
	for q: Rect2 in [Rect2(r.lo.x, PROS_Z, r.hi.x - r.lo.x, vh.y - hr - PROS_Z),
			Rect2(r.lo.x, vh.y + hr, r.hi.x - r.lo.x, EDGE_Z - 0.9 - vh.y - hr),
			Rect2(r.lo.x, vh.y - hr, vh.x - hr - r.lo.x, hr * 2.0),
			Rect2(vh.x + hr, vh.y - hr, r.hi.x - vh.x - hr, hr * 2.0)]:
		r.wood.face([Vector3(q.position.x, CEIL + 0.3, q.position.y), Vector3(q.end.x, CEIL + 0.3, q.position.y),
				Vector3(q.end.x, CEIL + 0.3, q.end.y), Vector3(q.position.x, CEIL + 0.3, q.end.y)], Vector3.DOWN)
	r.wood.colour = keep
	# The coffers: cased beams across and along, gilt beads at their soffits' edges, ending at the broken edge.
	for bz: float in [-7.0, -4.75]:
		_ceiling_beam(r, Vector3(r.lo.x, CEIL, bz), Vector3(r.hi.x, CEIL, bz), Vector3.BACK)
	for bx: float in [-3.7, 3.7]:
		var end := edge_z(bx) - 0.2
		_ceiling_beam(r, Vector3(bx, CEIL, PROS_Z), Vector3(bx, CEIL, end), Vector3.RIGHT)
	# The chandelier's rose: a plaster medallion, half of it fallen, its hook and the chain's end.
	var rose := Vector3(r.chandelier.x - 0.1, CEIL, r.chandelier.z + 0.4)
	var kc := r.plaster.colour
	r.plaster.colour = CEILING_WHITE * 0.8
	Shapes.lathe(r.plaster, [Vector2(0.62, 0.0), Vector2(0.6, -0.04), Vector2(0.5, -0.06), Vector2(0.42, -0.1),
			Vector2(0.3, -0.1), Vector2(0.22, -0.14), Vector2(0.1, -0.16), Vector2(0.0, -0.16)], rose, 20,
			Basis(Vector3.UP, 0.7), TAU * 0.58)
	r.plaster.colour = kc
	var link := rose + Vector3(0, -0.17, 0)
	for k in 14:
		var basis := Basis(Vector3.UP, PI * 0.5 * (k % 2)) * Basis(Vector3.BACK, 0.05 * sin(k))
		_link(r.brass, link + Vector3(0.01 * sin(k * 0.7), 0, 0), basis)
		link += Vector3(0.004, -0.048, 0.002)


static func _lath(r: Ruin, x0: float, x1: float, z: float, y: float, _past: bool) -> void:
	if x1 - x0 < 0.08:
		return
	var b := r.wood
	b.colour = TIMBER * (0.5 + 0.25 * _n(x0 * 3.0, z * 7.0, 131))
	var j0 := x0 + r.rng.randf_range(-0.03, 0.06)
	var j1 := x1 + r.rng.randf_range(-0.06, 0.03)
	var q: Array[Vector3] = [Vector3(j0, y, z), Vector3(j1, y, z), Vector3(j1, y, z + 0.026), Vector3(j0, y, z + 0.026)]
	var base: int = b._current.verts.size()
	for p: Vector3 in q:
		b._vertex(p, Vector3.DOWN, Vector2(p.x, p.z))
	b._triangle(base, base + 1, base + 2, q[0], q[1], q[2], Vector3.DOWN)
	b._triangle(base, base + 2, base + 3, q[0], q[2], q[3], Vector3.DOWN)


## A cased beam under the ceiling from a to c: its sides and soffit in plaster, a gilt bead along each lower edge.
static func _ceiling_beam(r: Ruin, a: Vector3, c: Vector3, across: Vector3) -> void:
	var path: Array[Vector3] = [a, c]
	var outs: Array[Vector3] = [across, across]
	var prof: Array[Vector2] = [Vector2(-0.24, 0.0), Vector2(-0.24, -0.3), Vector2(-0.22, -0.33), Vector2(0.22, -0.33),
			Vector2(0.24, -0.3), Vector2(0.24, 0.0)]
	var cc := CEILING_WHITE * 0.85
	_sweep(r.plaster, path, outs, Vector3.UP, prof, [cc, GILT * 0.7, cc, GILT * 0.7, cc])
	# A ragged end where it broke (the edge).
	if across == Vector3.RIGHT:
		_box(r.wood, c + Vector3(0, -0.12, 0.08), Vector3(0.2, 0.22, 0.25), Basis(Vector3.RIGHT, -0.2), TIMBER * 0.5)


## One link of a chain (a flattened ring of four bars), its middle at `at`.
static func _link(b: RoomMesh, at: Vector3, basis: Basis) -> void:
	var keep := b.colour
	b.colour = _lit(Color(0.35, 0.25, 0.1), at)
	for sgn: float in [-1.0, 1.0]:
		b.box(at + basis * Vector3(sgn * 0.014, 0, 0), Vector3(0.008, 0.056, 0.008), basis)
		b.box(at + basis * Vector3(0, sgn * 0.025, 0), Vector3(0.036, 0.008, 0.008), basis)
	b.colour = keep


## The ceiling's broken edge: the joists run on past the plaster, snapped at their own lengths (a few hang down where
## they broke), the laths' ragged ends with plaster on them, clumps of lath dangling.
static func _edge(r: Ruin) -> void:
	var b := r.wood
	var x := r.lo.x + 0.3
	while x < r.hi.x - 0.2:
		var e := edge_z(x)
		var len := 0.1 + 1.6 * pow(r.rng.randf(), 2.0)
		var y0 := CEIL + 0.04
		var a := Vector3(x, y0 + 0.09, e - 0.6)
		var c := Vector3(x, y0 + 0.09, e + len)
		var col := TIMBER * (0.22 + 0.16 * r.rng.randf())
		if r.rng.randf() < 0.12:
			# Gone: rotted off at the plaster.
			x += 0.4
			continue
		if r.rng.randf() < 0.2:
			# Snapped and hanging: the end swung down from where it broke.
			var brk := Vector3(x, y0 + 0.09, e + 0.15)
			_beam(b, a, brk, 0.06, 0.18, col)
			var droop := Basis(Vector3.RIGHT, r.rng.randf_range(0.6, 1.1))
			_beam(b, brk, brk + droop * Vector3(0, 0, len + 0.4), 0.06, 0.18, col * 0.9)
		else:
			_beam(b, a, c, 0.06, 0.18, col)
			# The snapped end: a splinter.
			_beam(b, c, c + Vector3(r.rng.randf_range(-0.02, 0.02), r.rng.randf_range(-0.03, 0.03), 0.12), 0.025,
					0.06, col * 0.9)
		x += 0.4 + r.rng.randf_range(-0.03, 0.03)
	# Dangling laths in clumps, some with plaster still on them.
	for k in 34:
		var lx := r.rng.randf_range(r.lo.x + 0.4, r.hi.x - 0.4)
		var e := edge_z(lx)
		var hang := r.rng.randf_range(0.25, 1.1)
		var lean := Basis(Vector3.RIGHT, r.rng.randf_range(0.15, 0.6)) * Basis(Vector3.BACK, r.rng.randf_range(-0.4, 0.4))
		var top := Vector3(lx, CEIL + 0.02, e + r.rng.randf_range(-0.05, 0.1))
		var bottom := top + lean * Vector3(0, -hang, 0)
		_beam(b, top, bottom, 0.026, 0.008, TIMBER * (0.4 + 0.2 * r.rng.randf()), Vector3.BACK)
		if r.rng.randf() < 0.35:
			var at := top.lerp(bottom, r.rng.randf_range(0.3, 0.8))
			_box(r.plaster, at + Vector3(0, 0, -0.012), Vector3(r.rng.randf_range(0.08, 0.2), r.rng.randf_range(0.1,
					0.25), 0.02), lean, CEILING_WHITE * 0.7)
	# The plaster's broken edge in front: its lath ends showing (the side the mask made), and a few pieces hanging by
	# their laths.
	for k in 10:
		var lx := r.rng.randf_range(r.lo.x + 1.0, r.hi.x - 1.0)
		var e := edge_z(lx)
		var basis := Basis(Vector3.RIGHT, r.rng.randf_range(0.5, 1.2))
		var w := r.rng.randf_range(0.3, 0.8)
		_box(r.plaster, Vector3(lx, CEIL - 0.12, e + 0.12), Vector3(w, 0.025, r.rng.randf_range(0.25, 0.5)), basis,
				CEILING_WHITE * 0.75)


## The trusses: king posts with tie beams on the walls, principal rafters to the ridge, struts; the one at the back
## broken (its left rafter snapped, the upper part fallen onto the tie beam), the purlins and the ridge piece only in
## part, all against the sky.
static func _trusses(r: Ruin) -> void:
	var b := r.wood
	for i in TRUSSES.size():
		var z: float = TRUSSES[i]
		var col := TIMBER * (0.7 + 0.1 * i)
		var broken := i == 2
		# The tie beam across, bearing on both walls.
		_beam(b, Vector3(r.lo.x - 0.3, TOP - 0.15, z), Vector3(r.hi.x + 0.3, TOP - 0.15, z), 0.22, 0.3, col)
		var apex := Vector3(0, RIDGE - 0.12, z)
		# The rafters.
		var right_foot := Vector3(r.hi.x + 0.1, TOP + 0.05, z)
		var left_foot := Vector3(r.lo.x - 0.1, TOP + 0.05, z)
		_beam(b, right_foot, apex, 0.2, 0.26, col, Vector3.UP)
		if broken:
			var snap := left_foot.lerp(apex, 0.52)
			_beam(b, left_foot, snap, 0.2, 0.26, col, Vector3.UP)
			# The splintered end.
			_beam(b, snap, snap + (apex - left_foot).normalized() * 0.18 + Vector3(0, 0.05, 0), 0.08, 0.1, col * 0.9)
			# The upper part: hanging from the apex, its broken end come down onto the tie beam.
			var rest := Vector3(-2.3, TOP + 0.02, z + 0.08)
			_beam(b, apex + Vector3(0, -0.05, 0.05), rest, 0.2, 0.26, col * 0.85, Vector3.UP)
		else:
			_beam(b, left_foot, apex, 0.2, 0.26, col, Vector3.UP)
		# The king post, its foot iron-strapped to the tie beam, and the struts.
		_beam(b, Vector3(0, TOP - 0.3, z), Vector3(0, RIDGE + 0.05, z), 0.2, 0.2, col, Vector3.BACK)
		_box(b, Vector3(0, TOP - 0.1, z), Vector3(0.26, 0.4, 0.24), Basis(), VOID * 5.0)
		for s: float in [-1.0, 1.0]:
			if broken and s < 0.0:
				continue
			var mid := Vector3(s * 4.0, roof_y(s * 4.0) - 0.35, z)
			_beam(b, Vector3(s * 0.1, TOP + 0.1, z), mid, 0.15, 0.15, col, Vector3.UP)
	# Purlins along the slopes (on the rafters at x +-4.1) and the ridge piece: whole on the right; on the left only
	# over the front bay; the ridge broken off past the second truss.
	var pc := TIMBER * 0.65
	_purlin(r, 4.1, TRUSSES[0] - 0.2, r.hi.z, pc)
	_purlin(r, -4.1, TRUSSES[0] - 0.2, TRUSSES[1] + 0.7, pc)
	_purlin(r, -4.1, TRUSSES[2] - 0.4, r.hi.z, pc)
	_purlin(r, 6.3, TRUSSES[0] - 0.2, r.hi.z, pc)
	_beam(b, Vector3(0, RIDGE + 0.1, TRUSSES[0] - 0.2), Vector3(0, RIDGE + 0.1, TRUSSES[1] + 0.9), 0.08, 0.26, pc,
			Vector3.UP)
	# The broken ridge's end hanging off the second truss.
	_beam(b, Vector3(0, RIDGE + 0.1, TRUSSES[1] + 0.9), Vector3(0.1, RIDGE - 0.9, TRUSSES[1] + 1.6), 0.08, 0.24, pc * 0.9,
			Vector3.UP)
	# Wall plates along the walls' tops (rotten, broken where the wall top fell).
	for s: float in [-1.0, 1.0]:
		var z := r.lo.z
		while z < r.hi.z:
			var z1 := minf(z + 1.6, r.hi.z)
			if wall_top(s, (z + z1) * 0.5) > TOP - 0.1:
				_beam(b, Vector3(s * (r.hi.x + 0.15), TOP + 0.02, z), Vector3(s * (r.hi.x + 0.15), TOP + 0.02, z1),
						0.22, 0.12, TIMBER * 0.5)
			z = z1 + 0.05


static func _purlin(r: Ruin, x: float, z0: float, z1: float, col: Color) -> void:
	var y := roof_y(x) + 0.14
	_beam(r.wood, Vector3(x, y, z0), Vector3(x, y, z1), 0.16, 0.2, col, Vector3(-signf(x) * 0.36, 0.93, 0).normalized())


## The roof: the front half whole (its slates over boards, their underside dark over the ceiling), ending in a ragged
## line over the edge's truss with slates hanging; a patch of rafters on the right of the open half with battens and
## a few courses of slates, some slid down and caught at the eaves.
static func _roof(r: Ruin) -> void:
	var b := r.wood
	var end := TRUSSES[0] + 0.1
	for s: float in [-1.0, 1.0]:
		var eave := Vector3(s * (r.hi.x + 0.45), TOP - 0.1, 0)
		var ridge := Vector3(0, RIDGE + 0.38, 0)
		# The underside (boards, dark), and the slates on top: from the front wall to the ragged end.
		var steps := 16
		var under_a := PackedVector3Array()
		var under_b := PackedVector3Array()
		var ns := PackedVector3Array()
		var top_a := PackedVector3Array()
		var top_b := PackedVector3Array()
		var tns := PackedVector3Array()
		var slope_n := Vector3(s * (RIDGE - TOP), 8.25, 0).normalized()
		for k in steps + 1:
			var t := float(k) / steps
			var p := eave.lerp(ridge, t)
			var rag := end + 0.35 * _n(t * 5.0, s * 3.0, 141) + 0.25
			under_a.append(Vector3(p.x, p.y - 0.03, r.lo.z))
			under_b.append(Vector3(p.x, p.y - 0.03, rag))
			ns.append(-slope_n)
			top_a.append(Vector3(p.x, p.y + 0.04, r.lo.z))
			top_b.append(Vector3(p.x, p.y + 0.04, rag + 0.05))
			tns.append(slope_n)
		if s > 0.0:
			b.colour = VOID * 3.0
			b.strip(under_a, under_b, ns)
			b.colour = SLATE
			b.strip(top_b, top_a, tns)
		else:
			_holed_slope(r, eave, ridge, end, slope_n)
		# Its broken end: slates hanging by a nail.
		for k in 9:
			var t := r.rng.randf_range(0.05, 0.95)
			var p := eave.lerp(ridge, t)
			var rag := end + 0.35 * _n(t * 5.0, s * 3.0, 141) + 0.3
			var hang := Basis(Vector3.RIGHT, r.rng.randf_range(0.6, 1.4)) * Basis(Vector3.BACK, r.rng.randf_range(-0.5,
					0.5))
			_box(b, Vector3(p.x, p.y - 0.15, rag + 0.12), Vector3(0.28, 0.012, 0.42), hang, SLATE * 1.3)
	b.colour = Color.WHITE
	# The right's patch of rafters over the open half: from the eaves to past the purlin, battens, slates low down.
	var z := TRUSSES[1] + 0.25
	while z < r.hi.z - 0.1:
		var reach := r.rng.randf_range(2.8, 4.6)
		var foot := Vector3(r.hi.x + 0.3, TOP + 0.08, z)
		var dir := Vector3(-8.25, RIDGE - TOP, 0).normalized()
		if z > 1.4 or r.rng.randf() < 0.6:
			_beam(b, foot, foot + dir * reach, 0.06, 0.13, TIMBER * (0.5 + 0.15 * r.rng.randf()), Vector3.UP)
		z += 0.45
	var bx := r.hi.x + 0.2
	while bx > 4.6:
		var y := roof_y(bx) + 0.17
		if bx > 5.6 or r.rng.randf() < 0.5:
			# In lengths: some broken off, some gone.
			var bz := TRUSSES[1] + 0.2
			while bz < r.hi.z - 0.2:
				var bz1 := minf(bz + r.rng.randf_range(0.9, 2.6), r.hi.z - 0.1)
				if r.rng.randf() < 0.7 or bx > 6.8:
					_beam(b, Vector3(bx, y, bz), Vector3(bx, y, bz1), 0.05, 0.025, TIMBER * 0.45,
							Vector3(-0.36, 0.93, 0))
				bz = bz1 + r.rng.randf_range(0.05, 0.9)
		bx -= 0.26
	# Slates on the lower courses, with gaps, a few slid down and caught on the batten below or the wall plate.
	var sz := TRUSSES[1] + 0.25
	var slope := Vector3(-8.25, RIDGE - TOP, 0).normalized()
	var sn := Vector3(RIDGE - TOP, 8.25, 0).normalized()
	while sz < r.hi.z - 0.2:
		var sx := r.hi.x + 0.35
		while sx > 5.2:
			if _slate_left(sx, sz):
				var p := Vector3(sx, roof_y(sx) + 0.21, sz)
				var basis := Basis(Vector3(0, 0, 1).cross(sn).normalized(), sn, Vector3(0, 0, 1)) \
						* Basis(Vector3.UP, r.rng.randf_range(-0.04, 0.04))
				var slid := r.rng.randf() < 0.1
				if slid:
					p += slope * -0.25 + Vector3(0, -0.05, 0)
					basis = basis * Basis(Vector3.UP, r.rng.randf_range(-0.4, 0.4))
				_box(b, p, Vector3(0.5, 0.012, 0.29), basis, SLATE * (0.8 + 0.5 * r.rng.randf()))
			sx -= 0.22
		sz += 0.3
	# The gable's ragged top course and its coping stones where they hold.
	var gx := r.lo.x + 0.2
	while gx < r.hi.x:
		var y := gable_top(gx)
		if y > roof_y(gx) - 0.1:
			_box(r.brick, Vector3(gx, y + 0.05, r.hi.z + 0.2), Vector3(0.55, 0.1, 0.5), Basis(Vector3.BACK,
					-signf(gx) * 0.37), BRICK * 0.6)
		gx += 0.6


# --- Growth ---------------------------------------------------------------------------------------------------------

## The ivy: masses pouring over the walls' tops under the open half and down the walls, over the rear wall's left,
## and in cascades from the ceiling's broken edge. Each mass is leaves over its outer surface, thick over the top
## and thinning down to trailing strands; the inner leaves darker.
static func _ivy_all(r: Ruin) -> void:
	# [wall: "l", "r" or "rear"; from; to (along it); drop (metres); bulk (how far out it stands)]
	var masses := [["l", -1.6, 1.9, 5.2, 0.45], ["l", 2.7, 5.5, 3.6, 0.35], ["r", -1.0, 3.6, 6.2, 0.5],
			["r", 4.2, 5.5, 2.8, 0.3], ["rear", -8.0, -3.4, 4.6, 0.4], ["rear", 3.4, 8.0, 3.0, 0.32],
			["l", -4.6, -2.8, 1.7, 0.25]]
	for m: Array in masses:
		_ivy_mass(r, str(m[0]), float(m[1]), float(m[2]), float(m[3]), float(m[4]))
	# Cascades off the ceiling's edge (hanging from the joists' ends): short curtains, clear of every sight line.
	for cx: float in [-6.1, -2.4, 1.6, 5.4]:
		_ivy_cascade(r, cx, r.rng.randf_range(0.8, 1.6), r.rng.randf_range(1.3, 2.4))


## The wall's frame for a mass: origin at the wall's top over `along`, the wall's normal (into the room), along.
static func _wall_frame(r: Ruin, wall: String, along: float) -> Array:
	match wall:
		"l":
			return [Vector3(r.lo.x, wall_top(-1.0, along), along), Vector3.RIGHT, Vector3.BACK]
		"r":
			return [Vector3(r.hi.x, wall_top(1.0, along), along), Vector3.LEFT, Vector3.BACK]
		_:
			return [Vector3(along, gable_top(along), r.hi.z), Vector3.FORWARD, Vector3.RIGHT]


static func _ivy_mass(r: Ruin, wall: String, a0: float, a1: float, drop: float, bulk: float) -> void:
	var b := r.leaves
	var length := a1 - a0
	var count := int(length * drop * 135.0)
	var seed_v := int(a0 * 13.0) + wall.length() * 7
	for i in count:
		var a := r.rng.randf_range(a0, a1)
		var fr: Array = _wall_frame(r, wall, a)
		var top: Vector3 = fr[0]
		var n: Vector3 = fr[1]
		# How far down here: the mass's ragged lower edge, shorter towards its ends.
		var end_fade := smoothstep(0.0, 0.8, minf(a - a0, a1 - a))
		var here := drop * (0.45 + 0.4 * (0.5 + 0.5 * _n(a * 0.9, float(seed_v), 151))) * (0.35 + 0.65 * end_fade)
		if wall == "rear":
			here = minf(here, top.y - floor_at(r, r.hi.z - 0.1) - 0.3)
		else:
			here = minf(here, top.y - floor_at(r, a) - 0.4)
		var d := pow(r.rng.randf(), 0.8) * here
		# The bulk: thick over the top (it spills over the wall's top), thinner down the face, ragged.
		var t := d / maxf(here, 0.01)
		var out := bulk * (1.0 - 0.75 * t) * (0.6 + 0.6 * (0.5 + 0.5 * _n(a * 2.2, d * 2.2, seed_v + 3)))
		var depth := r.rng.randf()
		var off := out * (0.35 + 0.65 * sqrt(depth))
		var p := top + n * (off + 0.02) + Vector3(0, -d + 0.12 * (1.0 - t), 0)
		if d < 0.25:
			# Over the top: the mass rounds over the wall's head.
			p += Vector3(0, 0.18 * (1.0 - d / 0.25) * depth, 0) - n * 0.15 * (1.0 - d / 0.25)
		if p.y < floor_at(r, p.z) + 0.15:
			continue
		var facing := (n * 0.8 + Vector3(r.rng.randf_range(-0.6, 0.6), r.rng.randf_range(-0.2, 0.7),
				r.rng.randf_range(-0.6, 0.6))).normalized()
		var size := r.rng.randf_range(0.08, 0.15) * (1.15 - 0.3 * t)
		var along := (Vector3.DOWN + facing * 0.3 + Vector3(r.rng.randf_range(-0.5, 0.5), 0, r.rng.randf_range(-0.5,
				0.5))).normalized()
		along = (along - facing * along.dot(facing)).normalized() * size
		var c := IVY * (0.55 + 0.75 * sqrt(depth)) * (0.8 + 0.4 * r.rng.randf())
		if r.rng.randf() < 0.07:
			c = Color(0.08, 0.12, 0.03)
		_leaf(b, p, along, size * 1.05, facing, _lit(c, p + n * 0.1))
	# Trailing strands below the mass: stems with a leaf every few centimetres.
	var strands := int(length * 2.2)
	for k in strands:
		var a := r.rng.randf_range(a0 + 0.2, a1 - 0.2)
		var fr: Array = _wall_frame(r, wall, a)
		var top: Vector3 = fr[0]
		var n: Vector3 = fr[1]
		var start := drop * 0.4
		var len := r.rng.randf_range(0.6, 2.4)
		var y := top.y - start
		var lowest := floor_at(r, a if wall != "rear" else r.hi.z - 0.1) + 0.3
		var sway := r.rng.randf_range(-0.2, 0.2)
		var j := 0.0
		while j < len and y - j > lowest:
			var p := top + n * (0.04 + 0.05 * sin(j * 3.0)) + Vector3(0, -start - j, 0)
			p += (fr[2] as Vector3) * sway * j
			var facing := (n + Vector3(r.rng.randf_range(-0.5, 0.5), 0.3, r.rng.randf_range(-0.5, 0.5))).normalized()
			var size := r.rng.randf_range(0.04, 0.075)
			_leaf(b, p, (Vector3.DOWN - facing * Vector3.DOWN.dot(facing)).normalized() * size, size, facing,
					_lit(IVY * (0.8 + 0.4 * r.rng.randf()), p))
			j += r.rng.randf_range(0.06, 0.11)


## Ivy hanging from the ceiling's broken edge: strands from the joists' ends, leaves along them both ways.
static func _ivy_cascade(r: Ruin, cx: float, width: float, drop: float) -> void:
	var b := r.leaves
	for k in int(width * 9.0):
		var x := cx + r.rng.randf_range(-width * 0.5, width * 0.5)
		var z := edge_z(x) + r.rng.randf_range(0.05, 0.6)
		var len := drop * r.rng.randf_range(0.35, 1.0) * (1.0 - absf(x - cx) / width)
		var j := 0.0
		var swing := Vector3(r.rng.randf_range(-0.08, 0.08), 0, r.rng.randf_range(-0.08, 0.08))
		while j < len:
			var p := Vector3(x, CEIL + 0.15 - j, z) + swing * j * j
			for side: float in [-1.0, 1.0]:
				var facing := Vector3(side * r.rng.randf_range(0.2, 0.8), r.rng.randf_range(-0.2, 0.4), side * 0.4 +
						r.rng.randf_range(-0.8, 0.8)).normalized()
				var size := r.rng.randf_range(0.05, 0.085)
				var along := (Vector3.DOWN - facing * Vector3.DOWN.dot(facing)).normalized() * size
				_leaf(b, p + facing * 0.02, along, size, facing, _lit(IVY * (0.7 + 0.5 * r.rng.randf()), p), true)
			j += r.rng.randf_range(0.05, 0.09)


## A young birch through the right side aisle's broken steps: a white trunk with dark marks, black and fissured at
## its foot, leaning towards the open sky; branches rising, their twigs weeping, small leaves turning yellow.
static func _birch(r: Ruin, foot: Vector3) -> void:
	var b := r.leaves
	foot.y = floor_at(r, foot.z) - 0.05
	var lean := Vector3(-0.12, 1.0, -0.05).normalized()
	var height := 9.2
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	var cols: Array[Color] = []
	for k in 25:
		var t := k / 24.0
		var p := foot + lean * height * t + Vector3(0.18 * sin(t * 4.0), 0, 0.1 * sin(t * 3.0 + 1.0)) * t
		pts.append(p)
		radii.append(lerpf(0.15, 0.03, pow(t, 0.75)) * (1.15 if k == 0 else 1.0))
		var c := BARK * (0.85 + 0.2 * _n(t * 9.0, 1.0, 161))
		if t < 0.14:
			c = c.lerp(Color(0.035, 0.03, 0.025), 1.0 - t / 0.14)
		elif _n(t * 26.0, 3.0, 163) > 0.3:
			c *= 0.15
		cols.append(_lit(c, p))
	_tube(b, pts, radii, 12, cols)
	var branches := 24
	for i in branches:
		var t := lerpf(0.22, 0.95, float(i) / (branches - 1)) + r.rng.randf_range(-0.02, 0.02)
		var k := clampi(int(t * 24.0), 0, 23)
		var base := pts[k].lerp(pts[k + 1], t * 24.0 - k)
		var az := i * 2.39996 + r.rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(az), 0, sin(az))
		# Towards the open hall more than into the wall.
		if out.x > 0.2:
			out = (out + Vector3(-1.1, 0, 0)).normalized()
		var reach := lerpf(2.6, 1.0, t) * r.rng.randf_range(0.75, 1.15)
		var rise := lerpf(0.55, 0.9, t)
		var bp: Array[Vector3] = []
		var br: Array[float] = []
		var bc: Array[Color] = []
		for j in 7:
			var s := j / 6.0
			var p := base + out * reach * s + Vector3(0, reach * (rise * s - 0.45 * s * s), 0)
			bp.append(p)
			br.append(lerpf(0.04 * (1.2 - t), 0.008, s))
			bc.append(_lit(BARK * (0.45 if j < 2 else 0.25), p))
		_tube(b, bp, br, 5, bc)
		# Side shoots, and twigs weeping from both, leaves along them.
		var shoots: Array = [bp]
		for q in 2:
			var j0 := 2 + q * 2
			var sdir := (out.rotated(Vector3.UP, (0.7 if q == 0 else -0.7)) + Vector3(0, 0.35, 0)).normalized()
			var sp: Array[Vector3] = [bp[j0], bp[j0] + sdir * reach * 0.3, bp[j0] + sdir * reach * 0.55
					+ Vector3(0, -0.1, 0)]
			_tube(b, sp, [0.012, 0.008, 0.004] as Array[float], 4, [bc[j0], bc[j0], bc[j0]] as Array[Color])
			shoots.append(sp)
		for sh: Array in shoots:
			for j in range(1, sh.size()):
				var p0: Vector3 = sh[j]
				for q in 2:
					_twig(r, p0 + Vector3(r.rng.randf_range(-0.1, 0.1), 0, r.rng.randf_range(-0.1, 0.1)), out,
							r.rng.randf_range(0.35, 0.95))


## Ferns: in the pit's corners by the stage, along the stage's foot, in the floor's rotted holes, at the walls' feet
## where the damp is, by the doorways; hart's-tongue in the brick where the plaster fell, under the open roof.
static func _ferns_all(r: Ruin) -> void:
	var spots := [[Vector3(-7.3, r.lo.y, -8.1), 1.1], [Vector3(7.2, r.lo.y, -8.0), 1.0],
			[Vector3(-5.6, r.lo.y, -8.25), 0.6], [Vector3(5.9, r.lo.y, -8.3), 0.7], [Vector3(-1.6, r.lo.y, -8.32), 0.42],
			[Vector3(2.4, r.lo.y, -8.32), 0.38], [Vector3(-3.5, r.lo.y - 0.25, -6.1), 0.9],
			[Vector3(-3.1, r.lo.y - 0.25, -5.95), 0.6], [Vector3(5.6, r.lo.y - 0.25, -7.2), 0.75],
			[Vector3(-7.4, r.lo.y, -5.0), 0.8], [Vector3(7.4, r.lo.y, -5.6), 0.9], [Vector3(-7.45, r.lo.y, -2.4), 0.7],
			[Vector3(7.45, r.lo.y, -1.7), 0.8], [Vector3(-8.9, r.lo.y, -7.1), 0.9], [Vector3(-7.6, 0.9, 5.25), 0.7],
			[Vector3(-6.6, 0.9, 6.5), 1.0], [Vector3(7.5, 0.9, 5.2), 0.9]]
	for s: Array in spots:
		_fern(r, s[0], float(s[1]))
		r.taken.append([Vector2((s[0] as Vector3).x, (s[0] as Vector3).z), float(s[1]) * 0.5])
	# Hart's-tongue: straps from the brick's joints, a few to a clump, on the walls under the open half.
	for k in 26:
		var side := -1.0 if k % 2 == 0 else 1.0
		var z := r.rng.randf_range(-1.5, 5.2)
		var y := r.rng.randf_range(floor_at(r, z) + 0.6, 6.5)
		if _wall_plaster(r, side, z, y) > -0.05:
			continue
		var at := Vector3(side * (r.hi.x - 0.01), y, z)
		var n := Vector3(-side, 0, 0)
		for j in 5:
			var dir := (n * 0.8 + Vector3(0, r.rng.randf_range(-0.6, 0.5), r.rng.randf_range(-0.7, 0.7))).normalized()
			var len := r.rng.randf_range(0.18, 0.32)
			var facing := (dir.cross(Vector3.UP).cross(dir)).normalized()
			if facing.dot(n) < 0.0:
				facing = -facing
			_leaf(r.leaves, at, dir * len, 0.045, (facing + Vector3.UP * 0.3).normalized(),
					_lit(Color(0.06, 0.12, 0.03) * (0.8 + 0.4 * r.rng.randf()), at), true)


static func _fern(r: Ruin, at: Vector3, size: float) -> void:
	var b := r.leaves
	var fronds := 8 + r.rng.randi() % 5
	for f in fronds:
		var a := TAU * f / fronds + r.rng.randf_range(-0.25, 0.25)
		var dir := Vector3(sin(a), 0, cos(a))
		var reach := size * r.rng.randf_range(0.7, 1.05)
		var lift := size * r.rng.randf_range(0.5, 0.9)
		var prev := at + Vector3(0, 0.02, 0)
		var col := Color(0.05, 0.1, 0.025) * (0.8 + 0.5 * r.rng.randf())
		if r.rng.randf() < 0.15:
			col = Color(0.18, 0.12, 0.03)
		for i in range(1, 13):
			var t := i / 12.0
			var p := at + dir * reach * t + Vector3.UP * (lift * sin(t * PI * 0.8) - 0.05 * t)
			var along := p - prev
			var side := dir.cross(Vector3.UP).normalized()
			var leaf_len := 0.16 * size * (1.0 - t * 0.75)
			for s: float in [-1.0, 1.0]:
				var lv := (side * s * leaf_len + along.normalized() * leaf_len * 0.4)
				var nn := (Vector3.UP + side * s * 0.2 - dir * 0.3).normalized()
				_leaf(b, p, lv, leaf_len * 0.38, nn, _lit(col * (0.9 + 0.2 * t), p), true)
			prev = p


## The pit's meadow in the Moon's pool: grass and flowers in patches where the light falls (ox-eye daisies, yarrow's
## flat heads), a few on their own; rosebay willowherb's pink spikes along the right wall's foot; all low in the pit,
## under every sight line.
static func _meadow(r: Ruin) -> void:
	var patches := 0
	var tries := 0
	while patches < 15 and tries < 500:
		tries += 1
		var x := r.rng.randf_range(-4.5, 6.6)
		var z := r.rng.randf_range(-7.4, -2.0)
		if z > riser_z(r, x) - 0.7:
			continue
		var lit := moon_light(Vector3(x, 0.0, z))
		if lit < 0.5 and r.rng.randf() < 0.9:
			continue
		if r.puddle.grow(0.4).has_point(Vector2(x, z)) or _taken(r, Vector2(x, z), 0.4):
			continue
		var rad := r.rng.randf_range(0.35, 0.8)
		var tufts := int(rad * 34.0)
		for k in tufts:
			var a := r.rng.randf() * TAU
			var d := sqrt(r.rng.randf()) * rad
			var px := x + cos(a) * d
			var pz := z + sin(a) * d * 0.8
			if r.puddle.grow(0.1).has_point(Vector2(px, pz)) or _taken(r, Vector2(px, pz), 0.05):
				continue
			var edge := d / rad
			_tuft(r, Vector3(px, r.lo.y, pz), r.rng.randf_range(0.14, 0.38) * (1.0 - 0.45 * edge))
			if r.rng.randf() < 0.5 * (1.0 - edge * 0.5):
				_flower(r, Vector3(px + r.rng.randf_range(-0.05, 0.05), r.lo.y, pz + r.rng.randf_range(-0.05, 0.05)),
						r.rng.randf_range(0.2, 0.4), r.rng.randf() < 0.35)
		r.taken.append([Vector2(x, z), rad * 0.8])
		patches += 1
	# Single tufts in the boards' cracks.
	for k in 40:
		var x := r.rng.randf_range(-7.5, 7.5)
		var z := r.rng.randf_range(r.stage_front + 0.2, -1.6)
		if z > riser_z(r, x) - 0.3 or r.puddle.grow(0.1).has_point(Vector2(x, z)) or _taken(r, Vector2(x, z), 0.1):
			continue
		_tuft(r, Vector3(x, r.lo.y, z), r.rng.randf_range(0.08, 0.2))
	# Willowherb along the right wall's foot and by the left doorway: pink spikes, tall, away from the sight lines.
	for k in 16:
		var x := r.rng.randf_range(7.15, 7.75) if k < 12 else r.rng.randf_range(-7.75, -7.3)
		var z := r.rng.randf_range(-7.5, -2.6) if k < 12 else r.rng.randf_range(-6.6, -5.4)
		_willowherb(r, Vector3(x, r.lo.y, z), r.rng.randf_range(0.7, 1.15))


static func _taken(r: Ruin, at: Vector2, rad: float) -> bool:
	for t: Array in r.taken:
		if (t[0] as Vector2).distance_to(at) < float(t[1]) + rad:
			return true
	return false


static func _tuft(r: Ruin, at: Vector3, h: float) -> void:
	var blades := 14 + r.rng.randi() % 10
	for k in blades:
		var a := r.rng.randf() * TAU
		var tilt := r.rng.randf_range(0.05, 0.55)
		var dir := Vector3(sin(a) * tilt, 1.0, cos(a) * tilt).normalized()
		var len := h * r.rng.randf_range(0.5, 1.0)
		var base := at + Vector3(r.rng.randf_range(-0.04, 0.04), 0, r.rng.randf_range(-0.04, 0.04))
		var facing := Vector3(cos(a), 0, -sin(a))
		var c := Color(0.05, 0.085, 0.022) * (0.7 + 0.6 * r.rng.randf())
		if r.rng.randf() < 0.3:
			c = Color(0.13, 0.12, 0.05) * (0.7 + 0.5 * r.rng.randf())
		var keep := r.leaves.colour
		r.leaves.colour = _lit(c * 0.6, base)
		var bi: int = r.leaves._current.verts.size()
		var side := facing.cross(dir).normalized() * 0.006
		var tip := base + dir * len + Vector3(sin(a), 0, cos(a)) * len * 0.2
		for q: Vector3 in [base - side, base + side]:
			r.leaves._vertex(q, facing, Vector2.ZERO)
		r.leaves.colour = _lit(c * 1.15, tip)
		r.leaves._vertex(tip, facing, Vector2.ZERO)
		r.leaves._triangle(bi, bi + 1, bi + 2, base - side, base + side, tip, facing)
		r.leaves._triangle(bi, bi + 2, bi + 1, base - side, tip, base + side, -facing)
		r.leaves.colour = keep


## A white flower on a stem: daisy (a ring of petals round a yellow eye) or yarrow (a flat head of tiny florets).
static func _flower(r: Ruin, at: Vector3, h: float, yarrow: bool) -> void:
	var b := r.leaves
	var head := at + Vector3(r.rng.randf_range(-0.04, 0.04), h, r.rng.randf_range(-0.04, 0.04))
	var stem: Array[Vector3] = [at, at.lerp(head, 0.5) + Vector3(0.01, 0, 0), head]
	var green := _lit(Color(0.05, 0.09, 0.025), head)
	_tube(b, stem, [0.004, 0.0035, 0.003] as Array[float], 3, [green, green, green] as Array[Color])
	var white := _lit(Color(0.62, 0.62, 0.56), head) if not yarrow else _lit(Color(0.5, 0.48, 0.42), head)
	var up := (Vector3.UP + Vector3(r.rng.randf_range(-0.3, 0.3), 0, r.rng.randf_range(-0.3, 0.3)) * 0.6).normalized()
	if yarrow:
		for k in 7:
			var a := TAU * k / 7.0
			var off := Vector3(cos(a), 0, sin(a)) * 0.025
			_leaf(b, head + off - Vector3(0.012, 0, 0), Vector3(0.024, 0, 0), 0.024, up, white)
		return
	for k in 10:
		var a := TAU * k / 10.0
		var dir := Vector3(cos(a), 0, sin(a))
		dir = (dir - up * dir.dot(up)).normalized()
		_leaf(b, head, dir * 0.028, 0.012, up, white)
	_leaf(b, head + up * 0.003 - Vector3(0.008, 0, 0), Vector3(0.016, 0, 0), 0.016, up, _lit(Color(0.42, 0.3,
			0.02), head))


static func _willowherb(r: Ruin, at: Vector3, h: float) -> void:
	var b := r.leaves
	var top := at + Vector3(r.rng.randf_range(-0.06, 0.06), h, r.rng.randf_range(-0.06, 0.06))
	var green := _lit(Color(0.05, 0.08, 0.025), top)
	_tube(b, [at, at.lerp(top, 0.5), top] as Array[Vector3], [0.006, 0.005, 0.003] as Array[float], 3,
			[green, green, green] as Array[Color])
	# Narrow leaves up the stem, the pink flowers on the top third, buds at the very top.
	for k in 9:
		var t := 0.1 + 0.55 * k / 8.0
		var p := at.lerp(top, t)
		var a := k * 2.4
		var dir := Vector3(cos(a), 0.6, sin(a)).normalized()
		_leaf(b, p, dir * 0.11, 0.022, Vector3(-sin(a), 0.3, cos(a)).normalized(), _lit(Color(0.05, 0.09, 0.025), p),
				true)
	for k in 14:
		var t := 0.68 + 0.3 * k / 13.0
		var p := at.lerp(top, t)
		var a := k * 2.1
		var off := Vector3(cos(a), 0, sin(a)) * 0.03 * (1.0 - t * 0.6)
		var pink := Color(0.42, 0.06, 0.2) if t < 0.92 else Color(0.2, 0.05, 0.1)
		_leaf(b, p + off, Vector3(cos(a), 0.2, sin(a)).normalized() * 0.024, 0.02, Vector3(cos(a), 0.6,
				sin(a)).normalized(), _lit(pink, p), true)


## Moss: a green band along the stage's nosing, cushions on the tops of seat backs here and there, small patches on
## the pit's boards by the walls and round the puddle.
static func _moss(r: Ruin) -> void:
	var x := r.lo.x + 0.2
	while x < r.hi.x - 0.2:
		if _n(x * 0.8, 1.0, 171) > -0.1:
			var p := Vector3(x, r.stage_top + 0.004, r.stage_front + r.rng.randf_range(0.01, 0.06))
			_pad(r, p, r.rng.randf_range(0.05, 0.11), Vector3.UP)
			if r.rng.randf() < 0.4:
				_pad(r, Vector3(x, r.stage_top - 0.07, r.stage_front + 0.042), r.rng.randf_range(0.03, 0.07),
						Vector3.BACK)
		x += r.rng.randf_range(0.06, 0.16)
	for i in r.seats.size():
		if i in r.skip_seats or r.seats[i].origin.length() < 0.05:
			continue
		var st := r.seats[i]
		var lit := moon_light(st * Vector3(0, 0.8, 0.3))
		if r.rng.randf() < 0.15 + 0.25 * lit:
			for k in 3 + r.rng.randi() % 4:
				var p := st * Vector3(r.rng.randf_range(-0.24, 0.24), 0.795, 0.33)
				_pad(r, p, r.rng.randf_range(0.025, 0.05), Vector3.UP)
	for k in 70:
		var side := -1.0 if k % 2 == 0 else 1.0
		var z := r.rng.randf_range(r.stage_front + 0.2, -1.6)
		var p := Vector3(side * r.rng.randf_range(6.8, 7.95), r.lo.y + 0.003, z)
		if k > 45:
			p = Vector3(r.puddle.position.x + r.rng.randf() * r.puddle.size.x, r.lo.y + 0.003,
					r.puddle.position.y + (0.0 if r.rng.randf() < 0.5 else r.puddle.size.y) + r.rng.randf_range(-0.25,
					0.25))
			if r.puddle.has_point(Vector2(p.x, p.z)):
				continue
		# A patch: a few cushions together.
		for j in 2 + r.rng.randi() % 4:
			_pad(r, p + Vector3(r.rng.randf_range(-0.08, 0.08), 0, r.rng.randf_range(-0.08, 0.08)),
					r.rng.randf_range(0.03, 0.07), Vector3.UP)


## A cushion of moss: a low dome of facets, rough-edged, dark green, a little brighter where the Moon is.
static func _pad(r: Ruin, at: Vector3, rad: float, up: Vector3) -> void:
	var b := r.leaves
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := up.cross(side).normalized()
	var ring := 7
	var keep := b.colour
	var centre := at + up * rad * 0.45
	var c := MOSS * (0.45 + 0.4 * r.rng.randf())
	if r.rng.randf() < 0.2:
		c = Color(0.09, 0.09, 0.02)
	b.colour = _lit(c * 1.1, centre)
	var base: int = b._current.verts.size()
	b._vertex(centre, up, Vector2.ZERO)
	var pts: Array[Vector3] = []
	for k in ring:
		var a := TAU * k / ring
		var rr := rad * r.rng.randf_range(0.65, 1.2)
		var p := at + (side * cos(a) + fwd * sin(a)) * rr + up * 0.002
		pts.append(p)
		b.colour = _lit(c * 0.6, p)
		b._vertex(p, (up + (side * cos(a) + fwd * sin(a)) * 0.6).normalized(), Vector2.ZERO)
	for k in ring:
		var k1 := (k + 1) % ring
		b._triangle(base, base + 1 + k, base + 1 + k1, centre, pts[k], pts[k1], up)
	b.colour = keep


## Leaf litter: drifts against the stage's front and the walls, round the puddle, under and between the seats, in
## the aisles; and leaves floating on the puddle.
static func _litter(r: Ruin) -> void:
	var b := r.leaves
	var count := 0
	var tries := 0
	while count < 2300 and tries < 9000:
		tries += 1
		var x := r.rng.randf_range(r.lo.x + 0.05, r.hi.x - 0.05)
		var z := r.rng.randf_range(r.stage_front + 0.02, r.hi.z - 0.1)
		# Denser by the stage, the walls, the riser and under the open roof.
		var w := 0.12 + 0.9 * (1.0 - smoothstep(0.0, 1.2, z - r.stage_front))
		w += 0.7 * (1.0 - smoothstep(0.0, 1.0, r.hi.x - absf(x)))
		w += 0.45 * moon_light(Vector3(x, 0.5, z))
		w += 0.4 * maxf(0.0, _n(x * 0.5, z * 0.5, 181))
		if r.rng.randf() > w:
			continue
		var y := r.lo.y
		var over_pit := z < riser_z(r, x) - 0.02
		if not over_pit:
			if r.L == null:
				continue
			y = floor_at(r, z) if absf(x) > r.L.block_x else _tier_floor(r, x, z)
		if over_pit and r.puddle.has_point(Vector2(x, z)):
			continue
		var in_hole := false
		for h: Array in r.holes:
			var hc: Vector2 = h[0]
			var hs: Vector2 = h[1]
			if Vector2((x - hc.x) / hs.x, (z - hc.y) / hs.y).length() < 1.1:
				in_hole = true
		if in_hole:
			continue
		var a := r.rng.randf() * TAU
		var size := r.rng.randf_range(0.045, 0.085)
		var n := Vector3(r.rng.randf_range(-0.25, 0.25), 1.0, r.rng.randf_range(-0.25, 0.25)).normalized()
		var p := Vector3(x, y + 0.004 + r.rng.randf() * 0.006, z)
		var c: Color = LITTER[r.rng.randi() % LITTER.size()] * (0.7 + 0.5 * r.rng.randf())
		_leaf(b, p, Vector3(cos(a), 0, sin(a)) * size, size * 0.7, n, _lit(c, p))
		count += 1
	# Floating on the puddle: a few, still.
	for k in 26:
		var x := r.puddle.position.x + r.rng.randf_range(0.2, r.puddle.size.x - 0.2)
		var z := r.puddle.position.y + r.rng.randf_range(0.2, r.puddle.size.y - 0.2)
		var p := Vector3(x, r.lo.y + 0.016, z)
		var a := r.rng.randf() * TAU
		var size := r.rng.randf_range(0.05, 0.08)
		_leaf(b, p, Vector3(cos(a), 0, sin(a)) * size, size * 0.75, Vector3.UP, _lit(LITTER[k % 4] * 0.8, p))


## The floor of the tiers under (x, z): its row's.
static func _tier_floor(r: Ruin, x: float, z: float) -> float:
	var d := Vector2(x, z + r.L.radius).length()
	var row := roundi((r.L.radius - d) / r.L.depth)
	row = clampi(row, -r.L.rows_back, r.L.rows_front)
	return r.L.row_floor(row)


# --- The stalls --------------------------------------------------------------------------------------------------------

## The chandelier where it fell: it came down on its basket of drops and tipped over; a brass column, two rings and
## eight scrolled arms with their cups, bent; chains of crystal drops in festoons between the arms and in strands
## from the rings, falling where gravity takes them and lying in heaps on the boards; drops scattered round; the
## chain's end from its crown along the floor. Its crystals catch the Moon: a few facets glint towards the stalls
## (fixed, no sparkle in time).
static func _chandelier(r: Ruin) -> void:
	var c := r.chandelier
	var floor_y := c.y
	var tilt := Basis(Vector3(0.35, 0, 1).normalized(), 0.95) * Basis(Vector3.UP, 0.5)
	var xf := Transform3D(tilt, Vector3.ZERO)
	# Rest it on the boards: the lowest of its points just on them.
	var low := INF
	for q: Vector3 in [Vector3(0, 0, 0), Vector3(0.62, 0.42, 0), Vector3(-0.62, 0.42, 0), Vector3(0, 0.42, 0.62),
			Vector3(0, 0.42, -0.62), Vector3(0.44, 0.42, 0.44), Vector3(-0.44, 0.42, -0.44), Vector3(0.44, 0.42, -0.44),
			Vector3(-0.44, 0.42, 0.44)]:
		low = minf(low, (xf * q).y)
	xf.origin = Vector3(c.x, floor_y + 0.03 - low, c.z)
	var brass := Color(0.3, 0.2, 0.075)
	var b := r.brass
	var col_pts: Array[Vector3] = []
	var col_r: Array[float] = []
	var col_c: Array[Color] = []
	for q: Array in [[0.0, 0.015], [0.04, 0.04], [0.1, 0.03], [0.2, 0.06], [0.32, 0.1], [0.42, 0.11], [0.5, 0.07],
			[0.62, 0.03], [0.74, 0.05], [0.86, 0.025], [1.0, 0.035], [1.1, 0.012]]:
		var p := xf * Vector3(0, float(q[0]), 0)
		col_pts.append(p)
		col_r.append(float(q[1]))
		col_c.append(_lit(brass, p))
	_tube(b, col_pts, col_r, 10, col_c)
	for ring: Array in [[0.42, 0.55], [0.78, 0.3], [1.0, 0.14]]:
		var pts: Array[Vector3] = []
		var rr: Array[float] = []
		var cc: Array[Color] = []
		for k in 29:
			var a := TAU * k / 28.0
			# The lower ring bent where it struck the boards.
			var dent := 1.0 - 0.18 * maxf(0.0, cos(a - 2.6)) if float(ring[0]) < 0.5 else 1.0
			var p := xf * Vector3(cos(a) * float(ring[1]) * dent, float(ring[0]), sin(a) * float(ring[1]) * dent)
			pts.append(p)
			rr.append(0.014)
			cc.append(_lit(brass, p))
		_tube(b, pts, rr, 5, cc)
	var tips: Array[Vector3] = []
	for k in 8:
		var a := TAU * k / 8.0 + 0.2
		var out := Vector3(cos(a), 0, sin(a))
		var bent := 1.0 if k != 2 else 0.6
		var pts: Array[Vector3] = []
		var rr: Array[float] = []
		var cc: Array[Color] = []
		for j in 9:
			var t := j / 8.0
			var lp := out * (0.06 + 0.6 * t * bent) + Vector3(0, 0.6 - 0.32 * t + 0.22 * t * t + 0.05 * sin(t * TAU), 0)
			var p := xf * lp
			pts.append(p)
			rr.append(0.013)
			cc.append(_lit(brass, p))
		_tube(b, pts, rr, 5, cc)
		var tip: Vector3 = pts[-1]
		tips.append(tip)
		if k != 3:
			var up := tilt * Vector3.UP
			_tube(b, [tip - up * 0.02, tip + up * 0.04, tip + up * 0.065] as Array[Vector3],
					[0.018, 0.034, 0.04] as Array[float], 8, [_lit(brass, tip), _lit(brass, tip), _lit(brass, tip)]
					as Array[Color])
	var cr := r.crystal
	var eye := Vector3(0, 1.2, 0)
	# The basket: strands from the lower ring in to the column's foot (the shape a chandelier is known by).
	for k in 16:
		var a := TAU * k / 16.0
		for j in range(1, 9):
			var t := j / 9.0
			var lp := Vector3(cos(a), 0, sin(a)) * 0.55 * (1.0 - t) + Vector3(0, 0.42 * (1.0 - t) - 0.1 * sin(t * PI), 0)
			var p := xf * lp
			p.y = maxf(p.y, floor_y + 0.02)
			_crystal(cr, p, 0.017, eye, r.rng)
	# Festoons between the arms' tips, sagging under their own weight.
	for k in 8:
		var p0 := tips[k]
		var p1 := tips[(k + 1) % 8]
		for j in range(1, 10):
			var t := j / 10.0
			var p := p0.lerp(p1, t) + Vector3(0, -0.2 * sin(t * PI), 0)
			p.y = maxf(p.y, floor_y + 0.02)
			_crystal(cr, p, 0.018, eye, r.rng)
	# Strands hanging from the upper ring and the arms' tips, down to the boards and lying along them.
	for k in 14:
		var start: Vector3 = tips[k % 8] if k < 8 else xf * (Vector3(cos(k * 1.1), 0, sin(k * 1.1)) * 0.3
				+ Vector3(0, 0.78, 0))
		var dir := Vector3(cos(k * 2.3), 0, sin(k * 2.3))
		var p := start
		for j in 12:
			if p.y > floor_y + 0.03:
				p.y = maxf(p.y - 0.045, floor_y + 0.02)
			else:
				p += dir * 0.042
				p.y = floor_y + 0.02
			_crystal(cr, p, 0.016 + 0.006 * float(j == 11), eye, r.rng)
	# Strings that came away and lie across the boards, loose drops round.
	for k in 7:
		var a := r.rng.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * r.rng.randf_range(0.6, 0.9)
		var dir := Vector3(cos(a + r.rng.randf_range(-0.8, 0.8)), 0, sin(a + r.rng.randf_range(-0.8, 0.8)))
		for j in 10:
			var q := p + dir * j * 0.04 + Vector3(0.02 * sin(j * 1.3 + k), 0, 0.02 * cos(j * 1.1))
			_crystal(cr, Vector3(q.x, floor_y + 0.02, q.z), 0.016, eye, r.rng)
	for k in 70:
		var a := r.rng.randf() * TAU
		var d := 0.55 + pow(r.rng.randf(), 1.6) * 1.8
		var q := c + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if r.puddle.has_point(Vector2(q.x, q.z)):
			continue
		_crystal(cr, Vector3(q.x, floor_y + 0.018, q.z), r.rng.randf_range(0.012, 0.024), eye, r.rng)
	# Pendants: long prisms that hung from the lower ring, lying now.
	for k in 9:
		var a := TAU * k / 9.0 + 0.3
		var p := xf * (Vector3(cos(a), 0, sin(a)) * 0.6 + Vector3(0, 0.42, 0))
		var lie := Vector3(p.x, floor_y + 0.03, p.z) + Vector3(cos(a), 0, sin(a)) * 0.1
		_prism(cr, lie, Vector3(cos(a), 0.05, sin(a)).normalized(), 0.1, eye, r.rng)
	# The chain's end from its crown, along the boards.
	var link: Vector3 = xf * Vector3(0, 1.1, 0)
	for k in 22:
		var basis := Basis(Vector3.UP, 0.4 + PI * 0.5 * (k % 2)) * Basis(Vector3.BACK, PI * 0.5)
		link = Vector3(link.x - 0.044, maxf(link.y - 0.035, floor_y + 0.012), link.z + 0.016 * sin(k * 0.4))
		_link(b, link, basis)
	r.shapes.append(PhysicsShapes.box(c + Vector3(0, 0.3, 0), Vector3(1.2, 0.6, 1.2)))


## A crystal drop: an octahedron, its facets lit by the Moon where they would send its light to the stalls (a glint,
## fixed), the others faint; now and then a facet in a prism's colour.
static func _crystal(b: RoomMesh, at: Vector3, size: float, eye: Vector3, rng: RandomNumberGenerator) -> void:
	var axes: Array[Vector3] = [Vector3(size, 0, 0), Vector3(0, size * 1.4, 0), Vector3(0, 0, size)]
	var turn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.6))
	var moon := MOON_DIR.normalized()
	var lit := moon_light(at)
	var keep := b.colour
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var p0 := at + turn * (axes[0] * sx)
				var p1 := at + turn * (axes[1] * sy)
				var p2 := at + turn * (axes[2] * sz)
				var n := (p1 - p0).cross(p2 - p0).normalized()
				if n.dot((p0 + p1 + p2) / 3.0 - at) < 0.0:
					n = -n
				var view := (eye - at).normalized()
				var half := (moon + view).normalized()
				var glint := pow(maxf(n.dot(half), 0.0), 40.0) * lit
				var c := Color(0.03, 0.035, 0.05) + Color(0.9, 0.95, 1.0) * (0.16 * lit + 1.2 * glint)
				var hue := rng.randf()
				if hue < 0.06 and glint > 0.05:
					c *= Color(1.3, 0.7, 0.5)
				elif hue < 0.12 and glint > 0.05:
					c *= Color(0.6, 0.8, 1.4)
				b.colour = c
				var base: int = b._current.verts.size()
				b._vertex(p0, n, Vector2.ZERO)
				b._vertex(p1, n, Vector2.ZERO)
				b._vertex(p2, n, Vector2.ZERO)
				b._triangle(base, base + 1, base + 2, p0, p1, p2, n)
	b.colour = keep


## A long crystal prism lying along `dir`: six sides, two points.
static func _prism(b: RoomMesh, at: Vector3, dir: Vector3, length: float, eye: Vector3, rng: RandomNumberGenerator) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir).normalized()
	var lit := moon_light(at)
	var moon := MOON_DIR.normalized()
	var a := at - dir * length * 0.5
	var e := at + dir * length * 0.5
	var keep := b.colour
	for k in 6:
		var t0 := TAU * k / 6.0
		var t1 := TAU * (k + 1) / 6.0
		var o0 := (side * cos(t0) + up * sin(t0)) * 0.012
		var o1 := (side * cos(t1) + up * sin(t1)) * 0.012
		var n := (o0 + o1).normalized()
		var half := (moon + (eye - at).normalized()).normalized()
		var glint := pow(maxf(n.dot(half), 0.0), 16.0) * lit
		b.colour = Color(0.05, 0.06, 0.08) + Color(0.9, 0.95, 1.0) * (0.12 * lit + 2.0 * glint)
		var base: int = b._current.verts.size()
		for q: Vector3 in [a + o0 + dir * 0.015, e + o0 - dir * 0.015, e + o1 - dir * 0.015, a + o1 + dir * 0.015]:
			b._vertex(q, n, Vector2.ZERO)
		b._triangle(base, base + 1, base + 2, a + o0, e + o0, e + o1, n)
		b._triangle(base, base + 2, base + 3, a + o0, e + o1, a + o1, n)
		for tip: Vector3 in [a, e]:
			var bt: int = b._current.verts.size()
			var inward := dir * (0.015 if tip == a else -0.015)
			var tn := (n + (tip - at).normalized()).normalized()
			b._vertex(tip, tn, Vector2.ZERO)
			b._vertex(tip + o0 + inward, tn, Vector2.ZERO)
			b._vertex(tip + o1 + inward, tn, Vector2.ZERO)
			b._triangle(bt, bt + 1, bt + 2, tip, tip + o0 + inward, tip + o1 + inward, tn)
	b.colour = keep
	rng.randf()


## Rubble: plaster in slabs and crumbs under the ceiling's broken edge (heaped where it fell), laths, slates and
## bricks under the walls' broken tops; all low, on the boards.
static func _rubble(r: Ruin) -> void:
	var placed := 0
	var tries := 0
	while placed < 170 and tries < 1500:
		tries += 1
		var x := r.rng.randf_range(r.lo.x + 0.2, r.hi.x - 0.2)
		var z := r.rng.randf_range(EDGE_Z - 2.8, riser_z(r, x) - 0.15)
		var near_edge := absf(z - edge_z(x) + 0.4) < 0.9 + 0.5 * _n(x * 0.7, 3.0, 201)
		var by_wall := absf(x) > 6.9
		if not near_edge and not by_wall and r.rng.randf() < 0.9:
			continue
		if r.puddle.grow(0.1).has_point(Vector2(x, z)) or _taken(r, Vector2(x, z), 0.08):
			continue
		var kind := r.rng.randf()
		var basis := Basis(Vector3.UP, r.rng.randf() * TAU) * Basis(Vector3.RIGHT, r.rng.randf_range(-0.35, 0.35)) \
				* Basis(Vector3.BACK, r.rng.randf_range(-0.3, 0.3))
		var dirt := 0.45 + 0.35 * r.rng.randf()
		if kind < 0.65:
			# Plaster: mostly small pieces and crumbs, a few slabs; the painted face up on some.
			var w := r.rng.randf_range(0.04, 0.14) if r.rng.randf() < 0.75 else r.rng.randf_range(0.15, 0.3)
			var t := r.rng.randf_range(0.02, 0.045)
			var col := CEILING_WHITE * dirt if r.rng.randf() < 0.6 else Color(0.2, 0.18, 0.15) * dirt
			_box(r.plaster, Vector3(x, r.lo.y + t * 0.4, z), Vector3(w, t, w * r.rng.randf_range(0.5, 1.0)), basis,
					col, [Vector3.DOWN])
			for j in 3:
				var cx := x + r.rng.randf_range(-0.15, 0.15)
				var cz := z + r.rng.randf_range(-0.15, 0.15)
				var cs := r.rng.randf_range(0.015, 0.035)
				_box(r.plaster, Vector3(cx, r.lo.y + cs * 0.4, cz), Vector3(cs, cs * 0.7, cs), basis, col * 0.9,
						[Vector3.DOWN])
		elif kind < 0.82:
			_box(r.wood, Vector3(x, r.lo.y + 0.01, z), Vector3(r.rng.randf_range(0.3, 0.9), 0.008, 0.026), basis,
					TIMBER * 0.45, [Vector3.DOWN])
		elif kind < 0.92 or not by_wall:
			_box(r.wood, Vector3(x, r.lo.y + 0.008, z), Vector3(0.26, 0.012, 0.44), basis, SLATE * 1.1, [Vector3.DOWN])
		else:
			_box(r.brick, Vector3(x, r.lo.y + 0.035, z), Vector3(0.22, 0.07, 0.11), basis, BRICK * 0.7,
					[Vector3.DOWN])
		placed += 1
	# A heap at the left wall's foot under its broken top, bricks and mortar.
	for k in 30:
		var z := r.rng.randf_range(-0.6, 1.4)
		var x := r.lo.x + r.rng.randf_range(0.12, 0.75)
		var y := floor_at(r, z)
		var basis := Basis(Vector3.UP, r.rng.randf() * TAU) * Basis(Vector3.RIGHT, r.rng.randf_range(-0.5, 0.5))
		_box(r.brick, Vector3(x, y + 0.035 + 0.1 * (1.0 - (x - r.lo.x) / 0.75) * r.rng.randf(), z),
				Vector3(0.22, 0.07, 0.11), basis, BRICK * (0.5 + 0.3 * r.rng.randf()), [Vector3.DOWN])


## The side aisles' carpet runner, rotted to the boards: pieces on the treads, ragged, holes through.
static func _carpet(r: Ruin) -> void:
	if r.L == null:
		return
	for s: float in [-1.0, 1.0]:
		var x0: float = s * (r.L.block_x + 0.2)
		var x1: float = s * (r.hi.x - 0.25)
		for row in range(-r.L.rows_back, r.L.rows_front + 1):
			var zf: float = r.L.arc_z(r.L.row_radius(row) - r.L.depth * 0.5, r.L.block_x)
			var zb: float = r.L.arc_z(r.L.row_radius(row) + r.L.depth * 0.5, r.L.block_x)
			var zm := (zf + zb) * 0.5
			for tread: Array in [[zm, zb, r.L.row_floor(row)], [zf, zm, r.L.row_floor(row) - r.L.rise * 0.5]]:
				var za: float = tread[0]
				var zc: float = tread[1]
				var y: float = tread[2] + 0.006
				var origin := Vector3(0, y, 0)
				var seed_v := row * 7 + int(s * 3.0) + int(za * 10.0)
				var mask := func(x: float, z: float) -> float:
					var m := minf(minf(absf(x) - absf(x0) - 0.02, absf(x1) - absf(x)), minf(z - za - 0.02, zc - z - 0.02))
					return minf(m, 0.12 - maxf(0.0, _n(x * 2.2, z * 2.2, 191 + seed_v)) * 0.35)
				var col := func(x: float, z: float) -> Color:
					return VELVET * 1.2 * (0.7 + 0.5 * _n(x * 3.0, z * 3.0, 193)) * (1.0 - 0.3 * moon_light(Vector3(x,
							y, z)))
				_masked(r.cloth, origin, Vector3.RIGHT, Vector3.BACK, Vector3.UP, minf(x0, x1), maxf(x0, x1), za, zc,
						0.12, mask, col, 0.0, 0.006)


## Leaves on the seats' cushions here and there (more under the open roof), none on a broken or tipped seat.
static func _seat_leaves(r: Ruin) -> void:
	for i in r.seats.size():
		if i in r.skip_seats or r.seats[i].origin.length() < 0.05:
			continue
		var st := r.seats[i]
		var lit := moon_light(st * Vector3(0, 0.6, 0))
		if r.rng.randf() > 0.25 + 0.45 * lit:
			continue
		for k in 1 + r.rng.randi() % 4:
			var p := st * Vector3(r.rng.randf_range(-0.2, 0.2), 0.535, r.rng.randf_range(-0.28, 0.12))
			var a := r.rng.randf() * TAU
			var size := r.rng.randf_range(0.045, 0.075)
			_leaf(r.leaves, p, Vector3(cos(a), 0, sin(a)) * size, size * 0.7, Vector3.UP,
					_lit(LITTER[r.rng.randi() % LITTER.size()], p))


## A birch twig weeping from p0, its leaves along it (none low over the seats: the sight lines).
static func _twig(r: Ruin, p0: Vector3, out: Vector3, hang: float) -> void:
	var dir := (Vector3.DOWN * 0.85 + out * 0.3 + Vector3(r.rng.randf_range(-0.35, 0.35), 0, r.rng.randf_range(-0.35,
			0.35))).normalized()
	var s := 0.05
	while s < hang:
		var lp := p0 + dir * s + Vector3(r.rng.randf_range(-0.04, 0.04), 0, r.rng.randf_range(-0.04, 0.04))
		if lp.y < 3.4:
			break
		var facing := Vector3(r.rng.randf_range(-1, 1), r.rng.randf_range(-0.2, 1.0), r.rng.randf_range(-1,
				1)).normalized()
		var size := r.rng.randf_range(0.05, 0.085)
		var along := (dir - facing * dir.dot(facing)).normalized() * size
		var c := LEAF * (0.7 + 0.6 * r.rng.randf())
		var turn := r.rng.randf()
		if turn < 0.2:
			c = Color(0.3, 0.22, 0.03) * (0.7 + 0.5 * r.rng.randf())
		elif turn < 0.35:
			c = c.lerp(Color(0.22, 0.2, 0.03), 0.6)
		_leaf(r.leaves, lp, along, size * 0.85, facing, _lit(c, lp), true)
		s += r.rng.randf_range(0.045, 0.075)


## The walls' thickness: their outer faces and their broken tops. From inside the tops show their thickness against
## the sky; the outer faces keep the bake's bounced light (and any light from outside) from coming through a face's
## back.
static func _wall_backs(r: Ruin) -> void:
	var t := WALL_T
	var dark := func(_a: float, _v: float) -> Color: return BRICK * 0.3
	var bottom := func(_a: float) -> float: return r.lo.y - 0.05
	for side: float in [-1.0, 1.0]:
		var top := func(a: float) -> float: return wall_top(side, clampf(a, r.lo.z, r.hi.z))
		var origin := Vector3(side * (r.hi.x + t), 0, 0)
		var n := Vector3(side, 0, 0)
		if side < 0.0:
			_sheet(r.brick, origin, Vector3.BACK, Vector3.UP, n, r.lo.z - t, -8.05, bottom, top, 1.0, 4, dark)
			_sheet(r.brick, origin, Vector3.BACK, Vector3.UP, n, -8.05, -6.85, func(_a: float) -> float: return 2.0,
					top, 0.6, 3, dark)
			_sheet(r.brick, origin, Vector3.BACK, Vector3.UP, n, -6.85, r.hi.z + t, bottom, top, 0.5, 4, dark)
		else:
			_sheet(r.brick, origin, Vector3.BACK, Vector3.UP, n, r.lo.z - t, r.hi.z + t, bottom, top, 0.5, 4, dark)
		# The top: from the inner face's line to the outer's.
		var inner := PackedVector3Array()
		var outer := PackedVector3Array()
		var ups := PackedVector3Array()
		var z := r.lo.z
		while z <= r.hi.z + 0.01:
			var y := wall_top(side, z)
			inner.append(Vector3(side * r.hi.x, y, z))
			outer.append(Vector3(side * (r.hi.x + t), y, z))
			ups.append(Vector3.UP)
			z += 0.25
		var keep := r.brick.colour
		r.brick.colour = BRICK * 0.55
		r.brick.strip(inner, outer, ups)
		r.brick.colour = keep
	# The rear wall's outside and the gable's broken top.
	var walk := floor_at(r, r.hi.z - 0.1)
	var gt := func(a: float) -> float: return gable_top(a)
	var rb := func(_a: float) -> float: return walk - 0.05
	var origin := Vector3(0, 0, r.hi.z + t)
	_sheet(r.brick, origin, Vector3.RIGHT, Vector3.UP, Vector3.BACK, r.lo.x - t, -7.6, rb, gt, 0.5, 4, dark)
	_sheet(r.brick, origin, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -7.6, -6.4, func(_a: float) -> float:
			return walk + 2.25, gt, 0.6, 3, dark)
	_sheet(r.brick, origin, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -6.4, r.hi.x + t, rb, gt, 0.5, 4, dark)
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	var ups := PackedVector3Array()
	var x := r.lo.x
	while x <= r.hi.x + 0.01:
		var y := gable_top(x)
		inner.append(Vector3(x, y, r.hi.z))
		outer.append(Vector3(x, y, r.hi.z + t))
		ups.append(Vector3.UP)
		x += 0.25
	var keep := r.brick.colour
	r.brick.colour = BRICK * 0.55
	r.brick.strip(inner, outer, ups)
	r.brick.colour = keep


## The Moon's and the sky's light at a vertex (0..1): the Moon where its ray gets out through the open roof, by the
## face's angle to it; the sky's share under the opening, more on what faces up.
static func vertex_light(p: Vector3, n: Vector3) -> float:
	var d := MOON_DIR.normalized()
	var lam := n.dot(d)
	var a := 0.0
	if lam > 0.0:
		a = moon_light(p + n * 0.03) * lam
	return clampf(a + SKY_SHARE * sky_light(p, n), 0.0, 1.0)


## The sky's light at p through the open roof (0..1): under the opening, less near the walls and low down beside them.
static func sky_light(p: Vector3, n: Vector3) -> float:
	var open := smoothstep(edge_z(p.x) - 0.3, edge_z(p.x) + 1.8, p.z) * smoothstep(5.75, 5.6, p.z)
	var up := 0.3 + 0.7 * maxf(n.y, 0.0)
	var walls := smoothstep(0.0, 2.5, 8.0 - absf(p.x) + p.y * 0.3) * smoothstep(0.0, 2.5, 5.65 - p.z + p.y * 0.3)
	return open * up * walls


## Every vertex of a baked mesh: its alpha the light at it (vertex_light()).
static func moon_alpha(b: RoomMesh) -> void:
	for surf: Variant in b._surfaces.values():
		var verts: PackedVector3Array = surf.verts
		var norms: PackedVector3Array = surf.normals
		var cols: PackedColorArray = surf.colours
		for i in verts.size():
			var c := cols[i]
			c.a = vertex_light(verts[i], norms[i])
			cols[i] = c
		surf.colours = cols


## The front roof's left slope with its hole: boards underneath, slates on top, round a gap up the Moon's ray from
## the ceiling's hole; broken slates hanging at its edge.
static func _holed_slope(r: Ruin, eave: Vector3, ridge: Vector3, end: float, slope_n: Vector3) -> void:
	var b := r.wood
	var rh := Vector3(HOLE.x, CEIL, HOLE.y)
	rh += MOON_DIR / MOON_DIR.y * (roof_y(HOLE.x - 0.9) - CEIL)
	var t_mid := clampf((rh.x - eave.x) / (ridge.x - eave.x), 0.0, 1.0)
	var dt := 0.75 / absf(ridge.x - eave.x)
	var t0 := t_mid - dt
	var t1 := t_mid + dt
	var z0 := rh.z - 1.6
	var z1 := rh.z + 0.6
	var rag := func(t: float) -> float: return end + 0.35 * _n(t * 5.0, -3.0, 141) + 0.25
	# Pieces: [t from, t to, z from (or -INF: the front wall), z to (or INF: the ragged end)].
	for piece: Array in [[0.0, 1.0, -INF, z0], [0.0, 1.0, z1, INF], [0.0, t0, z0, z1], [t1, 1.0, z0, z1]]:
		var under_a := PackedVector3Array()
		var under_b := PackedVector3Array()
		var top_a := PackedVector3Array()
		var top_b := PackedVector3Array()
		var ns := PackedVector3Array()
		var tns := PackedVector3Array()
		var steps := maxi(int((float(piece[1]) - float(piece[0])) * 16.0), 1)
		for k in steps + 1:
			var t := lerpf(float(piece[0]), float(piece[1]), float(k) / steps)
			var p := eave.lerp(ridge, t)
			var za := r.lo.z if float(piece[2]) == -INF else float(piece[2])
			var zb: float = rag.call(t) if float(piece[3]) == INF else float(piece[3])
			under_a.append(Vector3(p.x, p.y - 0.03, za))
			under_b.append(Vector3(p.x, p.y - 0.03, zb))
			top_a.append(Vector3(p.x, p.y + 0.04, za))
			top_b.append(Vector3(p.x, p.y + 0.04, zb + (0.05 if float(piece[3]) == INF else 0.0)))
			ns.append(-slope_n)
			tns.append(slope_n)
		b.colour = VOID * 3.0
		b.strip(under_a, under_b, ns)
		b.colour = SLATE
		b.strip(top_b, top_a, tns)
	# Slates and a batten hanging into the gap.
	for k in 7:
		var t := r.rng.randf_range(t0, t1)
		var p := eave.lerp(ridge, t)
		var z := r.rng.randf_range(z0, z1)
		var hang := Basis(Vector3.RIGHT, r.rng.randf_range(0.7, 1.4)) * Basis(Vector3.BACK, r.rng.randf_range(-0.6, 0.6))
		if k < 2:
			_box(b, Vector3(p.x, p.y - 0.2, z0 + 0.05), Vector3(0.05, 0.025, 0.5), hang, TIMBER * 0.4)
		else:
			_box(b, Vector3(p.x, p.y - 0.12, z0 if k % 2 == 0 else z1), Vector3(0.26, 0.012, 0.4), hang, SLATE * 1.3)
	b.colour = Color.WHITE
