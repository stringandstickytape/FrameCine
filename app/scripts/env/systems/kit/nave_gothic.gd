extends RefCounted

## The Nave's church (nave.gd with style "gothic"; docs/environments.md, "Room: Nave"): a Gothic nave at night, made
## for the deep pass of 2026-11-08 ("really improving their quality, imagination, delight, detail, lighting", the
## user). The builder lays it out from its parameters (the seats, the screen and the chancel where they were); this
## draws it, into the builder's meshes:
##   - clustered piers of pale limestone with four dark polished shafts (Purbeck-like marble), moulded bases,
##     foliage capitals; pointed arcade arches of two chamfered orders under a hood mould
##   - a triforium of small pointed openings on colonnettes, string courses, a clerestory of two-light windows with
##     bar tracery; vaulting shafts from the piers' capitals to the vault
##   - a quadripartite rib vault over the nave, the chancel and the aisles: webs of lime-washed stone, moulded ribs,
##     foliage bosses
##   - aisles with two-light windows of coloured glass, wall shafts, their own vaults; a lancet in each aisle's east
##     wall
##   - a chancel arch of two orders on shafts, three steps, a wider chancel with a rose window over the screen, a
##     two-light window either side
##   - the west wall with a three-light window and a pointed doorway
##   - a floor of worn flagstones, each its own shade, a little uneven, in mortar
## Stained glass is drawn here (no figures: geometric and floral, our own), lit faintly by the Moon outside; the Moon's
## light comes in through the south windows for the bake (a hidden directional light).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Strokes := preload("res://scripts/env/systems/kit/strokes.gd")
const IceHall := preload("res://scripts/env/systems/kit/ice_hall.gd")
const U := preload("res://scripts/env/systems/kit/build_util.gd")
const RoomSchemaRef := preload("res://scripts/assistant/room_schema.gd")
const ProcCache := preload("res://scripts/env/proc_cache.gd")

## The arcade's wall, thick: its faces either side of the columns' line.
const WALL_T := 0.8
## The vault's crown over its springing, as a share of the nave's width (a pointed vault).
const CROWN := 0.6
## The arcade's arches: their clear half span short of half the bay, and their rise.
const ARCADE_INSET := 0.52
const ARCADE_RISE := 2.15
## The string courses under and over the triforium.
const STRING_LOW := 8.1
const STRING_HIGH := 9.8
## The chancel's half width when the builder's chancel_width is 0 (wider than the nave between its arcades).
const CHANCEL_EXTRA := 0.6
## The chancel's vault springs lower than the nave's.
const CHANCEL_SPRING := 11.0
## The chancel arch: its clear half span, its rise, the wall it is cut through.
const CHANCEL_ARCH_A := 2.95
const CHANCEL_ARCH_H := 4.6
const DIAPHRAGM_T := 0.9
## The aisles' vaults: their rise over the piers' capitals.
const AISLE_RISE := 2.9
## The shafts: the piers' four (polished dark marble), the vaulting shafts', the wall shafts'.
const SHAFT_R := 0.12
const VSHAFT_R := 0.105
## The Moon's direction (towards it): high in the south, so its light comes in through the south windows
## (the right as one faces the screen, which is east) and falls across the south aisle's floor.
const MOON_DIR := Vector3(0.55, 0.83, -0.04)
const MOON_COLOUR := Color(0.62, 0.72, 1.0)
## The rose's glass disc, as a share of its tracery's radius (the picture's rim).
const ROSE_GLASS := 1.05
## The Moon's coloured pools on the south aisle's floor: their height over it, from where across (the pews' ends), and
## their glow as a share of the windows'.
const POOL_Y := 0.008
const POOL_FROM := 2.85
const POOL_SHARE := 1.6
## The reredos keeps this far from the picture (the masking round it is half the screen frame's margin).
const REREDOS_CLEAR := 0.17
## Metres a lightmap texel covers: the walls, the carved work, the vaults' webs, the floor. The headset bakes the
## room when it is first chosen; these keep its atlases near a million texels in all, so the bake takes seconds.
const STONE_TEXEL := 0.2
const CARVE_TEXEL := 0.4
const WEB_TEXEL := 0.3
const FLOOR_TEXEL := 0.2
## Candlelight: the flames' colour, their picture's half size and glow (ice_hall.gd's picture); the wax lit through
## near the flame (linear, emission: a candle is as bright as its group).
const FLAME := Color(1.0, 0.62, 0.3)
const FLAME_HALF := 0.075
const FLAME_ENERGY := 1.8
const WAX_FOOT := Color(0.16, 0.12, 0.08)
const WAX_TOP := Color(0.95, 0.62, 0.3)
const WAX_POOL := Color(1.0, 0.7, 0.36)
## The chancel's candle stands: each one's light in the bake (reach, energy) and, before a bake, its share of the
## stand-in lamp a side.
const STAND_REACH := 6.0
const STAND_LIGHT := 0.9
const STAND_LAMP := 0.6
## The coronae over the nave: their height, radius and candles; the light of each in the bake and its stand-in.
const CORONA_Y := 7.0
const CORONA_R := 0.8
const CORONA_CANDLES := 12
const CORONA_REACH := 10.0
const CORONA_LIGHT := 0.75
const CORONA_LAMP := 2.0
## The votive stand's light.
const VOTIVE_REACH := 4.0
const VOTIVE_LIGHT := 0.8
const VOTIVE_LAMP := 0.8
## Hymn books' cloth bindings, and hassocks worked in wool (linear tints on the cloth material).
const BOOK_COLOURS: Array[Color] = [Color(0.2, 0.05, 0.05), Color(0.06, 0.07, 0.14), Color(0.05, 0.05, 0.055),
		Color(0.07, 0.12, 0.07)]
const HASSOCKS: Array[Color] = [Color(0.36, 0.09, 0.07), Color(0.09, 0.13, 0.28), Color(0.1, 0.2, 0.11),
		Color(0.38, 0.28, 0.09), Color(0.24, 0.09, 0.17)]


## What the church is drawn into, and its layout (from the builder's parameters).
class Church:
	var n: Node
	var p: Dictionary
	var rng := RandomNumberGenerator.new()
	## The walls' faces (lightmap texels of STONE_TEXEL) and the carved work: capitals, mouldings, ribs, tracery
	## (coarser texels: the light on them varies slowly, and their many small charts would fill the atlas).
	var stone := RoomMesh.new()
	var carve := RoomMesh.new()
	var marble := RoomMesh.new()
	var webs := RoomMesh.new()
	var flags := RoomMesh.new()
	## The pews, the reredos, the doors (oak); the hassocks and the books (cloth); the candle stands and the coronae
	## (iron); the reredos's gilding and the hymn board's figures (gilt).
	var oak := RoomMesh.new()
	var cloth := RoomMesh.new()
	var iron := RoomMesh.new()
	var gilt := RoomMesh.new()
	## Candles by light group: their wax (lit by their own flames: vertex colours on a lamp material) and their
	## flames' quads ([centre, half across, half up, facing]); every candle [flame position, group].
	var wax := {}
	var flames := {}
	var candles: Array = []
	## Glass: [{"pts": PackedVector3Array (an outline), "uvs": PackedVector2Array, "normal"}] for the windows' atlas and
	## the rose.
	var glass: Array = []
	var rose_glass: Array = []
	## The windows' pictures: spec -> atlas cell.
	var specs: Array = []
	var nh := 3.8
	var face := 3.4
	var ow := 6.4
	var cz := -6.5
	var ez := -10.5
	var rz := 7.5
	var rise := 0.54
	var col_h := 5.0
	var wall_h := 12.0
	var crown := 16.56
	var ch := 4.4
	var lines: Array[float] = []
	## The ledger stones in the floor (x, z): the flags are laid round them.
	var ledgers: Array[Rect2] = []
	## The south windows the Moon shines through: [the glass's middle (a little inside), share of the moonlight,
	## the spot's half angle].
	var moon_windows: Array = []
	var screen_c := Vector3.ZERO
	var screen_s := Vector2.ZERO


# --- Building ---------------------------------------------------------------------------------------------------------

## The church into the builder `n` (nave.gd): its meshes added, its bake lights given to the light system.
static func build(n: Node) -> Church:
	var c := Church.new()
	c.n = n
	c.p = n.params
	c.rng.seed = 1268
	_layout(c)
	var stone_colour := RoomSchemaRef.to_color(c.p["stone"].get("color", "#8a8070"))
	var ashlar: ShaderMaterial = n._mat("stone")
	_apply_maps(ashlar, _stone_maps("ashlar"), stone_colour)
	var dressed: ShaderMaterial = n._mat("stone")
	_apply_maps(dressed, _stone_maps("grain"), stone_colour.lightened(0.06))
	dressed.set_shader_parameter("tiling", 1.1)
	var paving: ShaderMaterial = n._mat("floor")
	_apply_maps(paving, _stone_maps("flag"), RoomSchemaRef.to_color(c.p["floor"].get("color", "#706860")))
	_m(c, c.stone, ashlar)
	_m(c, c.carve, dressed)
	_m(c, c.marble, n._mat("columns"))
	_m(c, c.webs, n._patterned("webs", "lime_wash"))
	_m(c, c.flags, paving)
	_m(c, c.oak, n._mat("pews"))
	_m(c, c.cloth, n._mat("cloth"))
	_m(c, c.iron, n._mat("iron"))
	_m(c, c.gilt, n._mat("brass"))
	c.stone.texel = STONE_TEXEL
	c.carve.texel = CARVE_TEXEL
	c.marble.texel = CARVE_TEXEL
	c.webs.texel = WEB_TEXEL
	c.flags.texel = FLOOR_TEXEL
	c.oak.texel = CARVE_TEXEL
	c.cloth.texel = CARVE_TEXEL
	c.iron.texel = CARVE_TEXEL
	c.gilt.texel = CARVE_TEXEL
	_floor(c)
	for z: float in c.lines:
		for s: float in [-1.0, 1.0]:
			if z > c.cz + 0.01:
				_pier(c, Vector3(s * c.nh, 0.0, z))
	for s: float in [-1.0, 1.0]:
		_pier(c, Vector3(s * c.nh, 0.0, c.cz))
		_arcade(c, s)
		_upper(c, s)
		_aisle(c, s)
	_nave_vault(c)
	_chancel(c)
	_west(c)
	if not n.draws_seats_elsewhere():
		_pews(c)
	_stands(c, int(c.p["candles"]))
	for k in int(c.p["coronae"]):
		_corona(c, k, bool(c.p["coronae_lit"]))
	if bool(c.p["votive"]):
		_votive(c)
	_reredos(c)
	_hymn_board(c, 1.8)
	_ledgers(c)
	c.stone.shade(_stone_tone)
	c.carve.shade(_stone_tone)
	c.webs.shade(_web_tone)
	_add_candles(c)
	for e: Array in [["Stone", c.stone], ["Carving", c.carve], ["Shafts", c.marble], ["Vault", c.webs],
			["Floor", c.flags], ["Pews", c.oak], ["Cloth", c.cloth], ["Iron", c.iron], ["Gilt", c.gilt]]:
		var mi: MeshInstance3D = n._add_static(str(e[0]), e[1])
		# The church's stone shadows the bake's lights (the Moon through the windows, the candles' pools): the
		# lightmapper leaves out meshes that cast no shadow. No live light casts one, so it costs nothing at run time.
		if mi != null:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_add_glass(c)
	_moon(c)
	return c


static func _m(c: Church, b: RoomMesh, m: ShaderMaterial) -> void:
	m.set_shader_parameter("instance_tint", true)
	b.surface(m)


static func _layout(c: Church) -> void:
	var p := c.p
	c.nh = float(p["nave_width"]) * 0.5
	c.face = c.nh - WALL_T * 0.5
	c.ow = c.nh + float(p["aisle_width"])
	c.cz = float(p["chancel_z"])
	c.ez = c.cz - float(p["chancel_depth"])
	c.rz = float(p["rear_z"])
	c.rise = float(p["chancel_rise"])
	c.col_h = float(p["column_height"])
	c.wall_h = float(p["wall_height"])
	c.crown = c.wall_h + float(p["nave_width"]) * CROWN
	c.ch = float(p["chancel_width"]) * 0.5 if float(p["chancel_width"]) > 0.0 else c.nh + CHANCEL_EXTRA
	c.lines.clear()
	var z := c.cz
	var bay := float(p["bay"])
	while z < c.rz - bay * 0.5:
		c.lines.append(z)
		z += bay
	c.lines.append(c.rz)
	# Ledger stones: in the aisles between the piers' bases and the wall's bench, and two across the nave before the
	# chancel step.
	var ax := (c.ow + c.nh + WALL_T * 0.5) * 0.5
	c.ledgers = [Rect2(-ax - 0.45, -3.3, 0.9, 1.9), Rect2(ax - 0.45, 0.25, 0.9, 1.9), Rect2(-ax - 0.45, 3.6, 0.9, 1.9),
			Rect2(ax - 0.45, -5.6, 0.9, 1.9), Rect2(-2.05, c.cz + 0.58, 1.8, 0.85), Rect2(0.25, c.cz + 0.58, 1.8, 0.85)]
	var sc: Dictionary = c.n.call("screen")
	c.screen_c = U.v3(sc["center"])
	c.screen_s = U.v2(sc["size"])


# --- Arches -----------------------------------------------------------------------------------------------------------

## A pointed (two-centred) arch over half span a rising h: (its radius, the right half's centre across, 0 or less).
static func _pointed(a: float, h: float) -> Vector2:
	var r := (a * a + h * h) / (2.0 * a)
	return Vector2(r, a - r)


## A point of the arch's curve drawn `off` out from it (its centres kept): side -1 the left half, 1 the right; s from
## 0 at the springing to 1 at the apex. [Vector2(across, up), Vector2 the radial direction outward].
static func _arc(a: float, h: float, off: float, side: float, s: float) -> Array:
	var rc := _pointed(a, h)
	var big := rc.x + off
	var apex := acos(clampf(-rc.y / big, -1.0, 1.0))
	var t := apex * s
	return [Vector2(side * (rc.y + big * cos(t)), big * sin(t)), Vector2(side * cos(t), sin(t))]


## The height of a pointed vault's curve over its springing, x across from its middle (half span a, rise h).
static func _fv(a: float, h: float, x: float) -> float:
	var rc := _pointed(a, h)
	var d := absf(x) - rc.y
	return sqrt(maxf(rc.x * rc.x - d * d, 0.0))


## A profile's step normal (2D), facing away from `inside` (a point within the solid).
static func _n2(p0: Vector2, p1: Vector2, inside: Vector2) -> Vector2:
	var e := p1 - p0
	var nn := Vector2(e.y, -e.x).normalized()
	if nn.dot((p0 + p1) * 0.5 - inside) < 0.0:
		nn = -nn
	return nn


## Mouldings along a pointed arch: centre (the springing line's middle), u_dir across the opening, across through
## the wall; profile [Vector2(t across, d out from the arch's curve)], the solid round `inside`. A strip a step of the
## profile and a half of the arch.
static func _arch_sweep(b: RoomMesh, centre: Vector3, u_dir: Vector3, across: Vector3, a: float, h: float,
		profile: Array, inside: Vector2, seg := 10, up := Vector3.UP, s0 := 0.0) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var nn := _n2(p0, p1, inside)
		for side: float in [-1.0, 1.0]:
			var la := PackedVector3Array()
			var lb := PackedVector3Array()
			var ns := PackedVector3Array()
			for k in seg + 1:
				var s := lerpf(s0, 1.0, float(k) / seg)
				var q0: Array = _arc(a, h, p0.y, side, s)
				var q1: Array = _arc(a, h, p1.y, side, s)
				var r: Vector2 = q0[1]
				var radial := u_dir * r.x + up * r.y
				la.append(centre + u_dir * (q0[0] as Vector2).x + up * (q0[0] as Vector2).y + across * p0.x)
				lb.append(centre + u_dir * (q1[0] as Vector2).x + up * (q1[0] as Vector2).y + across * p1.x)
				ns.append((across * nn.x + radial * nn.y).normalized())
			b.strip(la, lb, ns)


## The same mouldings down the jambs under the arch, from the springing down to `foot` (metres under it).
static func _jamb_sweep(b: RoomMesh, centre: Vector3, u_dir: Vector3, across: Vector3, a: float, foot: float,
		profile: Array, inside: Vector2) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var nn := _n2(p0, p1, inside)
		for side: float in [-1.0, 1.0]:
			var out := u_dir * side
			var la := PackedVector3Array()
			var lb := PackedVector3Array()
			var ns := PackedVector3Array()
			for y: float in [-foot, 0.0]:
				la.append(centre + out * (a + p0.y) + Vector3.UP * y + across * p0.x)
				lb.append(centre + out * (a + p1.y) + Vector3.UP * y + across * p1.x)
				ns.append((across * nn.x + out * nn.y).normalized())
			b.strip(la, lb, ns)


## Mouldings along any line: points, and at each its side (profile t) and out (profile d) directions.
static func _curve_sweep(b: RoomMesh, pts: Array, sides: Array, outs: Array, profile: Array, inside: Vector2) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var nn := _n2(p0, p1, inside)
		var la := PackedVector3Array()
		var lb := PackedVector3Array()
		var ns := PackedVector3Array()
		for k in pts.size():
			var side: Vector3 = sides[k]
			var out: Vector3 = outs[k]
			la.append(pts[k] + side * p0.x + out * p0.y)
			lb.append(pts[k] + side * p1.x + out * p1.y)
			ns.append((side * nn.x + out * nn.y).normalized())
		b.strip(la, lb, ns)


## A line's frames for _curve_sweep: out the way `up` leans off the line, side across it.
static func _frames(pts: Array, up: Vector3) -> Array:
	var sides: Array = []
	var outs: Array = []
	for k in pts.size():
		var t: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var out := (up - t * up.dot(t)).normalized()
		sides.append(t.cross(out).normalized())
		outs.append(out)
	return [sides, outs]


## A profile mirrored across its t (the other side of a wall), its order kept so it still runs one way.
static func _mirror(profile: Array) -> Array:
	var out: Array = []
	for i in range(profile.size() - 1, -1, -1):
		out.append(Vector2(-(profile[i] as Vector2).x, (profile[i] as Vector2).y))
	return out


# --- Walls ------------------------------------------------------------------------------------------------------------

## A wall's face in the vertical plane through origin (u along it, a unit; normal its front): from u0 to u1 along and
## from v0 up to top (a float, or a Callable of the place along), with pointed openings [{c, a, h, off, spring, sill}]
## (their outline drawn `off` out from the arch; open from the sill up). Rows and columns of about a metre, so the
## stone's tone varies over it.
static func _panel(b: RoomMesh, origin: Vector3, u: Vector3, normal: Vector3, u0: float, u1: float, v0: float,
		top: Variant, holes: Array = [], seg := 8) -> void:
	var sorted := holes.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["c"]) < float(y["c"]))
	var x := u0
	for hole: Dictionary in sorted:
		var hc := float(hole["c"])
		var off := float(hole.get("off", 0.0))
		var a := float(hole["a"])
		var h := float(hole["h"])
		var spring := float(hole["spring"])
		var half := a + off
		if hc - half > x + 0.001:
			_solid(b, origin, u, normal, x, hc - half, v0, top)
		var sill := float(hole.get("sill", v0))
		if sill > v0 + 0.001:
			_solid(b, origin, u, normal, hc - half, hc + half, v0, sill)
		# Over the opening: from its arch up to the top, in rows.
		var arc: Array[Vector2] = []
		for k in seg * 2 + 1:
			var side := -1.0 if k <= seg else 1.0
			var s := float(k) / seg if k <= seg else float(seg * 2 - k) / seg
			var q: Vector2 = _arc(a, h, off, side, s)[0]
			arc.append(Vector2(hc + q.x, spring + q.y))
		var tallest := 0.0
		for q: Vector2 in arc:
			tallest = maxf(tallest, _top_at(top, q.x) - q.y)
		var rows := maxi(1, ceili(tallest / 1.4))
		for j in rows:
			var la := PackedVector3Array()
			var lb := PackedVector3Array()
			var ns := PackedVector3Array()
			for q: Vector2 in arc:
				var t := _top_at(top, q.x)
				la.append(origin + u * q.x + Vector3.UP * lerpf(q.y, t, float(j) / rows))
				lb.append(origin + u * q.x + Vector3.UP * lerpf(q.y, t, float(j + 1) / rows))
				ns.append(normal)
			b.strip(la, lb, ns)
		x = hc + half
	if u1 > x + 0.001:
		_solid(b, origin, u, normal, x, u1, v0, top)


static func _top_at(top: Variant, at: float) -> float:
	return float((top as Callable).call(at)) if top is Callable else float(top)


## A plain stretch of a wall's face, in rows and columns of about a metre.
static func _solid(b: RoomMesh, origin: Vector3, u: Vector3, normal: Vector3, x0: float, x1: float, v0: float,
		top: Variant) -> void:
	var cols := maxi(1, ceili((x1 - x0) / 1.1))
	if top is Callable:
		cols = maxi(cols, ceili((x1 - x0) / 0.35))
	var tallest := 0.0
	for k in cols + 1:
		tallest = maxf(tallest, _top_at(top, lerpf(x0, x1, float(k) / cols)) - v0)
	if tallest <= 0.001:
		return
	var rows := maxi(1, ceili(tallest / 1.3))
	for j in rows:
		var la := PackedVector3Array()
		var lb := PackedVector3Array()
		var ns := PackedVector3Array()
		for k in cols + 1:
			var at := lerpf(x0, x1, float(k) / cols)
			var t := _top_at(top, at)
			la.append(origin + u * at + Vector3.UP * lerpf(v0, t, float(j) / rows))
			lb.append(origin + u * at + Vector3.UP * lerpf(v0, t, float(j + 1) / rows))
			ns.append(normal)
		b.strip(la, lb, ns)


## An opening's reveal: from the face's outline into the wall by `depth`, drawn in by `splay` there; its sill rising
## by `drop` to the depth (a window's sloping sill). Returns the outline at the depth, as (along, up) from the left
## foot round to the right foot.
static func _reveal(b: RoomMesh, origin: Vector3, u: Vector3, normal: Vector3, hole: Dictionary, depth: float,
		splay: float, seg := 8, drop := 0.0, with_sill := true) -> Array[Vector2]:
	var hc := float(hole["c"])
	var a := float(hole["a"])
	var h := float(hole["h"])
	var spring := float(hole["spring"])
	var sill := float(hole.get("sill", 0.0))
	var la := PackedVector3Array()
	var lb := PackedVector3Array()
	var ns := PackedVector3Array()
	var inner: Array[Vector2] = []
	var into := -normal * depth
	# Up the left jamb, over the arch, down the right jamb.
	var pts: Array = [[-1.0, -1.0], [-1.0, 0.0]]
	for k in range(1, seg * 2):
		pts.append([0.0, float(k)])
	pts.append_array([[1.0, 0.0], [1.0, -1.0]])
	for e: Array in pts:
		var face_p: Vector2
		var deep_p: Vector2
		var nrm: Vector3
		if float(e[0]) != 0.0:
			var side := float(e[0])
			var y := sill if float(e[1]) < 0.0 else spring
			face_p = Vector2(hc + side * a, y)
			deep_p = Vector2(hc + side * (a - splay), y + (drop if float(e[1]) < 0.0 else 0.0))
			nrm = -u * side
		else:
			var k := int(e[1])
			var side := -1.0 if k <= seg else 1.0
			var s := float(k) / seg if k <= seg else float(seg * 2 - k) / seg
			var q0: Array = _arc(a, h, 0.0, side, s)
			var q1: Array = _arc(a, h, -splay, side, s)
			face_p = (q0[0] as Vector2) + Vector2(hc, spring)
			deep_p = (q1[0] as Vector2) + Vector2(hc, spring)
			var r: Vector2 = q0[1]
			nrm = -(u * r.x + Vector3.UP * r.y)
		la.append(origin + u * face_p.x + Vector3.UP * face_p.y)
		lb.append(origin + u * deep_p.x + Vector3.UP * deep_p.y + into)
		ns.append(nrm.normalized())
		inner.append(deep_p)
	b.strip(la, lb, ns)
	if with_sill:
		var l0 := origin + u * (hc - a) + Vector3.UP * sill
		var r0 := origin + u * (hc + a) + Vector3.UP * sill
		var l1 := origin + u * (hc - a + splay) + Vector3.UP * (sill + drop) + into
		var r1 := origin + u * (hc + a - splay) + Vector3.UP * (sill + drop) + into
		b.face([l0, r0, r1, l1], (Vector3.UP + normal * (drop / maxf(depth, 0.01))).normalized())
	return inner


## A horizontal moulding along a wall's face (a string course): from a to c at its height, out of the wall along
## `normal` (the face's front).
static func _string(b: RoomMesh, a: Vector3, c: Vector3, normal: Vector3, big := 1.0) -> void:
	var prof: Array = [Vector2(-0.07, 0.0), Vector2(-0.05, 0.09), Vector2(0.03, 0.11), Vector2(0.07, 0.07),
			Vector2(0.08, 0.0)]
	var scaled: Array = []
	for q: Vector2 in prof:
		scaled.append(q * big)
	_curve_sweep(b, [a, c], [Vector3.UP, Vector3.UP], [normal, normal], scaled, Vector2(0.0, 0.02))


# --- The floor --------------------------------------------------------------------------------------------------------

## Flagstones in courses across the church, each its own size, shade and tilt (a few millimetres), in mortar; the
## chancel's larger, up its three steps.
static func _floor(c: Church) -> void:
	var b := c.flags
	# The mortar under the joints.
	b.colour = Color(0.42, 0.4, 0.37)
	b.face([Vector3(-c.ow, -0.006, c.cz), Vector3(c.ow, -0.006, c.cz), Vector3(c.ow, -0.006, c.rz),
			Vector3(-c.ow, -0.006, c.rz)], Vector3.UP)
	_flags(c, Rect2(-c.ow, c.cz, c.ow * 2.0, c.rz - c.cz), 0.0, Vector2(0.5, 1.15), Vector2(0.5, 0.78))
	# The chancel: its floor, up three steps under the arch.
	var top := c.cz - DIAPHRAGM_T * 0.5 + 0.2
	b.colour = Color(0.4, 0.38, 0.35)
	b.face([Vector3(-c.ch, c.rise - 0.006, c.ez), Vector3(c.ch, c.rise - 0.006, c.ez),
			Vector3(c.ch, c.rise - 0.006, top), Vector3(-c.ch, c.rise - 0.006, top)], Vector3.UP)
	_flags(c, Rect2(-c.ch, c.ez, c.ch * 2.0, top - c.ez), c.rise, Vector2(0.8, 1.4), Vector2(0.7, 0.95))
	var w := CHANCEL_ARCH_A
	var front := c.cz + DIAPHRAGM_T * 0.5
	for k in 3:
		var y := c.rise * (k + 1) / 3.0
		var z0 := front - k * 0.35
		var z1 := top if k == 2 else front - (k + 1) * 0.35
		var tone := 0.92 + 0.08 * c.rng.randf()
		b.colour = Color(0.86 * tone, 0.82 * tone, 0.76 * tone)
		b.face([Vector3(-w, y, z1), Vector3(w, y, z1), Vector3(w, y, z0), Vector3(-w, y, z0)], Vector3.UP)
		b.face([Vector3(-w, y - c.rise / 3.0, z0), Vector3(w, y - c.rise / 3.0, z0), Vector3(w, y, z0),
				Vector3(-w, y, z0)], Vector3.BACK)
		# The nosing: a rounded edge, worn.
		var la := PackedVector3Array()
		var lb := PackedVector3Array()
		var ns := PackedVector3Array()
		for e: Array in [[0.0, -0.025], [0.3, -0.012], [0.7, 0.0]]:
			la.append(Vector3(-w, y + float(e[1]), z0 + 0.02 - 0.02 * float(e[0])))
			lb.append(Vector3(w, y + float(e[1]), z0 + 0.02 - 0.02 * float(e[0])))
			ns.append(Vector3(0.0, float(e[0]), 1.0 - float(e[0])).normalized())
		b.strip(la, lb, ns)


## Flagstones over a rectangle (x across, y along z) at height y: courses `rows` deep (min, max), flags `cols` long.
static func _flags(c: Church, r: Rect2, y: float, cols: Vector2, rows: Vector2) -> void:
	var b := c.flags
	var z := r.position.y
	while z < r.end.y - 0.05:
		var depth := minf(c.rng.randf_range(rows.x, rows.y), r.end.y - z)
		if r.end.y - (z + depth) < rows.x * 0.6:
			depth = r.end.y - z
		var x := r.position.x - c.rng.randf() * cols.x
		while x < r.end.x - 0.02:
			var length := c.rng.randf_range(cols.x, cols.y)
			var x0 := maxf(x, r.position.x)
			var x1 := minf(x + length, r.end.x)
			if x1 - x0 > 0.08:
				var pieces: Array[Rect2] = [Rect2(x0, z, x1 - x0, depth)]
				if y < 0.01:
					for l: Rect2 in c.ledgers:
						var keep: Array[Rect2] = []
						for f: Rect2 in pieces:
							keep.append_array(_minus(f, l.grow(0.012)))
						pieces = keep
				for f: Rect2 in pieces:
					if f.size.x > 0.1 and f.size.y > 0.1:
						_flag(c, f.position.x + 0.006, f.end.x - 0.006, f.position.y + 0.006, f.end.y - 0.006, y)
			x += length
		z += depth


## A rectangle less another: the pieces of `f` outside `l` (up to four).
static func _minus(f: Rect2, l: Rect2) -> Array[Rect2]:
	if not f.intersects(l):
		return [f]
	var out: Array[Rect2] = []
	if l.position.x > f.position.x:
		out.append(Rect2(f.position.x, f.position.y, l.position.x - f.position.x, f.size.y))
	if l.end.x < f.end.x:
		out.append(Rect2(l.end.x, f.position.y, f.end.x - l.end.x, f.size.y))
	var x0 := maxf(f.position.x, l.position.x)
	var x1 := minf(f.end.x, l.end.x)
	if l.position.y > f.position.y:
		out.append(Rect2(x0, f.position.y, x1 - x0, l.position.y - f.position.y))
	if l.end.y < f.end.y:
		out.append(Rect2(x0, l.end.y, x1 - x0, f.end.y - l.end.y))
	return out


## One flag: a top a little tilted, its own shade (a few darker, a few warmer, the aisles' worn paler), its edges
## down to the mortar.
static func _flag(c: Church, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var b := c.flags
	var tone := c.rng.randf_range(0.82, 1.08)
	var warm := c.rng.randf_range(-0.04, 0.05)
	var odd := c.rng.randf()
	var col := Color(0.92 * tone * (1.0 + warm), 0.88 * tone, 0.82 * tone * (1.0 - warm))
	if odd > 0.93:
		col = col * Color(0.78, 0.8, 0.82)
	elif odd < 0.05:
		col = col * Color(1.04, 0.96, 0.86)
	var mid_x := (x0 + x1) * 0.5
	# Worn smoother and paler where feet go: the aisles beside the pews, the way to the chancel.
	if absf(mid_x) > 2.75 and absf(mid_x) < 3.4 or absf(mid_x) > 4.4:
		col = col.lightened(0.06)
	b.colour = col
	var h: Array[float] = [y + c.rng.randf_range(-0.003, 0.004), y + c.rng.randf_range(-0.003, 0.004),
			y + c.rng.randf_range(-0.003, 0.004), y + c.rng.randf_range(-0.003, 0.004)]
	var corners: Array[Vector3] = [Vector3(x0, h[0], z0), Vector3(x1, h[1], z0), Vector3(x1, h[2], z1), Vector3(x0, h[3], z1)]
	var nrm := (corners[2] - corners[0]).cross(corners[1] - corners[3]).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	b.face(corners, nrm)


# --- Piers -------------------------------------------------------------------------------------------------------------

## A clustered pier on the floor at `at`: an octagonal plinth, moulded bases, a round core with four polished dark
## shafts (ringed halfway), a foliage capital and a moulded abacus.
static func _pier(c: Church, at: Vector3) -> void:
	var b := c.carve
	var r := float(c.p["column_radius"])
	var top := c.col_h
	var cap0 := top - 0.62
	b.colour = Color(0.9, 0.88, 0.84)
	Shapes.lathe(b, [Vector2(0.8, 0.0), Vector2(0.8, 0.28), Vector2(0.74, 0.32)], at, 8, Basis(Vector3.UP, PI / 8.0))
	b.face(_ring(at + Vector3(0, 0.32, 0), 0.74, 8, PI / 8.0), Vector3.UP)
	Shapes.lathe(b, [Vector2(r + 0.2, 0.32), Vector2(r + 0.2, 0.38), Vector2(r + 0.12, 0.42), Vector2(r + 0.08, 0.45),
			Vector2(r + 0.11, 0.5), Vector2(r + 0.04, 0.55), Vector2(r, 0.58), Vector2(r, cap0)], at, 16)
	# The capital: a bell in foliage over a necking, the abacus over it.
	b.colour = Color(0.94, 0.92, 0.88)
	Shapes.lathe(b, [Vector2(r, cap0), Vector2(r + 0.18, cap0 + 0.035), Vector2(r + 0.14, cap0 + 0.07)], at, 16)
	_foliage(b, at + Vector3(0, cap0 + 0.07, 0), [Vector2(r + 0.12, 0.0), Vector2(r + 0.13, 0.12),
			Vector2(r + 0.16, 0.26), Vector2(r + 0.22, 0.36), Vector2(r + 0.28, 0.41)], 8, 0.22, 0.0)
	b.colour = Color(0.9, 0.88, 0.84)
	Shapes.lathe(b, [Vector2(r + 0.26, top - 0.14), Vector2(r + 0.32, top - 0.11), Vector2(r + 0.32, top - 0.05),
			Vector2(r + 0.27, top), Vector2(0.0, top)], at, 16)
	# The shafts: polished, dark, on their own bases, a ring halfway.
	for k in 4:
		var d := Vector3(cos(k * PI * 0.5), 0.0, sin(k * PI * 0.5))
		var foot := at + d * (r + 0.02)
		b.colour = Color(0.88, 0.86, 0.82)
		Shapes.lathe(b, [Vector2(SHAFT_R + 0.06, 0.32), Vector2(SHAFT_R + 0.06, 0.4), Vector2(SHAFT_R + 0.02, 0.45),
				Vector2(SHAFT_R + 0.035, 0.5), Vector2(SHAFT_R, 0.55)], foot, 10)
		Shapes.lathe(b, [Vector2(SHAFT_R, cap0 * 0.5 + 0.2), Vector2(SHAFT_R + 0.035, cap0 * 0.5 + 0.23),
				Vector2(SHAFT_R + 0.035, cap0 * 0.5 + 0.29), Vector2(SHAFT_R, cap0 * 0.5 + 0.32)], foot, 10)
		Shapes.lathe(c.marble, [Vector2(SHAFT_R, 0.55), Vector2(SHAFT_R, cap0 * 0.5 + 0.2)], foot, 10)
		Shapes.lathe(c.marble, [Vector2(SHAFT_R, cap0 * 0.5 + 0.32), Vector2(SHAFT_R, cap0 + 0.01)], foot, 10)


## A ring of points (a polygon's corners) round centre, flat.
static func _ring(centre: Vector3, radius: float, sides: int, start := 0.0) -> Array:
	var out: Array = []
	for k in sides:
		var t := start + TAU * k / sides
		out.append(centre + Vector3(sin(t) * radius, 0.0, cos(t) * radius))
	return out


## A turned shape whose rings swell into leaves (a foliage capital, a boss): rings [Vector2(radius, height)] up from
## `at`; `lobes` clumps round it, each three-lobed, swelling by `amount` towards the top and curling out. down: the
## shape hangs (a boss under a vault).
static func _foliage(b: RoomMesh, at: Vector3, rings: Array, lobes: int, amount: float, phase: float,
		down := false) -> void:
	const SIDES := 40
	var rows: Array = []
	for i in rings.size():
		var q: Vector2 = rings[i]
		var t := float(i) / (rings.size() - 1)
		var row := PackedVector3Array()
		for k in SIDES + 1:
			var ang := TAU * float(k % SIDES) / SIDES
			var clump := pow(maxf(cos(lobes * (ang + phase) * 0.5), 0.0), 2.0)
			var leaf := clump * (0.75 + 0.25 * cos(3.0 * lobes * (ang + phase)))
			var swell := amount * leaf * smoothstep(0.15, 1.0, t)
			var radius := q.x * (1.0 + swell) + 0.03 * leaf * sin(t * PI)
			var y := q.y + 0.04 * leaf * t * t
			row.append(at + Vector3(sin(ang) * radius, -y if down else y, cos(ang) * radius))
		rows.append(row)
	for i in rows.size() - 1:
		var a: PackedVector3Array = rows[i]
		var c: PackedVector3Array = rows[i + 1]
		var ns := PackedVector3Array()
		for k in SIDES + 1:
			var around: Vector3 = a[(k + 1) % SIDES] - a[(k + SIDES - 1) % SIDES]
			var up: Vector3 = c[k] - a[k]
			var nrm := around.cross(up).normalized()
			var outward := a[k] - at
			outward.y = 0.0
			if nrm.dot(outward) < 0.0:
				nrm = -nrm
			ns.append(nrm)
		b.strip(a, c, ns)


# --- The arcades and the walls over them -------------------------------------------------------------------------------

## The arcade along one side: its arches of two orders under hood moulds, the wall over them on both faces.
static func _arcade(c: Church, s: float) -> void:
	var b := c.carve
	var x := s * c.nh
	var inner: Array = [Vector2(-0.24, 0.32), Vector2(-0.24, 0.05), Vector2(-0.19, 0.0), Vector2(0.19, 0.0),
			Vector2(0.24, 0.05), Vector2(0.24, 0.32)]
	var outer: Array = [Vector2(-0.4, 0.46), Vector2(-0.36, 0.32), Vector2(-0.24, 0.32)]
	var hood: Array = [Vector2(-0.4, 0.74), Vector2(-0.49, 0.72), Vector2(-0.52, 0.66), Vector2(-0.5, 0.6),
			Vector2(-0.4, 0.58)]
	var holes: Array = []
	for i in c.lines.size() - 1:
		var z0: float = c.lines[i]
		var z1: float = c.lines[i + 1]
		var mid := (z0 + z1) * 0.5
		var a := (z1 - z0) * 0.5 - ARCADE_INSET
		var centre := Vector3(x, c.col_h, mid)
		b.colour = Color(0.93, 0.91, 0.87)
		_arch_sweep(b, centre, Vector3.BACK, Vector3.RIGHT, a, ARCADE_RISE, inner, Vector2(0.0, 0.2))
		_arch_sweep(b, centre, Vector3.BACK, Vector3.RIGHT, a, ARCADE_RISE, outer, Vector2(-0.3, 0.6))
		_arch_sweep(b, centre, Vector3.BACK, Vector3.RIGHT, a, ARCADE_RISE, _mirror(outer), Vector2(0.3, 0.6))
		_arch_sweep(b, centre, Vector3.BACK, Vector3.RIGHT, a, ARCADE_RISE, hood, Vector2(-0.4, 0.66))
		_arch_sweep(b, centre, Vector3.BACK, Vector3.RIGHT, a, ARCADE_RISE, _mirror(hood), Vector2(0.4, 0.66))
		holes.append({"c": mid, "a": a, "h": ARCADE_RISE, "off": 0.46, "spring": c.col_h, "sill": c.col_h})
	b.colour = Color.WHITE
	for side: float in [-1.0, 1.0]:
		var fx := x + side * WALL_T * 0.5
		var top := STRING_LOW if side == -s else STRING_LOW + 0.2
		_panel(c.stone, Vector3(fx, 0, 0), Vector3.BACK, Vector3(side, 0, 0), c.cz, c.rz, c.col_h, top, holes)


## Over the arcade on the nave's side: the triforium between two string courses, the clerestory with its two-light
## windows up to the vault, and a vaulting shaft at each pier.
static func _upper(c: Church, s: float) -> void:
	var b := c.carve
	var fx := s * c.face
	var into := Vector3(-s, 0, 0)
	var origin := Vector3(fx, 0, 0)
	# The string courses, the length of the nave.
	_string(b, Vector3(fx, STRING_LOW, c.cz), Vector3(fx, STRING_LOW, c.rz), into)
	_string(b, Vector3(fx, STRING_HIGH, c.cz), Vector3(fx, STRING_HIGH, c.rz), into)
	# The triforium: four small pointed openings a bay into the dark passage behind, colonnettes between them.
	var tri: Array = []
	for i in c.lines.size() - 1:
		var mid := (c.lines[i] + c.lines[i + 1]) * 0.5
		for k in 4:
			tri.append({"c": mid + (k - 1.5) * 0.74, "a": 0.27, "h": 0.42, "spring": 9.05, "sill": 8.2})
	_panel(c.stone, origin, Vector3.BACK, into, c.cz, c.rz, STRING_LOW, STRING_HIGH, tri)
	for hole: Dictionary in tri:
		_reveal(c.stone, origin, Vector3.BACK, into, hole, 0.5, 0.0, 6)
		# The passage's back wall: dark (no light reaches it).
		var hc := float(hole["c"])
		b.colour = Color(0.5, 0.48, 0.46)
		b.face([Vector3(fx + s * 0.5, 8.2, hc - 0.3), Vector3(fx + s * 0.5, 8.2, hc + 0.3),
				Vector3(fx + s * 0.5, 9.6, hc + 0.3), Vector3(fx + s * 0.5, 9.6, hc - 0.3)], into)
		b.colour = Color.WHITE
		# A colonnette either side, on the face.
		for e: float in [-1.0, 1.0]:
			var foot := Vector3(fx - s * 0.05, 8.2, hc + e * 0.37)
			Shapes.lathe(c.marble, [Vector2(0.045, 0.0), Vector2(0.045, 0.85)], foot, 8)
			b.colour = Color(0.94, 0.92, 0.88)
			Shapes.lathe(b, [Vector2(0.07, -0.02), Vector2(0.07, 0.03), Vector2(0.045, 0.06)], foot, 8)
			Shapes.lathe(b, [Vector2(0.045, 0.82), Vector2(0.08, 0.88), Vector2(0.08, 0.92), Vector2(0.0, 0.92)], foot, 8)
			b.colour = Color.WHITE
	# The clerestory: a two-light window a bay, its reveal splayed, bar tracery at the glass.
	var holes: Array = []
	for i in c.lines.size() - 1:
		var mid := (c.lines[i] + c.lines[i + 1]) * 0.5
		holes.append({"c": mid, "a": 0.95, "h": 1.55, "spring": 13.1, "sill": 10.2})
	var top := func(at: float) -> float: return _lunette_top(c, at)
	_panel(c.stone, origin, Vector3.BACK, into, c.cz, c.rz, STRING_HIGH, top, holes)
	for hole: Dictionary in holes:
		var outline := _reveal(c.stone, origin, Vector3.BACK, into, hole, 0.55, 0.12, 8, 0.25)
		_two_light(c, origin - into * 0.55, Vector3.BACK, into, hole, outline, 0.12, "clere_s" if s > 0.0 else "clere_n")
	# The vaulting shafts: from each pier's capital up the wall to the vault's springing, ringed at the string courses.
	for z: float in c.lines:
		var zz := clampf(z, c.cz + DIAPHRAGM_T * 0.5 + VSHAFT_R, c.rz - VSHAFT_R)
		_vshaft(c, Vector3(fx - s * VSHAFT_R * 0.9, c.col_h, zz), c.wall_h)


## The clerestory wall's top: under each bay's wall rib (the vault's lunette), the bays meeting at the vaulting shafts.
static func _lunette_top(c: Church, at: float) -> float:
	for i in c.lines.size() - 1:
		var z0: float = c.lines[i]
		var z1: float = c.lines[i + 1]
		if at >= z0 - 0.001 and at <= z1 + 0.001:
			var half := (z1 - z0) * 0.5
			var aa := c.face
			return c.wall_h + _fv(aa, c.crown - c.wall_h, (at - (z0 + z1) * 0.5) * aa / half) + 0.05
	return c.wall_h


## A vaulting shaft from `foot` up to `top`: dark, ringed at `rings` (heights: the string courses), a small foliage
## capital.
static func _vshaft(c: Church, foot: Vector3, top: float, rings: Array = [STRING_LOW, STRING_HIGH]) -> void:
	var b := c.carve
	var h := top - foot.y
	b.colour = Color(0.92, 0.9, 0.86)
	Shapes.lathe(b, [Vector2(VSHAFT_R + 0.05, 0.0), Vector2(VSHAFT_R + 0.05, 0.06), Vector2(VSHAFT_R, 0.12)], foot, 10)
	var y := 0.12
	for ring: float in rings:
		var ry := ring - foot.y
		Shapes.lathe(c.marble, [Vector2(VSHAFT_R, y), Vector2(VSHAFT_R, ry - 0.06)], foot, 10)
		Shapes.lathe(b, [Vector2(VSHAFT_R, ry - 0.06), Vector2(VSHAFT_R + 0.04, ry - 0.03),
				Vector2(VSHAFT_R + 0.04, ry + 0.03), Vector2(VSHAFT_R, ry + 0.06)], foot, 10)
		y = ry + 0.06
	Shapes.lathe(c.marble, [Vector2(VSHAFT_R, y), Vector2(VSHAFT_R, h - 0.42)], foot, 10)
	b.colour = Color(0.95, 0.93, 0.89)
	_foliage(b, foot + Vector3(0, h - 0.42, 0), [Vector2(VSHAFT_R + 0.01, 0.0), Vector2(VSHAFT_R + 0.03, 0.12),
			Vector2(VSHAFT_R + 0.08, 0.24), Vector2(VSHAFT_R + 0.14, 0.3)], 5, 0.3, 0.3)
	Shapes.lathe(b, [Vector2(VSHAFT_R + 0.16, h - 0.12), Vector2(VSHAFT_R + 0.2, h - 0.08),
			Vector2(VSHAFT_R + 0.2, h - 0.02), Vector2(0.0, h)], foot, 10)


## Bar tracery in a two-light window at the glass: a mullion, two pointed lights, a circle in the head; and the glass
## (the window's picture, `spec`).
static func _two_light(c: Church, origin: Vector3, u: Vector3, normal: Vector3, hole: Dictionary,
		outline: Array[Vector2], splay: float, spec: String) -> void:
	var b := c.carve
	var hc := float(hole["c"])
	var a := float(hole["a"]) - splay
	var spring := float(hole["spring"])
	var h := _arc(float(hole["a"]), float(hole["h"]), -splay, 1.0, 1.0)[0].y as float
	var sill: float = outline[0].y
	var bar := 0.055
	var depth := 0.09
	b.colour = Color(0.95, 0.93, 0.9)
	# The mullion.
	b.box(origin + u * hc + Vector3.UP * (sill + spring) * 0.5 + normal * 0.01, Vector3(0, spring - sill, 0).abs()
			+ (u * bar * 2.0).abs() + (normal * depth * 2.0).abs(), Basis(), [-normal])
	# The lights' heads.
	var la := (a - bar) * 0.5
	var lh := la * 1.5
	for e: float in [-1.0, 1.0]:
		var centre := origin + u * (hc + e * (la + bar)) + Vector3.UP * spring
		_arch_sweep(b, centre, u, normal, la, lh, [Vector2(depth, 0.11), Vector2(depth, 0.0), Vector2(-depth, 0.0)],
				Vector2(0.0, 0.05), 6)
	# The circle.
	var cy := spring + lh + 0.1 + (h - lh - 0.2) * 0.5
	var cr := (h - lh - 0.2) * 0.5 - 0.02
	var pts: Array = []
	var sides: Array = []
	var outs: Array = []
	for k in 25:
		var t := TAU * k / 24.0
		var d := u * cos(t) + Vector3.UP * sin(t)
		pts.append(origin + u * hc + Vector3.UP * cy + d * cr)
		sides.append(normal)
		outs.append(d)
	_curve_sweep(b, pts, sides, outs, [Vector2(depth, 0.1), Vector2(depth, 0.0), Vector2(-depth, 0.0)],
			Vector2(0.0, 0.05))
	b.colour = Color.WHITE
	_glass(c, origin - normal * 0.02, u, normal, outline, spec, {"kind": "two", "c": hc, "a": a, "sill": sill,
			"spring": spring, "h": h, "bar": bar, "la": la, "lh": lh, "cy": cy, "cr": cr})
	# A south window: the Moon shines in through it (the clerestory's and the chancel's from higher, so a little
	# brighter and narrower).
	if spec.begins_with("aisle_s") or spec == "clere_s":
		var high := spec == "clere_s"
		c.moon_windows.append([origin + u * hc + Vector3.UP * (sill + (spring + h - sill) * 0.45) + normal * 0.2,
				1.3 if high else 1.0, 10.0 if high else 14.0])


# --- Vaults -----------------------------------------------------------------------------------------------------------

## The nave's vault: a quadripartite bay between each pair of piers, its transverse, diagonal and wall ribs, a boss
## at each crossing.
static func _nave_vault(c: Church) -> void:
	for i in c.lines.size() - 1:
		_vault_bay(c, 0.0, c.face, c.lines[i], c.lines[i + 1], c.wall_h, c.crown - c.wall_h, true, i == 0)


## One bay of a quadripartite vault over x from cx - a to cx + a and z from z0 to z1, springing at `spring`, its
## crown `h` over it: four cells of webs, ribs over their groins and edges, a foliage boss. first: the bay's first
## transverse rib too (the others share theirs with the bay before).
static func _vault_bay(c: Church, cx: float, a: float, z0: float, z1: float, spring: float, h: float,
		wall_ribs := true, first := true, rib := 1.0) -> void:
	var zc := (z0 + z1) * 0.5
	var bz := (z1 - z0) * 0.5
	var nw := 7
	var na := 10
	var below := Vector3(cx, spring - h, zc)
	for cell in 4:
		var rows: Array = []
		for i in nw + 1:
			var w := lerpf(0.04, 1.0, float(i) / nw)
			var row: Array = []
			for k in na + 1:
				var t := lerpf(-1.0, 1.0, float(k) / na)
				row.append(_cell_point(cx, a, zc, bz, spring, h, cell, w, t))
			rows.append(row)
		for i in nw:
			var la := PackedVector3Array()
			var lb := PackedVector3Array()
			var ns := PackedVector3Array()
			for k in na + 1:
				var p0: Vector3 = rows[i][k]
				la.append(p0)
				lb.append(rows[i + 1][k])
				var dw: Vector3 = rows[i + 1][k] - p0
				var dt: Vector3 = rows[i][mini(k + 1, na)] - rows[i][maxi(k - 1, 0)]
				var nrm := dw.cross(dt).normalized()
				if nrm.dot(below - p0) < 0.0:
					nrm = -nrm
				ns.append(nrm)
			c.webs.strip(la, lb, ns)
	# The ribs: the diagonals (over the groins), the transverse ribs, the wall ribs; the boss.
	var b := c.carve
	b.colour = Color(0.9, 0.88, 0.84)
	var prof: Array = [Vector2(-0.09, 0.04), Vector2(-0.09, -0.07), Vector2(-0.05, -0.15), Vector2(0.0, -0.19),
			Vector2(0.05, -0.15), Vector2(0.09, -0.07), Vector2(0.09, 0.04)]
	var scaled: Array = []
	for q: Vector2 in prof:
		scaled.append(q * rib)
	for d: float in [-1.0, 1.0]:
		for half: float in [-1.0, 1.0]:
			var pts: Array = []
			for k in 13:
				var t := half * float(k) / 12.0
				pts.append(Vector3(cx + a * t, spring + _fv(a, h, a * t), zc + d * bz * t))
			var f := _frames(pts, Vector3.UP)
			_curve_sweep(b, pts, f[0], f[1], scaled, Vector2(0.0, -0.05))
	var zs: Array = [z1]
	if first:
		zs.append(z0)
	for z: float in zs:
		for half: float in [-1.0, 1.0]:
			var pts: Array = []
			for k in 13:
				var t := half * float(k) / 12.0
				pts.append(Vector3(cx + a * t, spring + _fv(a, h, a * t), z))
			var f := _frames(pts, Vector3.UP)
			_curve_sweep(b, pts, f[0], f[1], scaled, Vector2(0.0, -0.05))
	if wall_ribs:
		var small: Array = [Vector2(-0.06, 0.0), Vector2(-0.06, -0.05), Vector2(0.0, -0.09), Vector2(0.06, -0.05),
				Vector2(0.06, 0.0)]
		for e: float in [-1.0, 1.0]:
			for half: float in [-1.0, 1.0]:
				var pts: Array = []
				for k in 11:
					var t := half * float(k) / 10.0
					pts.append(Vector3(cx + e * (a - 0.06), spring + _fv(a, h, a * t), zc + bz * t))
				var f := _frames(pts, Vector3.UP)
				_curve_sweep(b, pts, f[0], f[1], small, Vector2(0.0, -0.03))
	b.colour = Color(0.97, 0.95, 0.9)
	_foliage(b, Vector3(cx, spring + h - 0.12, zc), [Vector2(0.2 * rib, 0.0), Vector2(0.22 * rib, 0.06),
			Vector2(0.2 * rib, 0.14), Vector2(0.12 * rib, 0.22), Vector2(0.0, 0.25)], 6, 0.35, 0.2, true)
	b.colour = Color.WHITE


## A point of a vault cell: cell 0 and 1 by the transverse ribs (z1, z0), 2 and 3 by the walls (+x, -x); w from the
## crossing (0) to the cell's edge (1), t across the cell from groin to groin (-1 to 1).
static func _cell_point(cx: float, a: float, zc: float, bz: float, spring: float, h: float, cell: int, w: float,
		t: float) -> Vector3:
	var y := spring + _fv(a, h, a * absf(t) * w)
	match cell:
		0:
			return Vector3(cx + a * t * w, y, zc + bz * w)
		1:
			return Vector3(cx + a * t * w, y, zc - bz * w)
		2:
			return Vector3(cx + a * w, y, zc + bz * t * w)
	return Vector3(cx - a * w, y, zc + bz * t * w)


# --- The aisles -------------------------------------------------------------------------------------------------------

## One aisle: its outer wall with a two-light window a bay, wall shafts, its vault; its east wall's lancet.
static func _aisle(c: Church, s: float) -> void:
	var b := c.carve
	var wx := s * c.ow
	var into := Vector3(-s, 0, 0)
	var cx := s * (c.ow + c.nh + WALL_T * 0.5) * 0.5
	var aa := (c.ow - c.nh - WALL_T * 0.5) * 0.5
	var holes: Array = []
	for i in c.lines.size() - 1:
		var mid := (c.lines[i] + c.lines[i + 1]) * 0.5
		holes.append({"c": mid, "a": 0.8, "h": 1.3, "spring": 4.3, "sill": 2.0})
	var top := func(at: float) -> float: return _aisle_top(c, at)
	_panel(c.stone, Vector3(wx, 0, 0), Vector3.BACK, into, c.cz, c.rz, 0.0, top, holes)
	# A bench along the wall's foot (the old stone seat for the weak).
	b.colour = Color(0.86, 0.84, 0.8)
	b.box(Vector3(wx - s * 0.16, 0.2, (c.cz + c.rz) * 0.5), Vector3(0.32, 0.4, c.rz - c.cz), Basis(), [Vector3.DOWN])
	b.colour = Color.WHITE
	for i in holes.size():
		var hole: Dictionary = holes[i]
		var outline := _reveal(c.stone, Vector3(wx, 0, 0), Vector3.BACK, into, hole, 0.5, 0.1, 8, 0.3)
		# Each bay's glass its own design (three, in turn; the two sides set off from each other).
		_two_light(c, Vector3(wx, 0, 0) - into * 0.5, Vector3.BACK, into, hole, outline, 0.1,
				("aisle_s%d" if s > 0.0 else "aisle_n%d") % ((i + (1 if s > 0.0 else 0)) % 3))
	for z: float in c.lines:
		var zz := clampf(z, c.cz + VSHAFT_R, c.rz - VSHAFT_R)
		_vshaft(c, Vector3(wx - s * VSHAFT_R * 0.9, 0.0, zz), c.col_h, [2.4])
	for i in c.lines.size() - 1:
		_vault_bay(c, cx, aa, c.lines[i], c.lines[i + 1], c.col_h, AISLE_RISE, false, i == 0, 0.75)
	# The east wall, beside the chancel: a tall lancet of warm glass.
	var ex := s * (c.nh + WALL_T * 0.5)
	var origin := Vector3(0, 0, c.cz)
	var east_top := func(at: float) -> float: return c.col_h + _fv(aa, AISLE_RISE, at - cx) + 0.05
	var lancet := {"c": cx, "a": 0.42, "h": 0.85, "spring": 4.6, "sill": 2.5}
	_panel(c.stone, origin, Vector3.RIGHT, Vector3.BACK, minf(ex, wx), maxf(ex, wx), 0.0, east_top, [lancet])
	var outline := _reveal(c.stone, origin, Vector3.RIGHT, Vector3.BACK, lancet, 0.45, 0.08, 8, 0.25)
	_glass(c, origin + Vector3.FORWARD * 0.43, Vector3.RIGHT, Vector3.BACK, outline, "lancet",
			{"kind": "one", "c": cx, "a": 0.34, "sill": outline[0].y, "spring": 4.6,
			"h": _arc(0.42, 0.85, -0.08, 1.0, 1.0)[0].y as float})


static func _aisle_top(c: Church, at: float) -> float:
	for i in c.lines.size() - 1:
		var z0: float = c.lines[i]
		var z1: float = c.lines[i + 1]
		if at >= z0 - 0.001 and at <= z1 + 0.001:
			var half := (z1 - z0) * 0.5
			var aa := (c.ow - c.nh - WALL_T * 0.5) * 0.5
			return c.col_h + _fv(aa, AISLE_RISE, (at - (z0 + z1) * 0.5) * aa / half) + 0.05
	return c.col_h


# --- The chancel ------------------------------------------------------------------------------------------------------

## The chancel arch (two orders on shafts, a hood), the wall it is cut through up to the vault, the chancel's walls,
## a window either side, its vault, the east wall with the rose window.
static func _chancel(c: Church) -> void:
	var b := c.carve
	var a := CHANCEL_ARCH_A
	var front := c.cz + DIAPHRAGM_T * 0.5
	var back := c.cz - DIAPHRAGM_T * 0.5
	var centre := Vector3(0, c.col_h, c.cz)
	var inner: Array = [Vector2(-0.3, 0.22), Vector2(-0.3, 0.05), Vector2(-0.24, 0.0), Vector2(0.24, 0.0),
			Vector2(0.3, 0.05), Vector2(0.3, 0.22)]
	var outer: Array = [Vector2(-0.45, 0.45), Vector2(-0.45, 0.28), Vector2(-0.39, 0.22), Vector2(-0.3, 0.22)]
	var hood: Array = [Vector2(-0.45, 0.72), Vector2(-0.55, 0.7), Vector2(-0.58, 0.63), Vector2(-0.55, 0.56),
			Vector2(-0.45, 0.54)]
	b.colour = Color(0.94, 0.92, 0.88)
	_arch_sweep(b, centre, Vector3.RIGHT, Vector3.BACK, a, CHANCEL_ARCH_H, inner, Vector2(0.0, 0.15), 14)
	_arch_sweep(b, centre, Vector3.RIGHT, Vector3.BACK, a, CHANCEL_ARCH_H, outer, Vector2(-0.35, 0.4), 14)
	_arch_sweep(b, centre, Vector3.RIGHT, Vector3.BACK, a, CHANCEL_ARCH_H, _mirror(outer), Vector2(0.35, 0.4), 14)
	_arch_sweep(b, centre, Vector3.RIGHT, Vector3.BACK, a, CHANCEL_ARCH_H, _mirror(hood), Vector2(0.45, 0.63), 14,
			Vector3.UP, 0.12)
	# The jambs: both orders run down to the floor (continuous mouldings), a dark shaft in the angle between them, a
	# band of foliage where the arch springs.
	_jamb_sweep(b, centre, Vector3.RIGHT, Vector3.BACK, a, c.col_h, inner, Vector2(0.0, 0.15))
	_jamb_sweep(b, centre, Vector3.RIGHT, Vector3.BACK, a, c.col_h, outer, Vector2(-0.35, 0.4))
	_jamb_sweep(b, centre, Vector3.RIGHT, Vector3.BACK, a, c.col_h, _mirror(outer), Vector2(0.35, 0.4))
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			var foot := Vector3(s * (a + 0.24), 0.0, c.cz + e * 0.36)
			b.colour = Color(0.9, 0.88, 0.84)
			Shapes.lathe(b, [Vector2(0.11, 0.0), Vector2(0.11, 0.32), Vector2(0.08, 0.38), Vector2(0.065, 0.44)], foot, 8)
			Shapes.lathe(c.marble, [Vector2(0.065, 0.44), Vector2(0.065, c.col_h - 0.3)], foot, 8)
			b.colour = Color(0.95, 0.93, 0.89)
			_foliage(b, foot + Vector3(0, c.col_h - 0.3, 0), [Vector2(0.07, 0.0), Vector2(0.08, 0.1), Vector2(0.12, 0.2),
					Vector2(0.15, 0.26)], 5, 0.3, 0.4)
	b.colour = Color.WHITE
	# The wall the arch is cut through: towards the nave up to the vault, towards the chancel up to its vault.
	var hole := {"c": 0.0, "a": a, "h": CHANCEL_ARCH_H, "off": 0.45, "spring": c.col_h, "sill": 0.0}
	var nave_top := func(at: float) -> float: return c.wall_h + _fv(c.face, c.crown - c.wall_h, at) + 0.05
	_panel(c.stone, Vector3(0, 0, front), Vector3.RIGHT, Vector3.BACK, -c.face, c.face, 0.0, nave_top, [hole], 14)
	var ch_h := c.crown - 0.5 - CHANCEL_SPRING
	var ch_top := func(at: float) -> float: return CHANCEL_SPRING + _fv(c.ch, ch_h, at) + 0.05
	_panel(c.stone, Vector3(0, 0, back), Vector3.RIGHT, Vector3.FORWARD, -c.ch, c.ch, 0.0, ch_top, [hole], 14)
	# The chancel's side walls, a two-light window in each.
	for s: float in [-1.0, 1.0]:
		var wx := s * c.ch
		var into := Vector3(-s, 0, 0)
		var win := {"c": (back + c.ez) * 0.5, "a": 0.8, "h": 1.35, "spring": 9.6, "sill": 5.4}
		var bz := (back - c.ez) * 0.5
		var side_top := func(at: float) -> float:
			return CHANCEL_SPRING + _fv(c.ch, ch_h, (at - (back + c.ez) * 0.5) * c.ch / bz) + 0.05
		_panel(c.stone, Vector3(wx, 0, 0), Vector3.BACK, into, c.ez, back, 0.0, side_top, [win])
		var outline := _reveal(c.stone, Vector3(wx, 0, 0), Vector3.BACK, into, win, 0.55, 0.1, 8, 0.3)
		_two_light(c, Vector3(wx, 0, 0) - into * 0.55, Vector3.BACK, into, win, outline, 0.1,
				"clere_s" if s > 0.0 else "clere_n")
		_vshaft(c, Vector3(wx - s * VSHAFT_R * 0.9, c.rise, c.ez + VSHAFT_R), CHANCEL_SPRING, [c.col_h, STRING_LOW])
		_vshaft(c, Vector3(wx - s * VSHAFT_R * 0.9, c.rise, back - VSHAFT_R), CHANCEL_SPRING, [c.col_h, STRING_LOW])
	_vault_bay(c, 0.0, c.ch, c.ez, back, CHANCEL_SPRING, ch_h, true, true)
	_east_wall(c, ch_top)


## The east wall over the screen: the rose window in it (its reveal, a moulded ring), the wall round it to the vault.
static func _east_wall(c: Church, top: Callable) -> void:
	var b := c.carve
	var rr := float(c.p["rose_radius"])
	var rc := _rose_centre(c)
	var z := c.ez
	var sq := rr + 0.35
	var origin := Vector3(0, 0, z)
	# Left, right, under and over the rose's square.
	_panel(c.stone, origin, Vector3.RIGHT, Vector3.BACK, -c.ch, -sq, c.rise, top)
	_panel(c.stone, origin, Vector3.RIGHT, Vector3.BACK, sq, c.ch, c.rise, top)
	_panel(c.stone, origin, Vector3.RIGHT, Vector3.BACK, -sq, sq, c.rise, rc.y - sq)
	_panel(c.stone, Vector3(0, 0, z), Vector3.RIGHT, Vector3.BACK, -sq, sq, rc.y + sq, top)
	# Round the hole, out to the square.
	var la := PackedVector3Array()
	var lb := PackedVector3Array()
	var ns := PackedVector3Array()
	for k in 49:
		var t := TAU * k / 48.0
		var d := Vector2(cos(t), sin(t))
		la.append(Vector3(rc.x + d.x * rr, rc.y + d.y * rr, z))
		var m := maxf(absf(d.x), absf(d.y))
		lb.append(Vector3(rc.x + d.x * sq / m, rc.y + d.y * sq / m, z))
		ns.append(Vector3.BACK)
	b.strip(la, lb, ns)
	# The reveal and a moulded ring round it.
	var depth := 0.45
	var pts: Array = []
	var sides: Array = []
	var outs: Array = []
	for k in 49:
		var t := TAU * k / 48.0
		var d := Vector3(cos(t), sin(t), 0)
		pts.append(Vector3(rc.x, rc.y, z) + d * rr)
		sides.append(Vector3.BACK)
		outs.append(d)
	b.colour = Color(0.94, 0.92, 0.88)
	_curve_sweep(b, pts, sides, outs, [Vector2(0.0, 0.0), Vector2(-depth, -0.12)], Vector2(-0.2, 0.3))
	_curve_sweep(b, pts, sides, outs, [Vector2(0.0, 0.3), Vector2(0.06, 0.26), Vector2(0.1, 0.16), Vector2(0.06, 0.06),
			Vector2(0.0, 0.0)], Vector2(-0.05, 0.15))
	b.colour = Color.WHITE
	_rose(c, Vector3(rc.x, rc.y, z - depth + 0.02), rr - 0.12)


static func _rose_centre(c: Church) -> Vector2:
	var rr := float(c.p["rose_radius"])
	return Vector2(0.0, c.screen_c.y + c.screen_s.y * 0.5 + 1.3 + rr)


## The rose's tracery at the glass: a hub, twelve spokes, the lights' pointed heads, a ring, twelve circles round it;
## and the glass behind (the rose's picture).
static func _rose(c: Church, at: Vector3, r: float) -> void:
	var b := c.carve
	b.colour = Color(0.96, 0.94, 0.9)
	var depth := 0.09
	var prof: Array = [Vector2(depth, 0.09), Vector2(depth, 0.0), Vector2(-depth, 0.0)]
	var ring := func(centre: Vector3, radius: float, out := true) -> void:
		var pts: Array = []
		var sides: Array = []
		var outs: Array = []
		for k in 41:
			var t := TAU * k / 40.0
			var d := Vector3(cos(t), sin(t), 0)
			pts.append(centre + d * radius)
			sides.append(Vector3.BACK)
			outs.append(d if out else -d)
		_curve_sweep(b, pts, sides, outs, prof, Vector2(0.0, 0.05))
	ring.call(at, r * 0.2, false)
	ring.call(at, r * 0.7, true)
	for k in 12:
		var t := TAU * (k + 0.5) / 12.0
		var d := Vector3(cos(t), sin(t), 0)
		var side := Vector3(-d.y, d.x, 0)
		# A spoke (a colonnette) from the hub to the ring.
		b.box(at + d * r * 0.45 + Vector3.BACK * 0.01, Vector3(0.09, r * 0.5, 0.16), Basis(side, d, Vector3.BACK),
				[Vector3.FORWARD])
		# The circles of the outer band.
		var t2 := TAU * k / 12.0
		ring.call(at + Vector3(cos(t2), sin(t2), 0) * r * 0.86, r * 0.105, false)
	# The lights' heads: a pointed arch between each pair of spokes, under the ring.
	for k in 12:
		var t := TAU * k / 12.0
		var d := Vector3(cos(t), sin(t), 0)
		var side := Vector3(-d.y, d.x, 0)
		var half := r * 0.56 * sin(PI / 12.0) - 0.05
		_arch_sweep(b, at + d * (r * 0.56), side, Vector3.BACK, half, half * 1.25, prof, Vector2(0.0, 0.05), 4, d)
	b.colour = Color.WHITE
	# The glass: a disc behind the tracery (the picture's rim at ROSE_GLASS of the tracery's radius).
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for k in 48:
		var t := TAU * k / 48.0
		pts.append(at + Vector3(cos(t), sin(t), 0) * r * ROSE_GLASS + Vector3.FORWARD * 0.03)
		uvs.append(Vector2(0.5 + 0.5 * cos(t), 0.5 - 0.5 * sin(t)))
	c.rose_glass.append({"pts": pts, "uvs": uvs, "normal": Vector3.BACK})


# --- The west end -----------------------------------------------------------------------------------------------------

## The west wall behind the seats: the nave's part with a pointed doorway (oak doors) and a three-light window over
## it, the aisles' parts with a lancet each.
static func _west(c: Church) -> void:
	var b := c.carve
	var z := c.rz
	var origin := Vector3(0, 0, z)
	var n := Vector3.FORWARD
	var door := {"c": 0.0, "a": 1.0, "h": 1.25, "spring": 2.7, "sill": 0.0}
	var win := {"c": 0.0, "a": 1.6, "h": 2.4, "spring": 11.0, "sill": 6.2}
	_panel(c.stone, origin, Vector3.RIGHT, n, -c.face, c.face, 0.0, 5.8, [door])
	var top := func(at: float) -> float: return c.wall_h + _fv(c.face, c.crown - c.wall_h, at) + 0.05
	_panel(c.stone, origin, Vector3.RIGHT, n, -c.face, c.face, 5.8, top, [win])
	_string(b, Vector3(-c.face, 5.8, z), Vector3(c.face, 5.8, z), n)
	# The doorway's reveal with the doors in it.
	_reveal(c.stone, origin, Vector3.RIGHT, n, door, 0.5, 0.0, 8, 0.0, false)
	_doors(c, Vector3(0.0, 0.0, z + 0.48), 1.0, 2.7, 1.25)
	var outline := _reveal(c.stone, origin, Vector3.RIGHT, n, win, 0.55, 0.12, 10, 0.3)
	_three_light(c, origin + Vector3.BACK * 0.55, Vector3.RIGHT, n, win, outline, 0.12)
	for s: float in [-1.0, 1.0]:
		var cx := s * (c.ow + c.nh + WALL_T * 0.5) * 0.5
		var aa := (c.ow - c.nh - WALL_T * 0.5) * 0.5
		var aisle_top := func(at: float) -> float: return c.col_h + _fv(aa, AISLE_RISE, at - cx) + 0.05
		var lancet := {"c": cx, "a": 0.4, "h": 0.8, "spring": 4.4, "sill": 2.4}
		var x0 := s * (c.nh + WALL_T * 0.5)
		_panel(c.stone, origin, Vector3.RIGHT, n, minf(x0, s * c.ow), maxf(x0, s * c.ow), 0.0, aisle_top, [lancet])
		var lo := _reveal(c.stone, origin, Vector3.RIGHT, n, lancet, 0.45, 0.08, 8, 0.25)
		_glass(c, origin + Vector3.BACK * 0.43, Vector3.RIGHT, n, lo, "lancet_w",
				{"kind": "one", "c": cx, "a": 0.32, "sill": lo[0].y, "spring": 4.4,
				"h": _arc(0.4, 0.8, -0.08, 1.0, 1.0)[0].y as float})
		# The arcade wall's end, between the nave and the aisle.
		_panel(c.stone, origin, Vector3.RIGHT, n, minf(s * c.face, x0), maxf(s * c.face, x0), 0.0, c.wall_h + 1.0)


## A three-light window's tracery: two mullions, three pointed lights, three circles in the head.
static func _three_light(c: Church, origin: Vector3, u: Vector3, normal: Vector3, hole: Dictionary,
		outline: Array[Vector2], splay: float) -> void:
	var b := c.carve
	var hc := float(hole["c"])
	var a := float(hole["a"]) - splay
	var spring := float(hole["spring"])
	var h := _arc(float(hole["a"]), float(hole["h"]), -splay, 1.0, 1.0)[0].y as float
	var sill: float = outline[0].y
	var bar := 0.055
	var depth := 0.09
	b.colour = Color(0.95, 0.93, 0.9)
	var la := (a * 2.0 - bar * 4.0) / 6.0
	var lh := la * 1.6
	for e: float in [-1.0, 1.0]:
		var mx := hc + e * (la + bar)
		b.box(origin + u * mx + Vector3.UP * (sill + spring) * 0.5 + normal * 0.01, Vector3(0, spring - sill, 0)
				+ (u * bar * 2.0).abs() + (normal * depth * 2.0).abs(), Basis(), [-normal])
	var prof: Array = [Vector2(depth, 0.11), Vector2(depth, 0.0), Vector2(-depth, 0.0)]
	for e: float in [-1.0, 0.0, 1.0]:
		_arch_sweep(b, origin + u * (hc + e * (la * 2.0 + bar * 2.0)) + Vector3.UP * spring, u, normal, la, lh, prof,
				Vector2(0.0, 0.05), 6)
	var circles: Array = [[hc, spring + lh + 0.45, 0.32], [hc - 0.55, spring + lh + 0.22, 0.2],
			[hc + 0.55, spring + lh + 0.22, 0.2]]
	circles[0][1] = spring + lh + 0.15 + (h - lh - 0.25) * 0.5
	circles[0][2] = (h - lh - 0.25) * 0.5
	for ci: Array in circles:
		var pts: Array = []
		var sides: Array = []
		var outs: Array = []
		for k in 25:
			var t := TAU * k / 24.0
			var d := u * cos(t) + Vector3.UP * sin(t)
			pts.append(origin + u * float(ci[0]) + Vector3.UP * float(ci[1]) + d * float(ci[2]))
			sides.append(normal)
			outs.append(d)
		_curve_sweep(b, pts, sides, outs, prof, Vector2(0.0, 0.05))
	b.colour = Color.WHITE
	_glass(c, origin - normal * 0.02, u, normal, outline, "west", {"kind": "three", "c": hc, "a": a, "sill": sill,
			"spring": spring, "h": h, "bar": bar, "la": la, "lh": lh, "circles": circles})


# --- Candles ----------------------------------------------------------------------------------------------------------

## Pricket stands of iron in the chancel either side of the screen, `per_side` a side (2: a few, 4: many), each a
## tripod, a stem, a drip pan and a thick candle; beside the picture, never before it. Their group: house (the
## ritual takes them low for the film).
static func _stands(c: Church, per_side: int) -> void:
	if per_side <= 0:
		return
	var places: Array = [[3.85, -9.35, 1.5], [3.95, -8.1, 1.25], [4.1, -9.95, 1.15], [3.8, -7.3, 1.4]]
	var lamp_at := [Vector3.ZERO, Vector3.ZERO]
	for s: float in [-1.0, 1.0]:
		for k in mini(per_side, places.size()):
			var e: Array = places[k]
			var foot := Vector3(s * float(e[0]), c.rise, float(e[1]))
			var h := float(e[2]) + 0.04 * c.rng.randf()
			_stand(c, foot, h)
			var wax_h := c.rng.randf_range(0.32, 0.5)
			var f := _candle(c, foot + Vector3(0, h + 0.03, 0), wax_h, 0.042, "house", 1.0)
			c.n._bake_omni("Stand%d" % c.candles.size(), f + Vector3(0, 0.05, 0), STAND_REACH, STAND_LIGHT, FLAME)
			lamp_at[0 if s < 0.0 else 1] += f / float(per_side)
	for i in 2:
		c.n._light.add_lamp(lamp_at[i], FLAME * STAND_LAMP * per_side, 0.0)


## One pricket stand: three splayed feet, a turned stem with knops, a drip pan; the candle's foot at h.
static func _stand(c: Church, foot: Vector3, h: float) -> void:
	var b := c.iron
	var turn := c.rng.randf() * TAU
	for k in 3:
		var a := turn + TAU * k / 3.0
		var d := Vector3(sin(a), 0.0, cos(a))
		Shapes.beam(b, foot + Vector3(0, 0.16, 0), foot + d * 0.24 + Vector3(0, 0.01, 0), Vector2(0.025, 0.02))
		b.box(foot + d * 0.25 + Vector3(0, 0.012, 0), Vector3(0.05, 0.024, 0.05))
	Shapes.lathe(b, [Vector2(0.035, 0.12), Vector2(0.05, 0.16), Vector2(0.02, 0.2), Vector2(0.016, h * 0.45),
			Vector2(0.035, h * 0.47), Vector2(0.016, h * 0.49), Vector2(0.016, h - 0.06), Vector2(0.03, h - 0.04),
			Vector2(0.11, h - 0.015), Vector2(0.12, h), Vector2(0.0, h)], foot, 8)


## A candle of ivory wax standing at `at`: lit through near its flame, an uneven rim, a drip down its side, the pool
## in its top glowing; its flame above it (crossed quads: the flame and its halo). Returns the flame's place.
static func _candle(c: Church, at: Vector3, height: float, radius: float, group: String, size := 1.0) -> Vector3:
	var lit: RoomMesh = c.wax.get(group, null)
	if lit == null:
		lit = RoomMesh.new()
		var m: ShaderMaterial = c.n._lamp(Color.WHITE, 1.0, 0.0, group, true)
		m.set_shader_parameter("use_vertex_colour", true)
		lit.surface(m)
		c.wax[group] = lit
	var rows: Array = []
	var ns: Array = []
	var cols: Array = []
	var phase := c.rng.randf() * TAU
	var drip := c.rng.randf() * TAU
	var rings: Array = []
	for k in 9:
		var t := float(k) / 8.0
		rings.append([Vector2(radius, height * t), WAX_FOOT.lerp(WAX_TOP, pow(t, 2.2))])
	rings.append([Vector2(radius * 0.92, height + 0.004), WAX_TOP * 1.05])
	rings.append([Vector2(radius * 0.6, height - 0.008), WAX_POOL])
	rings.append([Vector2(0.0, height - 0.01), WAX_POOL * 1.15])
	for i in rings.size():
		var q: Vector2 = rings[i][0]
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in 11:
			var ang := TAU * float(k % 10) / 10.0
			var dir := Vector3(sin(ang), 0.0, cos(ang))
			var r := q.x
			var y := q.y
			if q.x > 0.0 and y > height - 0.01:
				y += 0.005 * sin(ang * 3.0 + phase)
			var swell := (1.0 - smoothstep(0.0, 0.5, absf(wrapf(ang - drip, -PI, PI)))) * smoothstep(height * 0.4,
					height * 0.7, y) * float(q.x > 0.0 and y <= height)
			r += 0.004 * swell
			row.append(at + dir * r + Vector3(0, y, 0))
			nrow.append((dir * 0.9 + Vector3.UP * (0.4 if i >= rings.size() - 3 else 0.0)).normalized())
			crow.append((rings[i][1] as Color).lerp(WAX_TOP, 0.3 * swell))
		rows.append(row)
		ns.append(nrow)
		cols.append(crow)
	lit.grid(rows, ns, cols)
	var f := at + Vector3(0, height + 0.006 + FLAME_HALF * 0.55 * size, 0)
	var quads: Array = c.flames.get(group, [])
	for k in 2:
		var t := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		quads.append([f, t * FLAME_HALF * size, Vector3(0, FLAME_HALF * size, 0), t.cross(Vector3.UP)])
	c.flames[group] = quads
	c.candles.append([f, group])
	return f


## A corona over the nave in bay k (from the chancel): an iron hoop with a cresting of small fleurs, `CORONA_CANDLES`
## candles on its rim, three chains to a ring and one chain up to the vault's boss. lit: its candles burn (the accent
## group: low in the film) and light the bake.
static func _corona(c: Church, k: int, lit: bool) -> void:
	if k + 1 >= c.lines.size():
		return
	var b := c.iron
	var z := (c.lines[k] + c.lines[k + 1]) * 0.5
	var at := Vector3(0.0, CORONA_Y, z)
	var r := CORONA_R
	# The hoop: a flat band, a rim and a bead under it.
	var pts: Array = []
	var sides: Array = []
	var outs: Array = []
	for i in 49:
		var t := TAU * i / 48.0
		var d := Vector3(sin(t), 0.0, cos(t))
		pts.append(at + d * r)
		sides.append(Vector3.UP)
		outs.append(d)
	_curve_sweep(b, pts, sides, outs, [Vector2(-0.07, 0.0), Vector2(-0.07, 0.012), Vector2(0.05, 0.012),
			Vector2(0.065, 0.02), Vector2(0.075, 0.0)], Vector2(0.0, -0.02))
	_curve_sweep(b, pts, sides, outs, [Vector2(0.075, 0.0), Vector2(0.065, -0.02), Vector2(0.05, -0.012),
			Vector2(-0.07, -0.012), Vector2(-0.07, 0.0)], Vector2(0.0, 0.02))
	# A cresting of small three-lobed fleurs round the top, and the candles' sockets on the rim.
	for i in 16:
		var t := TAU * (i + 0.5) / 16.0
		var d := Vector3(sin(t), 0.0, cos(t))
		var base := at + d * (r + 0.005) + Vector3(0, 0.075, 0)
		var across := Vector3(cos(t), 0.0, -sin(t))
		for lobe: Array in [[0.0, 0.07, 0.024], [-0.032, 0.035, 0.017], [0.032, 0.035, 0.017]]:
			var cen := base + across * float(lobe[0]) + Vector3(0, float(lobe[1]), 0)
			b.box(cen, Vector3(float(lobe[2]) * 2.0, float(lobe[2]) * 2.0, 0.008), Basis(across, Vector3.UP, d),
					[Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN])
	for i in CORONA_CANDLES:
		var t := TAU * i / CORONA_CANDLES
		var d := Vector3(sin(t), 0.0, cos(t))
		var sock := at + d * r + Vector3(0, 0.075, 0)
		Shapes.lathe(b, [Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.05, 0.01), Vector2(0.02, 0.02),
				Vector2(0.02, 0.035)], sock + Vector3(0, -0.04, 0), 8)
		if lit:
			_candle(c, sock - Vector3(0, 0.005, 0), c.rng.randf_range(0.14, 0.26), 0.022, "accent", 0.7)
	# The chains: three from the hoop to a ring above, one from it up to the boss.
	var ring := at + Vector3(0, 1.4, 0)
	for i in 3:
		var t := TAU * (i + 0.25) / 3.0
		_chain(c, at + Vector3(sin(t), 0.0, cos(t)) * (r - 0.02) + Vector3(0, 0.02, 0), ring)
	_chain(c, ring, Vector3(0.0, c.crown - 0.3, z))
	Shapes.lathe(b, [Vector2(0.06, -0.02), Vector2(0.07, 0.0), Vector2(0.06, 0.02), Vector2(0.0, 0.02)], ring, 8)
	if lit:
		c.n._bake_omni("Corona%d" % k, at + Vector3(0, 0.1, 0), CORONA_REACH, CORONA_LIGHT, FLAME)
		c.n._light.add_lamp(at + Vector3(0, 0.1, 0), FLAME * CORONA_LAMP, 0.0)


## A chain from a to b: seen from the floor seven metres down a thin dark line, so a slim rod of four faces (links
## would be thousands of tiny faces in the bake's atlas for nothing anyone can see).
static func _chain(c: Church, a: Vector3, b2: Vector3) -> void:
	Shapes.beam(c.iron, a, b2, Vector2(0.018, 0.018))


## A votive stand in the north aisle's east end: an iron rack of three tiers, small lights in glass cups of ruby,
## amber and blue on each (the stage group: dim in the film), against the east wall.
static func _votive(c: Church) -> void:
	var b := c.iron
	var x := -(c.ow + c.nh + WALL_T * 0.5) * 0.5
	var z := c.cz + 0.55
	var cups := RoomMesh.new()
	var m: ShaderMaterial = c.n._lamp(Color.WHITE, 1.0, 0.0, "stage", true)
	m.set_shader_parameter("use_vertex_colour", true)
	cups.surface(m)
	for k in 3:
		var y := 0.78 + k * 0.16
		var zz := z + 0.32 - k * 0.14
		b.box(Vector3(x, y - 0.01, zz), Vector3(1.0, 0.02, 0.12))
		for i in 7:
			var cx := x - 0.42 + i * 0.14 + (0.07 if k % 2 == 1 else 0.0)
			if cx > x + 0.46:
				continue
			var at := Vector3(cx, y, zz)
			var tint: Color = [Color(0.9, 0.12, 0.08), Color(1.0, 0.55, 0.12), Color(0.15, 0.25, 0.9),
					Color(0.95, 0.35, 0.1)][(i + k * 3) % 4]
			# The cup: a short tube of coloured glass lit from inside.
			var rows: Array = []
			var ns: Array = []
			var cols: Array = []
			for j in 3:
				var row := PackedVector3Array()
				var nrow := PackedVector3Array()
				var crow := PackedColorArray()
				for s in 9:
					var ang := TAU * float(s % 8) / 8.0
					var dir := Vector3(sin(ang), 0.0, cos(ang))
					row.append(at + dir * 0.028 + Vector3(0, 0.03 * j, 0))
					nrow.append(dir)
					crow.append(tint * (0.25 + 0.35 * j))
				rows.append(row)
				ns.append(nrow)
				cols.append(crow)
			cups.grid(rows, ns, cols)
			var f := at + Vector3(0, 0.05, 0)
			var quads: Array = c.flames.get("stage", [])
			for t: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
				quads.append([f, t * FLAME_HALF * 0.45, Vector3(0, FLAME_HALF * 0.45, 0), t.cross(Vector3.UP)])
			c.flames["stage"] = quads
			c.candles.append([f, "stage"])
	# The frame: legs and a back rail.
	for e: float in [-0.48, 0.48]:
		b.box(Vector3(x + e, 0.55, z + 0.32), Vector3(0.03, 1.1, 0.03), Basis(), [Vector3.DOWN])
		b.box(Vector3(x + e, 0.65, z + 0.04), Vector3(0.03, 1.3, 0.03), Basis(), [Vector3.DOWN])
	b.box(Vector3(x, 1.3, z + 0.04), Vector3(1.0, 0.03, 0.03))
	c.n._add_lamps("Votives", cups)
	c.n._bake_omni("Votive", Vector3(x, 1.1, z + 0.2), VOTIVE_REACH, VOTIVE_LIGHT, Color(1.0, 0.55, 0.3))
	c.n._light.add_lamp(Vector3(x, 1.1, z + 0.2), Color(1.0, 0.55, 0.3) * VOTIVE_LAMP, 0.0)


## The candles' wax and flames as meshes, by group.
static func _add_candles(c: Church) -> void:
	for group: String in c.wax:
		c.n._add_lamps("Candles" if group == "house" else "Candles_" + group, c.wax[group])
	for group: String in c.flames:
		c.n._add_glow("Flames" if group == "house" else "Flames_" + group, c.flames[group], IceHall.flame_picture(),
				Color.WHITE, FLAME_ENERGY, group, true)


# --- Pews -------------------------------------------------------------------------------------------------------------

## The pews, one a run of places: a seat board, an apron, a panelled back leaning back under a moulded top rail, a
## book ledge for the row behind with hymn books on it, carved ends with poppy-head finials; a hassock on the floor
## at each place (worked in wool, each its own colours).
static func _pews(c: Church) -> void:
	var b := c.oak
	for run: Array in U.runs(c.n.seat_slots()):
		var first: Vector3 = (run[0]["transform"] as Transform3D).origin
		var last: Vector3 = (run[-1]["transform"] as Transform3D).origin
		var w := float(run[0]["width"])
		var x0 := first.x - w * 0.5
		var x1 := last.x + w * 0.5
		var z := first.z
		var mid := (x0 + x1) * 0.5
		var length := x1 - x0
		var lean := Basis(Vector3.RIGHT, deg_to_rad(-9.0))
		b.colour = Color(1, 1, 1)
		b.box(Vector3(mid, 0.445, z - 0.07), Vector3(length, 0.04, 0.42), Basis(), [Vector3.LEFT, Vector3.RIGHT])
		b.box(Vector3(mid, 0.37, z - 0.265), Vector3(length, 0.11, 0.025), Basis(), [Vector3.LEFT, Vector3.RIGHT])
		b.box(Vector3(mid, 0.5, z + 0.14), Vector3(length, 0.06, 0.05), Basis(), [Vector3.LEFT, Vector3.RIGHT])
		b.box(Vector3(mid, 0.72, z + 0.17), Vector3(length, 0.44, 0.02), lean, [Vector3.LEFT, Vector3.RIGHT])
		# The back's muntins, a panel a place.
		for i in run.size() + 1:
			var mx := x0 + i * w
			b.box(Vector3(mx, 0.72, z + 0.16), Vector3(0.05, 0.44, 0.03), lean, [Vector3.LEFT, Vector3.RIGHT])
		# The top rail: rounded on top, the book ledge behind it, its lip.
		_curve_sweep(b, [Vector3(x0, 0.95, z + 0.21), Vector3(x1, 0.95, z + 0.21)], [Vector3.BACK, Vector3.BACK],
				[Vector3.UP, Vector3.UP], [Vector2(-0.04, -0.01), Vector2(-0.04, 0.02), Vector2(-0.02, 0.04),
				Vector2(0.02, 0.04), Vector2(0.04, 0.02), Vector2(0.04, -0.01)], Vector2(0.0, 0.0))
		b.box(Vector3(mid, 0.79, z + 0.29), Vector3(length, 0.022, 0.13), Basis(), [Vector3.LEFT, Vector3.RIGHT])
		b.box(Vector3(mid, 0.81, z + 0.355), Vector3(length, 0.06, 0.016), Basis(), [Vector3.LEFT, Vector3.RIGHT])
		for e: float in [-1.0, 1.0]:
			_pew_end(c, Vector3(mid + e * (length * 0.5 + 0.03), 0.0, z), e)
		# Books on the ledge and a hassock at each place.
		for slot: Dictionary in run:
			var o: Vector3 = (slot["transform"] as Transform3D).origin
			if c.rng.randf() < 0.45:
				var tint: Color = BOOK_COLOURS[c.rng.randi() % BOOK_COLOURS.size()]
				c.cloth.colour = tint
				var turn := Basis(Vector3.UP, c.rng.randf_range(-0.25, 0.25))
				c.cloth.box(Vector3(o.x + c.rng.randf_range(-0.12, 0.12), 0.818, z + 0.285), Vector3(0.12, 0.034, 0.18),
						turn, [Vector3.DOWN])
			if c.rng.randf() < 0.85:
				c.cloth.colour = HASSOCKS[c.rng.randi() % HASSOCKS.size()]
				var turn2 := Basis(Vector3.UP, c.rng.randf_range(-0.3, 0.3))
				c.cloth.box(Vector3(o.x + c.rng.randf_range(-0.08, 0.08), 0.043, z - 0.6 + c.rng.randf_range(-0.05,
						0.05)), Vector3(0.32, 0.085, 0.22), turn2, [Vector3.DOWN])
	c.cloth.colour = Color.WHITE


## A pew's end: a board a little proud of the pew, its top rising from the arm at the front to a poppy-head finial
## at the back (three lobes of carved leaf), its edges chamfered; side -1 the left end, 1 the right.
static func _pew_end(c: Church, at: Vector3, side: float) -> void:
	var b := c.oak
	var z := at.z
	var t := 0.055
	# The outline in (along z, up), from the front foot round the top to the back foot.
	var outline: Array[Vector2] = [Vector2(z - 0.33, 0.0), Vector2(z - 0.33, 0.6), Vector2(z - 0.29, 0.64),
			Vector2(z - 0.18, 0.66), Vector2(z - 0.05, 0.74), Vector2(z + 0.06, 0.88), Vector2(z + 0.13, 0.98)]
	# The poppy head: a stem, then three lobes (the middle tallest).
	var pc := z + 0.22
	for e: Array in [[-0.08, 0.99], [-0.1, 1.05], [-0.075, 1.1], [-0.045, 1.08], [-0.035, 1.14], [-0.015, 1.19],
			[0.0, 1.2], [0.015, 1.19], [0.035, 1.14], [0.045, 1.08], [0.075, 1.1], [0.1, 1.05], [0.08, 0.99]]:
		outline.append(Vector2(pc + float(e[0]), float(e[1])))
	outline.append_array([Vector2(z + 0.33, 0.97), Vector2(z + 0.36, 0.94), Vector2(z + 0.36, 0.0)])
	for f: float in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		for q: Vector2 in outline:
			pts.append(Vector3(at.x + f * t * 0.5, q.y, q.x))
		b.polygon(pts, Vector3(f, 0, 0))
	# The edges round the outline (not the foot).
	var la := PackedVector3Array()
	var lb := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in outline.size():
		var q: Vector2 = outline[i]
		var prev: Vector2 = outline[maxi(i - 1, 0)]
		var next: Vector2 = outline[mini(i + 1, outline.size() - 1)]
		var along := (next - prev).normalized()
		var nrm := Vector2(-along.y, along.x)
		var centre := Vector2(z + 0.02, 0.5)
		if nrm.dot(q - centre) < 0.0:
			nrm = -nrm
		la.append(Vector3(at.x - t * 0.5, q.y, q.x))
		lb.append(Vector3(at.x + t * 0.5, q.y, q.x))
		ns.append(Vector3(0.0, nrm.y, nrm.x))
	b.strip(la, lb, ns)
	# A sunk panel on the outer face, its tracery suggested by a pointed head.
	var o := at.x + side * (t * 0.5 + 0.004)
	var panel := PackedVector3Array()
	for q: Vector2 in [Vector2(z - 0.24, 0.12), Vector2(z + 0.27, 0.12), Vector2(z + 0.27, 0.62), Vector2(z + 0.15, 0.74),
			Vector2(z + 0.015, 0.78), Vector2(z - 0.12, 0.72), Vector2(z - 0.24, 0.6)]:
		panel.append(Vector3(o, q.y, q.x))
	b.colour = Color(0.72, 0.68, 0.64)
	b.polygon(panel, Vector3(side, 0, 0))
	b.colour = Color.WHITE


# --- Fittings ---------------------------------------------------------------------------------------------------------

## The reredos round the screen, as an altarpiece's frame of dark oak picked out in gilt (no figures): a buttress
## either side in three stages with a pinnacle, crockets and a finial; over the picture a frieze of small pointed
## arches under a moulded cornice with a cresting of gilt leaves; under it a panelled dado with blind tracery. The
## picture and the masking round it stay clear.
static func _reredos(c: Church) -> void:
	var b := c.oak
	var g := c.gilt
	var half := c.screen_s.x * 0.5 + REREDOS_CLEAR
	var bottom := c.screen_c.y - c.screen_s.y * 0.5 - REREDOS_CLEAR
	var top := c.screen_c.y + c.screen_s.y * 0.5 + REREDOS_CLEAR
	var back := c.ez
	var front := c.screen_c.z + 0.02
	b.colour = Color(0.75, 0.72, 0.7)
	# The buttresses.
	for s: float in [-1.0, 1.0]:
		var x := s * (half + 0.17)
		var stages: Array = [[c.rise, 2.6, 0.34, 0.56], [2.6, 4.5, 0.3, 0.5], [4.5, top + 0.5, 0.26, 0.44]]
		for st: Array in stages:
			var y0 := float(st[0])
			var y1 := float(st[1])
			var w := float(st[2])
			var d := float(st[3])
			b.box(Vector3(x, (y0 + y1) * 0.5, back + d * 0.5), Vector3(w, y1 - y0, d), Basis(), [Vector3.DOWN,
					Vector3.FORWARD])
			# A sunk panel with a pointed head on its front, outlined in gilt.
			var fz := back + d + 0.004
			_gilt_arch(c, Vector3(x, y1 - 0.12 - w * 0.6, fz), w * 0.3, w * 0.42, y1 - y0 - 0.3 - w * 0.6)
		# The gablet and the pinnacle with its crockets and finial.
		var py := top + 0.5
		Shapes.lathe(b, [Vector2(0.2, 0.0), Vector2(0.0, 0.3)], Vector3(x, py, back + 0.22), 4,
				Basis(Vector3.UP, PI * 0.25))
		b.box(Vector3(x, py + 0.55, back + 0.22), Vector3(0.11, 0.6, 0.11))
		for k in 4:
			for e: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				g.box(Vector3(x + e.x * 0.065, py + 0.38 + k * 0.14, back + 0.22 + e.y * 0.065), Vector3(0.035, 0.045,
						0.035), Basis(Vector3.UP, PI * 0.25))
		Shapes.lathe(g, [Vector2(0.0, 0.0), Vector2(0.05, 0.03), Vector2(0.06, 0.08), Vector2(0.03, 0.14),
				Vector2(0.045, 0.18), Vector2(0.0, 0.26)], Vector3(x, py + 0.85, back + 0.22), 8)
	# The frieze over the picture: a beam, a row of small pointed arches in gilt on its face, a cornice and a cresting.
	var fy := top + 0.02
	var fd := front - back + 0.06
	b.box(Vector3(0, fy + 0.17, back + fd * 0.5), Vector3(half * 2.0, 0.34, fd), Basis(), [Vector3.FORWARD])
	var count := 22
	var pitch := half * 2.0 / count
	for k in count:
		var cx := -half + (k + 0.5) * pitch
		_gilt_arch(c, Vector3(cx, fy + 0.08, back + fd + 0.004), pitch * 0.36, pitch * 0.5, 0.06)
	_curve_sweep(b, [Vector3(-half - 0.05, fy + 0.34, back + fd), Vector3(half + 0.05, fy + 0.34, back + fd)],
			[Vector3.UP, Vector3.UP], [Vector3.BACK, Vector3.BACK], [Vector2(0.0, 0.0), Vector2(0.02, 0.05),
			Vector2(0.06, 0.07), Vector2(0.1, 0.06), Vector2(0.12, 0.0)], Vector2(0.06, -0.05))
	b.box(Vector3(0, fy + 0.43, back + (fd + 0.06) * 0.5), Vector3(half * 2.0 + 0.1, 0.03, fd + 0.06))
	for k in int(half * 2.0 / 0.16):
		var cx := -half + 0.08 + k * 0.16
		var base := Vector3(cx, fy + 0.45, back + fd - 0.02)
		for lobe: Array in [[0.0, 0.07, 0.03], [-0.035, 0.035, 0.02], [0.035, 0.035, 0.02]]:
			g.box(base + Vector3(float(lobe[0]), float(lobe[1]), 0.0), Vector3(float(lobe[2]) * 2.0,
					float(lobe[2]) * 2.0, 0.012), Basis(Vector3.BACK, PI * 0.25), [Vector3.FORWARD])
	# The dado under the picture: panels of blind tracery between gilt rails.
	var dy := bottom - 0.02
	var dd := front - back - 0.04
	b.box(Vector3(0, (c.rise + dy) * 0.5, back + dd * 0.5), Vector3(half * 2.0, dy - c.rise, dd), Basis(),
			[Vector3.FORWARD, Vector3.DOWN])
	g.box(Vector3(0, dy - 0.02, back + dd + 0.005), Vector3(half * 2.0, 0.03, 0.012), Basis(), [Vector3.FORWARD])
	var panels := 8
	var pw := half * 2.0 / panels
	for k in panels:
		var cx := -half + (k + 0.5) * pw
		_gilt_arch(c, Vector3(cx, dy - 0.32, back + dd + 0.004), pw * 0.36, pw * 0.4, dy - c.rise - 0.45)
	b.colour = Color.WHITE


## A thin gilt line round a pointed arch on a face (at the springing `at`, half span a, rise h), down its jambs by
## `foot`.
static func _gilt_arch(c: Church, at: Vector3, a: float, h: float, foot: float) -> void:
	var prof: Array = [Vector2(0.012, 0.0), Vector2(0.012, 0.022), Vector2(0.0, 0.022)]
	_arch_sweep(c.gilt, at, Vector3.RIGHT, Vector3.BACK, a, h, prof, Vector2(0.0, 0.01), 5)
	if foot > 0.0:
		_jamb_sweep(c.gilt, at, Vector3.RIGHT, Vector3.BACK, a, foot, prof, Vector2(0.0, 0.01))


## The hymn board hung on the south pier nearest the chancel at height `y`, turned towards the middle of the pews:
## a board of oak with a gabled top, four black slips, each with a hymn's number in gilt (our own numbers).
static func _hymn_board(c: Church, y: float) -> void:
	var pier := Vector3(c.nh, 0.0, c.lines[1])
	var toward := Vector3(-pier.x, 0.0, 2.0 - pier.z).normalized()
	var basis := Basis(Vector3.UP.cross(toward).normalized(), Vector3.UP, toward)
	var xf := Transform3D(basis, pier + toward * 0.66 + Vector3.UP * y)
	var front := basis.z
	var b := c.oak
	var w := 0.5
	var h := 1.0
	b.colour = Color(0.8, 0.76, 0.72)
	b.box(xf * Vector3(0, h * 0.5, 0.02), Vector3(w, h, 0.04), basis, [Vector3.FORWARD])
	b.polygon(PackedVector3Array([xf * Vector3(-w * 0.5 - 0.02, h, 0.045), xf * Vector3(w * 0.5 + 0.02, h, 0.045),
			xf * Vector3(0, h + 0.18, 0.045)]), front)
	for e: float in [-1.0, 1.0]:
		b.box(xf * Vector3(e * (w * 0.5 + 0.01), h * 0.5, 0.035), Vector3(0.03, h + 0.02, 0.03), basis)
	b.box(xf * Vector3(0, -0.01, 0.035), Vector3(w + 0.05, 0.03, 0.04), basis)
	var numbers := ["117", "364", "52", "408"]
	for k in numbers.size():
		var ly := h - 0.14 - k * 0.22
		c.cloth.colour = Color(0.03, 0.03, 0.035)
		c.cloth.box(xf * Vector3(0, ly, 0.05), Vector3(w - 0.08, 0.17, 0.012), basis, [Vector3.FORWARD])
		var text: String = numbers[k]
		var tw := Strokes.width(text, 0.1)
		for line: PackedVector2Array in Strokes.lines(text, 0.1):
			for i in line.size() - 1:
				var p0 := xf * Vector3(-tw * 0.5 + line[i].x, ly - 0.05 + line[i].y, 0.058)
				var p1 := xf * Vector3(-tw * 0.5 + line[i + 1].x, ly - 0.05 + line[i + 1].y, 0.058)
				_stroke(c.carve, p0, p1, 0.013, front)
	c.cloth.colour = Color.WHITE
	b.colour = Color.WHITE
	# The hook it hangs from, into the pier.
	Shapes.beam(c.iron, xf * Vector3(0, h + 0.12, 0.03), xf * Vector3(0, h + 0.12, -0.3), Vector2(0.015, 0.015))


## A flat stroke from a to b, `width` wide, on a face looking along `normal`.
static func _stroke(b: RoomMesh, a: Vector3, e: Vector3, width: float, normal: Vector3) -> void:
	var d := (e - a)
	if d.length() < 0.0001:
		return
	var side := normal.cross(d.normalized()) * width * 0.5
	var ext := d.normalized() * width * 0.4
	b.face([a - side - ext, e - side + ext, e + side + ext, a + side - ext], normal)


## The ledger stones: slabs of dark polished stone let into the floor, worn smooth, each with a border line and rows
## of worn letters no one can read now (our own: random letters, half their strokes worn away), and a roundel.
static func _ledgers(c: Church) -> void:
	var b := c.marble
	var rng := RandomNumberGenerator.new()
	rng.seed = 1349
	for l: Rect2 in c.ledgers:
		var y := 0.005
		b.colour = Color(1.0, 0.97, 0.94) * rng.randf_range(0.8, 1.0)
		b.face([Vector3(l.position.x, y, l.position.y), Vector3(l.end.x, y, l.position.y), Vector3(l.end.x, y, l.end.y),
				Vector3(l.position.x, y, l.end.y)], Vector3.UP)
		# The lettering runs across the slab's width, read from its foot (the west, +z) or across the nave.
		var long_z := l.size.y > l.size.x
		var across := Vector3.RIGHT if long_z else Vector3.BACK
		var down := Vector3.BACK if long_z else Vector3.LEFT
		var width := l.size.x if long_z else l.size.y
		var length := l.size.y if long_z else l.size.x
		var origin := Vector3(l.get_center().x, y + 0.0015, l.get_center().y) - across * width * 0.5 - down * length * 0.5
		var cut := c.carve
		cut.colour = Color(0.62, 0.6, 0.56) * rng.randf_range(0.85, 1.1)
		# The border.
		var inset := 0.06
		var corners: Array[Vector3] = [origin + across * inset + down * inset, origin + across * (width - inset) + down * inset,
				origin + across * (width - inset) + down * (length - inset), origin + across * inset + down * (length - inset)]
		for k in 4:
			_stroke(cut, corners[k], corners[(k + 1) % 4], 0.01, Vector3.UP)
		# A roundel near the head.
		var rc: Vector3 = origin + across * width * 0.5 + down * 0.36
		for k in 20:
			var t0 := TAU * k / 20.0
			var t1 := TAU * (k + 1) / 20.0
			_stroke(cut, rc + (across * cos(t0) + down * sin(t0)) * 0.16, rc + (across * cos(t1) + down * sin(t1)) * 0.16,
					0.009, Vector3.UP)
			if k % 2 == 0:
				_stroke(cut, rc + (across * cos(t0) + down * sin(t0)) * 0.05, rc + (across * cos(t0) + down * sin(t0)) * 0.13,
						0.008, Vector3.UP)
		# Rows of worn letters.
		var rows := int((length - 0.75) / 0.11)
		for r in rows:
			var text := ""
			var count := rng.randi_range(5, 11)
			for k in count:
				text += "ABCDEFGHIKLMNOPRSTVX "[rng.randi() % 21]
			var tw := Strokes.width(text, 0.055)
			var lx := (width - tw) * 0.5
			var ly := 0.62 + r * 0.11
			for line: PackedVector2Array in Strokes.lines(text, 0.055):
				for i in line.size() - 1:
					if rng.randf() < 0.45:
						continue
					var p0 := origin + across * (lx + line[i].x) + down * (ly - line[i].y)
					var p1 := origin + across * (lx + line[i + 1].x) + down * (ly - line[i + 1].y)
					_stroke(cut, p0, p1, 0.009, Vector3.UP)
	b.colour = Color.WHITE
	c.carve.colour = Color.WHITE


## The west doors in their doorway (at: the foot of their middle, on the reveal's inner face): two leaves of oak
## boards, the head boarded to the arch, iron strap hinges with curled ends, a ring.
static func _doors(c: Church, at: Vector3, a: float, spring: float, rise: float) -> void:
	var b := c.oak
	var boards := 10
	var bw := a * 2.0 / boards
	for k in boards:
		var x0 := at.x - a + k * bw + 0.004
		var x1 := x0 + bw - 0.008
		var t0 := _fv(a, rise, x0 - at.x)
		var t1 := _fv(a, rise, x1 - at.x)
		b.colour = Color(0.62, 0.55, 0.5) * (0.85 + 0.25 * c.rng.randf())
		b.face([Vector3(x0, 0.0, at.z), Vector3(x1, 0.0, at.z), Vector3(x1, spring + t1 - 0.01, at.z),
				Vector3(x0, spring + t0 - 0.01, at.z)], Vector3.FORWARD)
	b.colour = Color(0.2, 0.18, 0.16)
	b.face([Vector3(at.x - a, 0.0, at.z + 0.002), Vector3(at.x + a, 0.0, at.z + 0.002),
			Vector3(at.x + a, spring + rise, at.z + 0.002), Vector3(at.x - a, spring + rise, at.z + 0.002)], Vector3.FORWARD)
	b.colour = Color.WHITE
	for s: float in [-1.0, 1.0]:
		for y: float in [0.45, 1.35, 2.25]:
			var x0 := at.x + s * (a - 0.03)
			var x1 := at.x + s * 0.15
			c.iron.box(Vector3((x0 + x1) * 0.5, y, at.z - 0.012), Vector3(absf(x1 - x0), 0.06, 0.012), Basis(),
					[Vector3.BACK])
			# The curled end: a few short strokes round.
			for k in 5:
				var t := PI * k / 5.0
				var p := Vector3(x1 - s * 0.05 * sin(t), y + 0.05 * cos(t), at.z - 0.013)
				c.iron.box(p, Vector3(0.025, 0.025, 0.012), Basis(), [Vector3.BACK])
		Shapes.lathe(c.iron, [Vector2(0.05, 0.0), Vector2(0.06, 0.01), Vector2(0.05, 0.02)],
				Vector3(at.x + s * 0.12, 1.05, at.z - 0.01), 10, Basis(Vector3.RIGHT, PI * 0.5))


# --- Glass ------------------------------------------------------------------------------------------------------------

## A window's glass: the outline at the glass (along, up), a polygon in the plane through origin; its picture the
## atlas cell of `spec` (drawn from `shape`, the tracery's layout).
static func _glass(c: Church, origin: Vector3, u: Vector3, normal: Vector3, outline: Array[Vector2], spec: String,
		shape: Dictionary) -> void:
	var cell := -1
	for i in c.specs.size():
		if c.specs[i][0] == spec:
			cell = i
	if cell < 0:
		c.specs.append([spec, shape])
		cell = c.specs.size() - 1
	var hc := float(shape["c"])
	var a := float(shape["a"])
	var sill := float(shape["sill"])
	var apex := float(shape["spring"]) + float(shape["h"])
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for q: Vector2 in outline:
		pts.append(origin + u * q.x + Vector3.UP * q.y)
		uvs.append(Vector2(clampf((q.x - hc + a) / (2.0 * a), 0.0, 1.0), clampf(1.0 - (q.y - sill) / (apex - sill),
				0.0, 1.0)))
	c.glass.append({"pts": pts, "uvs": uvs, "normal": normal, "cell": cell})


## The glass meshes: the windows (one atlas of their pictures) and the rose, on the light system's lamp material
## (they glow a little with the Moon behind them; never baked).
static func _add_glass(c: Church) -> void:
	var cells := c.specs.size()
	var atlas := _window_atlas(c)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for g: Dictionary in c.glass:
		var cell := int(g["cell"])
		var uvs := PackedVector2Array()
		for q: Vector2 in g["uvs"]:
			uvs.append(Vector2((cell + q.x) / cells, q.y))
		_polygon(st, g["pts"], uvs, g["normal"])
	var m: ShaderMaterial = c.n._lamp(Color.WHITE, float(c.p["window_glow"]), 0.0, "signs")
	m.set_shader_parameter("picture", atlas)
	m.set_shader_parameter("use_picture", true)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	c.n.set("_windows", m)
	c.n._add_mesh("Glass", mesh).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_pools(c, atlas, cells)
	if not c.rose_glass.is_empty():
		var rs := SurfaceTool.new()
		rs.begin(Mesh.PRIMITIVE_TRIANGLES)
		for g: Dictionary in c.rose_glass:
			_polygon(rs, g["pts"], g["uvs"], g["normal"])
		# In the steady signs group: the ritual moves accent (the coronae), the rose has its own cue.
		var rm: ShaderMaterial = c.n._lamp(Color.WHITE, float(c.p["rose_glow"]), 0.0, "signs")
		rm.set_shader_parameter("picture", _rose_picture())
		rm.set_shader_parameter("use_picture", true)
		var rmesh := rs.commit()
		rmesh.surface_set_material(0, rm)
		c.n.set("_rose", rm)
		c.n._add_mesh("Rose", rmesh).gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## The Moon's light through the south aisle's coloured glass lying on the aisle's floor: each window's glass carried
## along the light down to the floor (so its colours and leading fall there, stretched), the part on the open floor
## between the pews' ends and the wall, as a faint wash added over the stone (env_flame.gdshader). It follows the
## windows' glow (dimmer in the film).
static func _pools(c: Church, atlas: Texture2D, cells: int) -> void:
	var travel := -MOON_DIR.normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for g: Dictionary in c.glass:
		if not str(c.specs[int(g["cell"])][0]).begins_with("aisle_s"):
			continue
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		for i in (g["pts"] as PackedVector3Array).size():
			var p: Vector3 = g["pts"][i]
			pts.append(p + travel * ((POOL_Y - p.y) / travel.y))
			var q: Vector2 = g["uvs"][i]
			uvs.append(Vector2((int(g["cell"]) + q.x) / cells, q.y))
		# Only the open floor: from the pews' ends to the wall's bench.
		var clipped := _clip_x(pts, uvs, POOL_FROM, c.ow - 0.34)
		if (clipped[0] as PackedVector3Array).size() >= 3:
			_polygon(st, clipped[0], clipped[1], Vector3.UP)
			any = true
	if not any:
		return
	var m := ShaderMaterial.new()
	m.shader = c.n.GLOW_SHADER
	m.set_shader_parameter("colour", Color.WHITE)
	m.set_shader_parameter("picture", atlas)
	m.set_shader_parameter("energy", float(c.p["window_glow"]) * POOL_SHARE)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	c.n.set("_pool", m)
	var mi: MeshInstance3D = c.n._add_mesh("MoonPool", mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.add_to_group(c.n.SEE_THROUGH)


## A polygon (with its UVs) cut to x0 <= x <= x1.
static func _clip_x(pts: PackedVector3Array, uvs: PackedVector2Array, x0: float, x1: float) -> Array:
	var out_p := pts
	var out_u := uvs
	for edge: Array in [[x0, 1.0], [x1, -1.0]]:
		var limit := float(edge[0])
		var dir := float(edge[1])
		var np := PackedVector3Array()
		var nu := PackedVector2Array()
		for i in out_p.size():
			var a := out_p[i]
			var b := out_p[(i + 1) % out_p.size()]
			var ua := out_u[i]
			var ub := out_u[(i + 1) % out_u.size()]
			var ina := (a.x - limit) * dir >= 0.0
			var inb := (b.x - limit) * dir >= 0.0
			if ina:
				np.append(a)
				nu.append(ua)
			if ina != inb:
				var t := (limit - a.x) / (b.x - a.x)
				np.append(a.lerp(b, t))
				nu.append(ua.lerp(ub, t))
		out_p = np
		out_u = nu
		if out_p.size() < 3:
			break
	return [out_p, out_u]


## A flat polygon (its outline, a UV each) into a SurfaceTool, facing `normal`.
static func _polygon(st: SurfaceTool, pts: PackedVector3Array, uvs: PackedVector2Array, normal: Vector3) -> void:
	var u := (pts[1] - pts[0]).normalized()
	var v := normal.cross(u).normalized()
	var flat := PackedVector2Array()
	for q: Vector3 in pts:
		flat.append(Vector2((q - pts[0]).dot(u), (q - pts[0]).dot(v)))
	var tris := Geometry2D.triangulate_polygon(flat)
	for k in range(0, tris.size(), 3):
		var order := [tris[k], tris[k + 1], tris[k + 2]]
		if (pts[order[2]] - pts[order[0]]).cross(pts[order[1]] - pts[order[0]]).dot(normal) < 0.0:
			order = [tris[k], tris[k + 2], tris[k + 1]]
		for i: int in order:
			st.set_normal(normal)
			st.set_uv(uvs[i])
			st.add_vertex(pts[i])


## The Moon's light for the bake, through the south windows: a narrow spot just inside each (the window's middle),
## aimed along the Moon's light, so each lays a soft cool patch across the floor, the pews or the piers opposite (a
## directional light gave nothing in the run-time bake).
static func _moon(c: Church) -> void:
	var travel := -MOON_DIR.normalized()
	var k := 0
	for w: Array in c.moon_windows:
		var l := SpotLight3D.new()
		l.name = "Moon%d" % k
		l.light_color = MOON_COLOUR
		l.light_energy = float(c.p["moonlight"]) * float(w[1])
		l.spot_range = 22.0
		l.spot_angle = float(w[2])
		l.spot_attenuation = 0.2
		l.transform = Transform3D(Basis.looking_at(travel, Vector3.UP), w[0])
		c.n._light.add_bake_light(l)
		k += 1


# --- Stone ------------------------------------------------------------------------------------------------------------

static var _maps_cache := {}

## Our own stone's maps for the house shader (procedural.gd's layout: albedo; a normal map in G and A; occlusion,
## roughness and metal), made once:
##   ashlar   2.4 m square: eight courses of about 0.3 m, blocks of 0.45 to 0.95 m, each its own shade and hue (a few
##            ochre, a few grey), thin lime joints a little paler and sunk, the arrises worn round, a chip here and
##            there, the faces finely tooled
##   grain    1.1 m square: the same stone without joints (capitals, mouldings, tracery)
##   flag     1.5 m square: a worn paving stone's face, mottled, a few fossil flecks and darker stains
static func _stone_maps(kind: String) -> Dictionary:
	if _maps_cache.has(kind):
		return _maps_cache[kind]
	var span := 2.4 if kind == "ashlar" else (1.1 if kind == "grain" else 1.5)
	var drawn := ProcCache.images("nave_gothic.gd:_maps_cache:" + kind,
			func() -> Array: return _draw_stone_maps(kind, span))
	var out := {"albedo": ImageTexture.create_from_image(drawn[0]), "normal": ImageTexture.create_from_image(drawn[1]),
			"orm": ImageTexture.create_from_image(drawn[2]), "mean": drawn[3].get_pixel(0, 0), "span": span}
	_maps_cache[kind] = out
	return out


## The stone's maps of `kind` (mipmapped), one repeat `span` metres, and the albedo's mean as one pixel.
static func _draw_stone_maps(kind: String, span: float) -> Array:
	var size := 256 if kind == "ashlar" else 128
	var courses: Array[float] = [0.31, 0.27, 0.33, 0.29, 0.32, 0.28, 0.3, 0.3]
	var rng := RandomNumberGenerator.new()
	rng.seed = 731
	# Each course's joints along it (metres, wrapping at the span) and each block's tone.
	var joints: Array = []
	for k in courses.size():
		var list: Array[float] = []
		var x := rng.randf() * 0.6
		var first := x
		while x < first + span - 0.4:
			list.append(fposmod(x, span))
			x += rng.randf_range(0.45, 0.95)
		list.sort()
		joints.append(list)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var normal := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var rough := PackedFloat32Array()
	rough.resize(size * size)
	var mean := Color(0, 0, 0)
	# Seamless noise (it tiles with the maps): the grain fine and coarse, the mottle, the chips, stains, flecks.
	var fine := _seamless(size, span * 31.0, 3)
	var coarse := _seamless(size, span * 9.0, 5)
	var mot := _seamless(size, maxf(roundf(span * 1.7), 1.0), 7)
	var spots := _seamless(size, span * 14.0, 11)
	var stains := _seamless(size, maxf(roundf(span * 3.0), 1.0), 13)
	for py in size:
		for px in size:
			var u := (px + 0.5) / size * span
			var v := (py + 0.5) / size * span
			var at := py * size + px
			var grain := 0.6 * coarse[at] + 0.4 * fine[at]
			var mottle := mot[at]
			var h := 0.92 + 0.05 * grain
			var col := Color(0.86, 0.8, 0.7).lerp(Color(0.74, 0.69, 0.6), mottle)
			col = col * (0.94 + 0.1 * grain)
			var r := 0.88 - 0.1 * grain
			if kind == "ashlar":
				var cy := 0.0
				var k := 0
				while k < courses.size() - 1 and v > cy + courses[k]:
					cy += courses[k]
					k += 1
				var dv := minf(v - cy, cy + courses[k] - v)
				var list: Array[float] = joints[k]
				var bi := 0
				var du := 10.0
				for j in list.size():
					var d := absf(u - list[j])
					du = minf(du, minf(d, span - d))
					if u >= list[j]:
						bi = j + 1
				bi = bi % list.size()
				var edge := minf(du, dv)
				var tone := _hash3(k, bi, 17)
				var hue := _hash3(k, bi, 29)
				var block := Color(1.0, 1.0, 1.0) * (0.88 + 0.2 * tone)
				if hue > 0.86:
					block *= Color(1.08, 0.98, 0.84)
				elif hue < 0.12:
					block *= Color(0.9, 0.92, 0.95)
				col *= block
				# The arris worn round; the joint sunk and paler (lime).
				var worn := smoothstep(0.004, 0.022, edge)
				h = lerpf(0.55, h, worn)
				var chip := smoothstep(0.78, 0.95, spots[at]) * (1.0 - smoothstep(0.0, 0.05, edge))
				h -= 0.25 * chip
				col = col.lerp(Color(0.84, 0.8, 0.72), 1.0 - smoothstep(0.003, 0.007, edge))
				col *= 1.0 - 0.18 * (1.0 - worn) * smoothstep(0.003, 0.008, edge)
				r = lerpf(0.95, r, worn)
			elif kind == "flag":
				var stain := smoothstep(0.6, 0.9, stains[at])
				col = col.lerp(col * Color(0.8, 0.78, 0.76), stain * 0.5)
				var fleck := smoothstep(0.85, 0.97, spots[at])
				col = col.lerp(Color(0.92, 0.9, 0.84), fleck * 0.5)
				h = 0.9 + 0.04 * grain - 0.04 * stain
				# Worn smooth: a little sheen.
				r = 0.7 - 0.12 * mottle
			heights[py * size + px] = h
			rough[py * size + px] = r
			albedo.set_pixel(px, py, col)
			var lin := col.srgb_to_linear()
			mean += Color(lin.r, lin.g, lin.b) / float(size * size)
	var depth := 2.5 if kind == "ashlar" else 1.5
	for py in size:
		for px in size:
			var hx := heights[py * size + (px + 1) % size] - heights[py * size + (px - 1 + size) % size]
			var hy := heights[((py + 1) % size) * size + px] - heights[((py - 1 + size) % size) * size + px]
			var nn := Vector3(-hx * depth, hy * depth, 1.0).normalized()
			normal.set_pixel(px, py, Color(0.5, nn.x * 0.5 + 0.5, 0.5, nn.y * 0.5 + 0.5))
			orm.set_pixel(px, py, Color(clampf(0.6 + 0.4 * heights[py * size + px], 0.0, 1.0), rough[py * size + px], 0.0))
	for img: Image in [albedo, normal, orm]:
		img.generate_mipmaps()
	# UNDECIDED (brief): the mean is a number, not a picture; it is kept beside the maps as one float pixel (exact).
	var mean_px := Image.create_empty(1, 1, false, Image.FORMAT_RGBAF)
	mean_px.set_pixel(0, 0, mean)
	return [albedo, normal, orm, mean_px]


## Seamless noise over a square of `size` pixels, about `cells` features across (0..1).
static func _seamless(size: int, cells: float, seed_value: int) -> PackedFloat32Array:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.noise_type = FastNoiseLite.TYPE_PERLIN
	fn.fractal_type = FastNoiseLite.FRACTAL_NONE
	fn.frequency = cells / float(size)
	var img := fn.get_seamless_image(size, size, false, false, 0.1, true)
	var out := PackedFloat32Array()
	out.resize(size * size)
	for y in size:
		for x in size:
			out[y * size + x] = img.get_pixel(x, y).r
	return out


## A house material shows our stone's maps, `colour` on average, one repeat a span.
static func _apply_maps(m: ShaderMaterial, maps: Dictionary, colour: Color) -> void:
	m.set_shader_parameter("albedo_map", maps["albedo"])
	m.set_shader_parameter("normal_map", maps["normal"])
	m.set_shader_parameter("orm_map", maps["orm"])
	m.set_shader_parameter("normal_strength", 1.0)
	m.set_shader_parameter("tiling", float(maps["span"]))
	var mean: Color = maps["mean"]
	var c := colour.srgb_to_linear()
	m.set_shader_parameter("tint", Color(c.r / maxf(mean.r, 0.01), c.g / maxf(mean.g, 0.01),
			c.b / maxf(mean.b, 0.01)).linear_to_srgb())


# --- Pictures ----------------------------------------------------------------------------------------------------------

const CELL := Vector2i(96, 256)
static var _atlas_cache := {}


## The windows' pictures side by side, one cell a spec; made once for a set of specs.
static func _window_atlas(c: Church) -> ImageTexture:
	var key := ",".join(c.specs.map(func(e: Array) -> String: return str(e[0])))
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var img := Image.create_empty(CELL.x * maxi(c.specs.size(), 1), CELL.y, false, Image.FORMAT_RGB8)
	for i in c.specs.size():
		_draw_window(img, i, str(c.specs[i][0]), c.specs[i][1])
	var tex := ImageTexture.create_from_image(img)
	_atlas_cache[key] = tex
	return tex


## One window's glass in its cell: the lights in coloured glass (deep blue grounds, ruby borders, a vine of leaves
## or a lattice of quarries, our own), the head's circles in bright pieces round a flower, lead between the pieces;
## the stone's bars dark. The south side's glow a little where the Moon is behind it.
static func _draw_window(img: Image, cell: int, spec: String, shape: Dictionary) -> void:
	var hc := float(shape["c"])
	var a := float(shape["a"])
	var sill := float(shape["sill"])
	var apex := float(shape["spring"]) + float(shape["h"])
	var moonlit := spec.ends_with("_s") or spec == "lancet" or spec == "west"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec)
	var tones: Array[float] = []
	for k in 64:
		tones.append(rng.randf())
	for py in CELL.y:
		for px in CELL.x:
			var x := (px + 0.5) / CELL.x * 2.0 * a - a
			var y := sill + (1.0 - (py + 0.5) / CELL.y) * (apex - sill)
			var col := _window_colour(spec, shape, x + hc, y, tones) * (1.0 if moonlit else 0.55)
			if moonlit:
				# Brighter towards the top, where the Moon is behind it.
				col *= 0.75 + 0.5 * clampf((y - sill) / (apex - sill), 0.0, 1.0)
			img.set_pixel(cell * CELL.x + px, py, col.linear_to_srgb())


## The colour of the glass (linear) at (x, y) metres in a window's plane; black where stone or lead is.
static func _window_colour(spec: String, shape: Dictionary, x: float, y: float, tones: Array[float]) -> Color:
	var hc := float(shape["c"])
	var spring := float(shape["spring"])
	var bar := float(shape.get("bar", 0.05))
	var kind := str(shape["kind"])
	var palette := _palette(spec)
	var region := -1
	var lx := 0.0
	var ly := y - spring
	# Which light (or circle) the point is in.
	var lights: Array = []
	var circles: Array = []
	match kind:
		"two":
			var la := float(shape["la"])
			lights = [[hc - la - bar, la, float(shape["lh"])], [hc + la + bar, la, float(shape["lh"])]]
			circles = [[hc, float(shape["cy"]), float(shape["cr"])]]
		"three":
			var la := float(shape["la"])
			for e: float in [-1.0, 0.0, 1.0]:
				lights.append([hc + e * (la * 2.0 + bar * 2.0), la, float(shape["lh"])])
			circles = shape["circles"]
		_:
			lights = [[hc, float(shape["a"]), float(shape["h"])]]
	for i in lights.size():
		var l: Array = lights[i]
		var dx := x - float(l[0])
		if absf(dx) > float(l[1]) - 0.01:
			continue
		if y < spring or _inside_arch(dx, y - spring, float(l[1]) - 0.01, float(l[2]) - 0.01):
			region = i
			lx = dx / float(l[1])
			break
	if region < 0:
		for i in circles.size():
			var ci: Array = circles[i]
			var d := Vector2(x - float(ci[0]), y - float(ci[1]))
			if d.length() < float(ci[2]) - 0.01:
				return _rosette(d / float(ci[2]), palette, tones, i)
		# The spandrels between: small pieces of the ground's blue.
		if y > spring and kind != "one":
			var q := Vector2(x * 9.0, y * 9.0)
			var lead := _lead(q, 0.08)
			return palette[0] * (0.6 + 0.4 * tones[int(absf(floorf(q.x) * 7.0 + floorf(q.y) * 13.0)) % 64]) * (1.0 - lead)
		return Color.BLACK
	# Inside a light: a border of ruby, a field of quarries or a vine on the ground.
	var edge := 1.0 - absf(lx)
	var border := edge * float(lights[region][1]) < 0.07
	var tall := ly
	if border:
		var seg := floorf((tall + 10.0) / 0.12)
		var lead := _lead(Vector2(0.0, (tall + 10.0) / 0.12), 0.1)
		var bead := tones[int(absf(seg)) % 64]
		return (palette[1] if int(seg) % 3 != 0 else palette[3]) * (0.7 + 0.5 * bead) * (1.0 - lead)
	if spec.begins_with("clere"):
		# Grisaille: pale quarries of greenish white with a painted lattice, dim at night.
		var q := Vector2((lx + 1.0) * 3.0, (tall + 10.0) / 0.16)
		var r := Vector2(q.x + q.y, q.y - q.x)
		var lead := _lead(r * 0.5, 0.07)
		var t := tones[int(absf(floorf(r.x * 0.5) * 3.0 + floorf(r.y * 0.5) * 11.0)) % 64]
		var c: Color = palette[2] * (0.7 + 0.5 * t)
		# Now and then a coloured roundel in the grisaille.
		var cy := fposmod(tall + 10.0, 1.1) - 0.55
		var d := Vector2(lx * float(lights[region][1]), cy).length()
		if d < 0.13:
			c = palette[1 + int(floorf((tall + 10.0) / 1.1)) % 3] * (0.8 + 0.3 * t)
		return c * (1.0 - lead)
	var lw := float(lights[region][1])
	if spec.ends_with("1"):
		# A diaper of quatrefoils: ruby ground, each foil blue round a gold heart, set in a lattice.
		var q := Vector2((lx + 1.0) * lw / 0.16, (tall + 10.0) / 0.16)
		var f := Vector2(fposmod(q.x, 1.0) - 0.5, fposmod(q.y, 1.0) - 0.5)
		var ang := atan2(f.y, f.x)
		var fr := f.length() / (0.3 + 0.12 * absf(cos(ang * 2.0)))
		var cell := tones[int(absf(floorf(q.x) * 5.0 + floorf(q.y) * 9.0)) % 64]
		var col: Color = palette[1] * (0.7 + 0.4 * cell)
		if fr < 1.0:
			col = (palette[3] * 1.1 if fr < 0.3 else palette[0] * (0.8 + 0.4 * cell))
		var lead2 := maxf(_lead(q, 0.05), 1.0 - smoothstep(0.0, 0.08, absf(fr - 1.0)))
		return col * (1.0 - lead2)
	if spec.ends_with("2"):
		# A vine up the light: a ruby stem winding on a blue ground, green leaves off it, a gold bud at each turn.
		var stem_x := 0.45 * sin((tall + 10.0) * 4.5) * lw * 0.6
		var px := lx * lw
		var col: Color = palette[0] * (0.75 + 0.35 * tones[int(absf(floorf((tall + 10.0) / 0.14) * 3.0
				+ floorf((lx + 1.0) * 2.0))) % 64])
		var lead2 := _lead(Vector2((lx + 1.0) * 2.0, (tall + 10.0) / 0.14), 0.06)
		if absf(px - stem_x) < 0.025:
			col = palette[1]
		else:
			var phase := fposmod((tall + 10.0) * 4.5 / TAU, 1.0)
			var side := 1.0 if fposmod((tall + 10.0) * 4.5 / TAU, 2.0) < 1.0 else -1.0
			var leaf := Vector2(px - stem_x - side * 0.09, fposmod(tall + 10.0, TAU / 4.5) - 0.35)
			if Vector2(leaf.x / 0.07, leaf.y / 0.11).length() < 1.0:
				col = palette[2] * 1.2
				lead2 = maxf(lead2 * 0.3, 0.0)
			elif absf(phase - 0.5) < 0.06 and absf(px - stem_x) < 0.07:
				col = palette[3]
		return col * (1.0 - lead2)
	# Coloured lights: a ground of blue with a vine of leaves and a ruby stem, in panels.
	var panel := fposmod(tall + 10.0, 0.62) - 0.31
	var pc := Vector2(lx * float(lights[region][1]), panel)
	var c: Color = palette[0]
	var lead := _lead(Vector2((lx + 1.0) * 2.5, (tall + 10.0) / 0.15), 0.06)
	var medallion := pc.length() < 0.2
	if medallion:
		# A four-petalled flower in a ring.
		var ang := atan2(pc.y, pc.x)
		var pr := pc.length() / 0.2
		var petal := absf(cos(ang * 2.0))
		if pr > 0.86:
			c = palette[3]
		elif pr < 0.25:
			c = palette[3] * 1.2
		elif pr < 0.3 + 0.55 * petal:
			c = palette[1]
		else:
			c = palette[2]
		lead = maxf(lead * 0.4, 1.0 - smoothstep(0.0, 0.05, absf(pr - 0.86)))
	var t := tones[int(absf(floorf((lx + 1.0) * 2.5) * 5.0 + floorf((tall + 10.0) / 0.15) * 3.0)) % 64]
	return c * (0.65 + 0.55 * t) * (1.0 - lead)


static func _inside_arch(dx: float, dy: float, a: float, h: float) -> bool:
	if dy < 0.0:
		return absf(dx) < a
	var rc := _pointed(a, h)
	var d := absf(dx) - rc.y
	return d * d + dy * dy < rc.x * rc.x


## The lead between pieces on a grid (cells a unit), its width a share of a cell: 1 on the lead, 0 off it.
static func _lead(q: Vector2, w: float) -> float:
	var f := Vector2(fposmod(q.x, 1.0), fposmod(q.y, 1.0))
	var e := minf(minf(f.x, 1.0 - f.x), minf(f.y, 1.0 - f.y))
	return 1.0 - smoothstep(w * 0.5, w, e)


## A rosette in a circle (d: from its middle, 1 at the rim): eight petals round a gold heart, a ring of ruby.
static func _rosette(d: Vector2, palette: Array, tones: Array[float], i: int) -> Color:
	var r := d.length()
	var ang := atan2(d.y, d.x)
	var petal := absf(cos(ang * 4.0))
	var c: Color
	if r > 0.82:
		c = palette[1]
	elif r < 0.22:
		c = palette[3] * 1.2
	elif r < 0.3 + 0.48 * petal:
		c = palette[2] if i % 2 == 0 else palette[1]
	else:
		c = palette[0]
	var lead := maxf(1.0 - smoothstep(0.0, 0.05, absf(r - 0.82)), 1.0 - smoothstep(0.0, 0.04, absf(r - 0.22)))
	return c * (0.8 + 0.3 * tones[int(absf(ang * 8.0 / TAU * 7.0 + r * 13.0)) % 64]) * (1.0 - lead)


## A window's colours (linear): [ground, border, field, jewel].
static func _palette(spec: String) -> Array:
	if spec.begins_with("clere"):
		return [Color(0.05, 0.08, 0.2), Color(0.45, 0.04, 0.05), Color(0.38, 0.42, 0.38), Color(0.6, 0.42, 0.08)]
	if spec.begins_with("lancet"):
		return [Color(0.45, 0.05, 0.04), Color(0.06, 0.1, 0.42), Color(0.08, 0.3, 0.12), Color(0.75, 0.5, 0.1)]
	return [Color(0.04, 0.08, 0.38), Color(0.5, 0.03, 0.05), Color(0.06, 0.28, 0.14), Color(0.72, 0.48, 0.08)]


static var _rose_tex: ImageTexture

## The rose's picture (UV over its disc, the tracery's layout as _rose draws it): a gold flower at the hub, twelve
## lights of blue with a jewel each and ruby borders, twelve roundels of green and gold in the outer band, ruby and
## blue between them; the lead between pieces, the stone's bars dark; brighter to the upper right (the Moon behind).
static func _rose_picture() -> ImageTexture:
	if _rose_tex != null:
		return _rose_tex
	_rose_tex = ImageTexture.create_from_image(ProcCache.image("nave_gothic.gd:_rose_picture", _draw_rose_picture))
	return _rose_tex


static func _draw_rose_picture() -> Image:
	const N := 320
	var img := Image.create_empty(N, N, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1268
	var tones: Array[float] = []
	for k in 97:
		tones.append(rng.randf())
	var scale := 1.0 / ROSE_GLASS
	for py in N:
		for px in N:
			var d := Vector2((px + 0.5) / N * 2.0 - 1.0, 1.0 - (py + 0.5) / N * 2.0) / scale
			img.set_pixel(px, py, _rose_colour(d, tones).linear_to_srgb())
	return img


static func _rose_colour(d: Vector2, tones: Array[float]) -> Color:
	var r := d.length()
	var ang := fposmod(atan2(d.y, d.x), TAU)
	var blue := Color(0.05, 0.1, 0.45)
	var ruby := Color(0.55, 0.03, 0.06)
	var green := Color(0.06, 0.32, 0.12)
	var gold := Color(0.78, 0.52, 0.1)
	var white := Color(0.55, 0.55, 0.5)
	var moon := 0.8 + 0.35 * clampf(d.dot(Vector2(0.6, 0.8)), -1.0, 1.0)
	var c := Color.BLACK
	var lead := 0.0
	if r > 1.0:
		return Color.BLACK
	if r < 0.2:
		# The hub: a gold flower of eight petals on ruby.
		var petal := absf(cos(ang * 4.0))
		var q := r / 0.2
		c = gold * 1.2 if q < 0.35 + 0.5 * petal else ruby
		if q < 0.25:
			c = white
		lead = 1.0 - smoothstep(0.0, 0.06, absf(q - (0.35 + 0.5 * petal)))
	elif r < 0.7:
		# The twelve lights: a ruby border, a blue ground, a jewel in each and a gold bud at its head.
		# Light k is centred at k twelfths of a turn, the spokes between.
		var sector := fposmod(ang + TAU / 24.0, TAU / 12.0) / (TAU / 12.0) - 0.5
		var across := sector * r * TAU / 12.0
		var k := int(floorf((ang + TAU / 24.0) / (TAU / 12.0)))
		var w := r * TAU / 24.0
		if absf(across) > w - 0.035:
			c = ruby
		else:
			c = blue if k % 2 == 0 else Color(0.08, 0.06, 0.4)
			var jewel := Vector2(across, r - 0.42).length()
			if jewel < 0.07:
				c = [gold, green, ruby, white][k % 4]
				lead = 1.0 - smoothstep(0.0, 0.012, absf(jewel - 0.07))
			var bud := Vector2(across, r - 0.6).length()
			if bud < 0.04:
				c = gold
		lead = maxf(lead, _lead(Vector2(across / 0.05, r / 0.07), 0.12))
	else:
		# The outer band: twelve roundels, a quatrefoil of green and gold in each, ruby and blue between.
		var k := int(roundf(ang / (TAU / 12.0))) % 12
		var centre := Vector2(cos(k * TAU / 12.0), sin(k * TAU / 12.0)) * 0.86
		var q := (d - centre) / 0.105
		var qr := q.length()
		if qr < 1.0:
			var qa := atan2(q.y, q.x)
			var foil := absf(cos(qa * 2.0))
			c = gold if qr < 0.3 else (green if qr < 0.45 + 0.45 * foil else white * 0.8)
			lead = 1.0 - smoothstep(0.0, 0.08, absf(qr - (0.45 + 0.45 * foil)))
		else:
			c = ruby if r > 0.93 else blue
			lead = _lead(Vector2(ang / (TAU / 48.0), r / 0.06), 0.12)
	var t := tones[int(absf(ang * 31.0 + r * 53.0)) % 97]
	return c * (0.7 + 0.45 * t) * (1.0 - lead) * moon


# --- Tones --------------------------------------------------------------------------------------------------------------

## The stone's tone at a point: a slow mottle (the stone's own beds), damp darker near the floor, soot higher up.
static func _stone_tone(p: Vector3, _n: Vector3) -> float:
	var t := 0.86 + 0.16 * _noise(p * 0.55) + 0.08 * _noise(p * 1.7 + Vector3(7, 3, 1))
	t *= lerpf(0.82, 1.0, smoothstep(0.0, 1.4, p.y))
	t *= lerpf(1.0, 0.82, smoothstep(9.0, 16.0, p.y))
	return t


static func _web_tone(p: Vector3, _n: Vector3) -> float:
	return (0.88 + 0.16 * _noise(p * 0.4 + Vector3(3, 0, 5))) * lerpf(1.0, 0.85, smoothstep(14.0, 16.5, p.y))


static var _fnl: FastNoiseLite

## Smooth noise in 3D, about 0..1, a feature a unit (the engine's: quick for every vertex of the church).
static func _noise(p: Vector3) -> float:
	if _fnl == null:
		_fnl = FastNoiseLite.new()
		_fnl.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
		_fnl.fractal_type = FastNoiseLite.FRACTAL_NONE
		_fnl.frequency = 1.0
		_fnl.seed = 1268
	return clampf(_fnl.get_noise_3dv(p) * 0.6 + 0.5, 0.0, 1.0)


static func _hash3(x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
