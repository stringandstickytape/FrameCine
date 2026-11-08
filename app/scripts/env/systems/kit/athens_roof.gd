extends RefCounted

## The Athens rooftop's summer cinema (terrace.gd's rooftop with `city` on; since 2026-11-08, the room's quality pass:
## "Better to do a smaller number of incredible superb ones than a large number not so", the user, 2026-11-08). The
## terrace itself, made to be looked at from its own chairs; the city round it is kit/athens_city.gd.
##   Floor      terracotta tiles in grey grout (procedural.gd quarry_tiles), each its own shade; dirt along the walls,
##              the aisles a little worn, a stain under the kiosk's counter (vertex colours, baked)
##   Parapet    a whitewashed wall with real thickness, its coping laid in separate stones, the splash of rain dark at
##              its foot, streaks and chips; drain spouts
##   Wall       the next building's blind wall: rendered plaster gone ochre, rain streaks from its top, the ghost of a
##              house that once stood against it (its gable's line, two rooms' old paint), patches of newer render,
##              two painted signs of long ago in Greek (pastiche: a coffee, a soap), a drainpipe, an iron ladder down
##              its edge, a loudspeaker either side of the picture; the screen painted on it in white with a matte
##              black border
##   Hut        the projection hut at the back: whitewashed, a blue door, its two ports glowing towards the screen
##              (the booth group), a lamp in a cage over the door, a vent on its roof, jasmine up its corner
##   Kiosk      the bar in the back corner (ΚΥΛΙΚΕΙΟ, the canteen, painted over it): a counter, shelves of bottles, a
##              fridge's glow, a striped awning, a bulb inside (the accent group)
##   Plants     bougainvillea in three masses over the right parapet from big pots, geraniums in old oil tins, a lemon
##              tree in its pot in the corner, basil on the counter (leaves unbaked, in their vertex colours)
##   Bulbs      strings of warm bulbs sagging between steel poles clamped to the parapets, across the back and to the
##              hut and the kiosk; each with a soft halo (the house group: the ritual takes them down)
## No people, no mark of anyone's. Static; preload to use. `t` is the terrace system.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Strokes := preload("res://scripts/env/systems/kit/strokes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const AthensCity := preload("res://scripts/env/systems/kit/athens_city.gd")
const HALO_SHADER := preload("res://shaders/env_halo.gdshader")

## The bulbs' warm glow, the poles' height, the gap between bulbs on a string.
const BULB := Color(1.0, 0.7, 0.4)
const POLE_H := 3.3
const BULB_STEP := 0.55
## The hut and the kiosk, from the terrace's back edge (bz) and side (hw): [x0, x1, depth from the back, height].
const HUT := [-1.6, 1.6, 2.7, 2.7]
const KIOSK_W := 2.9
const KIOSK_D := 3.0
const KIOSK_H := 2.6
## The kiosk's name, painted over its counter (the Greek word for a canteen; no one's name).
const KIOSK_SIGN := "ΚΥΛΙΚΕΙΟ"
## The poles along each side (z), and where the bougainvillea grows over the right parapet (between the poles).
const POLES_LEFT: Array[float] = [-11.0, -6.5, -2.0, 2.5, 7.0]
const POLES_RIGHT: Array[float] = [-11.0, -6.5, -2.0, 2.5, 4.6]
const BOUGAINVILLEA: Array[float] = [-8.75, -4.25, 0.25]
## The loudspeakers either side of the picture (their centres' x, from the picture's edge).
const SPEAKER_OUT := 1.15


## The pieces' boxes for object physics (from parameters alone): the hut, the kiosk, the lemon tree's pot.
static func collision_boxes(hw: float, bz: float, gy: float) -> Array:
	var out: Array = []
	out.append([Vector3((HUT[0] + HUT[1]) * 0.5, gy + HUT[3] * 0.5, bz - HUT[2] * 0.5),
			Vector3(HUT[1] - HUT[0], HUT[3], HUT[2])])
	out.append([Vector3(hw - KIOSK_W * 0.5, gy + KIOSK_H * 0.5, bz - KIOSK_D * 0.5), Vector3(KIOSK_W, KIOSK_H, KIOSK_D)])
	out.append([Vector3(-hw + 1.0, gy + 0.3, bz - 1.1), Vector3(0.8, 0.6, 0.8)])
	return out


## Everything: returns what the terrace keeps for its live parameters {city: the city's material, halos: the
## halos' material}.
static func build(t: Object, hw: float, fz: float, bz: float, gy: float) -> Dictionary:
	# The parts share a few materials, each one mesh (a draw each): ironwork, wood, painted wood, plaster, the lamps'
	# glow by group, the pots, the leaves, the soft things (canvas, glass). Vertex colours give each piece its own.
	var parts := {}
	for e: Array in [["iron", "dark_metal", Color(0.24, 0.23, 0.22)], ["wood", "oak_veneer", Color(0.62, 0.48, 0.34)],
			["painted", "wood_slats", Color(0.92, 0.92, 0.9)], ["plaster", "rough_plaster", Color(0.92, 0.91, 0.88)],
			["pots", "painted_wall", Color(0.95, 0.95, 0.95)]]:
		var b := RoomMesh.new()
		b.surface(_lib(t, e[1], e[2]))
		parts[e[0]] = b
	for e: Array in [["leaves", "felt"], ["soft", "linen"]]:
		var b := RoomMesh.new()
		b.surface(_lib_soft(t, e[1], Color(1, 1, 1)))
		parts[e[0]] = b
	for e: Array in [["glow_house", BULB, 3.2, 1.0, "house"], ["glow_booth", Color.WHITE, 1.4, 0.0, "booth"],
			["glow_accent", Color.WHITE, ACCENT_ENERGY, 0.0, "accent"]]:
		var b := RoomMesh.new()
		var m: ShaderMaterial = t._lamp(e[1], e[2], e[3], e[4])
		if e[0] != "glow_house":
			m.set_shader_parameter("use_vertex_colour", true)
		b.surface(m)
		parts[e[0]] = b
	parts["posters"] = []
	t.set_meta("athens_parts", parts)
	_floor(t, hw, fz, bz, gy)
	_parapet(t, hw, fz, bz, gy)
	_screen_wall(t, hw, fz, gy)
	_hut(t, bz, gy)
	_kiosk(t, hw, bz, gy)
	_plants(t, hw, fz, bz, gy)
	var halos := _bulbs(t, hw, fz, bz, gy)
	t._add_static("Ironwork", parts["iron"])
	t._add_static("Woodwork", parts["wood"])
	t._add_static("PaintedWood", parts["painted"])
	t._add_static("Plaster", parts["plaster"])
	t._add_static("Pots", parts["pots"])
	t._add_unbaked("Plants", parts["leaves"])
	t._add_unbaked("Canvas", parts["soft"])
	t._add_lamps("Bulbs", parts["glow_house"])
	t._add_lamps("BoothGlow", parts["glow_booth"])
	t._add_lamps("KioskGlow", parts["glow_accent"])
	_posters_mesh(t, parts["posters"])
	t.remove_meta("athens_parts")
	var city: Array = AthensCity.build(1834)
	var mi := MeshInstance3D.new()
	mi.name = "City"
	mi.mesh = city[0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	t.own(mi)
	return {"city": city[1], "halos": halos}


# --- Helpers ------------------------------------------------------------------------------------------------------------

## Smooth value noise in 0..1.
static func _vn(x: float, y: float, seed_value: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_h(xi, yi, seed_value), _h(xi + 1, yi, seed_value), fx),
			lerpf(_h(xi, yi + 1, seed_value), _h(xi + 1, yi + 1, seed_value), fx), fy)


static func _h(x: int, y: int, seed_value: int) -> float:
	var q := (x * 374761393 + y * 668265263 + seed_value * 1442695041) & 0x7fffffff
	q = ((q ^ (q >> 13)) * 1274126177) & 0x7fffffff
	return float(q & 0xffff) / 65535.0


## A shared part's mesh (build()'s parts).
static func _part(t: Object, key: String) -> RoomMesh:
	return (t.get_meta("athens_parts") as Dictionary)[key]


## How many vertices each surface has now (so a later _tint() touches only what comes after).
static func _mark(b: RoomMesh) -> Dictionary:
	var out := {}
	for m: Material in b._surfaces:
		out[m] = (b._surfaces[m].get("verts") as PackedVector3Array).size()
	return out


## Every vertex colour so far (since `from`, a _mark()) times f(position, normal) -> Color (weathering by place;
## RoomMesh.shade() in colour).
static func _tint(b: RoomMesh, f: Callable, from := {}) -> void:
	for m: Material in b._surfaces:
		var s: Object = b._surfaces[m]
		var verts: PackedVector3Array = s.get("verts")
		var normals: PackedVector3Array = s.get("normals")
		var colours: PackedColorArray = s.get("colours")
		for i in range(int(from.get(m, 0)), verts.size()):
			var k: Color = f.call(verts[i], normals[i])
			var c: Color = colours[i]
			colours[i] = Color(c.r * k.r, c.g * k.g, c.b * k.b, c.a)
		s.set("colours", colours)


## A flat sheet of quads (rows of strips, a chart each) over a rectangle in the plane through `origin` spanned by u
## (along a row) and v (row to row), facing n: finely enough divided for vertex colours to show stains.
static func _sheet(b: RoomMesh, origin: Vector3, u: Vector3, v: Vector3, n: Vector3, cols: int, rows: int) -> void:
	for r in rows:
		var a := PackedVector3Array()
		var c := PackedVector3Array()
		var ns := PackedVector3Array()
		for k in cols + 1:
			a.append(origin + u * (float(k) / cols) + v * (float(r) / rows))
			c.append(origin + u * (float(k) / cols) + v * (float(r + 1) / rows))
			ns.append(n)
		b.strip(a, c, ns)


## A material from the library with vertex colours showing (instance_tint), this room's copy.
static func _lib(t: Object, id: String, colour: Color, options := {}, tinted := true) -> ShaderMaterial:
	var m: ShaderMaterial = t._light.library(id, colour, options)
	if tinted:
		m.set_shader_parameter("instance_tint", true)
	return m


static func _lib_soft(t: Object, id: String, colour: Color, options := {}) -> ShaderMaterial:
	var m: ShaderMaterial = t._light.library(id, colour, options, true)
	m.set_shader_parameter("instance_tint", true)
	return m


# --- The floor ----------------------------------------------------------------------------------------------------------

static func _floor(t: Object, hw: float, fz: float, bz: float, gy: float) -> void:
	var m: ShaderMaterial = t._patterned("floor", "quarry_tiles")
	m.set_shader_parameter("instance_tint", true)
	var b := RoomMesh.new()
	b.surface(m)
	var cols := int(roundf(hw * 2.0 / 0.65))
	var rows := int(roundf((bz - fz) / 0.65))
	_sheet(b, Vector3(-hw, gy, bz), Vector3(hw * 2.0, 0, 0), Vector3(0, 0, fz - bz), Vector3.UP, cols, rows)
	_tint(b, func(p: Vector3, _n: Vector3) -> Color:
		var k := 0.9 + 0.16 * _vn(p.x * 0.45, p.z * 0.45, 11)
		# Dirt along the walls, the aisles a little paler with wear, a dark stain under the kiosk's counter.
		var wall := minf(minf(hw - absf(p.x), p.z - fz), bz - p.z)
		k *= 1.0 - 0.2 * (1.0 - smoothstep(0.0, 0.7, wall))
		var aisle := smoothstep(3.0, 3.6, absf(p.x)) * (1.0 - smoothstep(5.6, 6.2, absf(p.x)))
		k *= 1.0 + 0.06 * aisle
		var spill := Vector2(p.x - (hw - KIOSK_W * 0.5), p.z - (bz - KIOSK_D - 0.3)).length()
		k *= 1.0 - 0.18 * (1.0 - smoothstep(0.3, 1.4, spill))
		var damp := smoothstep(0.62, 0.8, _vn(p.x * 0.3 + 7.0, p.z * 0.3, 13))
		return Color(k * (1.0 - 0.06 * damp), k * (1.0 - 0.04 * damp), k)
	)
	t._add_static("Floor", b)


# --- The parapet ---------------------------------------------------------------------------------------------------------

static func _parapet(t: Object, hw: float, fz: float, bz: float, gy: float) -> void:
	var h := float(t.params["parapet_height"])
	var b := RoomMesh.new()
	var mat: ShaderMaterial = t._mat("parapet_material")
	mat.set_shader_parameter("instance_tint", true)
	b.surface(mat)
	var from := fz - 0.5
	var th := 0.3
	for s: float in [-1.0, 1.0]:
		var xi := s * hw
		var xo := s * (hw + th)
		var length := bz + th - from
		var segs := int(length / 0.5)
		# Inside and outside faces, divided for their weathering; the top under the coping.
		_sheet(b, Vector3(xi, gy, from), Vector3(0, 0, length - th), Vector3(0, h, 0), Vector3(-s, 0, 0), segs, 4)
		_sheet(b, Vector3(xo, gy, from), Vector3(0, 0, length), Vector3(0, h, 0), Vector3(s, 0, 0), segs, 2)
	var bl := hw * 2.0 + th * 2.0
	_sheet(b, Vector3(-hw, gy, bz), Vector3(hw * 2.0, 0, 0), Vector3(0, h, 0), Vector3.FORWARD, int(hw * 4.0), 4)
	_sheet(b, Vector3(-hw - th, gy, bz + th), Vector3(bl, 0, 0), Vector3(0, h, 0), Vector3.BACK, int(bl * 2.0), 2)
	_tint(b, func(p: Vector3, n: Vector3) -> Color:
		var y := p.y - gy
		var along := p.z if absf(n.x) > 0.5 else p.x
		var k := 0.86 + 0.12 * _vn(along * 0.9, y * 2.0, 21)
		# The splash of rain at the foot; streaks run down from the coping; chips to the grey render.
		k *= 1.0 - 0.38 * (1.0 - smoothstep(0.0, 0.2, y)) - 0.1 * (1.0 - smoothstep(0.2, 0.45, y))
		var streak := smoothstep(0.55, 0.85, _vn(along * 3.1, 0.5, 23)) * smoothstep(0.3, h, y)
		k *= 1.0 - 0.18 * streak
		var chip := smoothstep(0.8, 0.9, _vn(along * 2.3, y * 2.3, 29))
		return Color(k * (1.0 - 0.16 * chip), k * (1.0 - 0.16 * chip), k * (1.0 - 0.1 * chip))
	)
	# The coping: stones 1.2 m long laid with joints, each its own shade and a hair off true.
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var cop := b
	for s: float in [-1.0, 1.0]:
		var z := from
		while z < bz + th - 0.05:
			var l := minf(1.2, bz + th - z)
			cop.colour = Color(1, 1, 1) * rng.randf_range(0.86, 1.0)
			cop.box(Vector3(s * (hw + th * 0.5), gy + h + 0.03 + rng.randf_range(-0.004, 0.004), z + l * 0.5),
					Vector3(0.4, 0.06, l - 0.015), Basis(Vector3.UP, rng.randf_range(-0.004, 0.004)))
			z += l
	var x := -hw
	while x < hw - 0.05:
		var l := minf(1.2, hw - x)
		cop.colour = Color(1, 1, 1) * rng.randf_range(0.86, 1.0)
		cop.box(Vector3(x + l * 0.5, gy + h + 0.03 + rng.randf_range(-0.004, 0.004), bz + th * 0.5),
				Vector3(l - 0.015, 0.06, 0.4))
		x += l
	cop.colour = Color.WHITE
	t._add_static("Parapet", b)
	# Drain spouts through the foot of the side walls: a dark slot inside, a short pipe out over the street.
	var sp := _part(t, "iron")
	sp.colour = Color(0.45, 0.4, 0.36)
	for s: float in [-1.0, 1.0]:
		for z: float in [-9.6, -0.9, 5.4]:
			sp.box(Vector3(s * (hw - 0.004), gy + 0.05, z), Vector3(0.01, 0.07, 0.16))
			sp.box(Vector3(s * (hw + th + 0.08), gy - 0.06, z), Vector3(0.18, 0.06, 0.1))
	sp.colour = Color.WHITE


# --- The screen wall ----------------------------------------------------------------------------------------------------

## The ghost of the house that once stood against the wall: its gable's line (y at x), peaking behind the picture.
static func gable(x: float) -> float:
	return 5.6 - absf(x) * 0.48


static func _screen_wall(t: Object, hw: float, fz: float, gy: float) -> void:
	var top := gy + float(t.params["wall_height"])
	var w := hw + 2.0
	var bottom := gy - 3.5
	var wm: ShaderMaterial = t._mat("wall")
	wm.set_shader_parameter("instance_tint", true)
	var b := RoomMesh.new()
	b.surface(wm)
	_sheet(b, Vector3(-w, bottom, fz), Vector3(w * 2.0, 0, 0), Vector3(0, top - bottom, 0), Vector3.BACK,
			int(w * 2.0 / 0.25), int((top - bottom) / 0.25))
	var sc: Dictionary = t.call("screen")
	var c: Vector3 = Vector3(sc["center"][0], sc["center"][1], sc["center"][2])
	var size := Vector2(sc["size"][0], sc["size"][1])
	_tint(b, func(p: Vector3, _n: Vector3) -> Color:
		return _wall_tint(p.x, p.y - gy, top - gy, c, size)
	)
	# The wall's ends and its coping.
	b.colour = Color(0.8, 0.78, 0.72)
	for s: float in [-1.0, 1.0]:
		b.face([Vector3(s * w, bottom, fz), Vector3(s * w, bottom, fz - 0.5), Vector3(s * w, top, fz - 0.5),
				Vector3(s * w, top, fz)], Vector3(s, 0, 0))
	b.colour = Color(0.72, 0.7, 0.66)
	b.box(Vector3(0, top + 0.05, fz - 0.22), Vector3(w * 2.0 + 0.1, 0.1, 0.62))
	b.colour = Color.WHITE
	_signs(b, fz, gy)
	t._add_static("ScreenWall", b)
	# The screen: painted white just larger than the picture, a matte black border round it (the paint's own).
	var pm: ShaderMaterial = t._mat("paint")
	pm.set_shader_parameter("instance_tint", true)
	var paint := RoomMesh.new()
	paint.surface(pm)
	var hx := size.x * 0.5 + 0.04
	var hy := size.y * 0.5 + 0.04
	paint.face([Vector3(c.x - hx, c.y - hy, fz + 0.01), Vector3(c.x + hx, c.y - hy, fz + 0.01),
			Vector3(c.x + hx, c.y + hy, fz + 0.01), Vector3(c.x - hx, c.y + hy, fz + 0.01)], Vector3.BACK)
	paint.colour = Color(0.05, 0.05, 0.05)
	var bw := 0.36
	for q: Array in [[-hx - bw, -hx, -hy - bw, hy + bw], [hx, hx + bw, -hy - bw, hy + bw], [-hx, hx, -hy - bw, -hy],
			[-hx, hx, hy, hy + bw]]:
		paint.face([Vector3(c.x + float(q[0]), c.y + float(q[2]), fz + 0.012), Vector3(c.x + float(q[1]),
				c.y + float(q[2]), fz + 0.012), Vector3(c.x + float(q[1]), c.y + float(q[3]), fz + 0.012),
				Vector3(c.x + float(q[0]), c.y + float(q[3]), fz + 0.012)], Vector3.BACK)
	paint.colour = Color.WHITE
	t._add_static("Painted", paint)
	_wall_fittings(t, hw, fz, gy, c, size)


## The blind wall's weathering at x, y (up from the roof): its plaster's blotches, rain streaks down from the top, the
## ghost of a house (inside its gable two rooms' old paint, blue-green and rose, its floor's line, the cut along its
## roof), a patch of newer render, the stain under the drainpipe's hopper, the roof's splash at the foot.
static func _wall_tint(x: float, y: float, top: float, c: Vector3, size: Vector2) -> Color:
	# Vertex colours stop at 1: the wall's own colour is its brightest, everything here takes from it.
	var col := Color(1, 1, 1)
	var k := 0.8 + 0.14 * _vn(x * 0.55, y * 0.55, 3) + 0.06 * _vn(x * 2.1, y * 2.1, 4)
	var streak := smoothstep(0.5, 0.9, _vn(x * 2.4, 0.5, 5)) * exp(-(top - y) / 2.8)
	k *= 1.0 - 0.32 * streak
	var g := gable(x)
	var inside := smoothstep(0.14, -0.14, y - g) * smoothstep(-0.3, 0.1, y)
	if inside > 0.0:
		var room := Color(0.52, 0.74, 0.86) if x < 0.0 else Color(0.96, 0.6, 0.58)
		var faded := 0.6 + 0.4 * _vn(x * 0.8 + 3.0, y * 0.8, 6)
		col = col.lerp(room, inside * faded)
		# The old floor's line, and a flue's soot up the left room's wall.
		k *= 1.0 - 0.32 * inside * exp(-pow((y - 2.7) / 0.14, 2.0))
		k *= 1.0 - 0.3 * inside * exp(-pow((x + 5.2) / 0.28, 2.0)) * smoothstep(0.0, 3.0, y)
	# The cut along the old roof: a dark seam, the plaster above it torn a little lighter.
	k *= 1.0 - 0.45 * exp(-pow((y - g) / 0.15, 2.0)) * smoothstep(-0.5, 0.2, y)
	k *= 1.0 + 0.1 * exp(-pow((y - g - 0.35) / 0.2, 2.0))
	# The light falls off up the wall (the bulbs are low).
	k *= 1.0 - 0.18 * smoothstep(3.0, top, y)
	# A patch of newer render, greyer and smoother, on the right.
	var patch := smoothstep(4.6, 4.8, x) * (1.0 - smoothstep(7.4, 7.6, x)) * smoothstep(3.4, 3.6, y) \
			* (1.0 - smoothstep(5.1, 5.3, y))
	col = col.lerp(Color(0.9, 0.93, 0.98), patch * 0.8)
	k *= 1.0 + 0.12 * patch
	# The drainpipe's stain, the roof's splash at the foot, darker round the black border's edge (handled, fingered).
	k *= 1.0 - 0.25 * exp(-pow((x - 7.9) / 0.35, 2.0)) * smoothstep(top - 1.2, top - 3.0, y)
	k *= 1.0 - 0.2 * (1.0 - smoothstep(0.0, 0.6, y))
	var bx := maxf(absf(x - c.x) - size.x * 0.5 - 0.4, 0.0)
	var by := maxf(absf(y - c.y) - size.y * 0.5 - 0.4, 0.0)
	k *= 1.0 - 0.06 * exp(-(bx * bx + by * by) / 0.2)
	k = minf(k, 1.0)
	return Color(col.r * k, col.g * k, col.b * k)


## Two painted signs of long ago on the wall, faded into it (strokes of paint a hair in front, the wall's material in
## the paint's colours): a coffee's over the old house on the left, a soap's lower on the right.
static func _signs(b: RoomMesh, fz: float, gy: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1952
	# The coffee's: a pale ground, a border, ΚΑΦΕΣ big, ΑΡΓΩ under it, in old oxblood gone pink.
	_sign_ground(b, Rect2(-8.15, gy + 4.55, 3.95, 2.45), fz, Color(1.05, 1.03, 0.97), Color(0.88, 0.76, 0.72))
	_paint_text(b, rng, "ΚΑΦΕΣ", Vector2(-6.17, gy + 5.85), 0.66, 0.1, fz, Color(0.8, 0.6, 0.55), 0.06)
	_paint_text(b, rng, "ΑΡΓΩ", Vector2(-6.17, gy + 4.9), 0.46, 0.08, fz, Color(0.82, 0.64, 0.58), 0.08)
	# The soap's, lower on the right: letters straight on the plaster in a blue gone grey.
	_paint_text(b, rng, "ΣΑΠΟΥΝΙΑ", Vector2(6.0, gy + 2.55), 0.36, 0.06, fz, Color(0.78, 0.82, 0.9), 0.06)
	_paint_text(b, rng, "ΛΕΥΚΗ", Vector2(6.0, gy + 1.65), 0.58, 0.09, fz, Color(0.74, 0.79, 0.9), 0.06)


static func _sign_ground(b: RoomMesh, r: Rect2, fz: float, ground: Color, border: Color) -> void:
	b.colour = ground
	b.face([Vector3(r.position.x, r.position.y, fz + 0.006), Vector3(r.end.x, r.position.y, fz + 0.006),
			Vector3(r.end.x, r.end.y, fz + 0.006), Vector3(r.position.x, r.end.y, fz + 0.006)], Vector3.BACK)
	b.colour = border
	var w := 0.06
	for q: Rect2 in [Rect2(r.position.x + 0.1, r.position.y + 0.1, r.size.x - 0.2, w),
			Rect2(r.position.x + 0.1, r.end.y - 0.1 - w, r.size.x - 0.2, w),
			Rect2(r.position.x + 0.1, r.position.y + 0.1, w, r.size.y - 0.2),
			Rect2(r.end.x - 0.1 - w, r.position.y + 0.1, w, r.size.y - 0.2)]:
		b.face([Vector3(q.position.x, q.position.y, fz + 0.009), Vector3(q.end.x, q.position.y, fz + 0.009),
				Vector3(q.end.x, q.end.y, fz + 0.009), Vector3(q.position.x, q.end.y, fz + 0.009)], Vector3.BACK)
	b.colour = Color.WHITE


## Text in strokes of paint centred on `at` (its baseline), letters `height` tall, strokes `thick` wide; some strokes
## worn away (`worn`: the share gone), none inside `covered` (painted over).
static func _paint_text(b: RoomMesh, rng: RandomNumberGenerator, text: String, at: Vector2, height: float, thick: float,
		fz: float, colour: Color, worn: float, covered := Rect2()) -> void:
	var x0 := at.x - Strokes.width(text, height) * 0.5
	for poly: PackedVector2Array in Strokes.lines(text, height):
		for i in poly.size() - 1:
			var a := Vector2(x0 + poly[i].x, at.y + poly[i].y)
			var e := Vector2(x0 + poly[i + 1].x, at.y + poly[i + 1].y)
			if rng.randf() < worn:
				continue
			if covered.has_area() and (covered.has_point(a) or covered.has_point(e)):
				continue
			b.colour = colour.lerp(Color.WHITE, rng.randf_range(0.0, 0.35))
			var d := (e - a).normalized()
			var nn := Vector2(-d.y, d.x) * thick * 0.5
			var ext := d * thick * 0.5
			var p := [a - ext - nn, e + ext - nn, e + ext + nn, a - ext + nn]
			b.face([Vector3(p[0].x, p[0].y, fz + 0.008), Vector3(p[1].x, p[1].y, fz + 0.008),
					Vector3(p[2].x, p[2].y, fz + 0.008), Vector3(p[3].x, p[3].y, fz + 0.008)], Vector3.BACK)
	b.colour = Color.WHITE


## On the wall: a loudspeaker either side of the picture on its bracket, a drainpipe with its hopper down the right
## edge, an iron ladder down the wall's right end to the neighbour's roof, a conduit from the hut's side to a box.
static func _wall_fittings(t: Object, _hw: float, fz: float, gy: float, c: Vector3, size: Vector2) -> void:
	var wood := _part(t, "wood")
	var b := _part(t, "iron")
	for s: float in [-1.0, 1.0]:
		var sx := c.x + s * (size.x * 0.5 + SPEAKER_OUT)
		var at := Vector3(sx, c.y - 0.1, fz + 0.32)
		var turn := Basis(Vector3.UP, -s * deg_to_rad(9.0))
		wood.colour = Color(0.62, 0.56, 0.5)
		wood.box(at, Vector3(0.62, 0.92, 0.4), turn)
		wood.colour = Color.WHITE
		# Its cloth front, nearly black.
		b.colour = Color(0.4, 0.38, 0.36)
		b.box(at + turn * Vector3(0, 0, 0.201), Vector3(0.52, 0.8, 0.01), turn, [RoomMesh.FRONT])
		b.colour = Color.WHITE
		b.box(Vector3(sx, at.y - 0.52, fz + 0.2), Vector3(0.5, 0.05, 0.4))
		b.box(Vector3(sx, at.y - 0.7, fz + 0.03), Vector3(0.06, 0.4, 0.06))
		Shapes.beam(b, Vector3(sx, at.y - 0.88, fz + 0.03), Vector3(sx, at.y - 0.54, fz + 0.36), Vector2(0.04, 0.04))
	# The drainpipe and its hopper.
	var px := 7.9
	Shapes.cylinder(b, Vector3(px, gy - 3.4, fz + 0.12), 0.055, float(t.params["wall_height"]) + 3.1, 8)
	b.box(Vector3(px, gy + float(t.params["wall_height"]) - 0.45, fz + 0.14), Vector3(0.3, 0.3, 0.26))
	for y: float in [0.8, 2.6, 4.4, 6.2]:
		b.box(Vector3(px, gy + y, fz + 0.06), Vector3(0.16, 0.04, 0.12))
	# The ladder: two rails, rungs, a hoop cage over its upper part, from the wall's top to the neighbour's roof.
	var lx := 7.15
	var y0 := gy - 1.0
	var y1 := gy + float(t.params["wall_height"]) + 1.0
	for s: float in [-1.0, 1.0]:
		b.box(Vector3(lx + s * 0.22, (y0 + y1) * 0.5, fz + 0.18), Vector3(0.05, y1 - y0, 0.05))
	var y := y0 + 0.3
	while y < y1 - 0.9:
		b.box(Vector3(lx, y, fz + 0.18), Vector3(0.44, 0.03, 0.03))
		y += 0.3
	for k in 7:
		var hy := gy + 2.6 + k * 0.85
		for seg in 6:
			var a0 := PI * seg / 6.0
			var a1 := PI * (seg + 1) / 6.0
			Shapes.beam(b, Vector3(lx - cos(a0) * 0.36, hy, fz + 0.18 + sin(a0) * 0.6),
					Vector3(lx - cos(a1) * 0.36, hy, fz + 0.18 + sin(a1) * 0.6), Vector2(0.03, 0.03))
	for s: float in [-0.36, 0.0, 0.36]:
		var zz := fz + 0.18 + (0.6 if s == 0.0 else 0.0)
		var xx := lx + s
		b.box(Vector3(xx, gy + 2.6 + 3.0 * 0.85, zz), Vector3(0.03, 6.0 * 0.85, 0.03))
	for s: float in [-1.0, 1.0]:
		for yy: float in [y0 + 1.0, gy + 4.0, y1 - 1.5]:
			b.box(Vector3(lx + s * 0.22, yy, fz + 0.08), Vector3(0.04, 0.04, 0.18))


# --- The projection hut ------------------------------------------------------------------------------------------------

static func _hut(t: Object, bz: float, gy: float) -> void:
	var x0 := float(HUT[0])
	var x1 := float(HUT[1])
	var z0 := bz - float(HUT[2])
	var z1 := bz
	var h := float(HUT[3])
	var b := _part(t, "plaster")
	var mark := _mark(b)
	# The ports: the projector's, square and wider, on the axis; the projectionist's small window to look through,
	# lower and to the side. [centre x, centre y, half width, half height]
	var ports: Array = [[0.0, gy + 2.02, 0.2, 0.16], [0.72, gy + 1.66, 0.12, 0.1]]
	# The front (towards the screen) with its two ports cut, the sides (the door on the right), the top.
	var holes: Array = []
	for pt: Array in ports:
		holes.append(Rect2(float(pt[0]) - x0 - float(pt[2]), float(pt[1]) - float(pt[3]) - gy, float(pt[2]) * 2.0,
				float(pt[3]) * 2.0))
	Shapes.wall(b, Vector3(x0, gy, z0), Vector3.RIGHT, Vector3.FORWARD, x1 - x0, h, holes)
	Shapes.wall(b, Vector3(x0, gy, z1), Vector3.FORWARD, Vector3.LEFT, z1 - z0, h)
	var door := Rect2(0.75, 0.0, 0.82, 2.0)
	Shapes.wall(b, Vector3(x1, gy, z0), Vector3.BACK, Vector3.RIGHT, z1 - z0, h, [door])
	# The ports' reveals.
	for pt: Array in ports:
		var px := float(pt[0])
		var py := float(pt[1])
		var hw2 := float(pt[2])
		var hh := float(pt[3])
		for q: Array in [[Vector3(px, py - hh, z0 + 0.12), Vector3(hw2 * 2.0, 0.01, 0.24)],
				[Vector3(px, py + hh, z0 + 0.12), Vector3(hw2 * 2.0, 0.01, 0.24)],
				[Vector3(px - hw2, py, z0 + 0.12), Vector3(0.01, hh * 2.0, 0.24)],
				[Vector3(px + hw2, py, z0 + 0.12), Vector3(0.01, hh * 2.0, 0.24)]]:
			b.box(q[0], q[1])
	_tint(b, func(p: Vector3, _n: Vector3) -> Color:
		var y := p.y - gy
		var k := 0.86 + 0.1 * _vn(p.x * 1.3 + p.z, y * 1.3, 41)
		k *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.25, y))
		k *= 1.0 - 0.1 * smoothstep(h - 0.6, h, y) * smoothstep(0.55, 0.8, _vn(p.x * 3.0 + p.z * 3.0, 1.0, 43))
		return Color(k, k, k * 0.98)
	, mark)
	# The roof slab over it, a little proud, greyer; the vent; the door, blue; the lamp's cage.
	b.colour = Color(0.72, 0.71, 0.69)
	b.box(Vector3((x0 + x1) * 0.5, gy + h + 0.06, (z0 + z1) * 0.5 - 0.05), Vector3(x1 - x0 + 0.24, 0.12,
			z1 - z0 + 0.14))
	b.colour = Color.WHITE
	var iron := _part(t, "iron")
	Shapes.cylinder(iron, Vector3(-0.7, gy + h + 0.12, z0 + 0.9), 0.1, 0.9, 10)
	Shapes.lathe(iron, [Vector2(0.0, 0.0), Vector2(0.2, 0.0), Vector2(0.0, 0.12)], Vector3(-0.7, gy + h + 1.08,
			z0 + 0.9), 10)
	var painted := _part(t, "painted")
	painted.colour = Color(0.2, 0.4, 0.68)
	painted.box(Vector3(x1 + 0.03, gy + 1.0, z0 + 0.75 + 0.41), Vector3(0.05, 2.0, 0.82))
	painted.colour = Color.WHITE
	iron.box(Vector3(x1 + 0.07, gy + 1.0, z0 + 0.75 + 0.7), Vector3(0.03, 0.12, 0.04))
	var lamp_at := Vector3(x1 + 0.16, gy + 2.25, z0 + 0.75 + 0.41)
	for k in 4:
		var a := TAU * k / 4.0
		Shapes.beam(iron, lamp_at + Vector3(cos(a) * 0.07, -0.09, sin(a) * 0.07), lamp_at + Vector3(cos(a) * 0.07,
				0.07, sin(a) * 0.07), Vector2(0.008, 0.008))
	iron.box(lamp_at + Vector3(-0.08, 0.1, 0), Vector3(0.16, 0.03, 0.03))
	# The ports' glass glowing (the projector's light, cool; the little window warm and dim: a lamp inside), the
	# lamp over the door (house).
	var glow := _part(t, "glow_booth")
	glow.colour = Color(0.78, 0.86, 1.0)
	Shapes.quad(glow, Vector3(0.0, float(ports[0][1]), z0 + 0.23), Vector3(0.19, 0, 0), Vector3(0, 0.15, 0),
			Vector3.FORWARD)
	glow.colour = Color(1.0, 0.72, 0.42) * 0.36
	Shapes.quad(glow, Vector3(0.72, float(ports[1][1]), z0 + 0.23), Vector3(0.11, 0, 0), Vector3(0, 0.09, 0),
			Vector3.FORWARD)
	glow.colour = Color.WHITE
	var port_y := float(ports[0][1])
	var bulb := _part(t, "glow_house")
	Shapes.lathe(bulb, [Vector2(0.0, -0.06), Vector2(0.045, -0.03), Vector2(0.05, 0.01), Vector2(0.02, 0.05)], lamp_at, 8)
	t._light.add_lamp(lamp_at + Vector3(0.3, 0, 0), BULB * 1.4, -1.0)
	t._bake_omni("HutLamp", lamp_at + Vector3(0.25, -0.1, 0), 5.0, 0.5, BULB)
	t._bake_omni("HutPorts", Vector3(0, port_y, z0 - 0.3), 3.0, 0.15, Color(0.78, 0.86, 1.0))
	# Tonight's film in a case on the hut's front (next week's is on the kiosk's side).
	_poster(t, Vector3(-1.0, gy + 1.15, z0 - 0.04), Vector3.LEFT, 0)


## A film poster in a wooden case: `across` is its width's direction (left to right as it is seen), so it faces
## across x up; kind 0 and 1 are two invented films.
static func _poster(t: Object, centre: Vector3, across: Vector3, kind: int) -> void:
	var n := across.cross(Vector3.UP).normalized()
	var w := 0.62
	var h := 0.9
	var b := _part(t, "wood")
	b.colour = Color(0.5, 0.42, 0.36)
	b.box(centre - n * 0.02, Vector3(w + 0.1, h + 0.1, 0.04), Basis(across, Vector3.UP, n))
	b.colour = Color.WHITE
	var c := centre + n * 0.002
	(t.get_meta("athens_parts")["posters"] as Array).append([[c - across * w * 0.5 - Vector3.UP * h * 0.5,
			c + across * w * 0.5 - Vector3.UP * h * 0.5, c + across * w * 0.5 + Vector3.UP * h * 0.5,
			c - across * w * 0.5 + Vector3.UP * h * 0.5], n, kind])


## The posters: one mesh, one picture with both side by side (the light system's house material on the mesh's UVs,
## unbaked: it keeps the stand-in lamps).
static func _posters_mesh(t: Object, posters: Array) -> void:
	if posters.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in posters:
		var corners: Array = p[0]
		var n: Vector3 = p[1]
		var u0 := 0.5 * int(p[2])
		var uvs := [Vector2(u0, 1), Vector2(u0 + 0.5, 1), Vector2(u0 + 0.5, 0), Vector2(u0, 0)]
		var order := [0, 1, 2, 0, 2, 3]
		if (corners[2] - corners[0]).cross(corners[1] - corners[0]).dot(n) < 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k: int in order:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(corners[k])
	var m: ShaderMaterial = t._light.library("painted_wall", Color(1, 1, 1), {}, true)
	m.set_shader_parameter("albedo_map", poster_picture())
	m.set_shader_parameter("use_mesh_uv", true)
	m.set_shader_parameter("normal_strength", 0.2)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mi: MeshInstance3D = t._add_mesh("Posters", mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Two invented films' posters side by side (no figure, no one's title or mark): a field of colour, a big simple
## picture (a moon over the sea and a sail; a sun over hills and a lone cypress), the title in our own letters, a
## line of credits' dashes under it, TODAY or COMING SOON over it. 256 x 192, each 128 wide.
static func poster_picture() -> ImageTexture:
	var img := Image.create_empty(256, 192, false, Image.FORMAT_RGB8)
	for kind in 2:
		_draw_poster(img, kind)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _draw_poster(img: Image, kind: int) -> void:
	var w := 128
	var h := 192
	var ox := kind * 128
	var sky := Color(0.1, 0.16, 0.36) if kind == 0 else Color(0.86, 0.46, 0.16)
	var low := Color(0.04, 0.08, 0.2) if kind == 0 else Color(0.5, 0.16, 0.08)
	for y in h:
		for x in w:
			var f := float(y) / h
			var c := sky.lerp(low, f)
			if kind == 0:
				# The moon, its path on the sea, a sail.
				var d := Vector2(x - 84, y - 52).length()
				if d < 15.0:
					c = Color(0.95, 0.9, 0.72)
				elif d < 22.0:
					c = c.lerp(Color(0.6, 0.6, 0.55), (22.0 - d) / 7.0 * 0.4)
				if y > 104 and y < 150:
					c = Color(0.05, 0.1, 0.22).lerp(Color(0.02, 0.05, 0.12), float(y - 104) / 46.0)
					if absf(x - 84 + (y - 104) * 0.1) < 3.0 + (y - 104) * 0.12 and (x + y) % 3 != 0:
						c = Color(0.85, 0.8, 0.6)
				var sx := x - 40
				var sy := y - 104
				if sy < 0 and sy > -34 and sx > 0 and sx < -sy * 0.7:
					c = Color(0.92, 0.9, 0.84)
				if sy >= 0 and sy < 6 and absf(sx - 6) < 14 - sy:
					c = Color(0.3, 0.12, 0.08)
			else:
				# The sun on the hills, a cypress.
				var d := Vector2(x - 64, y - 80).length()
				if d < 28.0:
					c = Color(1.0, 0.86, 0.4)
				var hill := 110.0 + 10.0 * sin(x * 0.07) + 6.0 * sin(x * 0.19 + 1.0)
				if y > hill:
					c = Color(0.24, 0.08, 0.06).lerp(Color(0.12, 0.04, 0.03), float(y - hill) / 40.0)
				var cx := absf(x - 30)
				if y > 62 and y < 118 and cx < 6.0 * sin(float(y - 62) / 56.0 * PI * 0.9 + 0.2):
					c = Color(0.08, 0.06, 0.04)
			if y > 150:
				c = Color(0.92, 0.88, 0.78) if kind == 0 else Color(0.95, 0.9, 0.78)
			img.set_pixel(ox + x, y, c)
	var title := "ΤΟ ΦΕΓΓΑΡΙ" if kind == 0 else "ΚΑΥΣΩΝΑΣ"
	Strokes.draw(img, title, Vector2(ox + 64, 172), 15.0, Color(0.6, 0.08, 0.06), 2.6, true, 0.95)
	for k in 3:
		Strokes.line(img, Vector2(ox + 24 + k * 30, 184), Vector2(ox + 44 + k * 30, 184), Color(0.3, 0.28, 0.26), 1.4)
	Strokes.draw(img, "ΣΗΜΕΡΑ" if kind == 0 else "ΠΡΟΣΕΧΩΣ", Vector2(ox + 64, 22), 10.0, Color(0.96, 0.9, 0.7), 2.0,
			true)


# --- The kiosk -----------------------------------------------------------------------------------------------------------

static func _kiosk(t: Object, hw: float, bz: float, gy: float) -> void:
	var x0 := hw - KIOSK_W
	var x1 := hw
	var z0 := bz - KIOSK_D
	var z1 := bz
	var b := _part(t, "plaster")
	var painted := _part(t, "painted")
	var wood := _part(t, "wood")
	# Its walls: the left side, plastered; the back is the parapet; posts at the front corners, painted green.
	b.colour = Color(0.9, 0.89, 0.86)
	b.box(Vector3(x0 + 0.06, gy + KIOSK_H * 0.5, (z0 + z1) * 0.5), Vector3(0.12, KIOSK_H, KIOSK_D), Basis(),
			[RoomMesh.DOWN])
	painted.colour = Color(0.22, 0.46, 0.33)
	painted.box(Vector3(x1 - 0.06, gy + KIOSK_H * 0.5, z0 + 0.06), Vector3(0.1, KIOSK_H, 0.1), Basis(),
			[RoomMesh.DOWN])
	# The counter: its front of green planks, a dark wooden top, a shelf under.
	painted.box(Vector3((x0 + x1) * 0.5 + 0.03, gy + 0.5, z0 + 0.25), Vector3(KIOSK_W - 0.18, 1.0, 0.06), Basis(),
			[RoomMesh.DOWN])
	wood.colour = Color(0.58, 0.5, 0.44)
	wood.box(Vector3((x0 + x1) * 0.5 + 0.03, gy + 1.03, z0 + 0.15), Vector3(KIOSK_W - 0.1, 0.05, 0.5))
	# The shelves on the back (the parapet's inner face), the fridge beside them.
	wood.box(Vector3((x0 + x1) * 0.5, gy + 1.45, z1 - 0.18), Vector3(KIOSK_W - 1.1, 0.03, 0.3))
	wood.box(Vector3((x0 + x1) * 0.5, gy + 1.85, z1 - 0.18), Vector3(KIOSK_W - 1.1, 0.03, 0.3))
	wood.colour = Color.WHITE
	b.box(Vector3(x1 - 0.42, gy + 0.85, z1 - 0.4), Vector3(0.72, 1.7, 0.7), Basis(), [RoomMesh.DOWN])
	# The roof, its fascia board with the name, the awning's frame.
	b.box(Vector3((x0 + x1) * 0.5, gy + KIOSK_H + 0.05, (z0 + z1) * 0.5 - 0.1), Vector3(KIOSK_W + 0.1, 0.1,
			KIOSK_D + 0.2))
	b.colour = Color.WHITE
	painted.colour = Color(0.97, 0.95, 0.89)
	painted.box(Vector3((x0 + x1) * 0.5, gy + KIOSK_H - 0.12, z0 - 0.16), Vector3(KIOSK_W + 0.1, 0.42, 0.05))
	# The name in red paint on the board (strokes a hair proud).
	var sign := painted
	sign.colour = Color(0.76, 0.13, 0.09)
	# It faces the seats (-z): seen from there, +x is on the left, so the text runs towards -x.
	var sx0 := (x0 + x1) * 0.5 + Strokes.width(KIOSK_SIGN, 0.24) * 0.5
	for poly: PackedVector2Array in Strokes.lines(KIOSK_SIGN, 0.24):
		for i in poly.size() - 1:
			var a := Vector2(sx0 - poly[i].x, gy + KIOSK_H - 0.24 + poly[i].y)
			var e := Vector2(sx0 - poly[i + 1].x, gy + KIOSK_H - 0.24 + poly[i + 1].y)
			var d := (e - a).normalized()
			var nn := Vector2(-d.y, d.x) * 0.02
			var ext := d * 0.02
			var p := [a - ext - nn, e + ext - nn, e + ext + nn, a - ext + nn]
			sign.face([Vector3(p[0].x, p[0].y, z0 - 0.188), Vector3(p[1].x, p[1].y, z0 - 0.188),
					Vector3(p[2].x, p[2].y, z0 - 0.188), Vector3(p[3].x, p[3].y, z0 - 0.188)], Vector3.FORWARD)
	sign.colour = Color.WHITE
	# The awning: a striped canvas sloping out over the counter (unbaked, its stripes in vertex colours).
	var aw := _part(t, "soft")
	var stripes := 11
	for k in stripes:
		var xa := lerpf(x0 - 0.05, x1 + 0.05, float(k) / stripes)
		var xb := lerpf(x0 - 0.05, x1 + 0.05, float(k + 1) / stripes)
		aw.colour = Color(0.92, 0.9, 0.85) if k % 2 == 0 else Color(0.2, 0.38, 0.62)
		aw.face([Vector3(xa, gy + KIOSK_H - 0.36, z0 - 0.2), Vector3(xb, gy + KIOSK_H - 0.36, z0 - 0.2),
				Vector3(xb, gy + KIOSK_H - 0.7, z0 - 0.95), Vector3(xa, gy + KIOSK_H - 0.7, z0 - 0.95)],
				Vector3(0, 0.9, -0.45).normalized())
		aw.face([Vector3(xa, gy + KIOSK_H - 0.36, z0 - 0.2), Vector3(xb, gy + KIOSK_H - 0.36, z0 - 0.2),
				Vector3(xb, gy + KIOSK_H - 0.7, z0 - 0.95), Vector3(xa, gy + KIOSK_H - 0.7, z0 - 0.95)],
				Vector3(0, -0.9, 0.45).normalized())
		# Its valance, scalloped.
		aw.face([Vector3(xa, gy + KIOSK_H - 0.7, z0 - 0.95), Vector3(xb, gy + KIOSK_H - 0.7, z0 - 0.95),
				Vector3((xa + xb) * 0.5, gy + KIOSK_H - 0.86, z0 - 0.95)], Vector3.FORWARD)
		aw.face([Vector3(xa, gy + KIOSK_H - 0.7, z0 - 0.95), Vector3(xb, gy + KIOSK_H - 0.7, z0 - 0.95),
				Vector3((xa + xb) * 0.5, gy + KIOSK_H - 0.86, z0 - 0.95)], Vector3.BACK)
	aw.colour = Color.WHITE
	# Bottles on the shelves, cups on the counter (glass and china in their colours, on the canvas's material: at this
	# size nobody tells).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var bottle_colours: Array[Color] = [Color(0.25, 0.42, 0.18), Color(0.55, 0.32, 0.1), Color(0.8, 0.8, 0.76),
			Color(0.5, 0.12, 0.08), Color(0.2, 0.3, 0.45)]
	for shelf_y: float in [1.465, 1.865]:
		var x := x0 + 0.62
		while x < x1 - 0.62:
			aw.colour = bottle_colours[rng.randi() % bottle_colours.size()]
			var hb := rng.randf_range(0.22, 0.32)
			Shapes.lathe(aw, [Vector2(0.0, 0.0), Vector2(0.035, 0.0), Vector2(0.035, hb * 0.65), Vector2(0.014, hb * 0.8),
					Vector2(0.012, hb), Vector2(0.0, hb)], Vector3(x, gy + shelf_y, z1 - 0.2 + rng.randf_range(-0.05, 0.05)),
					7)
			x += rng.randf_range(0.085, 0.14)
	aw.colour = Color(0.92, 0.9, 0.86)
	for k in 5:
		Shapes.lathe(aw, [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.04, 0.09), Vector2(0.0, 0.09)],
				Vector3(x0 + 0.5 + k * 0.08, gy + 1.055 + (0.09 if k == 4 else 0.0), z0 + 0.2), 8)
	aw.colour = Color.WHITE
	# The fridge's lit front and the bulb inside the kiosk (accent group: the glow part's energy is the bulb's, the
	# fridge's colour scaled down to its own 1.1).
	var glow := _part(t, "glow_accent")
	glow.colour = Color(0.82, 0.9, 1.0) * (1.1 / ACCENT_ENERGY)
	Shapes.quad(glow, Vector3(x1 - 0.42, gy + 1.0, z1 - 0.749), Vector3(0.3, 0, 0), Vector3(0, 0.62, 0),
			Vector3.FORWARD)
	glow.colour = BULB
	var bulb_at := Vector3((x0 + x1) * 0.5, gy + KIOSK_H - 0.3, (z0 + z1) * 0.5)
	Shapes.lathe(glow, [Vector2(0.0, -0.07), Vector2(0.05, -0.04), Vector2(0.055, 0.01), Vector2(0.02, 0.06)], bulb_at, 8)
	glow.colour = Color.WHITE
	Shapes.beam(_part(t, "iron"), bulb_at + Vector3(0, 0.06, 0), bulb_at + Vector3(0, 0.25, 0), Vector2(0.01, 0.01))
	t._light.add_lamp(bulb_at + Vector3(0, -0.2, -0.6), BULB * 1.6, -1.0)
	t._bake_omni("KioskBulb", bulb_at + Vector3(0, -0.1, -0.2), 5.5, 0.7, BULB)
	_poster(t, Vector3(x0 - 0.04, gy + 1.3, (z0 + z1) * 0.5 + 0.2), Vector3.BACK, 1)


# --- Plants (unbaked: leaves in their vertex colours; pots baked) -------------------------------------------------------

static func _plants(t: Object, hw: float, _fz: float, bz: float, gy: float) -> void:
	# Leaves and bark on the leaves part, clay and tins on the pots part, each in its vertex colour.
	var b := _part(t, "leaves")
	var pots := _part(t, "pots")
	var clay := Color(0.64, 0.33, 0.2)
	var bark := Color(0.3, 0.22, 0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	var h := float(t.params["parapet_height"])
	# Bougainvillea over the right parapet, each from a big pot at its foot.
	for z in BOUGAINVILLEA:
		var base := Vector3(hw - 0.42, gy, z)
		pots.colour = clay
		Shapes.lathe(pots, [Vector2(0.24, 0.0), Vector2(0.34, 0.5), Vector2(0.38, 0.52), Vector2(0.38, 0.58),
				Vector2(0.3, 0.58), Vector2(0.3, 0.5)], base, 14)
		b.colour = bark
		_stems(b, rng, base + Vector3(0, 0.5, 0), Vector3(hw + 0.15, gy + h + 0.15, z), 3)
		b.colour = Color.WHITE
		_bougainvillea(b, rng, hw, z, gy + h, 2.4)
	# The lemon tree in the back left corner.
	var lemon_at := Vector3(-hw + 1.0, gy, bz - 1.1)
	pots.colour = clay
	Shapes.lathe(pots, [Vector2(0.3, 0.0), Vector2(0.4, 0.55), Vector2(0.45, 0.58), Vector2(0.45, 0.64),
			Vector2(0.36, 0.64), Vector2(0.36, 0.56)], lemon_at, 16)
	b.colour = bark
	_stems(b, rng, lemon_at + Vector3(0, 0.55, 0), lemon_at + Vector3(0.05, 1.5, 0.02), 3)
	b.colour = Color.WHITE
	_crown(b, rng, lemon_at + Vector3(0.05, 1.95, 0.0), Vector3(0.75, 0.6, 0.75), 520, Color(0.08, 0.2, 0.06),
			Color(0.16, 0.3, 0.1))
	for k in 22:
		var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.6), rng.randf_range(-1, 1)).normalized()
		var p := lemon_at + Vector3(0.05, 1.95, 0) + dirv * Vector3(0.72, 0.58, 0.72) * rng.randf_range(0.85, 1.02)
		b.colour = Color(0.95, 0.78, 0.12) * rng.randf_range(0.85, 1.05)
		_fruit(b, p, 0.045)
	b.colour = Color.WHITE
	# Geraniums in old oil tins: along the back parapet's foot and the left one's (the cat walks its top).
	var spots: Array = []
	for x: float in [-4.4, -3.7, -2.4, 2.4]:
		spots.append(Vector3(x, gy, bz - 0.2))
	for z: float in [-9.0, -4.3, 0.3, 4.6]:
		spots.append(Vector3(-hw + 0.2, gy, z))
	var tins: Array[Color] = [Color(0.2, 0.36, 0.62), Color(0.75, 0.72, 0.62), Color(0.2, 0.45, 0.3),
			Color(0.62, 0.22, 0.14), Color(0.8, 0.62, 0.18)]
	var blooms: Array[Color] = [Color(0.85, 0.08, 0.1), Color(0.9, 0.25, 0.45), Color(0.95, 0.9, 0.9),
			Color(0.75, 0.05, 0.25)]
	for p: Vector3 in spots:
		pots.colour = tins[rng.randi() % tins.size()]
		pots.box(p + Vector3(0, 0.17, 0), Vector3(0.24, 0.34, 0.24), Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)),
				[RoomMesh.DOWN])
		pots.colour = Color.WHITE
		b.colour = Color.WHITE
		_geranium(b, rng, p + Vector3(0, 0.34, 0), blooms[rng.randi() % blooms.size()])
	# Basil on the kiosk's counter.
	var basil := Vector3(hw - KIOSK_W + 0.35, gy + 1.055, bz - KIOSK_D + 0.18)
	pots.colour = clay
	Shapes.lathe(pots, [Vector2(0.07, 0.0), Vector2(0.1, 0.13), Vector2(0.0, 0.13)], basil, 10)
	b.colour = Color.WHITE
	_crown(b, rng, basil + Vector3(0, 0.26, 0), Vector3(0.15, 0.13, 0.15), 120, Color(0.14, 0.32, 0.08),
			Color(0.24, 0.44, 0.12))
	# Jasmine up the hut's front left corner and along its top: small dark leaves, white stars.
	var hx := float(HUT[0])
	var hz := bz - float(HUT[2])
	b.colour = bark
	_stems(b, rng, Vector3(hx - 0.15, gy, hz - 0.12), Vector3(hx - 0.05, gy + float(HUT[3]), hz - 0.05), 3)
	b.colour = Color.WHITE
	for k in 680:
		var y := pow(rng.randf(), 0.6) * float(HUT[3])
		var along := rng.randf()
		var at := Vector3(hx - 0.12 + rng.randf_range(-0.12, 0.1) + (along * 1.2 if y > float(HUT[3]) - 0.4 else 0.0),
				gy + y + rng.randf_range(-0.05, 0.1), hz - 0.06 - rng.randf_range(0.0, 0.18))
		var flower := rng.randf() < 0.22
		b.colour = Color(0.95, 0.94, 0.88) if flower else Color(0.06, 0.16, 0.05) * rng.randf_range(0.8, 1.4)
		var len := 0.04 if flower else rng.randf_range(0.05, 0.08)
		var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 0.2)).normalized()
		var across := dirv.cross(Vector3.FORWARD).normalized() * len * 0.5
		if across.length() < 0.001:
			across = Vector3.RIGHT * len * 0.5
		Shapes.leaf(b, at, dirv * len, across, dirv.cross(across).normalized())
	b.colour = Color.WHITE
	b.colour = Color.WHITE
	pots.colour = Color.WHITE


## Woody stems from a pot up to where the leaves are, twisting a little.
static func _stems(b: RoomMesh, rng: RandomNumberGenerator, from: Vector3, to: Vector3, count: int) -> void:
	for k in count:
		var prev := from + Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
		var end := to + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.1, 0.15), rng.randf_range(-0.6, 0.6))
		for i in range(1, 6):
			var f := i / 5.0
			var p := prev.lerp(end, 1.0 / (6 - i)) + Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
			if i == 5:
				p = end
			Shapes.beam(b, prev, p, Vector2(0.028, 0.028) * (1.2 - f * 0.6))
			prev = p


## Bougainvillea over a parapet's top at z: a mass of leaves along it, falling down both faces (most outside, down to
## the street's side), magenta bracts in clusters on its surface.
static func _bougainvillea(b: RoomMesh, rng: RandomNumberGenerator, hw: float, z: float, top: float, length: float) -> void:
	var clusters := int(length * 62.0)
	for i in clusters:
		var u := rng.randf_range(-1.0, 1.0)
		var along := u * length * 0.5
		# The mass is fullest in its middle, thinning to its ends.
		var full := sqrt(maxf(1.0 - u * u, 0.0))
		var side := rng.randf()
		var centre: Vector3
		if side < 0.5:
			# A mound over the top, from the inner edge to past the outer.
			centre = Vector3(hw + rng.randf_range(-0.1, 0.6), top + 0.06 + rng.randf() * 0.55 * full, z + along)
		elif side < 0.85:
			# Falling down the outer face, towards the street.
			centre = Vector3(hw + 0.36 + rng.randf_range(0.0, 0.3) * full, top - pow(rng.randf(), 0.8) * 1.7 * full,
					z + along)
		else:
			# Down the inner face, less far, and round the stems from the pot.
			centre = Vector3(hw - rng.randf_range(0.05, 0.3), top - pow(rng.randf(), 1.2) * 0.8 * full, z + along * 0.7)
		var bloom := rng.randf() < (0.62 if side < 0.85 else 0.35)
		var radius := rng.randf_range(0.1, 0.2)
		for j in 12:
			var is_bract := bloom and rng.randf() < 0.7
			if is_bract:
				b.colour = [Color(0.8, 0.05, 0.42), Color(0.88, 0.12, 0.5), Color(0.62, 0.06, 0.45),
						Color(0.92, 0.2, 0.55)][rng.randi() % 4]
			else:
				b.colour = Color(0.07, 0.17, 0.05) * rng.randf_range(0.8, 1.5)
			var at := centre + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius
			var len := rng.randf_range(0.07, 0.12) * (0.85 if is_bract else 1.0)
			var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1.0, 0.6), rng.randf_range(-1, 1)).normalized()
			var across := dirv.cross(Vector3.UP).normalized() * len * 0.45
			if across.length() < 0.001:
				across = Vector3.RIGHT * len * 0.45
			Shapes.leaf(b, at, dirv * len, across, dirv.cross(across).normalized())
	b.colour = Color.WHITE


## A crown of leaves: many in an ellipsoid's shell (`size` its half axes), the colours between two greens.
static func _crown(b: RoomMesh, rng: RandomNumberGenerator, centre: Vector3, size: Vector3, count: int, dark: Color,
		light: Color) -> void:
	for k in count:
		var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if dirv.length() < 0.05:
			continue
		dirv = dirv.normalized()
		var at := centre + dirv * size * rng.randf_range(0.65, 1.0)
		b.colour = dark.lerp(light, clampf(dirv.y * 0.5 + 0.5 + rng.randf_range(-0.3, 0.3), 0.0, 1.0))
		var len := rng.randf_range(0.06, 0.1)
		var along := (dirv + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.6), rng.randf_range(-0.6,
				0.6))).normalized()
		var across := along.cross(dirv).normalized() * len * 0.4
		if across.length() < 0.001:
			across = Vector3.RIGHT * len * 0.4
		Shapes.leaf(b, at, along * len, across, dirv)
	b.colour = Color.WHITE


## A small round fruit (a few faces).
static func _fruit(b: RoomMesh, p: Vector3, r: float) -> void:
	Shapes.lathe(b, [Vector2(0.0, -r), Vector2(r * 0.85, -r * 0.5), Vector2(r, 0.0), Vector2(r * 0.85, r * 0.5),
			Vector2(0.0, r)], p, 6)


## A geranium: round leaves low, flower heads on stalks over them.
static func _geranium(b: RoomMesh, rng: RandomNumberGenerator, top: Vector3, bloom: Color) -> void:
	for k in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.02, 0.2)
		var at := top + Vector3(cos(a) * r, rng.randf_range(0.0, 0.12), sin(a) * r)
		b.colour = Color(0.12, 0.28, 0.08) * rng.randf_range(0.8, 1.3)
		var out := Vector3(cos(a), 0.6, sin(a)).normalized()
		var across := out.cross(Vector3.UP).normalized() * 0.045
		Shapes.leaf(b, at, out * 0.08, across, out.cross(across).normalized())
	for k in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.14)
		var head := top + Vector3(cos(a) * r, rng.randf_range(0.18, 0.32), sin(a) * r)
		b.colour = bloom * rng.randf_range(0.85, 1.1)
		for j in 9:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
			var across := d.cross(Vector3.UP).normalized() * 0.02
			if across.length() < 0.001:
				across = Vector3.RIGHT * 0.02
			Shapes.leaf(b, head + d * 0.03, d * 0.04, across, d.cross(across).normalized())
	b.colour = Color.WHITE


# --- The bulbs -------------------------------------------------------------------------------------------------------

## The strings of bulbs: steel poles clamped to the side parapets, strings sagging from pole to pole along both sides,
## one across behind the seats, and from the last poles to the hut's roof and on to the kiosk's. Each bulb a small
## glowing globe in its socket and a soft halo (one draw for all). Their light: stand-in lamps, and bake lights.
static func _bulbs(t: Object, hw: float, _fz: float, bz: float, gy: float) -> ShaderMaterial:
	var poles := _part(t, "iron")
	var tops := {}
	for s: float in [-1.0, 1.0]:
		var zs: Array[float] = POLES_LEFT if s < 0.0 else POLES_RIGHT
		for z in zs:
			var x := s * (hw - 0.12)
			Shapes.cylinder(poles, Vector3(x, gy, z), 0.035, POLE_H, 8)
			# Its clamps to the parapet, a cap.
			for y: float in [0.35, 0.85]:
				poles.box(Vector3(s * (hw - 0.06), gy + y, z), Vector3(0.14, 0.05, 0.09))
			Shapes.lathe(poles, [Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.0, 0.04)], Vector3(x, gy + POLE_H, z), 8)
			tops["%d %.1f" % [int(s), z]] = Vector3(x, gy + POLE_H - 0.05, z)
	var strings: Array = []
	for s: float in [-1.0, 1.0]:
		var zs: Array[float] = POLES_LEFT if s < 0.0 else POLES_RIGHT
		for i in zs.size() - 1:
			strings.append([tops["%d %.1f" % [int(s), zs[i]]], tops["%d %.1f" % [int(s), zs[i + 1]]], 0.38])
	# Across behind the seats, and to the hut and the kiosk.
	strings.append([tops["-1 2.5"], tops["1 2.5"], 0.7])
	var hut_l := Vector3(float(HUT[0]) - 0.05, gy + float(HUT[3]) + 0.14, bz - float(HUT[2]) - 0.05)
	var hut_r := Vector3(float(HUT[1]) + 0.05, gy + float(HUT[3]) + 0.14, bz - float(HUT[2]) - 0.05)
	var kiosk := Vector3(hw - KIOSK_W - 0.02, gy + KIOSK_H + 0.12, bz - KIOSK_D - 0.12)
	strings.append([tops["-1 7.0"], hut_l, 0.45])
	strings.append([hut_r, kiosk, 0.3])
	strings.append([tops["1 4.6"], kiosk, 0.12])
	var wire := poles
	var globes := _part(t, "glow_house")
	var sockets := poles
	var halo_points: Array[Vector3] = []
	var lamp_c: Color = BULB * float(t._light.params["lamp_energy"]) * 0.42
	var lamps := 0
	var bakes := 0
	for e: Array in strings:
		var a: Vector3 = e[0]
		var c: Vector3 = e[1]
		var sag := float(e[2])
		var span := a.distance_to(c)
		var steps := maxi(int(span / 0.25), 4)
		var prev := a
		for j in range(1, steps + 1):
			var f := float(j) / steps
			var p := a.lerp(c, f) - Vector3(0, sag * 4.0 * f * (1.0 - f), 0)
			Shapes.beam(wire, prev, p, Vector2(0.008, 0.008))
			prev = p
		var count := maxi(int(span / BULB_STEP), 1)
		for j in range(1, count):
			var f := float(j) / count
			var p := a.lerp(c, f) - Vector3(0, sag * 4.0 * f * (1.0 - f) + 0.05, 0)
			Shapes.cylinder(sockets, p + Vector3(0, 0.0, 0), 0.016, 0.05, 6)
			Shapes.lathe(globes, [Vector2(0.0, -0.075), Vector2(0.03, -0.065), Vector2(0.04, -0.035), Vector2(0.03,
					-0.008), Vector2(0.014, 0.0)], p, 7)
			halo_points.append(p - Vector3(0, 0.04, 0))
		# The string's light: a stand-in lamp at its middle (eight at most in the room), a bake light too.
		var mid := a.lerp(c, 0.5) - Vector3(0, sag + 0.15, 0)
		if lamps < 5 and span > 3.0:
			t._light.add_lamp(mid, lamp_c, -1.0)
			lamps += 1
		if span > 2.0:
			t._bake_omni("Bulbs%d" % bakes, mid, 5.5, 0.35, BULB)
			bakes += 1
	return _halos(t, halo_points)


## The bulbs' halos: a quad each that turns to face the eye (shaders/env_halo.gdshader), added over what is behind.
static func _halos(t: Object, points: Array[Vector3]) -> ShaderMaterial:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in points:
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[k])
			st.set_normal(Vector3.BACK)
			st.add_vertex(p)
	var m := ShaderMaterial.new()
	m.shader = HALO_SHADER
	m.set_shader_parameter("colour", BULB)
	m.set_shader_parameter("size", 0.16)
	m.set_shader_parameter("energy", HALO_ENERGY * t._group_level("house"))
	m.set_shader_parameter("house_reference", float(t.room.get("ambient_level")))
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mi: MeshInstance3D = t._add_mesh("BulbHalos", mesh)
	# The halos face the eye, so their bounds are the points' plus their size.
	mi.custom_aabb = mesh.get_aabb().grow(0.3)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.add_to_group("env_see_through")
	return m


## The halos' brightness at the house lights' full level.
const HALO_ENERGY := 0.55
## The accent glow's energy (the kiosk's bulb; its fridge's front is dimmer by its vertex colour).
const ACCENT_ENERGY := 2.6
