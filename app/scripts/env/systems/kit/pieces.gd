extends RefCounted

## The kit's pieces (docs/environments.md, "The kit"): each draws itself into the kit's shared meshes, so pieces cost
## draws by material, not by count. A piece works in its own frame: xf places it (a slot's transform, the piece's own
## offset, turn and size in it), its front faces local +Z, its foot is at local y 0. Statues are animals and things,
## never a figure or a torso. Static; kit.gd calls build(piece, ctx, xf, size, entry).
##
## ctx (kit.gd's Ctx): s (baked RoomMesh), u (unbaked RoomMesh: rounded shapes, leaves), lit (unbaked RoomMesh of
## lamp shades), mat(key, colour) -> material (made once a key and colour), shade(colour) -> a lamp shade's glow,
## shapes (physics boxes), glows (lamp quads by key), lamps ([at, colour, strength]: stand-in lamps), screen (the
## room's screen: {xf, size}), room (the environment node), rng. The furniture (desk, computer, video_recorder,
## sideboard, standard_lamp, rug, coffee_table) is furniture.gd's.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Furniture := preload("res://scripts/env/systems/kit/furniture.gd")

const PIECES: Array[String] = ["balcony_front", "niche", "urn", "lion", "obelisk", "column", "facade", "castle_gate",
		"booth", "snack_bar", "screen_tower", "bougainvillea", "ivy", "ferns", "carpet", "partition", "curves",
		"desk", "computer", "video_recorder", "sideboard", "standard_lamp", "rug", "coffee_table"]
## Each piece's size when neither the entry nor its slot gives one: [width, height, depth].
const SIZES := {
	"balcony_front": [6.0, 1.0, 0.25], "niche": [1.3, 2.6, 0.4], "urn": [0.5, 1.0, 0.5], "lion": [0.55, 0.9, 1.0],
	"obelisk": [0.55, 2.2, 0.55], "column": [0.7, 4.0, 0.7], "facade": [5.0, 5.0, 0.5], "castle_gate": [0.0, 0.0, 1.0],
	"booth": [2.0, 2.3, 1.8], "snack_bar": [3.2, 2.8, 2.0], "screen_tower": [0.0, 0.0, 2.0],
	"bougainvillea": [2.5, 1.6, 0.3], "ivy": [2.0, 2.5, 0.2], "ferns": [1.0, 0.8, 1.0], "carpet": [0.0, 0.0, 0.0],
	"partition": [6.0, 3.0, 0.12], "curves": [2.0, 3.0, 0.1],
	"desk": [1.2, 0.74, 0.65], "computer": [0.44, 0.42, 0.56], "video_recorder": [0.43, 0.09, 0.3],
	"sideboard": [1.6, 0.8, 0.45], "standard_lamp": [0.36, 1.55, 0.36], "rug": [2.0, 0.012, 1.4],
	"coffee_table": [1.0, 0.42, 0.55],
}
## The pieces that stand on a floor (their slot's origin is a floor point); the others hang on a wall.
const STANDING: Array[String] = ["urn", "lion", "obelisk", "column", "booth", "snack_bar", "ferns", "partition",
		"desk", "computer", "video_recorder", "sideboard", "standard_lamp", "rug", "coffee_table"]
## What a video recorder's clock shows (kit.gd flashes it).
const CLOCK := "12:00"


static func build(piece: String, c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	match piece:
		"balcony_front":
			_balcony_front(c, xf, size, e)
		"niche":
			_niche(c, xf, size, e)
		"urn":
			_urn(c, xf, 1.0, e)
		"lion":
			_lion(c, xf, e)
		"obelisk":
			_obelisk(c, xf, size, e)
		"column":
			_column(c, xf, size, e)
		"facade":
			_facade(c, xf, size, e)
		"castle_gate":
			_castle_gate(c, xf, size, e)
		"booth":
			_booth(c, xf, size, e)
		"snack_bar":
			_snack_bar(c, xf, size, e)
		"screen_tower":
			_screen_tower(c, xf, size, e)
		"bougainvillea":
			_bougainvillea(c, xf, size, e)
		"ivy":
			_ivy(c, xf, size, e)
		"ferns":
			_ferns(c, xf, size, e)
		"carpet":
			_carpet(c, e)
		"partition":
			_partition(c, xf, size, e)
		"curves":
			_curves(c, xf, size, e)
		"desk", "sideboard", "coffee_table":
			var m := {"body": c.mat("wood", e.get("colour")), "detail": c.mat("iron")}
			_solids(c, xf, Furniture.stand(piece, c.s, xf, size, m))
		"computer":
			var m := {"body": c.mat("plastic", e.get("colour")), "detail": c.mat("iron")}
			_solids(c, xf, Furniture.computer(c.s, xf, size, m, str(e.get("holds", "")) != "none"))
		"video_recorder":
			_video_recorder(c, xf, size, e)
		"standard_lamp":
			_standard_lamp(c, xf, size, e)
		"rug":
			var field := _colour(e, c.colour_of("fabric"))
			var accent: Variant = e.get("accent")
			Furniture.rug(c.s, xf, size, {"body": c.mat("fabric", field),
					"detail": c.mat("fabric", _to_color(accent) if accent != null else field * 0.55)})


# --- Furniture (furniture.gd draws it) -----------------------------------------------------------------------------

## A piece of furniture's boxes ([[centre, size]] in its own frame) as physics shapes.
static func _solids(c: Object, xf: Transform3D, boxes: Array) -> void:
	for bx: Array in boxes:
		_solid(c, xf, bx[0], bx[1])


## A video recorder, its clock's digits glowing in its window (the "display" glow: kit.gd flashes it).
static func _video_recorder(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var body := _colour(e, c.colour_of("iron"))
	var m := {"body": c.mat("iron", body), "detail": c.mat("iron", body * 0.35)}
	var win: Array = Furniture.video_recorder(c.s, xf, size, m)
	var g: Array = c.glows.get("display", [])
	g.append_array(Furniture.seven_segments(CLOCK, win[0], win[1], win[2], win[3], win[4]))
	c.glows["display"] = g
	_solid(c, xf, Vector3(0, size.y * 0.5, 0), size)


## A standard lamp: its shade glows (house group) and gives a dim stand-in lamp while the light system has room.
static func _standard_lamp(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var shade := _colour(e, c.colour_of("lamp_colour"))
	var accent: Variant = e.get("accent")
	var m := {"body": c.mat("iron"), "pole": c.mat("iron", _to_color(accent) if accent != null else null),
			"shade": c.shade(shade)}
	var at := Furniture.standard_lamp(c.s, c.lit, xf, size, m)
	c.lamps.append([xf * at, shade, 0.45])
	_solid(c, xf, Vector3(0, size.y * 0.5, 0), Vector3(0.3, size.y, 0.3))


# --- In the piece's frame ------------------------------------------------------------------------------------------

static func _box(b: RoomMesh, xf: Transform3D, centre: Vector3, size: Vector3, basis := Basis(), skip: Array = []) -> void:
	b.box(xf * centre, size, xf.basis * basis, skip)


static func _face(b: RoomMesh, xf: Transform3D, corners: Array, n: Vector3) -> void:
	var w: Array = []
	for p: Vector3 in corners:
		w.append(xf * p)
	b.face(w, (xf.basis * n).normalized())


static func _lathe(b: RoomMesh, xf: Transform3D, profile: Array, centre: Vector3, sides := 12) -> void:
	Shapes.lathe(b, profile, xf * centre, sides, xf.basis)


static func _rbox(b: RoomMesh, xf: Transform3D, centre: Vector3, size: Vector3, r: float, basis := Basis()) -> void:
	b.rounded_box(Vector3.ZERO, size, r, xf * Transform3D(basis, centre), 1)


static func _solid(c: Object, xf: Transform3D, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	var s := xf.basis.get_scale().x
	c.shapes.append(PhysicsShapes.box(xf * centre, size * s, xf.basis.orthonormalized() * basis))


static func _colour(e: Dictionary, fallback: Color) -> Color:
	var v: Variant = e.get("colour")
	if v == null or (v is Array and (v as Array).is_empty()):
		return fallback
	return _to_color(v)


static func _to_color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color(str(v))
	return Color(float(v[0]), float(v[1]), float(v[2]))


# --- Statues and stone --------------------------------------------------------------------------------------------

## An urn on a square plinth: a lathe's foot, bowl, neck and lip.
static func _urn(c: Object, xf: Transform3D, k: float, e: Dictionary) -> void:
	var m: Material = c.mat("stone", e.get("colour"))
	c.s.surface(m)
	_box(c.s, xf, Vector3(0, 0.15 * k, 0), Vector3(0.42, 0.3, 0.42) * k, Basis(), [RoomMesh.DOWN])
	var prof: Array = []
	for p: Vector2 in [Vector2(0.13, 0.0), Vector2(0.16, 0.04), Vector2(0.07, 0.14), Vector2(0.09, 0.2),
			Vector2(0.21, 0.36), Vector2(0.2, 0.48), Vector2(0.12, 0.6), Vector2(0.11, 0.64), Vector2(0.17, 0.68),
			Vector2(0.15, 0.72), Vector2(0.0, 0.7)]:
		prof.append(p * k)
	_lathe(c.s, xf, prof, Vector3(0, 0.3 * k, 0), 12)
	_solid(c, xf, Vector3(0, 0.5 * k, 0), Vector3(0.42, 1.0, 0.42) * k)


## A lion lying on a plinth, its head up and towards the room: rounded body, haunch, chest, head, mane, paws, tail.
static func _lion(c: Object, xf: Transform3D, e: Dictionary) -> void:
	var m: Material = c.mat("stone", e.get("colour"))
	c.s.surface(m)
	_box(c.s, xf, Vector3(0, 0.18, 0), Vector3(0.55, 0.36, 1.0), Basis(), [RoomMesh.DOWN])
	c.u.surface(m)
	var y := 0.36
	_rbox(c.u, xf, Vector3(0, y + 0.16, -0.08), Vector3(0.34, 0.3, 0.62), 0.12)
	_rbox(c.u, xf, Vector3(0, y + 0.17, -0.3), Vector3(0.38, 0.32, 0.3), 0.14)
	_rbox(c.u, xf, Vector3(0, y + 0.24, 0.2), Vector3(0.34, 0.4, 0.26), 0.12)
	_rbox(c.u, xf, Vector3(0, y + 0.42, 0.28), Vector3(0.42, 0.42, 0.2), 0.16)
	_rbox(c.u, xf, Vector3(0, y + 0.42, 0.36), Vector3(0.22, 0.24, 0.2), 0.08)
	_rbox(c.u, xf, Vector3(0, y + 0.37, 0.46), Vector3(0.12, 0.1, 0.08), 0.04)
	for s: float in [-1.0, 1.0]:
		_rbox(c.u, xf, Vector3(s * 0.1, y + 0.04, 0.3), Vector3(0.1, 0.08, 0.34), 0.035)
		_rbox(c.u, xf, Vector3(s * 0.08, y + 0.53, 0.33), Vector3(0.06, 0.06, 0.04), 0.02)
	# The tail along the plinth by the haunch, its tuft at the end.
	Shapes.beam(c.u, xf * Vector3(0.12, y + 0.05, -0.42), xf * Vector3(0.2, y + 0.03, -0.05), Vector2(0.04, 0.04) *
			xf.basis.get_scale().x)
	_rbox(c.u, xf, Vector3(0.21, y + 0.04, -0.02), Vector3(0.07, 0.07, 0.09), 0.03)
	_solid(c, xf, Vector3(0, 0.45, 0), Vector3(0.55, 0.9, 1.0))


## An obelisk on a stepped base: a tapering square shaft and a little pyramid on top.
static func _obelisk(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	c.s.surface(c.mat("stone", e.get("colour")))
	var w := size.x
	var h := size.y
	_box(c.s, xf, Vector3(0, 0.08, 0), Vector3(w, 0.16, w), Basis(), [RoomMesh.DOWN])
	_box(c.s, xf, Vector3(0, 0.22, 0), Vector3(w * 0.8, 0.12, w * 0.8), Basis(), [RoomMesh.DOWN])
	var b0 := w * 0.32
	var b1 := w * 0.2
	var y0 := 0.28
	var y1 := h - w * 0.35
	for k in 4:
		var a := Basis(Vector3.UP, PI * 0.5 * k)
		var n := a * Vector3.BACK
		var r := a * Vector3.RIGHT
		_face(c.s, xf, [n * b0 - r * b0 + Vector3(0, y0, 0), n * b0 + r * b0 + Vector3(0, y0, 0),
				n * b1 + r * b1 + Vector3(0, y1, 0), n * b1 - r * b1 + Vector3(0, y1, 0)],
				(n * (y1 - y0) + Vector3.UP * (b0 - b1)).normalized())
		_face(c.s, xf, [n * b1 - r * b1 + Vector3(0, y1, 0), n * b1 + r * b1 + Vector3(0, y1, 0), Vector3(0, h, 0)],
				(n * (h - y1) + Vector3.UP * b1).normalized())
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(w * 0.7, h, w * 0.7))


## A column: a base of two rolls, a shaft that narrows a little, a capital with its square abacus.
static func _column(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	c.s.surface(c.mat("stone", e.get("colour")))
	var r := size.x * 0.3
	var h := size.y
	_box(c.s, xf, Vector3(0, 0.06, 0), Vector3(r * 2.6, 0.12, r * 2.6), Basis(), [RoomMesh.DOWN])
	_lathe(c.s, xf, [Vector2(r * 1.25, 0.12), Vector2(r * 1.3, 0.18), Vector2(r * 1.1, 0.24), Vector2(r * 1.15, 0.28),
			Vector2(r, 0.34), Vector2(r * 0.86, h - 0.42), Vector2(r * 0.9, h - 0.38), Vector2(r * 1.3, h - 0.18),
			Vector2(r * 1.3, h - 0.14)], Vector3.ZERO, 16)
	_box(c.s, xf, Vector3(0, h - 0.07, 0), Vector3(r * 3.0, 0.14, r * 3.0))
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(r * 2.2, h, r * 2.2))


## A niche: pilasters either side, an arch over them, a shell hood, the recess's back darker, a shelf, and what it
## holds (an urn, a lion or an obelisk; never a figure).
static func _niche(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var stone: Material = c.mat("plaster", e.get("colour"))
	var w := size.x
	var h := size.y
	var d := maxf(size.z, 0.3)
	var inner := w * 0.5 - 0.16
	var spring := h - inner - 0.15
	c.s.surface(stone)
	for s: float in [-1.0, 1.0]:
		_box(c.s, xf, Vector3(s * (inner + 0.08), spring * 0.5, d * 0.5), Vector3(0.16, spring, d), Basis(),
				[RoomMesh.FRONT])
	Shapes.arch(c.s, xf * Vector3(0, spring, d * 0.5), inner, inner + 0.16, d, 12, xf.basis, 0.0, PI)
	_box(c.s, xf, Vector3(0, spring + inner + 0.08, d * 0.5), Vector3(w, 0.16, d), Basis(), [RoomMesh.FRONT])
	_box(c.s, xf, Vector3(0, 0.55, d * 0.6), Vector3(inner * 2.0 + 0.1, 0.06, d * 0.8))
	_box(c.s, xf, Vector3(0, 0.26, d * 0.5), Vector3(inner * 2.0, 0.52, d), Basis(), [RoomMesh.FRONT, RoomMesh.DOWN])
	c.s.surface(c.mat("plaster", _colour(e, c.colour_of("plaster")) * 0.55))
	_face(c.s, xf, [Vector3(-inner, 0.52, 0.02), Vector3(inner, 0.52, 0.02), Vector3(inner, spring, 0.02),
			Vector3(-inner, spring, 0.02)], Vector3.BACK)
	# The hood: a quarter sphere in the arch, its ribs a shell's.
	var prof: Array = []
	for i in 7:
		var lat := PI * 0.5 * i / 6.0
		prof.append(Vector2(cos(lat) * inner, sin(lat) * inner))
	prof.reverse()
	Shapes.lathe(c.s, prof, xf * Vector3(0, spring, 0.02), 8, xf.basis * Basis(Vector3.RIGHT, 0.0), PI, -PI * 0.5)
	_solid(c, xf, Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, d))
	var holds := str(e.get("holds", "urn"))
	var at := xf * Transform3D(Basis(), Vector3(0, 0.58, d * 0.45))
	var k := clampf(inner * 2.0 / 0.6, 0.5, 1.5)
	match holds:
		"urn":
			_urn(c, at * Transform3D().scaled(Vector3.ONE * minf(k, (spring - 0.6) / 1.0)), 1.0, {})
		"lion":
			_lion(c, at * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO).scaled(Vector3.ONE * minf(k * 0.6, 1.0)),
					{})
		"obelisk":
			_obelisk(c, at, Vector3(0.4 * k, spring - 0.8, 0.4), {})


# --- Façades and fronts ----------------------------------------------------------------------------------------------

## A balcony's front: a moulded parapet panel with a rail on top, bands and round bosses along it.
static func _balcony_front(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	c.s.surface(c.mat("plaster", e.get("colour")))
	_box(c.s, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, 0.12), Basis(), [RoomMesh.FRONT])
	for y: float in [0.12, h - 0.18]:
		_box(c.s, xf, Vector3(0, y, 0.08), Vector3(w, 0.06, 0.05))
	var n := maxi(int(w / 1.2), 1)
	for k in n:
		var x := (k + 0.5) * w / n - w * 0.5
		_lathe(c.s, xf, [Vector2(0.14, 0.0), Vector2(0.13, 0.03), Vector2(0.07, 0.06), Vector2(0.0, 0.07)],
				Vector3(x, h * 0.5, 0.06), 10)
	c.s.surface(c.mat("wood"))
	_box(c.s, xf, Vector3(0, h + 0.04, 0.02), Vector3(w + 0.1, 0.08, 0.22))
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, 0.16))


## A courtyard's façade on a wall: a plastered wall with a cornice and a tiled eave, two arched windows lit warm from
## inside with shutters, a little iron balcony under one.
static func _facade(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	c.s.surface(c.mat("plaster", e.get("colour")))
	_face(c.s, xf, [Vector3(-w * 0.5, 0, 0.12), Vector3(w * 0.5, 0, 0.12), Vector3(w * 0.5, h, 0.12),
			Vector3(-w * 0.5, h, 0.12)], Vector3.BACK)
	for s: float in [-1.0, 1.0]:
		_face(c.s, xf, [Vector3(s * w * 0.5, 0, 0), Vector3(s * w * 0.5, 0, 0.12), Vector3(s * w * 0.5, h, 0.12),
				Vector3(s * w * 0.5, h, 0)], Vector3(s, 0, 0))
	_box(c.s, xf, Vector3(0, h - 0.5, 0.2), Vector3(w + 0.1, 0.12, 0.16))
	# The eave: rows of round tiles on a slope.
	c.s.surface(c.mat("roof"))
	var rows := 3
	for r in rows:
		var y := h - 0.32 + r * 0.1
		var z := 0.62 - r * 0.18
		var n := int(w / 0.16)
		for k in n:
			var x := (k + 0.5) * w / n - w * 0.5
			_box(c.s, xf, Vector3(x, y, z), Vector3(0.13, 0.06, 0.24), Basis(Vector3.RIGHT, deg_to_rad(-28.0)),
					[RoomMesh.DOWN])
	var wood: Material = c.mat("wood")
	var win_w := minf(0.9, w * 0.2)
	var win_h := minf(1.6, h * 0.35)
	var sill := h * 0.38
	for s: float in [-1.0, 1.0]:
		var x := s * w * 0.22
		c.s.surface(wood)
		for t: float in [-1.0, 1.0]:
			_box(c.s, xf, Vector3(x + t * (win_w * 0.5 + 0.06), sill + win_h * 0.5, 0.14), Vector3(0.08, win_h + 0.1, 0.06))
			# Shutters, open against the wall.
			_box(c.s, xf, Vector3(x + t * (win_w * 0.5 + 0.1 + win_w * 0.25), sill + win_h * 0.45, 0.15),
					Vector3(win_w * 0.5, win_h * 0.9, 0.04))
		_box(c.s, xf, Vector3(x, sill - 0.04, 0.18), Vector3(win_w + 0.3, 0.08, 0.14))
		Shapes.arch(c.s, xf * Vector3(x, sill + win_h, 0.15), win_w * 0.5, win_w * 0.5 + 0.08, 0.06, 8, xf.basis)
		var g: Array = c.glows.get("window", [])
		g.append([xf * Vector3(x, sill + win_h * 0.5, 0.13), xf.basis.x * win_w * 0.5, xf.basis.y * win_h * 0.5,
				(xf.basis.z).normalized()])
		c.glows["window"] = g
	# An iron balcony under the left window.
	var iron: Material = c.mat("iron")
	c.s.surface(iron)
	var bx := -w * 0.22
	_box(c.s, xf, Vector3(bx, sill - 0.12, 0.4), Vector3(win_w + 0.6, 0.06, 0.55))
	for k in 9:
		var x := bx - (win_w + 0.6) * 0.5 + k * (win_w + 0.6) / 8.0
		_box(c.s, xf, Vector3(x, sill + 0.3, 0.66), Vector3(0.025, 0.8, 0.025))
	_box(c.s, xf, Vector3(bx, sill + 0.7, 0.66), Vector3(win_w + 0.62, 0.04, 0.04))
	_solid(c, xf, Vector3(0, h * 0.5, 0.06), Vector3(w, h, 0.12))


## A castle's gate round the screen: towers either side with battlements and arrow slits, a wall over the picture
## with its battlements, and a raised portcullis whose teeth hang just above the picture. Sized to the room's screen;
## nothing of it in front of the picture.
static func _castle_gate(c: Object, _xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var sc: Dictionary = c.screen
	var sxf: Transform3D = sc["xf"]
	var ss: Vector2 = sc["size"]
	var floor_y: float = sc.get("floor", sxf.origin.y - ss.y * 0.5 - 1.0)
	# The gate's frame: the screen's centre and facing, its foot at the floor under the picture.
	var xf := Transform3D(sxf.basis.orthonormalized(), Vector3(sxf.origin.x, floor_y, sxf.origin.z))
	var bottom := sxf.origin.y - ss.y * 0.5 - floor_y
	var open := ss * 0.5 + Vector2(0.35, 0.35)
	var tw := clampf(ss.x * 0.14, 1.0, 3.0)
	var d := maxf(size.z, 0.8)
	var top := bottom + ss.y + 0.35 + clampf(ss.y * 0.3, 1.0, 3.0)
	var tower_top := top + clampf(ss.y * 0.2, 0.8, 2.0)
	c.s.surface(c.mat("stone", e.get("colour")))
	for s: float in [-1.0, 1.0]:
		var x := s * (open.x + tw * 0.5)
		_box(c.s, xf, Vector3(x, tower_top * 0.5, 0.25 - d * 0.5), Vector3(tw, tower_top, d), Basis(), [RoomMesh.DOWN])
		_merlons(c, xf, x, tower_top, tw, d, 0.25 - d * 0.5)
		_solid(c, xf, Vector3(x, tower_top * 0.5, 0.25 - d * 0.5), Vector3(tw, tower_top, d))
	var lintel := bottom + ss.y + 0.35
	_box(c.s, xf, Vector3(0, (lintel + top) * 0.5, -0.1), Vector3(open.x * 2.0, top - lintel, 0.6), Basis(),
			[RoomMesh.DOWN])
	_box(c.s, xf, Vector3(0, lintel - 0.02, -0.25), Vector3(open.x * 2.0, 0.04, 0.3))
	_merlons(c, xf, 0.0, top, open.x * 2.0, 0.6, -0.1)
	c.s.surface(c.mat("iron"))
	for s: float in [-1.0, 1.0]:
		for k in 3:
			_box(c.s, xf, Vector3(s * (open.x + tw * 0.5), tower_top * (0.35 + k * 0.2), 0.27), Vector3(0.12, 0.6, 0.02))
	# The portcullis, raised: its bars and spikes just above the picture.
	var bars := maxi(int(open.x * 2.0 / 0.4), 3)
	for k in bars + 1:
		var x := -open.x + k * open.x * 2.0 / bars
		_box(c.s, xf, Vector3(x, lintel + 0.4, -0.45), Vector3(0.06, 0.9, 0.06))
		_face(c.s, xf, [Vector3(x - 0.04, lintel - 0.05, -0.42), Vector3(x + 0.04, lintel - 0.05, -0.42),
				Vector3(x, lintel - 0.2, -0.42)], Vector3.BACK)
	_box(c.s, xf, Vector3(0, lintel + 0.1, -0.45), Vector3(open.x * 2.0, 0.06, 0.06))


static func _merlons(c: Object, xf: Transform3D, x0: float, y: float, w: float, d: float, z: float) -> void:
	var n := maxi(int(w / 0.7), 2)
	for k in n:
		if k % 2 == 1:
			continue
		var x := x0 - w * 0.5 + (k + 0.5) * w / n
		_box(c.s, xf, Vector3(x, y + 0.25, z), Vector3(w / n, 0.5, d), Basis(), [RoomMesh.DOWN])


## A projection booth of corrugated tin: a hut with a sloping roof, a door on its side and a small window towards
## the screen with the projector's glow in it.
static func _booth(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	var tin: Material = c.mat("tin", e.get("colour"), "corrugated")
	c.s.surface(tin)
	var hw := w * 0.5
	var hd := d * 0.5
	var back_h := h - 0.25
	for s: float in [-1.0, 1.0]:
		_face(c.s, xf, [Vector3(s * hw, 0, -hd), Vector3(s * hw, 0, hd), Vector3(s * hw, h, hd), Vector3(s * hw, back_h, -hd)],
				Vector3(s, 0, 0))
	# The front (towards the screen: local +Z) round its window, and the back.
	var win := Rect2(hw - 0.25 - 0.35, h * 0.62, 0.35, 0.28)
	var k := xf.basis.get_scale().x
	Shapes.wall(c.s, xf * Vector3(-hw, 0, hd), xf.basis.x.normalized(), (xf.basis.z).normalized(), w * k, h * k,
			[Rect2(win.position * k, win.size * k)])
	_face(c.s, xf, [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, back_h, -hd), Vector3(-hw, back_h, -hd)],
			Vector3.FORWARD)
	c.s.surface(c.mat("tin", e.get("colour")))
	_face(c.s, xf, [Vector3(-hw - 0.1, h, hd + 0.1), Vector3(hw + 0.1, h, hd + 0.1), Vector3(hw + 0.1, back_h, -hd - 0.1),
			Vector3(-hw - 0.1, back_h, -hd - 0.1)], Vector3(0, hd * 2.0, -0.25).normalized())
	c.s.surface(c.mat("wood"))
	_box(c.s, xf, Vector3(-hw - 0.01, 0.95, 0.0), Vector3(0.03, 1.9, 0.75))
	var g: Array = c.glows.get("booth", [])
	g.append([xf * Vector3(win.get_center().x - hw, win.get_center().y, hd + 0.005), xf.basis.x * win.size.x * 0.5,
			xf.basis.y * win.size.y * 0.5, xf.basis.z.normalized()])
	c.glows["booth"] = g
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, d))


## A snack bar: a counter, its back wall and shelves, a canopy on posts, and a neon sign on the canopy ("SNACKS",
## or the entry's text: our own letters).
static func _snack_bar(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	var body: Material = c.mat("plaster", e.get("colour"))
	c.s.surface(body)
	_box(c.s, xf, Vector3(0, 0.55, d * 0.5 - 0.4), Vector3(w, 1.1, 0.8), Basis(), [RoomMesh.DOWN])
	_box(c.s, xf, Vector3(0, h * 0.5, -d * 0.5 + 0.1), Vector3(w, h, 0.2), Basis(), [RoomMesh.DOWN])
	for s: float in [-1.0, 1.0]:
		_box(c.s, xf, Vector3(s * (w * 0.5 - 0.05), h * 0.5, 0.0), Vector3(0.1, h, d), Basis(), [RoomMesh.DOWN])
	c.s.surface(c.mat("wood"))
	_box(c.s, xf, Vector3(0, 1.13, d * 0.5 - 0.38), Vector3(w + 0.1, 0.06, 0.9))
	for k in 2:
		_box(c.s, xf, Vector3(0, 1.5 + k * 0.4, -d * 0.5 + 0.32), Vector3(w - 0.4, 0.04, 0.25))
	c.s.surface(c.mat("tin", e.get("accent")))
	_box(c.s, xf, Vector3(0, h + 0.06, 0.25), Vector3(w + 0.6, 0.12, d + 0.9))
	var text := str(e.get("text", "SNACKS")).to_upper()
	var sign_w := clampf(text.length() * 0.42, 1.0, w)
	var sign := [xf * Vector3(0, h + 0.45, d * 0.5 + 0.55), xf.basis.x * sign_w * 0.5, xf.basis.y * 0.3,
			xf.basis.z.normalized()]
	c.signs.append([sign, text])
	_box(c.s, xf, Vector3(0, h + 0.45, d * 0.5 + 0.5), Vector3(sign_w + 0.2, 0.7, 0.08))
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, d))
	c.lamps.append([xf * Vector3(0, h - 0.3, d * 0.5), Color(1.0, 0.85, 0.6)])


## A drive-in's screen tower behind the room's screen: the face round the picture, posts and diagonal braces behind,
## sized to the screen and standing on the floor under it.
static func _screen_tower(c: Object, _xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var sc: Dictionary = c.screen
	var sxf: Transform3D = sc["xf"]
	var ss: Vector2 = sc["size"]
	var floor_y: float = sc.get("floor", sxf.origin.y - ss.y * 0.5 - 1.0)
	var xf := Transform3D(sxf.basis.orthonormalized(), Vector3(sxf.origin.x, floor_y, sxf.origin.z))
	var bottom := sxf.origin.y - ss.y * 0.5 - floor_y
	var w := ss.x + 2.0
	var top := bottom + ss.y + 1.0
	var d := maxf(size.z, 1.0)
	c.s.surface(c.mat("plaster", e.get("colour")))
	_box(c.s, xf, Vector3(0, (bottom - 0.6 + top) * 0.5, -0.15), Vector3(w, top - bottom + 0.6, 0.2), Basis(),
			[RoomMesh.DOWN])
	c.s.surface(c.mat("wood"))
	var posts := maxi(int(w / 4.0), 2) + 1
	for k in posts:
		var x := -w * 0.5 + k * w / (posts - 1)
		_box(c.s, xf, Vector3(x, top * 0.5, -0.35), Vector3(0.3, top, 0.3), Basis(), [RoomMesh.DOWN])
		Shapes.beam(c.s, xf * Vector3(x, top * 0.75, -0.4), xf * Vector3(x, 0.0, -0.4 - d * 3.0), Vector2(0.22, 0.22))
		for y: float in [top * 0.35, top * 0.7]:
			if k < posts - 1:
				_box(c.s, xf, Vector3(x + w / (posts - 1) * 0.5, y, -0.4), Vector3(w / (posts - 1), 0.15, 0.12))
	_solid(c, xf, Vector3(0, top * 0.5, -0.3), Vector3(w, top, 0.6))


## A plasterboard partition across a hall: both faces with the board's taped joints, its top and ends, a skirting.
static func _partition(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var t := maxf(size.z, 0.08)
	c.s.surface(c.mat("plaster", e.get("colour"), "plasterboard"))
	_box(c.s, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, t), Basis(), [RoomMesh.DOWN])
	c.s.surface(c.mat("wood"))
	for s: float in [-1.0, 1.0]:
		_box(c.s, xf, Vector3(0, 0.05, s * (t * 0.5 + 0.01)), Vector3(w, 0.1, 0.02), Basis(), [RoomMesh.DOWN])
	_solid(c, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, t))


## Curves on a wall: two bands that sweep along it in waves (a pink one and a blue one by default).
static func _curves(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var second: Variant = e.get("accent")
	var colours: Array[Color] = [_colour(e, Color(0.86, 0.45, 0.6)),
			_to_color(second) if second != null else Color(0.35, 0.55, 0.85)]
	for k in 2:
		c.s.surface(c.mat("plaster", colours[k]))
		var a := PackedVector3Array()
		var b := PackedVector3Array()
		var ns := PackedVector3Array()
		var n := maxi(24, int(w * 4.0))
		for i in n + 1:
			var t := float(i) / n
			# Gentle waves along the wall, whatever its length: about one wave in six metres.
			var waves := maxf(w / 6.0, 0.75)
			var y := h * (0.4 + 0.16 * k) + minf(h * 0.1, 0.5) * sin(t * TAU * waves + k * 1.3)
			var band := minf(h * 0.08, 0.35)
			a.append(xf * Vector3((t - 0.5) * w, y, 0.03 + 0.01 * k))
			b.append(xf * Vector3((t - 0.5) * w, y + band, 0.03 + 0.01 * k))
			ns.append(xf.basis.z.normalized())
		c.s.strip(a, b, ns)


## The floor's carpet: the builder's Floor (or the entry's target node) takes the swirling pattern.
static func _carpet(c: Object, e: Dictionary) -> void:
	var node := (c.room as Node).get_node_or_null(str(e.get("target", "Floor"))) as MeshInstance3D
	if node == null:
		return
	var colour := _colour(e, Color(0.4, 0.12, 0.2))
	for s in node.mesh.get_surface_count():
		var m := node.mesh.surface_get_material(s) as ShaderMaterial
		if m != null and m.shader != null and m.get_shader_parameter("albedo_map") != null:
			Procedural.apply(m, "swirl_carpet", colour)
			c.carpeted.append(m)
		break


# --- Plants (unbaked: leaves) -----------------------------------------------------------------------------------

## Bougainvillea over a wall's or a parapet's top: green leaves in a mass along it, falling down the face, magenta
## bracts in clusters among them.
static func _bougainvillea(c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var w := size.x
	var drop := size.y
	var leaf: Material = c.mat("leaves", c.colour_of("leaves"))
	var flower: Material = c.mat("flowers", _colour(e, c.colour_of("flowers")))
	var rng: RandomNumberGenerator = c.rng
	# Over the top (from behind the slot's point to in front of it), then down the face in front of it (a parapet's
	# slot is its middle line: its face is depth / 2 in front). Clusters of leaves, some of bracts, densest at the top.
	var front := size.z * 0.5
	var clusters := int(w * 14)
	for i in clusters:
		var x := rng.randf_range(-0.5, 0.5) * w
		var hang := pow(rng.randf(), 1.8) * drop * (0.55 + 0.45 * sin(x * 2.1 + 1.0))
		var centre := Vector3(x, -hang + 0.08, rng.randf_range(-front, front + 0.2) if hang < 0.15
				else front + rng.randf_range(0.06, 0.2))
		var bloom := rng.randf() < 0.45
		var radius := rng.randf_range(0.12, 0.24)
		for j in 14:
			var is_flower := bloom and rng.randf() < 0.75
			c.u.surface(flower if is_flower else leaf)
			var at := centre + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5)) * radius
			at.z = maxf(at.z, -front) if hang < 0.15 else maxf(at.z, front + 0.02)
			var leaf_len := rng.randf_range(0.08, 0.13) * (0.75 if is_flower else 1.0)
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1.0, 0.5), rng.randf_range(0.1, 1.0)).normalized()
			var across := dir.cross(Vector3.BACK).normalized() * leaf_len * 0.45
			if across.length() < 0.001:
				across = Vector3.RIGHT * leaf_len * 0.45
			Shapes.leaf(c.u, xf * at, xf.basis * (dir * leaf_len), xf.basis * across,
					(xf.basis * dir.cross(across)).normalized())


## Ivy over a wall: stems climbing from the foot, leaves along them, thicker low down.
static func _ivy(c: Object, xf: Transform3D, size: Vector3, _e: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var leaf: Material = c.mat("leaves", c.colour_of("leaves") * 0.75)
	var rng: RandomNumberGenerator = c.rng
	c.u.surface(leaf)
	var stems := maxi(int(w * 6.0), 2)
	for s in stems:
		var p := Vector3(rng.randf_range(-0.5, 0.5) * w, 0.0, 0.02)
		var top := rng.randf_range(0.3, 1.0) * h
		while p.y < top:
			var next := p + Vector3(rng.randf_range(-0.14, 0.14), rng.randf_range(0.07, 0.13), 0.0)
			next.x = clampf(next.x, -w * 0.5, w * 0.5)
			for k in 3:
				var side := -1.0 if k == 0 else (1.0 if k == 1 else rng.randf_range(-1.0, 1.0))
				var at := p.lerp(next, rng.randf()) + Vector3(side * 0.05, 0, 0.01 + rng.randf() * 0.04)
				var leaf_len := rng.randf_range(0.08, 0.13) * (1.2 - 0.4 * p.y / h)
				var along := Vector3(side * rng.randf_range(0.3, 1.0), rng.randf_range(-0.6, 0.6), 0.25).normalized() * leaf_len
				var across := Vector3(-along.y, along.x, 0).normalized() * leaf_len * 0.55
				Shapes.leaf(c.u, xf * at, xf.basis * along, xf.basis * across, (xf.basis * Vector3.BACK).normalized())
			p = next


## Ferns in a clump on the floor: fronds arching out from the middle, leaflets along each.
static func _ferns(c: Object, xf: Transform3D, size: Vector3, _e: Dictionary) -> void:
	var leaf: Material = c.mat("leaves", c.colour_of("leaves") * 1.1)
	var rng: RandomNumberGenerator = c.rng
	c.u.surface(leaf)
	var fronds := 9
	var reach := size.x * 0.5
	for f in fronds:
		var a := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(sin(a), 0, cos(a))
		var lift := rng.randf_range(0.6, 1.0) * size.y
		var prev := Vector3(0, 0.02, 0)
		for i in range(1, 11):
			var t := i / 10.0
			var p := dir * reach * t + Vector3.UP * (lift * sin(t * PI * 0.75))
			var along := (p - prev)
			var side := dir.cross(Vector3.UP).normalized()
			var leaf_len := 0.12 * (1.0 - t * 0.7) * reach
			for s: float in [-1.0, 1.0]:
				Shapes.leaf(c.u, xf * p, xf.basis * (side * s * leaf_len + along * 0.3), xf.basis * (along.normalized() * leaf_len * 0.25),
						(xf.basis * Vector3.UP).normalized())
			prev = p
