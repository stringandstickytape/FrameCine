extends RefCounted

## The Pink Palace's pieces (docs/environments.md, "The kit" and "Room: Pink Palace"; since 2026-11-08: "continue
## working on the environments one-by-one like you did with the bathysphere, really improving their quality,
## imagination, delight, detail, lighting and so on. Better to do a smaller number of incredible superb ones than a
## large number not so", the user, 2026-11-08). A dream palace in sugared almond colours: the hall is the inside of a
## great scallop shell. Its ribs fan out over the vault from an oval saucer dome, pink on their crests and powder
## blue in their troughs, and run down to a cornice along both walls whose hidden lamps light them from below, so
## each crest glows and each trough holds a soft coloured shadow; at the screen the shell's growth rings close round
## the picture as five fluted, scalloped arches with gilt edges, each lit from behind the next. Under the cornice a
## frieze of breaking waves, white on blue; tall arched mirrors between fluted pilasters; pink glass shell sconces; a
## balcony whose front is buttoned pink velvet with a gilt edge and little glass fans; the dome (its own kit, so its
## light is its own) with a gilt sunburst and a chandelier of glass shells. Everything is ours, drawn here from grids
## and strips; no figure anywhere, nothing borrowed.
##
## Pieces (pieces.gd dispatches here; none takes a slot, all read the auditorium's layout and the room's screen):
##   pink_hall        the walls (dado, mirrors, pilasters, sconces, the wave frieze, the cornice), the shell vault and
##                    the rear wall
##   pink_proscenium  the shell's rings round the picture, its gilt crest, the stage's shell footlights
##   pink_balcony     the balcony's buttoned front, its gilt edge and fan lamps, the soffit's downlights
##   pink_dome        the oval dome over the stalls: its rim, its gilt sunburst, the chandelier (put it in a kit of its
##                    own: the sunburst cue moves that kit's cove)
##
## Cost: by material into the kit's shared meshes. Baked (PieceStatic): the walls' plaster, the dado's marble, the
## frieze, the cornice, the pilasters, the balcony's velvet, the soffit, the rear wall. Unbaked (PieceSoft): the gilt
## (it reflects: kit/reflect.gd) and the mirrors. PieceLamps: the sconces' and fans' glass, the footlights, the
## downlights, the chandelier. PieceCove: the vault, the rings, the dome (their light per vertex, live in colour).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")

## The walls' registers, metres over the room's floor datum: the dado's height over the rake, the wave frieze, the
## cornice's mouldings and its ledge (how far it stands out from the wall), the lip on the ledge that hides the lamps,
## and where the vault leaves the wall (behind the lip).
const DADO := 1.05
const FRIEZE_FOOT := 5.85
const FRIEZE_TOP := 6.3
const CORNICE_TOP := 6.62
const LEDGE := 0.42
const LIP := 0.13
const SPRING := 6.72
## The vault: its flat crown's height and half width (the dome sits in it), and how far past the wall its quarter
## ellipse would reach (so it meets the wall at a finite slope).
const CROWN := 10.0
const FLAT := 4.6
const PAST := 0.15
## The shell's ribs over the vault (round the dome), and their depth at the walls.
const RIBS := 40
const RIB_DEPTH := 0.34
## The dome: its centre in plan (x, z), its half axes, the drum's height and the apex.
const DOME_AT := Vector2(0.0, -3.0)
const DOME_AXES := Vector2(4.3, 3.3)
const DRUM := 0.32
const DOME_TOP := 11.05
## The piers between the bays along each side wall (z), and where the walls' ornament ends at the balcony's front.
const PIERS: Array[float] = [-11.5, -8.4, -5.0, -1.6, 1.8]
const BALCONY_LINE := 3.3
## The mirrors' round heads reach this high; the mirrors stand this far over the dado.
const MIRROR_TOP := 5.15
const MIRROR_FOOT := 0.4
const MIRROR_HALF := 0.95
## The shell's rings round the picture: the first's plane, the step between them (towards the seats), how many; each
## opening a superellipse over the picture's middle (half width, top, exponent), wider and higher by a step a ring;
## the ribs across the arch.
const RING_Z := -13.45
const RING_STEP := 0.4
const RINGS := 5
const RING_HALF := 6.95
const RING_HALF_STEP := 0.6
const RING_TOP := 5.3
const RING_TOP_STEP := 0.88
const RING_EXP := 3.5
const RING_RIBS := 21
## The balcony's front: its face (z), its foot (it hides the slab's edge) and its top.
const FRONT_Z := 3.4
const FRONT_FOOT := 4.0
const FRONT_TOP := 5.28

## Sugared almond colours (sRGB; the meshes take them linear).
const PINK := Color(0.95, 0.74, 0.78)
const ROSE := Color(0.84, 0.5, 0.58)
const DEEP_ROSE := Color(0.62, 0.3, 0.38)
const BLUE := Color(0.66, 0.78, 0.92)
const DEEP_BLUE := Color(0.36, 0.48, 0.72)
const CREAM := Color(0.96, 0.9, 0.84)
const WALL := Color(0.74, 0.47, 0.52)
const MARBLE := Color(0.88, 0.7, 0.72)
const GILT := Color(1.0, 0.86, 0.6)
## Old mirror glass: dark (a mirror has no colour of its own; what it shows is the reflection's).
const MIRROR := Color(0.5, 0.4, 0.42)
const GLASS := Color(1.0, 0.7, 0.76)
const SCONCE_LIGHT := Color(1.0, 0.72, 0.7)


static func build(piece: String, c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	match piece:
		"pink_hall":
			_hall(c)
		"pink_proscenium":
			_proscenium(c)
		"pink_balcony":
			_balcony(c)
		"pink_dome":
			_dome(c)
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove]:
		b.colour = Color.WHITE


# --- Helpers ----------------------------------------------------------------------------------------------------------

static func _lin(colour: Color, alpha := 1.0) -> Color:
	var l := colour.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _layout(c: Object) -> Auditorium.Layout:
	return Auditorium.layout(c.builder_params)


## The light a lamp along a line (through `lamp`, along `axis`) gives a point facing n: the cosine (softened: plaster
## scatters) over the distance's fall-off, `reach` metres to half.
static func _lamp_w(p: Vector3, n: Vector3, lamp: Vector3, axis: Vector3, reach: float) -> float:
	var d := lamp - p
	d -= axis * d.dot(axis)
	var l := d.length()
	if l < 0.001:
		return 1.0
	var k := maxf(n.dot(d / l), 0.0)
	return pow(k, 0.6) / (1.0 + (l / reach) * (l / reach))


## The light a point lamp gives a point facing n (as _lamp_w).
static func _point_w(p: Vector3, n: Vector3, lamp: Vector3, reach: float) -> float:
	var d := lamp - p
	var l := d.length()
	if l < 0.001:
		return 1.0
	var k := maxf(n.dot(d / l), 0.0)
	return pow(k, 0.6) / (1.0 + (l / reach) * (l / reach))


## The rake's line along the side aisles: the pit's floor, then up the steps to the rear walkway (the dado follows it).
static func _rake(l: Auditorium.Layout, z: float) -> float:
	var z0 := l.arc_z(l.row_radius(l.rows_front) - l.depth * 0.5, l.block_x)
	var z1 := l.arc_z(l.row_radius(-l.rows_back) + l.depth * 0.5, l.block_x)
	var y1 := l.row_floor(-l.rows_back)
	if z <= z0:
		return l.lo.y
	if z >= z1:
		return y1
	return lerpf(l.lo.y, y1, (z - z0) / (z1 - z0))


## The vault's height over plan x: the flat crown, then a quarter ellipse down to the wall (where it is SPRING).
static func _vault_y(x: float, w: float) -> float:
	var e := absf(x) - FLAT
	if e <= 0.0:
		return CROWN
	var span := w + PAST - FLAT
	var u := minf(e / span, 0.999)
	var uw := (w - FLAT) / span
	var h := (CROWN - SPRING) / (1.0 - sqrt(1.0 - uw * uw))
	return CROWN - h * (1.0 - sqrt(1.0 - u * u))


## The vault's slope over plan x (dy/dx).
static func _vault_dy(x: float, w: float) -> float:
	var e := absf(x) - FLAT
	if e <= 0.0:
		return 0.0
	var span := w + PAST - FLAT
	var u := minf(e / span, 0.999)
	var uw := (w - FLAT) / span
	var h := (CROWN - SPRING) / (1.0 - sqrt(1.0 - uw * uw))
	return -signf(x) * h * u / (sqrt(1.0 - u * u) * span)


## A grid's normals from its points (each the cross of its row's and column's directions), turned to face `towards`
## (a callable p -> the direction the surface should face there).
static func _grid_normals(rows: Array, towards: Callable) -> Array:
	var out: Array = []
	var nr := rows.size()
	for i in nr:
		var row: PackedVector3Array = rows[i]
		var nrow := PackedVector3Array()
		var nc := row.size()
		for j in nc:
			var a: Vector3 = (rows[mini(i + 1, nr - 1)] as PackedVector3Array)[j] \
					- (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
			var b := row[mini(j + 1, nc - 1)] - row[maxi(j - 1, 0)]
			var n := a.cross(b).normalized()
			var want: Vector3 = towards.call(row[j])
			if n.length() < 0.5:
				n = want.normalized()
			elif n.dot(want) < 0.0:
				n = -n
			nrow.append(n)
		out.append(nrow)
	return out


## A wall's frame: x along the wall, y up, z out of it into the room; origin at p.
static func _wall_xf(p: Vector3, out: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), p)


static func _box(b: RoomMesh, xf: Transform3D, centre: Vector3, size: Vector3, skip: Array = []) -> void:
	b.box(xf * centre, size, xf.basis, skip)


## A round bead swept along a path of points with an outward direction at each: its section a half round of radius r
## (from straight out, round over the top and the bottom), `segs` facets.
static func _bead(b: RoomMesh, path: PackedVector3Array, outs: Array, up: Vector3, r: float, segs := 4) -> void:
	var rows: Array = []
	var norms: Array = []
	for k in segs + 1:
		var a := lerpf(-PI * 0.5, PI * 0.5, float(k) / segs)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in path.size():
			var o: Vector3 = outs[j]
			var d := (o * cos(a) + up * sin(a)).normalized()
			row.append(path[j] + d * r)
			nrow.append(d)
		rows.append(row)
		norms.append(nrow)
	b.grid(rows, norms)


## A bead along a curved edge: a half round centred on the edge, from the inward side (inward[j], in the surface's
## plane) round over `out` (off the surface) to the outward side.
static func _edge_bead(b: RoomMesh, path: PackedVector3Array, inward: Array, out: Vector3, r: float, segs := 4) -> void:
	var rows: Array = []
	var norms: Array = []
	for k in segs + 1:
		var a := PI * float(k) / segs
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in path.size():
			var d := ((inward[j] as Vector3) * cos(a) + out * sin(a)).normalized()
			row.append(path[j] + d * r)
			nrow.append(d)
		rows.append(row)
		norms.append(nrow)
	b.grid(rows, norms)


## A fan of glass (a shell lamp): its hinge at the frame's origin, opening up its y, bulging out along its z; ribs
## shaded, brighter near the lamp inside. radius, ribs, rings and segments as asked.
static func _glass_fan(b: RoomMesh, xf: Transform3D, radius: float, bulge: float, ribs := 9, segs := 14,
		rings := 4) -> void:
	var pts: Array = []
	for i in rings + 1:
		var rho := radius * float(i) / rings
		var row: Array = []
		for k in segs + 1:
			var phi := PI * k / segs
			var rib := 0.5 + 0.5 * cos(phi * ribs * 2.0)
			# Low at the hinge, full in the middle, curving back to the rim.
			var z := bulge * pow(sin(PI * clampf(rho / radius, 0.0, 1.0) * 0.82 + 0.12), 0.75) * (0.85 + 0.15 * rib) \
					+ 0.004
			# The rim scalloped: each rib's end a little further out.
			var r := rho * (1.0 + 0.06 * rib * float(i == rings))
			row.append(Vector3(cos(phi) * r, sin(phi) * r, z))
		pts.append(row)
	var rows: Array = []
	var cols: Array = []
	for i in rings + 1:
		var row := PackedVector3Array()
		var crow := PackedColorArray()
		for k in segs + 1:
			var phi := PI * k / segs
			var rib := 0.5 + 0.5 * cos(phi * ribs * 2.0)
			var bright := (0.6 + 0.4 * rib) * (1.2 - 0.6 * float(i) / rings)
			row.append(xf * (pts[i][k] as Vector3))
			crow.append(Color(bright, bright, bright))
		rows.append(row)
		cols.append(crow)
	var out := xf.basis.z.normalized()
	b.grid(rows, _grid_normals(rows, func(_p: Vector3) -> Vector3: return out), cols)


# --- The hall: walls, frieze, cornice, vault, rear wall --------------------------------------------------------------

static func _hall(c: Object) -> void:
	var l := _layout(c)
	var w := l.hi.x
	# The walls are big and their light soft (sconces' pools, the vault's glow): 14 cm a lightmap texel keeps the
	# atlas (and the bake on the headset) about half what 10 cm would.
	c.s.texel = 0.14
	var front := _ring_z(RINGS - 1)
	_walls(c, l, w, front)
	_mirrors(c, l, w)
	_pilasters(c, l, w)
	_frieze(c, w, front)
	_cornice(c, l, w, front)
	_vault(c, l, w, front)
	_rear_wall(c, l, w)
	_door_hoods(c, l, w)


## The side walls: rose marble along the rake (the dado, with a gilt bead on its moulded cap), rose plaster above it
## up behind the cornice; and the end walls of the bays.
static func _walls(c: Object, l: Auditorium.Layout, w: float, front: float) -> void:
	var plaster: Material = c.tinted("plaster")
	var marble: Material = c.tinted("stone")
	var gilt: Material = c.shiny("gilt", 1.0, 0.8, 0.22)
	var rz := l.hi.z
	# Along each wall: the rake's breaks, so the dado's top follows it exactly.
	var zs: Array[float] = [front]
	var z0 := l.arc_z(l.row_radius(l.rows_front) - l.depth * 0.5, l.block_x)
	var z1 := l.arc_z(l.row_radius(-l.rows_back) + l.depth * 0.5, l.block_x)
	zs.append_array([z0, z1, rz])
	for s: float in [-1.0, 1.0]:
		var x := s * w
		var into := Vector3(-s, 0, 0)
		for k in zs.size() - 1:
			var za := zs[k]
			var zb := zs[k + 1]
			var ya := _rake(l, za) + DADO
			var yb := _rake(l, zb) + DADO
			c.s.surface(marble)
			c.s.colour = _lin(MARBLE)
			c.s.face([Vector3(x, l.lo.y, za), Vector3(x, l.lo.y, zb), Vector3(x, yb, zb), Vector3(x, ya, za)], into)
			c.s.surface(plaster)
			c.s.colour = _lin(WALL)
			c.s.face([Vector3(x, ya, za), Vector3(x, yb, zb), Vector3(x, SPRING + 0.5, zb), Vector3(x, SPRING + 0.5, za)],
					into)
			# The dado's cap: a moulded rail of marble standing out 6 cm, a gilt bead along its top.
			var a := Vector3(x - s * 0.06, ya, za)
			var b := Vector3(x - s * 0.06, yb, zb)
			c.s.surface(marble)
			c.s.colour = _lin(MARBLE.lightened(0.15))
			c.s.face([a + Vector3.DOWN * 0.12, b + Vector3.DOWN * 0.12, b, a], into)
			c.s.face([a, b, Vector3(x, yb, zb), Vector3(x, ya, za)], Vector3.UP)
			c.s.face([a + Vector3.DOWN * 0.12, b + Vector3.DOWN * 0.12, Vector3(x, yb - 0.12, zb),
					Vector3(x, ya - 0.12, za)], Vector3.DOWN)
			c.u.surface(gilt)
			c.u.colour = _lin(GILT)
			_bead(c.u, PackedVector3Array([a + Vector3(s * 0.01, 0.0, 0.0), b + Vector3(s * 0.01, 0.0, 0.0)]),
					[into, into], Vector3.UP, 0.018, 3)
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


## The mirrors in the bays (all but the first, which holds the exit, and the short last one): round-headed, from just
## over the dado to MIRROR_TOP, framed in a gilt bead and a pink plaster architrave, a shell over each. Faint old glass
## (the reflecting shader at a low amount, rose-gold, a little foxed): it shows the hall's light and, faintly, the
## picture.
static func _mirrors(c: Object, l: Auditorium.Layout, w: float) -> void:
	# Old glass: it reflects softly (rough: the hall's light, not a sharp picture of a world it does not have), in
	# panes between thin gilt glazing bars.
	var glass: Material = c.shiny("chrome", 1.0, 0.9, 0.3)
	var gilt: Material = c.shiny("gilt", 1.0, 0.8, 0.22)
	var plaster: Material = c.tinted("plaster")
	for k in range(1, PIERS.size() - 1):
		var zc := (PIERS[k] + PIERS[k + 1]) * 0.5
		var foot := _rake(l, zc + MIRROR_HALF) + DADO + MIRROR_FOOT
		var head_c := MIRROR_TOP - MIRROR_HALF
		for s: float in [-1.0, 1.0]:
			var into := Vector3(-s, 0, 0)
			var xf := _wall_xf(Vector3(s * w, 0.0, zc), into)
			var outline := _arch_outline(MIRROR_HALF, foot, head_c, 14)
			# The glass: rows up it (across the head, as wide as the arch is there), a little foxed towards its sides
			# and its foot (vertex colour: darker, warmer).
			c.u.surface(glass)
			var rows: Array = []
			var cols: Array = []
			var ys: Array[float] = []
			var y := foot
			while y < head_c:
				ys.append(y)
				y += 0.5
			for k2 in 9:
				ys.append(head_c + MIRROR_HALF * sin(PI * 0.5 * float(k2) / 8.0))
			for yy in ys:
				var half := MIRROR_HALF if yy <= head_c else sqrt(maxf(MIRROR_HALF * MIRROR_HALF
						- (yy - head_c) * (yy - head_c), 0.0))
				var row := PackedVector3Array()
				var crow := PackedColorArray()
				# Across: the bevel round the edge (a narrow band that catches the light), then the plate.
				for u: float in [-1.0, -0.94, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 0.94, 1.0]:
					row.append(xf * Vector3(u * half, yy, 0.025))
					var fox := 1.0 + 0.6 * smoothstep(0.9, 1.0, absf(u)) - 0.15 * exp(-(yy - foot) / 0.5)
					crow.append(_lin(MIRROR * Color(fox, fox * 0.97, fox * 0.95)))
				rows.append(row)
				cols.append(crow)
			var norms: Array = []
			for r: PackedVector3Array in rows:
				norms.append(_fill_n(r.size(), into))
			c.u.grid(rows, norms, cols)
			# The architrave: a flat band of pale plaster round it, 16 cm, standing 4 cm off the wall.
			var outer := _arch_outline(MIRROR_HALF + 0.16, foot - 0.16, head_c, 14)
			var ra := PackedVector3Array()
			var rb := PackedVector3Array()
			var nn := PackedVector3Array()
			for j in outline.size():
				ra.append(xf * Vector3(outline[j].x, outline[j].y, 0.04))
				rb.append(xf * Vector3(outer[j].x, outer[j].y, 0.04))
				nn.append(into)
			c.s.surface(plaster)
			c.s.colour = _lin(CREAM)
			c.s.strip(ra, rb, nn)
			# Its outer edge's return to the wall, and the reveal down to the glass.
			var rc := PackedVector3Array()
			var rd := PackedVector3Array()
			var re := PackedVector3Array()
			var on := PackedVector3Array()
			var inn := PackedVector3Array()
			for j in outline.size():
				rc.append(xf * Vector3(outer[j].x, outer[j].y, 0.0))
				rd.append(xf * Vector3(outline[j].x, outline[j].y, 0.025))
				re.append(xf * Vector3(outline[j].x, outline[j].y, 0.04))
				var o2 := (outer[j] - Vector2(0.0, head_c)).normalized() if outer[j].y > head_c \
						else Vector2(signf(outer[j].x), 0.0)
				on.append((xf.basis * Vector3(o2.x, o2.y, 0.0)).normalized())
				inn.append((xf.basis * Vector3(-o2.x, -o2.y, 0.0)).normalized())
			c.s.strip(rc, rb, on)
			c.s.colour = _lin(CREAM.darkened(0.15))
			c.s.strip(rd, re, inn)
			# A gilt bead round the glass.
			c.u.surface(gilt)
			c.u.colour = _lin(GILT)
			var bead := PackedVector3Array()
			var ins: Array = []
			for j in outline.size():
				bead.append(xf * Vector3(outline[j].x, outline[j].y, 0.04))
				ins.append(inn[j])
			_edge_bead(c.u, bead, ins, into, 0.022, 4)
			# The glazing bars: two uprights, and a bar across every 0.62 m up to the head's spring.
			for bx: float in [-MIRROR_HALF / 3.0, MIRROR_HALF / 3.0]:
				var top := head_c + sqrt(MIRROR_HALF * MIRROR_HALF - bx * bx)
				_box(c.u, xf, Vector3(bx, (foot + top) * 0.5, 0.03), Vector3(0.045, top - foot, 0.014),
						[RoomMesh.BACK])
			var by := foot + 0.62
			while by < head_c - 0.1:
				_box(c.u, xf, Vector3(0.0, by, 0.03), Vector3(MIRROR_HALF * 2.0, 0.045, 0.014), [RoomMesh.BACK])
				by += 0.62
			# Over the head, a gilt shell (a fan of eleven ribs).
			_relief_fan(c.u, xf * Transform3D(Basis(), Vector3(0.0, MIRROR_TOP + 0.04, 0.05)), 0.42, 0.07, 11)
			c.shapes.append(PhysicsShapes.box(xf * Vector3(0.0, (foot + MIRROR_TOP) * 0.5, 0.03),
					Vector3(MIRROR_HALF * 2.0 + 0.3, MIRROR_TOP - foot + 0.3, 0.06), xf.basis.orthonormalized()))
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


## A round-headed arch's outline (x, y): up one side from the foot, round the head (its centre at head_c), down the
## other.
static func _arch_outline(half: float, foot: float, head_c: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(-half, foot))
	for k in segs + 1:
		var a := PI - PI * float(k) / segs
		pts.append(Vector2(cos(a) * half, head_c + sin(a) * half))
	pts.append(Vector2(half, foot))
	return pts


## A gilt shell in relief: a fan opening up from its hinge at the frame's origin, ribbed, standing out along z.
static func _relief_fan(b: RoomMesh, xf: Transform3D, radius: float, depth: float, ribs: int) -> void:
	var segs := ribs * 2 + 2
	var rows: Array = []
	for i in 4:
		var rho := radius * (0.12 + 0.88 * float(i) / 3.0)
		var row := PackedVector3Array()
		for k in segs + 1:
			var phi := PI * float(k) / segs
			var rib := 0.5 + 0.5 * cos(phi * ribs * 2.0)
			var r := rho * (1.0 + 0.07 * rib * float(i == 3))
			var z := depth * (0.35 + 0.65 * rib) * (1.0 - 0.75 * float(i == 3)) * (0.6 + 0.4 * float(i) / 3.0)
			row.append(xf * Vector3(cos(phi) * r, sin(phi) * r, z))
		rows.append(row)
	var out := xf.basis.z.normalized()
	b.grid(rows, _grid_normals(rows, func(_p: Vector3) -> Vector3: return out))
	# The hinge: a small boss.
	var boss := PackedVector3Array()
	var boss2 := PackedVector3Array()
	for k in segs + 1:
		var phi := PI * float(k) / segs
		boss.append(xf * Vector3(cos(phi) * radius * 0.12, sin(phi) * radius * 0.12, depth * 0.4))
		boss2.append(xf * Vector3(0.0, 0.0, depth * 0.5))
	b.grid([boss2, boss], [_fill_n(boss2.size(), out), _fill_n(boss.size(), out)])


## A great shell in relief drawn with the coves (PieceCove): as _relief_fan, its hollows in `ground`, its ribs gilt,
## lit from its foot (`foot_light` at the hinge, `top_light` at the rim: a lamp hidden below it).
static func _cove_fan(b: RoomMesh, xf: Transform3D, radius: float, depth: float, ribs: int, ground: Color,
		foot_light: float, top_light: float) -> void:
	var segs := ribs * 6
	var rows: Array = []
	var cols: Array = []
	var n_rings := 7
	for i in n_rings:
		var f := float(i) / (n_rings - 1)
		var rho := radius * (0.1 + 0.9 * f)
		var row := PackedVector3Array()
		var crow := PackedColorArray()
		for k in segs + 1:
			var phi := PI * float(k) / segs
			var rib := 0.5 + 0.5 * cos(phi * ribs * 2.0)
			var r := rho * (1.0 + 0.06 * rib * float(i == n_rings - 1))
			var z := depth * (0.3 + 0.7 * rib) * sin(PI * minf(f * 1.15, 1.0)) * (0.5 + 0.5 * f)
			row.append(xf * Vector3(cos(phi) * r, sin(phi) * r, z))
			var lit := lerpf(foot_light, top_light, f) * (0.55 + 0.45 * rib)
			crow.append(_lin(ground.lerp(GILT, smoothstep(0.75, 0.95, rib)), lit))
		rows.append(row)
		cols.append(crow)
	var out := xf.basis.z.normalized()
	b.grid(rows, _grid_normals(rows, func(_p: Vector3) -> Vector3: return out), cols)


static func _fill_n(count: int, n: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	out.fill(n)
	return out


## The pilasters between the bays: pale plaster, five flutes, a moulded base on the dado and a gilt shell for a
## capital under the frieze; a pink glass shell sconce on each (but the first, by the proscenium), a lamp in the bake.
static func _pilasters(c: Object, l: Auditorium.Layout, w: float) -> void:
	var plaster: Material = c.tinted("plaster")
	var gilt: Material = c.shiny("gilt", 1.0, 0.8, 0.22)
	var glass: ShaderMaterial = _glass_material(c)
	var half := 0.3
	var stand := 0.12
	for k in PIERS.size():
		var z := PIERS[k]
		var foot := _rake(l, z + half) + DADO
		for s: float in [-1.0, 1.0]:
			var into := Vector3(-s, 0, 0)
			var xf := _wall_xf(Vector3(s * w, 0.0, z), into)
			var top := FRIEZE_FOOT - 0.32
			c.s.surface(plaster)
			# The shaft: its sides, and its face fluted (five hollows between six fillets).
			c.s.colour = _lin(CREAM.darkened(0.06))
			_box(c.s, xf, Vector3(0.0, (foot + top) * 0.5, stand * 0.5), Vector3(half * 2.0, top - foot, stand),
					[RoomMesh.BACK, RoomMesh.FRONT, RoomMesh.UP, RoomMesh.DOWN])
			var rows: Array = []
			var cols: Array = []
			var xs: Array[float] = []
			var n_x := 31
			for j in n_x:
				xs.append(lerpf(-half, half, float(j) / (n_x - 1)))
			for y: float in [foot + 0.18, top - 0.05]:
				var row := PackedVector3Array()
				var crow := PackedColorArray()
				for x in xs:
					var f := fposmod((x + half) / (half * 2.0) * 5.0, 1.0)
					var inset := 0.03 * sin(PI * clampf((f - 0.12) / 0.76, 0.0, 1.0))
					row.append(xf * Vector3(x, y, stand - inset))
					var shade := 1.0 - 2.5 * inset
					crow.append(_lin(CREAM * Color(shade, shade, shade)))
				rows.append(row)
				cols.append(crow)
			# One chart (sheet, not grid): the bake lays its light on it.
			c.s.sheet(rows, _grid_normals(rows, func(_p: Vector3) -> Vector3: return into), cols, xf.basis.x,
					Vector3.UP)
			# The base (two steps) and the necking under the capital.
			c.s.colour = _lin(CREAM)
			_box(c.s, xf, Vector3(0.0, foot + 0.09, stand * 0.5 + 0.03), Vector3(half * 2.0 + 0.12, 0.18, stand + 0.06),
					[RoomMesh.BACK])
			_box(c.s, xf, Vector3(0.0, top + 0.04, stand * 0.5 + 0.02), Vector3(half * 2.0 + 0.08, 0.08, stand + 0.04),
					[RoomMesh.BACK])
			# The capital: a gilt shell fanning up under the frieze.
			c.u.surface(gilt)
			c.u.colour = _lin(GILT)
			_relief_fan(c.u, xf * Transform3D(Basis(), Vector3(0.0, top + 0.08, stand + 0.02)), 0.36, 0.08, 9)
			c.shapes.append(PhysicsShapes.box(xf * Vector3(0.0, (foot + top) * 0.5, stand * 0.5),
					Vector3(half * 2.0, top - foot, stand), xf.basis.orthonormalized()))
			if k == 0:
				continue
			# The sconce: a pink glass shell on a gilt bracket, its lamp inside.
			var sy := _rake(l, z) + DADO + 1.65
			var sxf := xf * Transform3D(Basis(), Vector3(0.0, sy, stand + 0.02))
			_box(c.u, sxf, Vector3(0.0, -0.06, 0.05), Vector3(0.1, 0.12, 0.1), [RoomMesh.BACK])
			_box(c.u, sxf, Vector3(0.0, -0.16, 0.03), Vector3(0.05, 0.1, 0.05), [RoomMesh.BACK])
			c.lit.surface(glass)
			_glass_fan(c.lit, sxf * Transform3D(Basis(), Vector3(0.0, -0.02, 0.06)), 0.26, 0.11, 9, 14, 4)
			c.glow_lights.append([sxf * Vector3(0.0, 0.1, 0.25), SCONCE_LIGHT, 0.55, 3.2])
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE
	c.lit.colour = Color.WHITE


## The shells' glass (sconces, the balcony's fans, the chandelier): the light system's lamp material, house group,
## coloured per vertex; made once.
static func _glass_material(c: Object) -> ShaderMaterial:
	var mats: Dictionary = c._mats
	if not mats.has("pink glass"):
		var g: ShaderMaterial = c.kit._lamp(GLASS, 1.4, 1.0, "house")
		g.set_shader_parameter("use_vertex_colour", true)
		mats["pink glass"] = g
	c.lit.surface(mats["pink glass"])
	return mats["pink glass"]


## The frieze under the cornice: breaking waves running towards the screen, white on powder blue, in relief (a band of
## blue, the white waves standing 2.5 cm off it), from the proscenium to the balcony's line on both walls; a gilt bead
## under it.
static func _frieze(c: Object, w: float, front: float) -> void:
	var plaster: Material = c.tinted("plaster")
	var gilt: Material = c.shiny("gilt", 1.0, 0.8, 0.22)
	var h := FRIEZE_TOP - FRIEZE_FOOT
	var unit := 0.62
	var wave := _wave_outline()
	for s: float in [-1.0, 1.0]:
		var x := s * w
		var into := Vector3(-s, 0, 0)
		var out_x := x - s * 0.07
		# The ground: blue, standing 7 cm off the wall, with its top and bottom edges.
		c.s.surface(plaster)
		c.s.colour = _lin(BLUE)
		c.s.face([Vector3(out_x, FRIEZE_FOOT, front), Vector3(out_x, FRIEZE_FOOT, BALCONY_LINE),
				Vector3(out_x, FRIEZE_TOP, BALCONY_LINE), Vector3(out_x, FRIEZE_TOP, front)], into)
		c.s.colour = _lin(BLUE.darkened(0.25))
		c.s.face([Vector3(x, FRIEZE_FOOT, front), Vector3(x, FRIEZE_FOOT, BALCONY_LINE),
				Vector3(out_x, FRIEZE_FOOT, BALCONY_LINE), Vector3(out_x, FRIEZE_FOOT, front)], Vector3.DOWN)
		c.s.face([Vector3(x, FRIEZE_FOOT, BALCONY_LINE), Vector3(out_x, FRIEZE_FOOT, BALCONY_LINE),
				Vector3(out_x, FRIEZE_TOP, BALCONY_LINE), Vector3(x, FRIEZE_TOP, BALCONY_LINE)], Vector3.BACK)
		# The waves: each unit's white shape, its face and its edge (the relief's side).
		var units := int(floor((BALCONY_LINE - front) / unit))
		var start := front + ((BALCONY_LINE - front) - units * unit) * 0.5
		for k in units:
			var z0 := start + k * unit
			var pts := PackedVector3Array()
			for p: Vector2 in wave:
				# Running towards the screen: the curl leads (along -z).
				pts.append(Vector3(out_x - s * 0.025, FRIEZE_FOOT + p.y * h, z0 + unit * (1.0 - p.x)))
			c.s.colour = _lin(CREAM)
			c.s.polygon(pts, into)
			var back := PackedVector3Array()
			for p in pts:
				back.append(Vector3(out_x, p.y, p.z))
			var ns := PackedVector3Array()
			for j in pts.size():
				var a := pts[(j + pts.size() - 1) % pts.size()]
				var b := pts[(j + 1) % pts.size()]
				var t := b - a
				var n := Vector3(0, t.z, -t.y).normalized()
				ns.append(n)
			c.s.colour = _lin(CREAM.darkened(0.2))
			# The edge as one strip round the outline (closed).
			var ea := PackedVector3Array(pts)
			var eb := PackedVector3Array(back)
			var en := PackedVector3Array(ns)
			ea.append(pts[0])
			eb.append(back[0])
			en.append(ns[0])
			_edge_strip(c.s, ea, eb, en, into)
		# The gilt bead under the frieze, and a fine one over it.
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		for y: float in [FRIEZE_FOOT - 0.02, FRIEZE_TOP + 0.015]:
			_bead(c.u, PackedVector3Array([Vector3(out_x, y, front), Vector3(out_x, y, BALCONY_LINE)]), [into, into],
					Vector3.UP, 0.022 if y < FRIEZE_TOP else 0.015, 3)
		c.shapes.append(PhysicsShapes.box(Vector3(s * (w - 0.04), (FRIEZE_FOOT + FRIEZE_TOP) * 0.5,
				(front + BALCONY_LINE) * 0.5), Vector3(0.08, h, BALCONY_LINE - front), Basis()))
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


## The relief's edge: quads between the outline on the face and on the ground, each facing out of the shape (its own
## normal from the outline, so a curl's underside faces down), skipping any that face the wall.
static func _edge_strip(b: RoomMesh, ea: PackedVector3Array, eb: PackedVector3Array, en: PackedVector3Array,
		into: Vector3) -> void:
	for j in ea.size() - 1:
		var n := (en[j] + en[j + 1]).normalized()
		if n.dot(into) < -0.5:
			continue
		b.face([ea[j], ea[j + 1], eb[j + 1], eb[j]], n)


## One wave of the frieze (x along the unit 0..1, y up its height 0..1): the white shape under a breaking wave, a back
## rising from the trough to the crest, the crest curling forward over a hollow into a tongue, the face dropping
## under it to the next trough. Counter-clockwise, simple (it never crosses itself).
static func _wave_outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, 0.0))
	pts.append(Vector2(1.0, 0.0))
	pts.append(Vector2(1.0, 0.18))
	# The face under the curl, back towards the hollow (right to left).
	pts.append(Vector2(0.9, 0.2))
	pts.append(Vector2(0.8, 0.26))
	pts.append(Vector2(0.72, 0.36))
	pts.append(Vector2(0.69, 0.46))
	# The hollow: up under the tongue.
	pts.append(Vector2(0.71, 0.54))
	pts.append(Vector2(0.76, 0.57))
	# The tongue: out and down to its tip, then round over the top back to the crest.
	pts.append(Vector2(0.82, 0.55))
	pts.append(Vector2(0.86, 0.5))
	pts.append(Vector2(0.91, 0.5))
	pts.append(Vector2(0.93, 0.56))
	pts.append(Vector2(0.92, 0.66))
	pts.append(Vector2(0.87, 0.76))
	pts.append(Vector2(0.79, 0.84))
	pts.append(Vector2(0.69, 0.88))
	pts.append(Vector2(0.58, 0.87))
	# The back, falling to the trough.
	pts.append(Vector2(0.46, 0.8))
	pts.append(Vector2(0.33, 0.65))
	pts.append(Vector2(0.2, 0.42))
	pts.append(Vector2(0.1, 0.26))
	pts.append(Vector2(0.0, 0.18))
	return pts


## The cornice over the frieze: mouldings stepping out to a ledge, a lip on the ledge with a gilt bead, and behind the
## lip the lamps that light the vault (they are the vault's light; for the bake, one hidden light a bay a side lays the
## glow down the upper wall). It runs the hall's length on both walls, over the balcony too.
static func _cornice(c: Object, l: Auditorium.Layout, w: float, front: float) -> void:
	var plaster: Material = c.tinted("plaster")
	var gilt: Material = c.shiny("gilt", 1.0, 0.8, 0.22)
	var rz := l.hi.z
	# The profile (out from the wall, up): a cyma under a flat soffit, then the ledge's front.
	var prof: Array = [Vector2(0.0, FRIEZE_TOP + 0.02), Vector2(0.1, FRIEZE_TOP + 0.03), Vector2(0.14, FRIEZE_TOP + 0.08),
			Vector2(0.22, FRIEZE_TOP + 0.14), Vector2(0.3, FRIEZE_TOP + 0.17), Vector2(LEDGE, FRIEZE_TOP + 0.18),
			Vector2(LEDGE, CORNICE_TOP), Vector2(LEDGE, CORNICE_TOP + LIP), Vector2(LEDGE - 0.05, CORNICE_TOP + LIP)]
	var shades: Array[float] = [0.7, 0.75, 0.82, 0.9, 0.95, 0.9, 1.0, 1.0, 0.9]
	for s: float in [-1.0, 1.0]:
		var x := s * w
		c.s.surface(plaster)
		for k in prof.size() - 1:
			var a: Vector2 = prof[k]
			var b: Vector2 = prof[k + 1]
			var t := b - a
			var n2 := Vector2(t.y, -t.x).normalized()
			if n2.x < 0.0:
				n2 = -n2
			var n := Vector3(-s * n2.x, n2.y, 0.0).normalized()
			c.s.colour = _lin(CREAM * Color(shades[k], shades[k], shades[k]))
			c.s.face([Vector3(x - s * a.x, a.y, front), Vector3(x - s * a.x, a.y, rz), Vector3(x - s * b.x, b.y, rz),
					Vector3(x - s * b.x, b.y, front)], n)
		# The ledge's top behind the lip (the lamps lie on it): it faces up, out of sight.
		c.s.colour = _lin(CREAM.darkened(0.3))
		c.s.face([Vector3(x, CORNICE_TOP, front), Vector3(x, CORNICE_TOP, rz), Vector3(x - s * LEDGE, CORNICE_TOP, rz),
				Vector3(x - s * LEDGE, CORNICE_TOP, front)], Vector3.UP)
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		var into := Vector3(-s, 0, 0)
		_bead(c.u, PackedVector3Array([Vector3(x - s * LEDGE, CORNICE_TOP + LIP, front),
				Vector3(x - s * LEDGE, CORNICE_TOP + LIP, rz)]), [into, into], Vector3.UP, 0.028, 4)
		_bead(c.u, PackedVector3Array([Vector3(x - s * LEDGE, FRIEZE_TOP + 0.18, front),
				Vector3(x - s * LEDGE, FRIEZE_TOP + 0.18, rz)]), [into, into], Vector3.UP, 0.02, 3)
		c.shapes.append(PhysicsShapes.box(Vector3(s * (w - LEDGE * 0.5), (FRIEZE_TOP + CORNICE_TOP) * 0.5,
				(front + rz) * 0.5), Vector3(LEDGE, CORNICE_TOP - FRIEZE_TOP + LIP, rz - front), Basis()))
		# For the bake: the glow off the lit vault comes down the upper walls.
		var z := front + 1.5
		while z < rz - 1.0:
			c.glow_lights.append([Vector3(s * (w - 1.1), SPRING - 0.35, z), Color(1.0, 0.72, 0.76), 0.3, 3.5])
			z += 3.6
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


## The shell vault: from the dome's rim the ribs fan out over the crown and down the quarter ellipses to the cornice,
## to ring 4 of the proscenium and to the rear wall, deepening as they go. Pink on the crests, powder blue in the
## troughs; the cornice's lamps light them from below at a grazing angle (each crest's flank towards the lamp bright,
## the troughs in shadow), a little of the chandelier's light round the dome. A gilt line along every crest: the
## sunburst's rays. PieceCove, its light per vertex.
static func _vault(c: Object, l: Auditorium.Layout, w: float, front: float) -> void:
	var b: RoomMesh = c.cove
	b.surface(c.kit.cove_material())
	var rz := l.hi.z
	var cols_per_rib := 6
	var n_cols := RIBS * cols_per_rib
	var ss: Array[float] = [0.0, 0.02, 0.06, 0.12, 0.2, 0.29, 0.39, 0.5, 0.6, 0.69, 0.77, 0.84, 0.89, 0.93, 0.96, 0.98,
			0.993, 1.0]
	var rows: Array = []
	var cols: Array = []
	var crests: Array = []
	for i in ss.size():
		var row := PackedVector3Array()
		var crow := PackedColorArray()
		for j in n_cols + 1:
			var phi := TAU * float(j % n_cols) / n_cols
			var p := _vault_point(phi, ss[i], w, front, rz)
			row.append(p)
		rows.append(row)
		cols.append(crow)
	var norms := _grid_normals(rows, func(p: Vector3) -> Vector3:
		return (Vector3(0.0, 2.0, p.z) - p).normalized())
	var chandelier := Vector3(DOME_AT.x, 9.0, DOME_AT.y)
	for i in ss.size():
		var row: PackedVector3Array = rows[i]
		var nrow: PackedVector3Array = norms[i]
		var crow: PackedColorArray = cols[i]
		for j in row.size():
			var phi := TAU * float(j % n_cols) / n_cols
			var crest := 0.5 + 0.5 * cos(RIBS * phi)
			var p := row[j]
			var n := nrow[j]
			var k := 0.0
			for s: float in [-1.0, 1.0]:
				k += 1.25 * _lamp_w(p, n, Vector3(s * (w - LEDGE + 0.12), CORNICE_TOP + 0.08, 0.0), Vector3.BACK, 2.4)
			k += 0.35 * _point_w(p, n, chandelier, 3.2)
			k *= 0.45 + 0.55 * pow(crest, 1.5)
			# The plaster's own glow: a little everywhere, so the crown is never black.
			k += 0.06 + 0.05 * crest
			var colour := BLUE.lerp(PINK, pow(crest, 0.8))
			crow.append(_lin(colour, k))
		cols[i] = crow
	b.grid(rows, norms, cols)
	# The rays: a gilt line along each crest, from the dome's rim to the wall. Drawn with the vault (PieceCove): gilt
	# catching the cornice's light where the crest does, brighter than the plaster (a gilt reflecting a dark hall from
	# a thin strip facing down reads as a dark seam).
	for r in RIBS:
		var phi := TAU * float(r) / RIBS
		var ra := PackedVector3Array()
		var rb := PackedVector3Array()
		var nn := PackedVector3Array()
		var rc := PackedColorArray()
		var j := r * cols_per_rib
		for i in ss.size():
			if ss[i] < 0.02:
				continue
			var p: Vector3 = (rows[i] as PackedVector3Array)[j]
			var n: Vector3 = (norms[i] as PackedVector3Array)[j]
			var side := n.cross(_plan_dir(phi)).normalized()
			var half := 0.014 + 0.012 * ss[i]
			ra.append(p + n * 0.012 + side * half)
			rb.append(p + n * 0.012 - side * half)
			nn.append(n)
			var lit := (cols[i] as PackedColorArray)[j].a
			rc.append(_lin(GILT.lerp(PINK, 0.25), minf(lit * 1.1 + 0.05, 1.0)))
		b.grid([ra, rb], [nn, nn], [rc, rc])
	b.colour = Color.WHITE


static func _plan_dir(phi: float) -> Vector3:
	return Vector3(cos(phi), 0.0, sin(phi))


## The dome's rim in plan at angle phi: distance from its centre.
static func _rim(phi: float) -> float:
	var cx := cos(phi) / DOME_AXES.x
	var cz := sin(phi) / DOME_AXES.y
	return 1.0 / sqrt(cx * cx + cz * cz)


## How far the vault reaches from the dome's centre at angle phi (the walls, the proscenium's front ring, the rear
## wall).
static func _reach(phi: float, w: float, front: float, rz: float) -> float:
	var d := _plan_dir(phi)
	var t := 1000.0
	if absf(d.x) > 0.0001:
		t = minf(t, (signf(d.x) * w - DOME_AT.x) / d.x)
	if d.z < -0.0001:
		t = minf(t, (front - DOME_AT.y) / d.z)
	elif d.z > 0.0001:
		t = minf(t, (rz - DOME_AT.y) / d.z)
	return t


## A point of the vault: angle phi round the dome, s from its rim (0) to the vault's edge (1). The ribs deepen
## outward; the troughs are pressed up into the vault along its normal.
static func _vault_point(phi: float, s: float, w: float, front: float, rz: float) -> Vector3:
	var d := _plan_dir(phi)
	var r0 := _rim(phi)
	var r1 := _reach(phi, w, front, rz)
	var r := lerpf(r0, r1, s)
	var x := DOME_AT.x + d.x * r
	var z := DOME_AT.y + d.z * r
	var y := _vault_y(x, w)
	var dy := _vault_dy(x, w)
	var up := Vector3(-dy, 1.0, 0.0).normalized()
	var crest := 0.5 + 0.5 * cos(RIBS * phi)
	# Deepening outward, and easing out in the last few per cent so the vault meets the cornice, the rings and the
	# rear wall in a clean line (no sawtooth of rib ends).
	var depth := RIB_DEPTH * smoothstep(0.0, 0.3, s) * (0.55 + 0.45 * s) * (1.0 - smoothstep(0.93, 1.0, s))
	return Vector3(x, y, z) + up * depth * (1.0 - crest)


## The rear wall over the walkway: rose plaster up into the vault; a cornice-high gilt bead across it over the
## balcony's back row; the projection ports are the builder's.
static func _rear_wall(c: Object, l: Auditorium.Layout, w: float) -> void:
	var plaster: Material = c.tinted("plaster")
	var rz := l.hi.z
	var walk := l.row_floor(-l.rows_back)
	c.s.surface(plaster)
	c.s.colour = _lin(WALL)
	var top := CROWN + RIB_DEPTH + 0.3
	c.s.face([Vector3(-w, walk, rz), Vector3(w, walk, rz), Vector3(w, top, rz), Vector3(-w, top, rz)], Vector3.FORWARD)
	# A great shell in relief over the balcony: powder blue with gilt ribs, washed from a lamp hidden behind the back
	# row (its light per vertex, with the coves; and in the bake, on the wall round it).
	var xf := Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), Vector3(0.0, 6.4, rz - 0.01))
	c.cove.surface(c.kit.cove_material())
	_cove_fan(c.cove, xf, 2.7, 0.3, 13, BLUE, 0.85, 0.12)
	c.cove.colour = Color.WHITE
	c.glow_lights.append([Vector3(0.0, 6.2, rz - 0.6), Color(1.0, 0.78, 0.76), 0.5, 4.0])
	# And the vault's glow down the rear wall either side of it, as along the side walls.
	for x: float in [-5.5, 5.5]:
		c.glow_lights.append([Vector3(x, 8.2, rz - 1.1), Color(1.0, 0.72, 0.76), 0.3, 4.5])
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


## Over each front exit, a gilt shell hood on a pink plaster arch round the door (the builder draws the door).
static func _door_hoods(c: Object, l: Auditorium.Layout, w: float) -> void:
	var p: Dictionary = c.builder_params
	if not bool(p.get("doors", true)):
		return
	var front_z := (l.lo.z + float(p["stage_depth"]) + l.arc_z(l.row_radius(l.rows_front) - l.depth * 0.5,
			l.block_x)) * 0.5
	var ds: Array = p["door_size"]
	var dw := float(ds[0])
	var dh := float(ds[1])
	var plaster: Material = c.tinted("plaster")
	var gilt: Material = c.shiny("gilt", 1.0, 0.8, 0.22)
	for s: float in [-1.0, 1.0]:
		var into := Vector3(-s, 0, 0)
		var xf := _wall_xf(Vector3(s * w, l.lo.y, front_z), into)
		var head := dh + 0.75
		# An architrave round the door and its sign: two jambs and a round head.
		var inner := _arch_outline(dw * 0.5 + 0.12, 0.0, head - dw * 0.5 - 0.12, 12)
		var outer := _arch_outline(dw * 0.5 + 0.34, 0.0, head - dw * 0.5 - 0.12, 12)
		var ra := PackedVector3Array()
		var rb := PackedVector3Array()
		var nn := PackedVector3Array()
		for j in inner.size():
			ra.append(xf * Vector3(inner[j].x, inner[j].y, 0.05))
			rb.append(xf * Vector3(outer[j].x, outer[j].y, 0.05))
			nn.append(into)
		c.s.surface(plaster)
		c.s.colour = _lin(CREAM)
		c.s.strip(ra, rb, nn)
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		var ins: Array = []
		for j in inner.size():
			var d := inner[j] - Vector2(0.0, head - dw * 0.5 - 0.12)
			var i2 := -d.normalized() if inner[j].y > head - dw * 0.5 - 0.12 else Vector2(-signf(inner[j].x), 0.0)
			ins.append((xf.basis * Vector3(i2.x, i2.y, 0.0)).normalized())
		_edge_bead(c.u, ra, ins, into, 0.02, 3)
		_relief_fan(c.u, xf * Transform3D(Basis(), Vector3(0.0, head + 0.05, 0.06)), 0.55, 0.1, 11)
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


# --- The proscenium: the shell's rings ---------------------------------------------------------------------------------

static func _ring_z(k: int) -> float:
	return RING_Z + RING_STEP * k


## Ring k's opening, scalloped: [points (x, y), inward normals, crest at each]. Up the left leg from its foot, over the
## arch (a superellipse round the picture's middle, its ribs radiating from there), down the right leg. All rings
## share the same count and angles, so the ribs run on from ring to ring.
static func _ring_outline(k: int, centre_y: float, foot: float) -> Array:
	var a := RING_HALF + RING_HALF_STEP * k
	var top := RING_TOP + RING_TOP_STEP * k
	var b := top - centre_y
	var legs := 6
	var segs := RING_RIBS * 6
	var pts := PackedVector2Array()
	var ns := PackedVector2Array()
	var crests := PackedFloat32Array()
	for i in legs:
		pts.append(Vector2(-a, lerpf(foot, centre_y, float(i) / legs)))
		ns.append(Vector2(1, 0))
		crests.append(0.0)
	var e := 2.0 / RING_EXP
	for i in segs + 1:
		var th := PI - PI * float(i) / segs
		var cx := cos(th)
		var sy := sin(th)
		var p := Vector2(signf(cx) * pow(absf(cx), e) * a, centre_y + pow(absf(sy), e) * b)
		var crest := 0.5 + 0.5 * cos(th * RING_RIBS * 2.0)
		# Scalloped: each rib's end stands a little into the opening, the edge between them drawn back.
		var dir := (p - Vector2(0.0, centre_y)).normalized()
		p -= dir * (0.07 * crest - 0.03)
		pts.append(p)
		ns.append(-dir)
		crests.append(crest)
	for i in range(legs - 1, -1, -1):
		pts.append(Vector2(a, lerpf(foot, centre_y, float(i) / legs)))
		ns.append(Vector2(-1, 0))
		crests.append(0.0)
	return [pts, ns, crests]


## The proscenium: five rings round the picture stepping towards the seats, each wider and higher; each face fluted
## (its ribs radiating from the picture's middle) and lit from a lamp hidden behind the next ring's edge (bright by
## that edge, fading towards its own opening), the rings blue and pink in turn; scalloped gilt reveals and a gilt
## bead round each edge. The fifth ring's face reaches the walls and the vault; a gilt shell crests it. Footlights in
## gilt shells along the stage's lip.
static func _proscenium(c: Object) -> void:
	var l := _layout(c)
	var w := l.hi.x
	var sxf: Transform3D = c.screen.get("xf", Transform3D())
	var sc := sxf.origin
	var stage_top := float(c.builder_params.get("stage_top", -2.1))
	var stage_front := l.lo.z + float(c.builder_params.get("stage_depth", 1.9))
	var outlines: Array = []
	for k in RINGS:
		var foot := stage_top if _ring_z(k) < stage_front else l.lo.y
		outlines.append(_ring_outline(k, sc.y, foot))
	var b: RoomMesh = c.cove
	b.surface(c.kit.cove_material())
	var faces: Array[Color] = [BLUE, PINK, BLUE, PINK, ROSE.lerp(PINK, 0.5)]
	for k in RINGS:
		var inner: PackedVector2Array = outlines[k][0]
		var crest_i: PackedFloat32Array = outlines[k][2]
		var z := _ring_z(k)
		var outer := PackedVector2Array()
		if k < RINGS - 1:
			outer = outlines[k + 1][0]
		else:
			outer = _to_hall(inner, sc.y, w)
		var ts: Array = [0.0, 0.2, 0.45, 0.7, 1.0] if k < RINGS - 1 else [0.0, 0.08, 0.2, 0.36, 0.55, 0.75, 1.0]
		var rows: Array = []
		var cols: Array = []
		for t: float in ts:
			var row := PackedVector3Array()
			var crow := PackedColorArray()
			for j in inner.size():
				var p := inner[j].lerp(outer[j], t)
				var crest := crest_i[j]
				# Fluted: the ribs stand out towards the seats, more towards the ring's outer edge.
				var relief := (0.025 + 0.05 * t) * crest * float(p.y > sc.y - 0.01)
				row.append(Vector3(p.x, p.y, z + relief))
				var lit: float
				if k < RINGS - 1:
					lit = 0.08 + 0.95 * pow(t, 1.5)
				else:
					# The fifth: washed from the vault's cornice lamps at its top and sides, from the footlights at its
					# foot, and a little round its own edge.
					lit = 0.12 + 0.5 * smoothstep(5.0, 9.5, p.y) + 0.35 * exp(-(p.y - l.lo.y) / 1.4) \
							+ 0.25 * exp(-t * 10.0)
				# The flutes: each rib's crest catches the light, the hollow beside it holds a shadow.
				lit *= 0.55 + 0.45 * crest
				crow.append(_lin(faces[k].lerp(CREAM, 0.2 * crest), lit))
			rows.append(row)
			cols.append(crow)
		b.grid(rows, _grid_normals(rows, func(_p: Vector3) -> Vector3: return Vector3.BACK), cols)
	# The reveals (gilt, from each ring back to the one behind; the first back past the screen) and the beads.
	var gilt: Material = c.shiny("gilt", 1.0, 0.8, 0.22)
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	for k in RINGS:
		var pts: PackedVector2Array = outlines[k][0]
		var ns: PackedVector2Array = outlines[k][1]
		var z_front := _ring_z(k)
		var z_back := _ring_z(k - 1) if k > 0 else sc.z - 0.2
		var fr := PackedVector3Array()
		var bk := PackedVector3Array()
		var nn := PackedVector3Array()
		var ins: Array = []
		for j in pts.size():
			fr.append(Vector3(pts[j].x, pts[j].y, z_front))
			bk.append(Vector3(pts[j].x, pts[j].y, z_back))
			nn.append(Vector3(ns[j].x, ns[j].y, 0.0))
			ins.append(Vector3(ns[j].x, ns[j].y, 0.0))
		c.u.grid([fr, bk], [nn, nn])
		_edge_bead(c.u, fr, ins, Vector3.BACK, 0.032, 4)
	# Ring 4 is a wall to object physics, the openings open.
	var z4 := _ring_z(RINGS - 1)
	c.shapes.append(PhysicsShapes.box(Vector3(0.0, (RING_TOP + RING_TOP_STEP * (RINGS - 1) + CROWN) * 0.5 + 0.3, z4 - 0.8),
			Vector3(w * 2.0, CROWN - RING_TOP - RING_TOP_STEP * (RINGS - 1) + 0.6, 1.6), Basis()))
	# The crest over the fifth ring: a gilt scallop, its hinge on the opening's head.
	var top4 := RING_TOP + RING_TOP_STEP * (RINGS - 1)
	b.surface(c.kit.cove_material())
	_cove_fan(b, Transform3D(Basis(), Vector3(0.0, top4 - 0.04, z4 + 0.03)), 1.35, 0.28, 11, BLUE, 0.95, 0.4)
	b.colour = Color.WHITE
	_footlights(c, l, stage_top, stage_front)
	c.u.colour = Color.WHITE
	b.colour = Color.WHITE


## The fifth ring's outer edge: from each point of its opening straight out from the picture's middle to the walls or
## the vault (a little past it, under the troughs).
static func _to_hall(inner: PackedVector2Array, centre_y: float, w: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in inner:
		var d := p - Vector2(0.0, centre_y)
		if p.y <= centre_y + 0.001:
			out.append(Vector2(signf(p.x) * w, p.y))
			continue
		d = d.normalized()
		var t := 0.0
		var q := p
		while t < 12.0:
			t += 0.02
			q = p + d * t
			if absf(q.x) >= w or q.y >= _vault_y(q.x, w) + RIB_DEPTH * 0.9:
				break
		out.append(Vector2(clampf(q.x, -w, w), minf(q.y, _vault_y(q.x, w) + RIB_DEPTH * 0.9)))
	return out


## Footlights along the stage's lip: little gilt shells lying open towards the curtain, a glow in each; four stand-in
## lamps in the coves' colour light the festoon's folds from below (never baked: the festoon is not).
static func _footlights(c: Object, l: Auditorium.Layout, stage_top: float, stage_front: float) -> void:
	# The house group: they go down with the house lights for the film.
	var glass: Material = c.kit._lamp(Color(1.0, 0.8, 0.66), 1.3, 1.0, "house")
	var n := 13
	for i in n:
		var x := lerpf(-6.6, 6.6, float(i) / (n - 1))
		# The shell stands at the lip leaning back, its fan rising towards the curtain, its back to the seats.
		var xf := Transform3D(Basis(Vector3.RIGHT, Vector3(0.0, 0.9, -0.44).normalized(),
				Vector3(0.0, 0.44, 0.9).normalized()), Vector3(x, stage_top + 0.005, stage_front - 0.04))
		c.u.colour = _lin(GILT)
		_relief_fan(c.u, xf, 0.16, 0.05, 7)
		c.lit.surface(glass)
		c.lit.colour = Color.WHITE
		var gxf := Transform3D(Basis(Vector3.RIGHT, Vector3(0.0, 0.3, -0.95).normalized(),
				Vector3(0.0, 0.95, 0.3).normalized()), Vector3(x, stage_top + 0.02, stage_front - 0.1))
		_glass_fan(c.lit, gxf, 0.1, 0.04, 5, 10, 2)
	for x: float in [-4.2, -1.4, 1.4, 4.2]:
		c.footlights.append([Vector3(x, stage_top + 0.12, stage_front - 0.1), 0.2, 1.0])


# --- The balcony --------------------------------------------------------------------------------------------------------

## The balcony's front: buttoned pink velvet (the tufted pattern) from below the slab's edge to its top, rolled over
## at the top towards the seats (kept under the front row's sight line to the picture's foot), a gilt bead along
## its top edge and its foot; seven little fans of pink glass on it; under the balcony a soffit of rose plaster with
## round downlights, and their light on the rear walkway in the bake.
static func _balcony(c: Object) -> void:
	var l := _layout(c)
	var w := l.hi.x
	var rows: Array = Auditorium._balcony_rows(c.builder_params, l)
	if rows.is_empty():
		return
	var slab := float(rows[0][1])
	var back_z := float(rows[0][0]) - l.depth * 0.5
	var velvet: Material = c.tinted("fabric", "tufted")
	var plain_velvet: Material = c.tinted("fabric")
	var gilt: Material = c.shiny("gilt", 1.0, 0.8, 0.22)
	var plaster: Material = c.tinted("plaster")
	var pink: Color = c.colour_of("fabric")
	# The face (towards the stalls and the screen).
	c.s.surface(velvet)
	c.s.colour = _lin(pink)
	c.s.face([Vector3(-w, FRONT_FOOT, FRONT_Z), Vector3(w, FRONT_FOOT, FRONT_Z), Vector3(w, FRONT_TOP, FRONT_Z),
			Vector3(-w, FRONT_TOP, FRONT_Z)], Vector3.FORWARD)
	# The roll over the top: a quarter round up and back over the builder's parapet, then down to the balcony's floor
	# on the seats' side. Every point under the front row's sight line to the picture's foot.
	var roll: Array = [Vector2(FRONT_Z, FRONT_TOP), Vector2(FRONT_Z + 0.05, FRONT_TOP + 0.06),
			Vector2(FRONT_Z + 0.13, FRONT_TOP + 0.1), Vector2(back_z - 0.03, FRONT_TOP + 0.11),
			Vector2(back_z + 0.01, FRONT_TOP + 0.05), Vector2(back_z + 0.02, FRONT_TOP - 0.08), Vector2(back_z + 0.02, slab)]
	var xs := PackedFloat32Array([-w, w])
	var grid_rows: Array = []
	for p: Vector2 in roll:
		var row := PackedVector3Array()
		for x in xs:
			row.append(Vector3(x, p.y, p.x))
		grid_rows.append(row)
	var mid_y := FRONT_TOP - 0.3
	c.s.surface(plain_velvet)
	c.s.colour = _lin(pink.darkened(0.05))
	for i in grid_rows.size() - 1:
		var a: PackedVector3Array = grid_rows[i]
		var bb: PackedVector3Array = grid_rows[i + 1]
		var n := (Vector3(0.0, (a[0].y + bb[0].y) * 0.5 - mid_y, (a[0].z + bb[0].z) * 0.5 - FRONT_Z - 0.12)).normalized()
		c.s.face([a[0], a[1], bb[1], bb[0]], n)
	# The fascia's underside back to the slab, and the soffit under the balcony.
	c.s.surface(plaster)
	c.s.colour = _lin(ROSE.lerp(CREAM, 0.3))
	var soffit_y := slab - 0.31
	c.s.face([Vector3(-w, FRONT_FOOT, FRONT_Z), Vector3(w, FRONT_FOOT, FRONT_Z), Vector3(w, FRONT_FOOT, FRONT_Z + 0.25),
			Vector3(-w, FRONT_FOOT, FRONT_Z + 0.25)], Vector3.DOWN)
	c.s.face([Vector3(-w, FRONT_FOOT, FRONT_Z + 0.25), Vector3(w, FRONT_FOOT, FRONT_Z + 0.25),
			Vector3(w, soffit_y, FRONT_Z + 0.25), Vector3(-w, soffit_y, FRONT_Z + 0.25)], Vector3.BACK)
	c.s.colour = _lin(PINK.lerp(CREAM, 0.4))
	c.s.face([Vector3(-w, soffit_y - 0.005, FRONT_Z + 0.25), Vector3(w, soffit_y - 0.005, FRONT_Z + 0.25),
			Vector3(w, soffit_y - 0.005, l.hi.z), Vector3(-w, soffit_y - 0.005, l.hi.z)], Vector3.DOWN)
	# Gilt beads: along the top edge and the foot.
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	for y: float in [FRONT_TOP - 0.01, FRONT_FOOT + 0.02]:
		_bead(c.u, PackedVector3Array([Vector3(-w, y, FRONT_Z), Vector3(w, y, FRONT_Z)]),
				[Vector3.FORWARD, Vector3.FORWARD], Vector3.UP, 0.024, 4)
	# The fans: little shells of pink glass on gilt brackets, facing the hall.
	var glass := _glass_material(c)
	for i in 7:
		var x := lerpf(-7.2, 7.2, float(i) / 6.0)
		var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(x, 4.58, FRONT_Z - 0.005))
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		_box(c.u, xf, Vector3(0.0, -0.05, 0.03), Vector3(0.08, 0.1, 0.06), [RoomMesh.FRONT])
		c.lit.surface(glass)
		_glass_fan(c.lit, xf * Transform3D(Basis(), Vector3(0.0, 0.0, 0.04)), 0.2, 0.08, 7, 12, 3)
		c.glow_lights.append([xf * Vector3(0.0, 0.1, 0.35), SCONCE_LIGHT, 0.35, 2.4])
	# The downlights in the soffit: round glows, three rows of five, and their pools below in the bake.
	var lamp: Material = c.kit._lamp(Color(1.0, 0.82, 0.7), 1.2, 1.0, "house")
	c.lit.surface(lamp)
	c.lit.colour = Color.WHITE
	for zi in 2:
		var z := lerpf(FRONT_Z + 0.9, l.hi.z - 0.8, float(zi))
		for xi in 5:
			var x := lerpf(-6.4, 6.4, float(xi) / 4.0)
			var ring: Array = []
			for k in 12:
				var a := TAU * k / 12.0
				ring.append(Vector3(x + cos(a) * 0.09, soffit_y - 0.012, z + sin(a) * 0.09))
			c.lit.face(ring, Vector3.DOWN)
	for x: float in [-5.0, 0.0, 5.0]:
		c.spots.append([Vector3(x, soffit_y - 0.05, (FRONT_Z + l.hi.z) * 0.5), Vector3(x, l.row_floor(-l.rows_back),
				(FRONT_Z + l.hi.z) * 0.5 + 0.3), Color(1.0, 0.8, 0.7), 1.4, 6.0, 55.0])
	c.shapes.append(PhysicsShapes.box(Vector3(0.0, (FRONT_FOOT + FRONT_TOP) * 0.5, FRONT_Z + 0.08),
			Vector3(w * 2.0, FRONT_TOP - FRONT_FOOT, 0.16), Basis()))
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


# --- The dome ----------------------------------------------------------------------------------------------------------

## The oval dome over the stalls, set into the vault's crown: a gilt lip round the opening hides the lamps on the ledge
## behind it, which light the drum and the dome from its foot (warm by the rim, the apex deep blue); a gilt sunburst
## of rays round a rosette; from the rosette, the chandelier: three tiers of pink glass shells on a gilt stem round a
## glass drop. Its lamp lights the room round it in the bake.
static func _dome(c: Object) -> void:
	var b: RoomMesh = c.cove
	b.surface(c.kit.cove_material())
	var centre := Vector3(DOME_AT.x, CROWN, DOME_AT.y)
	# As many as the vault's columns, at the same angles: the lip meets the vault's rim chord for chord.
	var segs := RIBS * 6
	var drum_k := 1.08
	# Profile, by the oval's normalised radius rho and height: the drum up from the ledge, then the dome to the apex.
	# (The drum's foot a little over the vault's top: under it, it would show through as a ring.)
	var prof: Array = [Vector2(drum_k, CROWN + 0.03), Vector2(drum_k, CROWN + DRUM * 0.5), Vector2(drum_k, CROWN + DRUM)]
	for i in range(1, 9):
		var a := PI * 0.5 * float(i) / 8.0
		prof.append(Vector2(drum_k * cos(a), CROWN + DRUM + (DOME_TOP - CROWN - DRUM) * sin(a)))
	var rows: Array = []
	var cols: Array = []
	var lamp_y := CROWN + 0.05
	for i in prof.size():
		var pr: Vector2 = prof[i]
		var row := PackedVector3Array()
		for k in segs + 1:
			var phi := TAU * float(k % segs) / segs
			var rad := _rim(phi) * pr.x
			row.append(centre + _plan_dir(phi) * rad + Vector3(0.0, pr.y - CROWN, 0.0))
		rows.append(row)
	var norms := _grid_normals(rows, func(p: Vector3) -> Vector3:
		return (Vector3(centre.x, CROWN - 2.0, centre.z) - p).normalized())
	for i in prof.size():
		var pr: Vector2 = prof[i]
		var row: PackedVector3Array = rows[i]
		var crow := PackedColorArray()
		for k in row.size():
			var phi := TAU * float(k % segs) / segs
			var p := row[k]
			# The lamps on the ledge just outside the opening, under the drum: their light up the drum and over the
			# dome, fading towards the apex.
			var lamp := centre + _plan_dir(phi) * _rim(phi) * 1.02 + Vector3(0.0, lamp_y - CROWN, 0.0)
			var rise := pr.y - CROWN
			var lit := 0.9 * _point_w(p, nrm(norms, i, k), lamp, 0.7) + 0.5 * exp(-rise / 0.5)
			lit += 0.14
			# The drum rose, the dome's foot a pale blue deepening to the apex: dawn round an evening sky.
			var colour := DEEP_BLUE.lerp(BLUE, pow(clampf(pr.x / drum_k, 0.0, 1.0), 1.5))
			if pr.x >= drum_k - 0.001:
				colour = ROSE.lerp(PINK, 0.5)
			crow.append(_lin(colour, lit))
		cols.append(crow)
	b.grid(rows, norms, cols)
	# The gilt lip round the opening (a downstand with a bead), and the sunburst's rays and rosette.
	var gilt: Material = c.shiny("gilt", 1.0, 0.85, 0.2)
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	var lip_top := PackedVector3Array()
	var lip_bot := PackedVector3Array()
	var outs: Array = []
	var ln := PackedVector3Array()
	for k in segs + 1:
		var phi := TAU * float(k % segs) / segs
		var p := centre + _plan_dir(phi) * _rim(phi)
		lip_top.append(p + Vector3.UP * 0.02)
		lip_bot.append(p + Vector3.DOWN * 0.14)
		var o := -_plan_dir(phi)
		outs.append(o)
		ln.append(o)
	c.u.grid([lip_top, lip_bot], [ln, ln])
	_bead(c.u, lip_bot, outs, Vector3.DOWN, 0.035, 4)
	# The sunburst's rays, long and short: gilt in the dome's own light (PieceCove: brighter towards the lamps at the
	# foot, a glint of gold to the apex).
	var rays := 32
	for r in rays:
		var phi := TAU * (float(r) + 0.5) / rays
		var long := r % 2 == 0
		var ra := PackedVector3Array()
		var rb := PackedVector3Array()
		var nn := PackedVector3Array()
		var rc := PackedColorArray()
		for i in 7:
			var t := lerpf(0.12, 0.9 if long else 0.66, float(i) / 6.0)
			var a := PI * 0.5 * (1.0 - t)
			var y := CROWN + DRUM + (DOME_TOP - CROWN - DRUM) * sin(a)
			var rad := drum_k * cos(a)
			var p := centre + _plan_dir(phi) * _rim(phi) * rad + Vector3(0.0, y - CROWN, 0.0)
			var n := (Vector3(centre.x, CROWN - 2.0, centre.z) - p).normalized()
			var side := n.cross(_plan_dir(phi)).normalized()
			var half := (0.015 + 0.055 * t) * (1.0 if long else 0.7)
			ra.append(p + n * 0.012 + side * half)
			rb.append(p + n * 0.012 - side * half)
			nn.append(n)
			rc.append(_lin(GILT.lerp(CREAM, 0.35), 0.16 + 0.36 * t * t))
		b.grid([ra, rb], [nn, nn], [rc, rc])
	# The rosette: a gilt boss of sixteen petals at the apex.
	var apex := Vector3(centre.x, DOME_TOP - 0.01, centre.z)
	var petals := PackedVector3Array()
	var hub := PackedVector3Array()
	for k in 65:
		var a := TAU * float(k % 64) / 64.0
		var r := 0.42 * (0.8 + 0.2 * absf(cos(a * 8.0)))
		petals.append(apex + Vector3(cos(a) * r, -0.04, sin(a) * r))
		hub.append(apex + Vector3(cos(a) * 0.1, -0.12, sin(a) * 0.1))
	c.u.grid([hub, petals], [_fill_n(hub.size(), Vector3.DOWN), _fill_n(petals.size(), Vector3.DOWN)])
	_chandelier(c, apex)
	c.u.colour = Color.WHITE
	b.colour = Color.WHITE


static func nrm(norms: Array, i: int, k: int) -> Vector3:
	return (norms[i] as PackedVector3Array)[k]


## The chandelier: a gilt stem from the rosette, three tiers of pink glass shells round it opening outwards and up,
## gilt rings carrying them, and a glass drop at the foot. One stand-in lamp and a bake light at its heart.
static func _chandelier(c: Object, apex: Vector3) -> void:
	var foot := 8.4
	var gilt: Material = c.shiny("gilt", 1.0, 0.85, 0.2)
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	Shapes.cylinder(c.u, Vector3(apex.x, foot + 0.3, apex.z), 0.03, apex.y - foot - 0.3, 8)
	var glass := _glass_material(c)
	var tiers: Array = [[9.62, 0.44, 6, 0.28], [9.2, 0.72, 8, 0.34], [8.78, 1.0, 10, 0.4]]
	for t: Array in tiers:
		var y := float(t[0])
		var r := float(t[1])
		var n := int(t[2])
		var size := float(t[3])
		# The ring that carries them.
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		var ring := PackedVector3Array()
		var outs: Array = []
		for k in 25:
			var a := TAU * float(k % 24) / 24.0
			ring.append(Vector3(apex.x + cos(a) * r * 0.82, y - 0.04, apex.z + sin(a) * r * 0.82))
			outs.append(Vector3(cos(a), 0.0, sin(a)))
		_bead(c.u, ring, outs, Vector3.UP, 0.018, 4)
		for k in n:
			var a := TAU * (float(k) + 0.5 * float(n == 8)) / n
			var out := Vector3(cos(a), 0.0, sin(a))
			# Each shell stands on the ring, leaning out, its hinge low, its fan up and out.
			var up := (Vector3.UP * 0.8 + out * 0.6).normalized()
			var tangent := Vector3.UP.cross(out).normalized()
			var zf := tangent.cross(up).normalized()
			if zf.dot(out) < 0.0:
				zf = -zf
			var xax := up.cross(zf).normalized()
			var xf := Transform3D(Basis(xax, up, zf), Vector3(apex.x, y, apex.z) + out * r)
			c.lit.surface(glass)
			_glass_fan(c.lit, xf, size, size * 0.4, 7, 12, 3)
	# The drop at the foot: a glass bowl.
	c.lit.surface(glass)
	c.lit.colour = Color(1.2, 1.2, 1.2)
	var prof: Array = [Vector2(0.0, -0.12), Vector2(0.12, -0.08), Vector2(0.19, 0.02), Vector2(0.16, 0.12),
			Vector2(0.03, 0.2)]
	Shapes.lathe(c.lit, prof, Vector3(apex.x, foot + 0.18, apex.z), 12)
	c.lit.colour = Color.WHITE
	var heart := Vector3(apex.x, 9.05, apex.z)
	c.lamps.append([heart, Color(1.0, 0.72, 0.72), 1.2])
	c.u.colour = Color.WHITE
