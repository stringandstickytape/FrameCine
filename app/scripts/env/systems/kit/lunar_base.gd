extends RefCounted

## Inside the Crater's dome (terrace.gd's amphitheatre with `lunar` on; since 2026-11-08, the Crater's quality pass:
## "Better to do a smaller number of incredible superb ones than a large number not so", the user, 2026-11-08). The
## amphitheatre made as a Moon base would make it, at the distances it is seen from its own seats:
##   Floor      hexagonal pavers of sintered regolith in dark joints (procedural.gd hex_pavers), the whole round of the
##              dome (its glass stands on its drum at the floor's edge)
##   Tiers      precast blocks of sintered regolith, about two metres a block, each its own shade where they butt
##              (the joint shows as the change), a chamfered nose; under each nose a warm strip of light that washes
##              the tread in front (the steps group: the light shows, the strip hides under the nose)
##   Seats      a pad on the tread at every seat and a back pad on the riser behind it, in a slate fabric
##   Stairs     a flight up each end of the tiers, two steps a tier, a small warm light in each riser, a steel handrail;
##              a guard rail along the back of the top tier (there is a drop behind it)
##   Stage      a low plinth of the same blocks under the screen, a line of warm footlights along its nose (the stage
##              group); two tapered pylons either side carry the screen's frame on steel brackets, a slot of cool light
##              up each (the house group: out in the film)
## The light in the bake: Earth's light through the glass (from Earth's place: tiers shade each other), the strips', the
## footlights' and the stairs' lamps. Static; preload to use. `t` is the terrace system, `p` its parameters.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")

## Sintered regolith (linear-ish sRGB colours), the pavers, the pads' slate, the lights.
const BLOCK := Color(0.4, 0.385, 0.365)
const FLOOR := Color(0.3, 0.29, 0.27)
const PAD := Color(0.16, 0.19, 0.24)
const WARM := Color(1.0, 0.68, 0.38)
const COOL := Color(0.75, 0.85, 1.0)
## A block's length along its tier (about), the nose's chamfer.
const BLOCK_LEN := 2.0
const CHAMFER := 0.03
## The stairs' width, the stage's size (across, deep, high), the pylons' (across at the foot, deep).
const STAIR_W := 1.15
const STAGE := Vector3(12.0, 0.45, 1.7)
const PYLON := Vector2(0.8, 1.0)


## The stage's and the pylons' boxes for object physics (from parameters alone): [[centre, size], ...].
static func collision_boxes(sc: Dictionary, gy: float) -> Array:
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	var size := Vector2(float(sc["size"][0]), float(sc["size"][1]))
	var out: Array = []
	out.append([Vector3(0, gy + STAGE.y * 0.5, c.z - 0.25), STAGE])
	var top := c.y + size.y * 0.5 + 0.9
	for s: float in [-1.0, 1.0]:
		var x := s * (size.x * 0.5 + 0.3 + PYLON.x * 0.5)
		out.append([Vector3(x, (gy + STAGE.y + top) * 0.5, c.z - 0.6), Vector3(PYLON.x, top - gy - STAGE.y, PYLON.y)])
	return out


## Everything inside. dome: {centre, radius} of the dome over it (its floor's round). earth: the direction to Earth.
static func build(t: Object, p: Dictionary, gy: float, dome: Dictionary, earth: Vector3) -> void:
	var light: Node = t.get("_light")
	var block: ShaderMaterial = light.library("smooth_concrete", BLOCK, {"tiling": 0.7})
	block.set_shader_parameter("instance_tint", true)
	var paving: ShaderMaterial = light.library("smooth_concrete", FLOOR, {"tiling": 0.55})
	Procedural.apply(paving, "hex_pavers", FLOOR)
	var steel: ShaderMaterial = light.library("brushed_steel", Color(0.62, 0.62, 0.64), {"tiling": 0.5})
	var dark: ShaderMaterial = light.library("dark_metal", Color(0.09, 0.09, 0.1))
	var pads: ShaderMaterial = light.library("melange_fabric", PAD, {"tiling": 0.35}, true)
	pads.set_shader_parameter("instance_tint", true)
	var strips: ShaderMaterial = t._lamp(WARM, 1.6, 0.0, "steps")
	var foot: ShaderMaterial = t._lamp(WARM, 1.3, 0.0, "stage")
	var slots: ShaderMaterial = t._lamp(COOL, 0.6, 1.0, "house")
	# The floor.
	var fl := RoomMesh.new()
	fl.surface(paving)
	var dc: Vector3 = dome["centre"]
	var dr := float(dome["radius"]) - 0.02
	var disc: Array = []
	for k in 72:
		var a := -TAU * k / 72.0
		disc.append(Vector3(dc.x + sin(a) * dr, gy, dc.z + cos(a) * dr))
	fl.face(disc, Vector3.UP)
	t._add_static("Floor", fl)
	# The tiers, the stairs, the stage and the pylons: one mesh of blocks; the strips and the lamps.
	var b := RoomMesh.new()
	b.surface(block)
	var glow := RoomMesh.new()
	glow.surface(strips)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1969
	_tiers(t, p, gy, b, glow, rng)
	var sc: Dictionary = t.screen_for(p)
	var steel_b := RoomMesh.new()
	steel_b.surface(steel)
	_stairs(t, p, gy, b, glow, steel_b, rng)
	var foot_b := RoomMesh.new()
	foot_b.surface(foot)
	var slot_b := RoomMesh.new()
	slot_b.surface(slots)
	var frame_b := RoomMesh.new()
	frame_b.surface(dark)
	_stage(sc, gy, b, foot_b, slot_b, frame_b, steel_b, rng)
	t._add_static("Tiers", b)
	t._add_unbaked("Steel", steel_b)
	t._add_static("ScreenFrame", frame_b)
	t._add_lamps("StepLights", glow)
	t._add_lamps("Footlights", foot_b)
	t._add_lamps("PylonLights", slot_b)
	# The pads, unbaked (rounded, smooth): lit by the fill, the film and the lamps.
	var pb := RoomMesh.new()
	pb.surface(pads)
	_pads(t, p, pb, rng)
	t._add_unbaked("Pads", pb)
	# The light for the bake: Earth's, through the glass; the lamps' pools.
	var e := DirectionalLight3D.new()
	e.name = "Earthlight"
	e.light_color = Color(0.66, 0.76, 1.0)
	e.light_energy = 0.45
	e.light_angular_distance = 2.0
	e.transform = Transform3D(Basis.looking_at(-earth, Vector3.UP), Vector3.ZERO)
	light.add_bake_light(e)
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	for s: float in [-1.0, 1.0]:
		t._bake_omni("Footlight", Vector3(s * 3.0, gy + 0.35, c.z + 0.9), 3.5, 0.5, WARM)


## A strip of quads along an arc round `foot` (radius r0 at height y0 to radius r1 at height y1) from angle a0 to a1,
## `steps` quads along: one chart. Normal: n_out (outward, by its radial share) and up.
static func _arc_strip(b: RoomMesh, foot: Vector3, a0: float, a1: float, steps: int, r0: float, y0: float, r1: float,
		y1: float, n_radial: float, n_up: float) -> void:
	var la := PackedVector3Array()
	var lb := PackedVector3Array()
	var ns := PackedVector3Array()
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		var dir := Vector3(sin(a), 0, cos(a))
		la.append(foot + dir * r0 + Vector3.UP * y0)
		lb.append(foot + dir * r1 + Vector3.UP * y1)
		ns.append((dir * n_radial + Vector3.UP * n_up).normalized())
	b.strip(la, lb, ns)


## The tiers: blocks along each arc, each its own shade, a joint between them; the nose's strip of light.
static func _tiers(t: Object, p: Dictionary, gy: float, b: RoomMesh, glow: RoomMesh, rng: RandomNumberGenerator) -> void:
	var half := deg_to_rad(float(p["arc_deg"])) * 0.5
	var foot := Vector3(0, 0, t._screen_z(p))
	var tiers: Array = t._tiers(p)
	for i in tiers.size():
		var r: float = tiers[i][0]
		var y: float = tiers[i][1]
		var d: float = tiers[i][2]
		var below: float = float(tiers[i + 1][1]) if i + 1 < tiers.size() else gy
		var rf := r - d * 0.5
		var rb := r + d * 0.5
		var n := maxi(int(round(r * half * 2.0 / BLOCK_LEN)), 3)
		for k in n:
			var a0 := lerpf(-half, half, float(k) / n)
			var a1 := lerpf(-half, half, float(k + 1) / n)
			var v := rng.randf_range(0.86, 1.0)
			var warm := rng.randf_range(-0.025, 0.025)
			b.colour = Color(v * (1.0 + warm), v, v * (1.0 - warm))
			# The tread, the chamfer, the riser down to the tier in front (or the floor).
			_arc_strip(b, foot, a0, a1, 3, rf + CHAMFER, y, rb, y, 0.0, 1.0)
			_arc_strip(b, foot, a0, a1, 3, rf, y - CHAMFER, rf + CHAMFER, y, -1.0, 1.0)
			_arc_strip(b, foot, a0, a1, 3, rf, below, rf, y - CHAMFER, -1.0, 0.0)
			if i == 0:
				_arc_strip(b, foot, a0, a1, 3, rb, y, rb, gy, 1.0, 0.0)
			# The tier's ends, down to the floor (the blocks butt, each its own shade: the joint shows as the change).
			for e: Array in ([[a0, -1.0]] if k == 0 else []) + ([[a1, 1.0]] if k == n - 1 else []):
				var a: float = e[0]
				var dir := Vector3(sin(a), 0, cos(a))
				var side := Vector3(cos(a), 0, -sin(a)) * float(e[1])
				var lo := gy
				b.face([foot + dir * rf + Vector3.UP * lo, foot + dir * rb + Vector3.UP * lo,
						foot + dir * rb + Vector3.UP * y, foot + dir * rf + Vector3.UP * y], side)
		b.colour = Color.WHITE
		# The strip under the nose: a thin line of light on the riser's top, the length of the tier.
		var inset := deg_to_rad(0.6)
		_arc_strip(glow, foot, -half + inset, half - inset, maxi(n * 3, 6), rf - 0.004, y - CHAMFER - 0.035,
				rf - 0.004, y - CHAMFER - 0.012, -1.0, 0.0)


## The stairs up each end of the tiers (two steps a tier), a light in each riser, the handrail; the guard rail along
## the back of the top tier.
static func _stairs(t: Object, p: Dictionary, gy: float, b: RoomMesh, glow: RoomMesh, steel: RoomMesh,
		rng: RandomNumberGenerator) -> void:
	var half := deg_to_rad(float(p["arc_deg"])) * 0.5
	var foot := Vector3(0, 0, t._screen_z(p))
	var tiers: Array = t._tiers(p)
	if tiers.is_empty():
		return
	var d: float = tiers[0][2]
	var rise := float(p["tier_rise"]) * 0.5
	for s: float in [-1.0, 1.0]:
		var a := s * half
		var dir := Vector3(sin(a), 0, cos(a))
		var out := Vector3(cos(a), 0, -sin(a)) * s
		var rail_pts: Array[Vector3] = []
		# From the front tier back: each tier's two steps (the first half its tier's top less half a rise).
		for i in range(tiers.size() - 1, -1, -1):
			var r: float = tiers[i][0]
			var y: float = tiers[i][1]
			for h in 2:
				var r0 := r - d * 0.5 + h * d * 0.5
				var r1 := r0 + d * 0.5
				var top := y - rise * (1 - h)
				var c0 := foot + dir * r0 + out * 0.012
				var c1 := foot + dir * r1 + out * 0.012
				var o0 := c0 + out * STAIR_W
				var o1 := c1 + out * STAIR_W
				var v := rng.randf_range(0.88, 1.0)
				b.colour = Color(v, v, v)
				b.face([c0 + Vector3.UP * top, o0 + Vector3.UP * top, o1 + Vector3.UP * top, c1 + Vector3.UP * top],
						Vector3.UP)
				var low := top - rise
				b.face([c0 + Vector3.UP * gy, o0 + Vector3.UP * gy, o0 + Vector3.UP * top, c0 + Vector3.UP * top]
						if h == 0 and i == tiers.size() - 1 else [c0 + Vector3.UP * low, o0 + Vector3.UP * low,
						o0 + Vector3.UP * top, c0 + Vector3.UP * top], -dir)
				b.face([o0 + Vector3.UP * gy, o1 + Vector3.UP * gy, o1 + Vector3.UP * top, o0 + Vector3.UP * top], out)
				b.colour = Color.WHITE
				# The riser's light, low in its middle.
				var lc := (c0 + o0) * 0.5 + Vector3.UP * (top - 0.07) - dir * 0.004
				Shapes.quad(glow, lc, out * 0.12, Vector3.UP * 0.016, -dir)
				rail_pts.append((o0 + o1) * 0.5 - out * 0.08 + Vector3.UP * top)
			if i == 0:
				# The top's back.
				var c1 := foot + dir * (float(tiers[0][0]) + d * 0.5) + out * 0.012
				b.face([c1 + Vector3.UP * gy, c1 + out * STAIR_W + Vector3.UP * gy,
						c1 + out * STAIR_W + Vector3.UP * float(tiers[0][1]), c1 + Vector3.UP * float(tiers[0][1])], dir)
		# The handrail: posts at every other step, a rail 0.9 m over the nosings.
		for k in rail_pts.size():
			if k % 2 == 0 or k == rail_pts.size() - 1:
				_tube(steel, rail_pts[k], rail_pts[k] + Vector3.UP * 0.92, 0.022, 6)
		for k in rail_pts.size() - 1:
			_tube(steel, rail_pts[k] + Vector3.UP * 0.9, rail_pts[k + 1] + Vector3.UP * 0.9, 0.024, 8)
	# The guard rail behind the top tier: posts every two metres or so, a top rail and a middle rail on the arc.
	var rt: float = tiers[0][0] + d * 0.5 - 0.06
	var yt: float = tiers[0][1]
	var posts := maxi(int(rt * half * 2.0 / 2.0), 2)
	for k in posts + 1:
		var a := lerpf(-half, half, float(k) / posts)
		var q := foot + Vector3(sin(a), 0, cos(a)) * rt + Vector3.UP * yt
		_tube(steel, q, q + Vector3.UP * 1.0, 0.025, 6)
	for y: float in [0.98, 0.5]:
		Shapes.lathe(steel, [Vector2(rt - 0.022, yt + y - 0.022), Vector2(rt + 0.022, yt + y - 0.022),
				Vector2(rt + 0.022, yt + y + 0.022), Vector2(rt - 0.022, yt + y + 0.022),
				Vector2(rt - 0.022, yt + y - 0.022)], foot, posts * 3, Basis(), half * 2.0, -half)


## A round tube from a to c (a rail, a post).
static func _tube(b: RoomMesh, a: Vector3, c: Vector3, radius: float, sides: int) -> void:
	var y := (c - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	Shapes.cylinder(b, a, radius, a.distance_to(c), sides, Basis(x, y, z), false)


## The stage under the screen and its footlights; the pylons, their slots of light, the frame on its brackets.
static func _stage(sc: Dictionary, gy: float, b: RoomMesh, foot: RoomMesh, slot: RoomMesh, frame: RoomMesh,
		steel: RoomMesh, rng: RandomNumberGenerator) -> void:
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	var size := Vector2(float(sc["size"][0]), float(sc["size"][1]))
	var st := Vector3(0, gy + STAGE.y * 0.5, c.z - 0.25)
	b.colour = Color(0.94, 0.94, 0.94)
	b.box(st, STAGE, Basis(), [RoomMesh.DOWN])
	# The nose: a reveal under its lip, the footlights in it.
	var front := st.z + STAGE.z * 0.5
	for k in 16:
		var x := lerpf(-STAGE.x * 0.5 + 0.6, STAGE.x * 0.5 - 0.6, k / 15.0)
		Shapes.quad(foot, Vector3(x, gy + STAGE.y - 0.06, front + 0.004), Vector3(0.09, 0, 0), Vector3(0, 0.012, 0),
				Vector3.BACK)
	# The pylons: tapered, standing on the stage, their tops over the frame's.
	var top := c.y + size.y * 0.5 + 0.9
	var base_y := gy + STAGE.y
	for s: float in [-1.0, 1.0]:
		var x := s * (size.x * 0.5 + 0.3 + PYLON.x * 0.5)
		var zc := c.z - 0.6
		var w0 := PYLON.x * 0.5
		var w1 := PYLON.x * 0.36
		var d0 := PYLON.y * 0.5
		var d1 := PYLON.y * 0.4
		var v := rng.randf_range(0.9, 1.0)
		b.colour = Color(v, v, v)
		var lo: Array[Vector3] = [Vector3(x - w0, base_y, zc - d0), Vector3(x + w0, base_y, zc - d0),
				Vector3(x + w0, base_y, zc + d0), Vector3(x - w0, base_y, zc + d0)]
		var hi: Array[Vector3] = [Vector3(x - w1, top, zc - d1), Vector3(x + w1, top, zc - d1),
				Vector3(x + w1, top, zc + d1), Vector3(x - w1, top, zc + d1)]
		for k in 4:
			var j := (k + 1) % 4
			var nrm := ((lo[j] - lo[k]).cross(hi[k] - lo[k])).normalized()
			if nrm.dot(Vector3(lo[k].x + lo[j].x - 2.0 * x, 0, lo[k].z + lo[j].z - 2.0 * zc)) < 0.0:
				nrm = -nrm
			b.face([lo[k], lo[j], hi[j], hi[k]], nrm)
		b.face(hi, Vector3.UP)
		b.colour = Color.WHITE
		# A slot of cool light up the pylon's face towards the room, out in the film.
		# Its upper part only: a short line of light high on the face, not a bar beside the picture.
		var tilt := atan2(d0 - d1, top - base_y)
		var my := top - 1.2
		var fz := zc + d0 - (d0 - d1) * (my - base_y) / (top - base_y) + 0.004
		var mid := Vector3(x, my, fz)
		Shapes.quad(slot, mid, Vector3(0.025, 0, 0), Vector3(0, 0.75, -0.75 * tan(tilt)),
				Vector3(0, sin(tilt), cos(tilt)).normalized())
		# The brackets: two steel arms from the pylon's inner face to the frame's edge.
		for y: float in [c.y - size.y * 0.35, c.y + size.y * 0.35]:
			var from := Vector3(x - s * w0 * 0.8, y, zc)
			var to := Vector3(s * (size.x * 0.5 + 0.2), y, c.z - 0.2)
			Shapes.beam(steel, from, to, Vector2(0.08, 0.12))
	# The frame: the dark panel round the picture (as the plain frame's), a little thicker.
	frame.box(Vector3(c.x, c.y, c.z - 0.15), Vector3(size.x + 0.6, size.y + 0.6, 0.14))


## A pad on every seat's tread and a back pad on the riser behind it (none on the top tier: its rail is behind).
static func _pads(t: Object, p: Dictionary, b: RoomMesh, rng: RandomNumberGenerator) -> void:
	var foot := Vector3(0, 0, t._screen_z(p))
	var tiers: Array = t._tiers(p)
	var d := float(p["row_pitch"])
	var top_y: float = tiers[0][1] if not tiers.is_empty() else 0.0
	for s: Dictionary in t.seat_slots_for(p):
		var o: Vector3 = (s["transform"] as Transform3D).origin
		var fwd := (foot - o) * Vector3(1, 0, 1)
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		var xf := Basis(side, Vector3.UP, -fwd)
		var v := rng.randf_range(0.88, 1.05)
		b.colour = Color(v, v, v * rng.randf_range(0.97, 1.03))
		b.rounded_box(Vector3.ZERO, Vector3(0.5, 0.06, 0.44), 0.025,
				Transform3D(xf, o + fwd * 0.06 + Vector3.UP * 0.03), 1)
		if o.y < top_y - 0.1:
			b.rounded_box(Vector3.ZERO, Vector3(0.46, 0.3, 0.05), 0.02,
					Transform3D(xf, o - fwd * (d * 0.5 - 0.035) + Vector3.UP * 0.25), 1)
	b.colour = Color.WHITE
