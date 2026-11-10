extends RefCounted

## The shapes of the passing system's scenery (docs/environments/passing.md): what stands along the way a journey
## goes. Each is drawn here in code, about its own foot, into a ShapeMesh; nothing comes from a file. Generic things
## only: a willow, a hedge, a far ridge, a lamp, a bridge. No people, no marks, nothing that is one real place.
##
## A band's shape is one of BANDS: many of it stand along a loop that comes round again. A landmark's is one of
## LANDMARKS: it stands once, at one place on the route.
##
##   Shapes.draw(shape, m, rng, size, colour, info)
##       m: the ShapeMesh, its item begun (ShapeMesh.begin_item()); the shape adds the item's parts about its foot
##       rng: the item's own random numbers (seeded by the system: the same item every time)
##       size: times the shape's natural size
##       colour: its main colour (COLOURS has each shape's own, used when a document gives none)
##       info: {along: the foot's place along the loop (metres), length: the loop's length, side: -1 when it stands
##              to the left of the way and 1 to the right, distance: how far across the way its foot is}
## Static; preload to use.

const ShapeMesh := preload("res://scripts/env/systems/passing/shape_mesh.gd")

const BANDS: Array[String] = ["reeds", "willow", "tree", "poplar", "hedge", "fence", "ridge", "lights", "cottage",
		"post"]
const LANDMARKS: Array[String] = ["lamp", "bridge", "boat", "wharf", "tower", "steamer"]
## Shapes that stand end to end in a row, each this long along the way (metres): such a band's count is its loop's
## length over this, and its items stand at even steps, all at the band's `near`.
const SEGMENT := {"hedge": 6.0, "fence": 2.4, "ridge": 12.0}
## Each shape's own main colour.
const COLOURS := {
	"reeds": "#3a4127", "willow": "#2f3a22", "tree": "#1f2a1b", "poplar": "#1b2618", "hedge": "#1c2617",
	"fence": "#4a4337", "ridge": "#10141c", "lights": "#ffc98a", "cottage": "#26221d", "post": "#2e2a24",
	"lamp": "#1b1b1d", "bridge": "#4a3329", "boat": "#17301f", "wharf": "#3a3632", "tower": "#15171c",
	"steamer": "#cfc8b8",
}
## A far village's lights: this share warm, the rest cool.
const WARM := Color(1.0, 0.79, 0.54)
const COOL := Color(0.81, 0.89, 1.0)
## A scattered band's items are this much smaller and larger than the band's size (a row's pieces are all its size).
const VARY := Vector2(0.8, 1.25)
## How far each shape reaches from its foot towards the way, and how high: what comfort needs to know of a shape
## (nearest()). A band's `near` says where its feet stand, and that is not how near it comes: a tree whose foot is
## 9 m off has a crown that reaches to 3, and a moored boat's side is a metre nearer than its middle. Three lengths,
## each as [metres whatever the size, metres times the size]:
##   stem   how far its solid part stands out from its foot at any height (a trunk, a wall, half a hedge)
##   wide   how far its widest part reaches (a crown, a willow's shoots, a lamp's arm, the eaves)
##   over   the height over its foot under which that widest part never comes (0: it reaches at the ground)
## Worked out from the drawing functions below at the largest each draws; change a shape and change its line here.
const REACH := {
	"reeds": {"stem": [0.25, 0.7], "wide": [0.25, 0.7], "over": [0.0, 0.0]},
	"willow": {"stem": [0.0, 0.8], "wide": [0.0, 3.75], "over": [0.0, 1.8]},
	"tree": {"stem": [0.0, 0.42], "wide": [0.0, 6.0], "over": [0.0, 3.2]},
	"poplar": {"stem": [0.0, 0.24], "wide": [0.0, 1.7], "over": [0.0, 1.4]},
	"hedge": {"stem": [0.68, 0.0], "wide": [0.68, 0.0], "over": [0.0, 0.0]},
	"fence": {"stem": [0.05, 0.0], "wide": [0.05, 0.0], "over": [0.0, 0.0]},
	"cottage": {"stem": [0.0, 2.25], "wide": [0.0, 2.4], "over": [0.0, 2.6]},
	"post": {"stem": [0.07, 0.0], "wide": [0.07, 0.0], "over": [0.0, 0.0]},
	"lamp": {"stem": [0.06, 0.0], "wide": [0.61, 0.0], "over": [0.0, 2.85]},
	"boat": {"stem": [0.0, 1.0], "wide": [0.0, 1.0], "over": [0.0, 0.0]},
	"tower": {"stem": [0.0, 3.5], "wide": [0.0, 3.5], "over": [0.0, 0.0]},
	"steamer": {"stem": [0.0, 4.5], "wide": [0.0, 4.5], "over": [0.0, 0.0]},
}


## The nearest any part of a shape comes to the line the viewer's eyes go along (metres): the least of its stem's
## distance and its widest part's, that one measured up to where it hangs. A bridge goes over the way: its nearest is
## its arch.
## distance: its foot from the way's line; foot: its foot's height; eye: the eyes' height (both in the room's frame)
static func nearest(shape: String, size: float, distance: float, foot: float, eye: float) -> float:
	if shape == "bridge":
		# Its piers stand at its distance; the arch springs 1.4 over its foot and rises 2.6 more over the way.
		var best := distance
		for k in 9:
			var t := PI * k / 8.0
			best = minf(best, Vector2(distance * cos(t), foot + (1.4 + 2.6 * sin(t)) * size - eye).length())
		return best
	if not REACH.has(shape):
		return distance
	var r: Dictionary = REACH[shape]
	var stem := distance - (float(r["stem"][0]) + float(r["stem"][1]) * size)
	var wide := maxf(distance - (float(r["wide"][0]) + float(r["wide"][1]) * size), 0.0)
	var over := maxf(foot + (float(r["over"][0]) + float(r["over"][1]) * size) - eye, 0.0)
	return maxf(minf(stem, Vector2(wide, over).length()), 0.0)


## The ground a landmark stands on, which no band's item may stand on too (a hedge through a wharf's shed, reeds
## through a moored boat, a willow on a bridge's road): Vector3(half its length along the way, its nearest and its
## furthest edge across the way, signed as the way's frame is: left negative). ZERO: none. The passing shaders leave
## out every band item whose foot is inside it; the margins past the shape itself are for what reaches (REACH).
## side: -1 left, 1 right; distance: its foot from the way's line
static func clearing(shape: String, size: float, side: float, distance: float) -> Vector3:
	match shape:
		"bridge":
			# Both sides of the way: its piers, its abutments (1.2 m) and what would reach over its parapet.
			return Vector3(4.25, -(distance + 9.0), distance + 9.0)
		"wharf":
			# Its deck is 20 m long and 6 m deep from its wall; reeds do not stand before a quay wall.
			return _clearing(11.5, side, distance - 2.0, distance + 11.0)
		"boat":
			return _clearing(8.5 * size, side, distance - 1.0 * size - 0.5, distance + 1.0 * size + 0.5)
		"tower":
			return _clearing(20.0 * size, side, distance - 8.0 * size, distance + 8.0 * size)
		"steamer":
			return _clearing(28.0 * size, side, distance - 4.5 * size - 1.0, distance + 4.5 * size + 1.0)
	return Vector3.ZERO


static func _clearing(half: float, side: float, a: float, b: float) -> Vector3:
	return Vector3(half, minf(side * a, side * b), maxf(side * a, side * b))


static func draw(shape: String, m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color,
		info: Dictionary) -> void:
	match shape:
		"post":
			_post(m, size, colour)
		"ridge":
			_ridge(m, size, colour, info)
		"lights":
			_lights(m, rng, size, colour)
		"reeds":
			_reeds(m, rng, size, colour)
		"willow":
			_willow(m, rng, size, colour)
		"tree":
			_tree(m, rng, size, colour)
		"poplar":
			_poplar(m, rng, size, colour)
		"hedge":
			_hedge(m, size, colour, info)
		"fence":
			_fence(m, size, colour)
		"cottage":
			_cottage(m, rng, size, colour, info)
		"lamp":
			_lamp(m, size, colour, info)
		"bridge":
			_bridge(m, size, colour, info)
		"boat":
			_boat(m, rng, size, colour, info)
		"wharf":
			_wharf(m, size, colour, info)
		"tower":
			_tower(m, size, colour)
		"steamer":
			_steamer(m, rng, size, colour, info)


## A colour with its r, g and b multiplied by k.
static func _mul(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)


## The horizontal unit vector at an angle a (radians) from x towards z.
static func _dir(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, sin(a))


## The vertical turned `degrees` towards the horizontal direction `towards`.
static func _lean(towards: Vector3, degrees: float) -> Vector3:
	var t := deg_to_rad(degrees)
	return Vector3.UP * cos(t) + towards * sin(t)


## A plain post: 0.14 m square and 1.2 m tall.
static func _post(m: ShapeMesh, size: float, colour: Color) -> void:
	m.material(ShapeMesh.M_PLAIN)
	m.box(Vector3(0.0, 0.6 * size, 0.0), Vector3(0.14, 1.2 * size, 0.14), colour)


## The height of a ridge's skyline at a place along its loop: three slow waves that fit the loop a whole number of
## times, so the skyline joins itself where the loop comes round. Metres, before `size`.
static func ridge_height(along: float, length: float) -> float:
	var t := TAU * along / maxf(length, 1.0)
	return 10.0 + 8.0 * sin(t + 0.7) + 5.0 * sin(3.0 * t + 2.1) + 2.5 * sin(7.0 * t + 4.4)


## One 12 m piece of a far ridge: a flat face from 2 m under its foot up to the skyline, which slopes from the
## height at its near end to the height at its far end. It faces the way.
static func _ridge(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var seg: float = SEGMENT["ridge"]
	var along := float(info.get("along", 0.0))
	var length := float(info.get("length", 240.0))
	var h0 := ridge_height(along, length) * size
	var h1 := ridge_height(along + seg, length) * size
	m.material(ShapeMesh.M_PLAIN)
	# A little over its own length, so no line of sky shows between two pieces.
	m.quad(Vector3(0.0, -2.0, -0.05), Vector3(0.0, -2.0, seg + 0.05), Vector3(0.0, h1, seg + 0.05),
			Vector3(0.0, h0, -0.05), colour)


## A far light: one point 1.5 to 6 m up, four in five warm and the rest cool, of uneven brightness.
static func _lights(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var warm := rng.randf() < 0.8
	var c := colour if warm else COOL
	# 0.25 m: a lit window and its glow on the wall round it. (At 0.08 a village across the fields was single
	# pixels, there and not seen: 2026-11-09.)
	m.light(Vector3(0.0, rng.randf_range(1.5, 6.0) * size, 0.0), c, rng.randf_range(0.4, 1.0), 0.25 * size)


## A clump of seven to twelve reeds, each a thin blade that leans and bends a little more near its tip; every third
## has a dark seed head.
static func _reeds(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var n := rng.randi_range(7, 12)
	for i in n:
		var foot := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
		var h := size * rng.randf_range(1.4, 2.3)
		var a := rng.randf_range(0.0, TAU)
		var lean := rng.randf_range(4.0, 14.0)
		var up1 := _lean(_dir(a), lean)
		var up2 := _lean(_dir(a), lean + 8.0)
		var p0 := foot
		var p1 := p0 + up1 * h * 0.55
		var p2 := p1 + up2 * h * 0.45
		var across := _dir(a + PI / 2.0)
		m.material(ShapeMesh.M_STEM, rng.randf())
		# A blade's width and its seed head grow with `size` as its height does: a bigger clump is the same plant
		# seen larger, not a taller and thinner one. (A blade of 8 mm at its tip is two pixels at 4 m on the
		# headset; a clump made taller at the same width would shimmer as it goes by.)
		m.ribbon(PackedVector3Array([p0, p1, p2]), PackedFloat32Array([0.035 * size, 0.025 * size, 0.008 * size]),
				across, _mul(colour, 0.75), colour.lerp(Color("#8a8456"), 0.7))
		if i % 3 == 0:
			m.material(ShapeMesh.M_PLAIN)
			var c := p2 - up2 * 0.09 * size
			var w := across * 0.015 * size
			var l := up2 * 0.07 * size
			m.quad(c - w - l, c + w - l, c + w + l, c - w + l, Color("#3a2a1c"))


## A pollard willow: a short thick trunk, a knobbed head, and twenty-six to thirty-four long shoots that rise from
## it, arch over and hang. They must hang: the first drawing's shoots stopped level, and from a boat's window at dusk
## the tree was a palm (2026-11-09, the Narrowboat's first render). Each now turns 35 degrees a piece through five
## pieces, from steeply up to steeply down, so the head is a fountain and its outline a dome with a ragged hem.
## REACH's line for it is worked out from these numbers.
static func _willow(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var lean_x := rng.randf_range(-0.2, 0.2)
	var lean_z := rng.randf_range(-0.2, 0.2)
	var top := Vector3(lean_x, 2.4, lean_z) * size
	var bark := Color("#3b352b")
	m.material(ShapeMesh.M_BARK)
	m.tube(Vector3.ZERO, top, 0.32 * size, 0.26 * size, 7, bark, _mul(bark, 1.1))
	m.ball(top + Vector3(0.0, 0.25 * size, 0.0), 0.5 * size, 3, 7, bark, 0.7, 0.15, rng)
	var n := rng.randi_range(26, 34)
	for i in n:
		var a := TAU * (i + rng.randf()) / n
		var pitch := rng.randf_range(50.0, 80.0)
		var length := size * rng.randf_range(3.0, 4.4)
		var piece := length / 5.0
		var p := top + Vector3(0.0, 0.45 * size, 0.0) + _dir(a) * 0.35 * size
		var points := PackedVector3Array([p])
		for _k in 5:
			var t := deg_to_rad(pitch)
			p += (_dir(a) * cos(t) + Vector3.UP * sin(t)) * piece
			points.append(p)
			pitch -= 35.0
		var widths := PackedFloat32Array()
		for w: float in [0.10, 0.2, 0.24, 0.2, 0.12, 0.03]:
			widths.append(w * size)
		m.material(ShapeMesh.M_LEAF, rng.randf())
		m.ribbon(points, widths, _dir(a + PI / 2.0), _mul(colour, 0.8), colour.lerp(Color("#55623a"), 0.6))


## A broadleaf tree, 9 to 14 m: a trunk to under half its height and a crown of five to seven balls about a top one.
## Its height is the top ball's top, exactly: no other ball stands over it, so a document that asks for a tree gets
## one of the height this says (a band of them makes an even wood, and a far tower still shows over it).
static func _tree(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var h := size * rng.randf_range(9.0, 14.0)
	var bark := Color("#2b2620")
	m.material(ShapeMesh.M_BARK)
	m.tube(Vector3.ZERO, Vector3(0.0, 0.38 * h, 0.0), 0.03 * h, 0.02 * h, 6, bark, bark)
	var k := rng.randi_range(5, 7)
	for i in k:
		var b := TAU * i / k + rng.randf_range(0.0, 0.5)
		var ri := rng.randf_range(0.5, 1.0)
		var lift := rng.randf_range(0.0, 1.0)
		var radius := h * rng.randf_range(0.16, 0.24)
		var tint := rng.randf_range(0.85, 1.15)
		# No higher than the tree: a ball's top is its centre and 0.85 of its radius (ShapeMesh.ball()'s squash).
		var y := minf(0.38 * h + h * (0.18 + 0.44 * lift), h - radius * 0.85)
		var centre := Vector3(cos(b) * 0.16 * h * ri, y, sin(b) * 0.16 * h * ri)
		m.material(ShapeMesh.M_LEAF, rng.randf())
		m.ball(centre, radius, 4, 6, _mul(colour, tint), 0.85, 0.12, rng)
	m.material(ShapeMesh.M_LEAF, rng.randf())
	m.ball(Vector3(0.0, h - 0.18 * h * 0.85, 0.0), 0.18 * h, 4, 6, colour, 0.85, 0.12, rng)


## A poplar, 14 to 20 m: a short trunk and a tall narrow crown, widest a quarter of the way up, paler towards its top.
static func _poplar(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var h := size * rng.randf_range(14.0, 20.0)
	var bark := Color("#2b2620")
	m.material(ShapeMesh.M_BARK)
	m.tube(Vector3.ZERO, Vector3(0.0, 0.12 * h, 0.0), 0.012 * h, 0.012 * h, 6, bark, bark)
	var heights: Array[float] = [0.10, 0.25, 0.5, 0.8, 1.0]
	var radii: Array[float] = [0.03, 0.085, 0.07, 0.035, 0.001]
	m.material(ShapeMesh.M_LEAF, rng.randf())
	for i in 4:
		m.tube(Vector3(0.0, heights[i] * h, 0.0), Vector3(0.0, heights[i + 1] * h, 0.0), radii[i] * h,
				radii[i + 1] * h, 8, _mul(colour, lerpf(0.85, 1.1, heights[i])),
				_mul(colour, lerpf(0.85, 1.1, heights[i + 1])))


## The height of a hedge's top at a place along its loop (metres, before size): two slow waves, so it is uneven but
## two pieces meet at the same height.
static func hedge_height(along: float) -> float:
	return 1.8 + 0.2 * sin(along * 0.9) + 0.12 * sin(along * 2.3 + 1.0)


## Half a hedge's width at a place along its loop (metres; not times size).
static func hedge_half_width(along: float) -> float:
	return 0.6 + 0.08 * sin(along * 1.7 + 2.0)


## One 6 m piece of a hedge: two sides, two chamfers and a top through five sections whose height and width follow
## the place along the loop.
static func _hedge(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var z0 := float(info["along"])
	var zs: Array[float] = [0.0, 1.5, 3.0, 4.5, 6.0]
	var sides := _mul(colour, 0.85)
	m.material(ShapeMesh.M_LEAF, fposmod(z0 * 0.37, 1.0))
	for i in 4:
		var za := zs[i]
		var zb := zs[i + 1]
		var ha := hedge_height(z0 + za) * size
		var hb := hedge_height(z0 + zb) * size
		var wa := hedge_half_width(z0 + za)
		var wb := hedge_half_width(z0 + zb)
		m.quad(Vector3(-wa, 0.0, za), Vector3(-wb, 0.0, zb), Vector3(-wb, hb - 0.25, zb), Vector3(-wa, ha - 0.25, za),
				sides)
		m.quad(Vector3(wa, 0.0, za), Vector3(wb, 0.0, zb), Vector3(wb, hb - 0.25, zb), Vector3(wa, ha - 0.25, za),
				sides)
		m.quad(Vector3(-wa, ha - 0.25, za), Vector3(-wb, hb - 0.25, zb), Vector3(-(wb - 0.25), hb, zb),
				Vector3(-(wa - 0.25), ha, za), colour)
		m.quad(Vector3(wa, ha - 0.25, za), Vector3(wb, hb - 0.25, zb), Vector3(wb - 0.25, hb, zb),
				Vector3(wa - 0.25, ha, za), colour)
		m.quad(Vector3(-(wa - 0.25), ha, za), Vector3(-(wb - 0.25), hb, zb), Vector3(wb - 0.25, hb, zb),
				Vector3(wa - 0.25, ha, za), _mul(colour, 1.15))


## One 2.4 m piece of a post-and-rail fence: a post at its foot and two rails to the next.
static func _fence(m: ShapeMesh, size: float, colour: Color) -> void:
	m.material(ShapeMesh.M_PLAIN)
	m.box(Vector3(0.0, 0.55 * size, 0.0), Vector3(0.1, 1.1 * size, 0.1), colour)
	m.box(Vector3(0.0, 0.45 * size, 1.2), Vector3(0.03, 0.08, 2.4), colour)
	m.box(Vector3(0.0, 0.85 * size, 1.2), Vector3(0.03, 0.08, 2.4), colour)


## A small house, its long side along the way: walls, a dark roof, a chimney, and on the wall that faces the way a
## door and two windows, each lit or dark.
static func _cottage(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	m.material(ShapeMesh.M_PLAIN)
	m.box(Vector3(0.0, 1.3, 0.0) * s, Vector3(4.5, 2.6, 6.0) * s, colour)
	var roof := Color("#1b1a1c")
	for x: float in [-2.4, 2.4]:
		m.quad(Vector3(x, 2.6, -3.15) * s, Vector3(x, 2.6, 3.15) * s, Vector3(0.0, 4.6, 3.15) * s,
				Vector3(0.0, 4.6, -3.15) * s, roof)
	for z: float in [-3.0, 3.0]:
		m.tri(Vector3(-2.25, 2.6, z) * s, Vector3(2.25, 2.6, z) * s, Vector3(0.0, 4.6, z) * s, colour)
	m.box(Vector3(0.0, 4.9, 2.2) * s, Vector3(0.5, 1.0, 0.5) * s, _mul(colour, 0.8))
	var x := -side * (2.25 + 0.01) * s
	m.quad(Vector3(x, 0.0, -0.45 * s), Vector3(x, 0.0, 0.45 * s), Vector3(x, 1.9 * s, 0.45 * s),
			Vector3(x, 1.9 * s, -0.45 * s), _mul(colour, 0.6))
	for z: float in [-1.5, 1.5]:
		var lit := rng.randf() < 0.6
		var bright := rng.randf_range(0.7, 1.0)
		var c := Color("#0a0a0c")
		if lit:
			m.material(ShapeMesh.M_WINDOW)
			c = _mul(WARM, bright)
		else:
			m.material(ShapeMesh.M_PLAIN)
		m.quad(Vector3(x, 1.05 * s, (z - 0.35) * s), Vector3(x, 1.05 * s, (z + 0.35) * s),
				Vector3(x, 1.95 * s, (z + 0.35) * s), Vector3(x, 1.95 * s, (z - 0.35) * s), c)


## A lamp on a post, its arm reaching towards the way, with a lantern's glow and flame. `at` stands it elsewhere
## than the item's foot (the wharf has one).
static func _lamp(m: ShapeMesh, size: float, colour: Color, info: Dictionary, at := Vector3.ZERO) -> void:
	var side := float(info["side"])
	m.material(ShapeMesh.M_PLAIN)
	m.tube(at, at + Vector3(0.0, 3.2 * size, 0.0), 0.06, 0.045, 6, colour, colour)
	m.box(at + Vector3(-side * 0.25, 3.15 * size, 0.0), Vector3(0.5, 0.05, 0.05), colour)
	m.box(at + Vector3(-side * 0.5, 3.0 * size, 0.0), Vector3(0.22, 0.3, 0.22), colour)
	var p := at + Vector3(-side * 0.5, 2.95 * size, 0.0)
	m.light(p, WARM, 1.0, 0.6)
	m.light(p, WARM, 1.0, 0.1)


## A brick arch over the way: a half-round arch from a pier on each side, the faces up to the parapet, abutments
## outside the piers and a flat top. Its span is twice the item's distance; only its heights are times size.
static func _bridge(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var d := float(info["distance"])
	var xc := -side * d
	# Its depth along the way is the road's width over it (4.5 m), which a taller arch does not make wider: not
	# times size, as the span is not (that is the water's width, the item's distance twice).
	var hz := 2.25
	var s := 1.4 * size
	var r := 2.6 * size
	var top := 5.2 * size
	var ab := 1.2
	var line: Array[Vector2] = []
	for k in 9:
		var t := PI * k / 8.0
		line.append(Vector2(xc + d * cos(t), s + r * sin(t)))
	m.material(ShapeMesh.M_PLAIN)
	for k in 8:
		var p := line[k]
		var q := line[k + 1]
		m.quad(Vector3(p.x, p.y, -hz), Vector3(q.x, q.y, -hz), Vector3(q.x, q.y, hz), Vector3(p.x, p.y, hz),
				_mul(colour, 0.7))
	for z: float in [-hz, hz]:
		for k in 8:
			var p := line[k]
			var q := line[k + 1]
			m.quad(Vector3(p.x, p.y, z), Vector3(q.x, q.y, z), Vector3(q.x, top, z), Vector3(p.x, top, z),
					_mul(colour, 0.92) if k % 2 == 1 else colour)
	for x: float in [xc + d, xc - d]:
		m.quad(Vector3(x, 0.0, -hz), Vector3(x, 0.0, hz), Vector3(x, s, hz), Vector3(x, s, -hz), _mul(colour, 0.7))
	for e: float in [1.0, -1.0]:
		var inner := xc + e * d
		var outer := inner + e * ab
		for z: float in [-hz, hz]:
			m.quad(Vector3(inner, 0.0, z), Vector3(outer, 0.0, z), Vector3(outer, top, z), Vector3(inner, top, z),
					colour)
		m.quad(Vector3(outer, 0.0, -hz), Vector3(outer, 0.0, hz), Vector3(outer, top, hz), Vector3(outer, top, -hz),
				colour)
	m.quad(Vector3(xc - d - ab, top, -hz), Vector3(xc + d + ab, top, -hz), Vector3(xc + d + ab, top, hz),
			Vector3(xc - d - ab, top, hz), _mul(colour, 0.8))


## A narrowboat tied up alongside, its length along the way: a dark hull with a pointed bow, a long cabin, a chimney,
## and three portholes on the side that faces the way, each lit or dark.
static func _boat(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var hull := Color("#101112")
	m.material(ShapeMesh.M_PLAIN)
	m.box(Vector3(0.0, 0.175, -1.25) * s, Vector3(2.0, 0.55, 12.5) * s, hull)
	for x: float in [-1.0, 1.0]:
		m.quad(Vector3(x, -0.1, 5.0) * s, Vector3(0.0, -0.1, 7.5) * s, Vector3(0.0, 0.45, 7.5) * s,
				Vector3(x, 0.45, 5.0) * s, hull)
	m.tri(Vector3(-1.0, 0.45, 5.0) * s, Vector3(1.0, 0.45, 5.0) * s, Vector3(0.0, 0.45, 7.5) * s, hull)
	m.box(Vector3(0.0, 0.95, -0.5) * s, Vector3(1.8, 1.0, 10.0) * s, colour)
	var flue := Color("#0c0c0d")
	m.tube(Vector3(0.4, 1.45, 3.5) * s, Vector3(0.4, 1.95, 3.5) * s, 0.07 * s, 0.07 * s, 6, flue, flue)
	var x := -side * 0.905 * s
	for z: float in [-3.0, 0.0, 3.0]:
		var lit := rng.randf() < 0.35
		var c := Color("#07080a")
		if lit:
			m.material(ShapeMesh.M_WINDOW)
			c = _mul(WARM, 0.9)
		else:
			m.material(ShapeMesh.M_PLAIN)
		m.quad(Vector3(x, 0.9 * s, (z - 0.15) * s), Vector3(x, 0.9 * s, (z + 0.15) * s),
				Vector3(x, 1.2 * s, (z + 0.15) * s), Vector3(x, 1.2 * s, (z - 0.15) * s), c)


## A quay with a shed: a wall facing the way and a flat top 6 m deep, three bollards, a brick shed with a door and a
## lit window towards the way, and a lamp near the edge. Only its heights are times size.
static func _wharf(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var deck := 0.6 * size
	m.material(ShapeMesh.M_PLAIN)
	m.quad(Vector3(0.0, -0.6 * size, -10.0), Vector3(0.0, -0.6 * size, 10.0), Vector3(0.0, deck, 10.0),
			Vector3(0.0, deck, -10.0), colour)
	m.quad(Vector3(0.0, deck, -10.0), Vector3(side * 6.0, deck, -10.0), Vector3(side * 6.0, deck, 10.0),
			Vector3(0.0, deck, 10.0), _mul(colour, 1.1))
	var c := Color("#1a1a1c")
	for z: float in [-6.0, 0.0, 6.0]:
		m.tube(Vector3(side * 0.4, deck, z), Vector3(side * 0.4, 1.1 * size, z), 0.12, 0.12, 6, c, c)
	var brick := Color("#3b2b24")
	var sx := side * 3.6
	m.box(Vector3(sx, (0.6 + 1.5) * size, -3.0), Vector3(4.0, 3.0 * size, 8.0), brick)
	var roof := Color("#1b1a1c")
	for x: float in [sx - 2.2, sx + 2.2]:
		m.quad(Vector3(x, 3.6 * size, -7.2), Vector3(x, 3.6 * size, 1.2), Vector3(sx, 4.8 * size, 1.2),
				Vector3(sx, 4.8 * size, -7.2), roof)
	for z: float in [-7.0, 1.0]:
		# A gable stands on the shed's walls (x = sx - 2 and sx + 2), not on the eaves, which hang 0.2 over them:
		# as the cottage's.
		m.tri(Vector3(sx - 2.0, 3.6 * size, z), Vector3(sx + 2.0, 3.6 * size, z), Vector3(sx, 4.8 * size, z), brick)
	var x := side * 1.59
	m.quad(Vector3(x, deck, -5.6), Vector3(x, deck, -3.4), Vector3(x, deck + 2.4 * size, -3.4),
			Vector3(x, deck + 2.4 * size, -5.6), Color("#1f2a22"))
	m.material(ShapeMesh.M_WINDOW)
	var wy := (0.6 + 1.7) * size
	m.quad(Vector3(x, wy - 0.4 * size, -1.4), Vector3(x, wy - 0.4 * size, -0.6), Vector3(x, wy + 0.4 * size, -0.6),
			Vector3(x, wy + 0.4 * size, -1.4), WARM)
	_lamp(m, size, Color(COLOURS["lamp"]), info, Vector3(side * 0.6, deck, 5.0))


## A church tower, far off: a square tower with four pinnacles and a lower nave behind it under a pitched roof.
static func _tower(m: ShapeMesh, size: float, colour: Color) -> void:
	var s := size
	m.material(ShapeMesh.M_PLAIN)
	m.box(Vector3(0.0, 9.0, 0.0) * s, Vector3(5.0, 18.0, 5.0) * s, colour)
	for x: float in [-2.2, 2.2]:
		for z: float in [-2.2, 2.2]:
			m.box(Vector3(x, 18.8, z) * s, Vector3(0.6, 1.6, 0.6) * s, colour)
	m.box(Vector3(0.0, 3.5, -9.5) * s, Vector3(7.0, 7.0, 14.0) * s, _mul(colour, 0.9))
	for x: float in [-3.5, 3.5]:
		m.quad(Vector3(x, 7.0, -16.5) * s, Vector3(x, 7.0, -2.5) * s, Vector3(0.0, 10.0, -2.5) * s,
				Vector3(0.0, 10.0, -16.5) * s, _mul(colour, 0.8))


## A sternwheel river steamer at anchor, its length along the way: two deck houses, a pilot house, twin stacks and
## a stern wheel, with lit windows and deck lamps on the side that faces the way.
static func _steamer(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	m.material(ShapeMesh.M_PLAIN)
	m.box(Vector3(0.0, 0.3, 0.0) * size, Vector3(9.0, 1.2, 44.0) * size, Color("#1a1c1e"))
	m.box(Vector3(0.0, 2.2, -2.0) * size, Vector3(7.6, 2.6, 32.0) * size, colour)
	m.box(Vector3(0.0, 3.575, -2.0) * size, Vector3(8.6, 0.15, 36.0) * size, _mul(colour, 0.8))
	m.box(Vector3(0.0, 4.8, -4.0) * size, Vector3(6.0, 2.3, 24.0) * size, colour)
	m.box(Vector3(0.0, 6.01, -4.0) * size, Vector3(7.0, 0.12, 27.0) * size, _mul(colour, 0.8))
	m.box(Vector3(0.0, 7.17, 4.0) * size, Vector3(3.0, 2.2, 3.4) * size, colour)
	m.box(Vector3(0.0, 8.33, 4.0) * size, Vector3(3.6, 0.12, 4.0) * size, _mul(colour, 0.8))
	var stack := Color("#0e0e10")
	for x: float in [-1.4, 1.4]:
		m.tube(Vector3(x, 6.07, 9.0) * size, Vector3(x, 13.0, 9.0) * size, 0.45 * size, 0.45 * size, 8,
				stack, stack)
		m.box(Vector3(x, 12.9, 9.0) * size, Vector3(1.2, 0.3, 1.2) * size, stack)
	m.ball(Vector3(0.0, 1.8, -24.8) * size, 2.6 * size, 4, 10, Color("#5a1a14"))
	var x1 := -side * 3.81 * size
	var x2 := -side * 3.01 * size
	for i in 10:
		var z := -16.0 + 3.1 * i
		var lit := rng.randf() < 0.7
		var bright := rng.randf_range(0.7, 1.0)
		var c := Color("#0a0a0c")
		if lit:
			m.material(ShapeMesh.M_WINDOW)
			c = _mul(WARM, bright)
		else:
			m.material(ShapeMesh.M_PLAIN)
		m.quad(Vector3(x1, 1.75 * size, (z - 0.45) * size), Vector3(x1, 1.75 * size, (z + 0.45) * size),
				Vector3(x1, 2.85 * size, (z + 0.45) * size), Vector3(x1, 2.85 * size, (z - 0.45) * size), c)
	for i in 7:
		var z := -13.0 + 3.0 * i
		var lit := rng.randf() < 0.5
		var bright := rng.randf_range(0.7, 1.0)
		var c := Color("#0a0a0c")
		if lit:
			m.material(ShapeMesh.M_WINDOW)
			c = _mul(WARM, bright)
		else:
			m.material(ShapeMesh.M_PLAIN)
		m.quad(Vector3(x2, 4.45 * size, (z - 0.4) * size), Vector3(x2, 4.45 * size, (z + 0.4) * size),
				Vector3(x2, 5.35 * size, (z + 0.4) * size), Vector3(x2, 5.35 * size, (z - 0.4) * size), c)
	for i in 5:
		m.light(Vector3(-side * 4.3, 3.4, -16.0 + 8.0 * i) * size, WARM, 0.8, 0.35 * size)
	m.light(Vector3(0.0, 9.2, 4.0) * size, COOL, 1.0, 0.3 * size)
