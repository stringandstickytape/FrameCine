extends RefCounted

## A glass dome made as engineers would make it on the Moon (dome_hall.gd's `lattice` geodesic, `airlocks`, `trays`;
## since 2026-11-08, the Crater's quality pass: "a geodesic or ribbed glass dome with real engineering: steel ribs with
## bolts and seals ... the drum with airlock doors and status lights, cable trays", the brief).
##   Lattice   a geodesic frame: an icosahedron with a point at the top, each face split `frequency` times, the half
##             over the equator put on the dome's shell (its own height, so a low dome is a squashed one); its ring at
##             the equator stands on the drum. Steel struts of a box section, a hub at every node (bolt heads on the
##             lowest two rings, the ones near the seats). Flat glass in every triangle: one thin layer, never two.
##   Airlocks  a door set into the dome's foot either side of the screen (two by two): a steel portal, the door leaf
##             with a round window lit from the vestibule, a status lamp over it (green: the vestibule holds its air),
##             a lit panel beside it, the threshold's plate. Outside, the tube is the terrace's (kit/lunar_surface.gd).
##   Trays     a cable tray along the drum on brackets, cables in it, broken at the doors.
## Unbaked (their many small faces would each be a lightmap chart): lit by the fill, the film and the lamps. Static.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")

## The struts' section (across, deep), the hubs' radius and depth, how far inside the glass the frame stands.
const STRUT := Vector2(0.085, 0.15)
const HUB_R := 0.13
const HUB_D := 0.12
const INSET := 0.1
## The airlocks' bearings from the dome's centre (degrees from ahead): the first pair, then a second pair behind.
const AIRLOCK_THETAS: Array[float] = [62.0, -62.0, 118.0, -118.0]
const DOOR := Vector2(1.3, 2.15)


## A geodesic half sphere (unit): [points: Array[Vector3], edges: Array[Vector2i], triangles: Array[Vector3i]], every
## point with y >= 0. `frequency` even, so a ring of edges lies on the equator.
static func geodesic(frequency: int) -> Array:
	var lat := atan(0.5)
	var ico: Array[Vector3] = [Vector3.UP]
	for k in 5:
		var a := TAU * k / 5.0
		ico.append(Vector3(cos(lat) * sin(a), sin(lat), cos(lat) * cos(a)))
	for k in 5:
		var a := TAU * (k + 0.5) / 5.0
		ico.append(Vector3(cos(lat) * sin(a), -sin(lat), cos(lat) * cos(a)))
	ico.append(Vector3.DOWN)
	var faces: Array = []
	for k in 5:
		var u0 := 1 + k
		var u1 := 1 + (k + 1) % 5
		var l0 := 6 + k
		var l1 := 6 + (k + 1) % 5
		faces.append([0, u0, u1])
		faces.append([u0, l0, u1])
		faces.append([l0, l1, u1])
		faces.append([11, l1, l0])
	var f := maxi(frequency, 1)
	var points: Array[Vector3] = []
	var index := {}
	var tris: Array[Vector3i] = []
	var key := func(p: Vector3) -> String: return "%d,%d,%d" % [roundi(p.x * 10000), roundi(p.y * 10000),
			roundi(p.z * 10000)]
	for face: Array in faces:
		var a: Vector3 = ico[face[0]]
		var b: Vector3 = ico[face[1]]
		var c: Vector3 = ico[face[2]]
		var grid := {}
		for i in f + 1:
			for j in f + 1 - i:
				var p := (a + (b - a) * float(i) / f + (c - a) * float(j) / f).normalized()
				var k: String = key.call(p)
				if not index.has(k):
					index[k] = points.size()
					points.append(p)
				grid[Vector2i(i, j)] = index[k]
		for i in f:
			for j in f - i:
				tris.append(Vector3i(grid[Vector2i(i, j)], grid[Vector2i(i + 1, j)], grid[Vector2i(i, j + 1)]))
				if i + j < f - 1:
					tris.append(Vector3i(grid[Vector2i(i + 1, j)], grid[Vector2i(i + 1, j + 1)], grid[Vector2i(i, j + 1)]))
	var keep: Array[Vector3i] = []
	for t: Vector3i in tris:
		if points[t.x].y > -0.001 and points[t.y].y > -0.001 and points[t.z].y > -0.001:
			keep.append(t)
	var edges := {}
	for t: Vector3i in keep:
		for e: Vector2i in [Vector2i(t.x, t.y), Vector2i(t.y, t.z), Vector2i(t.z, t.x)]:
			edges[Vector2i(mini(e.x, e.y), maxi(e.x, e.y))] = true
	var edge_list: Array[Vector2i] = []
	for e: Vector2i in edges:
		edge_list.append(e)
	return [points, edge_list, keep]


## A unit point on the dome's shell: base (its equator's centre), r across, h up, turned by `turn` round the vertical.
static func on_shell(p: Vector3, base: Vector3, r: float, h: float, turn: float) -> Vector3:
	var q := Basis(Vector3.UP, turn) * p
	return base + Vector3(q.x * r, maxf(q.y, 0.0) * h, q.z * r)


## The lattice: struts and hubs into `frame`, the panes into `panes` (flat triangles facing in).
static func lattice(frame: RoomMesh, panes: RoomMesh, base: Vector3, r: float, h: float, frequency: int,
		turn: float, floor_y: float) -> void:
	var g := geodesic(frequency)
	var pts: Array[Vector3] = g[0]
	var edges: Array[Vector2i] = g[1]
	var tris: Array[Vector3i] = g[2]
	var centre := base
	for t: Vector3i in tris:
		var a := on_shell(pts[t.x], base, r, h, turn)
		var b := on_shell(pts[t.y], base, r, h, turn)
		var c := on_shell(pts[t.z], base, r, h, turn)
		var n := (b - a).cross(c - a).normalized()
		if n.dot((a + b + c) / 3.0 - centre) > 0.0:
			n = -n
		panes.face([a, b, c], n)
	var inr := r - INSET
	var inh := h - INSET
	for e: Vector2i in edges:
		var a := on_shell(pts[e.x], base, inr, inh, turn)
		var b := on_shell(pts[e.y], base, inr, inh, turn)
		var out := ((a + b) * 0.5 - centre).normalized()
		Shapes.beam(frame, a, b, STRUT, out)
	for i in pts.size():
		if pts[i].y < -0.001:
			continue
		var q := on_shell(pts[i], base, inr, inh, turn)
		var out := (q - centre).normalized()
		var bas := _facing(out)
		Shapes.cylinder(frame, q - out * HUB_D * 0.75, HUB_R, HUB_D, 8, bas)
		# Bolt heads round the lowest hubs (the ones a seat is near).
		if pts[i].y < 0.3:
			for k in 6:
				var a := TAU * k / 6.0
				var at := q - out * (HUB_D * 0.75 + 0.012) + bas * Vector3(cos(a) * 0.085, 0, sin(a) * 0.085)
				Shapes.cylinder(frame, at, 0.018, 0.02, 6, Basis(bas.x, -bas.y, -bas.z), false)
	# The seal round the dome's foot: a compression ring on the drum.
	Shapes.lathe(frame, [Vector2(r - 0.02, 0.0), Vector2(r - 0.28, 0.0), Vector2(r - 0.28, 0.16),
			Vector2(r - 0.05, 0.22)], base, 64)


## A basis whose +Y points along `dir`.
static func _facing(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


## The airlocks' doors into `steel` (frames), `leaf` (the doors), their lamps into `status` (green), `panels` (cool)
## and `windows` (warm, the vestibule's light behind the door's window). c: the dome's centre on its floor.
static func airlocks(count: int, c: Vector3, r: float, steel: RoomMesh, leaf: RoomMesh, status: RoomMesh,
		panels: RoomMesh, windows: RoomMesh) -> Array[Vector3]:
	var at: Array[Vector3] = []
	for i in mini(count, AIRLOCK_THETAS.size()):
		var th := deg_to_rad(AIRLOCK_THETAS[i])
		var out := Vector3(sin(th), 0, -cos(th))
		var side := Vector3(-out.z, 0, out.x)
		var face := c + out * (r - 0.45)
		var bas := Basis(side, Vector3.UP, -out)
		# The portal: jambs, a head, the threshold plate; its reveal back to the glass.
		var w := DOOR.x * 0.5
		for s: float in [-1.0, 1.0]:
			steel.box(face + side * s * (w + 0.16) + Vector3.UP * (DOOR.y + 0.25) * 0.5, Vector3(0.32, DOOR.y + 0.25,
					0.5), bas)
		steel.box(face + Vector3.UP * (DOOR.y + 0.2), Vector3(DOOR.x + 0.64, 0.4, 0.5), bas)
		steel.box(face + Vector3.UP * 0.02 - out * 0.05, Vector3(DOOR.x + 0.3, 0.04, 0.7), bas)
		# The leaf, set back in the portal; a round window in it.
		leaf.box(face + out * 0.12 + Vector3.UP * (DOOR.y * 0.5 + 0.02), Vector3(DOOR.x, DOOR.y, 0.1), bas)
		var win := face + out * 0.065 + Vector3.UP * 1.5
		Shapes.cylinder(windows, win, 0.17, 0.005, 16, bas.rotated(side, PI * 0.5), false)
		var cap: Array = []
		for k in 16:
			var a := TAU * k / 16.0
			cap.append(win + side * cos(a) * 0.17 + Vector3.UP * sin(a) * 0.17)
		windows.face(cap, -out)
		# The status lamp over the door, the panel beside it.
		status.box(face - out * 0.26 + Vector3.UP * (DOOR.y + 0.48), Vector3(0.28, 0.07, 0.05), bas)
		panels.box(face - out * 0.26 + side * (w + 0.55) + Vector3.UP * 1.35, Vector3(0.22, 0.3, 0.03), bas)
		steel.box(face - out * 0.235 + side * (w + 0.55) + Vector3.UP * 1.35, Vector3(0.3, 0.38, 0.03), bas)
		at.append(face)
	return at


## The cable tray along the drum (at `y` over the floor), on brackets, cables in it; broken at the doors.
static func trays(tray: RoomMesh, cables: RoomMesh, c: Vector3, r: float, y: float, doors: int) -> void:
	var gaps: Array[float] = []
	for i in mini(doors, AIRLOCK_THETAS.size()):
		gaps.append(AIRLOCK_THETAS[i])
	gaps.sort()
	var rr := r - 0.12
	# Runs between the doors, as angles from ahead (the lathe's angle runs from +Z, so ahead is PI).
	var runs: Array = []
	if gaps.is_empty():
		runs.append([0.0, TAU])
	else:
		var half := deg_to_rad(4.5)
		for i in gaps.size():
			var a0 := deg_to_rad(gaps[i]) + half
			var a1 := deg_to_rad(gaps[(i + 1) % gaps.size()]) - half
			if a1 <= a0:
				a1 += TAU
			runs.append([a0, a1])
	for run: Array in runs:
		var a0: float = run[0]
		var a1: float = run[1]
		var arc := a1 - a0
		var sides := maxi(int(arc * rr / 1.5), 4)
		# The lathe's 0 is +Z; theta 0 is -Z (ahead): start at PI - a1 going round the other way is the same arc.
		var start := PI - a1
		var prof := [Vector2(rr - 0.3, y + 0.09), Vector2(rr - 0.3, y), Vector2(rr, y), Vector2(rr, y + 0.06)]
		Shapes.lathe(tray, prof, c, sides, Basis(), arc, start)
		Shapes.lathe(cables, [Vector2(rr - 0.27, y + 0.005), Vector2(rr - 0.25, y + 0.05), Vector2(rr - 0.1, y + 0.06),
				Vector2(rr - 0.03, y + 0.005)], c, sides, Basis(), arc, start)
		var n := maxi(int(arc * rr / 2.2), 1)
		for k in n + 1:
			var a := start + arc * float(k) / n
			var dir := Vector3(sin(a), 0, cos(a))
			tray.box(c + dir * (rr - 0.12) + Vector3.UP * (y - 0.04), Vector3(0.04, 0.05, 0.3),
					Basis(Vector3.UP, a))
