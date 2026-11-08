extends RefCounted

## A generic 1950s car's body, lofted from cross-sections (since 2026-11-08, the drive-in's quality pass: "the car is
## where you sit: the closest, most-looked-at thing. Make it superb", the brief). No maker's shape, no badge, no name:
## long flat wings ending in hooded headlamps, a bonnet with a soft crown, a wraparound windscreen, a side spear in a
## second colour edged in chrome, a skirted rear wheel, tail fins rising to rocket-like lamps. The viewer's convertible
## (vehicle.gd: the cabin open, the interior its own) and the cars parked round it (drive_in_lot.gd: closed, a
## hardtop's glasshouse, dark glass) share it. Static; preload to use.
##
##   dims(overrides) -> Dictionary                  the plan (metres; the cabin's floor at y 0, the bonnet to -Z)
##   body(b, d, paint, trim, dark, chrome_b, open)  the shell into the RoomMesh's current surface, vertex colours
##                                                  paint, trim (the spear) and dark (wheel wells, the inside); the
##                                                  spear's chrome beads, the bumpers, the grille into chrome_b
##   wheels(b, chrome_b, d, ground_y, tyre, wall)   tyres with whitewalls, hub caps
##   glasshouse(b, d, glass, roof)                  a hardtop's pillars, roof and dark glass (parked cars)
##   section(d, z, open) -> PackedVector3Array      one cross-section, left to right over the top

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")

const DEFAULTS := {"half": 0.98, "inner": 0.8, "front": -3.0, "rear": 2.8, "belt": 0.72, "bottom": -0.28,
		"cowl": -1.2, "dash_z": -0.9, "cabin_back": 1.62, "fins": 0.32, "axle_front": -2.05, "axle_rear": 1.85,
		"wheel_r": 0.36, "arch": 0.46, "ground_y": -0.5}
## Points a section has (11 a side and the crown).
const SECTION_POINTS := 23


static func dims(overrides := {}) -> Dictionary:
	var d := DEFAULTS.duplicate()
	d.merge(overrides, true)
	return d


# --- The lines of the body -----------------------------------------------------------------------------------------

## Half the body's width at z: the corners rounded in plan at both ends.
static func half_width(d: Dictionary, z: float) -> float:
	var front := float(d["front"])
	var rear := float(d["rear"])
	var w := float(d["half"])
	w -= 0.07 * pow(smoothstep(front + 0.35, front, z), 1.6)
	w -= 0.05 * pow(smoothstep(rear - 0.3, rear, z), 1.6)
	return w


## How far the fins have risen at z (0..1).
static func fin_rise(d: Dictionary, z: float) -> float:
	return pow(smoothstep(float(d["cabin_back"]) + 0.05, float(d["rear"]) - 0.06, z), 1.5)


## The top of the side: the wing's top ahead of the cabin (a hooded headlamp at its end), the belt along the doors,
## rising into the fin behind.
static func belt(d: Dictionary, z: float) -> float:
	var front := float(d["front"])
	var cowl := float(d["cowl"])
	var b := float(d["belt"])
	if z < cowl:
		var s := smoothstep(front, cowl, z)
		var y := lerpf(0.6, b - 0.02, s)
		# The headlamp's hood: a swell near the end of the wing, then the wing turns down to the lamp.
		y += 0.035 * exp(-pow((z - (front + 0.28)) / 0.22, 2.0))
		y -= 0.07 * pow(smoothstep(front + 0.16, front, z), 1.5)
		return y
	if z < float(d["dash_z"]):
		return lerpf(b - 0.02, b, smoothstep(cowl, float(d["dash_z"]), z))
	return b + float(d["fins"]) * fin_rise(d, z) - 0.05 * pow(smoothstep(float(d["rear"]) - 0.08,
			float(d["rear"]), z), 2.0)


## The middle of the top: the bonnet's crown ahead, the rear deck behind; inside the cabin (a closed car) the belt.
static func crown(d: Dictionary, z: float) -> float:
	var front := float(d["front"])
	var cowl := float(d["cowl"])
	if z <= cowl:
		var s := clampf((z - front) / (cowl - front), 0.0, 1.0)
		var y := 0.665 - 0.15 * pow(1.0 - s, 1.8)
		y -= 0.06 * pow(smoothstep(front + 0.12, front, z), 2.0)
		return y
	var back := float(d["cabin_back"])
	if z >= back:
		var rear := float(d["rear"])
		var s := clampf((z - back) / (rear - back), 0.0, 1.0)
		return 0.66 - 0.06 * s - 0.08 * pow(smoothstep(rear - 0.15, rear, z), 2.0)
	return float(d["belt"]) - 0.03


## The body's lowest line: raised over the front wheel (its arch; the rear wheel is skirted) and at the overhangs.
static func bottom(d: Dictionary, z: float) -> float:
	var y := float(d["bottom"])
	y += 0.06 * smoothstep(float(d["front"]) + 0.5, float(d["front"]), z)
	y += 0.05 * smoothstep(float(d["rear"]) - 0.5, float(d["rear"]), z)
	var a := float(d["axle_front"])
	var r := float(d["arch"])
	var axle_y := float(d["ground_y"]) + float(d["wheel_r"])
	if r > 0.0 and absf(z - a) < r:
		y = maxf(y, axle_y + sqrt(r * r - (z - a) * (z - a)))
	return y


## One side's outer points at z, bottom to top (x for the left side; mirror for the right): rocker, side, shoulder,
## the top's outer edge, middle and inner edge.
static func _side_points(d: Dictionary, z: float) -> Array[Vector2]:
	var w := half_width(d, z)
	var b := belt(d, z)
	var lo := bottom(d, z)
	var fin := fin_rise(d, z)
	# The fin narrows to a blade as it rises.
	var o6 := lerpf(0.11, 0.07, fin)
	var o7 := lerpf(0.17, 0.1, fin)
	var arch := lo > float(d["bottom"]) + 0.08
	return [Vector2(-(w - (0.03 if arch else 0.07)), lo), Vector2(-(w - 0.01), lo + (0.025 if arch else 0.06)),
			Vector2(-w, lerpf(lo, b, 0.45)), Vector2(-(w - 0.004), b - 0.1), Vector2(-(w - 0.022), b - 0.03),
			Vector2(-(w - 0.05), b - 0.004), Vector2(-(w - o6), b + 0.002), Vector2(-(w - o7), b - 0.012)]


## A full cross-section at z, left bottom over the top to right bottom (SECTION_POINTS points): the sides, a gutter
## inside each wing, the bonnet's or the deck's crown. open: none inside the cabin (the caller asks only outside it).
static func section(d: Dictionary, z: float) -> PackedVector3Array:
	var side := _side_points(d, z)
	var w := half_width(d, z)
	var c := crown(d, z)
	var b := belt(d, z)
	var fin := fin_rise(d, z)
	# The gutter between the wing and the bonnet (ahead), or the fin's foot on the deck (behind).
	var gutter := Vector2(-(w - lerpf(0.24, 0.16, fin)), lerpf(c - 0.03, c + 0.012, fin) if z > float(d["cowl"])
			else minf(c - 0.03, b - 0.05))
	var pts: Array[Vector2] = []
	pts.append_array(side)
	pts.append(gutter)
	pts.append(Vector2(-0.48, c - 0.02))
	pts.append(Vector2(-0.24, c - 0.005))
	var out := PackedVector3Array()
	for p: Vector2 in pts:
		out.append(Vector3(p.x, p.y, z))
	out.append(Vector3(0.0, c, z))
	for k in range(pts.size() - 1, -1, -1):
		out.append(Vector3(-pts[k].x, pts[k].y, z))
	return out


## A side of the open cabin at z (sign -1 left, 1 right), bottom to the inner lip of the door's top (10 points), its
## outer points the full section's.
static func cabin_side(d: Dictionary, z: float, sign_x: float) -> PackedVector3Array:
	var side := _side_points(d, z)
	var inner := float(d["inner"])
	var b := belt(d, z)
	var out := PackedVector3Array()
	for p: Vector2 in side:
		out.append(Vector3(p.x if sign_x < 0.0 else -p.x, p.y, z))
	out.append(Vector3(sign_x * (inner + 0.004), b - 0.018, z))
	out.append(Vector3(sign_x * inner, b - 0.075, z))
	if sign_x > 0.0:
		out.reverse()
	return out


## Stations along the body: close together round the front wheel's arch and where the lines turn, always including
## the cowl and the cabin's back (the joins).
static func stations(d: Dictionary, z0: float, z1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var z := z0
	var a := float(d["axle_front"])
	var r := float(d["arch"])
	var front := float(d["front"])
	var rear := float(d["rear"])
	# A coarse body (cars parked further off): three times the steps.
	var k := 3.0 if bool(d.get("coarse", false)) else 1.0
	while z < z1 - 0.005:
		out.append(z)
		var step := 0.16
		if absf(z - a) < r + 0.08:
			step = 0.045
		elif z < front + 0.45 or z > rear - 0.35:
			step = 0.05
		elif z > float(d["cabin_back"]):
			step = 0.1
		z = minf(z + step * k, z1)
	out.append(z1)
	return out


# --- Building ------------------------------------------------------------------------------------------------------

## Normals for a grid of points (rows along z, points across): from the neighbours, turned outward (away from the
## body's middle line at the given height).
static func _normals(rows: Array, mid_y: float) -> Array:
	var out: Array = []
	var h := rows.size()
	for i in h:
		var row: PackedVector3Array = rows[i]
		var w := row.size()
		var nrow := PackedVector3Array()
		nrow.resize(w)
		for j in w:
			var along: Vector3 = (rows[mini(i + 1, h - 1)] as PackedVector3Array)[j] \
					- (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
			var across: Vector3 = row[mini(j + 1, w - 1)] - row[maxi(j - 1, 0)]
			var n := across.cross(along)
			if n.length_squared() < 1e-12:
				n = Vector3(row[j].x, row[j].y - mid_y, 0.0)
			n = n.normalized()
			var guess := Vector3(row[j].x, row[j].y - mid_y, 0.0)
			if n.dot(guess) < 0.0:
				n = -n
			nrow[j] = n
		out.append(nrow)
	return out


## Colours for a grid: every point one colour.
static func _flat_colours(rows: Array, c: Color) -> Array:
	var out: Array = []
	for row: PackedVector3Array in rows:
		var cr := PackedColorArray()
		cr.resize(row.size())
		cr.fill(c)
		out.append(cr)
	return out


## The shell: ahead of the cabin and behind it the full sections; along an open cabin the two sides only (a closed
## car's lid at the belt instead, dark). The ends closed behind the bumpers. Wheel wells dark.
static func body(b: RoomMesh, d: Dictionary, paint: Color, trim: Color, dark: Color, chrome_b: RoomMesh,
		open: bool) -> void:
	var mid := (float(d["bottom"]) + float(d["belt"])) * 0.5
	var cowl := float(d["cowl"])
	var back := float(d["cabin_back"])
	var parts: Array = []
	if open:
		parts.append(stations(d, float(d["front"]), cowl))
		parts.append(stations(d, back, float(d["rear"])))
	else:
		parts.append(stations(d, float(d["front"]), float(d["rear"])))
	for zs: PackedFloat32Array in parts:
		var rows: Array = []
		for z in zs:
			rows.append(section(d, z))
		var cols := _flat_colours(rows, paint)
		if not open:
			# The closed car's lid over the cabin: dark (the inside, seen through the glass).
			for i in rows.size():
				var z := zs[i]
				if z > cowl + 0.05 and z < back - 0.05:
					var cr: PackedColorArray = cols[i]
					for j in range(8, SECTION_POINTS - 8):
						cr[j] = dark
		b.grid(rows, _normals(rows, mid), cols)
		_cap(b, rows[0], Vector3.FORWARD, paint)
		_cap(b, rows[rows.size() - 1], Vector3.BACK, paint)
	if open:
		for s: float in [-1.0, 1.0]:
			var rows: Array = []
			for z in stations(d, cowl, back):
				rows.append(cabin_side(d, z, s))
			b.grid(rows, _normals(rows, mid), _flat_colours(rows, paint))
	_spear(b, d, trim, chrome_b)
	_wells(b, d, dark)
	_bumpers(chrome_b, d)


## A section's end closed (a fan from its middle), behind the grille or the bumper.
static func _cap(b: RoomMesh, row: PackedVector3Array, normal: Vector3, c: Color) -> void:
	var centre := Vector3.ZERO
	for p in row:
		centre += p
	centre /= row.size()
	var keep := b.colour
	b.colour = c
	for k in row.size() - 1:
		b.face([centre, row[k], row[k + 1]], normal)
	b.face([centre, row[row.size() - 1], row[0]], normal)
	b.colour = keep


## A point on the body's side at z and height y (the side's points interpolated), a little proud of it.
static func side_at(d: Dictionary, z: float, y: float, sign_x: float, proud := 0.004) -> Array:
	var pts := _side_points(d, z)
	for k in range(1, 6):
		if y <= pts[k].y or k == 5:
			var a := pts[k - 1]
			var c := pts[k]
			var t := clampf((y - a.y) / maxf(c.y - a.y, 0.0001), 0.0, 1.0)
			var p := a.lerp(c, t)
			var tangent := (c - a).normalized()
			var n := Vector2(-tangent.y, tangent.x)
			if n.x > 0.0:
				n = -n
			var at := Vector3(p.x, p.y, z) + Vector3(n.x, n.y, 0.0) * proud
			var nn := Vector3(n.x, n.y, 0.0).normalized()
			if sign_x > 0.0:
				at.x = -at.x
				nn.x = -nn.x
			return [at, nn]
	return [Vector3.ZERO, Vector3.RIGHT]


## The spear: a sweep in the second colour along each side, narrow on the front wing, widening to the fin, edged
## with chrome beads.
static func _spear(b: RoomMesh, d: Dictionary, trim: Color, chrome_b: RoomMesh) -> void:
	var z0 := float(d["front"]) + 0.55
	var z1 := float(d["rear"]) - 0.12
	var coarse := bool(d.get("coarse", false))
	var n := 12 if coarse else 40
	for s: float in [-1.0, 1.0]:
		var rows: Array = []
		var norms: Array = []
		var top_line := PackedVector3Array()
		var low_line := PackedVector3Array()
		for k in n + 1:
			var t := float(k) / n
			var z := lerpf(z0, z1, t)
			var bl := belt(d, z)
			var hi := bl - 0.075 - 0.02 * fin_rise(d, z)
			var width := lerpf(0.012, 0.15, pow(smoothstep(0.0, 0.85, t), 1.3))
			var lo := hi - width
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			for y: float in [lo, (lo + hi) * 0.5, hi]:
				var at: Array = side_at(d, z, y, s)
				row.append(at[0])
				nrow.append(at[1])
			rows.append(row)
			norms.append(nrow)
			top_line.append((side_at(d, z, hi + 0.004, s, 0.008)[0]))
			low_line.append((side_at(d, z, lo - 0.004, s, 0.008)[0]))
		b.grid(rows, norms, _flat_colours(rows, trim))
		if coarse:
			continue
		for line: PackedVector3Array in [top_line, low_line]:
			for k in line.size() - 1:
				Shapes.beam(chrome_b, line[k], line[k + 1], Vector2(0.012, 0.008), Vector3(s, 0, 0))


## The front wheel's well: a dark half drum inside the arch.
static func _wells(b: RoomMesh, d: Dictionary, dark: Color) -> void:
	var a := float(d["axle_front"])
	var r := float(d["arch"]) - 0.01
	if r <= 0.0:
		return
	var axle_y := float(d["ground_y"]) + float(d["wheel_r"])
	var keep := b.colour
	b.colour = dark
	for s: float in [-1.0, 1.0]:
		var w := half_width(d, a)
		var rows: Array = []
		var norms: Array = []
		for x: float in [s * (w - 0.3), s * (w - 0.02)]:
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			for k in 13:
				var ang := PI * float(k) / 12.0
				var p := Vector3(x, axle_y + sin(ang) * r, a - cos(ang) * r)
				row.append(p)
				nrow.append(-Vector3(0, sin(ang), -cos(ang)))
			rows.append(row)
			norms.append(nrow)
		b.grid(rows, norms)
	b.colour = keep


## The bumpers: bent bars across both ends, round the corners.
static func _bumpers(c: RoomMesh, d: Dictionary) -> void:
	var front := float(d["front"])
	var rear := float(d["rear"])
	var w := float(d["half"])
	var coarse := bool(d.get("coarse", false))
	var steps := 1 if coarse else 2
	var inner := Vector3i(2 if coarse else 6, 0, 0)
	c.rounded_box(Vector3(0, -0.02, front - 0.02), Vector3(w * 2.0 + 0.06, 0.15, 0.14), 0.055, Transform3D(), steps,
			inner, 0.075)
	c.rounded_box(Vector3(0, 0.0, rear + 0.04), Vector3(w * 2.0 + 0.04, 0.14, 0.13), 0.05,
			Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), steps, inner, 0.07)
	if coarse:
		c.box(Vector3(0, 0.25, front - 0.005), Vector3(1.1, 0.2, 0.02))
		return
	# Over-riders, and the grille's bars between the headlamps.
	for s: float in [-1.0, 1.0]:
		c.rounded_box(Vector3(s * 0.42, 0.06, front - 0.09), Vector3(0.09, 0.2, 0.1), 0.04, Transform3D(), 1)
	for k in 4:
		c.rounded_box(Vector3(0, 0.16 + k * 0.065, front - 0.005), Vector3(1.15, 0.022, 0.03), 0.009,
				Transform3D(), 1, Vector3i(3, 0, 0), 0.05)


## Tyres with whitewalls, full hub caps, under the arch and the skirt.
static func wheels(b: RoomMesh, c: RoomMesh, d: Dictionary, tyre: Color, wall: Color) -> void:
	var r := float(d["wheel_r"])
	var axle_y := float(d["ground_y"]) + r
	var side := Basis(Vector3.FORWARD, PI * 0.5)
	var n := 10 if bool(d.get("coarse", false)) else 18
	for z: float in [float(d["axle_front"]), float(d["axle_rear"])]:
		for s: float in [-1.0, 1.0]:
			var at := Vector3(s * (float(d["half"]) - 0.13), axle_y, z)
			var turn := side if s > 0.0 else side * Basis(Vector3.RIGHT, PI)
			var keep := b.colour
			b.colour = tyre
			Shapes.lathe(b, [Vector2(r - 0.12, -0.105), Vector2(r - 0.02, -0.11), Vector2(r, -0.08),
					Vector2(r, 0.08), Vector2(r - 0.02, 0.105)], at, n, turn)
			b.colour = wall
			Shapes.lathe(b, [Vector2(r - 0.025, 0.106), Vector2(r - 0.095, 0.108)], at, n, turn)
			b.colour = tyre
			Shapes.lathe(b, [Vector2(r - 0.095, 0.108), Vector2(r - 0.12, 0.1)], at, n, turn)
			b.colour = keep
			Shapes.lathe(c, [Vector2(r - 0.12, 0.1), Vector2(0.15, 0.12), Vector2(0.06, 0.135), Vector2(0.0, 0.14)],
					at, n - 2, turn)


## A hardtop's glasshouse (the parked cars): the windscreen raked back from the cowl, a flat roof, the back window
## down to the deck, the side windows; glass dark (its own colour), the roof in `roof`, thin pillars in it too.
static func glasshouse(b: RoomMesh, d: Dictionary, glass: Color, roof: Color) -> void:
	var cowl := float(d["cowl"])
	var back := float(d["cabin_back"])
	var roof_y := float(d["belt"]) + 0.52
	var roof_front := cowl + 0.62
	var roof_back := back - 0.55
	var zs := PackedFloat32Array([cowl + 0.02, cowl + 0.25, roof_front - 0.06, roof_front, roof_back,
			roof_back + 0.06, back - 0.25, back - 0.02])
	var rows: Array = []
	var cols: Array = []
	var norms: Array = []
	for z in zs:
		var bl := belt(d, z)
		var h: float
		if z < roof_front:
			h = lerpf(bl + 0.01, roof_y, smoothstep(cowl, roof_front, z))
		elif z > roof_back:
			h = lerpf(roof_y, bl + 0.01, smoothstep(roof_back, back, z))
		else:
			h = roof_y
		var wl := half_width(d, z) - 0.11
		var wh := wl - 0.12 * clampf((h - bl) / 0.5, 0.0, 1.0)
		var row := PackedVector3Array([Vector3(-wl, bl, z), Vector3(-wh, h, z), Vector3(-wh, h, z),
				Vector3(-wh * 0.5, h + 0.025, z), Vector3(0, h + 0.03, z), Vector3(wh * 0.5, h + 0.025, z),
				Vector3(wh, h, z), Vector3(wh, h, z), Vector3(wl, bl, z)])
		var top := z >= roof_front - 0.001 and z <= roof_back + 0.001
		var c_top := roof if top else glass
		var cr := PackedColorArray([glass, glass, c_top, c_top, c_top, c_top, c_top, glass, glass])
		rows.append(row)
		cols.append(cr)
	norms = _normals(rows, float(d["belt"]))
	b.grid(rows, norms, cols)
	# The pillars: a band of roof colour up the side at the windscreen's and the back window's edges.
	var keep := b.colour
	b.colour = roof
	for s: float in [-1.0, 1.0]:
		for pair: Array in [[cowl + 0.02, roof_front], [roof_back, back - 0.02]]:
			var za := float(pair[0])
			var zb := float(pair[1])
			var a0 := Vector3(s * (half_width(d, za) - 0.105), belt(d, za) + 0.005, za)
			var a1 := Vector3(s * (half_width(d, zb) - 0.105 - 0.12), roof_y, zb)
			Shapes.beam(b, a0, a1, Vector2(0.05, 0.04), Vector3(s, 0, 0))
	b.colour = keep
