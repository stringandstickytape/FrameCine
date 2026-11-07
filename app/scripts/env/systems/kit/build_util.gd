extends RefCounted

## The builders' static helpers (docs/environments.md, "The builders"): seat slots in rows and arcs, the seats'
## physics boxes, a hall's shell as boxes. Static; the builders call them from their own static functions (layout(),
## seat_slots_for(), collision_shapes_for()), which work from parameters alone, before a room is built.
##
## A seat slot (the seats system's interface): {transform, row, style, width, builder}. transform: the floor point
## under the seated eyes, facing -Z in its own frame, in room coordinates. row: 0 is the viewer's row, rows in front
## count up, rows behind are negative. style: chair, pew, bench, cushion, club, ring, tier. width: metres along the
## row a slot takes. A row's slots go left to right as the viewer faces the screen; a pew's or a bench's slots are
## `width` apart, an aisle leaves a bigger gap.

const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const SeatModels := preload("res://scripts/env/systems/kit/seat_models.gd")

## Styles drawn one seat a slot (a MultiMesh, the viewer's own folded away); the others are drawn as one piece.
const SINGLE: Array[String] = ["chair", "club", "ring"]


static func v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	return Vector2(float(v[0]), float(v[1]))


static func slot(xf: Transform3D, row: int, style: String, width: float) -> Dictionary:
	return {"transform": xf, "row": row, "style": style, "width": width, "builder": ""}


## A straight row across x at z, `count` slots `pitch` apart, centred on x0 (an odd count puts one at x0). gaps:
## extra space after these indices (aisles), the row kept centred on the slot at x0 when there is one.
static func row(z: float, y: float, count: int, pitch: float, row_index: int, style: String, x0 := 0.0,
		gaps := {}) -> Array:
	var xs: Array[float] = []
	var x := 0.0
	for i in count:
		xs.append(x)
		x += pitch + float(gaps.get(i, 0.0))
	var mid := xs[(count - 1) / 2] if count % 2 == 1 else (xs[0] + xs[-1]) * 0.5
	var out: Array = []
	for px in xs:
		out.append(slot(Transform3D(Basis(), Vector3(x0 + px - mid, y, z)), row_index, style, pitch))
	return out


## Slots on an arc round `centre` (in plan) at `radius`, facing it, `pitch` apart along the arc, within +-half_span
## radians of straight ahead (-Z from the centre's far side, the viewer's side being +Z). The middle slot (when the
## count is odd) is on the centre line.
static func arc(centre: Vector3, radius: float, y: float, pitch: float, half_span: float, row_index: int,
		style: String) -> Array:
	var step := pitch / maxf(radius, 0.01)
	var n := int(floor(half_span / step))
	var out: Array = []
	for k in range(-n, n + 1):
		var a := k * step
		var p := Vector3(centre.x + radius * sin(a), y, centre.z + radius * cos(a))
		out.append(slot(Transform3D(Basis(Vector3.UP, a), p), row_index, style, pitch))
	return out


static func transforms(slots: Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for s: Dictionary in slots:
		out.append(s["transform"])
	return out


## The slots in runs: consecutive slots of a row no more than 1.5 widths apart (a pew, a bench).
static func runs(slots: Array) -> Array:
	var out: Array = []
	var cur: Array = []
	for s: Dictionary in slots:
		if not cur.is_empty():
			var last: Dictionary = cur[-1]
			var gap := (last["transform"] as Transform3D).origin.distance_to((s["transform"] as Transform3D).origin)
			if int(last["row"]) != int(s["row"]) or gap > 1.5 * float(s["width"]):
				out.append(cur)
				cur = []
		cur.append(s)
	if not cur.is_empty():
		out.append(cur)
	return out


## Physics boxes for single seats of a model, one pair a slot (two shared shapes).
static func seat_boxes(slots: Array, model: String) -> Array:
	var out: Array = []
	var shapes: Array = []
	for bx: Array in SeatModels.boxes(model):
		var s := BoxShape3D.new()
		s.size = bx[1]
		shapes.append([s, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(float(bx[2]))), bx[0])])
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		for sh: Array in shapes:
			out.append([sh[0], xf * (sh[1] as Transform3D)])
	return out


## A closed hall's shell: a slab under the floor, the ceiling (unless open), the four walls, outside the box.
static func shell_boxes(lo: Vector3, hi: Vector3, ceiling := true, t := 1.0) -> Array:
	var out: Array = []
	var size := hi - lo
	var mid := (lo + hi) * 0.5
	out.append(PhysicsShapes.box(Vector3(mid.x, lo.y - t * 0.5, mid.z), Vector3(size.x + 2.0 * t, t, size.z + 2.0 * t)))
	if ceiling:
		out.append(PhysicsShapes.box(Vector3(mid.x, hi.y + t * 0.5, mid.z), Vector3(size.x + 2.0 * t, t,
				size.z + 2.0 * t)))
	for s: float in [-1.0, 1.0]:
		out.append(PhysicsShapes.box(Vector3(mid.x + s * (size.x + t) * 0.5, mid.y, mid.z),
				Vector3(t, size.y + 2.0 * t, size.z + 2.0 * t)))
		out.append(PhysicsShapes.box(Vector3(mid.x, mid.y, mid.z + s * (size.z + t) * 0.5),
				Vector3(size.x + 2.0 * t, size.y + 2.0 * t, t)))
	return out


## A box as a physics shape from [centre, size] (or with a basis third).
static func box_shape(part: Array) -> Array:
	return PhysicsShapes.box(part[0], part[1], part[2] if part.size() > 2 else Basis())
