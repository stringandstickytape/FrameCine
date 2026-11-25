extends RefCounted

## Orbital ring (app/environments/orbital_ring.env.json; docs/environments/rooms/orbital_ring.md): a sleek
## cantilevered mid-century-futurist glass-and-travertine observation terrace inside a colossal rotating O'Neill
## cylinder space habitat where illuminated valleys, silver rivers, and night city lights curve upside-down overhead
## across the sky. Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, arches, cylinders,
## lathes and custom opaque procedural world meshes; no people, no real trademarks, no text.
##
## Pieces (pieces.gd dispatches here; dressed over `domestic` with `shell: "kit"` and `seats` `lounge`):
##   ring_terrace   sweeping cantilevered curved honed-travertine & brushed-titanium observation terrace (y = 0),
##                  stepped forward rim & glowing crescent infinity reflecting pool (`RingWater` on
##                  `env_world_water.gdshader`), floating slim brushed-titanium cantilevered cinema screen frame
##                  (6.2 x 3.49 m at [0, 2.85, -8.9]), slender sweeping titanium canopy wing-ribs & aft observatory
##                  canopy soffit, indirect architectural cove ribbons (`PieceCove`, live Warm gold / Orbital cyan /
##                  Off), single-layer frameless low glass balustrades (`PieceGlass`), 4 warm cedar & travertine
##                  planters with sculpted bamboo & dwarf cypress trees, 2 tulip lounge side-tables with ceramic
##                  carafes, 6 opal-globe bollard lamps (`PieceLamps`, `bake_lamps: 6`), aft cantilevered observatory
##                  promenade with working modernist wall clock (`PieceClock`) and twin backlit orbital-ring schematic
##                  placards (`PieceWindows`, pure geometry, zero text).
##   ring_cylinder  colossal O'Neill cylinder interior megastructure (`RingCylinder` on `env_ring_world.gdshader`,
##                  1 opaque draw, 0 blend cost, radius 78 m, length 174 m, well inside 184 m sky layers & 200 m far
##                  plane): 3 alternating illuminated land-valley continents (one directly upside-down overhead, two
##                  rising up the port & starboard walls) separated by 3 monumental open space-window gaps letting
##                  the real Milky Way & 3200 stars shine straight through, longitudinal window girders, 8 giant
##                  circumferential structural tension rings, alpine mountain-ring end-caps with open radial spokes,
##                  and luminous central axial solar/docking hubs.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const Domestic := preload("res://scripts/env/systems/domestic.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const RING_SHADER := preload("res://shaders/env_ring_world.gdshader")
const WATER_SHADER := preload("res://shaders/env_world_water.gdshader")

const PIECES: Array[String] = ["ring_terrace", "ring_cylinder"]

## Terrace & cylinder geometry constants (metres, viewer's seat at origin facing -Z).
const TERRACE_HW := 7.6
const TERRACE_BZ := 6.25
const PROW_Z := -5.65
const PROW_CURVE := 1.45

## O'Neill cylinder parameters (every vertex stays <= 176 m from every seat, safely inside 184 m sky & 200 m far).
const CYL_RADIUS := 78.0
const CYL_CENTER_Y := 68.0
const CYL_FRONT_Z := -96.0
const CYL_BACK_Z := 78.0
const CYL_CAP_BULGE := 16.0
const CYL_HUB_R := 17.0
const CYL_CAP_INNER_R := 50.5

## Palette (sRGB; meshes take linear via _lin()).
const TRAVERTINE := Color(0.84, 0.80, 0.72)
const TRAVERTINE_TRIM := Color(0.76, 0.71, 0.62)
const TRAVERTINE_DARK := Color(0.58, 0.54, 0.47)
const TITANIUM := Color(0.84, 0.87, 0.91)
const TITANIUM_SATIN := Color(0.60, 0.64, 0.70)
const BRONZE_GOLD := Color(0.86, 0.69, 0.36)
const CEDAR := Color(0.56, 0.34, 0.19)
const CEDAR_DARK := Color(0.32, 0.19, 0.11)
const SLATE_DARK := Color(0.095, 0.11, 0.14)
const SLATE_MID := Color(0.18, 0.205, 0.25)
const RUG_FIELD := Color(0.19, 0.215, 0.26)
const RUG_BORDER := Color(0.82, 0.78, 0.70)
const RUG_LINE := Color(0.72, 0.54, 0.26)
const SOIL_DARK := Color(0.14, 0.11, 0.085)
const BAMBOO_CULM := Color(0.46, 0.55, 0.27)
const CYPRESS_BARK := Color(0.30, 0.21, 0.14)
const LEAF_BRIGHT := Color(0.24, 0.45, 0.22)
const LEAF_DEEP := Color(0.13, 0.28, 0.14)
const LAMP_GLOW := Color(1.0, 0.86, 0.62)
const CERAMIC_IVORY := Color(0.92, 0.89, 0.82)
const CYAN_ACCENT := Color(0.38, 0.86, 0.98)
const AMBER_ACCENT := Color(1.0, 0.74, 0.34)


## Custom hall owning the O'Neill cylinder world mesh (`RingCylinder`) and infinity pool (`RingWater`).
class Hall:
	var kit: Node
	var cyl := Verts.new()
	var water := Verts.new()
	var cyl_m: ShaderMaterial
	var water_m: ShaderMaterial
	var clock_t := 0.0
	var water_t := 0.0
	## Smoothly eased weights for habitat_time moods: (night, golden, twilight).
	var mood_weights := Vector3(1.0, 0.0, 0.0)
	var time_mood := 0.0
	var _inited := false

	func finish(k: Node) -> void:
		var noise := SkySys.noise_texture()
		var caustics := Procedural.caustic_map()
		if cyl.count() > 0:
			cyl_m = ShaderMaterial.new()
			cyl_m.shader = RING_SHADER
			cyl_m.set_shader_parameter("noise_map", noise)
			cyl_m.set_shader_parameter("cylinder_axis", Vector3(0.0, CYL_CENTER_Y, 0.0))
			cyl_m.set_shader_parameter("spill_strength", 0.32)
			var mi: MeshInstance3D = k._add_mesh("RingCylinder", cyl.commit(cyl_m))
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mi.extra_cull_margin = 256.0
		if water.count() > 0:
			water_m = ShaderMaterial.new()
			water_m.shader = WATER_SHADER
			water_m.set_shader_parameter("caustic_map", caustics)
			water_m.set_shader_parameter("house_reference", float(k.room.get("ambient_level")))
			water_m.set_shader_parameter("ripple_scale", 0.68)
			water_m.set_shader_parameter("spill_strength", 0.78)
			water_m.set_shader_parameter("ambient_floor", 0.26)
			var wm: MeshInstance3D = k._add_mesh("RingWater", water.commit(water_m))
			wm.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# Fine-tune low frameless balustrade glass to crisp ultra-clear architectural low-iron glass.
		for n: Node in k.owned():
			if n is MeshInstance3D and str(n.name) == "PieceGlass" and (n as MeshInstance3D).material_override is ShaderMaterial:
				var gm := (n as MeshInstance3D).material_override as ShaderMaterial
				gm.set_shader_parameter("alpha", 0.045)
				gm.set_shader_parameter("rim", 0.16)
		tick(0.0)

	func _target_mood() -> Array:
		var mode := "night"
		if kit != null and kit.host != null and kit.host.has_method("setting"):
			var v: Variant = kit.host.setting("habitat_time")
			if v is String and str(v) != "":
				mode = str(v)
		match mode:
			"golden":
				return [1.0, Vector3(0.0, 1.0, 0.0)]
			"twilight":
				return [2.0, Vector3(0.0, 0.0, 1.0)]
		return [0.0, Vector3(1.0, 0.0, 0.0)]

	func tick(delta: float) -> void:
		var motion := 1.0
		if kit != null and kit.host != null and kit.host.has_method("setting"):
			motion = clampf(float(kit.host.setting("motion")), 0.0, 1.0)
		var wm_param := float(kit.params.get("water_motion", 1.0)) if kit != null else 1.0
		clock_t += delta * motion
		water_t += delta * wm_param
		var target := _target_mood()
		time_mood = float(target[0])
		var tw: Vector3 = target[1]
		if not _inited or delta <= 0.0:
			mood_weights = tw
			_inited = true
		else:
			var k := 1.0 - exp(-delta / 0.85)
			mood_weights = mood_weights.lerp(tw, k)
		var house := float(kit._group_level("house")) if kit != null else 1.0
		var film_dim := lerpf(0.68, 1.0, clampf(house, 0.0, 1.0))
		if cyl_m != null:
			cyl_m.set_shader_parameter("clock", clock_t)
			cyl_m.set_shader_parameter("time_mood", time_mood)
			cyl_m.set_shader_parameter("mood_weights", mood_weights)
			cyl_m.set_shader_parameter("film_dim", film_dim)
		if water_m != null:
			water_m.set_shader_parameter("clock", water_t)
			var w_n := mood_weights.x
			var w_g := mood_weights.y
			var w_t := mood_weights.z
			var deep := Color(0.010, 0.036, 0.072) * w_n + Color(0.032, 0.082, 0.112) * w_g + Color(0.024, 0.040, 0.102) * w_t
			var shallow := Color(0.036, 0.17, 0.25) * w_n + Color(0.11, 0.27, 0.23) * w_g + Color(0.10, 0.15, 0.29) * w_t
			var sky_c := Color(0.14, 0.24, 0.42) * w_n + Color(0.72, 0.50, 0.26) * w_g + Color(0.46, 0.25, 0.44) * w_t
			var caust := Color(0.32, 0.80, 0.94) * w_n + Color(0.94, 0.78, 0.42) * w_g + Color(0.84, 0.56, 0.62) * w_t
			var glint := Color(0.78, 0.92, 1.0) * w_n + Color(1.0, 0.88, 0.58) * w_g + Color(1.0, 0.70, 0.60) * w_t
			water_m.set_shader_parameter("deep_colour", deep)
			water_m.set_shader_parameter("shallow_colour", shallow)
			water_m.set_shader_parameter("sky_colour", sky_c)
			water_m.set_shader_parameter("caustic_colour", caust)
			water_m.set_shader_parameter("glint_colour", glint)
			water_m.set_shader_parameter("caustic_level", lerpf(0.42, 0.70, house))
			water_m.set_shader_parameter("glint_dir", Vector3(0.0, 0.48, -0.88).normalized())
			water_m.set_shader_parameter("glint_level", 0.82 + 0.42 * w_g + 0.28 * w_t)


## Lightweight mesh builder for custom-shader opaque world meshes (positions, normals, colours, UV, UV2).
class Verts:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func count() -> int:
		return idx.size()

	func vert(p: Vector3, nrm: Vector3, col: Color, t := Vector2.ZERO, meta := Vector2.ZERO) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		uv2.append(meta)
		return v.size() - 1

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, col: Color,
			uvs: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], meta := Vector2.ZERO) -> void:
		var k0 := vert(a, nrm, col, uvs[0], meta)
		vert(b, nrm, col, uvs[1], meta)
		vert(cc, nrm, col, uvs[2], meta)
		vert(d, nrm, col, uvs[3], meta)
		# Godot front faces wind clockwise when looking against the normal.
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			idx.append_array([k0, k0 + 2, k0 + 1, k0, k0 + 3, k0 + 2])
		else:
			idx.append_array([k0, k0 + 1, k0 + 2, k0, k0 + 2, k0 + 3])

	func grid(rows: Array, normals: Array, uvs: Array, cols: Array, meta := Vector2.ZERO) -> void:
		var w := (rows[0] as PackedVector3Array).size()
		var base := v.size()
		for i in rows.size():
			var r: PackedVector3Array = rows[i]
			var nr: PackedVector3Array = normals[i]
			var ur: PackedVector2Array = uvs[i]
			var cr: PackedColorArray = cols[i]
			for j in w:
				vert(r[j], nr[j], cr[j], ur[j], meta)
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
		"ring_terrace":
			_terrace(c, h)
		"ring_cylinder":
			_cylinder(h)
	for b: RoomMesh in [c.s, c.u, c.lit, c.glass, c.cove]:
		b.colour = Color.WHITE


static func hall(c: Object) -> Hall:
	for h: Object in c.halls:
		if h is Hall:
			return h
	var h := Hall.new()
	h.kit = c.kit
	c.halls.append(h)
	return h


# --- Helpers ----------------------------------------------------------------------------------------------------------

static func _lin(col: Color, alpha := 1.0) -> Color:
	var l := col.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _titanium(c: Object) -> Material:
	return c.shiny("chrome", 0.94, 0.80, 0.12)


static func _bronze(c: Object) -> Material:
	return c.shiny("gilt", 0.90, 0.72, 0.16)


static func _solid(c: Object, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, basis))


static func _prow_z(x: float) -> float:
	var u := clampf(x / TERRACE_HW, -1.0, 1.0)
	return PROW_Z + PROW_CURVE * u * u


static func _pool_outer_z(x: float) -> float:
	var u := clampf(x / 6.6, -1.0, 1.0)
	return -8.25 + 2.45 * u * u


static func _cyl_pt(theta: float, z: float, r := CYL_RADIUS) -> Vector3:
	return Vector3(r * sin(theta), CYL_CENTER_Y - r * cos(theta), z)


static func _cyl_in_n(theta: float) -> Vector3:
	return Vector3(-sin(theta), cos(theta), 0.0).normalized()


# --- Terrace piece (`ring_terrace`) -----------------------------------------------------------------------------------

static func _terrace(c: Object, h: Hall) -> void:
	_deck_and_pool(c, h)
	_screen_frame(c)
	_canopy_ribs(c)
	_balustrades(c)
	_planters_and_trees(c)
	_bollards_and_tables(c)
	_seat_shells(c)
	_aft_promenade(c)


## Sweeping cantilevered honed-travertine observation terrace, stepped forward rim, infinity reflecting pool,
## lounge wool rug, bronze floor expansion strips, under-deck structural belly, and curved terrace rim coves.
static func _deck_and_pool(c: Object, h: Hall) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var segs := 28

	# 1. Main upper honed-travertine deck slab (`y = 0.0`, curved forward prow to `TERRACE_BZ`).
	s.surface(c.tinted("stone"))
	s.colour = _lin(TRAVERTINE)
	var top_front := PackedVector3Array()
	var top_back := PackedVector3Array()
	var top_n := PackedVector3Array()
	var rim_top := PackedVector3Array()
	var rim_bot := PackedVector3Array()
	var rim_n := PackedVector3Array()
	for i in segs + 1:
		var t := lerpf(-1.0, 1.0, float(i) / segs)
		var x := t * TERRACE_HW
		var zf := _prow_z(x)
		top_front.append(Vector3(x, 0.0, zf))
		top_back.append(Vector3(x, 0.0, TERRACE_BZ))
		top_n.append(Vector3.UP)
		rim_top.append(Vector3(x, 0.0, zf))
		rim_bot.append(Vector3(x, -0.15, zf))
		# Outward normal of z = PROW_Z + PROW_CURVE * (x / HW)^2 pointing forward (-Z).
		var dz_dx := 2.0 * PROW_CURVE * x / (TERRACE_HW * TERRACE_HW)
		rim_n.append(Vector3(dz_dx, 0.0, -1.0).normalized())
	s.strip(top_front, top_back, top_n)
	s.colour = _lin(TRAVERTINE_TRIM)
	s.strip(rim_top, rim_bot, rim_n)

	# Side and aft perimeter fascia edges of the main cantilevered terrace slab.
	for side: float in [-1.0, 1.0]:
		var sx := side * TERRACE_HW
		var z0 := _prow_z(sx)
		s.face([Vector3(sx, -0.34, z0), Vector3(sx, -0.34, TERRACE_BZ),
				Vector3(sx, 0.0, TERRACE_BZ), Vector3(sx, 0.0, z0)], Vector3(side, 0.0, 0.0))
	s.face([Vector3(-TERRACE_HW, -0.34, TERRACE_BZ), Vector3(TERRACE_HW, -0.34, TERRACE_BZ),
			Vector3(TERRACE_HW, 0.0, TERRACE_BZ), Vector3(-TERRACE_HW, 0.0, TERRACE_BZ)], Vector3.BACK)

	# Tapered cantilevered under-deck travertine hull belly (visible when peering over balustrades!).
	s.colour = _lin(TRAVERTINE_DARK)
	var hull_out := PackedVector3Array()
	var hull_in := PackedVector3Array()
	var hull_n := PackedVector3Array()
	for i in segs + 1:
		var x := lerpf(-TERRACE_HW, TERRACE_HW, float(i) / segs)
		var zf := _prow_z(x)
		hull_out.append(Vector3(x, -0.34, zf - 0.15))
		hull_in.append(Vector3(x * 0.72, -1.25, zf + 1.4))
		hull_n.append(Vector3(0.0, -0.82, -0.57).normalized())
	s.strip(hull_out, hull_in, hull_n)
	# Under-deck structural belly soffit closing underneath the terrace.
	s.box(Vector3(0.0, -0.78, 1.0), Vector3(TERRACE_HW * 1.48, 0.88, 10.6), Basis(), [RoomMesh.UP])

	# 2. Stepped lower travertine promenade tread (`y = -0.14`) curving gracefully into the infinity pool!
	s.colour = _lin(TRAVERTINE)
	var step_in := PackedVector3Array()
	var step_out := PackedVector3Array()
	var step_n := PackedVector3Array()
	var step_r_top := PackedVector3Array()
	var step_r_bot := PackedVector3Array()
	var step_r_n := PackedVector3Array()
	var pool_hw := 6.6
	for i in segs + 1:
		var x := lerpf(-pool_hw, pool_hw, float(i) / segs)
		var z0 := _prow_z(x)
		var z1 := z0 - 0.44
		step_in.append(Vector3(x, -0.14, z0 + 0.02))
		step_out.append(Vector3(x, -0.14, z1))
		step_n.append(Vector3.UP)
		step_r_top.append(Vector3(x, -0.14, z1))
		step_r_bot.append(Vector3(x, -0.44, z1))
		var dz_dx := 2.0 * PROW_CURVE * x / (TERRACE_HW * TERRACE_HW)
		step_r_n.append(Vector3(dz_dx, 0.0, -1.0).normalized())
	s.strip(step_in, step_out, step_n)
	s.colour = _lin(TRAVERTINE_TRIM)
	s.strip(step_r_top, step_r_bot, step_r_n)

	# 3. Crescent infinity reflecting pool dark-slate tiled basin & cantilevered forward knife-edge weir!
	s.surface(c.tinted("iron"))
	s.colour = _lin(SLATE_DARK)
	var b_in := PackedVector3Array()
	var b_out := PackedVector3Array()
	var b_n := PackedVector3Array()
	var weir_in := PackedVector3Array()
	var weir_out := PackedVector3Array()
	var weir_bot := PackedVector3Array()
	var weir_n := PackedVector3Array()
	for i in segs + 1:
		var x := lerpf(-pool_hw, pool_hw, float(i) / segs)
		var zi := _prow_z(x) - 0.42
		var zo := _pool_outer_z(x)
		b_in.append(Vector3(x, -0.42, zi))
		b_out.append(Vector3(x, -0.42, zo))
		b_n.append(Vector3.UP)
		weir_in.append(Vector3(x, -0.185, zo + 0.06))
		weir_out.append(Vector3(x, -0.185, zo - 0.14))
		weir_bot.append(Vector3(x, -0.64, zo - 0.14))
		var dz_dx := 2.0 * 2.45 * x / (pool_hw * pool_hw)
		weir_n.append(Vector3(dz_dx, 0.0, -1.0).normalized())
	s.strip(b_in, b_out, b_n)
	# Sweeping knife-edge slate infinity weir top & cantilevered forward drop fascia!
	s.strip(weir_in, weir_out, b_n)
	s.strip(weir_out, weir_bot, weir_n)
	# Travertine coping piers closing the left & right tapered ends of the crescent pool.
	s.surface(c.tinted("stone"))
	s.colour = _lin(TRAVERTINE_TRIM)
	for side: float in [-1.0, 1.0]:
		var ex := side * (pool_hw + 0.18)
		var ez := (_prow_z(side * pool_hw) + _pool_outer_z(side * pool_hw)) * 0.5 - 0.18
		s.box(Vector3(ex, -0.24, ez), Vector3(0.42, 0.42, 1.65), Basis(Vector3.UP, -side * 0.24))

	# 4. Infinity reflecting pool water surface (`RingWater`, `env_world_water.gdshader`, 1 opaque draw!).
	var w_rows := 6
	var w_pts: Array = []
	var w_nrms: Array = []
	var w_uvs: Array = []
	var w_cols: Array = []
	for j in w_rows + 1:
		var fv := float(j) / w_rows
		var rp := PackedVector3Array()
		var rn := PackedVector3Array()
		var ru := PackedVector2Array()
		var rc := PackedColorArray()
		for i in segs + 1:
			var fu := float(i) / segs
			var x := lerpf(-pool_hw + 0.04, pool_hw - 0.04, fu)
			var zi := _prow_z(x) - 0.43
			var zo := _pool_outer_z(x) + 0.05
			var z := lerpf(zi, zo, fv)
			rp.append(Vector3(x, -0.195, z))
			rn.append(Vector3.UP)
			ru.append(Vector2(fu, fv))
			# COLOR.r = shallow edge share (tight turquoise step & weir edge, dark obsidian mirror basin center);
			# COLOR.g = concealed underwater step glow strictly localized along the submerged rim!
			var step_edge := 1.0 - smoothstep(0.0, 0.18, fv)
			var weir_edge := 1.0 - smoothstep(0.0, 0.12, 1.0 - fv)
			var end_shallow := 1.0 - smoothstep(0.0, 0.10, minf(fu, 1.0 - fu))
			var shallow_r := clampf(0.08 + 0.82 * maxf(maxf(step_edge, weir_edge * 0.65), end_shallow * 0.60), 0.0, 1.0)
			var extra_g := clampf(0.72 * (1.0 - smoothstep(0.0, 0.15, fv)) + 0.28 * (1.0 - smoothstep(0.0, 0.10, 1.0 - fv)), 0.0, 1.0)
			rc.append(Color(shallow_r, extra_g, 0.0, 1.0))
		w_pts.append(rp)
		w_nrms.append(rn)
		w_uvs.append(ru)
		w_cols.append(rc)
	h.water.grid(w_pts, w_nrms, w_uvs, w_cols)

	# 5. Mid-century woven architectural lounge wool rug grounding the 3x3 lounge chairs (`y = 0.012`).
	var rx := 2.65
	var rz := 2.82
	var rt := 0.014
	s.surface(c.tinted("fabric"))
	s.colour = _lin(RUG_FIELD)
	s.box(Vector3(0.0, rt * 0.5, 0.0), Vector3(rx * 2.0, rt, rz * 2.0), Basis(), [RoomMesh.DOWN])
	var bw := 0.22
	s.colour = _lin(RUG_BORDER)
	for band: Array in [
			[Vector2(-rx, -rz), Vector2(rx, -rz + bw)], [Vector2(-rx, rz - bw), Vector2(rx, rz)],
			[Vector2(-rx, -rz + bw), Vector2(-rx + bw, rz - bw)], [Vector2(rx - bw, -rz + bw), Vector2(rx, rz - bw)]]:
		var p0: Vector2 = band[0]
		var p1: Vector2 = band[1]
		s.face([Vector3(p0.x, rt + 0.001, p0.y), Vector3(p1.x, rt + 0.001, p0.y),
				Vector3(p1.x, rt + 0.001, p1.y), Vector3(p0.x, rt + 0.001, p1.y)], Vector3.UP)
	s.colour = _lin(RUG_LINE)
	var li := bw + 0.08
	var lw := 0.032
	for band: Array in [
			[Vector2(-rx + li, -rz + li), Vector2(rx - li, -rz + li + lw)],
			[Vector2(-rx + li, rz - li - lw), Vector2(rx - li, rz - li)],
			[Vector2(-rx + li, -rz + li + lw), Vector2(-rx + li + lw, rz - li - lw)],
			[Vector2(rx - li - lw, -rz + li + lw), Vector2(rx - li, rz - li - lw)]]:
		var p0: Vector2 = band[0]
		var p1: Vector2 = band[1]
		s.face([Vector3(p0.x, rt + 0.0015, p0.y), Vector3(p1.x, rt + 0.0015, p0.y),
				Vector3(p1.x, rt + 0.0015, p1.y), Vector3(p0.x, rt + 0.0015, p1.y)], Vector3.UP)

	# 6. Champagne-bronze architectural floor expansion inlay strips across the travertine terrace!
	u.surface(_bronze(c))
	u.colour = _lin(BRONZE_GOLD)
	for x_in: float in [-3.4, 3.4, -6.1, 6.1]:
		var z_start := _prow_z(x_in) + 0.25
		var z_end := TERRACE_BZ - 0.25
		u.box(Vector3(x_in, 0.003, (z_start + z_end) * 0.5), Vector3(0.026, 0.006, z_end - z_start), Basis(), [RoomMesh.DOWN])
	for z_in: float in [-3.4, 3.4, 4.9]:
		u.box(Vector3(0.0, 0.003, z_in), Vector3(TERRACE_HW * 1.92, 0.006, 0.026), Basis(), [RoomMesh.DOWN])
	# Brushed-titanium stepped-terrace nosing trim curving along the forward prow edge!
	u.surface(_titanium(c))
	u.colour = _lin(TITANIUM)
	var n_a := PackedVector3Array()
	var n_b := PackedVector3Array()
	var n_n := PackedVector3Array()
	for i in segs + 1:
		var x := lerpf(-TERRACE_HW, TERRACE_HW, float(i) / segs)
		var zf := _prow_z(x)
		n_a.append(Vector3(x, 0.005, zf + 0.045))
		n_b.append(Vector3(x, 0.005, zf - 0.015))
		n_n.append(Vector3.UP)
	u.strip(n_a, n_b, n_n)

	# 7. Indirect curved architectural terrace cove strips (`PieceCove`, live Warm gold / Orbital cyan / Off)!
	cove.surface(c.kit.cove_material())
	var cove_tint := Color(0.96, 0.96, 0.94).srgb_to_linear()
	cove.colour = Color(cove_tint.r, cove_tint.g, cove_tint.b, 0.96)
	# Sweeping curved cove strip tucked right under the upper terrace prow lip washing down onto the step & pool!
	var ca := PackedVector3Array()
	var cb := PackedVector3Array()
	var cn := PackedVector3Array()
	for i in segs + 1:
		var x := lerpf(-pool_hw, pool_hw, float(i) / segs)
		var zf := _prow_z(x) - 0.008
		var dz_dx := 2.0 * PROW_CURVE * x / (TERRACE_HW * TERRACE_HW)
		ca.append(Vector3(x, -0.045, zf))
		cb.append(Vector3(x, -0.115, zf))
		cn.append(Vector3(dz_dx, 0.0, -1.0).normalized())
	cove.strip(ca, cb, cn)
	# Soft horizontal cove strips along the outer deck walkways flanking the seating zone!
	cove.colour = Color(cove_tint.r, cove_tint.g, cove_tint.b, 0.78)
	for side: float in [-1.0, 1.0]:
		var gx := side * 7.04
		cove.face([Vector3(gx - 0.025, 0.006, -4.1), Vector3(gx + 0.025, 0.006, -4.1),
				Vector3(gx + 0.025, 0.006, 5.75), Vector3(gx - 0.025, 0.006, 5.75)], Vector3.UP)


## Floating slim brushed-titanium cantilevered cinema screen frame (`center: [0, 2.85, -8.9]`, `size: [6.2, 3.49]`).
## Strictly positioned at `z <= -8.92` so nothing ever enters in front of the picture from any seat!
static func _screen_frame(c: Object) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 2.85, -8.9)))
	var sc_sz: Vector2 = scr.get("size", Vector2(6.2, 3.49))
	var sc_x := sc_xf.origin.x
	var sc_y := sc_xf.origin.y
	var sc_z := sc_xf.origin.z
	var sw := sc_sz.x
	var sh := sc_sz.y
	var hsw := sw * 0.5
	var hsh := sh * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# 1. Matte-slate recessed cinema mask bezel & slim backing panel strictly behind the picture plane.
	var bw := 0.085
	var bz := sc_z - 0.048
	s.surface(c.tinted("iron"))
	s.colour = _lin(SLATE_DARK)
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(sc_x + side * (hsw + bw * 0.5), sc_y, bz), Vector3(bw, sh + bw * 2.0, 0.068))
	s.box(Vector3(sc_x, sc_y + hsh + bw * 0.5, bz), Vector3(sw, bw, 0.068))
	s.box(Vector3(sc_x, sc_y - hsh - bw * 0.5, bz), Vector3(sw, bw, 0.068))
	# Slim matte rear backing enclosure behind the picture so stars never leak through behind the screen!
	s.box(Vector3(sc_x, sc_y, sc_z - 0.072), Vector3(sw + 0.04, sh + 0.04, 0.024))

	# 2. Sleek chamfered brushed-titanium floating outer aerospace halo frame + twin cantilevered V-strut pylons!
	u.surface(_titanium(c))
	u.colour = _lin(TITANIUM)
	var rim_w := 0.042
	var fr_z := sc_z - 0.036
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(sc_x + side * (hsw + bw + rim_w * 0.5), sc_y, fr_z),
				Vector3(rim_w, sh + bw * 2.0 + rim_w * 2.0, 0.088))
		# Machined aerospace corner clamp collars at all 4 corners of the floating chassis.
		for sy: float in [-1.0, 1.0]:
			u.box(Vector3(sc_x + side * (hsw + bw + rim_w + 0.024), sc_y + sy * (hsh + bw - 0.14), fr_z - 0.02),
					Vector3(0.056, 0.34, 0.095))
	u.box(Vector3(sc_x, sc_y + hsh + bw + rim_w * 0.5, fr_z), Vector3(sw + bw * 2.0, rim_w, 0.088))
	u.box(Vector3(sc_x, sc_y - hsh - bw - rim_w * 0.5, fr_z), Vector3(sw + bw * 2.0, rim_w, 0.088))

	# Twin dramatic cantilevered brushed-titanium V-struts anchoring the floating screen cleanly down below the pool weir!
	var bot_y := sc_y - hsh - bw - rim_w
	for side: float in [-1.0, 1.0]:
		var sx := sc_x + side * 2.15
		var p_top := Vector3(sx, bot_y + 0.02, sc_z - 0.065)
		var p_top_out := Vector3(sx + side * 0.34, bot_y + 0.02, sc_z - 0.065)
		var p_foot := Vector3(sx - side * 0.12, -0.58, _pool_outer_z(sx) - 0.08)
		var p_keel := Vector3(sx - side * 0.25, -0.95, _pool_outer_z(sx) + 0.85)
		u.colour = _lin(TITANIUM)
		Shapes.beam(u, p_foot, p_top, Vector2(0.11, 0.16))
		u.colour = _lin(TITANIUM_SATIN)
		Shapes.beam(u, p_foot, p_top_out, Vector2(0.065, 0.085))
		Shapes.beam(u, p_keel, p_foot, Vector2(0.14, 0.18))
		# Sleek titanium horizontal saddle crossbar linking both struts behind the bottom chassis rail.
		u.box(Vector3(sx, bot_y - 0.05, sc_z - 0.09), Vector3(0.46, 0.08, 0.12))
		# Machined dark-slate & champagne-bronze structural anchor collar clamping each V-strut cleanly to the weir!
		var weir_z := _pool_outer_z(sx) - 0.08
		s.surface(c.tinted("iron"))
		s.colour = _lin(SLATE_DARK)
		s.box(Vector3(sx - side * 0.10, -0.34, weir_z), Vector3(0.32, 0.48, 0.30))
		u.surface(_bronze(c))
		u.colour = _lin(BRONZE_GOLD)
		u.box(Vector3(sx - side * 0.10, -0.10, weir_z), Vector3(0.34, 0.032, 0.32))
		u.surface(_titanium(c))
		u.colour = _lin(TITANIUM)
	u.box(Vector3(sc_x, bot_y - 0.04, sc_z - 0.10), Vector3(4.5, 0.065, 0.08))

	# Fine champagne-bronze inner pinstripe line between slate mask and titanium outer halo.
	u.surface(_bronze(c))
	u.colour = _lin(BRONZE_GOLD)
	u.box(Vector3(sc_x, sc_y - hsh - bw - 0.008, sc_z - 0.006), Vector3(sw + bw * 2.0, 0.016, 0.012))

	# 3. Indirect subtle halo cove tucked behind the floating chassis perimeter (`PieceCove`).
	cove.surface(c.kit.cove_material())
	var ct := Color(0.96, 0.96, 0.94).srgb_to_linear()
	cove.colour = Color(ct.r, ct.g, ct.b, 0.65)
	cove.face([Vector3(sc_x - hsw - 0.05, bot_y - 0.015, sc_z - 0.072),
			Vector3(sc_x + hsw + 0.05, bot_y - 0.015, sc_z - 0.072),
			Vector3(sc_x + hsw + 0.05, bot_y + 0.025, sc_z - 0.072),
			Vector3(sc_x - hsw - 0.05, bot_y + 0.025, sc_z - 0.072)], Vector3.BACK)


## Sweeping mid-century-futurist brushed-titanium arched canopy wing-ribs & aft observatory canopy soffit.
## Forward ribs curve dramatically open into cantilevered wingtips (`|x| = 4.35, y = 6.15`) leaving the entire
## central overhead & forward sky 100% open to the upside-down O'Neill cylinder continents and Milky Way!
static func _canopy_ribs(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	# Sculpted travertine buttress plinths rooting all 4 rib stations cleanly into the terrace perimeter (`|x| = 7.42`).
	var rib_zs: Array[float] = [-2.55, 0.35, 3.15, 5.72]
	s.surface(c.tinted("stone"))
	s.colour = _lin(TRAVERTINE_TRIM)
	for rz: float in rib_zs:
		for side: float in [-1.0, 1.0]:
			s.box(Vector3(side * 7.46, 0.36, rz), Vector3(0.42, 0.84, 0.44), Basis(), [RoomMesh.DOWN])
			_solid(c, Vector3(side * 7.46, 0.42, rz), Vector3(0.44, 0.84, 0.46))

	# Sweeping parabolic arched brushed-titanium canopy ribs!
	u.surface(_titanium(c))
	u.colour = _lin(TITANIUM)
	var open_ribs: Array[float] = [-2.55, 0.35]
	var full_ribs: Array[float] = [3.15, 5.72]

	# Helper closure points for a sweeping arch curve from base (x = 7.42, y = 0.0) to crown (x = 0.0, y = 6.22).
	var arch_pt := func(side: float, t: float) -> Vector2:
		# t in 0..1: smooth bowed aerospace parabolic curve leaning gently outward at waist then arching over!
		var x := side * (7.42 * cos(t * PI * 0.5) + 0.58 * sin(t * PI) * (1.0 - t * 0.5))
		var y := 6.22 * sin(t * PI * 0.5)
		return Vector2(x, y)

	# 1. Forward cantilevered gull-wing observatory ribs (`t: 0.0 .. 0.62`, opening wide above the seating deck!).
	for rz: float in open_ribs:
		for side: float in [-1.0, 1.0]:
			var steps := 12
			var prev := Vector3.ZERO
			for k in steps + 1:
				var t := 0.60 * float(k) / steps
				var p2: Vector2 = arch_pt.call(side, t)
				var p3 := Vector3(p2.x, p2.y, rz)
				if k > 0:
					var taper := lerpf(1.0, 0.42, float(k) / steps)
					Shapes.beam(u, prev, p3, Vector2(0.18 * taper, 0.24 * taper))
				prev = p3
			# Sleek tapered inner titanium flange web & glowing indirect rib cove strip tucked neatly inside the soffit!
			cove.surface(c.kit.cove_material())
			var ct := Color(0.96, 0.96, 0.94).srgb_to_linear()
			cove.colour = Color(ct.r, ct.g, ct.b, 0.86)
			var ca := PackedVector3Array()
			var cb := PackedVector3Array()
			var cn := PackedVector3Array()
			for k in 10:
				var f_k := float(k) / 9.0
				var t := 0.12 + 0.44 * f_k
				var p2: Vector2 = arch_pt.call(side, t)
				var inward := Vector3(-side * 0.85, -0.52, 0.0).normalized()
				var p_in := Vector3(p2.x, p2.y, rz) + inward * lerpf(0.112, 0.074, f_k)
				var hw_c := lerpf(0.024, 0.014, f_k)
				ca.append(p_in + Vector3(0.0, 0.0, -hw_c))
				cb.append(p_in + Vector3(0.0, 0.0, hw_c))
				cn.append(inward)
			cove.strip(ca, cb, cn)

	# 2. Aft full sweeping structural arches (`t: -1.0 .. +1.0` continuously across the overhead crown!).
	u.surface(_titanium(c))
	u.colour = _lin(TITANIUM)
	for rz: float in full_ribs:
		var steps := 24
		var prev := Vector3.ZERO
		for k in steps + 1:
			var frac := float(k) / steps
			var p2: Vector2
			if frac <= 0.5:
				p2 = arch_pt.call(-1.0, frac * 2.0)
			else:
				p2 = arch_pt.call(1.0, (1.0 - frac) * 2.0)
			var p3 := Vector3(p2.x, p2.y, rz)
			if k > 0:
				Shapes.beam(u, prev, p3, Vector2(0.18, 0.25))
			prev = p3

	# 3. Longitudinal brushed-titanium tension purlins terminating flush between the 4 rib stations (zero overhang!).
	u.colour = _lin(TITANIUM_SATIN)
	for side: float in [-1.0, 1.0]:
		for pt_t: float in [0.34, 0.56]:
			var p2: Vector2 = arch_pt.call(side, pt_t)
			var z_start := rib_zs[0] + 0.04
			var z_end := rib_zs[-1] - 0.04
			u.box(Vector3(p2.x, p2.y, (z_start + z_end) * 0.5), Vector3(0.085, 0.070, z_end - z_start))

	# 4. Aft cantilevered observatory partial canopy soffit (`z = +3.18 .. +5.82`) with warm architectural cedar slats,
	#    recessed warm soffit downlights (`PieceLamps`), and continuous curved cove wash (`PieceCove`)!
	var sof_steps := 16
	var sf_a := PackedVector3Array()
	var sf_b := PackedVector3Array()
	var sf_n := PackedVector3Array()
	for k in sof_steps + 1:
		var frac := float(k) / sof_steps
		var p2: Vector2
		if frac <= 0.5:
			p2 = arch_pt.call(-1.0, 0.52 + frac * 0.96)
		else:
			p2 = arch_pt.call(1.0, 0.52 + (1.0 - frac) * 0.96)
		var inward := Vector3(-p2.x, 3.0 - p2.y, 0.0).normalized()
		var p_off := Vector2(p2.x, p2.y) + Vector2(inward.x, inward.y) * 0.14
		sf_a.append(Vector3(p_off.x, p_off.y, 3.22))
		sf_b.append(Vector3(p_off.x, p_off.y, 5.76))
		sf_n.append(Vector3(inward.x, inward.y, 0.0).normalized())
	s.surface(c.tinted("wood"))
	s.colour = _lin(CEDAR)
	s.strip(sf_a, sf_b, sf_n)
	# Sleek curved dark-cedar outer roof cap over the aft canopy soffit so it has clean architectural thickness.
	s.colour = _lin(CEDAR_DARK)
	var cap_a := PackedVector3Array()
	var cap_b := PackedVector3Array()
	var cap_n := PackedVector3Array()
	for k in sof_steps + 1:
		cap_a.append(sf_a[k] + Vector3(0.0, 0.12, 0.0))
		cap_b.append(sf_b[k] + Vector3(0.0, 0.12, 0.0))
		cap_n.append(Vector3.UP)
	s.strip(cap_a, cap_b, cap_n)

	# Curved architectural cove ribbon along the leading edge of the aft canopy soffit (`PieceCove`).
	cove.surface(c.kit.cove_material())
	var ct := Color(0.96, 0.96, 0.94).srgb_to_linear()
	cove.colour = Color(ct.r, ct.g, ct.b, 0.88)
	var lc_a := PackedVector3Array()
	var lc_b := PackedVector3Array()
	for k in sof_steps + 1:
		lc_a.append(sf_a[k] + sf_n[k] * 0.015)
		lc_b.append(sf_a[k] + sf_n[k] * 0.015 + Vector3(0.0, 0.0, 0.16))
	cove.strip(lc_a, lc_b, sf_n)

	# Four warm architectural recessed soffit downlight discs tucked under the aft canopy (`PieceLamps`).
	lit.surface(c.shade(LAMP_GLOW))
	for dl_x: float in [-3.1, -1.05, 1.05, 3.1]:
		var t_approx := clampf(1.0 - absf(dl_x) / 7.42, 0.55, 1.0)
		var dl_y := 6.22 * sin(t_approx * PI * 0.5) - 0.18
		var at := Vector3(dl_x, dl_y, 4.48)
		var ring: Array = []
		for j in 12:
			var a := TAU * float(j) / 12.0
			ring.append(at + Vector3(cos(a) * 0.11, 0.0, sin(a) * 0.11))
		lit.face(ring, Vector3.DOWN)


## Frameless low architectural glass balustrades (`PieceGlass`, single-layer quads for minimal blend overdraw!)
## running cleanly along port/starboard terrace edges and the outer curved pool-overlook wings (`|x| >= 4.2`).
static func _balustrades(c: Object) -> void:
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var rail_h := 0.92
	var shoe_h := 0.09
	var gx := 7.18
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)

	u.surface(_titanium(c))
	u.colour = _lin(TITANIUM)
	glass.surface(c.kit.GLASS)

	# 1. Port & starboard straight terrace perimeter glass balustrades (`z = -4.25 .. +5.75`).
	var z0 := -4.25
	var z1 := 5.75
	var span := z1 - z0
	var mid_z := (z0 + z1) * 0.5
	for side: float in [-1.0, 1.0]:
		var bx := side * gx
		# Brushed-titanium continuous floor shoe channel & ultra-slim top handrail cap!
		u.box(Vector3(bx, shoe_h * 0.5, mid_z), Vector3(0.065, shoe_h, span), Basis(), [RoomMesh.DOWN])
		Shapes.cylinder(u, Vector3(bx, rail_h, z0), 0.018, span, 8, basis_z)
		# Minimalist machined titanium vertical glass clamp stanchions spaced every 2.0 m.
		for k in 6:
			var pz := lerpf(z0, z1, float(k) / 5.0)
			u.box(Vector3(bx, 0.18, pz), Vector3(0.078, 0.20, 0.045))
			u.box(Vector3(bx, rail_h * 0.5, pz), Vector3(0.024, rail_h, 0.024))
		# SINGLE-LAYER frameless glass sheet (one quad per side -> zero double-layer overdraw!).
		Shapes.quad(glass, Vector3(bx, (shoe_h + rail_h) * 0.5, mid_z),
				Vector3(0.0, 0.0, span * 0.5), Vector3(0.0, (rail_h - shoe_h) * 0.5, 0.0), Vector3(-side, 0.0, 0.0))
		_solid(c, Vector3(bx, rail_h * 0.5, mid_z), Vector3(0.08, rail_h, span))

	# 2. Outer curved wing overlook balustrades flanking the infinity pool (`|x| = 4.35 .. 7.18`), leaving the
	#    central forward pool overlook `|x| < 4.35` completely open & glass-free in front of the cinema screen!
	for side: float in [-1.0, 1.0]:
		var w_segs := 4
		for k in w_segs:
			var x0 := side * lerpf(4.35, gx, float(k) / w_segs)
			var x1 := side * lerpf(4.35, gx, float(k + 1) / w_segs)
			var p0 := Vector3(x0, 0.0, _prow_z(x0) + 0.16)
			var p1 := Vector3(x1, 0.0, _prow_z(x1) + 0.16)
			var mid := (p0 + p1) * 0.5
			var along := p1 - p0
			var seg_len := along.length()
			var dir := along / maxf(seg_len, 0.001)
			var nrm := Vector3.UP.cross(dir).normalized()
			if nrm.z < 0.0:
				nrm = -nrm
			Shapes.beam(u, p0 + Vector3(0.0, shoe_h * 0.5, 0.0), p1 + Vector3(0.0, shoe_h * 0.5, 0.0),
					Vector2(0.065, shoe_h))
			Shapes.beam(u, p0 + Vector3(0.0, rail_h, 0.0), p1 + Vector3(0.0, rail_h, 0.0), Vector2(0.032, 0.032))
			u.box(p0 + Vector3(0.0, rail_h * 0.5, 0.0), Vector3(0.026, rail_h, 0.026))
			Shapes.quad(glass, mid + Vector3(0.0, (shoe_h + rail_h) * 0.5, 0.0),
					dir * (seg_len * 0.5), Vector3(0.0, (rail_h - shoe_h) * 0.5, 0.0), nrm)
		# Crisp brushed-titanium terminal newel post at the inner overlook edge (`|x| = 4.35`).
		var end_p := Vector3(side * 4.35, 0.0, _prow_z(side * 4.35) + 0.16)
		Shapes.cylinder(u, end_p, 0.024, rail_h + 0.02, 10)
		_solid(c, Vector3(side * 5.76, rail_h * 0.5, -4.65), Vector3(2.85, rail_h, 0.6))


## Four warm oiled-cedar & honed-travertine architectural planters holding sculpted stylized terrace bamboo groves
## (forward wings) and dwarf sculpted terrace cypresses (aft flanks), all strictly clear of screen sight lines!
static func _planters_and_trees(c: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2077

	# Forward pair: angled gracefully along the curved prow wings (`|x| = 5.45, z = -3.75`), holding bamboo + agaves!
	for side: float in [-1.0, 1.0]:
		var px := side * 5.45
		var pz := -3.75
		var yaw := -side * 0.30
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(px, 0.0, pz))
		_planter_box(c, xf, Vector3(2.05, 0.62, 1.02))
		_bamboo_grove(c, xf, rng, side)
		_agave_tuft(c, xf * Vector3(-side * 0.62, 0.56, 0.22), 0.34, rng)
		_solid(c, Vector3(px, 0.45, pz), Vector3(2.1, 0.9, 1.1), Basis(Vector3.UP, yaw))

	# Aft pair: flanking the lounge seating promenade (`|x| = 5.70, z = +2.45`), holding sculpted dwarf cypresses!
	for side: float in [-1.0, 1.0]:
		var px := side * 5.70
		var pz := 2.45
		var xf := Transform3D(Basis(), Vector3(px, 0.0, pz))
		_planter_box(c, xf, Vector3(1.55, 0.62, 1.95))
		_dwarf_cypress(c, xf * Vector3(0.0, 0.56, -0.25), 2.95, rng)
		_dwarf_cypress(c, xf * Vector3(side * 0.24, 0.56, 0.48), 2.15, rng)
		_agave_tuft(c, xf * Vector3(-side * 0.35, 0.56, 0.45), 0.30, rng)
		_solid(c, Vector3(px, 0.45, pz), Vector3(1.6, 0.9, 2.0))


## One tiered honed-travertine & vertical cedar-slat architectural planter box with recessed dark soil bed & cove trim.
static func _planter_box(c: Object, xf: Transform3D, sz: Vector3) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var w := sz.x
	var h := sz.y
	var d := sz.z

	# Dark recessed shadow kick-plinth (`y = 0..0.09`).
	s.surface(c.tinted("iron"))
	s.colour = _lin(SLATE_DARK)
	s.box(xf * Vector3(0.0, 0.045, 0.0), Vector3(w - 0.14, 0.09, d - 0.14), xf.basis, [RoomMesh.DOWN, RoomMesh.UP])

	# Main warm oiled-cedar body with vertical architectural timber slats!
	s.surface(c.tinted("wood"))
	s.colour = _lin(CEDAR_DARK)
	s.box(xf * Vector3(0.0, 0.09 + (h - 0.17) * 0.5, 0.0), Vector3(w - 0.05, h - 0.17, d - 0.05), xf.basis,
			[RoomMesh.DOWN, RoomMesh.UP])
	s.colour = _lin(CEDAR)
	var slats_x := maxi(4, int(w / 0.14))
	for k in slats_x:
		var sx := lerpf(-w * 0.46, w * 0.46, float(k) / maxf(slats_x - 1, 1))
		for fs: float in [-1.0, 1.0]:
			s.box(xf * Vector3(sx, 0.09 + (h - 0.17) * 0.5, fs * (d * 0.5 - 0.015)),
					Vector3(0.055, h - 0.19, 0.03), xf.basis)
	var slats_z := maxi(3, int(d / 0.14))
	for k in slats_z:
		var sz_i := lerpf(-d * 0.44, d * 0.44, float(k) / maxf(slats_z - 1, 1))
		for fs: float in [-1.0, 1.0]:
			s.box(xf * Vector3(fs * (w * 0.5 - 0.015), 0.09 + (h - 0.17) * 0.5, sz_i),
					Vector3(0.03, h - 0.19, 0.055), xf.basis)

	# Pale honed-travertine overhanging coping rim + dark soil bed recessed cleanly inside!
	s.surface(c.tinted("stone"))
	s.colour = _lin(TRAVERTINE)
	var rim := 0.10
	for fs: float in [-1.0, 1.0]:
		s.box(xf * Vector3(0.0, h - 0.04, fs * (d * 0.5 - rim * 0.5 + 0.02)),
				Vector3(w + 0.06, 0.08, rim), xf.basis)
		s.box(xf * Vector3(fs * (w * 0.5 - rim * 0.5 + 0.02), h - 0.04, 0.0),
				Vector3(rim, 0.08, d - rim * 2.0 + 0.04), xf.basis)
	s.surface(c.tinted("iron"))
	s.colour = _lin(SOIL_DARK)
	s.box(xf * Vector3(0.0, h - 0.08, 0.0), Vector3(w - rim * 2.0, 0.04, d - rim * 2.0), xf.basis, [RoomMesh.DOWN])

	# Subtle brushed-titanium corner trim angle clips & concealed kick-plinth cove glow (`PieceCove`).
	u.surface(_titanium(c))
	u.colour = _lin(TITANIUM)
	for sx: float in [-1.0, 1.0]:
		for sz_s: float in [-1.0, 1.0]:
			u.box(xf * Vector3(sx * (w * 0.5 + 0.01), h - 0.04, sz_s * (d * 0.5 + 0.01)),
					Vector3(0.04, 0.085, 0.04), xf.basis)
	cove.surface(c.kit.cove_material())
	var ct := Color(0.96, 0.96, 0.94).srgb_to_linear()
	cove.colour = Color(ct.r, ct.g, ct.b, 0.72)
	cove.box(xf * Vector3(0.0, 0.05, 0.0), Vector3(w - 0.09, 0.04, d - 0.09), xf.basis, [RoomMesh.DOWN, RoomMesh.UP])


## Stylized architectural terrace bamboo grove: segmented jade-olive culms with ring nodes & tiered diamond leaf fans.
static func _bamboo_grove(c: Object, xf: Transform3D, rng: RandomNumberGenerator, side: float) -> void:
	var u: RoomMesh = c.u
	var stalks: Array = [
		[Vector2(-0.55, -0.15), 3.35, Vector2(0.18, -0.08)],
		[Vector2(-0.22, 0.14), 2.85, Vector2(-0.10, 0.16)],
		[Vector2(0.05, -0.12), 3.75, Vector2(0.08, -0.14)],
		[Vector2(0.32, 0.10), 2.60, Vector2(0.22, 0.12)],
		[Vector2(0.58, -0.06), 3.15, Vector2(-0.14, -0.08)],
		[Vector2(-0.08, 0.22), 2.30, Vector2(0.05, 0.20)],
	]
	for st: Array in stalks:
		var base2: Vector2 = st[0]
		var h: float = float(st[1])
		var lean: Vector2 = st[2]
		var segs := 6
		var prev := Vector3(base2.x, 0.56, base2.y)
		# Segmented culm with crisp slightly-flared node rings!
		u.surface(c.soft("wood", true))
		for k in range(1, segs + 1):
			var t := float(k) / segs
			var p := Vector3(base2.x + lean.x * t * t, 0.56 + h * t, base2.y + lean.y * t * t)
			var r := lerpf(0.028, 0.014, t)
			u.colour = _lin(BAMBOO_CULM * rng.randf_range(0.88, 1.12))
			Shapes.beam(u, xf * prev, xf * p, Vector2(r * 2.0, r * 2.0))
			# Ring collar at each node.
			u.colour = _lin(BAMBOO_CULM * 1.22)
			u.box(xf * p, Vector3(r * 2.6, 0.018, r * 2.6), xf.basis)
			# Delicate bamboo leaf clusters sprouting from upper nodes!
			if k >= 3:
				u.surface(c.soft("leaves", true))
				for l in 7:
					var az := TAU * float(l) / 7.0 + float(k) * 1.1 + side
					var dir := Vector3(cos(az) * 0.85, rng.randf_range(-0.22, 0.45), sin(az) * 0.85).normalized()
					var llen := rng.randf_range(0.24, 0.40) * (1.15 - 0.3 * t)
					var across := dir.cross(Vector3.UP).normalized() * llen * 0.22
					if across.length() < 0.001:
						across = Vector3.RIGHT * 0.05
					u.colour = _lin(LEAF_DEEP.lerp(LEAF_BRIGHT, rng.randf_range(0.25, 0.95)))
					Shapes.leaf(u, xf * p, xf.basis * (dir * llen), xf.basis * across,
							(xf.basis * dir.cross(across)).normalized())
				u.surface(c.soft("wood", true))
			prev = p


## Sculpted stylized mid-century dwarf terrace cypress: gently curving trunk + tiered organic emerald foliage clouds.
static func _dwarf_cypress(c: Object, base_pos: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	u.surface(c.soft("wood", true))
	u.colour = _lin(CYPRESS_BARK)
	var trunk_pts: Array[Vector3] = [
		base_pos,
		base_pos + Vector3(0.05, h * 0.28, -0.04),
		base_pos + Vector3(-0.04, h * 0.56, 0.05),
		base_pos + Vector3(0.02, h * 0.82, -0.02),
	]
	for k in trunk_pts.size() - 1:
		var thick := lerpf(0.11, 0.045, float(k) / 2.0)
		Shapes.beam(u, trunk_pts[k], trunk_pts[k + 1], Vector2(thick, thick))

	# Tiered sculpted architectural foliage pads (cloud-pruned cypress aesthetic, clean low-poly lathes!).
	var clouds: Array = [
		[Vector3(-0.26, h * 0.44, 0.16), 0.36, 0.16],
		[Vector3(0.28, h * 0.52, -0.18), 0.40, 0.17],
		[Vector3(-0.18, h * 0.68, -0.22), 0.38, 0.17],
		[Vector3(0.22, h * 0.76, 0.20), 0.34, 0.15],
		[Vector3(0.0, h * 0.90, 0.0), 0.42, 0.20],
		[Vector3(0.02, h * 1.02, -0.02), 0.24, 0.15],
	]
	u.surface(c.soft("leaves", true))
	for cl: Array in clouds:
		var off: Vector3 = cl[0]
		var r: float = float(cl[1])
		var rh: float = float(cl[2])
		var prof: Array = []
		for i in 7:
			var ang := lerpf(-PI * 0.5, PI * 0.5, float(i) / 6.0)
			var bump := 0.90 + 0.18 * rng.randf() if i > 0 and i < 6 else 1.0
			prof.append(Vector2(cos(ang) * r * bump, sin(ang) * rh))
		u.colour = _lin(LEAF_DEEP.lerp(LEAF_BRIGHT, clampf((off.y / h - 0.3) * 1.1, 0.15, 1.0)))
		Shapes.lathe(u, prof, base_pos + off, 10)
		# Slim branch connecting trunk to cloud center.
		u.surface(c.soft("wood", true))
		u.colour = _lin(CYPRESS_BARK)
		Shapes.beam(u, base_pos + Vector3(0.0, off.y - 0.16, 0.0), base_pos + off, Vector2(0.032, 0.032))
		u.surface(c.soft("leaves", true))


## Sculptural mid-century architectural agave rosette tuft nestled at the base of the planters.
static func _agave_tuft(c: Object, at: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	u.surface(c.soft("leaves", true))
	for ring in 2:
		var count := 8 if ring == 0 else 6
		for k in count:
			var a := TAU * float(k) / count + float(ring) * 0.42
			var lift := 0.32 if ring == 0 else 0.72
			var len_b := r * (1.05 if ring == 0 else 0.76)
			var dir := Vector3(cos(a), lift, sin(a)).normalized()
			var across := dir.cross(Vector3.UP).normalized() * len_b * 0.20
			u.colour = _lin(Color(0.28, 0.46, 0.36) * rng.randf_range(0.9, 1.1))
			Shapes.leaf(u, at, dir * len_b, across, dir.cross(across).normalized())


## Six sleek brushed-titanium & warm frosted opal-glass globe bollard lamps (`PieceLamps`, `bake_lamps: 6`) plus
## two mid-century circular travertine & titanium lounge side-tables holding ceramic carafes!
static func _bollards_and_tables(c: Object) -> void:
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit

	# 1. Six architectural globe bollard lamps framing the curved pool rim, flanking walkways & aft promenade.
	var bollards: Array[Vector3] = [
		Vector3(-3.95, 0.0, -5.05), Vector3(3.95, 0.0, -5.05),
		Vector3(-6.45, 0.0, -0.55), Vector3(6.45, 0.0, -0.55),
		Vector3(-4.45, 0.0, 4.45), Vector3(4.45, 0.0, 4.45),
	]
	for bp: Vector3 in bollards:
		# Weighted dark-slate plinth & slender brushed-titanium column post.
		u.surface(c.soft("plastic", true))
		u.colour = _lin(SLATE_DARK)
		Shapes.lathe(u, [Vector2(0.115, 0.0), Vector2(0.115, 0.04), Vector2(0.085, 0.075)], bp, 12)
		u.surface(_titanium(c))
		u.colour = _lin(TITANIUM)
		Shapes.lathe(u, [Vector2(0.048, 0.07), Vector2(0.042, 0.58), Vector2(0.095, 0.62), Vector2(0.095, 0.64)], bp, 12)
		# Floating spun-titanium reflector saucer crowning the glowing globe (shields stars from upward glare!).
		Shapes.lathe(u, [Vector2(0.185, 0.88), Vector2(0.195, 0.90), Vector2(0.11, 0.945), Vector2(0.0, 0.96)], bp, 14)
		# Three delicate vertical titanium stem rods linking collar to saucer cap.
		for k in 3:
			var a := TAU * float(k) / 3.0
			var rx := cos(a) * 0.135
			var rz := sin(a) * 0.135
			Shapes.beam(u, bp + Vector3(rx * 0.68, 0.63, rz * 0.68), bp + Vector3(rx, 0.89, rz), Vector2(0.011, 0.011))
		# Glowing warm frosted opal-glass globe (`PieceLamps`, house group)!
		lit.surface(c.shade(LAMP_GLOW))
		Shapes.dome(lit, bp + Vector3(0.0, 0.76, 0.0), 0.125, 6, 12, false, -PI * 0.5, PI * 0.5)
		# Register all 6 bollards for stand-in shader lighting & lightmap baking (`bake_lamps: 6`).
		c.lamps.append([bp + Vector3(0.0, 0.82, 0.0), LAMP_GLOW, 0.92])
		_solid(c, bp + Vector3(0.0, 0.48, 0.0), Vector3(0.32, 0.96, 0.32))

	# 2. Twin mid-century circular travertine & titanium tulip lounge side-tables (`x = ±2.45, z = 0.0` — 2.45 m from origin).
	for side: float in [-1.0, 1.0]:
		var tp := Vector3(side * 2.45, 0.0, 0.0)
		u.surface(_titanium(c))
		u.colour = _lin(TITANIUM)
		Shapes.lathe(u, [Vector2(0.21, 0.0), Vector2(0.20, 0.025), Vector2(0.065, 0.08),
				Vector2(0.038, 0.24), Vector2(0.055, 0.41), Vector2(0.18, 0.425)], tp, 14)
		# Circular honed-travertine tabletop (`y = 0.425..0.46`).
		u.surface(c.soft("stone", true))
		u.colour = _lin(TRAVERTINE)
		Shapes.cylinder(u, tp + Vector3(0.0, 0.425, 0.0), 0.34, 0.036, 16)
		# Mid-century lathed ivory-ceramic architectural carafe + champagne-bronze collar & twin tumblers!
		u.surface(c.soft("plastic", true))
		u.colour = _lin(CERAMIC_IVORY)
		var cp := tp + Vector3(-side * 0.08, 0.461, -0.05)
		Shapes.lathe(u, [Vector2(0.062, 0.0), Vector2(0.075, 0.06), Vector2(0.068, 0.14),
				Vector2(0.032, 0.21), Vector2(0.040, 0.25), Vector2(0.034, 0.25)], cp, 12)
		u.surface(_bronze(c))
		u.colour = _lin(BRONZE_GOLD)
		Shapes.lathe(u, [Vector2(0.036, 0.19), Vector2(0.038, 0.215)], cp, 10)
		for tk in 2:
			var gp := tp + Vector3(side * (0.08 + 0.06 * tk), 0.461, 0.08 - 0.10 * tk)
			Shapes.lathe(u, [Vector2(0.030, 0.0), Vector2(0.036, 0.095), Vector2(0.033, 0.095)], gp, 10)
		_solid(c, tp + Vector3(0.0, 0.26, 0.0), Vector3(0.68, 0.52, 0.68))


## Sculpted mid-century molded oiled-cedar & champagne-bronze lounge chair rear shells wrapping every non-folded
## `seats.gd _lounge` chair (`origin.length() >= 0.05`). Seals `_lounge`'s omitted lower-body and arm `RoomMesh.BACK`
## faces cleanly from behind with museum-grade bent-wood cabinetry and zero clipping or z-fighting!
static func _seat_shells(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var u: RoomMesh = c.u
	var slots: Array = Domestic.seat_slots_for(c.builder_params)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(11.0))
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		# Never place shell geometry on the viewer's own folded-away seat at origin (0, 0, 0).
		if xf.origin.length() < 0.05:
			continue
		# 1. Warm oiled-cedar sculpted rear lower cabinet shell spanning seamlessly across the full chair width
		#    (`x in [-0.428, +0.428], y in [0.17, 0.72], z = 0.440`), cleanly closing both arm backs & body back!
		u.surface(c.soft("wood", true))
		u.colour = _lin(CEDAR)
		u.rounded_box(Vector3(0.0, 0.445, 0.442), Vector3(0.858, 0.545, 0.032), 0.014, xf, 1, Vector3i.ZERO, 0.0)
		# Gently reclined molded oiled-cedar upper backrest shell tucked strictly behind `_lounge`'s curved back
		# (local z = +0.118 -> >= 3 cm behind leather rear face, zero z-fighting from any viewing angle!).
		var back_xf := xf * Transform3D(tilt, Vector3(0.0, 0.66, 0.34))
		u.rounded_box(Vector3(0.0, 0.025, 0.118), Vector3(0.858, 0.495, 0.028), 0.013, back_xf, 1,
				Vector3i(2, 0, 0), -0.22)
		# Dark recessed walnut lower kick-trim bar neatly uniting the shell bottom with the splayed walnut legs.
		u.colour = _lin(CEDAR_DARK)
		u.box(xf * Vector3(0.0, 0.175, 0.436), Vector3(0.84, 0.032, 0.036), xf.basis)
		# 2. Razor-slim champagne-bronze architectural horizontal waist inlay strip & corner pins (refined mid-century
		#    craft detail, zero protruding bars!).
		u.surface(_bronze(c))
		u.colour = _lin(BRONZE_GOLD)
		u.box(xf * Vector3(0.0, 0.435, 0.459), Vector3(0.78, 0.014, 0.008), xf.basis)
		for side: float in [-1.0, 1.0]:
			u.box(xf * Vector3(side * 0.37, 0.66, 0.459), Vector3(0.022, 0.022, 0.008), xf.basis)
			u.box(xf * Vector3(side * 0.37, 0.24, 0.459), Vector3(0.022, 0.022, 0.008), xf.basis)


## Aft cantilevered orbital observatory promenade: stepped travertine & cedar-slat monolith wall (`z = +6.05`),
## working modernist orbital wall clock (`PieceClock`), twin backlit orbital-ring schematic placards (`PieceWindows`,
## pure geometry — zero text/marks!), and a floating travertine & cedar credenza bench with indirect cove lighting.
static func _aft_promenade(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var wz := 6.02
	var basis_aft := Basis(Vector3.UP, PI) # local +Z faces world -Z (into terrace)

	# 1. Stepped architectural honed-travertine central monolith (`|x| <= 2.25, h = 3.20`) & flanking warm cedar-slat
	#    wings (`2.25 <= |x| <= 5.75, h = 2.15`) leaving the upper sky wide open behind and overhead!
	s.surface(c.tinted("stone"))
	s.colour = _lin(TRAVERTINE)
	s.box(Vector3(0.0, 1.60, wz), Vector3(4.50, 3.20, 0.34), Basis(), [RoomMesh.DOWN])
	s.colour = _lin(TRAVERTINE_TRIM)
	# Crisp cantilevered top stone coping ledges crowning both the central monolith and flanking wings.
	s.box(Vector3(0.0, 3.24, wz - 0.02), Vector3(4.68, 0.09, 0.44))
	for side: float in [-1.0, 1.0]:
		var wx := side * 4.00
		s.box(Vector3(wx, 2.18, wz - 0.02), Vector3(3.56, 0.08, 0.40))
		s.surface(c.tinted("wood"))
		s.colour = _lin(CEDAR_DARK)
		s.box(Vector3(wx, 1.07, wz + 0.04), Vector3(3.48, 2.14, 0.24), Basis(), [RoomMesh.DOWN])
		# Crisp vertical warm oiled-cedar acoustic slats across both aft promenade wings!
		s.colour = _lin(CEDAR)
		for k in 14:
			var sx := side * lerpf(2.38, 5.62, float(k) / 13.0)
			# Leave clean recess pockets for the twin backlit orbital schematic placards (`|x| ~ 3.95, y = 1.15..1.85`).
			if absf(sx - side * 3.95) < 0.72:
				s.box(Vector3(sx, 0.56, wz - 0.095), Vector3(0.055, 1.12, 0.045), Basis(), [RoomMesh.DOWN])
				s.box(Vector3(sx, 1.98, wz - 0.095), Vector3(0.055, 0.32, 0.045))
			else:
				s.box(Vector3(sx, 1.07, wz - 0.095), Vector3(0.055, 2.12, 0.045), Basis(), [RoomMesh.DOWN])
		s.surface(c.tinted("stone"))
		s.colour = _lin(TRAVERTINE_TRIM)

	# 2. Floating cantilevered honed-travertine & cedar credenza bench along the aft promenade (`z = +5.44`).
	s.surface(c.tinted("iron"))
	s.colour = _lin(SLATE_DARK)
	s.box(Vector3(0.0, 0.14, 5.60), Vector3(7.6, 0.28, 0.56), Basis(), [RoomMesh.DOWN])
	s.surface(c.tinted("wood"))
	s.colour = _lin(CEDAR)
	s.box(Vector3(0.0, 0.44, 5.52), Vector3(8.4, 0.34, 0.72))
	s.surface(c.tinted("stone"))
	s.colour = _lin(TRAVERTINE)
	s.box(Vector3(0.0, 0.65, 5.50), Vector3(8.7, 0.09, 0.80))

	# Sculpted mid-century orbital model sphere on a champagne-bronze cradle + ceramic bowls on the credenza!
	u.surface(_bronze(c))
	u.colour = _lin(BRONZE_GOLD)
	Shapes.arch(u, Vector3(0.0, 0.96, 5.44), 0.17, 0.19, 0.022, 20, basis_aft, 0.0, TAU, ["front", "inner", "outer"])
	Shapes.arch(u, Vector3(0.0, 0.96, 5.44), 0.23, 0.248, 0.018, 20,
			Basis(Vector3.UP, 0.65) * Basis(Vector3.RIGHT, 0.48), 0.0, TAU, ["front", "inner", "outer"])
	Shapes.cylinder(u, Vector3(0.0, 0.695, 5.44), 0.065, 0.075, 10)
	u.surface(c.soft("plastic", true))
	u.colour = _lin(CERAMIC_IVORY)
	for side: float in [-1.0, 1.0]:
		var bp := Vector3(side * 1.45, 0.695, 5.46)
		Shapes.lathe(u, [Vector2(0.11, 0.0), Vector2(0.18, 0.05), Vector2(0.20, 0.12), Vector2(0.16, 0.14)], bp, 14)

	# 3. Working sleek modernist orbital wall clock (`PieceClock`, real system time) centered on the aft monolith!
	var clk_y := 2.28
	var clk_r := 0.30
	var clk_z := wz - 0.185
	u.surface(_titanium(c))
	u.colour = _lin(TITANIUM)
	Shapes.arch(u, Vector3(0.0, clk_y, clk_z), clk_r, clk_r + 0.048, 0.062, 28, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	u.colour = _lin(TITANIUM_SATIN)
	Shapes.arch(u, Vector3(0.0, clk_y, clk_z + 0.015), clk_r + 0.12, clk_r + 0.145, 0.024, 28, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# 12 minimalist mid-century champagne-bronze radial baton indices around the titanium orbital clock ring!
	u.surface(_bronze(c))
	u.colour = _lin(BRONZE_GOLD)
	for k in 12:
		var ang := TAU * float(k) / 12.0
		var card := (k % 3 == 0)
		var r0 := clk_r + 0.044
		var rlen := 0.135 if card else 0.072
		var mr := r0 + rlen * 0.5
		u.box(Vector3(sin(ang) * mr, clk_y + cos(ang) * mr, clk_z - 0.004),
				Vector3(0.024 if card else 0.013, rlen, 0.020), Basis(Vector3.BACK, -ang))
	# Sleek horizontal brushed-titanium architectural speed-wings flanking the clock dial!
	u.surface(_titanium(c))
	u.colour = _lin(TITANIUM)
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var wl := 0.92 - 0.22 * k
			u.box(Vector3(side * (clk_r + 0.22 + wl * 0.5), clk_y + (k - 1) * 0.085, wz - 0.18),
					Vector3(wl, 0.020, 0.024))
	# Register live working clock dial (`PieceClock`, hands updated every second).
	c.clocks.append([Vector3(0.0, clk_y, clk_z - 0.022), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# 4. Twin backlit orbital ring schematic placards (`PieceWindows`, pure architectural geometry — ZERO text/marks!).
	var wins: Array = c.glows.get("window", [])
	var py := 1.48
	var pz := wz - 0.11
	var pw := 1.24
	var ph := 0.64
	for side: float in [-1.0, 1.0]:
		var px := side * 3.95
		# Dark recessed slate housing + brushed-titanium perimeter bezel frame.
		s.surface(c.tinted("iron"))
		s.colour = _lin(SLATE_DARK)
		s.box(Vector3(px, py, pz + 0.01), Vector3(pw + 0.08, ph + 0.08, 0.045))
		u.surface(_titanium(c))
		u.colour = _lin(TITANIUM)
		for vs: float in [-1.0, 1.0]:
			u.box(Vector3(px, py + vs * (ph * 0.5 + 0.024), pz - 0.018), Vector3(pw + 0.096, 0.032, 0.034))
		for hs: float in [-1.0, 1.0]:
			u.box(Vector3(px + hs * (pw * 0.5 + 0.024), py, pz - 0.018), Vector3(0.032, ph + 0.096, 0.034))
		# Illuminated translucent schematic screen quad (`PieceWindows`, facing -Z into the terrace!).
		wins.append([Vector3(px, py, pz - 0.016), Vector3(-pw * 0.5, 0.0, 0.0), Vector3(0.0, ph * 0.5, 0.0),
				Vector3.FORWARD])
		# Crisp 3D geometric orbital schematics floating cleanly 5 mm proud of the backlit face!
		var rz := pz - 0.022
		u.surface(c.soft("plastic", true))
		u.colour = _lin(SLATE_DARK)
		if side < 0.0:
			# Port placard: O'Neill cylinder 3-land / 3-window cross-section diagram + axial hub + sector bars!
			var cx_d := px - 0.24
			for sec in 3:
				var a0 := deg_to_rad(float(sec) * 120.0 + 29.0)
				var a1 := deg_to_rad(float(sec) * 120.0 + 91.0)
				Shapes.arch(u, Vector3(cx_d, py, rz), 0.165, 0.215, 0.008, 10, basis_aft, a0, a1, ["front"])
			Shapes.arch(u, Vector3(cx_d, py, rz), 0.095, 0.112, 0.006, 18, basis_aft, 0.0, TAU, ["front"])
			u.box(Vector3(cx_d, py, rz), Vector3(0.042, 0.042, 0.008))
			# Horizontal grid bar & 5 stepped habitat rotation-gravity telemetry bars on the right half.
			u.box(Vector3(px + 0.28, py, rz), Vector3(0.46, 0.012, 0.006))
			for k in 5:
				var bh := 0.06 + 0.042 * float((k * 2 + 1) % 4)
				u.box(Vector3(px + 0.10 + 0.088 * k, py - 0.16 + bh * 0.5, rz), Vector3(0.048, bh, 0.006))
			u.colour = _lin(AMBER_ACCENT)
			u.box(Vector3(px + 0.28, py + 0.14, rz - 0.002), Vector3(0.36, 0.024, 0.006))
		else:
			# Starboard placard: longitudinal O'Neill cylinder elevation with domed end-caps, 6 ring-ribs, axial spine,
			# twin 45° solar mirror vanes & concentric orbital trajectory arcs (pure geometry, zero text!).
			u.box(Vector3(px, py + 0.08, rz), Vector3(0.68, 0.016, 0.006))
			u.box(Vector3(px, py - 0.14, rz), Vector3(0.68, 0.016, 0.006))
			u.box(Vector3(px, py - 0.03, rz), Vector3(0.88, 0.008, 0.006))
			for k in 6:
				var rx_k := px - 0.32 + 0.128 * k
				u.box(Vector3(rx_k, py - 0.03, rz), Vector3(0.015, 0.22, 0.006))
			# Domed hemispherical cylinder end-cap arcs at port & starboard ends of the elevation silhouette.
			Shapes.arch(u, Vector3(px - 0.34, py - 0.03, rz), 0.102, 0.118, 0.006, 10, basis_aft,
					-PI * 0.5, PI * 0.5, ["front"])
			Shapes.arch(u, Vector3(px + 0.34, py - 0.03, rz), 0.102, 0.118, 0.006, 10, basis_aft,
					PI * 0.5, PI * 1.5, ["front"])
			# Twin angled 45° orbital solar mirror vanes flanking the cylinder ends.
			for es: float in [-1.0, 1.0]:
				u.box(Vector3(px + es * 0.45, py + 0.09, rz), Vector3(0.18, 0.018, 0.006),
						Basis(Vector3.BACK, es * 0.65))
				u.box(Vector3(px + es * 0.45, py - 0.15, rz), Vector3(0.18, 0.018, 0.006),
						Basis(Vector3.BACK, -es * 0.65))
			# Concentric orbital transfer elevation arc + telemetry bars above the cylinder silhouette!
			Shapes.arch(u, Vector3(px, py - 0.18, rz), 0.34, 0.354, 0.006, 16, basis_aft,
					deg_to_rad(52.0), deg_to_rad(128.0), ["front"])
			u.colour = _lin(AMBER_ACCENT)
			u.box(Vector3(px, py + 0.168, rz - 0.002), Vector3(0.034, 0.034, 0.008))
			u.colour = _lin(CYAN_ACCENT)
			for k in 4:
				u.box(Vector3(px - 0.26 + 0.172 * k, py + 0.22, rz - 0.002), Vector3(0.10, 0.020, 0.006))
	c.glows["window"] = wins

	# 5. Indirect cove lighting washing up the aft travertine monolith & under the floating credenza (`PieceCove`).
	cove.surface(c.kit.cove_material())
	var ct := Color(0.96, 0.96, 0.94).srgb_to_linear()
	cove.colour = Color(ct.r, ct.g, ct.b, 0.92)
	# Under-credenza floating shadow wash (`y = 0.24`, facing -Z).
	cove.face([Vector3(-4.15, 0.20, 5.20), Vector3(4.15, 0.20, 5.20),
			Vector3(4.15, 0.27, 5.20), Vector3(-4.15, 0.27, 5.20)], Vector3.FORWARD)
	# Vertical architectural cove reveals framing the stepped travertine monolith edges!
	for side: float in [-1.0, 1.0]:
		var vx := side * 2.27
		cove.face([Vector3(vx - 0.024, 0.72, wz - 0.165), Vector3(vx + 0.024, 0.72, wz - 0.165),
				Vector3(vx + 0.024, 3.16, wz - 0.165), Vector3(vx - 0.024, 3.16, wz - 0.165)], Vector3.FORWARD)
	# Clean physics collision boxes for the aft credenza & stepped promenade wall (strictly >= 5.1 m behind origin).
	_solid(c, Vector3(0.0, 0.35, 5.50), Vector3(8.7, 0.70, 0.80))
	_solid(c, Vector3(0.0, 1.60, wz), Vector3(11.5, 3.20, 0.40))


# --- Colossal O'Neill Cylinder (`ring_cylinder`) ----------------------------------------------------------------------

## Builds the entire rotating O'Neill cylinder interior shell into one opaque custom mesh (`RingCylinder`, 1 draw,
## 0 blend cost): 3 illuminated land-valley strips separated by 3 real geometric open space-window gaps so `SkyDome`
## & `SkyStars` shine straight through, longitudinal window girders, 8 giant circumferential tension rings, secondary
## space-window mullions, domed mountain-ring end-caps with open radial spokes, central axial solar/docking hubs, and
## sweeping structural support arches anchoring the cantilevered terrace into the lower cylinder hull!
static func _cylinder(h: Hall) -> void:
	var v: Verts = h.cyl

	# 1. Three opaque habitat land-valley strips (each 62 deg wide, leaving three 58 deg open space-window gaps!):
	#    strip 0: starboard rising valley [29..91 deg]
	#    strip 1: colossal UPSIDE-DOWN zenith continent [149..211 deg] directly overhead!
	#    strip 2: port rising valley [269..331 deg]
	var strip_ranges: Array = [[29.0, 91.0], [149.0, 211.0], [269.0, 331.0]]
	var u_segs := 16
	var z_segs := 22
	for sid in 3:
		var a0 := deg_to_rad(float(strip_ranges[sid][0]))
		var a1 := deg_to_rad(float(strip_ranges[sid][1]))
		var rows: Array = []
		var norms: Array = []
		var uvs: Array = []
		var cols: Array = []
		for iz in z_segs + 1:
			var fv := float(iz) / z_segs
			var z := lerpf(CYL_FRONT_Z, CYL_BACK_Z, fv)
			var rp := PackedVector3Array()
			var rn := PackedVector3Array()
			var ru := PackedVector2Array()
			var rc := PackedColorArray()
			for iu in u_segs + 1:
				var fu := float(iu) / u_segs
				var th := lerpf(a0, a1, fu)
				# Subtle 3D sculpted mountain rim rising 1.4 m inward along both window-shore borders & ends.
				var edge_m := pow(maxf(0.0, 1.0 - minf(fu, 1.0 - fu) / 0.16), 1.6)
				var end_m := pow(maxf(0.0, 1.0 - minf(fv, 1.0 - fv) / 0.12), 1.6)
				var ridge := maxf(edge_m, end_m)
				var r_here := CYL_RADIUS - 1.35 * ridge
				rp.append(_cyl_pt(th, z, r_here))
				rn.append(_cyl_in_n(th))
				ru.append(Vector2(fu, fv))
				rc.append(Color(1.0, 1.0, 1.0, ridge))
			rows.append(rp)
			norms.append(rn)
			uvs.append(ru)
			cols.append(rc)
		v.grid(rows, norms, uvs, cols, Vector2(0.0, float(sid)))

	# 2. Six monumental longitudinal titanium hull girders framing all 6 land-to-window borders (`kind = 1.0`).
	var girder_col := Color(0.82, 0.86, 0.94, 1.0)
	for deg_val: float in [29.0, 91.0, 149.0, 211.0, 269.0, 331.0]:
		_cyl_long_girder(v, deg_to_rad(deg_val), 1.65, 1.85, CYL_FRONT_Z, CYL_BACK_Z, girder_col)
	# Subtle slender titanium window mullion stringers subdividing the two upper space windows into grand star-bays.
	for deg_val: float in [110.5, 129.5, 230.5, 249.5]:
		_cyl_long_girder(v, deg_to_rad(deg_val), 0.52, 0.62, CYL_FRONT_Z, CYL_BACK_Z, girder_col * 0.82)

	# 3. Eight colossal circumferential structural tension rings sweeping full 360° across land & open star windows!
	var ring_zs: Array[float] = [-94.5, -72.0, -48.0, -24.0, 0.0, 24.0, 48.0, 76.5]
	for rz: float in ring_zs:
		var thick := 2.1 if (absf(rz - CYL_FRONT_Z) < 3.0 or absf(rz - CYL_BACK_Z) < 3.0) else 1.25
		_cyl_hoop_ring(v, rz, CYL_RADIUS - 1.05, CYL_RADIUS + 0.15, thick, 72, girder_col)

	# 4. Forward & aft hemispherical alpine mountain-ring end-caps + open spoke sky ring + luminous axial solar hubs!
	_end_cap(v, CYL_FRONT_Z, -1.0, girder_col)
	_end_cap(v, CYL_BACK_Z, 1.0, girder_col)

	# 5. Sweeping structural megastructure keel arches anchoring our cantilevered terrace into the lower cylinder hull!
	for side: float in [-1.0, 1.0]:
		var th_hull := deg_to_rad(29.0 if side > 0.0 else 331.0)
		for sz: float in [-4.5, 4.5]:
			var p_terrace := Vector3(side * 6.8, -1.05, sz)
			var p_hull := _cyl_pt(th_hull, sz - 2.0, CYL_RADIUS - 0.8)
			_struct_strut(v, p_terrace, p_hull, 0.55, girder_col * 0.9)


## Longitudinal beveled structural hull girder along the cylinder wall (`kind = 1.0`).
static func _cyl_long_girder(v: Verts, theta: float, half_w: float, depth: float, z0: float, z1: float,
		col: Color) -> void:
	var n_in := _cyl_in_n(theta)
	var tang := Vector3(cos(theta), sin(theta), 0.0).normalized()
	var segs := 18
	var p_in := _cyl_pt(theta, 0.0, CYL_RADIUS - depth)
	var p_out := _cyl_pt(theta, 0.0, CYL_RADIUS + 0.1)
	var a_l := PackedVector3Array()
	var a_r := PackedVector3Array()
	var a_n := PackedVector3Array()
	var u_l := PackedVector2Array()
	var u_r := PackedVector2Array()
	var c_row := PackedColorArray()
	for i in segs + 1:
		var fv := float(i) / segs
		var z := lerpf(z0, z1, fv)
		var base_p := Vector3(p_in.x, p_in.y, z)
		a_l.append(base_p - tang * half_w)
		a_r.append(base_p + tang * half_w)
		a_n.append(n_in)
		u_l.append(Vector2(0.0, fv))
		u_r.append(Vector2(1.0, fv))
		c_row.append(col)
	v.grid([a_l, a_r], [a_n, a_n], [u_l, u_r], [c_row, c_row], Vector2(1.0, 0.0))
	# Two flanking bevel cheeks tying the girder cleanly to the cylinder radius.
	for side: float in [-1.0, 1.0]:
		var s_in := PackedVector3Array()
		var s_out := PackedVector3Array()
		var s_n := PackedVector3Array()
		for i in segs + 1:
			var z := lerpf(z0, z1, float(i) / segs)
			s_in.append(Vector3(p_in.x, p_in.y, z) + tang * (side * half_w))
			s_out.append(Vector3(p_out.x, p_out.y, z) + tang * (side * (half_w * 1.15)))
			s_n.append((tang * side + n_in * 0.35).normalized())
		v.grid([s_in, s_out], [s_n, s_n], [u_l, u_r], [c_row, c_row], Vector2(1.0, 0.0))


## Full 360-degree circumferential titanium tension hoop ring (`kind = 1.0`, faces inward & along ±Z).
static func _cyl_hoop_ring(v: Verts, z_mid: float, r_in: float, r_out: float, width_z: float, segs: int,
		col: Color) -> void:
	var hz := width_z * 0.5
	var f0 := PackedVector3Array()
	var f1 := PackedVector3Array()
	var fn := PackedVector3Array()
	var u0 := PackedVector2Array()
	var u1 := PackedVector2Array()
	var cr := PackedColorArray()
	for i in segs + 1:
		var ft := float(i) / segs
		var th := ft * TAU
		f0.append(_cyl_pt(th, z_mid - hz, r_in))
		f1.append(_cyl_pt(th, z_mid + hz, r_in))
		fn.append(_cyl_in_n(th))
		u0.append(Vector2(0.0, ft))
		u1.append(Vector2(1.0, ft))
		cr.append(col)
	v.grid([f0, f1], [fn, fn], [u0, u1], [cr, cr], Vector2(1.0, 0.0))
	# Both axial cheeks of the structural hoop ring so it reads with bold depth from every angle.
	for zs: float in [-1.0, 1.0]:
		var zi := z_mid + zs * hz
		var c_in := PackedVector3Array()
		var c_out := PackedVector3Array()
		var c_n := PackedVector3Array()
		for i in segs + 1:
			var th := TAU * float(i) / segs
			c_in.append(_cyl_pt(th, zi, r_in))
			c_out.append(_cyl_pt(th, zi, r_out))
			c_n.append(Vector3(0.0, 0.0, zs))
		v.grid([c_in, c_out], [c_n, c_n], [u0, u1], [cr, cr], Vector2(1.0, 0.0))


## Hemispherical stepped mountain-ring end-cap + open radial titanium spokes + glowing axial solar/docking hub core!
## dir_out: -1.0 for forward end-cap (`z = CYL_FRONT_Z`), +1.0 for aft end-cap (`z = CYL_BACK_Z`).
static func _end_cap(v: Verts, z_edge: float, dir_out: float, girder_col: Color) -> void:
	var segs := 56
	var rings := 8
	var inward_z := -dir_out

	# 1. Outer annular sculpted alpine mountain-ring curving smoothly from `CYL_RADIUS` inward to `CYL_CAP_INNER_R`
	#    with genuine 3D undulating mountain-ridge relief so peaks catch directional light and cast bold silhouettes!
	var rows: Array = []
	var norms: Array = []
	var uvs: Array = []
	var cols: Array = []
	for ir in rings + 1:
		var fr := float(ir) / rings
		var r_base := lerpf(CYL_RADIUS, CYL_CAP_INNER_R, fr)
		var z_base := z_edge + dir_out * CYL_CAP_BULGE * sin(fr * PI * 0.42)
		var envelope := sin(fr * PI)
		var rp := PackedVector3Array()
		var rn := PackedVector3Array()
		var ru := PackedVector2Array()
		var rc := PackedColorArray()
		for it in segs + 1:
			var ft := float(it) / segs
			var th := ft * TAU
			var ridge_h := (2.6 * sin(th * 9.0 + 0.4) + 1.5 * cos(th * 17.0 - 0.9) + 0.8 * sin(th * 29.0)) * envelope
			var r_here := r_base - ridge_h * 0.42
			var z_here := z_base + inward_z * ridge_h * 0.65
			var n_base := (_cyl_in_n(th) * (1.0 - fr * 0.55) + Vector3(0.0, 0.0, inward_z) * (0.55 + fr * 0.65)).normalized()
			# Tilt normal subtly along the azimuthal ridge slope so crags catch directional sun/starlight!
			var d_th := (2.6 * 9.0 * cos(th * 9.0 + 0.4) - 1.5 * 17.0 * sin(th * 17.0 - 0.9)) * 0.012 * envelope
			var tang := Vector3(cos(th), sin(th), 0.0).normalized()
			var n_sculpt := (n_base - tang * d_th).normalized()
			rp.append(_cyl_pt(th, z_here, r_here))
			rn.append(n_sculpt)
			ru.append(Vector2(fr, ft * 3.0))
			rc.append(Color(1.0, 1.0, 1.0, clampf(lerpf(0.28, 0.95, fr) + ridge_h * 0.04, 0.0, 1.0)))
		rows.append(rp)
		norms.append(rn)
		uvs.append(ru)
		cols.append(rc)
	v.grid(rows, norms, uvs, cols, Vector2(0.35, 1.0 if dir_out < 0.0 else 2.0))

	# 2. Structural titanium collar rings framing the alpine mountain ring + 6 full-length radial megastructure spokes
	#    extending continuously from the outer cylinder hull girders across the mountain ring into the central axial hub!
	var z_mid_ring := z_edge + dir_out * CYL_CAP_BULGE * sin(0.42 * PI)
	_cyl_hoop_ring(v, z_mid_ring, CYL_CAP_INNER_R - 1.2, CYL_CAP_INNER_R + 0.9, 1.7, 56, girder_col)
	var z_hub_rim := z_edge + dir_out * CYL_CAP_BULGE * 0.92
	_cyl_hoop_ring(v, z_hub_rim, CYL_HUB_R - 0.8, CYL_HUB_R + 1.2, 1.8, 36, girder_col)
	for deg_val: float in [29.0, 91.0, 149.0, 211.0, 269.0, 331.0]:
		var th := deg_to_rad(deg_val)
		var p_hull := _cyl_pt(th, z_edge + inward_z * 0.6, CYL_RADIUS - 1.1)
		var p_outer := _cyl_pt(th, z_mid_ring + inward_z * 0.8, CYL_CAP_INNER_R - 0.2)
		var p_inner := _cyl_pt(th, z_hub_rim, CYL_HUB_R)
		_struct_strut(v, p_hull, p_outer, 1.25, girder_col)
		_struct_strut(v, p_outer, p_inner, 1.15, girder_col)

	# 3. Luminous Central Axial Solar/Docking Hub Core (`kind = 2.0`, radius `0 .. CYL_HUB_R`)!
	var h_segs := 32
	var h_rings := 4
	var h_rows: Array = []
	var h_norms: Array = []
	var h_uvs: Array = []
	var h_cols: Array = []
	for ir in h_rings + 1:
		var fr := float(ir) / h_rings
		var r := fr * CYL_HUB_R
		# Subtle gentle dish dome bowing slightly inward at the center axis.
		var z := z_hub_rim + dir_out * (1.0 - fr * fr) * 2.2
		var rp := PackedVector3Array()
		var rn := PackedVector3Array()
		var ru := PackedVector2Array()
		var rc := PackedColorArray()
		for it in h_segs + 1:
			var ft := float(it) / h_segs
			var th := ft * TAU
			rp.append(_cyl_pt(th, z, r))
			rn.append(Vector3(0.0, 0.0, inward_z))
			ru.append(Vector2(fr, ft))
			rc.append(Color.WHITE)
		h_rows.append(rp)
		h_norms.append(rn)
		h_uvs.append(ru)
		h_cols.append(rc)
	v.grid(h_rows, h_norms, h_uvs, h_cols, Vector2(2.0, 0.0))


## Tapered 4-sided structural titanium box beam between two 3D world points (`kind = 1.0`).
static func _struct_strut(v: Verts, a: Vector3, b: Vector3, half_w: float, col: Color) -> void:
	var dir := (b - a).normalized()
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := ref.cross(dir).normalized() * half_w
	var w := dir.cross(u).normalized() * half_w
	var faces: Array = [
		[u + w, -u + w, w.normalized()],
		[-u - w, u - w, -w.normalized()],
		[u - w, u + w, u.normalized()],
		[-u + w, -u - w, -u.normalized()],
	]
	for f: Array in faces:
		var o0: Vector3 = f[0]
		var o1: Vector3 = f[1]
		var nrm: Vector3 = f[2]
		v.quad(a + o0, a + o1, b + o1, b + o0, nrm, col,
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(1.0, 0.0))
