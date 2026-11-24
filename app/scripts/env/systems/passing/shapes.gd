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
		"post", "buoy", "telegraph", "pine", "birch", "mesa", "cactus", "cloud_bank",
		"kelp", "sea_rock", "highway_lamp", "gantry", "tether_ring", "dust_devil", "mars_rock"]
const LANDMARKS: Array[String] = ["lamp", "bridge", "boat", "wharf", "tower", "steamer", "pier", "lighthouse", "ship",
		"ferry_port", "freighter", "signal", "station", "water_tower", "airship_mast", "airport",
		"sunken_wreck", "hydro_vent", "services", "ocean_platform", "orbital_station", "lunar_base", "mars_base"]
## Shapes that stand end to end in a row, each this long along the way (metres): such a band's count is its loop's
## length over this, and its items stand at even steps, all at the band's `near`.
const SEGMENT := {"hedge": 6.0, "fence": 2.4, "ridge": 12.0}
## Each shape's own main colour.
const COLOURS := {
	"reeds": "#3a4127", "willow": "#2f3a22", "tree": "#1f2a1b", "poplar": "#1b2618", "hedge": "#1c2617",
	"fence": "#4a4337", "ridge": "#10141c", "lights": "#ffc98a", "cottage": "#26221d", "post": "#2e2a24",
	"lamp": "#1b1b1d", "bridge": "#4a3329", "boat": "#17301f", "wharf": "#3a3632", "tower": "#15171c",
	"steamer": "#cfc8b8", "buoy": "#5a1512", "pier": "#3e3c38", "lighthouse": "#d4d0c6", "ship": "#c8c2b4",
	"ferry_port": "#3a4048", "freighter": "#18202c",
	"telegraph": "#2b2119", "pine": "#15261c", "birch": "#cfd4dc", "mesa": "#6b3828", "cactus": "#25402b",
	"cloud_bank": "#5e6f8c", "signal": "#22262b", "station": "#3f3832", "water_tower": "#47372a",
	"airship_mast": "#767d86", "airport": "#4b525c",
	"kelp": "#27422a", "sea_rock": "#223238", "highway_lamp": "#32363c", "gantry": "#3b424a",
	"tether_ring": "#7a8490", "dust_devil": "#b86a42", "mars_rock": "#5c3122",
	"sunken_wreck": "#382c22", "hydro_vent": "#283034", "services": "#3e434a",
	"ocean_platform": "#444c54", "orbital_station": "#c6ccd4", "lunar_base": "#8c8a86", "mars_base": "#9a5c3c",
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
	"buoy": {"stem": [0.0, 0.45], "wide": [0.0, 0.45], "over": [0.0, 0.0]},
	"lighthouse": {"stem": [0.0, 3.2], "wide": [0.0, 3.6], "over": [0.0, 0.0]},
	"ship": {"stem": [0.0, 6.8], "wide": [0.0, 7.2], "over": [0.0, 0.0]},
	"freighter": {"stem": [0.0, 6.6], "wide": [0.0, 7.0], "over": [0.0, 0.0]},
	"telegraph": {"stem": [0.0, 0.16], "wide": [0.0, 1.1], "over": [0.0, 6.8]},
	"pine": {"stem": [0.0, 0.25], "wide": [0.0, 2.4], "over": [0.0, 1.4]},
	"birch": {"stem": [0.0, 0.16], "wide": [0.0, 1.8], "over": [0.0, 2.4]},
	"mesa": {"stem": [0.0, 10.0], "wide": [0.0, 14.0], "over": [0.0, 0.0]},
	"cactus": {"stem": [0.0, 0.28], "wide": [0.0, 1.25], "over": [0.0, 1.2]},
	"cloud_bank": {"stem": [0.0, 6.0], "wide": [0.0, 12.0], "over": [0.0, 0.0]},
	"signal": {"stem": [0.0, 0.45], "wide": [0.0, 1.8], "over": [0.0, 6.5]},
	"water_tower": {"stem": [0.0, 2.8], "wide": [0.0, 3.2], "over": [0.0, 5.0]},
	"airship_mast": {"stem": [0.0, 4.5], "wide": [0.0, 5.5], "over": [0.0, 0.0]},
	"kelp": {"stem": [0.0, 0.4], "wide": [0.0, 1.8], "over": [0.0, 0.8]},
	"sea_rock": {"stem": [0.0, 2.6], "wide": [0.0, 3.0], "over": [0.0, 0.0]},
	"highway_lamp": {"stem": [0.0, 0.25], "wide": [0.0, 2.7], "over": [0.0, 9.8]},
	"gantry": {"stem": [0.0, 0.4], "wide": [0.0, 4.5], "over": [0.0, 5.2]},
	"tether_ring": {"stem": [0.0, 1.5], "wide": [0.0, 2.5], "over": [0.0, 0.0]},
	"dust_devil": {"stem": [0.0, 1.5], "wide": [0.0, 5.0], "over": [0.0, 0.0]},
	"mars_rock": {"stem": [0.0, 2.5], "wide": [0.0, 2.8], "over": [0.0, 0.0]},
	"sunken_wreck": {"stem": [0.0, 5.0], "wide": [0.0, 5.5], "over": [0.0, 0.0]},
	"hydro_vent": {"stem": [0.0, 4.0], "wide": [0.0, 4.5], "over": [0.0, 0.0]},
	"ocean_platform": {"stem": [0.0, 12.0], "wide": [0.0, 14.0], "over": [0.0, 0.0]},
	"orbital_station": {"stem": [0.0, 10.0], "wide": [0.0, 14.0], "over": [0.0, 0.0]},
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
		"pier":
			return _clearing(34.0, side, distance - 6.0, distance + 22.0)
		"lighthouse":
			return _clearing(20.0 * size, side, distance - 5.0 * size, distance + 14.0 * size)
		"ship":
			return _clearing(50.0 * size, side, distance - 8.0 * size, distance + 8.0 * size)
		"ferry_port":
			return _clearing(38.0, side, distance - 6.0, distance + 24.0)
		"freighter":
			return _clearing(46.0 * size, side, distance - 8.0 * size, distance + 8.0 * size)
		"signal":
			return _clearing(4.0 * size, side, distance - 2.0 * size, distance + 2.5 * size)
		"station":
			return _clearing(22.0, side, distance - 2.0, distance + 14.0)
		"water_tower":
			return _clearing(9.0 * size, side, distance - 4.0 * size, distance + 10.0 * size)
		"airship_mast":
			return _clearing(14.0 * size, side, distance - 6.0 * size, distance + 14.0 * size)
		"airport":
			return _clearing(38.0, side, distance - 6.0, distance + 24.0)
		"sunken_wreck":
			return _clearing(18.0 * size, side, distance - 6.0 * size, distance + 8.0 * size)
		"hydro_vent":
			return _clearing(10.0 * size, side, distance - 5.0 * size, distance + 7.0 * size)
		"services":
			return _clearing(32.0, side, distance - 4.0, distance + 24.0)
		"ocean_platform":
			return _clearing(24.0 * size, side, distance - 14.0 * size, distance + 16.0 * size)
		"orbital_station":
			return _clearing(24.0 * size, side, distance - 14.0 * size, distance + 16.0 * size)
		"lunar_base":
			return _clearing(32.0, side, distance - 6.0, distance + 24.0)
		"mars_base":
			return _clearing(32.0, side, distance - 6.0, distance + 24.0)
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
		"buoy":
			_buoy(m, rng, size)
		"pier":
			_pier(m, size, colour, info)
		"lighthouse":
			_lighthouse(m, size, colour, info)
		"ship":
			_ship(m, rng, size, colour, info)
		"ferry_port":
			_ferry_port(m, size, colour, info)
		"freighter":
			_freighter(m, rng, size, colour, info)
		"telegraph":
			_telegraph(m, size, colour)
		"pine":
			_pine(m, rng, size, colour)
		"birch":
			_birch(m, rng, size, colour)
		"mesa":
			_mesa(m, rng, size, colour)
		"cactus":
			_cactus(m, rng, size, colour)
		"cloud_bank":
			_cloud_bank(m, rng, size, colour)
		"signal":
			_signal(m, size, colour, info)
		"station":
			_station(m, rng, size, colour, info)
		"water_tower":
			_water_tower(m, size, colour, info)
		"airship_mast":
			_airship_mast(m, size, colour, info)
		"airport":
			_airport(m, size, colour, info)
		"kelp":
			_kelp(m, rng, size, colour)
		"sea_rock":
			_sea_rock(m, rng, size, colour)
		"highway_lamp":
			_highway_lamp(m, size, colour, info)
		"gantry":
			_gantry(m, size, colour, info)
		"tether_ring":
			_tether_ring(m, size, colour, info)
		"dust_devil":
			_dust_devil(m, rng, size, colour)
		"mars_rock":
			_mars_rock(m, rng, size, colour)
		"sunken_wreck":
			_sunken_wreck(m, rng, size, colour, info)
		"hydro_vent":
			_hydro_vent(m, size, colour, info)
		"services":
			_services(m, size, colour, info)
		"ocean_platform":
			_ocean_platform(m, size, colour, info)
		"orbital_station":
			_orbital_station(m, size, colour, info)
		"lunar_base":
			_lunar_base(m, size, colour, info)
		"mars_base":
			_mars_base(m, size, colour, info)


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
	_wheel(m, Vector3(0.0, 1.8, -24.8) * size, 2.6 * size, 3.3 * size, Color("#5a1a14"))
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


## A paddle wheel on an axle across the way, seen from the side as two rims, spokes and twelve paddles.
static func _wheel(m: ShapeMesh, centre: Vector3, radius: float, half_width: float, colour: Color) -> void:
	m.material(ShapeMesh.M_PLAIN)
	var across := Vector3.RIGHT * half_width
	for k in 12:
		var a := TAU * k / 12.0
		var dir := Vector3(0.0, sin(a), cos(a))
		m.quad(centre - across + dir * radius * 0.8, centre + across + dir * radius * 0.8,
				centre + across + dir * radius, centre - across + dir * radius, colour)
	var rim := _mul(colour, 0.8)
	for x: float in [-half_width, half_width]:
		var o := centre + Vector3.RIGHT * x
		for k in 12:
			var a0 := TAU * k / 12.0
			var a1 := TAU * (k + 1) / 12.0
			var d0 := Vector3(0.0, sin(a0), cos(a0))
			var d1 := Vector3(0.0, sin(a1), cos(a1))
			m.quad(o + d0 * radius * 0.88, o + d1 * radius * 0.88, o + d1 * radius, o + d0 * radius, rim)
	for x: float in [-half_width, half_width]:
		var o := centre + Vector3.RIGHT * x
		for k in 6:
			var a := PI * k / 6.0
			var dir := Vector3(0.0, sin(a), cos(a))
			var perp := Vector3(0.0, cos(a), -sin(a))
			var t := radius * 0.03
			m.quad(o - dir * radius - perp * t, o + dir * radius - perp * t, o + dir * radius + perp * t,
					o - dir * radius + perp * t, rim)


## A channel buoy on the water line: a can, a staff and one red or green light. Its colour marks the channel's side,
## so the band's colour is not used.
static func _buoy(m: ShapeMesh, rng: RandomNumberGenerator, size: float) -> void:
	var red := rng.randf() < 0.5
	var colour := Color("#5a1512") if red else Color("#123a22")
	m.material(ShapeMesh.M_PLAIN)
	m.tube(Vector3(0.0, -0.3, 0.0) * size, Vector3(0.0, 1.2, 0.0) * size, 0.45 * size, 0.3 * size, 6,
			colour, colour)
	var staff := Color("#0e0e10")
	m.tube(Vector3(0.0, 1.2, 0.0) * size, Vector3(0.0, 2.0, 0.0) * size, 0.04 * size, 0.04 * size, 6,
			staff, staff)
	var c := Color(1.0, 0.25, 0.2) if red else Color(0.3, 1.0, 0.5)
	# A navigation light is the brightest small thing on dark water, and is seen from 30 or 40 m: at a deck lamp's
	# size (0.22) it was hardly a dot in the first pictures.
	m.light(Vector3(0.0, 2.0, 0.0) * size, c, 1.0, 0.4 * size)


## An ocean terminal pier: a long stone quay facing the ship, five heavy bollards, a long transit shed with warm lit
## upper windows and boarding bays, four harbour lamp standards and a steel cargo gantry at one end. Heights scale
## with `size`; its length along the way is 60 m.
static func _pier(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var deck := 3.2 * s
	m.material(ShapeMesh.M_PLAIN)
	# Quay face, deck apron and end caps.
	m.quad(Vector3(0.0, -1.5 * s, -30.0), Vector3(0.0, -1.5 * s, 30.0), Vector3(0.0, deck, 30.0),
			Vector3(0.0, deck, -30.0), colour)
	m.quad(Vector3(0.0, deck, -30.0), Vector3(side * 14.0, deck, -30.0), Vector3(side * 14.0, deck, 30.0),
			Vector3(0.0, deck, 30.0), _mul(colour, 1.12))
	for z: float in [-30.0, 30.0]:
		m.quad(Vector3(0.0, -1.5 * s, z), Vector3(side * 14.0, -1.5 * s, z), Vector3(side * 14.0, deck, z),
				Vector3(0.0, deck, z), _mul(colour, 0.85))
	# Heavy iron bollards along the quay edge.
	var iron := Color("#16171a")
	for z: float in [-24.0, -12.0, 0.0, 12.0, 24.0]:
		m.box(Vector3(side * 0.7, deck + 0.45 * s, z), Vector3(0.45, 0.9 * s, 0.45), iron)
	# Transit shed with pitched clerestory roof.
	var shed_x := side * 9.0
	var shed_wall := Color("#4b463e")
	var roof := Color("#232428")
	m.box(Vector3(shed_x, deck + 3.4 * s, -2.0), Vector3(8.0, 6.8 * s, 44.0), shed_wall)
	for dx: float in [-4.3, 4.3]:
		m.quad(Vector3(shed_x + dx, deck + 6.8 * s, -24.5), Vector3(shed_x + dx, deck + 6.8 * s, 20.5),
				Vector3(shed_x, deck + 9.0 * s, 20.5), Vector3(shed_x, deck + 9.0 * s, -24.5), roof)
	for z: float in [-24.0, 20.0]:
		m.tri(Vector3(shed_x - 4.0, deck + 6.8 * s, z), Vector3(shed_x + 4.0, deck + 6.8 * s, z),
				Vector3(shed_x, deck + 9.0 * s, z), shed_wall)
	# Lit upper terminal windows and lower boarding bays on the face towards the ship.
	var face_x := side * 4.98
	m.material(ShapeMesh.M_WINDOW)
	for i in 10:
		var wz := -20.5 + 4.1 * i
		m.quad(Vector3(face_x, deck + 4.2 * s, wz - 1.15), Vector3(face_x, deck + 4.2 * s, wz + 1.15),
				Vector3(face_x, deck + 5.7 * s, wz + 1.15), Vector3(face_x, deck + 5.7 * s, wz - 1.15),
				_mul(WARM, 0.85 if i % 2 == 0 else 0.7))
	for z: float in [-14.0, -2.0, 10.0]:
		m.quad(Vector3(face_x, deck + 0.1 * s, z - 2.2), Vector3(face_x, deck + 0.1 * s, z + 2.2),
				Vector3(face_x, deck + 3.0 * s, z + 2.2), Vector3(face_x, deck + 3.0 * s, z - 2.2), _mul(WARM, 0.6))
	# Four tall harbour lamp standards along the quay apron.
	m.material(ShapeMesh.M_PLAIN)
	for z: float in [-21.0, -7.0, 7.0, 21.0]:
		var px := side * 2.2
		m.tube(Vector3(px, deck, z), Vector3(px, deck + 6.4 * s, z), 0.12, 0.08, 4, iron, iron)
		m.box(Vector3(px - side * 0.45, deck + 6.25 * s, z), Vector3(0.9, 0.25 * s, 0.35), iron)
		var lp := Vector3(px - side * 0.75, deck + 6.1 * s, z)
		m.light(lp, WARM, 1.0, 0.9 * s)
		m.light(lp, WARM, 0.8, 0.22 * s)
	# Cargo crane gantry near the forward end of the quay.
	var gx := side * 3.0
	var gz := 23.0
	m.box(Vector3(gx, deck + 4.2 * s, gz - 2.2), Vector3(0.45, 8.4 * s, 0.45), iron)
	m.box(Vector3(gx, deck + 4.2 * s, gz + 2.2), Vector3(0.45, 8.4 * s, 0.45), iron)
	m.box(Vector3(gx, deck + 8.3 * s, gz), Vector3(0.6, 0.55 * s, 5.2), iron)
	m.box(Vector3(gx - side * 1.4, deck + 8.85 * s, gz), Vector3(4.2, 0.45 * s, 0.45), iron)
	m.light(Vector3(gx, deck + 9.0 * s, gz), Color(1.0, 0.24, 0.18), 0.9, 0.35 * s)


## A harbour breakwater and lighthouse: a stone sea wall with a tapered banded tower, gallery deck, glowing lantern
## room, domed cupola and bright warm beacon light.
static func _lighthouse(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var stone := Color("#2f3134")
	var band_red := Color("#6a1d1a")
	var iron := Color("#16171a")
	m.material(ShapeMesh.M_PLAIN)
	# Stone breakwater wall and head apron.
	m.box(Vector3(side * 4.0, 0.5, -5.0) * s, Vector3(10.0, 4.0, 22.0) * s, stone)
	m.box(Vector3(0.0, 0.75, 0.0) * s, Vector3(6.4, 4.5, 6.4) * s, _mul(stone, 1.1))
	# Tapered banded masonry tower (white / red / white / red).
	var tiers := [[2.8, 6.2, 2.5, 2.25, colour], [6.2, 9.2, 2.25, 2.02, band_red],
			[9.2, 12.6, 2.02, 1.78, colour], [12.6, 15.3, 1.78, 1.6, band_red]]
	for tier: Array in tiers:
		var c: Color = tier[4]
		m.tube(Vector3(0.0, float(tier[0]), 0.0) * s, Vector3(0.0, float(tier[1]), 0.0) * s,
				float(tier[2]) * s, float(tier[3]) * s, 8, c, _mul(c, 1.05))
	# Gallery deck and parapet.
	m.tube(Vector3(0.0, 15.1, 0.0) * s, Vector3(0.0, 15.7, 0.0) * s, 1.65 * s, 2.35 * s, 8, iron, iron)
	m.tube(Vector3(0.0, 15.7, 0.0) * s, Vector3(0.0, 16.2, 0.0) * s, 2.35 * s, 2.35 * s, 8, iron, iron)
	# Glowing glass lantern room.
	m.material(ShapeMesh.M_WINDOW)
	m.tube(Vector3(0.0, 15.8, 0.0) * s, Vector3(0.0, 17.8, 0.0) * s, 1.35 * s, 1.35 * s, 8,
			Color(1.0, 0.94, 0.78), Color(1.0, 0.94, 0.78))
	# Domed cupola and finial.
	m.material(ShapeMesh.M_PLAIN)
	m.tube(Vector3(0.0, 17.8, 0.0) * s, Vector3(0.0, 18.8, 0.0) * s, 1.45 * s, 0.6 * s, 8, band_red, band_red)
	m.tube(Vector3(0.0, 18.8, 0.0) * s, Vector3(0.0, 19.5, 0.0) * s, 0.25 * s, 0.04 * s, 6, iron, iron)
	# Beacon light (bright core + wide warm glow), twin sweeping volumetric beams, and a harbour-mouth marker.
	var beacon := Vector3(0.0, 16.8, 0.0) * s
	m.light(beacon, Color(1.0, 0.92, 0.7), 1.3, 2.6 * s)
	m.light(beacon, Color(1.0, 0.97, 0.88), 1.5, 0.65 * s)
	m.beam(16.8 * s, 68.0 * s, 0.9 * s, 11.5 * s, Color(1.0, 0.96, 0.84), 0.72,
			fmod(float(info.get("distance", 0.0)) * 0.17, TAU))
	var nav := Color(0.28, 1.0, 0.48) if side > 0.0 else Color(1.0, 0.25, 0.2)
	m.light(Vector3(-side * 2.8, 3.6, 2.6) * s, nav, 1.0, 0.45 * s)


## A 1930s ocean liner at sea or moored in harbour: dark steel hull with raked bow, three stepped white promenade
## decks, bridge wings, two raked funnels, two masts, rows of warmly lit promenade windows and hull portholes, and
## steaming and navigation lights.
static func _ship(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var hull := Color("#12151a")
	var waterline := Color("#4d1714")
	var stack_body := Color("#a85824") if rng.randf() < 0.5 else Color("#78201e")
	var stack_top := Color("#121215")
	m.material(ShapeMesh.M_PLAIN)
	# Main hull, waterline boot-topping, raked bow and cruiser stern.
	m.box(Vector3(0.0, 2.4, -2.0) * s, Vector3(13.0, 5.8, 72.0) * s, hull)
	for sx: float in [-6.55, 6.55]:
		m.quad(Vector3(sx, -0.4, -38.0) * s, Vector3(sx, -0.4, 34.0) * s, Vector3(sx, 0.7, 34.0) * s,
				Vector3(sx, 0.7, -38.0) * s, waterline)
	for sx: float in [-6.5, 6.5]:
		m.quad(Vector3(sx, -0.4, 34.0) * s, Vector3(0.0, -0.4, 44.0) * s, Vector3(0.0, 5.6, 47.0) * s,
				Vector3(sx, 5.3, 34.0) * s, hull)
		m.quad(Vector3(sx, -0.4, -38.0) * s, Vector3(0.0, -0.4, -44.0) * s, Vector3(0.0, 4.9, -45.5) * s,
				Vector3(sx, 5.3, -38.0) * s, hull)
	m.tri(Vector3(-6.5, 5.3, 34.0) * s, Vector3(6.5, 5.3, 34.0) * s, Vector3(0.0, 5.6, 47.0) * s, _mul(hull, 1.3))
	m.tri(Vector3(-6.5, 5.3, -38.0) * s, Vector3(6.5, 5.3, -38.0) * s, Vector3(0.0, 4.9, -45.5) * s, _mul(hull, 1.3))
	# Three stepped cream-white promenade decks and forward bridge wings.
	m.box(Vector3(0.0, 6.7, -2.0) * s, Vector3(11.4, 2.8, 56.0) * s, colour)
	m.box(Vector3(0.0, 9.4, -1.0) * s, Vector3(9.8, 2.6, 44.0) * s, _mul(colour, 0.96))
	m.box(Vector3(0.0, 11.7, 1.0) * s, Vector3(7.6, 2.0, 30.0) * s, colour)
	m.box(Vector3(0.0, 12.1, 14.5) * s, Vector3(14.2, 1.4, 3.2) * s, colour)
	# Two bold raked Art Deco funnels.
	for zf: float in [4.0, -10.0]:
		m.tube(Vector3(0.0, 12.6, zf) * s, Vector3(0.0, 18.2, zf - 1.4) * s, 2.1 * s, 1.9 * s, 8,
				stack_body, stack_body)
		m.tube(Vector3(0.0, 18.2, zf - 1.4) * s, Vector3(0.0, 20.4, zf - 2.0) * s, 1.9 * s, 1.85 * s, 8,
				stack_top, stack_top)
	# Foremast and mainmast.
	var mast := Color("#b89c6a")
	m.tube(Vector3(0.0, 12.6, 20.0) * s, Vector3(0.0, 22.5, 18.5) * s, 0.35 * s, 0.14 * s, 4, mast, mast)
	m.tube(Vector3(0.0, 10.6, -24.0) * s, Vector3(0.0, 21.2, -25.5) * s, 0.35 * s, 0.14 * s, 4, mast, mast)
	# Warmly lit promenade deck windows and hull portholes on the side facing the way.
	var x_lo := -side * 5.75 * s
	var x_hi := -side * 4.95 * s
	var x_hull := -side * 6.56 * s
	for i in 14:
		var wz := -26.0 + 3.7 * i
		var lit := rng.randf() < 0.8
		m.material(ShapeMesh.M_WINDOW if lit else ShapeMesh.M_PLAIN)
		var c := _mul(WARM, rng.randf_range(0.75, 1.0)) if lit else Color("#0b0d10")
		m.quad(Vector3(x_lo, 6.2 * s, (wz - 0.85) * s), Vector3(x_lo, 6.2 * s, (wz + 0.85) * s),
				Vector3(x_lo, 7.4 * s, (wz + 0.85) * s), Vector3(x_lo, 7.4 * s, (wz - 0.85) * s), c)
	for i in 11:
		var wz := -20.0 + 3.8 * i
		var lit := rng.randf() < 0.72
		m.material(ShapeMesh.M_WINDOW if lit else ShapeMesh.M_PLAIN)
		var c := _mul(WARM, rng.randf_range(0.7, 1.0)) if lit else Color("#0b0d10")
		m.quad(Vector3(x_hi, 8.9 * s, (wz - 0.8) * s), Vector3(x_hi, 8.9 * s, (wz + 0.8) * s),
				Vector3(x_hi, 10.0 * s, (wz + 0.8) * s), Vector3(x_hi, 10.0 * s, (wz - 0.8) * s), c)
	for i in 10:
		var wz := -27.0 + 5.8 * i
		var lit := rng.randf() < 0.55
		m.material(ShapeMesh.M_WINDOW if lit else ShapeMesh.M_PLAIN)
		var c := _mul(WARM, rng.randf_range(0.65, 0.95)) if lit else Color("#090b0e")
		m.quad(Vector3(x_hull, 3.2 * s, (wz - 0.35) * s), Vector3(x_hull, 3.2 * s, (wz + 0.35) * s),
				Vector3(x_hull, 3.9 * s, (wz + 0.35) * s), Vector3(x_hull, 3.9 * s, (wz - 0.35) * s), c)
	# Promenade glow lights, masthead steaming lights and bridge wing navigation light.
	for i in 5:
		m.light(Vector3(-side * 6.0, 8.1, -20.0 + 10.0 * i) * s, WARM, 0.85, 0.55 * s)
	m.light(Vector3(0.0, 22.6, 18.5) * s, COOL, 1.1, 0.45 * s)
	m.light(Vector3(0.0, 21.3, -25.5) * s, COOL, 1.0, 0.4 * s)
	var nav := Color(1.0, 0.25, 0.2) if side > 0.0 else Color(0.28, 1.0, 0.48)
	m.light(Vector3(-side * 7.1, 12.6, 14.5) * s, nav, 1.1, 0.45 * s)


## A 1990s cross-Channel Ro-Ro ferry terminal: concrete quay apron with bollards, corrugated steel passenger terminal
## with glazed elevated boarding gangway, twin-tower vehicle linkspan gantry with yellow-and-black hazard piers, four
## high-mast cold-sodium/halide port floodlight towers, and berth alignment signals. Length along the way is 68 m.
static func _ferry_port(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var deck := 3.0 * s
	var steel := Color("#232930")
	var blue_steel := Color("#243b52")
	var hazard := Color("#b88a1e")
	var terminal := Color("#4b535c")
	var roof := Color("#1c2026")
	var sodium := Color(1.0, 0.72, 0.32)
	var halide := Color(0.82, 0.92, 1.0)
	m.material(ShapeMesh.M_PLAIN)
	# Quay wall, apron deck and end caps.
	m.quad(Vector3(0.0, -1.5 * s, -34.0), Vector3(0.0, -1.5 * s, 34.0), Vector3(0.0, deck, 34.0),
			Vector3(0.0, deck, -34.0), colour)
	m.quad(Vector3(0.0, deck, -34.0), Vector3(side * 16.0, deck, -34.0), Vector3(side * 16.0, deck, 34.0),
			Vector3(0.0, deck, 34.0), _mul(colour, 1.12))
	for z: float in [-34.0, 34.0]:
		m.quad(Vector3(0.0, -1.5 * s, z), Vector3(side * 16.0, -1.5 * s, z), Vector3(side * 16.0, deck, z),
				Vector3(0.0, deck, z), _mul(colour, 0.85))
	# Steel bollards along the quay edge.
	for z: float in [-28.0, -14.0, 0.0, 14.0, 28.0]:
		m.box(Vector3(side * 0.75, deck + 0.45 * s, z), Vector3(0.5, 0.9 * s, 0.5), steel)
	# Modern flat-roofed terminal hall and elevated enclosed passenger gangway jutting towards the ferry.
	var hall_x := side * 11.2
	m.box(Vector3(hall_x, deck + 3.4 * s, -12.0), Vector3(8.5, 6.8 * s, 32.0), terminal)
	m.box(Vector3(hall_x, deck + 7.05 * s, -12.0), Vector3(9.0, 0.5 * s, 32.8), roof)
	# Elevated passenger walkway tunnel projecting out to the quay edge.
	var gang_x := side * 4.4
	m.box(Vector3(gang_x, deck + 5.2 * s, -8.0), Vector3(5.6, 2.5 * s, 4.2), _mul(terminal, 1.1))
	m.box(Vector3(side * 2.1, deck + 2.0 * s, -8.0), Vector3(0.7, 4.0 * s, 0.7), steel)
	# Glowing terminal departure hall windows and gangway glazing facing the ship.
	var face_x := side * 6.92
	m.material(ShapeMesh.M_WINDOW)
	for i in 7:
		var wz := -25.0 + 4.3 * i
		m.quad(Vector3(face_x, deck + 3.9 * s, wz - 1.55), Vector3(face_x, deck + 3.9 * s, wz + 1.55),
				Vector3(face_x, deck + 5.8 * s, wz + 1.55), Vector3(face_x, deck + 5.8 * s, wz - 1.55),
				_mul(halide, 0.85 if i % 2 == 0 else 0.72))
	var gang_face := side * 1.58
	m.quad(Vector3(gang_face, deck + 4.5 * s, -9.6), Vector3(gang_face, deck + 4.5 * s, -6.4),
			Vector3(gang_face, deck + 5.9 * s, -6.4), Vector3(gang_face, deck + 5.9 * s, -9.6), _mul(halide, 0.9))
	# Ro-Ro steel vehicle linkspan gantry (twin hoist portal towers, hazard bases, crosshead and loading ramp).
	m.material(ShapeMesh.M_PLAIN)
	var lx := side * 5.2
	for dz: float in [11.0, 25.0]:
		m.box(Vector3(lx, deck + 1.3 * s, dz), Vector3(1.5, 2.6 * s, 1.5), hazard)
		m.box(Vector3(lx, deck + 7.2 * s, dz), Vector3(1.2, 9.2 * s, 1.2), blue_steel)
	m.box(Vector3(lx, deck + 12.1 * s, 18.0), Vector3(1.6, 1.3 * s, 16.4), blue_steel)
	m.box(Vector3(lx - side * 1.6, deck + 1.8 * s, 18.0), Vector3(5.2, 0.7 * s, 12.0), steel)
	# Illuminated amber clearance strip across the linkspan portal crosshead and warm hazard markings on its piers.
	m.material(ShapeMesh.M_WINDOW)
	var gx := lx - side * 0.82
	m.quad(Vector3(gx, deck + 11.75 * s, 11.5), Vector3(gx, deck + 11.75 * s, 24.5),
			Vector3(gx, deck + 12.25 * s, 24.5), Vector3(gx, deck + 12.25 * s, 11.5), _mul(sodium, 0.72))
	for dz: float in [11.0, 25.0]:
		m.quad(Vector3(lx - side * 0.78, deck + 0.5 * s, dz - 0.55),
				Vector3(lx - side * 0.78, deck + 0.5 * s, dz + 0.55),
				Vector3(lx - side * 0.78, deck + 2.2 * s, dz + 0.55),
				Vector3(lx - side * 0.78, deck + 2.2 * s, dz - 0.55), _mul(hazard, 0.65))
	# Ground-level vehicle check-in booths / concourse glow along the terminal front apron.
	for i in 4:
		var bz := -23.0 + 7.2 * i
		m.quad(Vector3(face_x, deck + 0.6 * s, bz - 1.8), Vector3(face_x, deck + 0.6 * s, bz + 1.8),
				Vector3(face_x, deck + 2.3 * s, bz + 1.8), Vector3(face_x, deck + 2.3 * s, bz - 1.8),
				_mul(sodium, 0.6))
	m.material(ShapeMesh.M_PLAIN)
	# Four towering port high-mast floodlight standards (17.2 m) with sodium & halide lights.
	for z: float in [-28.0, -8.0, 8.0, 29.0]:
		var mx := side * 2.4
		m.tube(Vector3(mx, deck, z), Vector3(mx, deck + 14.2 * s, z), 0.24, 0.12, 4, steel, steel)
		m.box(Vector3(mx - side * 0.4, deck + 14.1 * s, z), Vector3(1.8, 0.45 * s, 1.4), steel)
		var lp := Vector3(mx - side * 0.9, deck + 13.8 * s, z)
		m.light(lp, sodium, 1.15, 1.35 * s)
		m.light(lp + Vector3(0.0, 0.0, 0.6), halide, 0.95, 0.55 * s)
	# Berth-mouth green/red traffic indicator lights on the linkspan piers.
	m.light(Vector3(lx - side * 0.9, deck + 4.4 * s, 11.0), Color(0.28, 1.0, 0.48), 1.0, 0.35 * s)
	m.light(Vector3(lx - side * 0.9, deck + 4.4 * s, 25.0), Color(1.0, 0.28, 0.2), 0.9, 0.35 * s)


## A cross-Channel cargo / container freighter under way at night: long dark steel hull with rust-red boot-topping,
## stacked multi-coloured shipping containers in three deck bays, tall white aft bridge superstructure with glowing
## bridge windows, blocky funnel, radar mast, working deck floodlights and maritime navigation lights.
static func _freighter(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var hull := colour
	var waterline := Color("#5a1d17")
	var white := Color("#cdd2d6")
	var funnel := Color("#9a3822") if rng.randf() < 0.5 else Color("#244b6e")
	var dark := Color("#12151a")
	m.material(ShapeMesh.M_PLAIN)
	# Main hull, waterline boot-topping, raked bow and transom stern.
	m.box(Vector3(0.0, 2.5, -1.0) * s, Vector3(12.6, 5.8, 66.0) * s, hull)
	for sx: float in [-6.35, 6.35]:
		m.quad(Vector3(sx, -0.4, -34.0) * s, Vector3(sx, -0.4, 32.0) * s, Vector3(sx, 0.9, 32.0) * s,
				Vector3(sx, 0.9, -34.0) * s, waterline)
	for sx: float in [-6.3, 6.3]:
		m.quad(Vector3(sx, -0.4, 32.0) * s, Vector3(0.0, -0.4, 41.0) * s, Vector3(0.0, 6.2, 43.0) * s,
				Vector3(sx, 5.4, 32.0) * s, hull)
	m.tri(Vector3(-6.3, 5.4, 32.0) * s, Vector3(6.3, 5.4, 32.0) * s, Vector3(0.0, 6.2, 43.0) * s, _mul(hull, 1.3))
	# Stacked multi-coloured shipping containers in three bays forward of the bridge.
	var palette := [Color("#6e2922"), Color("#263f59"), Color("#7d6228"), Color("#234733"), Color("#4e545c")]
	for bay in 3:
		var bz := -2.0 + 11.0 * bay
		var tiers := 2 + (1 if rng.randf() < 0.65 else 0)
		for tier in tiers:
			var col: Color = palette[rng.randi() % palette.size()]
			m.box(Vector3(0.0, 6.6 + 2.5 * tier, bz) * s, Vector3(10.6, 2.45, 9.6) * s, col)
	# Tall white aft accommodation block, cantilevered bridge wings, funnel and radar mast.
	m.box(Vector3(0.0, 9.4, -22.0) * s, Vector3(11.0, 8.2, 13.0) * s, white)
	m.box(Vector3(0.0, 14.8, -21.0) * s, Vector3(14.0, 2.4, 5.0) * s, white)
	m.box(Vector3(0.0, 17.6, -25.0) * s, Vector3(3.0, 3.6, 4.2) * s, funnel)
	m.box(Vector3(0.0, 19.6, -25.0) * s, Vector3(3.1, 0.7, 4.3) * s, dark)
	m.tube(Vector3(0.0, 16.0, -21.0) * s, Vector3(0.0, 21.6, -21.5) * s, 0.35 * s, 0.14 * s, 4, white, white)
	m.tube(Vector3(0.0, 5.8, 36.0) * s, Vector3(0.0, 15.2, 35.5) * s, 0.3 * s, 0.12 * s, 4, white, white)
	# Lit bridge & accommodation portholes facing the way, plus softly floodlit container faces along the deck.
	var xb := -side * 5.56 * s
	var xw := -side * 7.04 * s
	m.material(ShapeMesh.M_WINDOW)
	m.quad(Vector3(xw, 14.3 * s, -22.8 * s), Vector3(xw, 14.3 * s, -19.0 * s),
			Vector3(xw, 15.4 * s, -19.0 * s), Vector3(xw, 15.4 * s, -22.8 * s), _mul(WARM, 1.0))
	for row in 2:
		for i in 4:
			var wz := -26.5 + 3.0 * i
			var lit := rng.randf() < 0.78
			m.material(ShapeMesh.M_WINDOW if lit else ShapeMesh.M_PLAIN)
			var c := _mul(WARM, rng.randf_range(0.75, 1.0)) if lit else Color("#0b0d10")
			var y0 := (7.4 + 2.7 * row) * s
			m.quad(Vector3(xb, y0, (wz - 0.55) * s), Vector3(xb, y0, (wz + 0.55) * s),
					Vector3(xb, y0 + 1.05 * s, (wz + 0.55) * s), Vector3(xb, y0 + 1.05 * s, (wz - 0.55) * s), c)
	# Subtle warm deck-flood wash on the ship-facing side of the container stacks so the cargo reads at night.
	m.material(ShapeMesh.M_WINDOW)
	var xc := -side * 5.34 * s
	for bay in 3:
		var bz := -2.0 + 11.0 * bay
		var col: Color = palette[(bay + rng.randi()) % palette.size()]
		m.quad(Vector3(xc, 5.6 * s, (bz - 4.4) * s), Vector3(xc, 5.6 * s, (bz + 4.4) * s),
				Vector3(xc, 10.2 * s, (bz + 4.4) * s), Vector3(xc, 10.2 * s, (bz - 4.4) * s), _mul(col, 0.42))
	# Masthead steaming lights, bright deck working floodlights and bridge-wing red/green nav light.
	m.light(Vector3(0.0, 21.7, -21.5) * s, COOL, 1.2, 0.55 * s)
	m.light(Vector3(0.0, 15.3, 35.5) * s, COOL, 1.1, 0.5 * s)
	for bz: float in [-4.0, 8.0, 20.0]:
		m.light(Vector3(-side * 5.8, 12.2, bz) * s, WARM, 1.1, 0.75 * s)
	var nav := Color(1.0, 0.25, 0.2) if side > 0.0 else Color(0.28, 1.0, 0.48)
	m.light(Vector3(-side * 7.1, 15.2, -21.0) * s, nav, 1.2, 0.55 * s)


## A vintage railway telegraph pole: creosoted timber shaft, twin crossarms and pale porcelain insulator pins.
static func _telegraph(m: ShapeMesh, size: float, colour: Color) -> void:
	var s := size
	m.material(ShapeMesh.M_BARK)
	m.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 8.4, 0.0) * s, 0.16 * s, 0.11 * s, 6, colour, _mul(colour, 1.1))
	m.material(ShapeMesh.M_PLAIN)
	var arm := _mul(colour, 1.15)
	var ins := Color("#cfd6dc")
	for ay: float in [7.2, 7.9]:
		m.box(Vector3(0.0, ay, 0.0) * s, Vector3(2.1, 0.12, 0.12) * s, arm)
		for ax: float in [-0.9, -0.42, 0.42, 0.9]:
			m.box(Vector3(ax, ay + 0.12, 0.0) * s, Vector3(0.07, 0.14, 0.07) * s, ins)


## A snow-dusted alpine spruce / pine tree: dark bark trunk, four stacked evergreen bough cones and moonlit snow caps.
static func _pine(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	var h := rng.randf_range(8.5, 13.0) * s
	var r := rng.randf_range(1.75, 2.35) * s
	var bark := Color("#231914")
	var snow := Color("#c6d1df")
	m.material(ShapeMesh.M_BARK)
	m.tube(Vector3.ZERO, Vector3(0.0, h * 0.45, 0.0), 0.22 * s, 0.11 * s, 5, bark, bark)
	for tier in 4:
		var t0 := float(tier) / 4.0
		var y0 := h * (0.18 + 0.19 * tier)
		var y1 := h * (0.44 + 0.187 * tier)
		var rad := r * (1.0 - 0.21 * tier)
		m.material(ShapeMesh.M_LEAF)
		m.tube(Vector3(0.0, y0, 0.0), Vector3(0.0, y1, 0.0), rad, rad * 0.12, 6, colour, _mul(colour, 1.25))
		m.material(ShapeMesh.M_PLAIN)
		m.tube(Vector3(0.0, y0 + (y1 - y0) * 0.35, 0.0), Vector3(0.0, y1 + 0.06 * s, 0.0), rad * 0.78, rad * 0.08, 6,
				_mul(snow, 0.85 + 0.15 * t0), snow)


## A slender frosted silver birch: pale bark trunk with dark bands, forked limbs and a light frosty winter crown.
static func _birch(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	var h := rng.randf_range(7.5, 11.2) * s
	var lean := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35)) * s
	var dark := Color("#24262a")
	var frost := Color("#9fb0c4")
	m.material(ShapeMesh.M_BARK)
	m.tube(Vector3.ZERO, Vector3(0.0, h * 0.72, 0.0) + lean, 0.15 * s, 0.07 * s, 5, _mul(colour, 0.85), colour)
	for k in 3:
		var by := h * (0.18 + 0.18 * k)
		m.box(Vector3(lean.x * (by / h), by, lean.z * (by / h)), Vector3(0.24, 0.14, 0.24) * s, dark)
	for k in 3:
		var a := TAU * (float(k) / 3.0 + rng.randf_range(-0.12, 0.12))
		var base := Vector3(0.0, h * rng.randf_range(0.48, 0.68), 0.0) + lean * 0.8
		var tip := base + Vector3(cos(a) * rng.randf_range(0.9, 1.55) * s, h * rng.randf_range(0.24, 0.34),
				sin(a) * rng.randf_range(0.9, 1.55) * s)
		m.material(ShapeMesh.M_BARK)
		m.tube(base, tip, 0.06 * s, 0.025 * s, 4, colour, _mul(colour, 0.9))
		m.material(ShapeMesh.M_LEAF)
		m.ball(tip, rng.randf_range(0.55, 0.85) * s, 2, 5, frost, 0.85, 0.18, rng)


## A flat-topped Southwest red-rock desert mesa / butte: broad talus apron, sheer stepped sandstone cliffs and flat cap.
static func _mesa(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	var h := rng.randf_range(15.0, 25.0) * s
	var rw := rng.randf_range(10.0, 13.8) * s
	var talus := _mul(colour, 0.72)
	var cap := _mul(colour, 1.18)
	m.material(ShapeMesh.M_PLAIN)
	m.tube(Vector3(0.0, -0.5, 0.0) * s, Vector3(0.0, h * 0.42, 0.0), rw, rw * 0.68, 7, talus, colour)
	m.tube(Vector3(0.0, h * 0.42, 0.0), Vector3(0.0, h * 0.94, 0.0), rw * 0.68, rw * 0.62, 7, colour, cap)
	m.tube(Vector3(0.0, h * 0.94, 0.0), Vector3(0.0, h, 0.0), rw * 0.62, 0.1 * s, 7, cap, cap)
	if rng.randf() < 0.55:
		var sx := rng.randf_range(-4.5, 4.5) * s
		var sz := rng.randf_range(-5.5, 5.5) * s
		var sh := h * rng.randf_range(0.65, 0.9)
		m.tube(Vector3(sx, 0.0, sz), Vector3(sx, sh, sz), rw * 0.34, rw * 0.22, 6, talus, cap)


## A Southwest saguaro cactus: ribbed sage-green main trunk with one or two iconic upturned elbow arms.
static func _cactus(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	var h := rng.randf_range(3.3, 5.4) * s
	m.material(ShapeMesh.M_LEAF)
	m.tube(Vector3.ZERO, Vector3(0.0, h, 0.0), 0.26 * s, 0.2 * s, 6, _mul(colour, 0.85), _mul(colour, 1.15))
	var arms := 1 + (1 if rng.randf() < 0.75 else 0)
	for k in arms:
		var dir := -1.0 if k == 0 else 1.0
		if arms == 1 and rng.randf() < 0.5:
			dir = 1.0
		var ay := h * rng.randf_range(0.36, 0.58)
		var out := rng.randf_range(0.65, 1.05) * s
		var rise := rng.randf_range(1.1, 1.9) * s
		var elbow := Vector3(dir * out, ay, rng.randf_range(-0.18, 0.18) * s)
		m.tube(Vector3(0.0, ay, 0.0), elbow, 0.18 * s, 0.15 * s, 5, colour, colour)
		m.tube(elbow, Vector3(elbow.x, minf(ay + rise, h * 0.96), elbow.z), 0.16 * s, 0.13 * s, 5, colour,
				_mul(colour, 1.15))


## A soft multi-lobed cloud puff floating at altitude beside an airship or jetliner above the cloud deck.
static func _cloud_bank(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	m.material(ShapeMesh.M_PLAIN)
	var main_r := rng.randf_range(7.0, 10.5) * s
	var sq := rng.randf_range(0.45, 0.65)
	m.ball(Vector3(0.0, main_r * sq, 0.0), main_r, 3, 6, colour, sq, 0.14, rng)
	for k in 2:
		var ang := TAU * (0.25 + 0.5 * k + rng.randf_range(-0.15, 0.15))
		var r2 := main_r * rng.randf_range(0.55, 0.78)
		var at := Vector3(cos(ang) * main_r * 0.55, r2 * sq * 0.85, sin(ang) * main_r * 0.65)
		m.ball(at, r2, 2, 5, _mul(colour, 0.92), sq * 0.95, 0.16, rng)


## A vintage 1930s railway lattice semaphore signal post with angled red-and-white arm, finial and glowing green lamp.
static func _signal(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var iron := colour
	var red := Color("#8a1e18")
	var white := Color("#d8d4c8")
	m.material(ShapeMesh.M_PLAIN)
	# Base relay box and tapered lattice signal post.
	m.box(Vector3(side * 0.5, 0.65, 0.0) * s, Vector3(0.9, 1.3, 0.8) * s, iron)
	m.tube(Vector3.ZERO, Vector3(0.0, 9.2, 0.0) * s, 0.24 * s, 0.14 * s, 4, iron, _mul(iron, 1.15))
	m.tube(Vector3(0.0, 9.2, 0.0) * s, Vector3(0.0, 9.6, 0.0) * s, 0.18 * s, 0.04 * s, 4, white, white)
	# Semaphore arm angled upwards (clear line) extending towards the track with a crisp white stripe.
	var arm_dir := Vector3(-side, 0.65, 0.0).normalized()
	m.tube(Vector3(0.0, 7.9, 0.0) * s, Vector3(0.0, 7.9, 0.0) * s + arm_dir * 1.85 * s, 0.16 * s, 0.14 * s, 4, red, red)
	m.tube(Vector3(0.0, 7.9, 0.0) * s + arm_dir * 1.1 * s, Vector3(0.0, 7.9, 0.0) * s + arm_dir * 1.45 * s,
			0.17 * s, 0.16 * s, 4, white, white)
	# Glowing emerald-green aspect lamp facing oncoming train + soft halo.
	var lp := Vector3(-side * 0.35, 7.8, 0.3) * s
	m.light(lp, Color(0.24, 1.0, 0.52), 1.25, 0.32 * s)
	m.light(lp, Color(0.24, 1.0, 0.52), 0.45, 0.9 * s)


## A sleeping 1920s/30s wayside railway station: raised stone platform (36 m), pitched canopy, ticket hall with warm
## glowing windows facing the line, station clock fascia and six warm platform globe lamps.
static func _station(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var plat_h := 1.15 * s
	var wall := colour
	var roof := Color("#232830")
	var snow_roof := Color("#9aa6b8")
	var iron := Color("#1a1c20")
	m.material(ShapeMesh.M_PLAIN)
	# Raised stone platform and trackside coping.
	m.quad(Vector3(0.0, -0.4 * s, -18.0), Vector3(0.0, -0.4 * s, 18.0), Vector3(0.0, plat_h, 18.0),
			Vector3(0.0, plat_h, -18.0), _mul(wall, 0.82))
	m.quad(Vector3(0.0, plat_h, -18.0), Vector3(side * 10.0, plat_h, -18.0), Vector3(side * 10.0, plat_h, 18.0),
			Vector3(0.0, plat_h, 18.0), _mul(wall, 1.08))
	# Station house set back on the platform with pitched roof and snow-tinted eaves.
	var bx := side * 6.8
	m.box(Vector3(bx, plat_h + 2.2 * s, 0.0), Vector3(5.6, 4.4 * s, 16.0), wall)
	for dx: float in [-3.1, 3.1]:
		m.quad(Vector3(bx + dx, plat_h + 4.4 * s, -8.4), Vector3(bx + dx, plat_h + 4.4 * s, 8.4),
				Vector3(bx, plat_h + 6.2 * s, 8.4), Vector3(bx, plat_h + 6.2 * s, -8.4), roof)
	# Overhanging platform canopy on four cast-iron columns.
	m.box(Vector3(side * 2.5, plat_h + 3.55 * s, 0.0), Vector3(3.4, 0.24 * s, 20.0), snow_roof)
	for cz: float in [-8.5, -2.8, 2.8, 8.5]:
		m.tube(Vector3(side * 1.2, plat_h, cz), Vector3(side * 1.2, plat_h + 3.5 * s, cz), 0.11, 0.09, 5, iron, iron)
	# Warm glowing ticket-hall and waiting-room windows facing the railway line.
	var fx := side * 3.96
	for i in 5:
		var wz := -6.0 + 3.0 * i
		var lit := i == 2 or rng.randf() < 0.72
		m.material(ShapeMesh.M_WINDOW if lit else ShapeMesh.M_PLAIN)
		var wc := _mul(WARM, rng.randf_range(0.72, 1.0)) if lit else Color("#0b0d10")
		m.quad(Vector3(fx, plat_h + 1.1 * s, wz - 0.75), Vector3(fx, plat_h + 1.1 * s, wz + 0.75),
				Vector3(fx, plat_h + 2.65 * s, wz + 0.75), Vector3(fx, plat_h + 2.65 * s, wz - 0.75), wc)
	# Illuminated round-ish station clock box on the canopy edge.
	m.material(ShapeMesh.M_WINDOW)
	m.quad(Vector3(side * 0.78, plat_h + 3.0 * s, -0.45), Vector3(side * 0.78, plat_h + 3.0 * s, 0.45),
			Vector3(side * 0.78, plat_h + 3.8 * s, 0.45), Vector3(side * 0.78, plat_h + 3.8 * s, -0.45),
			_mul(WARM, 0.95))
	# Six warm platform globe lamps along the platform edge.
	m.material(ShapeMesh.M_PLAIN)
	for z: float in [-15.0, -9.0, -3.0, 3.0, 9.0, 15.0]:
		var px := side * 1.0
		m.tube(Vector3(px, plat_h, z), Vector3(px, plat_h + 3.1 * s, z), 0.07, 0.05, 4, iron, iron)
		m.light(Vector3(px, plat_h + 3.25 * s, z), WARM, 1.0, 0.45 * s)


## A classic 1950s desert railway water tower: hooped timber tank on four braced trestle legs, conical cap, delivery
## spout and a small lit pump-house shed with two depot lanterns.
static func _water_tower(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var timber := colour
	var steel := Color("#1c1f24")
	var roof := Color("#2a2624")
	m.material(ShapeMesh.M_PLAIN)
	# Four battered trestle legs and cross-braces.
	for lx: float in [-1.8, 1.8]:
		for lz: float in [-1.8, 1.8]:
			m.tube(Vector3(lx * 1.25, 0.0, lz * 1.25) * s, Vector3(lx, 7.6, lz) * s, 0.24 * s, 0.2 * s, 4, timber,
					timber)
	m.box(Vector3(0.0, 3.8, 0.0) * s, Vector3(4.2, 0.26, 4.2) * s, steel)
	m.box(Vector3(0.0, 7.55, 0.0) * s, Vector3(4.4, 0.4, 4.4) * s, timber)
	# Cylindrical hooped water tank and conical roof cap.
	m.tube(Vector3(0.0, 7.75, 0.0) * s, Vector3(0.0, 12.1, 0.0) * s, 2.75 * s, 2.75 * s, 10, timber, _mul(timber, 1.1))
	m.tube(Vector3(0.0, 12.1, 0.0) * s, Vector3(0.0, 13.7, 0.0) * s, 3.05 * s, 0.15 * s, 10, roof, roof)
	# Track-facing steel locomotive water spout.
	m.tube(Vector3(-side * 2.5, 8.2, 0.0) * s, Vector3(-side * 3.15, 6.2, 0.0) * s, 0.24 * s, 0.2 * s, 5, steel, steel)
	# Small pump-house shed beneath the legs with a glowing window.
	m.box(Vector3(side * 3.8, 1.5, 4.2) * s, Vector3(3.4, 3.0, 4.4) * s, _mul(timber, 0.9))
	m.material(ShapeMesh.M_WINDOW)
	var wx := side * 2.08 * s
	m.quad(Vector3(wx, 1.2 * s, 3.5 * s), Vector3(wx, 1.2 * s, 4.9 * s), Vector3(wx, 2.2 * s, 4.9 * s),
			Vector3(wx, 2.2 * s, 3.5 * s), WARM)
	m.light(Vector3(-side * 2.4, 7.8, 0.0) * s, WARM, 1.0, 0.42 * s)
	m.light(Vector3(0.0, 13.85, 0.0) * s, Color(1.0, 0.28, 0.2), 1.1, 0.35 * s)


## A 1930s steel lattice airship mooring mast tower: tapered four-legged pylon, circular glazed passenger boarding
## gallery, conical nose-docking cup, aviation red obstruction beacons and airfield floodlights.
static func _airship_mast(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var steel := colour
	var dark := Color("#232933")
	var base := Color("#363b42")
	m.material(ShapeMesh.M_PLAIN)
	# Concrete airfield base pavilion and tapered four-legged lattice pylon rising 34 m.
	m.box(Vector3(0.0, 2.2, 0.0) * s, Vector3(9.6, 4.4, 9.6) * s, base)
	for lx: float in [-1.0, 1.0]:
		for lz: float in [-1.0, 1.0]:
			m.tube(Vector3(lx * 4.2, 4.2, lz * 4.2) * s, Vector3(lx * 1.4, 32.0, lz * 1.4) * s, 0.42 * s, 0.26 * s, 4,
					steel, _mul(steel, 1.15))
	for ry: float in [11.0, 19.0, 26.5]:
		var rw := lerpf(7.6, 3.4, (ry - 4.2) / 27.8)
		m.box(Vector3(0.0, ry, 0.0) * s, Vector3(rw, 0.55, rw) * s, dark)
	# Central elevator shaft and cantilevered circular passenger boarding gallery at y 28.5..31.5 m.
	m.tube(Vector3(0.0, 4.2, 0.0) * s, Vector3(0.0, 32.0, 0.0) * s, 1.2 * s, 1.0 * s, 6, dark, dark)
	m.tube(Vector3(0.0, 28.2, 0.0) * s, Vector3(0.0, 31.6, 0.0) * s, 4.8 * s, 5.2 * s, 10, steel, _mul(steel, 1.15))
	# Conical nose-cone docking masthead cup.
	m.tube(Vector3(0.0, 31.6, 0.0) * s, Vector3(0.0, 35.8, 0.0) * s, 2.2 * s, 0.45 * s, 8, dark, steel)
	# Glowing Art Deco boarding-gallery observation windows facing the airship.
	m.material(ShapeMesh.M_WINDOW)
	var gx := -side * 5.05 * s
	for i in 4:
		var wz := -3.0 + 2.0 * i
		m.quad(Vector3(gx, 29.0 * s, (wz - 0.65) * s), Vector3(gx, 29.0 * s, (wz + 0.65) * s),
				Vector3(gx, 30.8 * s, (wz + 0.65) * s), Vector3(gx, 30.8 * s, (wz - 0.65) * s), _mul(WARM, 0.95))
	# Red aviation warning beacons at masthead + warm gallery & airfield searchlight lamps.
	var red := Color(1.0, 0.22, 0.18)
	m.light(Vector3(0.0, 36.1, 0.0) * s, red, 1.35, 0.65 * s)
	m.light(Vector3(-side * 5.1, 31.8, 0.0) * s, red, 1.05, 0.45 * s)
	for gz: float in [-3.8, 3.8]:
		m.light(Vector3(-side * 5.2, 28.4, gz) * s, WARM, 1.0, 0.6 * s)
	for bz: float in [-4.5, 4.5]:
		m.light(Vector3(-side * 5.0, 4.8, bz) * s, COOL, 1.1, 0.9 * s)


## A 1960s mid-century jet-age airport terminal: concrete apron, cantilevered departure concourse with bright lounge
## glazing, dramatic canted glass-cab control tower, aviation beacon and runway/apron edge lights.
static func _airport(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var conc := colour
	var roof := Color("#20262e")
	var steel := Color("#2a313b")
	var halide := Color(0.84, 0.93, 1.0)
	var taxi_blue := Color(0.24, 0.56, 1.0)
	m.material(ShapeMesh.M_PLAIN)
	# Apron slab and main mid-century terminal concourse with sweeping cantilevered roof overhang.
	m.quad(Vector3(0.0, 0.0, -34.0), Vector3(side * 22.0, 0.0, -34.0), Vector3(side * 22.0, 0.0, 34.0),
			Vector3(0.0, 0.0, 34.0), _mul(conc, 0.72))
	var hall_x := side * 12.5
	m.box(Vector3(hall_x, 3.6 * s, -4.0), Vector3(9.5, 7.2 * s, 44.0), conc)
	m.box(Vector3(hall_x - side * 1.4, 7.55 * s, -4.0), Vector3(12.8, 0.65 * s, 46.0), roof)
	# Enclosed jetway boarding pier extending towards the aircraft stand.
	m.box(Vector3(side * 4.8, 3.6 * s, 2.0), Vector3(6.4, 2.6 * s, 3.6), _mul(conc, 1.12))
	m.box(Vector3(side * 2.4, 1.2 * s, 2.0), Vector3(0.7, 2.4 * s, 0.7), steel)
	# Sweeping 1960s air traffic control tower: tapered pedestal + flared canted glass cab at 19..22 m.
	var tx := side * 14.5
	var tz := 22.0
	m.tube(Vector3(tx, 0.0, tz), Vector3(tx, 17.8 * s, tz), 2.8, 1.9, 6, _mul(conc, 0.95), conc)
	m.tube(Vector3(tx, 17.8 * s, tz), Vector3(tx, 21.4 * s, tz), 2.6, 4.2, 8, roof, _mul(conc, 1.1))
	m.tube(Vector3(tx, 21.4 * s, tz), Vector3(tx, 22.3 * s, tz), 4.5, 1.2, 8, roof, roof)
	# Bright departure concourse floor-to-ceiling windows and glowing ATC tower cab glazing.
	var face_x := side * 7.72
	m.material(ShapeMesh.M_WINDOW)
	for i in 9:
		var wz := -24.0 + 4.8 * i
		m.quad(Vector3(face_x, 1.4 * s, wz - 1.9), Vector3(face_x, 1.4 * s, wz + 1.9),
				Vector3(face_x, 6.2 * s, wz + 1.9), Vector3(face_x, 6.2 * s, wz - 1.9),
				_mul(halide if i % 3 != 0 else WARM, 0.9))
	var cab_x := tx - side * 3.7
	m.quad(Vector3(cab_x, 18.6 * s, tz - 2.4), Vector3(cab_x, 18.6 * s, tz + 2.4),
			Vector3(cab_x, 20.9 * s, tz + 2.4), Vector3(cab_x, 20.9 * s, tz - 2.4), _mul(halide, 0.95))
	# Control tower green/white rotating-style aviation beacons, apron halide masts and blue taxiway edge lights.
	m.light(Vector3(tx, 22.8 * s, tz), Color(0.28, 1.0, 0.52), 1.35, 0.7 * s)
	m.light(Vector3(tx - side * 1.2, 22.5 * s, tz), COOL, 1.15, 0.55 * s)
	for z: float in [-24.0, -8.0, 8.0, 26.0]:
		m.light(Vector3(side * 6.8, 8.2 * s, z), halide, 1.05, 0.85 * s)
	for z: float in [-28.0, -10.0, 10.0, 28.0]:
		m.light(Vector3(side * 0.6, 0.6 * s, z), taxi_blue, 1.0, 0.36 * s)


## Giant swaying underwater kelp cluster: three undulating stalks rising from a dark holdfast with golden-olive
## ribbon fronds fanning out up the water column.
static func _kelp(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	var holdfast := _mul(colour, 0.65)
	var frond_col := Color(colour.r * 1.45, colour.g * 1.35, colour.b * 0.85)
	m.material(ShapeMesh.M_STEM)
	m.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.6 * s, 0.0), 0.52 * s, 0.28 * s, 5, holdfast, holdfast)
	var stalks := 3
	for i in stalks:
		var ang := rng.randf() * TAU
		var h := rng.randf_range(8.5, 12.8) * s
		var ox := cos(ang) * rng.randf_range(0.18, 0.42) * s
		var oz := sin(ang) * rng.randf_range(0.18, 0.42) * s
		var sway_x := rng.randf_range(-0.9, 0.9) * s
		var sway_z := rng.randf_range(-0.9, 0.9) * s
		var p0 := Vector3(ox, 0.2 * s, oz)
		var p1 := Vector3(ox + sway_x * 0.45, h * 0.48, oz + sway_z * 0.45)
		var p2 := Vector3(ox + sway_x, h, oz + sway_z)
		m.material(ShapeMesh.M_STEM)
		m.tube(p0, p1, 0.09 * s, 0.065 * s, 4, colour, colour)
		m.tube(p1, p2, 0.065 * s, 0.04 * s, 4, colour, frond_col)
		m.material(ShapeMesh.M_LEAF)
		for k in 3:
			var t := 0.28 + 0.28 * k
			var base := p0.lerp(p1, t * 2.0) if t < 0.5 else p1.lerp(p2, (t - 0.5) * 2.0)
			var fa := ang + k * 2.1 + rng.randf_range(-0.4, 0.4)
			var dir := Vector3(cos(fa), 0.22, sin(fa)).normalized()
			var side_v := Vector3(-dir.z, 0.0, dir.x) * (0.34 * s)
			var tip := base + dir * rng.randf_range(0.95, 1.45) * s
			var fc := frond_col.lerp(colour, 0.35 * (k % 2))
			m.quad(base - side_v * 0.25, base + side_v * 0.25, tip + side_v * 0.45, tip - side_v * 0.45, fc)


## Craggy layered seabed basalt outcrop with pale coral/sea-fan tufts and a tiny cyan bioluminescent polyp.
static func _sea_rock(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	var dark := _mul(colour, 0.78)
	var hi := _mul(colour, 1.2)
	var coral := Color(0.68, 0.34, 0.26)
	m.material(ShapeMesh.M_PLAIN)
	var spires := 3
	for i in spires:
		var ang := i * TAU / spires + rng.randf_range(-0.4, 0.4)
		var rad := rng.randf_range(0.8, 1.65) * s if i > 0 else 0.0
		var h := (rng.randf_range(3.6, 6.2) if i == 0 else rng.randf_range(1.9, 4.2)) * s
		var r0 := rng.randf_range(1.1, 1.75) * s
		var r1 := r0 * rng.randf_range(0.28, 0.55)
		var p0 := Vector3(cos(ang) * rad, -0.2 * s, sin(ang) * rad)
		var p1 := p0 + Vector3(rng.randf_range(-0.4, 0.4) * s, h, rng.randf_range(-0.4, 0.4) * s)
		m.tube(p0, p1, r0, r1, 5, dark, hi)
	m.material(ShapeMesh.M_LEAF)
	for j in 2:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		var b := d * (0.9 * s) + Vector3(0.0, 1.3 * s, 0.0)
		var perp := Vector3(-d.z, 0.0, d.x) * (0.55 * s)
		m.quad(b - perp, b + perp, b + perp * 1.2 + Vector3(0.0, 1.15 * s, 0.0),
				b - perp * 1.2 + Vector3(0.0, 1.15 * s, 0.0), coral if j == 0 else Color(0.24, 0.56, 0.58))
	m.light(Vector3(0.0, 2.2 * s, 0.0), Color(0.25, 0.92, 0.95), 0.65, 0.24 * s)


## Swept-arm motorway sodium lighting mast with warm amber cobra-head luminaire.
static func _highway_lamp(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var arm_dir := -side
	var sodium := Color(1.0, 0.62, 0.22)
	m.material(ShapeMesh.M_PLAIN)
	m.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 10.2 * s, 0.0), 0.16 * s, 0.09 * s, 5, _mul(colour, 0.85), colour)
	m.tube(Vector3(0.0, 10.0 * s, 0.0), Vector3(arm_dir * 2.2 * s, 11.15 * s, 0.0), 0.08 * s, 0.06 * s, 4, colour, colour)
	m.box(Vector3(arm_dir * 2.35 * s, 11.2 * s, 0.0), Vector3(0.72, 0.18, 0.34) * s, _mul(colour, 1.15))
	m.material(ShapeMesh.M_WINDOW)
	var lx := arm_dir * 2.35 * s
	var ly := 11.09 * s
	m.quad(Vector3(lx - 0.3 * s, ly, -0.14 * s), Vector3(lx + 0.3 * s, ly, -0.14 * s),
			Vector3(lx + 0.3 * s, ly, 0.14 * s), Vector3(lx - 0.3 * s, ly, 0.14 * s), sodium)
	m.light(Vector3(lx, 10.95 * s, 0.0), sodium, 1.35, 0.48 * s)
	m.light(Vector3(lx, 10.75 * s, 0.0), Color(1.0, 0.72, 0.38), 0.7, 0.95 * s)


## Roadside motorway cantilever gantry with dark-blue reflective sign board, clean white geometric lane arrows and
## overhead luminaire lamps (zero text or trademarks).
static func _gantry(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var reach := -side
	var sign_blue := Color("#123664")
	var white := Color("#e4e8ee")
	m.material(ShapeMesh.M_PLAIN)
	# Twin vertical truss columns and cantilevered horizontal beam.
	for dz: float in [-0.45, 0.45]:
		m.tube(Vector3(0.0, 0.0, dz * s), Vector3(0.0, 8.2 * s, dz * s), 0.16 * s, 0.14 * s, 4, _mul(colour, 0.85), colour)
	m.box(Vector3(reach * 2.2 * s, 7.6 * s, 0.0), Vector3(4.4, 0.35, 0.95) * s, colour)
	m.box(Vector3(reach * 2.2 * s, 5.7 * s, 0.0), Vector3(4.4, 0.25, 0.75) * s, _mul(colour, 0.9))
	# Blue motorway signboard facing oncoming traffic (-Z) and rear (+Z), with crisp white border bars.
	m.box(Vector3(reach * 2.4 * s, 6.7 * s, 0.0), Vector3(3.6, 2.0, 0.18) * s, sign_blue)
	m.material(ShapeMesh.M_WINDOW)
	for sz: float in [-0.11, 0.11]:
		m.quad(Vector3((reach * 2.4 - 1.65) * s, 7.42 * s, sz * s),
				Vector3((reach * 2.4 + 1.65) * s, 7.42 * s, sz * s),
				Vector3((reach * 2.4 + 1.65) * s, 7.56 * s, sz * s),
				Vector3((reach * 2.4 - 1.65) * s, 7.56 * s, sz * s), _mul(white, 0.55))
		m.quad(Vector3((reach * 2.4 - 1.35) * s, 6.2 * s, sz * s),
				Vector3((reach * 2.4 + 1.35) * s, 6.2 * s, sz * s),
				Vector3((reach * 2.4 + 1.35) * s, 6.36 * s, sz * s),
				Vector3((reach * 2.4 - 1.35) * s, 6.36 * s, sz * s), _mul(white, 0.55))
	for ax: float in [1.4, 3.4]:
		m.light(Vector3(reach * ax * s, 8.25 * s, 0.35 * s), COOL, 1.0, 0.35 * s)


## Orbital elevator distant carbon-tether repeater pylon / beacon ring gliding vertically outside the climber car.
static func _tether_ring(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var foil := Color("#c49a38")
	var dark := Color("#2c323a")
	m.material(ShapeMesh.M_PLAIN)
	m.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 6.0 * s, 0.0), 0.38 * s, 0.38 * s, 6, dark, colour)
	m.box(Vector3(0.0, 3.0 * s, 0.0), Vector3(3.8, 0.75, 2.2) * s, colour)
	m.box(Vector3(-side * 1.4 * s, 3.0 * s, 0.0), Vector3(1.1, 1.35, 1.2) * s, foil)
	m.material(ShapeMesh.M_WINDOW)
	var wx := -side * 1.98 * s
	m.quad(Vector3(wx, 2.75 * s, -0.4 * s), Vector3(wx, 2.75 * s, 0.4 * s),
			Vector3(wx, 3.25 * s, 0.4 * s), Vector3(wx, 3.25 * s, -0.4 * s), Color(0.55, 0.9, 1.0))
	m.light(Vector3(-side * 2.1 * s, 3.6 * s, 0.0), Color(0.45, 0.88, 1.0), 1.15, 0.42 * s)
	m.light(Vector3(side * 1.9 * s, 2.4 * s, 0.0), Color(1.0, 0.58, 0.22), 0.95, 0.36 * s)


## Tall tapered Martian dust-devil vortex column drifting slowly across the rust plain.
static func _dust_devil(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	var h := rng.randf_range(18.0, 29.0) * s
	var lean_x := rng.randf_range(-1.6, 1.6) * s
	var lean_z := rng.randf_range(-1.6, 1.6) * s
	var base_col := _mul(colour, 0.72)
	var top_col := Color(minf(colour.r * 1.22, 1.0), minf(colour.g * 1.18, 1.0), minf(colour.b * 1.15, 1.0))
	m.material(ShapeMesh.M_PLAIN)
	var segs := 4
	var prev := Vector3.ZERO
	var prev_r := 0.85 * s
	for i in segs:
		var t1 := float(i + 1) / segs
		var next := Vector3(lean_x * t1 + sin(t1 * PI) * 0.45 * s, h * t1, lean_z * t1)
		var next_r := lerpf(0.85, 3.8, pow(t1, 1.25)) * s
		var c0 := base_col.lerp(top_col, float(i) / segs)
		var c1 := base_col.lerp(top_col, t1)
		m.tube(prev, next, prev_r, next_r, 7, c0, c1)
		prev = next
		prev_r = next_r


## Wind-carved Martian basalt ventifact boulders and stratified iron-oxide rocks.
static func _mars_rock(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color) -> void:
	var s := size
	var dark := _mul(colour, 0.62)
	var ochre := Color(minf(colour.r * 1.3, 1.0), minf(colour.g * 1.15, 1.0), colour.b * 0.9)
	m.material(ShapeMesh.M_PLAIN)
	for i in 3:
		var ang := i * TAU / 3.0 + rng.randf_range(-0.4, 0.4)
		var d := rng.randf_range(0.6, 1.7) * s if i > 0 else 0.0
		var h := (rng.randf_range(1.9, 3.9) if i == 0 else rng.randf_range(0.9, 2.2)) * s
		var r0 := rng.randf_range(0.9, 1.6) * s
		var p0 := Vector3(cos(ang) * d, -0.15 * s, sin(ang) * d)
		var p1 := p0 + Vector3(rng.randf_range(-0.3, 0.3) * s, h, rng.randf_range(-0.3, 0.3) * s)
		m.tube(p0, p1, r0, r0 * rng.randf_range(0.45, 0.85), 5, dark, ochre)


## Sunken 18th-century wooden sailing hull canted on the seabed: stern castle with eerie bioluminescent ports,
## exposed curved hull ribs, and broken tilted mainmast.
static func _sunken_wreck(m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var dark := _mul(colour, 0.68)
	var moss := Color(0.18, 0.32, 0.26)
	var bio := Color(0.28, 0.92, 0.85)
	m.material(ShapeMesh.M_PLAIN)
	# Main timber hull and raised stern castle.
	m.box(Vector3(0.0, 1.8 * s, 0.0), Vector3(6.2, 3.6, 22.0) * s, dark)
	m.box(Vector3(0.0, 4.4 * s, -7.2 * s), Vector3(5.6, 2.8, 7.6) * s, colour)
	m.box(Vector3(0.0, 1.2 * s, 12.2 * s), Vector3(3.4, 2.2, 5.2) * s, moss)
	# Five exposed wooden hull ribs curving up along the broken flank.
	for i in 5:
		var rz := (-4.0 + 3.2 * i) * s
		var rx := -side * 2.9 * s
		m.tube(Vector3(rx, 2.2 * s, rz), Vector3(rx + side * 0.4 * s, 5.2 * s, rz), 0.24 * s, 0.16 * s, 4, colour, moss)
	# Broken tilted mainmast and canted yardarm.
	var tilt := rng.randf_range(0.8, 1.8) * s
	m.tube(Vector3(0.0, 3.2 * s, 1.5 * s), Vector3(-side * tilt, 12.8 * s, 2.2 * s), 0.36 * s, 0.22 * s, 5, colour, dark)
	m.tube(Vector3(-side * (tilt * 0.65) - 3.6 * s, 8.8 * s, 1.8 * s),
			Vector3(-side * (tilt * 0.65) + 3.6 * s, 9.6 * s, 2.0 * s), 0.18 * s, 0.14 * s, 4, dark, colour)
	# Glowing turquoise bioluminescent stern-castle cabin windows facing the submarine.
	m.material(ShapeMesh.M_WINDOW)
	var wx := -side * 2.85 * s
	for i in 3:
		var wz := (-9.4 + 2.2 * i) * s
		m.quad(Vector3(wx, 4.0 * s, wz - 0.6 * s), Vector3(wx, 4.0 * s, wz + 0.6 * s),
				Vector3(wx, 5.1 * s, wz + 0.6 * s), Vector3(wx, 5.1 * s, wz - 0.6 * s), _mul(bio, 0.72))
	m.light(Vector3(wx, 4.6 * s, -7.2 * s), bio, 0.95, 0.65 * s)
	m.light(Vector3(-side * 1.4 * s, 3.8 * s, 5.5 * s), Color(0.4, 0.95, 0.78), 0.75, 0.45 * s)
	m.light(Vector3(-side * tilt, 12.6 * s, 2.2 * s), bio, 0.7, 0.38 * s)


## Towering deep-sea hydrothermal chimney cluster with glowing volcanic mineral fissures and plume rings.
static func _hydro_vent(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var dark := _mul(colour, 0.65)
	var mineral := Color("#3d4a4c")
	var ember := Color(1.0, 0.48, 0.16)
	var cyan := Color(0.28, 0.88, 0.95)
	m.material(ShapeMesh.M_PLAIN)
	m.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 14.2 * s, 0.0), 3.6 * s, 0.95 * s, 7, dark, mineral)
	m.tube(Vector3(side * 2.2 * s, 0.0, 2.8 * s), Vector3(side * 2.0 * s, 9.6 * s, 2.6 * s), 2.4 * s, 0.7 * s, 6, dark, colour)
	m.tube(Vector3(-side * 1.8 * s, 0.0, -2.5 * s), Vector3(-side * 1.6 * s, 7.2 * s, -2.3 * s), 1.9 * s, 0.55 * s, 6, dark, colour)
	m.material(ShapeMesh.M_WINDOW)
	var fx := -side * 1.35 * s
	m.quad(Vector3(fx, 11.2 * s, -0.35 * s), Vector3(fx, 11.2 * s, 0.35 * s),
			Vector3(fx, 13.6 * s, 0.25 * s), Vector3(fx, 13.6 * s, -0.25 * s), ember)
	m.light(Vector3(0.0, 14.5 * s, 0.0), ember, 1.3, 0.85 * s)
	m.light(Vector3(side * 2.0 * s, 9.9 * s, 2.6 * s), cyan, 1.0, 0.6 * s)
	m.light(Vector3(-side * 1.6 * s, 7.5 * s, -2.3 * s), ember, 0.95, 0.55 * s)
	m.light(Vector3(0.0, 12.2 * s, -side * 1.4 * s), cyan, 0.8, 0.5 * s)


## 1988 night motorway service station: tarmac forecourt, bright cantilevered petrol canopy, two-storey glass
## cafeteria block, retro three-stripe unbranded totem pylon and sodium car-park floodlights.
static func _services(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var tarmac := Color("#1c1f24")
	var canopy := Color("#cfd4da")
	var trim_teal := Color("#1a6b6e")
	var sodium := Color(1.0, 0.68, 0.28)
	var fluor := Color(0.88, 0.96, 1.0)
	m.material(ShapeMesh.M_PLAIN)
	# Tarmac forecourt apron.
	m.quad(Vector3(0.0, 0.0, -28.0), Vector3(side * 22.0, 0.0, -28.0), Vector3(side * 22.0, 0.0, 28.0),
			Vector3(0.0, 0.0, 28.0), tarmac)
	# Cantilevered petrol forecourt canopy with bright teal fascia band and four support stanchions.
	var cx := side * 9.0
	m.box(Vector3(cx, 5.2 * s, -10.0), Vector3(11.0, 0.9 * s, 18.0), canopy)
	m.box(Vector3(cx, 5.35 * s, -10.0), Vector3(11.15, 0.35 * s, 18.15), trim_teal)
	for px: float in [6.0, 12.0]:
		for pz: float in [-16.0, -4.0]:
			m.box(Vector3(side * px, 2.5 * s, pz), Vector3(0.45, 5.0 * s, 0.45), colour)
			m.box(Vector3(side * px, 0.85 * s, pz + 1.8), Vector3(0.85, 1.7 * s, 1.6), _mul(canopy, 0.85))
	# Two-storey motorway cafeteria and shop building.
	var bx := side * 14.5
	m.box(Vector3(bx, 3.8 * s, 11.0), Vector3(10.0, 7.6 * s, 22.0), colour)
	m.box(Vector3(bx - side * 0.6, 7.8 * s, 11.0), Vector3(11.6, 0.55 * s, 23.0), _mul(colour, 0.72))
	# Unbranded 1988 illuminated price/brand totem pylon at forecourt entry (three coloured bands, zero text).
	var tx := side * 3.2
	var tz := -22.0
	m.box(Vector3(tx, 7.4 * s, tz), Vector3(1.1, 14.8 * s, 2.6), _mul(colour, 0.85))
	m.material(ShapeMesh.M_WINDOW)
	# Bright glowing under-canopy strips, cafeteria windows and totem colour blocks.
	var face_x := side * 9.45
	for i in 5:
		var wz := 2.0 + 4.4 * i
		m.quad(Vector3(face_x, 1.2 * s, wz - 1.6), Vector3(face_x, 1.2 * s, wz + 1.6),
				Vector3(face_x, 6.2 * s, wz + 1.6), Vector3(face_x, 6.2 * s, wz - 1.6),
				_mul(WARM if i % 2 == 0 else fluor, 0.92))
	var tot_x := tx - side * 0.58
	m.quad(Vector3(tot_x, 12.2 * s, tz - 1.0), Vector3(tot_x, 12.2 * s, tz + 1.0),
			Vector3(tot_x, 14.1 * s, tz + 1.0), Vector3(tot_x, 14.1 * s, tz - 1.0), Color(0.18, 0.78, 0.76))
	m.quad(Vector3(tot_x, 9.8 * s, tz - 1.0), Vector3(tot_x, 9.8 * s, tz + 1.0),
			Vector3(tot_x, 11.8 * s, tz + 1.0), Vector3(tot_x, 11.8 * s, tz - 1.0), sodium)
	m.quad(Vector3(tot_x, 7.6 * s, tz - 1.0), Vector3(tot_x, 7.6 * s, tz + 1.0),
			Vector3(tot_x, 9.4 * s, tz + 1.0), Vector3(tot_x, 9.4 * s, tz - 1.0), Color(0.95, 0.32, 0.22))
	# Forecourt canopy floods and sodium car-park masts.
	for pz: float in [-15.0, -5.0]:
		m.light(Vector3(cx - side * 2.5, 4.7 * s, pz), fluor, 1.2, 0.9 * s)
	for mz: float in [-22.0, -10.0, 6.0, 22.0]:
		m.light(Vector3(side * 4.2, 11.5 * s, mz), sodium, 1.15, 0.85 * s)


## Equatorial semi-submersible orbital elevator sea-launch tether platform with twin tension gantry pylons, glazed
## control deck and warm perimeter deck beacons.
static func _ocean_platform(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var dark := _mul(colour, 0.68)
	var deck := _mul(colour, 1.08)
	var orange := Color("#c85a24")
	var cyan := Color(0.62, 0.92, 1.0)
	m.material(ShapeMesh.M_PLAIN)
	# Heavy semi-submersible deck and four deep ocean caisson legs.
	m.box(Vector3(0.0, 2.2 * s, 0.0), Vector3(22.0, 3.6, 26.0) * s, deck)
	for lx: float in [-9.0, 9.0]:
		for lz: float in [-10.0, 10.0]:
			m.tube(Vector3(lx, -2.0, lz) * s, Vector3(lx, 1.0, lz) * s, 2.2 * s, 2.2 * s, 6, dark, dark)
	# Twin angled tension-gantry pylons rising 24 m to anchor the orbital tether.
	for gz: float in [-8.5, 8.5]:
		m.tube(Vector3(side * 6.0, 4.0, gz) * s, Vector3(side * 1.2, 24.0, gz * 0.55) * s, 1.3 * s, 0.75 * s, 5,
				colour, orange)
		m.tube(Vector3(-side * 6.0, 4.0, gz) * s, Vector3(-side * 1.2, 24.0, gz * 0.55) * s, 1.3 * s, 0.75 * s, 5,
				colour, orange)
	m.box(Vector3(0.0, 23.6 * s, 0.0), Vector3(5.2, 1.4, 11.0) * s, orange)
	# Operations control house facing the climber car.
	m.box(Vector3(side * 6.8 * s, 6.2 * s, 0.0), Vector3(6.2, 4.4, 12.0) * s, colour)
	m.material(ShapeMesh.M_WINDOW)
	var wx := side * 3.65 * s
	for i in 4:
		var wz := (-4.5 + 3.0 * i) * s
		m.quad(Vector3(wx, 5.6 * s, wz - 1.1 * s), Vector3(wx, 5.6 * s, wz + 1.1 * s),
				Vector3(wx, 7.6 * s, wz + 1.1 * s), Vector3(wx, 7.6 * s, wz - 1.1 * s), cyan)
	for gz: float in [-5.2, 5.2]:
		m.light(Vector3(0.0, 24.3 * s, gz * s), Color(1.0, 0.34, 0.2), 1.3, 0.75 * s)
	for dz: float in [-11.0, 0.0, 11.0]:
		m.light(Vector3(-side * 10.5 * s, 4.6 * s, dz * s), WARM, 1.1, 0.7 * s)
	for dz: float in [-9.0, 9.0]:
		m.light(Vector3(side * 10.5 * s, 4.6 * s, dz * s), cyan, 1.05, 0.65 * s)


## Gleaming orbital elevator docking station terminus: pressurised habitat ring modules, gold foil thermal trusses,
## sweeping photovoltaic radiator wings and crisp docking alignment beacons.
static func _orbital_station(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var white := colour
	var foil := Color("#c89d3a")
	var panel := Color("#162848")
	var dark := Color("#363d48")
	var cyan := Color(0.68, 0.94, 1.0)
	m.material(ShapeMesh.M_PLAIN)
	# Central pressurised docking core and octagonal ring modules.
	m.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 18.5 * s, 0.0), 4.6 * s, 4.2 * s, 8, dark, white)
	m.box(Vector3(0.0, 9.5 * s, 0.0), Vector3(20.0, 4.4, 20.0) * s, white)
	m.box(Vector3(0.0, 12.2 * s, 0.0), Vector3(14.0, 2.2, 14.0) * s, foil)
	m.tube(Vector3(0.0, 18.5 * s, 0.0), Vector3(0.0, 21.5 * s, 0.0), 2.8 * s, 1.2 * s, 8, foil, white)
	# Four sweeping dark-blue solar radiator wings extending fore/aft and outward.
	for sz: float in [-16.0, 16.0]:
		m.box(Vector3(0.0, 9.5 * s, sz * s), Vector3(12.0, 0.35, 11.0) * s, panel)
		m.box(Vector3(0.0, 9.5 * s, (sz * 0.62) * s), Vector3(1.2, 1.0, 4.5) * s, foil)
	# Bright cyan-white observation bay windows facing the climber.
	m.material(ShapeMesh.M_WINDOW)
	var wx := -side * 10.06 * s
	for i in 5:
		var wz := (-7.2 + 3.6 * i) * s
		m.quad(Vector3(wx, 8.4 * s, wz - 1.2 * s), Vector3(wx, 8.4 * s, wz + 1.2 * s),
				Vector3(wx, 10.6 * s, wz + 1.2 * s), Vector3(wx, 10.6 * s, wz - 1.2 * s), cyan)
	for bz: float in [-9.0, 0.0, 9.0]:
		m.light(Vector3(-side * 10.4 * s, 11.8 * s, bz * s), Color(0.28, 1.0, 0.56), 1.25, 0.65 * s)
	for bz: float in [-9.0, 9.0]:
		m.light(Vector3(-side * 10.4 * s, 7.0 * s, bz * s), WARM, 1.1, 0.6 * s)
	m.light(Vector3(0.0, 21.8 * s, 0.0), Color(1.0, 0.36, 0.22), 1.35, 0.72 * s)
	for sz: float in [-21.5, 21.5]:
		m.light(Vector3(0.0, 9.8 * s, sz * s), cyan, 1.0, 0.55 * s)


## Moon Crater landing complex: sintered regolith landing apron, two illuminated geodesic lunar habitat domes,
## connecting airlock tunnel, communications dish mast and amber approach strobes.
static func _lunar_base(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var pad := Color("#464542")
	var dome := colour
	var steel := Color("#545960")
	var warm_win := Color(1.0, 0.84, 0.58)
	var cyan := Color(0.64, 0.9, 1.0)
	m.material(ShapeMesh.M_PLAIN)
	# Sintered regolith landing apron.
	m.quad(Vector3(0.0, 0.0, -30.0), Vector3(side * 24.0, 0.0, -30.0), Vector3(side * 24.0, 0.0, 30.0),
			Vector3(0.0, 0.0, 30.0), pad)
	# Main Crater geodesic habitat dome and secondary dome linked by pressurised airlock tunnel.
	var dx := side * 14.0
	m.tube(Vector3(dx, 0.0, -4.0), Vector3(dx, 5.2 * s, -4.0), 8.2, 7.6, 10, steel, dome)
	m.tube(Vector3(dx, 5.2 * s, -4.0), Vector3(dx, 10.4 * s, -4.0), 7.6, 4.2, 10, dome, _mul(dome, 1.1))
	m.tube(Vector3(dx, 10.4 * s, -4.0), Vector3(dx, 12.6 * s, -4.0), 4.2, 0.8, 10, _mul(dome, 1.1), dome)
	m.tube(Vector3(dx, 0.0, 14.0), Vector3(dx, 3.8 * s, 14.0), 5.4, 5.0, 8, steel, dome)
	m.tube(Vector3(dx, 3.8 * s, 14.0), Vector3(dx, 7.4 * s, 14.0), 5.0, 1.2, 8, dome, _mul(dome, 1.08))
	m.box(Vector3(dx, 2.2 * s, 5.5), Vector3(3.2, 3.2 * s, 10.0), steel)
	# Tall lunar comms mast and dish.
	m.tube(Vector3(dx, 0.0, -19.0), Vector3(dx, 16.4 * s, -19.0), 0.7, 0.35, 5, steel, dome)
	m.box(Vector3(dx - side * 1.4, 14.2 * s, -19.0), Vector3(2.8, 2.6 * s, 2.8), _mul(dome, 1.15))
	# Glowing habitat dome observation windows facing the landing pad.
	m.material(ShapeMesh.M_WINDOW)
	var wx := dx - side * 7.85
	for i in 4:
		var wz := -8.8 + 3.2 * i
		m.quad(Vector3(wx, 2.4 * s, wz - 1.1), Vector3(wx, 2.4 * s, wz + 1.1),
				Vector3(wx, 4.6 * s, wz + 1.1), Vector3(wx, 4.6 * s, wz - 1.1), warm_win)
	var wx2 := dx - side * 5.25
	for i in 2:
		var wz := 12.2 + 3.6 * i
		m.quad(Vector3(wx2, 1.8 * s, wz - 1.2), Vector3(wx2, 1.8 * s, wz + 1.2),
				Vector3(wx2, 3.4 * s, wz + 1.2), Vector3(wx2, 3.4 * s, wz - 1.2), cyan)
	# Approach pad strobe pylons and dome beacons.
	for pz: float in [-24.0, -8.0, 8.0, 24.0]:
		m.light(Vector3(side * 2.2, 1.4 * s, pz), WARM, 1.2, 0.55 * s)
	m.light(Vector3(dx, 13.0 * s, -4.0), cyan, 1.25, 0.7 * s)
	m.light(Vector3(dx, 16.7 * s, -19.0), Color(1.0, 0.28, 0.2), 1.35, 0.65 * s)
	for dz: float in [-4.0, 14.0]:
		m.light(Vector3(dx - side * 8.2, 5.6 * s, dz), warm_win, 1.05, 0.65 * s)


## Pressurised Martian domed night colony: grand translucent-glow biodome, flank habitat domes, dust-coated solar
## wing arrays, rover docking airlock tunnel and warm amber/red colony beacons.
static func _mars_base(m: ShapeMesh, size: float, colour: Color, info: Dictionary) -> void:
	var side := float(info["side"])
	var s := size
	var pad := Color("#5a3222")
	var dome := colour
	var steel := Color("#463832")
	var panel := Color("#2c2a3a")
	var amber := Color(1.0, 0.72, 0.34)
	var red := Color(1.0, 0.26, 0.18)
	m.material(ShapeMesh.M_PLAIN)
	m.quad(Vector3(0.0, 0.0, -30.0), Vector3(side * 24.0, 0.0, -30.0), Vector3(side * 24.0, 0.0, 30.0),
			Vector3(0.0, 0.0, 30.0), pad)
	# Central geodesic Martian biodome + two flank habitat modules.
	var dx := side * 14.5
	m.tube(Vector3(dx, 0.0, 0.0), Vector3(dx, 5.4 * s, 0.0), 8.6, 8.0, 10, steel, dome)
	m.tube(Vector3(dx, 5.4 * s, 0.0), Vector3(dx, 10.8 * s, 0.0), 8.0, 4.4, 10, dome, _mul(dome, 1.15))
	m.tube(Vector3(dx, 10.8 * s, 0.0), Vector3(dx, 13.2 * s, 0.0), 4.4, 0.9, 10, _mul(dome, 1.15), dome)
	for fz: float in [-16.0, 16.0]:
		m.tube(Vector3(dx, 0.0, fz), Vector3(dx, 3.8 * s, fz), 5.0, 4.6, 8, steel, dome)
		m.tube(Vector3(dx, 3.8 * s, fz), Vector3(dx, 7.2 * s, fz), 4.6, 1.0, 8, dome, _mul(dome, 1.12))
	# Rover docking airlock tunnel extending towards the trackway + solar arrays + comms tower.
	m.box(Vector3(side * 4.8, 2.2 * s, 0.0), Vector3(6.2, 3.4 * s, 4.4), steel)
	for sz: float in [-25.0, 25.0]:
		m.box(Vector3(side * 12.0, 2.4 * s, sz), Vector3(9.0, 0.35 * s, 5.5), panel)
	m.tube(Vector3(dx, 0.0, -21.0), Vector3(dx, 17.4 * s, -21.0), 0.7, 0.3, 5, steel, dome)
	# Glowing warm greenhouse/biodome window bands facing the Martian rover-train.
	m.material(ShapeMesh.M_WINDOW)
	var wx := dx - side * 8.2
	for i in 5:
		var wz := -6.4 + 3.2 * i
		m.quad(Vector3(wx, 2.2 * s, wz - 1.1), Vector3(wx, 2.2 * s, wz + 1.1),
				Vector3(wx, 5.0 * s, wz + 1.1), Vector3(wx, 5.0 * s, wz - 1.1), amber)
	var wx2 := dx - side * 4.9
	for fz: float in [-16.0, 16.0]:
		m.quad(Vector3(wx2, 1.8 * s, fz - 2.2), Vector3(wx2, 1.8 * s, fz + 2.2),
				Vector3(wx2, 3.6 * s, fz + 2.2), Vector3(wx2, 3.6 * s, fz - 2.2), amber)
	for pz: float in [-22.0, -6.0, 6.0, 22.0]:
		m.light(Vector3(side * 1.8, 1.8 * s, pz), amber, 1.2, 0.55 * s)
	m.light(Vector3(dx, 13.6 * s, 0.0), amber, 1.25, 0.8 * s)
	m.light(Vector3(dx, 17.7 * s, -21.0), red, 1.35, 0.7 * s)
	for fz: float in [-16.0, 16.0]:
		m.light(Vector3(dx, 7.6 * s, fz), amber, 1.0, 0.6 * s)
