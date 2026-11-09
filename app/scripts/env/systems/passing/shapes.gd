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
const LANDMARKS: Array[String] = ["lamp", "bridge", "boat", "wharf", "tower"]
## Shapes that stand end to end in a row, each this long along the way (metres): such a band's count is its loop's
## length over this, and its items stand at even steps, all at the band's `near`.
const SEGMENT := {"hedge": 6.0, "fence": 2.4, "ridge": 12.0}
## Each shape's own main colour.
const COLOURS := {
	"reeds": "#3a4127", "willow": "#2f3a22", "tree": "#1f2a1b", "poplar": "#1b2618", "hedge": "#1c2617",
	"fence": "#4a4337", "ridge": "#10141c", "lights": "#ffc98a", "cottage": "#26221d", "post": "#2e2a24",
	"lamp": "#1b1b1d", "bridge": "#4a3329", "boat": "#17301f", "wharf": "#3a3632", "tower": "#15171c",
}
## A far village's lights: this share warm, the rest cool.
const WARM := Color(1.0, 0.79, 0.54)
const COOL := Color(0.81, 0.89, 1.0)


static func draw(shape: String, m: ShapeMesh, rng: RandomNumberGenerator, size: float, colour: Color,
		info: Dictionary) -> void:
	match shape:
		"post":
			_post(m, size, colour)
		"ridge":
			_ridge(m, size, colour, info)
		"lights":
			_lights(m, rng, size, colour)


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
	m.light(Vector3(0.0, rng.randf_range(1.5, 6.0) * size, 0.0), c, rng.randf_range(0.4, 1.0), 0.08)
