extends RefCounted

## The Screening room 1962's pieces (docs/environments.md, "The kit" and "Room: Screening room 1962"; since 2026-11-08:
## "continue working on the environments one-by-one like you did with the bathysphere, really improving their quality,
## imagination, delight, detail, lighting and so on. Better to do a smaller number of incredible superb ones than a
## large number not so", the user, 2026-11-08). A collector's private cinema in a modernist house in the hills, 1962:
## walnut panels with shadow gaps between them, a screen wall of walnut slats over black felt with the picture in a
## deep walnut frame, a coffered ceiling with brass downlights, a floating hearth of slate under a brick chimney breast
## with a slow fire and a sunburst clock that tells the real time, a floor-to-ceiling window onto a terrace where the
## pool glows turquoise right outside the glass (its light rippling on the eaves and the ceiling), agaves in concrete
## bowls, palms down the slope and the city's lights far below in the valley. A credenza under the screen, a bar cart
## with decanters, a surfboard coffee table, a tripod lamp, a sheepskin by the fire, shelves of books and film cans
## round the projection port. Everything is ours, drawn here from boxes, lathes and strips; no figure, no brand.
##
## Pieces (pieces.gd dispatches here; none takes a slot: the room is the domestic builder's walnut_1962 box, its shell
## left to the kit):
##   screening_room       the walls, the screen wall and the picture's frame, the coffered ceiling and its downlights,
##                        the window and its curtains, the door, the shelves round the projection port, the sconces,
##                        the carpet and the rug
##   screening_hearth     the chimney breast, the floating hearth, the firebox and its fire, the logs, the clock
##   screening_furniture  the credenza, the bar cart, the coffee table, the tripod lamp, the sheepskin
##   screening_garden     outside: the eaves, the terrace, the pool, the planters, the palms, the low wall, the city
##
## Cost, by material into the kit's shared meshes: baked (PieceStatic) the walnut (two cuts of it, so neighbouring
## panels differ), the felt, the plaster, the brick, the slate, the carpet and rug, the curtains, the books, the tins,
## the ceramics and the bronze; unbaked (PieceSoft) the brass (it reflects) and the sheepskin; PieceLamps the shades,
## the downlights and the sconces' glow; PieceGlass the window and the decanters. The hall's own: the garden (one
## unshaded mesh, shaders/env_screening_outside.gdshader), the glows (one added mesh: the pool's ripples, the flames,
## the fire's glow, the city; shaders/env_screening_glow.gdshader), the clock's two hands.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const OUTSIDE_SHADER := preload("res://shaders/env_screening_outside.gdshader")
const GLOW_SHADER := preload("res://shaders/env_screening_glow.gdshader")

## The room: the domestic builder's walnut_1962 box (half width, the screen's wall, the back wall, the height).
const HW := 3.2
const FZ := -5.2
const BZ := 3.0
const H := 2.7
## The walls' walnut panels: their width (about), how far each stands off the wall, the shadow gaps between them,
## the dark gap at the floor (no skirting: the panels float over it) and under the ceiling.
const PANEL := 0.62
const PROUD := 0.02
const GAP := 0.008
const BASE := 0.07
const TOP_GAP := 0.02
## The screen wall's slats over felt: width, depth, pitch.
const SLAT_W := 0.042
const SLAT_D := 0.035
const SLAT_PITCH := 0.072
## The picture's frame: its opening (the painting's: the picture and 4 cm round it), its width, its face (the screen
## sits 6 cm back in it), a brass bead round the opening.
const FRAME_HALF := Vector2(1.34, 0.77)
const FRAME_W := 0.09
const FRAME_FACE := -5.08
## The window: floor to the ceiling's beam in the left wall between these z, PANES panes in slim bronze frames.
const WIN_Z0 := -4.9
const WIN_Z1 := -0.3
const PANES := 4
const MULLION := 0.045
## The chimney breast on the right wall (its z, depth), the floating hearth's slab (top, z, how far it stands out from
## the breast's face), the firebox's opening.
const BREAST_Z0 := -2.85
const BREAST_Z1 := -0.95
const BREAST_D := 0.42
const HEARTH_TOP := 0.4
const HEARTH_T := 0.075
const HEARTH_Z0 := -3.45
const HEARTH_Z1 := -0.35
const HEARTH_OUT := 0.5
const FIRE_Z0 := -2.32
const FIRE_Z1 := -1.48
const FIRE_Y0 := HEARTH_TOP + 0.06
const FIRE_Y1 := 1.06
const CLOCK_Y := 1.9
const CLOCK_R := 0.36
## The coffered ceiling: walnut beams on a grid, BAYS_X across and BAYS_Z along from the soffit over the screen wall
## (where the painting rises into its slot) to the back wall.
const SOFFIT_Z := -4.8
const BAYS_X := 5
const BAYS_Z := 6
const BEAM_W := 0.08
const BEAM_D := 0.13
## The shelves across the back wall from the door to the right wall, round the projection port.
const SHELF_X0 := -1.62
const SHELF_D := 0.36
const SHELF_TOP := 2.02
const PORT := Rect2(-0.19, 2.14, 0.38, 0.26)
const DOOR_X0 := -2.7
const DOOR_X1 := -1.84
const DOOR_TOP := 2.02
## Outside: the terrace's paving, the pool (its water's x and z, the coping round it), the low wall at the terrace's
## edge, the eaves over the glass.
const TERRACE_Y := -0.03
const POOL_X0 := -7.85
const POOL_X1 := -4.65
const POOL_Z0 := -7.6
const POOL_Z1 := -1.4
const COPING := 0.4
const WATER_Y := -0.16
const EDGE_X := -9.5
const EAVE_X := -4.9
## The pool's underwater lamps (in its far wall) and its colour (sRGB).
const POOL_LAMPS: Array[Vector3] = [Vector3(-7.8, -0.55, -5.9), Vector3(-7.8, -0.55, -3.1)]
const POOL_COLOUR := Color(0.32, 0.86, 0.88)

## Colours (sRGB; the meshes take them linear).
const WALNUT := Color(0.42, 0.26, 0.16)
const WALNUT_DARK := Color(0.2, 0.12, 0.075)
const SLAT := Color(0.46, 0.29, 0.17)
const FELT := Color(0.035, 0.032, 0.03)
## The ceiling's boards: narrow cedar planks between the beams (the kit's plaster key: wood_slats).
const BOARDS := Color(0.56, 0.4, 0.27)
const BRICK := Color(0.56, 0.38, 0.3)
const SLATE := Color(0.16, 0.16, 0.17)
const CARPET := Color(0.36, 0.27, 0.19)
const RUG := Color(0.62, 0.3, 0.13)
const RUG_BORDER := Color(0.82, 0.74, 0.58)
const RUG_LINE := Color(0.12, 0.1, 0.09)
const LINEN := Color(0.8, 0.74, 0.62)
const BRONZE := Color(0.16, 0.13, 0.1)
const BRASS := Color(0.86, 0.66, 0.34)
const SHEEPSKIN := Color(0.9, 0.86, 0.77)
const LAMP_LIGHT := Color(1.0, 0.72, 0.44)
## The lamps' own glow (shades, lenses, the sconces' rims: one material).
const LAMP_GLOW := Color(1.0, 0.8, 0.56)
## The brass's reflection (kit/reflect.gd): how much, how rough; one material for all of it.
const BRASS_SHINE := 0.6
const BRASS_ROUGH := 0.25
const FIRE_LIGHT := Color(1.0, 0.56, 0.24)
## The fire's waver (Hz): the builders' (builder.gd FLICKER_HZ), every one under the photosensitivity ceiling.
const FLICKER_HZ: Array[float] = [0.37, 0.83, 1.31, 2.07]
## The downlights' places (coffer centres), the sconces' ([place on its wall, its normal]).
const DOWNLIGHTS: Array[Vector2] = [Vector2(-2.56, -4.15), Vector2(2.56, -4.15), Vector2(2.56, 0.4),
		Vector2(-2.56, 1.7), Vector2(-1.28, 2.35), Vector2(1.28, 2.35), Vector2(1.28, -1.55), Vector2(-1.28, -1.55)]


## The hall's own meshes and materials (kept on the kit's ctx.halls; kit.gd calls finish() and tick()).
class Hall:
	var kit: Node
	var outside := Verts.new()
	var glow := Verts.new()
	var outside_m: ShaderMaterial
	var glow_m: ShaderMaterial
	var walnut_b: Material
	var city_tex: Texture2D
	## The window's panes: their own glass, faint (the kit's is a decanter's).
	var window_glass := RoomMesh.new()
	var hands: Array[MeshInstance3D] = []
	var fire_at := Vector3.ZERO
	var clock_at := Vector3.ZERO
	var water_t := 0.0
	var flame_t := 0.0
	var clock_t := 1.0
	var flicker_t := 0.0
	## The fire's level now (the accent lamps' level, wavering with the flicker), for the tests.
	var fire_level := 1.0

	func finish(k: Node) -> void:
		var noise := SkySys.noise_texture()
		var caustics := Procedural.caustic_map()
		if outside.count() > 0:
			outside_m = ShaderMaterial.new()
			outside_m.shader = OUTSIDE_SHADER
			outside_m.set_shader_parameter("caustic_map", caustics)
			outside_m.set_shader_parameter("pool_colour", POOL_COLOUR.srgb_to_linear())
			var mi: MeshInstance3D = k._add_mesh("Garden", outside.commit(outside_m))
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if glow.count() > 0:
			glow_m = ShaderMaterial.new()
			glow_m.shader = GLOW_SHADER
			glow_m.set_shader_parameter("caustic_map", caustics)
			glow_m.set_shader_parameter("noise_map", noise)
			glow_m.set_shader_parameter("city_map", city_tex)
			glow_m.set_shader_parameter("pool_colour", POOL_COLOUR.srgb_to_linear())
			var mi: MeshInstance3D = k._add_mesh("Glows", glow.commit(glow_m))
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mi.add_to_group("env_see_through")
		var crystal := k.find_child("PieceGlass", true, false) as MeshInstance3D
		if crystal == null:
			for n: Node in k.owned():
				if n is MeshInstance3D and str(n.name).begins_with("PieceGlass"):
					crystal = n
		if crystal != null and crystal.material_override is ShaderMaterial:
			(crystal.material_override as ShaderMaterial).set_shader_parameter("alpha", 0.08)
			(crystal.material_override as ShaderMaterial).set_shader_parameter("rim", 0.16)
		if window_glass.triangle_count() > 0:
			var wg: MeshInstance3D = k._add_glass("WindowGlass", window_glass, Color(0.42, 0.48, 0.52), 0.035)
			(wg.material_override as ShaderMaterial).set_shader_parameter("rim", 0.05)
		if fire_at != Vector3.ZERO:
			# Where the fire is (its sound's place; the tests find it).
			var marker := Node3D.new()
			marker.name = "Fire"
			marker.position = fire_at
			k.own(marker)
		if clock_at != Vector3.ZERO:
			_clock_hands(k)
		tick(0.0)

	## The clock's hands: a brass hour hand and a longer minute hand on the clock's axis (into the room, -x), each
	## its own node so it turns; set from the real time once a second (as slowly as a clock's hands move).
	func _clock_hands(k: Node) -> void:
		var brass: Material = k._ctx.shiny("gilt", 1.0, BRASS_SHINE, BRASS_ROUGH)
		for i in 2:
			var b := RoomMesh.new()
			b.surface(brass)
			b.colour = BRASS.srgb_to_linear()
			var length := CLOCK_R * (0.42 if i == 0 else 0.62)
			var w := 0.022 if i == 0 else 0.014
			# Along local +y from the pivot (a short tail behind it), flat in the clock's face (local x, y).
			b.box(Vector3(0.0, length * 0.5 - 0.03, 0.006 + 0.004 * i), Vector3(w, length + 0.06, 0.005))
			b.box(Vector3(0.0, length - 0.02, 0.006 + 0.004 * i), Vector3(w * 1.9, 0.05, 0.005))
			var mi: MeshInstance3D = k._add_mesh("ClockHour" if i == 0 else "ClockMinute", b.commit(false))
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			hands.append(mi)
		_set_hands()

	## The hands from the real time: the face looks into the room (-x), twelve up; clockwise as seen from the room.
	func _set_hands() -> void:
		if hands.size() < 2:
			return
		var t := Time.get_time_dict_from_system()
		var minutes := float(t["minute"]) + float(t["second"]) / 60.0
		var hours := fmod(float(t["hour"]), 12.0) + minutes / 60.0
		# The face's frame: x to the right as seen from the room (+z), y up, z out of the face into the room (-x).
		var face := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0))
		for i in 2:
			var a := TAU * (hours / 12.0 if i == 0 else minutes / 60.0)
			# Clockwise seen from the room: about the face's normal (local +z), negative.
			hands[i].transform = Transform3D(face * Basis(Vector3(0, 0, 1), -a), clock_at)

	## The clock's hands now, radians clockwise from twelve: [hour, minute] (tests).
	func hand_angles() -> Array:
		if hands.size() < 2:
			return []
		var out: Array = []
		for h: MeshInstance3D in hands:
			# Twelve is up (+y), three o'clock to the right seen from the room (+z).
			var up := h.transform.basis.y
			out.append(fposmod(atan2(up.z, up.y), TAU))
		return out

	func tick(delta: float) -> void:
		var p: Dictionary = kit.params
		var motion := float(p.get("water_motion", 1.0))
		water_t += delta * motion
		flame_t += delta
		flicker_t += delta
		var steady: bool = kit.host != null and kit.host.has_method("setting") and kit.host.setting("flicker") == false
		var w := 0.0
		if not steady:
			for i in FLICKER_HZ.size():
				w += sin(TAU * FLICKER_HZ[i] * flicker_t + 0.9 * (i + 1)) / (i + 1)
		fire_level = kit._group_level("accent") * (1.0 + 0.12 * float(p.get("flicker", 0.0)) * w)
		var glow_level := float(p.get("glow", 1.0))
		if outside_m != null:
			outside_m.set_shader_parameter("water_clock", water_t)
			outside_m.set_shader_parameter("pool_level", glow_level)
		if glow_m != null:
			glow_m.set_shader_parameter("water_clock", water_t)
			glow_m.set_shader_parameter("flame_clock", flame_t)
			glow_m.set_shader_parameter("pool_level", glow_level)
			glow_m.set_shader_parameter("fire_level", fire_level)
			glow_m.set_shader_parameter("city_level", 1.0)
		clock_t += delta
		if clock_t >= 1.0:
			clock_t = 0.0
			_set_hands()


## Vertices for a mesh of the hall's own (the garden, the glows): positions, normals, colours, UV and UV2 (x: the
## shader's kind), one surface.
class Verts:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func count() -> int:
		return idx.size()

	func vert(p: Vector3, nrm: Vector3, col: Color, t := Vector2.ZERO, kind := 0.0) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		uv2.append(Vector2(kind, 0.0))
		return v.size() - 1

	## A quad a, b, c, d (in order round it) facing nrm; cols one colour or four; UVs 0..1 (y down from d-c's edge).
	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, cols: Variant, kind := 0.0,
			uvs: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]) -> void:
		var cs: Array = cols if cols is Array else [cols, cols, cols, cols]
		var k0 := vert(a, nrm, cs[0], uvs[0], kind)
		vert(b, nrm, cs[1], uvs[1], kind)
		vert(cc, nrm, cs[2], uvs[2], kind)
		vert(d, nrm, cs[3], uvs[3], kind)
		# Godot draws the side where the corners run clockwise.
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			idx.append_array([k0, k0 + 2, k0 + 1, k0, k0 + 3, k0 + 2])
		else:
			idx.append_array([k0, k0 + 1, k0 + 2, k0, k0 + 2, k0 + 3])

	func tri(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, cols: Array, kind := 0.0) -> void:
		var k0 := vert(a, nrm, cols[0], Vector2.ZERO, kind)
		vert(b, nrm, cols[1], Vector2.ZERO, kind)
		vert(cc, nrm, cols[2], Vector2.ZERO, kind)
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			idx.append_array([k0, k0 + 2, k0 + 1])
		else:
			idx.append_array([k0, k0 + 1, k0 + 2])

	## A grid of points (rows of one length) with a normal and a colour at each.
	func grid(rows: Array, normals: Array, colours: Array, kind := 0.0) -> void:
		var w := (rows[0] as PackedVector3Array).size()
		var base := v.size()
		for i in rows.size():
			for j in w:
				vert((rows[i] as PackedVector3Array)[j], (normals[i] as PackedVector3Array)[j],
						(colours[i] as PackedColorArray)[j], Vector2(float(j) / maxf(w - 1, 1), float(i)), kind)
		for i in rows.size() - 1:
			for j in w - 1:
				var a := base + i * w + j
				var p0 := v[a]
				var p1 := v[a + 1]
				var p2 := v[a + w + 1]
				var fn := n[a] + n[a + w + 1]
				if (p1 - p0).cross(p2 - p0).dot(fn) > 0.0:
					idx.append_array([a, a + w + 1, a + 1, a, a + w, a + w + 1])
				else:
					idx.append_array([a, a + 1, a + w + 1, a, a + w + 1, a + w])

	func commit(m: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, m)
		return mesh


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	var h := hall(c)
	match piece:
		"screening_room":
			_room(c, h)
		"screening_hearth":
			_hearth(c, h)
		"screening_furniture":
			_furniture(c, h)
		"screening_garden":
			_garden(c, h)
	for b: RoomMesh in [c.s, c.u, c.lit, c.glass]:
		b.colour = Color.WHITE


## The hall on the kit's ctx (made with the first piece).
static func hall(c: Object) -> Hall:
	for h: Object in c.halls:
		if h is Hall:
			return h
	var h := Hall.new()
	h.kit = c.kit
	c.halls.append(h)
	return h


# --- Helpers ----------------------------------------------------------------------------------------------------------

static func _lin(colour: Color, alpha := 1.0) -> Color:
	var l := colour.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


## The brass (one material: the frames, pulls, lamps, the clock, the cart).
static func _brass(c: Object) -> Material:
	return c.shiny("gilt", 1.0, BRASS_SHINE, BRASS_ROUGH)


static func _solid(c: Object, centre: Vector3, size: Vector3) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, Basis()))


## A wall's frame: [origin (along 0, floor), along (unit), normal (into the room), length]. Along runs so that
## along x up = the normal (the box's basis is right-handed).
static func _wall(side: String) -> Array:
	match side:
		"left":
			return [Vector3(-HW, 0, BZ), Vector3(0, 0, -1), Vector3.RIGHT, BZ - FZ]
		"right":
			return [Vector3(HW, 0, FZ), Vector3(0, 0, 1), Vector3.LEFT, BZ - FZ]
		"back":
			return [Vector3(HW, 0, BZ), Vector3.LEFT, Vector3.FORWARD, HW * 2.0]
	return [Vector3(-HW, 0, FZ), Vector3.RIGHT, Vector3.BACK, HW * 2.0]


static func _at(w: Array, along: float, y: float, out := 0.0) -> Vector3:
	return (w[0] as Vector3) + (w[1] as Vector3) * along + Vector3.UP * y + (w[2] as Vector3) * out


static func _basis(w: Array) -> Basis:
	return Basis(w[1], Vector3.UP, w[2])


## The other cut of walnut (the same veneer, another part of the flitch): every other panel, so no two neighbours
## show the same figure.
static func _walnut_b(c: Object, h: Hall) -> Material:
	if h.walnut_b == null:
		var d: Dictionary = (c.kit.params["wood"] as Dictionary).duplicate()
		d["color"] = [1.0, 1.0, 1.0]
		var m: ShaderMaterial = c.kit._light.from_param(d, false)
		m.set_shader_parameter("instance_tint", true)
		m.set_shader_parameter("uv_offset", Vector2(0.43, 0.29))
		m.set_shader_parameter("uv_turn", PI)
		h.walnut_b = m
	return h.walnut_b


## Walnut panels on a wall between along a and b, from the floor's gap to the ceiling's: each a board standing PROUD
## off the wall (its face and its edges), a shadow gap between them, each its own shade; alternate panels the other
## cut. The wall behind is dark (the gaps).
static func _panels(c: Object, h: Hall, w: Array, a: float, b: float, y0 := BASE, y1 := H - TOP_GAP,
		seed_value := 0) -> void:
	if b - a < 0.05:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1962 + seed_value
	var basis := _basis(w)
	var count := maxi(1, roundi((b - a) / PANEL))
	var pw := (b - a) / count
	# The dark wall behind, its gaps.
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT_DARK * 0.4)
	Shapes.wall(c.s, _at(w, a, 0.0), w[1], w[2], b - a, H)
	for i in count:
		var mid := a + pw * (i + 0.5)
		var shade := rng.randf_range(0.88, 1.1)
		var warm := rng.randf_range(-0.04, 0.04)
		c.s.surface(c.tinted("wood") if (i + seed_value) % 2 == 0 else _walnut_b(c, h))
		c.s.colour = _lin(Color(WALNUT.r * shade * (1.0 + warm), WALNUT.g * shade, WALNUT.b * shade * (1.0 - warm)))
		c.s.box(_at(w, mid, (y0 + y1) * 0.5, PROUD * 0.5), Vector3(pw - GAP, y1 - y0, PROUD), basis,
				[RoomMesh.FRONT])


# --- The room ---------------------------------------------------------------------------------------------------------

static func _room(c: Object, h: Hall) -> void:
	_floor(c)
	_side_walls(c, h)
	_screen_wall(c, h)
	_ceiling(c)
	_window(c, h)
	_curtains(c)
	_door(c, h)
	_shelves(c)
	_sconces(c)
	_room_lights(c)


## The carpet wall to wall, deep and dark; a wool rug under the chairs in burnt orange with a cream border and a dark
## line inside it.
static func _floor(c: Object) -> void:
	c.s.surface(c.tinted("fabric"))
	c.s.colour = _lin(CARPET)
	c.s.face([Vector3(-HW, 0, FZ), Vector3(HW, 0, FZ), Vector3(HW, 0, BZ), Vector3(-HW, 0, BZ)], Vector3.UP)
	var lo := Vector2(-2.05, -0.95)
	var hi := Vector2(2.05, 2.62)
	var t := 0.014
	# The field, then the border's four bands and the line, each a hair higher (no fighting).
	c.s.colour = _lin(RUG)
	c.s.box(Vector3((lo.x + hi.x) * 0.5, t * 0.5, (lo.y + hi.y) * 0.5), Vector3(hi.x - lo.x, t, hi.y - lo.y),
			Basis(), [RoomMesh.DOWN])
	var bw := 0.2
	c.s.colour = _lin(RUG_BORDER)
	for band: Array in [[Vector2(lo.x, lo.y), Vector2(hi.x, lo.y + bw)], [Vector2(lo.x, hi.y - bw), Vector2(hi.x, hi.y)],
			[Vector2(lo.x, lo.y + bw), Vector2(lo.x + bw, hi.y - bw)], [Vector2(hi.x - bw, lo.y + bw),
			Vector2(hi.x, hi.y - bw)]]:
		var p0: Vector2 = band[0]
		var p1: Vector2 = band[1]
		c.s.face([Vector3(p0.x, t + 0.001, p0.y), Vector3(p1.x, t + 0.001, p0.y), Vector3(p1.x, t + 0.001, p1.y),
				Vector3(p0.x, t + 0.001, p1.y)], Vector3.UP)
	c.s.colour = _lin(RUG_LINE)
	var li := bw + 0.08
	var lw := 0.03
	for band: Array in [[Vector2(lo.x + li, lo.y + li), Vector2(hi.x - li, lo.y + li + lw)],
			[Vector2(lo.x + li, hi.y - li - lw), Vector2(hi.x - li, hi.y - li)],
			[Vector2(lo.x + li, lo.y + li + lw), Vector2(lo.x + li + lw, hi.y - li - lw)],
			[Vector2(hi.x - li - lw, lo.y + li + lw), Vector2(hi.x - li, hi.y - li - lw)]]:
		var p0: Vector2 = band[0]
		var p1: Vector2 = band[1]
		c.s.face([Vector3(p0.x, t + 0.001, p0.y), Vector3(p1.x, t + 0.001, p0.y), Vector3(p1.x, t + 0.001, p1.y),
				Vector3(p0.x, t + 0.001, p1.y)], Vector3.UP)


## The side and back walls in walnut panels: the left wall either side of the window, the right wall either side of
## the chimney breast, the back wall from the left corner to the shelves (round the door).
static func _side_walls(c: Object, h: Hall) -> void:
	var left := _wall("left")
	_panels(c, h, left, 0.0, BZ - WIN_Z1, BASE, H - TOP_GAP, 1)
	_panels(c, h, left, BZ - WIN_Z0, BZ - FZ, BASE, H - TOP_GAP, 2)
	var right := _wall("right")
	_panels(c, h, right, 0.0, BREAST_Z0 - FZ, BASE, H - TOP_GAP, 3)
	_panels(c, h, right, BREAST_Z1 - FZ, BZ - FZ, BASE, H - TOP_GAP, 4)
	var back := _wall("back")
	# From the shelves' end to the corner, the door's opening left: a panel over it, the two beside it.
	var d0 := HW - DOOR_X1
	var d1 := HW - DOOR_X0
	_panels(c, h, back, HW - SHELF_X0, d0, BASE, H - TOP_GAP, 5)
	_panels(c, h, back, d1, HW * 2.0, BASE, H - TOP_GAP, 6)
	_panels(c, h, back, d0, d1, DOOR_TOP + GAP, H - TOP_GAP, 7)


## The screen wall: walnut slats over black felt from corner to corner, round the picture's deep walnut frame; a brass
## bead round the frame's opening. The picture sits 6 cm back in the frame (the painting slides up in front of it).
static func _screen_wall(c: Object, h: Hall) -> void:
	c.s.surface(c.tinted("cloth"))
	c.s.colour = _lin(FELT)
	c.s.face([Vector3(-HW, 0, FZ), Vector3(HW, 0, FZ), Vector3(HW, H, FZ), Vector3(-HW, H, FZ)], Vector3.BACK)
	var cy := 1.68
	var outer := FRAME_HALF + Vector2(FRAME_W, FRAME_W)
	var rng := RandomNumberGenerator.new()
	rng.seed = 621
	c.s.surface(c.tinted("wood"))
	var count := int((HW * 2.0 - SLAT_W) / SLAT_PITCH)
	var x0 := -(count - 1) * SLAT_PITCH * 0.5
	for i in count:
		var x := x0 + i * SLAT_PITCH
		var k := rng.randf_range(0.9, 1.08)
		c.s.colour = _lin(SLAT * k)
		var spans: Array[Vector2] = [Vector2(0.0, H)]
		if absf(x) < outer.x + SLAT_W * 0.5 + 0.01:
			spans = [Vector2(0.0, cy - outer.y - 0.01), Vector2(cy + outer.y + 0.01, H)]
		for s: Vector2 in spans:
			if s.y - s.x < 0.02:
				continue
			c.s.box(Vector3(x, (s.x + s.y) * 0.5, FZ + SLAT_D * 0.5), Vector3(SLAT_W, s.y - s.x, SLAT_D), Basis(),
					[RoomMesh.FRONT, RoomMesh.DOWN, RoomMesh.UP])
	# The frame: four rails mitred by overlap, their faces and outer edges; the opening's reveal down to the wall.
	var depth := FRAME_FACE - FZ
	var zc := FZ + depth * 0.5
	c.s.colour = _lin(WALNUT * 0.82)
	for sd: float in [-1.0, 1.0]:
		c.s.box(Vector3(sd * (FRAME_HALF.x + FRAME_W * 0.5), cy, zc), Vector3(FRAME_W, outer.y * 2.0, depth), Basis(),
				[RoomMesh.FRONT])
		c.s.box(Vector3(0.0, cy + sd * (FRAME_HALF.y + FRAME_W * 0.5), zc), Vector3(FRAME_HALF.x * 2.0, FRAME_W, depth),
				Basis(), [RoomMesh.FRONT, RoomMesh.LEFT, RoomMesh.RIGHT])
	_solid(c, Vector3(0.0, cy, zc), Vector3(outer.x * 2.0, outer.y * 2.0, depth))
	# The brass bead on the frame's face round the opening.
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	var bead := 0.012
	for sd: float in [-1.0, 1.0]:
		c.u.box(Vector3(sd * (FRAME_HALF.x + bead * 0.5), cy, FRAME_FACE + 0.003), Vector3(bead, FRAME_HALF.y * 2.0 + bead * 2.0,
				0.006), Basis(), [RoomMesh.FRONT])
		c.u.box(Vector3(0.0, cy + sd * (FRAME_HALF.y + bead * 0.5), FRAME_FACE + 0.003), Vector3(FRAME_HALF.x * 2.0, bead,
				0.006), Basis(), [RoomMesh.FRONT])


## The coffered ceiling: cedar boards between walnut beams on a grid from the soffit over the screen wall to the back wall;
## a brass downlight in some coffers (their glow the house lamps'); the soffit flat (the painting rises into its slot
## there), two wall-washers in it light the screen wall's slats.
static func _ceiling(c: Object) -> void:
	c.s.surface(c.tinted("plaster"))
	c.s.colour = _lin(BOARDS)
	c.s.face([Vector3(-HW, H, FZ), Vector3(HW, H, FZ), Vector3(HW, H, BZ), Vector3(-HW, H, BZ)], Vector3.DOWN)
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT * 0.85)
	var y := H - BEAM_D * 0.5
	var bx := (HW * 2.0) / BAYS_X
	var bz := (BZ - SOFFIT_Z) / BAYS_Z
	# Beams across (along x), at each line from the soffit to the back wall; the last against the wall, half width.
	for j in BAYS_Z + 1:
		var z := SOFFIT_Z + j * bz
		var wz := BEAM_W if j < BAYS_Z else BEAM_W * 0.5
		var zc := z if j < BAYS_Z else z - wz * 0.5
		var x1 := HW - (BREAST_D if zc > BREAST_Z0 and zc < BREAST_Z1 else 0.0)
		c.s.box(Vector3((-HW + x1) * 0.5, y, zc), Vector3(x1 + HW, BEAM_D, wz), Basis(), [RoomMesh.UP])
	# Beams along (z), between the cross beams, at each line across; the outer ones against the walls, half width.
	for i in BAYS_X + 1:
		var x := -HW + i * bx
		var wx := BEAM_W if i > 0 and i < BAYS_X else BEAM_W * 0.5
		var xc := x + (wx * 0.5 if i == 0 else (-wx * 0.5 if i == BAYS_X else 0.0))
		for j in BAYS_Z:
			var z0 := SOFFIT_Z + j * bz + BEAM_W * 0.5
			var z1 := SOFFIT_Z + (j + 1) * bz - (BEAM_W * 0.5 if j < BAYS_Z - 1 else BEAM_W * 0.5)
			if i == BAYS_X:
				# Not into the chimney breast.
				if z1 > BREAST_Z0 and z0 < BREAST_Z1:
					var parts: Array[Vector2] = []
					if z0 < BREAST_Z0:
						parts.append(Vector2(z0, BREAST_Z0))
					if z1 > BREAST_Z1:
						parts.append(Vector2(BREAST_Z1, z1))
					for pr: Vector2 in parts:
						c.s.box(Vector3(xc, y, (pr.x + pr.y) * 0.5), Vector3(wx, BEAM_D, pr.y - pr.x), Basis(), [RoomMesh.UP])
					continue
			c.s.box(Vector3(xc, y, (z0 + z1) * 0.5), Vector3(wx, BEAM_D, z1 - z0), Basis(), [RoomMesh.UP])
	# The downlights: a brass ring flush with the plaster round a glowing lens set up in its can.
	for d: Vector2 in DOWNLIGHTS:
		_downlight(c, Vector3(d.x, H, d.y))
	for sd: float in [-1.0, 1.0]:
		_downlight(c, Vector3(sd * 2.3, H, -4.98), 0.045)


static func _downlight(c: Object, at: Vector3, r := 0.06) -> void:
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	# From the inside out, so the faces look down.
	Shapes.lathe(c.u, [Vector2(r * 0.92, 0.0), Vector2(r, -0.006), Vector2(r + 0.025, -0.003)], at, 20)
	# The can's inside, dark, and the lens up in it.
	c.lit.surface(c.shade(LAMP_GLOW))
	var corners: Array = []
	for k in 16:
		var a := TAU * k / 16.0
		corners.append(at + Vector3(cos(a) * r * 0.85, -0.004, sin(a) * r * 0.85))
	c.lit.face(corners, Vector3.DOWN)


## The window: floor to the beam in the left wall, PANES panes between slim bronze mullions, a bronze head and
## threshold; clear glass.
static func _window(c: Object, h: Hall) -> void:
	var top := H - BEAM_D
	c.s.surface(c.tinted("iron"))
	c.s.colour = _lin(BRONZE)
	var x := -HW
	var pw := (WIN_Z1 - WIN_Z0) / PANES
	for k in PANES + 1:
		var z := WIN_Z0 + k * pw
		var wz := MULLION * (1.6 if k == 0 or k == PANES else 1.0)
		c.s.box(Vector3(x, top * 0.5, z), Vector3(0.11, top, wz), Basis(), [RoomMesh.LEFT])
	c.s.box(Vector3(x, top - 0.025, (WIN_Z0 + WIN_Z1) * 0.5), Vector3(0.12, 0.05, WIN_Z1 - WIN_Z0), Basis(),
			[RoomMesh.LEFT, RoomMesh.UP])
	c.s.box(Vector3(x, 0.012, (WIN_Z0 + WIN_Z1) * 0.5), Vector3(0.14, 0.024, WIN_Z1 - WIN_Z0), Basis(),
			[RoomMesh.DOWN])
	# The glass, a hair outside the mullions' middle.
	h.window_glass.surface(c.kit.GLASS)
	for k in PANES:
		var z0 := WIN_Z0 + k * pw
		Shapes.quad(h.window_glass, Vector3(x - 0.01, top * 0.5, z0 + pw * 0.5), Vector3(0, 0, pw * 0.5), Vector3(0, top * 0.5, 0),
				Vector3.RIGHT)
	# The wall's thickness either side of the glass (into the room the panels' edge), dark walnut.
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT_DARK)
	for z: float in [WIN_Z0, WIN_Z1]:
		var sd := 1.0 if z == WIN_Z0 else -1.0
		c.s.face([Vector3(-HW - 0.15, 0, z), Vector3(-HW + PROUD, 0, z), Vector3(-HW + PROUD, H, z),
				Vector3(-HW - 0.15, H, z)], Vector3(0, 0, sd))


## Linen curtains drawn back to either end of the window, hung from a track recessed in the ceiling: deep, soft folds
## from the ceiling to the floor, standing in front of the panels, each fold's trough in its own shadow (the folds are
## finer than the lightmap: their shading rides in the vertex colours).
static func _curtains(c: Object) -> void:
	c.s.surface(c.tinted("cloth"))
	for stack: Vector2 in [Vector2(WIN_Z0 - 0.24, WIN_Z0 + 0.3), Vector2(WIN_Z1 - 0.3, WIN_Z1 + 0.44)]:
		var folds := 7
		var n := folds * 6
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		var dz := (stack.y - stack.x)
		for j in 2:
			var y := 0.012 if j == 0 else H
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for k in n + 1:
				var t := float(k) / n
				var z := stack.x + dz * t
				var ph := t * folds * TAU
				var amp := 0.06 * (0.75 + 0.25 * sin(t * 5.0 + 1.0))
				var xo := -HW + 0.14 + amp * sin(ph)
				var slope := amp * cos(ph) * folds * TAU / dz
				row.append(Vector3(xo, y, z))
				nrow.append(Vector3(1.0, 0.0, -slope).normalized())
				# The trough (back towards the wall) in shadow, the crest catching the light; darker at the foot.
				var lit := 0.55 + 0.45 * (0.5 + 0.5 * sin(ph))
				crow.append(_lin(LINEN * lit * (0.82 if j == 0 else 1.0)))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		c.s.sheet(rows, norms, cols, Vector3(0, 0, 1), Vector3.UP)
		_solid(c, Vector3(-HW + 0.14, H * 0.5, (stack.x + stack.y) * 0.5), Vector3(0.14, H, stack.y - stack.x))
	c.s.colour = Color.WHITE


## The door at the back: a flush walnut leaf a little in from the panels' face in its shadow-gap opening, a long
## brass pull.
static func _door(c: Object, h: Hall) -> void:
	var back := _wall("back")
	var basis := _basis(back)
	var a0 := HW - DOOR_X1
	var a1 := HW - DOOR_X0
	c.s.surface(_walnut_b(c, h))
	c.s.colour = _lin(WALNUT * 1.05)
	c.s.box(_at(back, (a0 + a1) * 0.5, DOOR_TOP * 0.5, 0.008), Vector3(a1 - a0 - 0.012, DOOR_TOP - 0.008, 0.016), basis,
			[RoomMesh.FRONT])
	# The opening's reveal (the wall's thickness round the leaf).
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT_DARK)
	for along: float in [a0, a1]:
		c.s.box(_at(back, along, DOOR_TOP * 0.5, 0.01), Vector3(0.004, DOOR_TOP, 0.02), basis)
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	var px := a0 + 0.1
	c.u.box(_at(back, px, 1.05, 0.06), Vector3(0.02, 0.5, 0.02), basis)
	for y: float in [0.85, 1.25]:
		c.u.box(_at(back, px, y, 0.035), Vector3(0.014, 0.014, 0.05), basis)


## The shelves across the back wall from the door to the right wall, floor to ceiling: a cupboard under (its doors in
## the other cut), open shelves of books and film cans over it in bays, a walnut fascia at the top round the
## projection port (the booth behind the back wall: its lens a warm glow behind dark glass).
static func _shelves(c: Object) -> void:
	var x0 := SHELF_X0
	var x1 := HW
	var zf := BZ - SHELF_D
	var zc := BZ - SHELF_D * 0.5
	var t := 0.025
	c.s.surface(c.tinted("wood"))
	# The back (dark), the sides, the bays' uprights, the shelves.
	c.s.colour = _lin(WALNUT_DARK * 0.7)
	c.s.face([Vector3(x0, 0, BZ - 0.002), Vector3(x1, 0, BZ - 0.002), Vector3(x1, SHELF_TOP, BZ - 0.002),
			Vector3(x0, SHELF_TOP, BZ - 0.002)], Vector3.FORWARD)
	c.s.colour = _lin(WALNUT)
	var bays := 4
	var bw := (x1 - x0) / bays
	for k in bays + 1:
		var x := x0 + k * bw
		var wx := t if k > 0 and k < bays else t * 1.6
		c.s.box(Vector3(clampf(x, x0 + wx * 0.5, x1 - wx * 0.5), SHELF_TOP * 0.5, zc), Vector3(wx, SHELF_TOP, SHELF_D),
				Basis(), [RoomMesh.BACK])
	var levels: Array[float] = [0.72, 1.16, 1.58, SHELF_TOP - t * 0.5]
	for y: float in levels:
		c.s.box(Vector3((x0 + x1) * 0.5, y, zc), Vector3(x1 - x0, t, SHELF_D), Basis(), [RoomMesh.BACK])
	# The cupboard's doors under the first shelf (two a bay), a recessed plinth.
	c.s.colour = _lin(WALNUT * 0.95)
	for k in bays * 2:
		var dx0 := x0 + k * bw * 0.5 + 0.004
		var dx1 := x0 + (k + 1) * bw * 0.5 - 0.004
		c.s.box(Vector3((dx0 + dx1) * 0.5, (0.08 + levels[0] - t * 0.5) * 0.5, zf - 0.006), Vector3(dx1 - dx0,
				levels[0] - t * 0.5 - 0.08, 0.02), Basis(), [RoomMesh.BACK])
	c.s.colour = _lin(FELT)
	c.s.face([Vector3(x0, 0, zf + 0.04), Vector3(x1, 0, zf + 0.04), Vector3(x1, 0.08, zf + 0.04), Vector3(x0, 0.08, zf + 0.04)],
			Vector3.FORWARD)
	# The fascia over the shelves, to the ceiling, round the port.
	c.s.colour = _lin(WALNUT)
	Shapes.wall(c.s, Vector3(x0, SHELF_TOP, zf), Vector3.RIGHT, Vector3.FORWARD, x1 - x0, H - SHELF_TOP,
			[Rect2(PORT.position.x - x0, PORT.position.y - SHELF_TOP, PORT.size.x, PORT.size.y)])
	# Small walnut pulls on the doors.
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	for k in bays * 2:
		var dx := x0 + (k + (0.85 if k % 2 == 0 else 0.15)) * bw * 0.5
		c.u.box(Vector3(dx, levels[0] - 0.09, zf + 0.025), Vector3(0.012, 0.09, 0.012))
	_solid(c, Vector3((x0 + x1) * 0.5, SHELF_TOP * 0.5, zc), Vector3(x1 - x0, SHELF_TOP, SHELF_D))
	_port(c, zf)
	_books(c, x0, x1, bw, levels, zf)


## The projection port: a bronze-framed opening in the fascia, dark glass in it, the projector's lens a warm glow
## behind (the booth's light: the booth group).
static func _port(c: Object, zf: float) -> void:
	c.s.surface(c.tinted("iron"))
	c.s.colour = _lin(BRONZE)
	var r := PORT
	for k: Array in [[Vector3(r.position.x - 0.012, r.get_center().y, zf), Vector3(0.024, r.size.y + 0.048, 0.03)],
			[Vector3(r.end.x + 0.012, r.get_center().y, zf), Vector3(0.024, r.size.y + 0.048, 0.03)],
			[Vector3(r.get_center().x, r.position.y - 0.012, zf), Vector3(r.size.x, 0.024, 0.03)],
			[Vector3(r.get_center().x, r.end.y + 0.012, zf), Vector3(r.size.x, 0.024, 0.03)]]:
		c.s.box(k[0], k[1], Basis(), [RoomMesh.BACK])
	# The booth's dark inside behind the glass.
	c.s.colour = _lin(Color(0.02, 0.02, 0.02))
	c.s.box(Vector3(r.get_center().x, r.get_center().y, zf + 0.25), Vector3(r.size.x, r.size.y, 0.5), Basis(),
			[RoomMesh.FRONT], true)
	var h: Hall = hall(c)
	h.window_glass.surface(c.kit.GLASS)
	Shapes.quad(h.window_glass, Vector3(r.get_center().x, r.get_center().y, zf + 0.02), Vector3(r.size.x * 0.5, 0, 0),
			Vector3(0, r.size.y * 0.5, 0), Vector3.FORWARD)
	# The lens: a small warm disc deep in the booth.
	var lens: Array = []
	for k in 14:
		var a := TAU * k / 14.0
		lens.append(Vector3(r.get_center().x + cos(a) * 0.045, r.get_center().y - 0.02 + sin(a) * 0.045, zf + 0.42))
	c.lit.surface(c.kit._lamp(Color(1.0, 0.82, 0.6), 0.9, 0.0, "booth"))
	c.lit.face(lens, Vector3.FORWARD)


## Books and film cans on the shelves: runs of books (each its own height, depth, colour, a lighter band on the
## spine), a few leaning, flat stacks of film cans (silver, a coloured label), reel cans on edge, a ceramic or two.
static func _books(c: Object, x0: float, x1: float, bw: float, levels: Array[float], zf: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1962
	var spines: Array[Color] = [Color(0.45, 0.12, 0.1), Color(0.12, 0.22, 0.32), Color(0.62, 0.52, 0.34),
			Color(0.2, 0.3, 0.2), Color(0.75, 0.68, 0.55), Color(0.55, 0.3, 0.12), Color(0.1, 0.1, 0.1),
			Color(0.32, 0.18, 0.28), Color(0.7, 0.45, 0.15), Color(0.85, 0.82, 0.74)]
	var t := 0.025
	for li in levels.size() - 1:
		var y := levels[li] + t * 0.5
		var room_h := levels[li + 1] - t * 0.5 - y
		for k in 4:
			var bx0 := x0 + k * bw + 0.03
			var bx1 := x0 + (k + 1) * bw - 0.03
			var kind := (li * 4 + k * 3 + 1) % 5
			if kind == 0:
				_film_cans(c, rng, Vector3((bx0 + bx1) * 0.5 - 0.25, y, zf + SHELF_D * 0.48), 4 + rng.randi() % 3)
				_film_cans(c, rng, Vector3((bx0 + bx1) * 0.5 + 0.2, y, zf + SHELF_D * 0.48), 2 + rng.randi() % 3)
				continue
			var x := bx0 + (0.0 if kind != 3 else 0.32)
			var stop := bx1 - (0.0 if kind != 2 else 0.35)
			while x < stop - 0.02:
				var bt := rng.randf_range(0.022, 0.05)
				var bh := minf(rng.randf_range(0.19, 0.31), room_h - 0.02)
				var bd := rng.randf_range(0.15, 0.24)
				if x + bt > stop:
					break
				var col: Color = spines[rng.randi() % spines.size()] * rng.randf_range(0.8, 1.1)
				c.s.surface(c.tinted("cloth"))
				c.s.colour = _lin(col)
				var centre := Vector3(x + bt * 0.5, y + bh * 0.5, zf + 0.03 + bd * 0.5)
				c.s.box(centre, Vector3(bt, bh, bd), Basis(), [RoomMesh.BACK, RoomMesh.DOWN])
				# A band of the title's colour across the spine.
				if rng.randf() < 0.7:
					c.s.colour = _lin(col.lerp(Color(0.92, 0.85, 0.65), 0.55))
					c.s.box(Vector3(centre.x, y + bh * rng.randf_range(0.6, 0.82), zf + 0.029), Vector3(bt * 0.8, 0.018,
							0.002), Basis(), [RoomMesh.BACK])
				x += bt + 0.002
			if kind == 2:
				# A stack of film cans at the end of the run.
				_film_cans(c, rng, Vector3(bx1 - 0.18, y, zf + SHELF_D * 0.48), 3 + rng.randi() % 3)
			elif kind == 3:
				# A ceramic at the start of the run.
				_vessel(c, Vector3(bx0 + 0.15, y, zf + SHELF_D * 0.5), 0.06, minf(0.24, room_h - 0.04),
						[Color(0.12, 0.38, 0.38), Color(0.78, 0.4, 0.15), Color(0.85, 0.8, 0.7)][li % 3])


## A flat stack of film cans: round tins, silver, each a little askew, a label of colour on the lid of the top one.
static func _film_cans(c: Object, rng: RandomNumberGenerator, at: Vector3, count: int) -> void:
	var y := at.y
	var r := 0.17
	for k in count:
		var off := Vector3(rng.randf_range(-0.012, 0.012), 0, rng.randf_range(-0.012, 0.012))
		var hgt := 0.032
		c.s.surface(c.tinted("tin"))
		c.s.colour = _lin(Color(0.62, 0.62, 0.6) * rng.randf_range(0.82, 1.05))
		Shapes.cylinder(c.s, at + off + Vector3(0, y - at.y, 0), r, hgt, 18)
		# The lid's rim: a hair proud.
		Shapes.lathe(c.s, [Vector2(r + 0.004, 0.0), Vector2(r + 0.004, 0.008)], at + off + Vector3(0, y - at.y + hgt - 0.008, 0),
				18)
		if k == count - 1:
			c.s.surface(c.tinted("cloth"))
			c.s.colour = _lin([Color(0.85, 0.2, 0.1), Color(0.95, 0.85, 0.5), Color(0.2, 0.4, 0.7)][rng.randi() % 3])
			var lab: Array = []
			for j in 12:
				var a := TAU * j / 12.0
				lab.append(at + off + Vector3(cos(a) * 0.06, y - at.y + hgt + 0.001, sin(a) * 0.06))
			c.s.face(lab, Vector3.UP)
		y += hgt + 0.001


## A ceramic vessel: a bottle form turned on the wheel, glazed (china, its colour per vertex).
static func _vessel(c: Object, at: Vector3, r: float, hgt: float, colour: Color) -> void:
	c.u.surface(c.soft("china"))
	c.u.colour = _lin(colour)
	Shapes.lathe(c.u, [Vector2(r * 0.55, 0.0), Vector2(r, hgt * 0.18), Vector2(r * 0.95, hgt * 0.45),
			Vector2(r * 0.42, hgt * 0.72), Vector2(r * 0.22, hgt * 0.86), Vector2(r * 0.26, hgt), Vector2(r * 0.18, hgt)],
			at, 16)


## The sconces: brass cylinders on short arms, open top and bottom, their light up and down the walnut (scallops) in
## the bake; the glow at their ends the house lamps'.
static func _sconces(c: Object) -> void:
	var places: Array = [["right", -4.2 - FZ], ["right", 0.62 - FZ], ["left", BZ - 1.65]]
	for p: Array in places:
		var w := _wall(str(p[0]))
		var along := float(p[1])
		var nrm: Vector3 = w[2]
		var at := _at(w, along, 1.78, PROUD)
		var body := at + nrm * 0.12
		c.u.surface(_brass(c))
		c.u.colour = _lin(BRASS)
		# The back plate, the arm, the cylinder (both ends open: a lip inside each).
		c.u.box(at + nrm * 0.006, Vector3(0.07, 0.16, 0.012), _basis(w))
		Shapes.beam(c.u, at + nrm * 0.01, body - nrm * 0.05, Vector2(0.018, 0.018))
		Shapes.lathe(c.u, [Vector2(0.05, -0.13), Vector2(0.055, -0.12), Vector2(0.055, 0.12), Vector2(0.05, 0.13)], body,
				20)
		Shapes.lathe(c.u, [Vector2(0.05, 0.13), Vector2(0.046, 0.0), Vector2(0.05, -0.13)], body, 20)
		c.lit.surface(c.shade(LAMP_GLOW))
		for e: float in [-1.0, 1.0]:
			var ring: Array = []
			for k in 16:
				var a := TAU * k / 16.0
				ring.append(body + Vector3(cos(a) * 0.044, e * 0.1, sin(a) * 0.044))
			c.lit.face(ring, Vector3(0, -e, 0))
		# The bake: light up and down the wall.
		c.spots.append([body + Vector3(0, 0.1, 0), body + Vector3(0, 2.0, 0) - nrm * 0.12, LAMP_LIGHT, 1.6, 2.4, 26.0])
		c.spots.append([body - Vector3(0, 0.1, 0), body - Vector3(0, 2.0, 0) - nrm * 0.08, LAMP_LIGHT, 2.0, 3.0, 28.0])
		c.kit._light.add_lamp(body + nrm * 0.15, LAMP_LIGHT * 0.9, cos(deg_to_rad(40.0)))


## The room's light in the bake: the downlights' pools on the carpet and the walls, the wall-washers' light down the
## screen wall's slats (either side of the frame), and a little of the night's cool light through the glass.
static func _room_lights(c: Object) -> void:
	for d: Vector2 in DOWNLIGHTS:
		var at := Vector3(d.x, H - 0.03, d.y)
		# Near a wall: aimed a little at it (a wash down the panels, the shelves); else straight down (a pool).
		var aim := Vector3(signf(d.x) * 0.3 if absf(d.x) > 2.0 else 0.0, -2.0, 0.55 if d.y > 2.0 else 0.0)
		c.spots.append([at, at + aim, LAMP_LIGHT, 3.4, 4.2, 22.0])
	for sd: float in [-1.0, 1.0]:
		var at := Vector3(sd * 2.3, H - 0.03, -4.98)
		c.spots.append([at, Vector3(sd * 2.2, 0.6, FZ), LAMP_LIGHT, 0.9, 3.4, 30.0])
	# The night through the window: a faint cold light from high over the terrace.
	c.spots.append([Vector3(-8.0, 6.0, -2.6), Vector3(-1.5, 0.0, -2.6), Color(0.5, 0.6, 0.85), 0.25, 14.0, 40.0])
	# Stand-in lamps (until a bake; always for the seats and the soft parts): over each row, and the back downlights.
	c.kit._light.add_lamp(Vector3(0.0, 2.5, -0.4), LAMP_LIGHT * 0.45, -1.0)
	c.kit._light.add_lamp(Vector3(0.0, 2.5, 1.3), LAMP_LIGHT * 0.45, -1.0)
	c.kit._light.add_lamp(Vector3(0.0, 2.3, 2.4), LAMP_LIGHT * 0.5, -1.0)


# --- The hearth -------------------------------------------------------------------------------------------------------

## The chimney breast in long iron-spot bricks from the floor to the ceiling, the firebox's opening low in it over a
## floating hearth: a slab of slate that runs past the breast either side, cantilevered, logs stacked under its ends.
## In the firebox: firebrick, a steel grate, three logs, embers glowing under them, slow flames. Over the opening a
## steel lintel; over that the sunburst clock.
static func _hearth(c: Object, h: Hall) -> void:
	var face_x := HW - BREAST_D
	var zc := (BREAST_Z0 + BREAST_Z1) * 0.5
	var bw := BREAST_Z1 - BREAST_Z0
	c.s.surface(c.tinted("stone"))
	c.s.colour = _lin(BRICK)
	# The face round the opening (along -z from the breast's back end, so along x up is -x), and its two returns.
	var open := Rect2(BREAST_Z1 - FIRE_Z1, FIRE_Y0, FIRE_Z1 - FIRE_Z0, FIRE_Y1 - FIRE_Y0)
	Shapes.wall(c.s, Vector3(face_x, 0, BREAST_Z1), Vector3(0, 0, -1), Vector3.LEFT, bw, H, [open])
	for e: float in [-1.0, 1.0]:
		var z := zc + e * bw * 0.5
		c.s.face([Vector3(face_x, 0, z), Vector3(HW, 0, z), Vector3(HW, H, z), Vector3(face_x, H, z)], Vector3(0, 0, e))
	_solid(c, Vector3(HW - BREAST_D * 0.5, H * 0.5, zc), Vector3(BREAST_D, H, bw))
	# The firebox: firebrick sides, back and floor, sooted towards the top.
	var depth := 0.4
	c.s.colour = _lin(Color(0.3, 0.2, 0.16))
	var fz0 := FIRE_Z0
	var fz1 := FIRE_Z1
	c.s.face([Vector3(face_x + depth, FIRE_Y0, fz0), Vector3(face_x + depth, FIRE_Y0, fz1),
			Vector3(face_x + depth, FIRE_Y1, fz1), Vector3(face_x + depth, FIRE_Y1, fz0)], Vector3.LEFT)
	for z: float in [fz0, fz1]:
		c.s.face([Vector3(face_x, FIRE_Y0, z), Vector3(face_x + depth, FIRE_Y0, z), Vector3(face_x + depth, FIRE_Y1, z),
				Vector3(face_x, FIRE_Y1, z)], Vector3(0, 0, 1.0 if z == fz0 else -1.0))
	c.s.colour = _lin(Color(0.08, 0.06, 0.05))
	c.s.face([Vector3(face_x, FIRE_Y1, fz0), Vector3(face_x + depth, FIRE_Y1, fz0), Vector3(face_x + depth, FIRE_Y1, fz1),
			Vector3(face_x, FIRE_Y1, fz1)], Vector3.DOWN)
	c.s.colour = _lin(Color(0.12, 0.09, 0.07))
	c.s.face([Vector3(face_x, FIRE_Y0, fz0), Vector3(face_x + depth, FIRE_Y0, fz0), Vector3(face_x + depth, FIRE_Y0, fz1),
			Vector3(face_x, FIRE_Y0, fz1)], Vector3.UP)
	# The hearth's slab: from the wall out past the breast's face, along past the breast either side.
	c.s.surface(c.tinted("roof"))
	c.s.colour = _lin(SLATE)
	var sx0 := face_x - HEARTH_OUT
	c.s.box(Vector3((sx0 + HW) * 0.5, HEARTH_TOP - HEARTH_T * 0.5, (HEARTH_Z0 + HEARTH_Z1) * 0.5),
			Vector3(HW - sx0, HEARTH_T, HEARTH_Z1 - HEARTH_Z0), Basis(), [RoomMesh.RIGHT])
	_solid(c, Vector3((sx0 + HW) * 0.5, HEARTH_TOP * 0.5, (HEARTH_Z0 + HEARTH_Z1) * 0.5),
			Vector3(HW - sx0, HEARTH_TOP, HEARTH_Z1 - HEARTH_Z0))
	# The steel lintel over the opening.
	c.s.surface(c.tinted("iron"))
	c.s.colour = _lin(Color(0.07, 0.065, 0.06))
	c.s.box(Vector3(face_x - 0.004, FIRE_Y1 + 0.04, (fz0 + fz1) * 0.5), Vector3(0.012, 0.08, fz1 - fz0 + 0.16))
	# The grate: two bars across on four short legs.
	var gx := face_x + 0.2
	for z: float in [fz0 + 0.12, fz1 - 0.12]:
		c.s.box(Vector3(gx, FIRE_Y0 + 0.05, z), Vector3(0.24, 0.02, 0.02))
		for x: float in [gx - 0.1, gx + 0.1]:
			c.s.box(Vector3(x, FIRE_Y0 + 0.025, z), Vector3(0.018, 0.05, 0.018), Basis(), [RoomMesh.DOWN])
	_logs(c, h, face_x)
	_log_store(c)
	_clock(c, h, face_x, zc)
	_hearth_tools(c, face_x)


## The fire: three logs on the grate (charred, their ends lighter), the embers' bed glowing under them, slow flames
## licking up between them, the fire's glow on the hearth and the floor before it; its light in the bake and a
## stand-in lamp.
static func _logs(c: Object, h: Hall, face_x: float) -> void:
	var gx := face_x + 0.2
	var zc := (FIRE_Z0 + FIRE_Z1) * 0.5
	var base := FIRE_Y0 + 0.07
	c.s.surface(c.tinted("wood"))
	var logs: Array = [[Vector3(gx - 0.05, base + 0.04, zc), 0.055, 0.62, 0.0],
			[Vector3(gx + 0.07, base + 0.05, zc + 0.03), 0.05, 0.58, 0.08],
			[Vector3(gx + 0.01, base + 0.13, zc - 0.04), 0.045, 0.5, -0.25]]
	for lg: Array in logs:
		var centre: Vector3 = lg[0]
		var basis := Basis(Vector3.UP, float(lg[3])) * Basis(Vector3.RIGHT, PI * 0.5)
		c.s.colour = _lin(Color(0.09, 0.07, 0.06))
		Shapes.cylinder(c.s, centre - basis * Vector3(0, float(lg[2]) * 0.5, 0), float(lg[1]), float(lg[2]), 9, basis,
				false)
		c.s.colour = _lin(Color(0.45, 0.32, 0.2))
		for e: float in [-0.5, 0.5]:
			var cap: Array = []
			for k in 9:
				var a := TAU * k / 9.0
				cap.append(centre + basis * Vector3(cos(a) * float(lg[1]), float(lg[2]) * e, sin(a) * float(lg[1])))
			c.s.face(cap, (basis * Vector3(0, e, 0)).normalized())
	# The embers' bed under the logs, and their glow on the logs' undersides.
	var g := h.glow
	var ember := _lin(Color(1.0, 0.36, 0.08))
	ember.a = 1.0
	var e0 := Vector3(face_x + 0.06, FIRE_Y0 + 0.012, FIRE_Z0 + 0.06)
	var e1 := Vector3(face_x + 0.36, FIRE_Y0 + 0.012, FIRE_Z1 - 0.06)
	var dim := ember
	dim.a = 0.25
	g.quad(Vector3(e0.x, e0.y, e0.z), Vector3(e1.x, e0.y, e0.z), Vector3(e1.x, e0.y, e1.z), Vector3(e0.x, e0.y, e1.z),
			Vector3.UP, [dim, dim, dim, dim], 2.0)
	_radial(g, Vector3(gx, FIRE_Y0 + 0.014, zc), Vector3(0.16, 0, 0), Vector3(0, 0, 0.3), Vector3.UP,
			_lin(Color(1.0, 0.45, 0.1)), 1.4)
	# The flames: crossed quads standing among the logs, each its own size and seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1962
	var tongues := 11
	for k in tongues:
		var z := lerpf(FIRE_Z0 + 0.14, FIRE_Z1 - 0.14, (k + 0.5) / tongues) + rng.randf_range(-0.03, 0.03)
		var x := gx + rng.randf_range(-0.07, 0.07)
		var mid := 1.0 - absf((k - (tongues - 1) * 0.5) / ((tongues - 1) * 0.5))
		var hgt := rng.randf_range(0.24, 0.42) * (0.65 + 0.35 * mid)
		var wdt := rng.randf_range(0.16, 0.24)
		var foot := Vector3(x, base + 0.02, z)
		var tint := Color(1.0, 1.0, 1.0, rng.randf())
		for turn: float in [0.6, -0.6]:
			var across := Vector3(sin(turn), 0, cos(turn)) * wdt * 0.5
			g.quad(foot - across, foot + across, foot + across + Vector3(0, hgt, 0), foot - across + Vector3(0, hgt, 0),
					across.cross(Vector3.UP).normalized(), tint, 1.0)
	# The flames' glow on the firebox's back and sides (the firebrick lit and wavering with them).
	_radial(g, Vector3(face_x + 0.395, FIRE_Y0 + 0.2, zc), Vector3(0, 0.32, 0), Vector3(0, 0, 0.45), Vector3.LEFT,
			_lin(FIRE_LIGHT) * 0.5, 1.0)
	# The fire's glow on the hearth before the opening, the floor below it, the brick round the opening.
	var fx := face_x - 0.02
	_radial(g, Vector3(face_x - HEARTH_OUT * 0.5, HEARTH_TOP + 0.002, zc), Vector3(HEARTH_OUT * 0.5, 0, 0),
			Vector3(0, 0, 0.9), Vector3.UP, _lin(FIRE_LIGHT) * 0.35, 1.0)
	_radial(g, Vector3(face_x - HEARTH_OUT - 0.6, 0.004, zc), Vector3(0.6, 0, 0), Vector3(0, 0, 1.1), Vector3.UP,
			_lin(FIRE_LIGHT) * 0.12, 1.0)
	_radial(g, Vector3(fx, (FIRE_Y0 + FIRE_Y1) * 0.5 + 0.12, zc), Vector3(0, 0.55, 0), Vector3(0, 0, 0.75), Vector3.LEFT,
			_lin(FIRE_LIGHT) * 0.1, 1.0, true)
	h.fire_at = Vector3(gx, base + 0.1, zc)
	# Its light: in the bake (warm, low, into the room), and a stand-in lamp for the chairs and the soft parts.
	c.glow_lights.append([Vector3(face_x - 0.25, FIRE_Y0 + 0.25, zc), FIRE_LIGHT, 1.6, 4.5])
	c.glow_lights.append([Vector3(face_x + 0.15, FIRE_Y0 + 0.2, zc), FIRE_LIGHT, 0.8, 1.2])
	c.kit._light.add_lamp(Vector3(face_x - 0.4, FIRE_Y0 + 0.3, zc), FIRE_LIGHT * 1.6, -1.0)


## A soft glow over a patch (centre, half axes u and v, facing n): strongest in its middle, nothing at its edge; a grid
## of the added mesh's kind 2 (the fire's glow). hole: a patch round the firebox's opening, dark in the middle.
static func _radial(g: Verts, centre: Vector3, u: Vector3, v: Vector3, n: Vector3, colour: Color, strength: float,
		hole := false) -> void:
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	var steps := 8
	for j in steps + 1:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for i in steps + 1:
			var a := (float(i) / steps) * 2.0 - 1.0
			var b := (float(j) / steps) * 2.0 - 1.0
			var r := sqrt(a * a + b * b)
			var k := pow(clampf(1.0 - r, 0.0, 1.0), 1.6)
			if hole:
				# Round the opening: brightest just over it, nothing below its lintel's middle.
				k = pow(clampf(1.0 - r, 0.0, 1.0), 1.2) * smoothstep(-0.55, 0.2, a)
			row.append(centre + u * a + v * b)
			nrow.append(n)
			var col := colour
			col.a = k * strength
			crow.append(col)
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	g.grid(rows, norms, cols, 2.0)


## Logs stacked under the hearth's slab where it runs past the breast: end grain out, in a neat pile.
static func _log_store(c: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var face_x := HW - BREAST_D
	var x0 := face_x - HEARTH_OUT + 0.05
	c.s.surface(c.tinted("wood"))
	for span: Vector2 in [Vector2(HEARTH_Z0 + 0.04, BREAST_Z0 - 0.04)]:
		var z := span.x
		var r := 0.055
		var row := 0
		var y := r
		while y + r < HEARTH_TOP - HEARTH_T - 0.005:
			z = span.x + (r if row % 2 == 0 else r * 2.0)
			while z + r < span.y:
				var rr := r * rng.randf_range(0.85, 1.05)
				var basis := Basis(Vector3.FORWARD, PI * 0.5)
				var foot := Vector3(x0, y, z)
				# Bark on the long side, the cut end lighter (facing the room).
				c.s.colour = _lin(Color(0.22, 0.15, 0.1) * rng.randf_range(0.8, 1.15))
				Shapes.cylinder(c.s, foot - Vector3(HW - x0 - 0.04, 0, 0) * 0.0, rr, HW - x0 - 0.02, 8,
						Basis(Vector3.BACK, -PI * 0.5), false)
				c.s.colour = _lin(Color(0.62, 0.48, 0.32) * rng.randf_range(0.85, 1.1))
				var cap: Array = []
				for k in 8:
					var a := TAU * k / 8.0
					cap.append(foot + Vector3(0, cos(a) * rr, sin(a) * rr))
				c.s.face(cap, Vector3.LEFT)
				z += r * 2.05
			y += r * 1.75
			row += 1


## The sunburst clock on the breast: a walnut disc, brass rays round it (long and short in turn, each tapering to a
## point), brass hour marks, and its two hands (the hall's own nodes: they keep the real time).
static func _clock(c: Object, h: Hall, face_x: float, zc: float) -> void:
	var centre := Vector3(face_x - 0.03, CLOCK_Y, zc)
	h.clock_at = centre + Vector3(-0.012, 0, 0)
	var n := Vector3.LEFT
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	var rays := 24
	for k in rays:
		var a := TAU * k / rays
		var dir := Vector3(0, cos(a), -sin(a))
		var side := Vector3(0, -sin(a), -cos(a))
		var r0 := 0.15
		var r1 := CLOCK_R * (1.0 if k % 2 == 0 else 0.7)
		var w := 0.016 if k % 2 == 0 else 0.012
		var p0 := centre + dir * r0
		var p1 := centre + dir * r1
		# A blade: a flat taper with a little depth (front and two sides), standing off the brick.
		c.u.face([p0 - side * w + n * 0.008, p0 + side * w + n * 0.008, p1 + n * 0.004], n)
		c.u.face([p0 - side * w + n * 0.008, p1 + n * 0.004, p1 + Vector3(0.012, 0, 0), p0 - side * w + Vector3(0.012, 0, 0)],
				(-side + n * 0.3).normalized())
		c.u.face([p0 + side * w + n * 0.008, p0 + side * w + Vector3(0.012, 0, 0), p1 + Vector3(0.012, 0, 0), p1 + n * 0.004],
				(side + n * 0.3).normalized())
		# A small ball at each long ray's tip.
		if k % 2 == 0:
			Shapes.lathe(c.u, [Vector2(0.0, -0.012), Vector2(0.011, -0.006), Vector2(0.011, 0.006), Vector2(0.0, 0.012)],
					p1 + n * 0.006, 8, Basis(Vector3.FORWARD, PI * 0.5))
	# The walnut disc in the middle, its brass rim, the hour marks.
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT * 1.1)
	Shapes.lathe(c.s, [Vector2(0.15, 0.0), Vector2(0.15, 0.022), Vector2(0.145, 0.026)], centre + Vector3(0.012, 0, 0),
			28, Basis(Vector3.FORWARD, -PI * 0.5))
	var disc: Array = []
	for k in 28:
		var a := TAU * k / 28.0
		disc.append(centre + Vector3(-0.014, cos(a) * 0.145, sin(a) * 0.145))
	c.s.face(disc, n)
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	for k in 12:
		var a := TAU * k / 12.0
		var dir := Vector3(0, cos(a), -sin(a))
		var long := 0.03 if k % 3 == 0 else 0.018
		c.u.box(centre + dir * (0.125 - long * 0.5) + Vector3(-0.016, 0, 0), Vector3(0.004, long, 0.008),
				Basis(Vector3.RIGHT, -a))
	Shapes.cylinder(c.u, centre + Vector3(-0.03, 0, 0), 0.012, 0.016, 10, Basis(Vector3.FORWARD, -PI * 0.5))


## Fire tools on a stand at the hearth's end: a brass stand, a poker, a brush, tongs (thin dark steel with brass
## handles).
static func _hearth_tools(c: Object, face_x: float) -> void:
	var base := Vector3(face_x - 0.2, HEARTH_TOP, HEARTH_Z1 - 0.16)
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	Shapes.cylinder(c.u, base, 0.08, 0.012, 14)
	Shapes.cylinder(c.u, base, 0.008, 0.74, 8)
	c.u.box(base + Vector3(0, 0.66, 0), Vector3(0.16, 0.01, 0.01))
	c.s.surface(c.tinted("iron"))
	c.s.colour = _lin(Color(0.06, 0.06, 0.06))
	for k in 3:
		var hx := -0.07 + k * 0.07
		var top := base + Vector3(hx, 0.65, 0.0)
		Shapes.beam(c.s, top, base + Vector3(hx * 1.4, 0.03, 0.03), Vector2(0.008, 0.008))
		c.u.box(top + Vector3(0, 0.06, 0), Vector3(0.016, 0.1, 0.016))


# --- The furniture ----------------------------------------------------------------------------------------------------

static func _furniture(c: Object, h: Hall) -> void:
	_credenza(c, h)
	_bar_cart(c)
	_coffee_table(c, h)
	_tripod_lamp(c)
	_sheepskin(c)


## The credenza under the screen: a long, low walnut cabinet floating off the floor on the slats, four doors with
## recessed brass pulls, its top under every seat's view of the picture; on it, film cans at one end, a tall glazed
## bottle and a low walnut bowl at the other.
static func _credenza(c: Object, h: Hall) -> void:
	var x0 := -2.15
	var x1 := 2.15
	var y0 := 0.2
	var y1 := 0.62
	var zb := FZ + SLAT_D
	var zf := zb + 0.44
	var zc := (zb + zf) * 0.5
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT * 1.05)
	c.s.box(Vector3(0, y1 - 0.015, zc), Vector3(x1 - x0, 0.03, zf - zb), Basis(), [RoomMesh.FRONT])
	c.s.box(Vector3(0, y0 + 0.01, zc), Vector3(x1 - x0, 0.02, zf - zb), Basis(), [RoomMesh.FRONT])
	for x: float in [x0 + 0.0125, x1 - 0.0125]:
		c.s.box(Vector3(x, (y0 + y1) * 0.5, zc), Vector3(0.025, y1 - y0, zf - zb), Basis(), [RoomMesh.FRONT])
	c.s.colour = _lin(WALNUT_DARK * 0.5)
	c.s.face([Vector3(x0, y0 + 0.02, zf - 0.02), Vector3(x1, y0 + 0.02, zf - 0.02), Vector3(x1, y1 - 0.03, zf - 0.02),
			Vector3(x0, y1 - 0.03, zf - 0.02)], Vector3.BACK)
	var doors := 4
	var dw := (x1 - x0 - 0.05) / doors
	for k in doors:
		var dx0 := x0 + 0.025 + k * dw + 0.003
		var dx1 := dx0 + dw - 0.006
		c.s.surface(c.tinted("wood") if k % 2 == 0 else _walnut_b(c, h))
		c.s.colour = _lin(WALNUT * (1.08 if k % 2 == 0 else 1.0))
		c.s.box(Vector3((dx0 + dx1) * 0.5, (y0 + y1) * 0.5, zf - 0.01), Vector3(dx1 - dx0, y1 - y0 - 0.056, 0.02), Basis(),
				[RoomMesh.FRONT])
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	for k in doors:
		var px := x0 + 0.025 + (k + (0.9 if k % 2 == 0 else 0.1)) * dw
		c.u.box(Vector3(px, y1 - 0.09, zf + 0.004), Vector3(0.012, 0.11, 0.01))
	_solid(c, Vector3(0, (y0 + y1) * 0.5, zc), Vector3(x1 - x0, y1 - y0, zf - zb))
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	_film_cans(c, rng, Vector3(-1.78, y1, zc), 4)
	_vessel(c, Vector3(1.62, y1, zc - 0.04), 0.075, 0.42, Color(0.1, 0.36, 0.38))
	_vessel(c, Vector3(1.84, y1, zc + 0.06), 0.06, 0.26, Color(0.85, 0.42, 0.14))
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT * 1.2)
	Shapes.lathe(c.s, [Vector2(0.05, 0.0), Vector2(0.13, 0.04), Vector2(0.16, 0.075), Vector2(0.15, 0.075),
			Vector2(0.11, 0.035), Vector2(0.0, 0.03)], Vector3(1.15, y1, zc), 20)


## The bar cart by the right wall between the breast and the back row: a brass frame on two wheels and two legs, two
## walnut trays with brass galleries; on top two crystal decanters (whisky, brandy), a soda siphon, an ice bucket,
## tumblers and a bowl of lemons; on the lower tray bottles lying, a stack of coasters.
static func _bar_cart(c: Object) -> void:
	var at := Vector3(HW - 0.32, 0.0, 0.62)
	var lx := 0.2
	var lz := 0.4
	var trays: Array[float] = [0.24, 0.72]
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := at + Vector3(sx * lx, 0, sz * lz)
			Shapes.cylinder(c.u, p + Vector3(0, 0.06 if sz < 0 else 0.0, 0), 0.01, 0.84 - (0.06 if sz < 0 else 0.0), 8)
	# The handle at the back end, the galleries round each tray.
	for sx: float in [-1.0, 1.0]:
		Shapes.beam(c.u, at + Vector3(sx * lx, 0.84, lz), at + Vector3(sx * lx, 0.84, lz + 0.12), Vector2(0.016, 0.016))
	Shapes.beam(c.u, at + Vector3(-lx, 0.84, lz + 0.12), at + Vector3(lx, 0.84, lz + 0.12), Vector2(0.018, 0.018))
	for y: float in trays:
		for sx: float in [-1.0, 1.0]:
			Shapes.beam(c.u, at + Vector3(sx * lx, y + 0.05, -lz), at + Vector3(sx * lx, y + 0.05, lz), Vector2(0.008, 0.008))
		for sz: float in [-1.0, 1.0]:
			Shapes.beam(c.u, at + Vector3(-lx, y + 0.05, sz * lz), at + Vector3(lx, y + 0.05, sz * lz), Vector2(0.008, 0.008))
	# The wheels at the front end (towards the screen): a brass hub in a black tyre.
	for sx: float in [-1.0, 1.0]:
		var hub := at + Vector3(sx * (lx + 0.025), 0.065, -lz)
		Shapes.cylinder(c.u, hub - Vector3(sx * 0.01, 0, 0), 0.025, 0.02, 10, Basis(Vector3.BACK, PI * 0.5))
		c.s.surface(c.tinted("iron"))
		c.s.colour = _lin(Color(0.04, 0.04, 0.04))
		Shapes.cylinder(c.s, hub - Vector3(sx * 0.012, 0, 0), 0.065, 0.024, 16, Basis(Vector3.BACK, PI * 0.5))
		c.u.surface(_brass(c))
		c.u.colour = _lin(BRASS)
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT * 1.1)
	for y: float in trays:
		c.s.box(at + Vector3(0, y, 0), Vector3(lx * 2.0, 0.02, lz * 2.0))
	_solid(c, at + Vector3(0, 0.45, 0.06), Vector3(lx * 2.0 + 0.06, 0.9, lz * 2.0 + 0.12))
	var top := at + Vector3(0, trays[1] + 0.01, 0)
	# The decanters: square crystal with a ball stopper, the spirit in them.
	c.glass.surface(c.kit.GLASS)
	_decanter(c, top + Vector3(-0.06, 0, -0.22), Color(0.62, 0.32, 0.08), 0.6)
	_decanter(c, top + Vector3(0.07, 0, -0.06), Color(0.45, 0.16, 0.06), 0.45)
	# Tumblers (heavy glass, a little whisky in one).
	for p: Vector3 in [Vector3(-0.1, 0, 0.12), Vector3(-0.02, 0, 0.18), Vector3(0.08, 0, 0.13)]:
		Shapes.lathe(c.glass, [Vector2(0.032, 0.0), Vector2(0.036, 0.085)], top + p, 12)
		var floor_: Array = []
		for k in 12:
			var a := TAU * k / 12.0
			floor_.append(top + p + Vector3(cos(a) * 0.032, 0.012, sin(a) * 0.032))
		c.glass.face(floor_, Vector3.UP)
	c.u.surface(c.soft("china"))
	c.u.colour = _lin(Color(0.65, 0.33, 0.09))
	Shapes.cylinder(c.u, top + Vector3(-0.1, 0.012, 0.12), 0.029, 0.025, 10)
	# The ice bucket (brass, its lid), the siphon (blue glass, a steel head).
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	Shapes.lathe(c.u, [Vector2(0.0, 0.0), Vector2(0.065, 0.0), Vector2(0.075, 0.15), Vector2(0.078, 0.155),
			Vector2(0.05, 0.17), Vector2(0.0, 0.175)], top + Vector3(0.08, 0, 0.3), 16)
	c.u.surface(c.soft("china"))
	c.u.colour = _lin(Color(0.1, 0.22, 0.42))
	Shapes.lathe(c.u, [Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.045, 0.2), Vector2(0.03, 0.23)],
			top + Vector3(-0.1, 0, -0.02), 12)
	c.u.surface(c.soft("china"))
	c.u.colour = _lin(Color(0.55, 0.56, 0.58))
	Shapes.lathe(c.u, [Vector2(0.03, 0.23), Vector2(0.032, 0.27), Vector2(0.015, 0.29)], top + Vector3(-0.1, 0, -0.02),
			10)
	c.u.box(top + Vector3(-0.1, 0.285, -0.055), Vector3(0.012, 0.012, 0.07))
	# A bowl of lemons on the lower tray, bottles lying on it.
	var low := at + Vector3(0, trays[0] + 0.01, 0)
	c.u.surface(c.soft("china"))
	c.u.colour = _lin(Color(0.86, 0.82, 0.74))
	Shapes.lathe(c.u, [Vector2(0.03, 0.0), Vector2(0.09, 0.03), Vector2(0.11, 0.06)], low + Vector3(0, 0, 0.24), 16)
	c.u.surface(c.soft("china"))
	c.u.colour = _lin(Color(0.95, 0.78, 0.15))
	for p: Vector3 in [Vector3(0.03, 0.06, 0.24), Vector3(-0.04, 0.06, 0.22), Vector3(0.0, 0.07, 0.29)]:
		c.u.rounded_box(low + p, Vector3(0.07, 0.05, 0.05), 0.024, Transform3D(Basis(Vector3.UP, p.x * 20.0), Vector3.ZERO), 2)
	for k in 3:
		var bz := -0.3 + k * 0.1
		var col: Color = [Color(0.12, 0.2, 0.08), Color(0.35, 0.12, 0.05), Color(0.1, 0.1, 0.1)][k]
		c.u.surface(c.soft("china"))
		c.u.colour = _lin(col)
		var basis := Basis(Vector3.BACK, PI * 0.5)
		var foot := low + Vector3(-0.15, 0.04, bz)
		Shapes.lathe(c.u, [Vector2(0.0, 0.0), Vector2(0.038, 0.0), Vector2(0.038, 0.2), Vector2(0.014, 0.26),
				Vector2(0.014, 0.3), Vector2(0.0, 0.3)], foot, 10, Basis(Vector3.BACK, -PI * 0.5))


## A decanter: a square crystal body with chamfered shoulders, a neck and a ball stopper, the spirit inside to `fill`.
static func _decanter(c: Object, at: Vector3, spirit: Color, fill: float) -> void:
	var hw := 0.048
	var hgt := 0.17
	c.glass.box(at + Vector3(0, hgt * 0.5, 0), Vector3(hw * 2.0, hgt, hw * 2.0))
	Shapes.lathe(c.glass, [Vector2(hw, hgt), Vector2(0.018, hgt + 0.035), Vector2(0.016, hgt + 0.06)], at, 4,
			Basis(Vector3.UP, PI * 0.25))
	Shapes.lathe(c.glass, [Vector2(0.0, hgt + 0.06), Vector2(0.024, hgt + 0.075), Vector2(0.024, hgt + 0.1),
			Vector2(0.0, hgt + 0.115)], at, 10)
	c.u.surface(c.soft("china"))
	c.u.colour = _lin(spirit)
	var lh := hgt * fill
	c.u.box(at + Vector3(0, 0.008 + lh * 0.5, 0), Vector3(hw * 2.0 - 0.008, lh, hw * 2.0 - 0.008))


## The coffee table before the front row, to the right (clear of every seat's view): a walnut surfboard top on
## splayed tapered legs; on it a walnut cigar box, a teak bowl, a heavy glass ashtray-free tray with two tumblers,
## a book.
static func _coffee_table(c: Object, h: Hall) -> void:
	var at := Vector3(1.0, 0.0, -1.5)
	var top := 0.38
	var hl := 0.55
	var hw := 0.26
	c.s.surface(_walnut_b(c, h))
	c.s.colour = _lin(WALNUT * 1.12)
	# The top: a rounded oblong (a polygon of its outline), its edge a strip.
	var outline := PackedVector3Array()
	var steps := 28
	for k in steps:
		var a := TAU * k / steps
		var sx := signf(cos(a)) * pow(absf(cos(a)), 0.6)
		var sz := signf(sin(a)) * pow(absf(sin(a)), 0.6)
		outline.append(at + Vector3(sx * hl, top, sz * hw))
	c.s.polygon(outline, Vector3.UP)
	var a_ := PackedVector3Array()
	var b_ := PackedVector3Array()
	var ns := PackedVector3Array()
	for k in steps + 1:
		var p := outline[k % steps]
		a_.append(p)
		b_.append(p - Vector3(0, 0.035, 0))
		ns.append(Vector3(p.x - at.x, 0, (p.z - at.z) * 2.0).normalized())
	c.s.strip(a_, b_, ns)
	c.s.colour = _lin(WALNUT * 0.9)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p0 := at + Vector3(sx * (hl - 0.18), top - 0.035, sz * (hw - 0.1))
			var p1 := at + Vector3(sx * (hl - 0.1), 0.0, sz * (hw - 0.04))
			Shapes.beam(c.s, p0, p1, Vector2(0.03, 0.03))
	_solid(c, at + Vector3(0, top * 0.5, 0), Vector3(hl * 2.0, top, hw * 2.0))
	var t := at + Vector3(0, top, 0)
	# The cigar box (walnut, a brass clasp), the bowl, the book.
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT_DARK * 1.4)
	c.s.box(t + Vector3(-0.32, 0.03, -0.04), Vector3(0.24, 0.06, 0.15), Basis(Vector3.UP, 0.12), [RoomMesh.DOWN])
	c.s.colour = _lin(WALNUT * 1.3)
	Shapes.lathe(c.s, [Vector2(0.04, 0.0), Vector2(0.1, 0.03), Vector2(0.12, 0.06), Vector2(0.11, 0.06),
			Vector2(0.08, 0.03), Vector2(0.0, 0.025)], t + Vector3(0.28, 0, 0.03), 18)
	c.s.surface(c.tinted("cloth"))
	c.s.colour = _lin(Color(0.12, 0.22, 0.3))
	c.s.box(t + Vector3(0.0, 0.012, 0.06), Vector3(0.22, 0.024, 0.28), Basis(Vector3.UP, -0.3), [RoomMesh.DOWN])
	c.s.colour = _lin(Color(0.9, 0.86, 0.76))
	c.s.box(t + Vector3(0.0, 0.0125, 0.06), Vector3(0.212, 0.02, 0.272) + Vector3(0.012, 0, 0), Basis(Vector3.UP, -0.3),
			[RoomMesh.DOWN, RoomMesh.UP])
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	c.u.box(t + Vector3(-0.32, 0.045, -0.04) + Basis(Vector3.UP, 0.12) * Vector3(0, 0, 0.078), Vector3(0.03, 0.02, 0.006),
			Basis(Vector3.UP, 0.12))


## A tripod floor lamp in the corner by the window: three splayed walnut legs, a brass stem, a linen drum shade that
## glows (the house lamps), its light on the corner in the bake.
static func _tripod_lamp(c: Object) -> void:
	var at := Vector3(-2.62, 0.0, -4.55)
	var hub := at + Vector3(0, 0.62, 0)
	c.s.surface(c.tinted("wood"))
	c.s.colour = _lin(WALNUT * 1.05)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		Shapes.beam(c.s, hub, at + Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3), Vector2(0.026, 0.026))
	c.u.surface(_brass(c))
	c.u.colour = _lin(BRASS)
	Shapes.cylinder(c.u, hub - Vector3(0, 0.02, 0), 0.022, 0.05, 10)
	Shapes.cylinder(c.u, hub, 0.009, 0.92, 8)
	var shade_y := hub.y + 0.8
	c.lit.surface(c.shade(LAMP_GLOW))
	Shapes.lathe(c.lit, [Vector2(0.24, 0.0), Vector2(0.21, 0.3)], at + Vector3(0, shade_y, 0), 24)
	Shapes.lathe(c.lit, [Vector2(0.21, 0.3), Vector2(0.24, 0.0)], at + Vector3(0, shade_y, 0), 24)
	c.glow_lights.append([at + Vector3(0, shade_y + 0.12, 0), LAMP_LIGHT, 0.9, 3.0])
	c.kit._light.add_lamp(at + Vector3(0, shade_y + 0.1, 0), LAMP_LIGHT * 1.1, -1.0)
	_solid(c, at + Vector3(0, 0.75, 0), Vector3(0.5, 1.5, 0.5))


## A sheepskin on the carpet before the hearth: an irregular outline (narrower at the neck, the legs' lobes), domed a
## little, its edge a fringe of tufts lying out over the carpet; cream, deep-piled.
static func _sheepskin(c: Object) -> void:
	var centre := Vector3(HW - BREAST_D - HEARTH_OUT - 0.5, 0.0, (BREAST_Z0 + BREAST_Z1) * 0.5 + 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1962
	var rings := 6
	var sides := 32
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	var turn := Basis(Vector3.UP, 0.35)
	for j in rings + 1:
		var t := float(j) / rings
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for i in sides + 1:
			var a := TAU * float(i % sides) / sides
			# The outline: an oval, lobed at the legs, pinched at the neck.
			var r := 1.0 + 0.16 * cos(a * 4.0 + 0.5) + 0.08 * sin(a * 7.0) - 0.12 * pow(maxf(cos(a), 0.0), 6.0)
			var p := Vector3(cos(a) * 0.62 * r * t, 0.0, sin(a) * 0.42 * r * t)
			var y := 0.035 * (1.0 - t * t) + 0.008
			row.append(centre + turn * p + Vector3(0, y, 0))
			nrow.append((turn * Vector3(p.x * 0.06, 1.0, p.z * 0.06)).normalized())
			var k := 1.0 - 0.1 * t
			crow.append(_lin(SHEEPSKIN * k))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	c.u.surface(c.soft("fabric"))
	c.u.grid(rows, norms, cols)
	# The fringe: tufts lying out from the edge, longer in clumps.
	for i in sides * 3:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / (sides * 3)
		var r := 1.0 + 0.16 * cos(a * 4.0 + 0.5) + 0.08 * sin(a * 7.0) - 0.12 * pow(maxf(cos(a), 0.0), 6.0)
		var p := centre + turn * Vector3(cos(a) * 0.62 * r, 0.0, sin(a) * 0.42 * r) + Vector3(0, 0.008, 0)
		var out := (turn * Vector3(cos(a), 0, sin(a) * 1.4)).normalized()
		var len := rng.randf_range(0.03, 0.07) * (1.6 if sin(a * 3.0 + 1.0) > 0.6 else 1.0)
		var side := out.cross(Vector3.UP).normalized() * rng.randf_range(0.012, 0.02)
		c.u.colour = _lin(SHEEPSKIN * rng.randf_range(0.85, 1.0))
		c.u.face([p - side, p + side, p + out * len + Vector3(0, -0.006, 0)], Vector3.UP)
	c.u.colour = Color.WHITE


# --- The garden -------------------------------------------------------------------------------------------------------

## Outside the glass: the eaves running on over the terrace (their undersides catch the pool's rippling light), the
## terrace's big pavers, the pool right outside glowing turquoise with its coping, agaves in concrete bowls, palms
## down the slope, the low wall at the terrace's edge, and far below the city's lights to the horizon. Its light is
## worked out here into the vertex colours (the night's cool light, the room's warm light through the glass, the
## pool's glow); the ripples of the pool's light are the shader's. Also the pool's light on the ceiling inside by the
## window (the glows) and in the bake.
static func _garden(c: Object, h: Hall) -> void:
	var o := h.outside
	_eaves(o)
	_terrace(o)
	_pool(o)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1962
	for p: Vector3 in [Vector3(-3.95, TERRACE_Y, -6.0), Vector3(-8.75, TERRACE_Y, -0.4), Vector3(-8.7, TERRACE_Y, -8.9)]:
		_planter(o, rng, p)
	_low_wall(o)
	for pl: Array in [[Vector3(-24.0, -5.5, -17.0), 10.0, 3], [Vector3(-30.0, -7.0, -6.0), 12.0, 5],
			[Vector3(-27.0, -6.5, 2.0), 9.5, 8], [Vector3(-36.0, -8.5, -12.0), 13.0, 11],
			[Vector3(-21.0, -5.0, -9.0), 8.5, 13]]:
		_palm(o, rng, pl[0], float(pl[1]), int(pl[2]))
	_city(h.glow)
	h.city_tex = city_picture()
	_pool_light_inside(c, h)


## The light outside at a point facing n: the night's cool light from above, the room's warm light through the
## glass (near the window, falling off), and how much of the pool's glow reaches it (the alpha: its ripples).
static func _out_light(p: Vector3, n: Vector3, base: Color) -> Color:
	var sky := Color(0.05, 0.065, 0.1) * (0.55 + 0.45 * clampf(n.y, 0.0, 1.0))
	var d_room := maxf(-HW - p.x, 0.0)
	var in_window := smoothstep(WIN_Z0 - 1.5, WIN_Z0 + 0.3, p.z) * (1.0 - smoothstep(WIN_Z1 - 0.3, WIN_Z1 + 1.5, p.z))
	var room := Color(1.0, 0.62, 0.35) * 0.12 * in_window * clampf(-n.x * 0.6 + 0.5, 0.0, 1.0) / (1.0 + d_room * d_room
			* 0.6)
	var pool := _pool_reach(p, n)
	var c := Color(base.r * (sky.r + room.r), base.g * (sky.g + room.g), base.b * (sky.b + room.b))
	# The pool's glow as light (steady) plus the ripples (the shader's, by the alpha).
	var pc := _lin(POOL_COLOUR)
	c += Color(base.r * pc.r, base.g * pc.g, base.b * pc.b) * pool * 0.5
	c.a = clampf(pool * 0.3, 0.0, 1.0)
	return c


## How much of the pool's light reaches a point facing n: the water's glow is a broad source low over the pool;
## faces turned to it and near it take most.
static func _pool_reach(p: Vector3, n: Vector3) -> float:
	var q := Vector3(clampf(p.x, POOL_X0, POOL_X1), WATER_Y, clampf(p.z, POOL_Z0, POOL_Z1))
	var d := q - p
	var l := d.length()
	var facing := 1.0 if l < 0.01 else clampf(n.dot(d / l) * 0.8 + 0.2, 0.0, 1.0)
	return facing / (1.0 + l * l * 0.35)


static func _oquad(o: Verts, a: Vector3, b: Vector3, cc: Vector3, d: Vector3, n: Vector3, base: Color) -> void:
	o.quad(a, b, cc, d, n, [_out_light(a, n, base), _out_light(b, n, base), _out_light(cc, n, base),
			_out_light(d, n, base)])


static func _obox(o: Verts, centre: Vector3, size: Vector3, base: Color, skip: Array = []) -> void:
	var hs := size * 0.5
	for n: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK]:
		if n in skip:
			continue
		var a1 := Vector3(n.y, n.z, n.x).abs()
		var a2 := n.cross(a1).abs()
		var pts: Array = []
		for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			pts.append(centre + n * hs + a1 * hs * k.x + a2 * hs * k.y)
		_oquad(o, pts[0], pts[1], pts[2], pts[3], n, base)


## The eaves: the ceiling's plane running on out over the terrace (its boards between the beams' ends, which run
## through the glass as they did in such houses), a deep walnut fascia at their edge.
static func _eaves(o: Verts) -> void:
	var plaster := _lin(BOARDS * 0.9)
	var z0 := -9.5
	var z1 := 3.5
	var n := 16
	for k in n:
		var za := lerpf(z0, z1, float(k) / n)
		var zb := lerpf(z0, z1, float(k + 1) / n)
		for s in 3:
			var xa := lerpf(-HW - 0.12, EAVE_X, float(s) / 3.0)
			var xb := lerpf(-HW - 0.12, EAVE_X, float(s + 1) / 3.0)
			_oquad(o, Vector3(xa, H, za), Vector3(xb, H, za), Vector3(xb, H, zb), Vector3(xa, H, zb), Vector3.DOWN, plaster)
	var wood := _lin(WALNUT * 0.8)
	var bz := (BZ - SOFFIT_Z) / BAYS_Z
	for j in range(-4, BAYS_Z + 1):
		var z := SOFFIT_Z + j * bz
		if z < z0 or z > z1:
			continue
		_obox(o, Vector3((-HW - 0.12 + EAVE_X) * 0.5, H - BEAM_D * 0.5, z), Vector3(EAVE_X + HW + 0.12, BEAM_D, BEAM_W), wood,
				[Vector3.UP])
	_obox(o, Vector3(EAVE_X - 0.04, H - 0.06, (z0 + z1) * 0.5), Vector3(0.08, 0.36, z1 - z0), wood, [Vector3.RIGHT])
	# A slim bronze column at the eaves' corner, out front.
	_obox(o, Vector3(EAVE_X + 0.1, H * 0.5, z0 + 0.15), Vector3(0.08, H, 0.08), _lin(BRONZE))


## The terrace: big square pavers of pale concrete, each its own shade, on a dark bed (the joints), from the glass to
## the low wall, round the pool's coping.
static func _terrace(o: Verts) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	var bed := _lin(Color(0.12, 0.12, 0.11))
	var by := TERRACE_Y - 0.01
	var cx0 := POOL_X0 - COPING
	var cx1 := POOL_X1 + COPING
	var cz0 := POOL_Z0 - COPING
	var cz1 := POOL_Z1 + COPING
	for r: Rect2 in [Rect2(EDGE_X, -12.0, -HW - 0.05 - EDGE_X, cz0 + 12.0), Rect2(EDGE_X, cz1, -HW - 0.05 - EDGE_X, 4.5 - cz1),
			Rect2(EDGE_X, cz0, cx0 - EDGE_X, cz1 - cz0), Rect2(cx1, cz0, -HW - 0.05 - cx1, cz1 - cz0)]:
		_oquad(o, Vector3(r.position.x, by, r.position.y), Vector3(r.end.x, by, r.position.y),
				Vector3(r.end.x, by, r.end.y), Vector3(r.position.x, by, r.end.y), Vector3.UP, bed)
	var size := 1.0
	var joint := 0.025
	var x := -HW - 0.05
	while x > EDGE_X + 0.01:
		var z := -12.0
		var xb := maxf(x - size, EDGE_X)
		while z < 4.5 - 0.01:
			var zb := minf(z + size, 4.5)
			var cx := (x + xb) * 0.5
			var cz := (z + zb) * 0.5
			var in_pool := cx < POOL_X1 + COPING and cx > POOL_X0 - COPING and cz > POOL_Z0 - COPING and cz < POOL_Z1 + COPING
			if not in_pool:
				var k := rng.randf_range(0.82, 1.08)
				var base := _lin(Color(0.66, 0.63, 0.58) * k)
				var y := TERRACE_Y
				_oquad(o, Vector3(x - joint * 0.5, y, z + joint * 0.5), Vector3(xb + joint * 0.5, y, z + joint * 0.5),
						Vector3(xb + joint * 0.5, y, zb - joint * 0.5), Vector3(x - joint * 0.5, y, zb - joint * 0.5),
						Vector3.UP, base)
			z = zb
		x = xb


## The pool: its water a hair under the coping, glowing turquoise from two lamps in its far wall (the water's colour
## per vertex, brighter by them), its walls under the water glowing too; the coping round it in pale stone, a step's
## lip over the water.
static func _pool(o: Verts) -> void:
	var nx := 6
	var nz := 14
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for j in nz + 1:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for i in nx + 1:
			var p := Vector3(lerpf(POOL_X1, POOL_X0, float(i) / nx), WATER_Y, lerpf(POOL_Z0, POOL_Z1, float(j) / nz))
			row.append(p)
			nrow.append(Vector3.UP)
			crow.append(_water_colour(p))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	o.grid(rows, norms, cols, 1.0)
	# The walls under the water's edge, seen at a slant (their glow, deeper).
	var deep := WATER_Y - 0.25
	for wall: Array in [[Vector3(POOL_X1, 0, POOL_Z0), Vector3(POOL_X1, 0, POOL_Z1), Vector3.LEFT],
			[Vector3(POOL_X0, 0, POOL_Z1), Vector3(POOL_X0, 0, POOL_Z0), Vector3.RIGHT],
			[Vector3(POOL_X0, 0, POOL_Z0), Vector3(POOL_X1, 0, POOL_Z0), Vector3.BACK],
			[Vector3(POOL_X1, 0, POOL_Z1), Vector3(POOL_X0, 0, POOL_Z1), Vector3.FORWARD]]:
		var a: Vector3 = wall[0]
		var b: Vector3 = wall[1]
		var n: Vector3 = wall[2]
		var ca := _water_colour(a) * 0.7
		var cb := _water_colour(b) * 0.7
		o.quad(Vector3(a.x, deep, a.z), Vector3(b.x, deep, b.z), Vector3(b.x, TERRACE_Y - 0.04, b.z),
				Vector3(a.x, TERRACE_Y - 0.04, a.z), n, [ca, cb, cb, ca], 1.0)
	# The coping: pale stone slabs round the water, their inner lip over it.
	var stone := Color(0.8, 0.77, 0.7)
	var y := TERRACE_Y + 0.02
	var x0 := POOL_X0 - COPING
	var x1 := POOL_X1 + COPING
	var z0 := POOL_Z0 - COPING
	var z1 := POOL_Z1 + COPING
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var slab := 0.6
	for side: Array in [[Vector3(x0, y, z0), Vector3(x1, y, z0 + COPING)], [Vector3(x0, y, z1 - COPING), Vector3(x1, y, z1)],
			[Vector3(x0, y, z0 + COPING), Vector3(x0 + COPING, y, z1 - COPING)],
			[Vector3(x1 - COPING, y, z0 + COPING), Vector3(x1, y, z1 - COPING)]]:
		var a: Vector3 = side[0]
		var b: Vector3 = side[1]
		var along_x := (b.x - a.x) > (b.z - a.z)
		var length := (b.x - a.x) if along_x else (b.z - a.z)
		var count := maxi(1, roundi(length / slab))
		for k in count:
			var t0 := float(k) / count
			var t1 := float(k + 1) / count
			var p0 := Vector3(lerpf(a.x, b.x, t0) if along_x else a.x, y, a.z if along_x else lerpf(a.z, b.z, t0))
			var p1 := Vector3(lerpf(a.x, b.x, t1) if along_x else b.x, y, b.z if along_x else lerpf(a.z, b.z, t1))
			var shade := _lin(stone * rng.randf_range(0.9, 1.05))
			var g := 0.006
			_obox(o, (p0 + p1) * 0.5 + Vector3(0, -0.03, 0), Vector3(absf(p1.x - p0.x) - g, 0.06, absf(p1.z - p0.z) - g),
					shade, [Vector3.DOWN])


## The water's glow at a point: deep turquoise, brighter round the two lamps in the far wall.
static func _water_colour(p: Vector3) -> Color:
	var k := 0.3
	for l: Vector3 in POOL_LAMPS:
		var d := Vector2(p.x - l.x, p.z - l.z).length()
		k += 0.85 / (1.0 + d * d * 0.5)
	var c := _lin(Color(0.16, 0.66, 0.72)) * minf(k, 1.0)
	c.a = 1.0
	return c


## A planter: a wide concrete bowl on a short foot, soil, and an agave in it: thick pointed leaves curving up and out
## from the middle, blue-grey, a dark spine at each tip.
static func _planter(o: Verts, rng: RandomNumberGenerator, at: Vector3) -> void:
	var concrete := Color(0.6, 0.58, 0.54)
	var sides := 16
	var prof: Array = [Vector2(0.14, 0.0), Vector2(0.16, 0.1), Vector2(0.42, 0.22), Vector2(0.5, 0.42), Vector2(0.47, 0.44),
			Vector2(0.4, 0.3)]
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var slope := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var n0 := (d0 * slope.x + Vector3.UP * slope.y).normalized()
			var pa := at + d0 * p0.x + Vector3.UP * p0.y
			var pb := at + d1 * p0.x + Vector3.UP * p0.y
			var pc := at + d1 * p1.x + Vector3.UP * p1.y
			var pd := at + d0 * p1.x + Vector3.UP * p1.y
			_oquad(o, pa, pb, pc, pd, n0, _lin(concrete))
	# The soil.
	var soil := _lin(Color(0.1, 0.08, 0.06))
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var top := at + Vector3(0, 0.34, 0)
		o.tri(top, top + Vector3(cos(a0), 0, sin(a0)) * 0.42, top + Vector3(cos(a1), 0, sin(a1)) * 0.42, Vector3.UP,
				[_out_light(top, Vector3.UP, soil), _out_light(top, Vector3.UP, soil), _out_light(top, Vector3.UP, soil)])
	# The agave.
	var leaves := 22
	var base := at + Vector3(0, 0.34, 0)
	var green := Color(0.4, 0.52, 0.48)
	for k in leaves:
		var a := TAU * k / leaves * 2.618 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0, sin(a))
		var rise := lerpf(1.25, 0.25, float(k) / leaves) + rng.randf_range(-0.1, 0.1)
		var length := rng.randf_range(0.45, 0.68) * (1.15 - 0.4 * float(k) / leaves)
		var wid := length * 0.13
		var side := out.cross(Vector3.UP).normalized()
		var segs := 4
		var prev_l := base - side * wid * 0.6
		var prev_r := base + side * wid * 0.6
		var prev_c := base
		for s in range(1, segs + 1):
			var t := float(s) / segs
			# Out and up, the tip curving out a little more.
			var dirv := (out * (0.35 + 0.5 * t) + Vector3.UP * rise * (1.0 - 0.45 * t)).normalized()
			var cpt := prev_c + dirv * length / segs
			var wv := wid * (1.0 - t) * (1.0 + 0.4 * sin(t * PI))
			var l := cpt - side * wv
			var r := cpt + side * wv
			var nrm := side.cross(dirv).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			var col := _lin(green * rng.randf_range(0.85, 1.1)) if s < segs else _lin(Color(0.12, 0.1, 0.08))
			for flip: float in [1.0, -1.0]:
				_oquad(o, prev_l, prev_r, r, l, nrm * flip, col)
			prev_l = l
			prev_r = r
			prev_c = cpt


## The low wall at the terrace's edge (rendered block, a cap), and beyond it the ground falling away into the dark.
static func _low_wall(o: Verts) -> void:
	var wall := Color(0.55, 0.52, 0.48)
	var z0 := -12.0
	var z1 := 4.5
	var hgt := 0.42
	_obox(o, Vector3(EDGE_X - 0.15, TERRACE_Y + hgt * 0.5, (z0 + z1) * 0.5), Vector3(0.3, hgt, z1 - z0), wall,
			[Vector3.DOWN])
	_obox(o, Vector3(EDGE_X - 0.15, TERRACE_Y + hgt + 0.025, (z0 + z1) * 0.5), Vector3(0.38, 0.05, z1 - z0 + 0.04),
			wall * 1.1, [Vector3.DOWN])
	# The slope beyond, dark scrub falling away.
	var dark := _lin(Color(0.06, 0.07, 0.05))
	o.quad(Vector3(EDGE_X - 0.3, TERRACE_Y, z0), Vector3(EDGE_X - 0.3, TERRACE_Y, z1), Vector3(EDGE_X - 22.0, -9.0, z1 + 6.0),
			Vector3(EDGE_X - 22.0, -9.0, z0 - 6.0), Vector3(0.38, 1.0, 0.0).normalized(), Color(dark, 0.0))


## A palm down the slope: a tall slender trunk leaning a little, rings on it, a head of drooping fronds; dark against
## the sky, the undersides of the lowest fronds catching a little of the valley's glow.
static func _palm(o: Verts, rng: RandomNumberGenerator, at: Vector3, hgt: float, seed_value: int) -> void:
	rng.seed = seed_value * 31 + 7
	var lean := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
	var trunk := _lin(Color(0.12, 0.1, 0.08))
	var segs := 10
	var prev := at
	var sides := 6
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := at + Vector3(lean.x * t * t, hgt * t, lean.z * t * t)
		var r0 := lerpf(0.22, 0.14, float(i - 1) / segs)
		var r1 := lerpf(0.22, 0.14, t)
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var shade := trunk * (0.85 + 0.3 * float(i % 2))
			shade.a = 0.0
			o.quad(prev + d0 * r0, prev + d1 * r0, p + d1 * r1, p + d0 * r1, (d0 + d1).normalized(), shade)
		prev = p
	var top := prev
	var fronds := 16
	for f in fronds:
		var az := TAU * f / fronds + rng.randf_range(-0.15, 0.15)
		var up := rng.randf_range(-0.2, 0.6)
		var length := rng.randf_range(2.2, 3.0)
		var out := Vector3(sin(az), 0, cos(az))
		var side := out.cross(Vector3.UP).normalized()
		var n := 6
		var last := top
		for j in range(1, n + 1):
			var t := float(j) / n
			var p := top + out * length * t + Vector3.UP * (length * (up * t - 0.6 * t * t))
			var leaflet := length * 0.2 * sin(PI * clampf(t * 0.9 + 0.1, 0.0, 1.0))
			var col := _lin(Color(0.06, 0.08, 0.05) * rng.randf_range(0.8, 1.2))
			col.a = 0.0
			for s: float in [-1.0, 1.0]:
				var tip := last.lerp(p, 0.5) + side * s * leaflet + Vector3.DOWN * leaflet * 0.6
				var nn := (p - last).cross(tip - last).normalized()
				for flip: float in [1.0, -1.0]:
					o.tri(last, p, tip, nn * flip, [col, col, col])
			last = p


## The city's lights far below in the valley: a band round the left of the house 150 m out, from a few degrees under
## the horizon up to it, its picture (city_picture) thick with lights towards the horizon; added over the dark.
static func _city(g: Verts) -> void:
	var r := 150.0
	var eye := EnvChecks_EYE
	var from := -150.0
	var to := -15.0
	var segs := 24
	var lo := eye + tan(deg_to_rad(-6.0)) * r
	var hi := eye + tan(deg_to_rad(0.6)) * r
	var white := Color(1, 1, 1, 1)
	for k in segs:
		var a0 := deg_to_rad(lerpf(from, to, float(k) / segs))
		var a1 := deg_to_rad(lerpf(from, to, float(k + 1) / segs))
		var p0 := Vector3(sin(a0) * r, 0, -cos(a0) * r)
		var p1 := Vector3(sin(a1) * r, 0, -cos(a1) * r)
		var u0 := float(k) / segs
		var u1 := float(k + 1) / segs
		g.quad(p0 + Vector3(0, lo, 0), p1 + Vector3(0, lo, 0), p1 + Vector3(0, hi, 0), p0 + Vector3(0, hi, 0),
				-(p0 + p1).normalized(), white, 3.0, [Vector2(u0 * 3.0, 1), Vector2(u1 * 3.0, 1), Vector2(u1 * 3.0, 0),
				Vector2(u0 * 3.0, 0)])


const EnvChecks_EYE := 1.2

static var _city_picture: ImageTexture


## The city's picture (3 repeats round the band): the valley floor's lights in perspective, sparse and bigger near
## the bottom (nearer), dense and fine towards the horizon at the top where they merge into a warm haze; streets as
## lines of lamps converging; sodium orange, a few white and green-white. Our own, made here once.
static func city_picture() -> ImageTexture:
	if _city_picture != null:
		return _city_picture
	var w := 1024
	var hgt := 128
	var img := Image.create_empty(w, hgt, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1962
	var buf := PackedFloat32Array()
	buf.resize(w * hgt * 3)
	# v: 0 the horizon (top) .. 1 the bottom (near). Depth in the valley: far at the top.
	var colours: Array[Color] = [Color(1.0, 0.62, 0.28), Color(1.0, 0.7, 0.36), Color(1.0, 0.55, 0.22),
			Color(0.85, 0.95, 0.88), Color(0.95, 0.92, 0.82)]
	var add := func(x: float, y: float, col: Color, size: float, k: float) -> void:
		var r := maxf(size, 0.6)
		for yy in range(int(y - r - 1), int(y + r + 2)):
			if yy < 0 or yy >= hgt:
				continue
			for xx in range(int(x - r - 1), int(x + r + 2)):
				var d := Vector2(xx + 0.5 - x, yy + 0.5 - y).length()
				var f := clampf(1.0 - d / (r + 0.5), 0.0, 1.0)
				if f <= 0.0:
					continue
				var i := (yy * w + posmod(xx, w)) * 3
				buf[i] += col.r * f * k
				buf[i + 1] += col.g * f * k
				buf[i + 2] += col.b * f * k
	# Streets: rows of lamps along lines across (avenues, parallel to the horizon) and lines down (boulevards,
	# converging on a far point).
	for s in 22:
		var v := pow(rng.randf(), 1.8)
		var y := 6.0 + v * (hgt - 10.0)
		var spacing := lerpf(3.0, 14.0, v)
		var x := rng.randf() * spacing
		var size := lerpf(0.5, 1.4, v)
		var col: Color = colours[rng.randi() % 3]
		var start := rng.randf() * w
		var length := rng.randf_range(0.2, 0.7) * w
		while x < length:
			add.call(start + x, y + rng.randf_range(-0.3, 0.3), col, size, lerpf(0.5, 0.9, v))
			x += spacing * rng.randf_range(0.8, 1.2)
	for s in 14:
		var x0 := rng.randf() * w
		var vanish := x0 + rng.randf_range(-60.0, 60.0)
		var col: Color = colours[rng.randi() % 5]
		var t := 0.0
		while t < 1.0:
			var v := t
			var y := 4.0 + v * (hgt - 6.0)
			var x := lerpf(vanish, x0, v)
			add.call(x, y, col, lerpf(0.5, 1.3, v), lerpf(0.4, 0.9, v))
			t += lerpf(0.02, 0.07, v)
	# The scatter of the city's lights, denser towards the horizon.
	for k in 5200:
		var v := pow(rng.randf(), 1.7)
		var y := 3.0 + v * (hgt - 5.0)
		if rng.randf() > lerpf(1.0, 0.35, v):
			continue
		var col: Color = colours[rng.randi() % 5] * rng.randf_range(0.5, 1.0)
		add.call(rng.randf() * w, y, col, lerpf(0.45, 1.0, v), lerpf(0.4, 0.8, v))
	# The haze over the city: warm, strongest at the horizon, fading down the band (and up into the sky's foot).
	for y in hgt:
		var v := float(y) / (hgt - 1)
		var haze := 0.055 * exp(-v * 5.0) + 0.012 * (1.0 - v)
		for x in w:
			var i := (y * w + x) * 3
			buf[i] += 1.0 * haze
			buf[i + 1] += 0.62 * haze
			buf[i + 2] += 0.36 * haze
	# The top rows (the band runs a little over the horizon): only the haze, fading out.
	var top_rows := 10
	for y in hgt:
		var keep := smoothstep(0.0, float(top_rows), float(y))
		for x in w:
			var i := (y * w + x) * 3
			var hz := 0.05 * (1.0 - keep) * smoothstep(0.0, float(top_rows), float(y) + 1.0)
			img.set_pixel(x, y, Color(minf(buf[i] * keep + hz, 1.0), minf(buf[i + 1] * keep + hz * 0.62, 1.0),
					minf(buf[i + 2] * keep + hz * 0.36, 1.0)))
	img.generate_mipmaps()
	_city_picture = ImageTexture.create_from_image(img)
	return _city_picture


## The pool's light inside: its rippling web on the ceiling and the beams by the window (the glows, strongest at the
## glass and over the pool's length), and in the bake a cool light from the water up through the glass.
static func _pool_light_inside(c: Object, h: Hall) -> void:
	var g := h.glow
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	var nx := 6
	var nz := 12
	var y := H - 0.004
	for j in nz + 1:
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for i in nx + 1:
			var x := lerpf(-HW + 0.02, -HW + 2.4, float(i) / nx)
			var z := lerpf(WIN_Z0 - 0.2, WIN_Z1 + 0.3, float(j) / nz)
			var depth := (x + HW) / 2.4
			var along := smoothstep(WIN_Z0 - 0.2, WIN_Z0 + 0.8, z) * (1.0 - smoothstep(WIN_Z1 - 0.8, WIN_Z1 + 0.3, z))
			var k := pow(1.0 - depth, 2.4) * along * 0.12
			row.append(Vector3(x, y, z))
			nrow.append(Vector3.DOWN)
			crow.append(Color(1, 1, 1, k))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	g.grid(rows, norms, cols, 0.0)
	# On the beams' undersides by the window too (a hair under them).
	var bz := (BZ - SOFFIT_Z) / BAYS_Z
	for j in BAYS_Z + 1:
		var z := SOFFIT_Z + j * bz
		if z < WIN_Z0 or z > WIN_Z1:
			continue
		var by := H - BEAM_D - 0.003
		var cc := [Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.12)]
		g.quad(Vector3(-HW + 0.02, by, z - BEAM_W * 0.5), Vector3(-HW + 1.6, by, z - BEAM_W * 0.5),
				Vector3(-HW + 1.6, by, z + BEAM_W * 0.5), Vector3(-HW + 0.02, by, z + BEAM_W * 0.5), Vector3.DOWN,
				[cc[0], cc[1], cc[2], cc[3]], 0.0)
	# The bake: the pool's cool light up through the glass onto the ceiling and the window's reveal.
	var pc := POOL_COLOUR
	c.spots.append([Vector3(-6.2, -0.05, -4.5), Vector3(-2.2, H, -2.6), pc, 0.9, 9.0, 28.0])
