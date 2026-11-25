extends RefCounted

## Snowed-in cabin kit (Cozy retreats: app/environments/snowed_in_cabin.env.json;
## docs/environments/rooms/snowed_in_cabin.md).
## A steep alpine timber A-frame chalet snowed in on a moonlit winter night: heavy chamfered Douglas-fir scissor
## trusses with forged-iron gusset plates & bolts, warm tongue-and-groove timber slopes, wide honey-oak floorboards,
## a hand-loomed woven Nordic wool rug (`nordic_rug`), monumental snow-rimmed mullioned forward gable windows framing
## the cinema screen & opening onto a deep moonlit alpine winter valley (layered snowdrifts, snow-laden evergreen
## spruces, distant jagged alpine ridges, tiny glowing valley cabin), a snow-rimmed port dormer window, a monumental
## starboard river-stone chimney breast & arched hearth with sculpted boulders, rough-hewn timber mantel, charred oak
## logs, live animated dancing flames & embers (`env_screening_glow.gdshader`), wrought-iron fire screen, brass tools,
## steaming copper kettle, firewood alcove, wagon-wheel beam chandelier, low live-edge cedar coffee table with steaming
## cocoa mugs, brass lantern, pinecones & tartan wool throw, aft timber sleeping-loft mezzanine with wooden balustrade
## & slanted attic ladder, heavy chalet entry door, coat rack, wooden alpine skis + poles, and winter bookshelves.
##
## Pieces (pieces.gd dispatches here):
##   cabin_chalet  A-frame timber shell, honey-oak floor, woven nordic_rug, scissor trusses with iron gussets,
##                 monumental forward gable window wall & timber screen hood, exterior sill snow pillows, port dormer
##                 window & winter bookcases, forged-iron wagon-wheel chandelier, low live-edge cedar coffee table
##                 with steaming mugs/lantern/pinecones/tartan throw, aft sleeping-loft mezzanine with balustrade &
##                 ladder, heavy entry door, coat rack, wooden alpine skis & poles, beam cove uplights (`PieceCove`),
##                 and the moonlit alpine winter valley outside (`AlpineOutside`, `env_ice_outside.gdshader`).
##   cabin_hearth  Monumental starboard river-stone chimney breast & arched firebox (`x = +3.85, z = -2.75`), sculpted
##                 river-stone courses & arch voussoirs, rough-hewn cedar mantel with pinecone-evergreen garland &
##                 brass lantern, charred split-oak logs over glowing embers, live dancing fire flames (`HearthGlow`,
##                 `env_screening_glow.gdshader`), wrought-iron fire screen, brass fireside tool stand, steaming copper
##                 kettle on cast-iron trivet, recessed firewood log alcove, and soft warm hearth glow cone & steam
##                 wisps (`HearthShaft`, `env_world_shaft.gdshader`).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const OUTSIDE_SHADER := preload("res://shaders/env_ice_outside.gdshader")
const GLOW_SHADER := preload("res://shaders/env_screening_glow.gdshader")
const SHAFT_SHADER := preload("res://shaders/env_world_shaft.gdshader")

## A-frame chalet interior dimensions (exact 45-degree roof pitch: roof_y(x) = RIDGE_Y - absf(x)).
const HW := 5.80
const FZ := -8.20
const BZ := 5.60
const KNEE_Y := 1.15
const RIDGE_Y := 6.95
const FLOOR_Y := 0.0

## Structural A-frame scissor-truss Z stations (leaves a 4.40 m grand hearth & dormer bay at z = -4.95..-0.55).
const TRUSS_ZS: Array[float] = [-7.95, -4.95, -0.55, 2.55, 5.40]

## Cinema screen geometry (matches app/environments/snowed_in_cabin.env.json).
const SCREEN_C := Vector3(0.0, 2.35, -7.40)
const SCREEN_W := 4.80
const SCREEN_H := 2.70

## Monumental starboard river-stone hearth coordinates.
const HEARTH_FACE_X := 3.85
const HEARTH_Z := -2.75
const HEARTH_W := 2.20
const HEARTH_APRON_Y := 0.18
const HEARTH_APRON_X0 := 3.05
const MANTEL_Y := 1.68

## Port A-frame dormer window bay (fits cleanly inside bay 2 between z = -4.95 and -0.55).
const DORMER_Z0 := -4.55
const DORMER_Z1 := -2.35
const DORMER_SILL_Y := 0.72
const DORMER_TOP_Y := 2.82

## Aft timber sleeping-loft mezzanine coordinates.
const LOFT_Z0 := 3.05
const LOFT_Y := 2.65

## Low live-edge cedar coffee table (strictly y <= 0.44 m so every seat's sight line stays 100% clear).
const TABLE_C := Vector3(0.0, 0.0, -1.48)
const TABLE_TOP_Y := 0.40

## Slow sub-3 Hz fire flicker frequencies (photosensitivity ceiling: every frequency < 3 Hz).
const FLICKER_HZ: Array[float] = [0.37, 0.79, 1.27, 2.11]

## Warm alpine timber, river-stone, leather, iron, brass, copper & snow palette (sRGB; meshes receive linear).
const FIR_TIMBER := Color(0.54, 0.34, 0.19)
const FIR_DARK := Color(0.32, 0.19, 0.105)
const FIR_WARM := Color(0.66, 0.44, 0.25)
const CEIL_PLANK := Color(0.58, 0.38, 0.22)
const FLOOR_OAK := Color(0.46, 0.29, 0.16)
const CEDAR_LIVE := Color(0.56, 0.28, 0.15)
const BARK_DARK := Color(0.20, 0.12, 0.08)
const LOG_END := Color(0.76, 0.60, 0.40)
const CHARRED_LOG := Color(0.10, 0.075, 0.06)
const MULLION_DARK := Color(0.18, 0.12, 0.085)
const IRON := Color(0.10, 0.10, 0.11)
const IRON_BACK := Color(0.04, 0.04, 0.045)
const STONE_BASE := Color(0.42, 0.41, 0.39)
const STONE_MORTAR := Color(0.24, 0.23, 0.22)
const HEARTH_SLATE := Color(0.30, 0.31, 0.33)
const SOOT := Color(0.07, 0.06, 0.055)
const BRASS := Color(0.88, 0.70, 0.34)
const COPPER := Color(0.84, 0.42, 0.22)
const SNOW_SILL := Color(0.88, 0.92, 0.98)
const SPRUCE_GARLAND := Color(0.11, 0.24, 0.14)
const PINECONE := Color(0.34, 0.20, 0.11)
const CREAM_MUG := Color(0.90, 0.86, 0.78)
const SPRUCE_MUG := Color(0.16, 0.34, 0.27)
const COCOA := Color(0.16, 0.075, 0.04)
const QUILT_CREAM := Color(0.86, 0.82, 0.74)
const QUILT_CRIMSON := Color(0.56, 0.14, 0.14)
const SCARF_OCHRE := Color(0.76, 0.48, 0.16)
const SKI_HICKORY := Color(0.68, 0.46, 0.24)
const SKI_STRIPE := Color(0.64, 0.14, 0.12)
const LAMP_WARM := Color(1.0, 0.80, 0.48)
const FIRE_LIGHT := Color(1.0, 0.56, 0.20)
const MOON_FILL := Color(0.52, 0.68, 0.96)

## Exterior alpine valley palette (linear for env_ice_outside.gdshader).
const OUT_SNOW := Color(0.88, 0.92, 0.99)
const OUT_SNOW_SHADE := Color(0.56, 0.68, 0.86)
const OUT_NEEDLES := Color(0.016, 0.056, 0.036)
const OUT_ROCK := Color(0.14, 0.19, 0.28)
const OUT_TRUNK := Color(0.045, 0.032, 0.022)
const OUT_CABIN_WOOD := Color(0.18, 0.07, 0.04)
const OUT_CABIN_WIN := Color(1.0, 0.60, 0.22)


## Hall owning the cabin's custom meshes (AlpineOutside, HearthGlow, HearthShaft) and live frame updates
## (moonlight outside, animated hearth flames & embers, dynamic hearth stand-in lamp brightness, steam wisps).
class Hall:
	var kit: Node
	var outside := RoomMesh.new()
	var glow := Verts.new()
	var shaft := Verts.new()

	var outside_m: ShaderMaterial
	var glow_m: ShaderMaterial
	var shaft_m: ShaderMaterial

	var outside_mi: MeshInstance3D
	var glow_mi: MeshInstance3D
	var shaft_mi: MeshInstance3D
	var accent_lamp_m: Material

	var sky: Node
	var hearth_lamp_low := -1
	var hearth_lamp_high := -1
	var last_lamp_level := -1.0
	var lamp_wait := 0.0

	var flame_clock := 0.0
	var shaft_clock := 0.0
	var flicker_t := 0.0
	var fire_level := 1.0
	var shaft_level := 0.24

	func finish(k: Node) -> void:
		var noise := SkySys.noise_texture()
		var caustics := Procedural.caustic_map()

		if outside.triangle_count() > 0:
			outside_mi = k._add_unbaked("AlpineOutside", outside)
			outside_mi.material_override = outside_m
			outside_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			outside_mi.extra_cull_margin = 200.0

		if glow.count() > 0:
			glow_m = ShaderMaterial.new()
			glow_m.shader = GLOW_SHADER
			glow_m.set_shader_parameter("noise_map", noise)
			glow_m.set_shader_parameter("caustic_map", caustics)
			glow_m.set_shader_parameter("pool_level", 0.0)
			glow_m.set_shader_parameter("city_level", 0.0)
			glow_m.set_shader_parameter("fire_level", 1.0)
			glow_mi = k._add_mesh("HearthGlow", glow.commit(glow_m))
			glow_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			glow_mi.add_to_group("env_see_through")

		if shaft.count() > 0:
			shaft_m = ShaderMaterial.new()
			shaft_m.shader = SHAFT_SHADER
			shaft_m.set_shader_parameter("noise_map", noise)
			shaft_m.set_shader_parameter("shaft_colour", Color(1.0, 0.94, 0.86))
			shaft_m.set_shader_parameter("shaft_level", 0.24)
			shaft_m.set_shader_parameter("edge_softness", 2.15)
			shaft_m.set_shader_parameter("wisp_strength", 0.42)
			shaft_mi = k._add_mesh("HearthShaft", shaft.commit(shaft_m))
			shaft_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			shaft_mi.add_to_group("env_see_through")

		# Tune PieceGlass to crisp alpine winter panes with subtle frosty rim.
		for n: Node in k.owned():
			if n is MeshInstance3D and str(n.name).begins_with("PieceGlass"):
				var gm := (n as MeshInstance3D).material_override as ShaderMaterial
				if gm != null:
					gm.set_shader_parameter("alpha", 0.09)
					gm.set_shader_parameter("rim", 0.30)

		for s: Node in k.host.systems_of_kind("sky"):
			if s.has_method("sky_light"):
				sky = s
				break

		tick(0.0)

	func tick(delta: float) -> void:
		var host: Node = kit.host
		var motion := float(kit.params.get("water_motion", 1.0))
		flame_clock += delta * (0.25 + 0.75 * motion)
		shaft_clock += delta * motion
		flicker_t += delta

		# 1. Sync moonlit alpine exterior terrain/spruces/ridges with live sky & Moon direction.
		if outside_m != null and kit != null and kit.room.is_inside_tree():
			var basis: Basis = kit.room.global_transform.basis
			var zenith := Color(0.02, 0.035, 0.075)
			var horizon := Color(0.06, 0.09, 0.16)
			var moon := Vector3(-0.28, 0.37, -0.88).normalized()
			var moon_level := 0.92
			if sky != null and is_instance_valid(sky):
				var l: Dictionary = sky.call("sky_light")
				zenith = l["zenith"]
				horizon = l["horizon"]
				var md: Vector3 = sky.call("moon_direction")
				if md != Vector3.ZERO:
					moon = md
					moon_level = float(sky.params.get("moon", 0.92))
			outside_m.set_shader_parameter("sky_top", zenith)
			outside_m.set_shader_parameter("sky_low", horizon)
			outside_m.set_shader_parameter("moon_dir", (basis * moon).normalized())
			outside_m.set_shader_parameter("moon_light", Vector3(0.58, 0.68, 0.88) * moon_level)
			outside_m.set_shader_parameter("aurora_light", Vector3.ZERO)

		# 2. Hearth fire flames & embers: follow accent (bound to setting.hearth) + slow sub-3 Hz flicker.
		var steady: bool = host != null and host.has_method("setting") and host.setting("flicker") == false
		var w := 0.0
		if not steady:
			for i in FLICKER_HZ.size():
				w += sin(TAU * FLICKER_HZ[i] * flicker_t + 1.05 * (i + 1)) / float(i + 1)
		var hearth_mode := str(host.setting("hearth")) if (host != null and host.has_method("setting")) else "roaring"
		var accent: float = kit._group_level("accent")
		var flk := float(kit.params.get("flicker", 0.0))
		fire_level = maxf(0.0, accent * (1.0 + 0.11 * flk * w))
		if glow_m != null:
			glow_m.set_shader_parameter("flame_clock", flame_clock)
			glow_m.set_shader_parameter("fire_level", fire_level)
		if glow_mi != null:
			glow_mi.visible = fire_level > 0.005
			glow_mi.set_meta("fire_level", fire_level)
			glow_mi.set_meta("hearth_mode", hearth_mode)

		# 3. Soft hearth glow cone onto the Nordic rug & subtle kettle/cocoa steam wisps.
		shaft_level = 0.22 * clampf(0.35 + 0.75 * fire_level, 0.0, 1.35)
		if shaft_m != null:
			shaft_m.set_shader_parameter("clock", shaft_clock)
			shaft_m.set_shader_parameter("shaft_level", shaft_level)
		if shaft_mi != null:
			shaft_mi.visible = shaft_level > 0.004
			shaft_mi.set_meta("shaft_level", shaft_level)
			shaft_mi.set_meta("clock", shaft_clock)

		# 4. Update the two hearth stand-in lamps smoothly when fire level shifts (at most ~8 Hz).
		lamp_wait -= delta
		if (hearth_lamp_low >= 0 or hearth_lamp_high >= 0) and (lamp_wait <= 0.0 or delta == 0.0):
			if absf(fire_level - last_lamp_level) > 0.015 or delta == 0.0:
				lamp_wait = 0.12
				last_lamp_level = fire_level
				var e_lo := FIRE_LIGHT * (3.1 * fire_level)
				var e_hi := FIRE_LIGHT * (1.75 * fire_level)
				if hearth_lamp_low >= 0:
					kit._light.set_lamp(hearth_lamp_low, e_lo)
				if hearth_lamp_high >= 0:
					kit._light.set_lamp(hearth_lamp_high, e_hi)


## Compact indexed mesh builder for HearthGlow and HearthShaft.
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

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, cols: Variant, kind := 0.0,
			uvs: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]) -> void:
		var cs: Array = cols if cols is Array else [cols, cols, cols, cols]
		var k0 := vert(a, nrm, cs[0], uvs[0], kind)
		vert(b, nrm, cs[1], uvs[1], kind)
		vert(cc, nrm, cs[2], uvs[2], kind)
		vert(d, nrm, cs[3], uvs[3], kind)
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			idx.append_array([k0, k0 + 2, k0 + 1, k0, k0 + 3, k0 + 2])
		else:
			idx.append_array([k0, k0 + 1, k0 + 2, k0, k0 + 2, k0 + 3])

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

	func cone(top: Vector3, bot: Vector3, r_top: float, r_bot: float, sides: int, col_top: Color,
			col_bot: Color) -> void:
		var axis := (bot - top).normalized()
		var hint := Vector3.UP if absf(axis.y) < 0.92 else Vector3.FORWARD
		var sx := axis.cross(hint).normalized()
		var sz := sx.cross(axis).normalized()
		var slope_len := top.distance_to(bot)
		var dr := r_bot - r_top
		var base := v.size()
		for j in 2:
			var fy := float(j)
			var ctr := top.lerp(bot, fy)
			var rad := lerpf(r_top, r_bot, fy)
			var col := col_top if j == 0 else col_bot
			for i in sides + 1:
				var a := TAU * float(i) / float(sides)
				var radial := sx * cos(a) + sz * sin(a)
				var nrm := (radial * slope_len - axis * dr).normalized()
				vert(ctr + radial * rad, nrm, col, Vector2(float(i) / float(sides), fy), 0.0)
		var row := sides + 1
		for i in sides:
			var a := base + i
			var b := base + i + 1
			var cc := base + row + i + 1
			var d := base + row + i
			idx.append_array([a, cc, b, a, d, cc])

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
	# Keep static lightmap atlas compact (<= 1024 x 1024) and build speed crisp (< 1.5 pace units).
	c.s.texel = maxf(float(c.s.texel), 0.22)
	var h := _hall(c)
	match piece:
		"cabin_chalet":
			_chalet(c, h)
		"cabin_hearth":
			_hearth(c, h)
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove, c.glass]:
		b.colour = Color.WHITE


static func _hall(c: Object) -> Hall:
	for obj: Object in c.halls:
		if obj is Hall:
			return obj
	var h := Hall.new()
	h.kit = c.kit
	c.halls.append(h)
	return h


# --- Shared helpers ---------------------------------------------------------------------------------------------------

static func _lin(col: Color, alpha := 1.0) -> Color:
	var l := col.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _roof_y(x: float) -> float:
	return RIDGE_Y - absf(x)


static func _metal(c: Object) -> Material:
	return c.shiny("gilt", 1.0, 0.72, 0.22)


static func _ceramic(c: Object) -> Material:
	return c.shiny("cloth", 0.0, 0.36, 0.14)


static func _accent_lamp(c: Object, h: Hall) -> Material:
	if h.accent_lamp_m == null:
		h.accent_lamp_m = c.kit._lamp(Color(1.0, 0.70, 0.34), 1.35, 0.0, "accent")
	return h.accent_lamp_m


static func _solid(c: Object, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, basis))


static func _radial(g: Verts, centre: Vector3, u: Vector3, v: Vector3, n: Vector3, colour: Color,
		strength: float) -> void:
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
			var k := pow(clampf(1.0 - r, 0.0, 1.0), 1.65)
			row.append(centre + u * a + v * b)
			nrow.append(n)
			var col := colour
			col.a = k * strength
			crow.append(col)
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	g.grid(rows, norms, cols, 2.0)


static func _tube(b: RoomMesh, pts: Array[Vector3], rx: float, ry: float, sides := 8,
		side_hint := Vector3.UP) -> void:
	if pts.size() < 2:
		return
	var rings: Array = []
	var nrings: Array = []
	for i in pts.size():
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		var s1 := side_hint.cross(t)
		if s1.length() < 0.01:
			s1 = Vector3.RIGHT.cross(t)
		s1 = s1.normalized()
		var s2 := t.cross(s1).normalized()
		var ring := PackedVector3Array()
		var nring := PackedVector3Array()
		for k in sides + 1:
			var a := TAU * float(k % sides) / float(sides)
			var ca := cos(a)
			var sa := sin(a)
			ring.append(pts[i] + s1 * (ca * rx) + s2 * (sa * ry))
			nring.append((s1 * (ca / maxf(rx, 0.001)) + s2 * (sa / maxf(ry, 0.001))).normalized())
		rings.append(ring)
		nrings.append(nring)
	for i in pts.size() - 1:
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		var n0: PackedVector3Array = nrings[i]
		var n1: PackedVector3Array = nrings[i + 1]
		var nmid := PackedVector3Array()
		for k in sides + 1:
			nmid.append((n0[k] + n1[k]).normalized())
		b.strip(r0, r1, nmid)


# ======================================================================================================================
# Piece 1: cabin_chalet — Steep Alpine Timber A-Frame Chalet & Moonlit Winter Valley
# ======================================================================================================================

static func _chalet(c: Object, h: Hall) -> void:
	_floor_and_rug(c)
	_aframe_shell_and_dormer(c)
	_scissor_trusses(c)
	_forward_gable_and_screen(c)
	_aft_wall_loft_and_entry(c)
	_chandelier(c)
	_coffee_table(c, h)
	_side_bookcases_and_skis(c)
	_chalet_lights(c)
	_alpine_outside(h)


## Wide honey-oak plank floorboards, knee-wall baseboards, and the cozy hand-loomed woven `nordic_rug` laid flat
## beneath both chalet sofas, the cedar coffee table, and the hearth apron.
static func _floor_and_rug(c: Object) -> void:
	var s: RoomMesh = c.s
	var wood: Material = c.tinted("wood")
	var rug_mat: Material = c.tinted("fabric", "nordic_rug")

	# Main honey-oak plank floorboard deck (slightly oversized under walls so zero light leaks at baseboards).
	s.surface(wood)
	s.colour = _lin(FLOOR_OAK)
	s.face([
		Vector3(-HW - 0.15, FLOOR_Y, FZ - 0.15),
		Vector3(HW + 0.15, FLOOR_Y, FZ - 0.15),
		Vector3(HW + 0.15, FLOOR_Y, BZ + 0.15),
		Vector3(-HW - 0.15, FLOOR_Y, BZ + 0.15),
	], Vector3.UP)

	# Heavy dark-fir baseboards lining left, right and aft perimeter walls.
	s.colour = _lin(FIR_DARK)
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(sd * (HW - 0.02), 0.075, (FZ + BZ) * 0.5), Vector3(0.04, 0.15, BZ - FZ), Basis(),
				[RoomMesh.DOWN, RoomMesh.RIGHT if sd > 0.0 else RoomMesh.LEFT])
	s.box(Vector3(0.0, 0.075, BZ - 0.02), Vector3(HW * 2.0, 0.15, 0.04), Basis(), [RoomMesh.DOWN, RoomMesh.BACK])

	# Cozy woven Nordic wool rug (`nordic_rug`: cream oatmeal yarn with crimson, spruce & ochre diamond bands).
	var rx0 := -2.50
	var rx1 := 3.15
	var rz0 := -3.55
	var rz1 := 2.85
	var rcx := (rx0 + rx1) * 0.5
	var rcz := (rz0 + rz1) * 0.5
	var rw := rx1 - rx0
	var rd := rz1 - rz0
	var rug_y := 0.012

	# Bevelled woven spruce wool border pad underneath (0.010 m high; skip UP so zero Z-fighting with patterned top).
	s.surface(c.tinted("cloth"))
	s.colour = _lin(Color(0.14, 0.24, 0.19))
	s.box(Vector3(rcx, 0.005, rcz), Vector3(rw + 0.12, 0.010, rd + 0.12), Basis(), [RoomMesh.DOWN, RoomMesh.UP])
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(rcx, 0.0055, rcz + sd * (rd * 0.5 + 0.03)), Vector3(rw + 0.12, 0.011, 0.06), Basis(),
				[RoomMesh.DOWN])
		s.box(Vector3(rcx + sd * (rw * 0.5 + 0.03), 0.0055, rcz), Vector3(0.06, 0.011, rd), Basis(), [RoomMesh.DOWN])

	# Patterned hand-loomed `nordic_rug` field lying flat at y = 0.012 m.
	s.surface(rug_mat)
	s.colour = _lin(Color(0.70, 0.65, 0.58))
	s.face([
		Vector3(rx0, rug_y, rz0),
		Vector3(rx1, rug_y, rz0),
		Vector3(rx1, rug_y, rz1),
		Vector3(rx0, rug_y, rz1),
	], Vector3.UP)

	# Cream wool fringe tassels along front & back rug ends (in PieceSoft so zero lightmap texel waste).
	var u: RoomMesh = c.u
	u.surface(c.soft("cloth"))
	u.colour = _lin(QUILT_CREAM * 0.88)
	for ez: float in [rz0 - 0.085, rz1 + 0.085]:
		for k in 28:
			var tx := lerpf(rx0 + 0.08, rx1 - 0.08, float(k) / 27.0)
			u.box(Vector3(tx, 0.004, ez), Vector3(0.045, 0.006, 0.08), Basis(), [RoomMesh.DOWN])


## Steep 45-degree tongue-and-groove alpine A-frame timber slopes, sturdy side knee walls, continuous ridge beam,
## horizontal purlins, and the frost-rimmed port dormer window bay looking out into snowy spruces.
static func _aframe_shell_and_dormer(c: Object) -> void:
	var s: RoomMesh = c.s
	var wood: Material = c.tinted("wood")
	var dark_mull := _lin(MULLION_DARK)

	# 1. Side knee walls (y = 0.0..KNEE_Y at x = +-HW). Left knee wall has an opening under the port dormer window.
	s.surface(wood)
	s.colour = _lin(FIR_TIMBER * 0.84)
	# Starboard full knee wall.
	Shapes.wall(s, Vector3(HW, 0.0, BZ), Vector3.FORWARD, Vector3.LEFT, BZ - FZ, KNEE_Y)
	# Port knee wall (solid below dormer sill y = DORMER_SILL_Y inside DORMER_Z0..Z1).
	var d_hole := Rect2(DORMER_Z0 - FZ, DORMER_SILL_Y, DORMER_Z1 - DORMER_Z0, KNEE_Y - DORMER_SILL_Y + 0.05)
	Shapes.wall(s, Vector3(-HW, 0.0, FZ), Vector3.BACK, Vector3.RIGHT, BZ - FZ, KNEE_Y, [d_hole])
	# Horizontal knee-wall timber cap moulding along both sides.
	s.colour = _lin(FIR_DARK)
	s.box(Vector3(HW - 0.06, KNEE_Y, (FZ + BZ) * 0.5), Vector3(0.14, 0.10, BZ - FZ))
	s.box(Vector3(-HW + 0.06, KNEE_Y, (FZ + DORMER_Z0) * 0.5), Vector3(0.14, 0.10, DORMER_Z0 - FZ))
	s.box(Vector3(-HW + 0.06, KNEE_Y, (DORMER_Z1 + BZ) * 0.5), Vector3(0.14, 0.10, BZ - DORMER_Z1))

	# 2. Steep 45-degree tongue-and-groove ceiling slopes (inward normals).
	var n_right := Vector3(-1.0, -1.0, 0.0).normalized()
	var n_left := Vector3(1.0, -1.0, 0.0).normalized()
	s.colour = _lin(CEIL_PLANK)
	# Full starboard roof slope (from ridge x = 0, y = RIDGE_Y down to x = +HW, y = KNEE_Y).
	s.face([
		Vector3(0.0, RIDGE_Y, FZ),
		Vector3(HW, KNEE_Y, FZ),
		Vector3(HW, KNEE_Y, BZ),
		Vector3(0.0, RIDGE_Y, BZ),
	], n_right)
	# Port roof slope split cleanly around the dormer opening (z = DORMER_Z0..DORMER_Z1, y = KNEE_Y..DORMER_TOP_Y).
	var dx_top := RIDGE_Y - DORMER_TOP_Y # 4.13 m from centre -> x = -4.13 m
	# Forward port slope strip (FZ .. DORMER_Z0).
	s.face([
		Vector3(-HW, KNEE_Y, FZ),
		Vector3(0.0, RIDGE_Y, FZ),
		Vector3(0.0, RIDGE_Y, DORMER_Z0),
		Vector3(-HW, KNEE_Y, DORMER_Z0),
	], n_left)
	# Aft port slope strip (DORMER_Z1 .. BZ).
	s.face([
		Vector3(-HW, KNEE_Y, DORMER_Z1),
		Vector3(0.0, RIDGE_Y, DORMER_Z1),
		Vector3(0.0, RIDGE_Y, BZ),
		Vector3(-HW, KNEE_Y, BZ),
	], n_left)
	# Upper port slope strip above the dormer ceiling (x = -dx_top .. 0.0, z = DORMER_Z0 .. DORMER_Z1).
	s.face([
		Vector3(-dx_top, DORMER_TOP_Y, DORMER_Z0),
		Vector3(0.0, RIDGE_Y, DORMER_Z0),
		Vector3(0.0, RIDGE_Y, DORMER_Z1),
		Vector3(-dx_top, DORMER_TOP_Y, DORMER_Z1),
	], n_left)

	# 3. Heavy central timber ridge beam & longitudinal roof purlins (strong architectural rhythm along the slopes).
	s.colour = _lin(FIR_DARK)
	s.box(Vector3(0.0, RIDGE_Y - 0.16, (FZ + BZ) * 0.5), Vector3(0.26, 0.34, BZ - FZ))
	for px: float in [1.85, 3.65]:
		var py := _roof_y(px)
		for sd: float in [-1.0, 1.0]:
			var tilt := Basis(Vector3.BACK, sd * PI * 0.25)
			if sd < 0.0 and px > 3.5:
				# Break lower port purlin cleanly around the dormer window bay.
				s.box(Vector3(-px + 0.06, py - 0.06, (FZ + DORMER_Z0) * 0.5), Vector3(0.12, 0.16, DORMER_Z0 - FZ), tilt)
				s.box(Vector3(-px + 0.06, py - 0.06, (DORMER_Z1 + BZ) * 0.5), Vector3(0.12, 0.16, BZ - DORMER_Z1), tilt)
			else:
				s.box(Vector3(sd * (px - 0.06), py - 0.06, (FZ + BZ) * 0.5), Vector3(0.12, 0.16, BZ - FZ), tilt)

	# 4. Port dormer window box (`z = DORMER_Z0..DORMER_Z1`, vertical glass at `x = -HW`, looking at snowy pines!).
	var dw := DORMER_Z1 - DORMER_Z0
	var dzc := (DORMER_Z0 + DORMER_Z1) * 0.5
	s.colour = _lin(CEIL_PLANK * 0.90)
	# Flat timber dormer ceiling from x = -HW to -dx_top at y = DORMER_TOP_Y.
	s.face([
		Vector3(-HW, DORMER_TOP_Y, DORMER_Z0),
		Vector3(-dx_top, DORMER_TOP_Y, DORMER_Z0),
		Vector3(-dx_top, DORMER_TOP_Y, DORMER_Z1),
		Vector3(-HW, DORMER_TOP_Y, DORMER_Z1),
	], Vector3.DOWN)
	# Two triangular dormer cheek walls sealing the sides airtight from y = KNEE_Y to DORMER_TOP_Y.
	s.colour = _lin(FIR_TIMBER * 0.86)
	s.face([
		Vector3(-HW, KNEE_Y, DORMER_Z0),
		Vector3(-dx_top, DORMER_TOP_Y, DORMER_Z0),
		Vector3(-HW, DORMER_TOP_Y, DORMER_Z0),
	], Vector3.BACK)
	s.face([
		Vector3(-HW, KNEE_Y, DORMER_Z1),
		Vector3(-HW, DORMER_TOP_Y, DORMER_Z1),
		Vector3(-dx_top, DORMER_TOP_Y, DORMER_Z1),
	], Vector3.FORWARD)
	# Dark-timber dormer window sill, head, jambs, central mullion & transom.
	s.colour = dark_mull
	s.box(Vector3(-HW + 0.04, DORMER_SILL_Y - 0.04, dzc), Vector3(0.24, 0.08, dw + 0.14))
	s.box(Vector3(-HW + 0.03, DORMER_TOP_Y - 0.05, dzc), Vector3(0.18, 0.10, dw + 0.10))
	for dz: float in [DORMER_Z0 + 0.05, dzc, DORMER_Z1 - 0.05]:
		s.box(Vector3(-HW + 0.03, (DORMER_SILL_Y + DORMER_TOP_Y) * 0.5, dz),
				Vector3(0.14, DORMER_TOP_Y - DORMER_SILL_Y, 0.09))
	s.box(Vector3(-HW + 0.03, 1.82, dzc), Vector3(0.10, 0.07, dw))
	# Dormer glass pane (`PieceGlass`, facing +X into the cabin).
	c.glass.surface(c.kit.GLASS)
	Shapes.quad(c.glass, Vector3(-HW - 0.02, (DORMER_SILL_Y + DORMER_TOP_Y) * 0.5, dzc),
			Vector3(0.0, 0.0, dw * 0.49), Vector3(0.0, (DORMER_TOP_Y - DORMER_SILL_Y) * 0.49, 0.0), Vector3.RIGHT)
	# Exterior snow pillows piled along the outer port dormer sill & mid-transom!
	_snow_ledge(c, Vector3(-HW - 0.14, DORMER_SILL_Y + 0.04, dzc), Vector3(0.22, 0.13, dw - 0.06))
	_snow_ledge(c, Vector3(-HW - 0.09, 1.89, dzc), Vector3(0.12, 0.08, dw - 0.10))


## Five monumental Douglas-fir A-frame scissor trusses with forged-iron gusset plates, bolts, king posts, and
## recessed warm fairy-amber/frost-blue beam uplights (`PieceCove`).
static func _scissor_trusses(c: Object) -> void:
	var s: RoomMesh = c.s
	var wood: Material = c.tinted("wood")
	var iron: Material = c.tinted("iron")
	var cove_m: Material = c.kit.cove_material()

	for i in TRUSS_ZS.size():
		var tz := TRUSS_ZS[i]
		var interior := (i > 0 and i < TRUSS_ZS.size() - 1)
		s.surface(wood)
		s.colour = _lin(FIR_TIMBER * (0.94 if interior else 0.82))

		# Principal 45-degree rafters & knee-wall posts on both flanks.
		for sd: float in [-1.0, 1.0]:
			s.box(Vector3(sd * (HW - 0.12), KNEE_Y * 0.5, tz), Vector3(0.24, KNEE_Y, 0.22), Basis(), [RoomMesh.DOWN])
			var bot := Vector3(sd * (HW - 0.12), KNEE_Y + 0.02, tz)
			var top := Vector3(0.0, RIDGE_Y - 0.14, tz)
			Shapes.beam(s, bot, top, Vector2(0.22, 0.28))

		if not interior:
			continue

		# Dramatic alpine scissor-truss collar tie (`y = 4.58 m`, well above screen sight lines!), diagonal scissor
		# struts (`(+-3.52, 3.35) -> (0.0, 5.45)`), and central vertical king post (`y = 4.58..6.78 m`).
		var collar_y := 4.58
		var collar_hw := RIDGE_Y - collar_y - 0.12 # ~2.25 m
		s.colour = _lin(FIR_WARM * 0.90)
		s.box(Vector3(0.0, collar_y, tz), Vector3(collar_hw * 2.0, 0.24, 0.22))
		s.box(Vector3(0.0, (collar_y + RIDGE_Y - 0.16) * 0.5, tz), Vector3(0.20, RIDGE_Y - 0.16 - collar_y, 0.20))
		for sd: float in [-1.0, 1.0]:
			Shapes.beam(s, Vector3(sd * 3.45, 3.40, tz), Vector3(0.0, 5.42, tz), Vector2(0.16, 0.18))
			# Timber knee corbel braces anchoring knee post into rafter.
			Shapes.beam(s, Vector3(sd * (HW - 0.14), 0.72, tz), Vector3(sd * (HW - 0.72), 1.65, tz), Vector2(0.14, 0.16))

		# Sleek forged-iron gusset strap plates & bolt heads (reflective gunmetal iron catching warm firelight,
		# hugging the timber cleanly without bulky black silhouettes!).
		var u: RoomMesh = c.u
		u.surface(_metal(c))
		u.colour = _lin(Color(0.24, 0.23, 0.24))
		# Central collar-to-king-post slim iron strap T-plates (front & back faces of the truss).
		for fz_s: float in [-0.118, 0.118]:
			u.box(Vector3(0.0, collar_y, tz + fz_s), Vector3(0.44, 0.18, 0.018))
			u.box(Vector3(0.0, collar_y + 0.16, tz + fz_s), Vector3(0.16, 0.22, 0.018))
			# Ridge apex iron strap bracket.
			u.box(Vector3(0.0, RIDGE_Y - 0.34, tz + fz_s), Vector3(0.32, 0.22, 0.018))
		for sd: float in [-1.0, 1.0]:
			for fz_s: float in [-0.118, 0.118]:
				# Collar-to-rafter & scissor-foot slim forged-iron strap plates.
				u.box(Vector3(sd * (collar_hw - 0.06), collar_y, tz + fz_s), Vector3(0.24, 0.18, 0.018))
				u.box(Vector3(sd * 3.42, 3.42, tz + fz_s), Vector3(0.20, 0.14, 0.018))
			# Raised gleaming brass/iron hex bolt heads on front & back faces of central gusset.
			u.colour = _lin(Color(0.46, 0.40, 0.30))
			for fz_s: float in [-0.132, 0.132]:
				u.box(Vector3(sd * 0.15, collar_y, tz + fz_s), Vector3(0.028, 0.028, 0.016))
				u.box(Vector3(sd * 0.04, collar_y + 0.20, tz + fz_s), Vector3(0.028, 0.028, 0.016))
			u.colour = _lin(Color(0.24, 0.23, 0.24))

	# Architectural `PieceCove` fairy-amber / frost-blue indirect ceiling wash tucked tightly along the sloping
	# tongue-and-groove roof planks directly above BOTH upper longitudinal purlins (hugging real wood, zero air flaps!).
	c.cove.surface(cove_m)
	for sd: float in [-1.0, 1.0]:
		var n_slope := Vector3(-sd, -1.0, 0.0).normalized()
		var up_slope := Vector3(-sd, 1.0, 0.0).normalized()
		var base_x := sd * 1.85
		var base_y := _roof_y(1.85)
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		for r_def: Array in [[0.06, 0.88], [0.42, 0.42], [1.05, 0.0]]:
			var dist := float(r_def[0])
			var w := float(r_def[1])
			var p_xy := Vector3(base_x, base_y, 0.0) + up_slope * dist + n_slope * 0.008
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for k in 9:
				var zz := lerpf(FZ + 0.25, BZ - 0.25, float(k) / 8.0)
				row.append(Vector3(p_xy.x, p_xy.y, zz))
				nrow.append(n_slope)
				crow.append(_lin(CEIL_PLANK, w))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		c.cove.grid(rows, norms, cols)


## Monumental snow-rimmed forward gable window wall (`z = FZ`) framing the cinema screen (`[0, 2.35, -7.40]`,
## `4.80 x 2.70 m`) inside warm chamfered timber posts, acoustic screen hood, low window-bench credenza, and soaring
## triangular mullioned gable glass panes looking straight into the moonlit alpine winter valley.
static func _forward_gable_and_screen(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood: Material = c.tinted("wood")
	var iron: Material = c.tinted("iron")
	var cove_m: Material = c.kit.cove_material()

	var sc_x := SCREEN_C.x
	var sc_y := SCREEN_C.y
	var sc_z := SCREEN_C.z
	var hw := SCREEN_W * 0.5
	var hh := SCREEN_H * 0.5
	var sill_y := 0.58

	# 1. Low timber dado wall beneath the panoramic forward gable windows (`y = 0.0 .. sill_y` across full width).
	s.surface(wood)
	s.colour = _lin(FIR_TIMBER * 0.80)
	s.box(Vector3(0.0, sill_y * 0.5, FZ + 0.06), Vector3(HW * 2.0, sill_y, 0.14), Basis(), [RoomMesh.DOWN])
	# Wide timber window sill shelf running cleanly across the gable base.
	s.colour = _lin(FIR_DARK)
	s.box(Vector3(0.0, sill_y + 0.03, FZ + 0.12), Vector3(HW * 2.0, 0.06, 0.28))

	# 2. Dark timber mullions & transoms dividing the monumental forward gable window wall (`z = FZ`).
	s.colour = _lin(MULLION_DARK)
	var post_x := hw + 0.22 # +-2.62 m framing the screen bay cleanly!
	# Twin heavy vertical timber mullions at +-2.62 m rising all the way to the 45-deg roof slope (`y = 4.33 m`),
	# plus secondary flank mullions at +-4.22 m (`y = 2.73 m`) and central gable apex mullion above screen (`y = 3.92..6.86 m`).
	for mx: float in [-4.22, -post_x, post_x, 4.22]:
		var my1 := _roof_y(mx) - 0.05
		s.box(Vector3(mx, (sill_y + my1) * 0.5, FZ + 0.02), Vector3(0.11, my1 - sill_y, 0.18))
	# Central upper-gable vertical mullion soaring from top of screen header (`y = 3.90`) to ridge (`y = 6.86`).
	s.box(Vector3(0.0, (3.90 + RIDGE_Y - 0.10) * 0.5, FZ + 0.02), Vector3(0.11, RIDGE_Y - 0.10 - 3.90, 0.18))
	# Horizontal timber transoms at `y = 2.25 m` (side bays) and `y = 3.90 m` (spanning full gable width +-3.05 m)
	# and upper gable transom at `y = 5.30 m` (spanning +-1.65 m).
	for sd: float in [-1.0, 1.0]:
		var x_out := RIDGE_Y - 2.25
		s.box(Vector3(sd * (post_x + x_out) * 0.5, 2.25, FZ + 0.02), Vector3(x_out - post_x, 0.09, 0.16))
	var w390 := (RIDGE_Y - 3.90) * 2.0
	s.box(Vector3(0.0, 3.90, FZ + 0.02), Vector3(w390, 0.13, 0.18))
	var w530 := (RIDGE_Y - 5.30) * 2.0
	s.box(Vector3(0.0, 5.30, FZ + 0.02), Vector3(w530, 0.09, 0.16))
	# Outer diagonal gable window casing rails hugging the 45-degree roof edges.
	for sd: float in [-1.0, 1.0]:
		Shapes.beam(s, Vector3(sd * (HW - 0.06), KNEE_Y, FZ + 0.02), Vector3(0.0, RIDGE_Y - 0.06, FZ + 0.02),
				Vector2(0.14, 0.18))

	# 3. Monumental forward gable glass (`PieceGlass`, strictly OUTSIDE the central screen rectangle and with zero
	#    overlap between the side bays below y = 3.90 and the soaring triangular gable apex above y = 3.90!).
	c.glass.surface(c.kit.GLASS)
	var x_transom := RIDGE_Y - 3.88 # 3.07 m
	for sd: float in [-1.0, 1.0]:
		var x_in := sd * (post_x + 0.04)
		var x_tr := sd * x_transom
		var x_out := sd * (HW - 0.06)
		# Pentagon below y = 3.88 m (follows 45-deg roof slope from x_out to x_tr, then flat along transom to x_in).
		var pts := [
			Vector3(x_out, sill_y + 0.04, FZ - 0.02),
			Vector3(x_in, sill_y + 0.04, FZ - 0.02),
			Vector3(x_in, 3.88, FZ - 0.02),
			Vector3(x_tr, 3.88, FZ - 0.02),
			Vector3(x_out, KNEE_Y, FZ - 0.02),
		]
		if sd < 0.0:
			c.glass.face(pts, Vector3.BACK)
		else:
			c.glass.face([pts[1], pts[0], pts[4], pts[3], pts[2]], Vector3.BACK)
	# Soaring triangular upper gable glass apex above the transom (`y = 3.92 .. RIDGE_Y - 0.10`).
	var apex_hw := RIDGE_Y - 3.92 - 0.04
	c.glass.face([
		Vector3(-apex_hw, 3.92, FZ - 0.02),
		Vector3(apex_hw, 3.92, FZ - 0.02),
		Vector3(0.0, RIDGE_Y - 0.10, FZ - 0.02),
	], Vector3.BACK)

	# 4. Crisp white exterior snow piled cleanly on every outer forward gable sill & transom ledge!
	for sd: float in [-1.0, 1.0]:
		_snow_ledge(c, Vector3(sd * 4.18, sill_y + 0.08, FZ - 0.16), Vector3(2.90, 0.16, 0.28))
		_snow_ledge(c, Vector3(sd * 3.65, 2.33, FZ - 0.11), Vector3(1.90, 0.10, 0.18))
	_snow_ledge(c, Vector3(0.0, 3.99, FZ - 0.12), Vector3(w390 - 0.24, 0.11, 0.18))
	_snow_ledge(c, Vector3(0.0, 5.38, FZ - 0.10), Vector3(w530 - 0.24, 0.09, 0.15))

	# 5. Cinema Screen Timber Framing, Twin Supporting Gable Posts, Hood & Low Media Credenza (`z = -7.40 .. -8.10`).
	# Twin heavy Douglas-fir floor-to-rafter screen posts at `x = +-2.58, z = -7.62`.
	s.surface(wood)
	s.colour = _lin(FIR_TIMBER)
	for sd: float in [-1.0, 1.0]:
		var ph := _roof_y(2.58) - 0.06
		s.box(Vector3(sd * 2.58, ph * 0.5, sc_z - 0.22), Vector3(0.20, ph, 0.22), Basis(), [RoomMesh.DOWN])
		# Tie beams anchoring the screen posts back to the gable mullions.
		s.box(Vector3(sd * 2.58, 0.90, (sc_z - 0.22 + FZ) * 0.5), Vector3(0.14, 0.14, (sc_z - 0.22) - FZ))
		s.box(Vector3(sd * 2.58, 3.84, (sc_z - 0.22 + FZ) * 0.5), Vector3(0.14, 0.16, (sc_z - 0.22) - FZ))

	# Matte-charcoal rear backing slab strictly behind the picture (`z = sc_z - 0.05`) so bright moonlit snow never bleeds behind the film!
	s.surface(iron)
	s.colour = _lin(IRON_BACK)
	s.box(Vector3(sc_x, sc_y, sc_z - 0.065), Vector3(SCREEN_W + 0.14, SCREEN_H + 0.14, 0.06))

	# Chamfered dark-walnut/fir screen border rails & protective timber top hood (strictly clear of picture rect!).
	s.surface(wood)
	s.colour = _lin(FIR_DARK)
	var border := 0.13
	var frame_z := sc_z - 0.07
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(sc_x + sd * (hw + border * 0.5), sc_y, frame_z), Vector3(border, SCREEN_H + border * 2.0, 0.18))
	s.box(Vector3(sc_x, sc_y - hh - border * 0.5, frame_z), Vector3(SCREEN_W + border * 2.0, border, 0.20))
	# Projecting angled timber screen hood above the top rail (`y = 3.70..3.94`, stays strictly above screen top!).
	s.colour = _lin(FIR_TIMBER * 0.92)
	s.box(Vector3(sc_x, sc_y + hh + border * 0.5 + 0.02, sc_z - 0.04),
			Vector3(SCREEN_W + border * 2.0 + 0.18, 0.16, 0.34))

	# Concealed `PieceCove` architectural wash hugging ONLY the solid timber screen hood underside & screen posts
	# (never protruding into the flanking gable window glass!).
	c.cove.surface(cove_m)
	var h_rows: Array = []
	var h_nrms: Array = []
	var h_cols: Array = []
	for r_def: Array in [[0.0, 0.86], [0.12, 0.45], [0.26, 0.04]]:
		var dz := float(r_def[0])
		var w := float(r_def[1])
		h_rows.append(PackedVector3Array([
			Vector3(sc_x - hw - border, sc_y + hh + border + 0.018, sc_z - 0.16 + dz),
			Vector3(sc_x + hw + border, sc_y + hh + border + 0.018, sc_z - 0.16 + dz),
		]))
		h_nrms.append(PackedVector3Array([Vector3.DOWN, Vector3.DOWN]))
		h_cols.append(PackedColorArray([_lin(FIR_WARM, w), _lin(FIR_WARM, w)]))
	c.cove.grid(h_rows, h_nrms, h_cols)

	# Dark recessed timber shadow panel sealing the narrow gap between the media credenza top (0.68) and the
	# cinema screen bottom border (0.87) so snow never leaks beneath the screen!
	s.surface(wood)
	s.colour = _lin(FIR_DARK * 0.72)
	s.box(Vector3(0.0, 0.78, sc_z - 0.18), Vector3(5.04, 0.24, 0.14))

	# Low built-in timber window-bench credenza directly beneath the screen (`y = 0.0 .. 0.68 m`, well below screen bottom 1.00 m!).
	s.surface(wood)
	s.colour = _lin(FIR_TIMBER * 0.86)
	s.box(Vector3(0.0, 0.31, sc_z - 0.34), Vector3(4.92, 0.62, 0.68), Basis(), [RoomMesh.DOWN])
	s.colour = _lin(FIR_WARM)
	s.box(Vector3(0.0, 0.65, sc_z - 0.32), Vector3(5.06, 0.06, 0.76))
	# Recessed dark acoustic wool speaker cloth grille in the credenza centre + subtle brass pulls on flank doors.
	s.surface(c.tinted("cloth"))
	s.colour = _lin(Color(0.12, 0.11, 0.10))
	s.box(Vector3(0.0, 0.34, sc_z + 0.005), Vector3(1.85, 0.38, 0.02))
	u.surface(_metal(c))
	u.colour = _lin(BRASS)
	for px: float in [-1.55, -1.35, 1.35, 1.55]:
		u.box(Vector3(px, 0.36, sc_z + 0.015), Vector3(0.025, 0.12, 0.025))

	# Clean physics box enclosing the screen posts & credenza (z <= -7.1, far clear of viewer).
	_solid(c, Vector3(0.0, 2.2, sc_z - 0.35), Vector3(5.4, 4.4, 0.85))


## Sculpted soft snow pillow piled cleanly on an exterior window sill or transom ledge.
static func _snow_ledge(c: Object, centre: Vector3, size: Vector3) -> void:
	var u: RoomMesh = c.u
	u.surface(c.soft("stone"))
	u.colour = _lin(SNOW_SILL)
	u.rounded_box(Vector3.ZERO, size, minf(size.y * 0.44, 0.06), Transform3D(Basis(), centre), 1,
			Vector3i(2, 0, 0), 0.0, [RoomMesh.DOWN])


## Aft timber gable wall (`z = BZ`), cozy timber sleeping-loft mezzanine balcony (`z = LOFT_Z0..BZ, y = LOFT_Y`),
## wooden balustrade, loft bed with alpine quilt & warm bedside lantern, slanted attic ladder, heavy timber chalet
## entry door with iron strap hinges, and wooden coat rack with draped knit scarf.
static func _aft_wall_loft_and_entry(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood: Material = c.tinted("wood")
	var iron: Material = c.tinted("iron")

	# 1. Full aft A-frame timber gable wall at `z = BZ` (pentagon: base +-HW, knees y = KNEE_Y, ridge apex y = RIDGE_Y).
	s.surface(wood)
	s.colour = _lin(FIR_TIMBER * 0.85)
	# Lower rectangle (`y = 0 .. KNEE_Y`) + upper triangle (`y = KNEE_Y .. RIDGE_Y`) facing -Z (Vector3.FORWARD).
	s.face([
		Vector3(HW, 0.0, BZ),
		Vector3(-HW, 0.0, BZ),
		Vector3(-HW, KNEE_Y, BZ),
		Vector3(HW, KNEE_Y, BZ),
	], Vector3.FORWARD)
	s.face([
		Vector3(HW, KNEE_Y, BZ),
		Vector3(-HW, KNEE_Y, BZ),
		Vector3(0.0, RIDGE_Y, BZ),
	], Vector3.FORWARD)
	# Horizontal log/timber dado & loft trim bands across the aft gable for crisp chalet texture.
	s.colour = _lin(FIR_DARK)
	s.box(Vector3(0.0, LOFT_Y - 0.08, BZ - 0.05), Vector3((RIDGE_Y - LOFT_Y) * 2.0, 0.16, 0.10))
	s.box(Vector3(0.0, 4.75, BZ - 0.04), Vector3((RIDGE_Y - 4.75) * 2.0, 0.12, 0.08))

	# 2. Aft timber sleeping-loft mezzanine balcony (`z = LOFT_Z0..BZ`, deck at `y = LOFT_Y = 2.65 m`).
	var loft_hw := RIDGE_Y - LOFT_Y # 4.30 m exact intersection with 45-degree roof slopes!
	var loft_d := BZ - LOFT_Z0      # 2.55 m deep!
	var loft_zc := (LOFT_Z0 + BZ) * 0.5
	s.colour = _lin(FLOOR_OAK * 0.96)
	# Loft floor slab (thick timber deck + warm plank underside).
	s.box(Vector3(0.0, LOFT_Y - 0.08, loft_zc), Vector3(loft_hw * 2.0, 0.16, loft_d))
	# Heavy main loft support fascia beam along front edge (`z = LOFT_Z0`) + twin vertical timber support posts (`x = +-2.95 m`).
	s.colour = _lin(FIR_DARK)
	s.box(Vector3(0.0, LOFT_Y - 0.14, LOFT_Z0 + 0.08), Vector3(loft_hw * 2.0, 0.28, 0.24))
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(sd * 2.95, (LOFT_Y - 0.24) * 0.5, LOFT_Z0 + 0.10), Vector3(0.22, LOFT_Y - 0.24, 0.22),
				Basis(), [RoomMesh.DOWN])
		# Diagonal timber knee braces under the loft fascia beam!
		Shapes.beam(s, Vector3(sd * 2.95, LOFT_Y - 0.85, LOFT_Z0 + 0.10),
				Vector3(sd * 2.25, LOFT_Y - 0.16, LOFT_Z0 + 0.10), Vector2(0.14, 0.14))
		_solid(c, Vector3(sd * 2.95, (LOFT_Y - 0.24) * 0.5, LOFT_Z0 + 0.10), Vector3(0.28, LOFT_Y, 0.28))

	# Wooden mezzanine balustrade along front edge (`z = LOFT_Z0 + 0.08`, `y = LOFT_Y .. LOFT_Y + 0.92 m`), leaving a
	# neat ladder access opening on the starboard loft side (`x = +1.55 .. +2.35 m`).
	var rail_y := LOFT_Y + 0.90
	var rail_z := LOFT_Z0 + 0.08
	s.colour = _lin(FIR_WARM * 0.92)
	# Left balustrade run (`x = -3.45 .. +1.55 m`) and short starboard run (`x = +2.35 .. +3.45 m`).
	var runs: Array = [[-3.42, 1.52], [2.36, 3.42]]
	for run: Array in runs:
		var x0: float = run[0]
		var x1: float = run[1]
		var rw := x1 - x0
		var rxc := (x0 + x1) * 0.5
		# Chamfered top handrail & bottom shoe rail.
		s.box(Vector3(rxc, rail_y, rail_z), Vector3(rw + 0.08, 0.075, 0.11))
		s.box(Vector3(rxc, LOFT_Y + 0.06, rail_z), Vector3(rw, 0.055, 0.08))
		# Sturdy newel posts at ends.
		for nx: float in [x0, x1]:
			s.box(Vector3(nx, LOFT_Y + 0.50, rail_z), Vector3(0.10, 1.00, 0.10))
		# Vertical wooden balusters spaced cleanly every ~0.26 m.
		var n_bal := maxi(2, int(rw / 0.26))
		for k in range(1, n_bal):
			var bx := lerpf(x0, x1, float(k) / float(n_bal))
			s.box(Vector3(bx, LOFT_Y + 0.48, rail_z), Vector3(0.042, 0.80, 0.042))

	# Slanted timber attic ladder descending from loft opening (`x = 1.94 m`, `z = 2.28..3.06 m`, `y = 0.0..2.78 m`).
	var lad_x := 1.94
	var lad_bot := Vector3(lad_x, 0.0, 2.24)
	var lad_top := Vector3(lad_x, LOFT_Y + 0.12, LOFT_Z0 + 0.02)
	s.colour = _lin(FIR_WARM)
	for sd: float in [-0.24, 0.24]:
		Shapes.beam(s, lad_bot + Vector3(sd, 0.0, 0.0), lad_top + Vector3(sd, 0.0, 0.0), Vector2(0.05, 0.10))
	for k in 8:
		var t := (float(k) + 0.65) / 8.5
		var rp := lad_bot.lerp(lad_top, t)
		s.box(rp, Vector3(0.46, 0.032, 0.095))
	_solid(c, (lad_bot + lad_top) * 0.5, Vector3(0.60, LOFT_Y, 0.90))

	# 3. Cozy sleeping-loft bed with alpine crimson-and-cream quilt, plump pillows & glowing bedside amber lantern!
	var bed_x := -0.70
	var bed_z := LOFT_Z0 + 1.55
	s.colour = _lin(FIR_DARK)
	s.box(Vector3(bed_x, LOFT_Y + 0.14, bed_z), Vector3(1.96, 0.28, 1.52), Basis(), [RoomMesh.DOWN])
	# Cream wool mattress & folded crimson alpine quilt blanket.
	u.surface(c.soft("cloth"))
	u.colour = _lin(QUILT_CREAM)
	u.rounded_box(Vector3.ZERO, Vector3(1.86, 0.22, 1.44), 0.06,
			Transform3D(Basis(), Vector3(bed_x, LOFT_Y + 0.34, bed_z)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
	u.colour = _lin(QUILT_CRIMSON)
	u.rounded_box(Vector3.ZERO, Vector3(1.90, 0.12, 0.92), 0.05,
			Transform3D(Basis(), Vector3(bed_x, LOFT_Y + 0.42, bed_z - 0.24)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
	# Two plump cream pillows at the headboard (`z = BZ - 0.45`).
	u.colour = _lin(QUILT_CREAM * 1.04)
	for px: float in [bed_x - 0.44, bed_x + 0.44]:
		u.rounded_box(Vector3.ZERO, Vector3(0.68, 0.16, 0.38), 0.065,
				Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10.0)), Vector3(px, LOFT_Y + 0.50, bed_z + 0.45)), 1)
	# Warm glowing bedside lantern perched clearly forward beside the loft bed (`x = +0.72, z = LOFT_Z0 + 0.92`)
	# so its golden alpine glow peeks warmly through the wooden balustrade from below!
	s.surface(wood)
	s.colour = _lin(FIR_TIMBER)
	s.box(Vector3(0.72, LOFT_Y + 0.22, LOFT_Z0 + 0.92), Vector3(0.44, 0.44, 0.44), Basis(), [RoomMesh.DOWN])
	_brass_lantern(c, Vector3(0.72, LOFT_Y + 0.44, LOFT_Z0 + 0.92), 0.36, "house")

	# Cozy braided door mat resting on the honey-oak planks directly inside the chalet entry door.
	u.surface(c.soft("cloth"))
	u.colour = _lin(Color(0.32, 0.18, 0.14))
	u.rounded_box(Vector3.ZERO, Vector3(0.96, 0.016, 0.52), 0.008,
			Transform3D(Basis(), Vector3(-1.25, 0.008, BZ - 0.42)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])

	# Plush alpine wool accent throw pillows nestled into the outer corners of both cognac-leather sofas
	# (strictly at |x| = 1.04 m, well clear of viewer (0, 0, 0) and every seat's sight line!).
	for rz: float in [0.0, 1.85]:
		for sd: float in [-1.0, 1.0]:
			var pcol := QUILT_CRIMSON if sd < 0.0 else SPRUCE_MUG * 1.15
			u.colour = _lin(pcol)
			var pb := Basis(Vector3.UP, deg_to_rad(sd * 22.0)) * Basis(Vector3.RIGHT, deg_to_rad(14.0))
			u.rounded_box(Vector3.ZERO, Vector3(0.30, 0.28, 0.11), 0.05,
					Transform3D(pb, Vector3(sd * 1.02, 0.60, rz + 0.12)), 1)

	# 4. Heavy timber chalet entry door (`x = -1.25, z = BZ - 0.04`) with Z-brace planks, forged-iron strap hinges,
	#    ring latch, and small frost-lit upper mullioned door pane!
	var dx := -1.25
	var dw := 1.06
	var dh := 2.16
	s.surface(wood)
	s.colour = _lin(FIR_DARK)
	# Deep door frame jambs & lintel.
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(dx + sd * (dw * 0.5 + 0.06), dh * 0.5, BZ - 0.07), Vector3(0.12, dh + 0.10, 0.16),
				Basis(), [RoomMesh.DOWN])
	s.box(Vector3(dx, dh + 0.06, BZ - 0.07), Vector3(dw + 0.26, 0.12, 0.18))
	# Recessed vertical plank door leaf & classic alpine Z-brace rails.
	s.colour = _lin(FIR_TIMBER * 0.78)
	s.box(Vector3(dx, dh * 0.5, BZ - 0.03), Vector3(dw, dh, 0.06), Basis(), [RoomMesh.DOWN])
	s.colour = _lin(FIR_DARK * 1.08)
	for ry: float in [0.22, 1.12, 1.98]:
		s.box(Vector3(dx, ry, BZ - 0.075), Vector3(dw - 0.08, 0.14, 0.035))
	Shapes.beam(s, Vector3(dx - 0.44, 0.26, BZ - 0.075), Vector3(dx + 0.44, 1.08, BZ - 0.075), Vector2(0.035, 0.11))
	# Forged-iron strap hinges & ring latch on the entry door.
	s.surface(iron)
	s.colour = _lin(IRON)
	for hy: float in [0.38, 1.80]:
		s.box(Vector3(dx - 0.22, hy, BZ - 0.098), Vector3(0.56, 0.055, 0.018))
	u.surface(_metal(c))
	u.colour = _lin(Color(0.20, 0.19, 0.18))
	u.box(Vector3(dx + 0.39, 1.02, BZ - 0.095), Vector3(0.06, 0.16, 0.02))
	Shapes.arch(u, Vector3(dx + 0.39, 0.96, BZ - 0.115), 0.035, 0.052, 0.018, 12, Basis(), 0.0, TAU)
	# Small frost-blue moonlit upper door transom pane (`PieceWindows` soft cool alpine glint or dark inset glass).
	s.surface(wood)
	s.colour = _lin(MULLION_DARK)
	s.box(Vector3(dx, 1.56, BZ - 0.08), Vector3(0.54, 0.48, 0.03))
	c.lit.surface(c.kit._lamp(Color(0.32, 0.46, 0.72), 0.35, 0.0, "house"))
	Shapes.quad(c.lit, Vector3(dx, 1.56, BZ - 0.096), Vector3(0.22, 0.0, 0.0), Vector3(0.0, 0.19, 0.0), Vector3.FORWARD)
	s.surface(wood)
	s.colour = _lin(MULLION_DARK)
	s.box(Vector3(dx, 1.56, BZ - 0.102), Vector3(0.03, 0.44, 0.02))
	s.box(Vector3(dx, 1.56, BZ - 0.102), Vector3(0.48, 0.03, 0.02))

	# 5. Wall-mounted timber coat rack (`x = -0.18, y = 1.52, z = BZ - 0.05`) with brass pegs & draped winter scarf!
	var rx := -0.18
	s.surface(wood)
	s.colour = _lin(FIR_DARK)
	s.box(Vector3(rx, 1.54, BZ - 0.035), Vector3(0.84, 0.14, 0.05))
	u.surface(_metal(c))
	u.colour = _lin(BRASS)
	for k in 4:
		var px := rx - 0.30 + float(k) * 0.20
		Shapes.cylinder(u, Vector3(px, 1.54, BZ - 0.06), 0.014, 0.085, 8, Basis(Vector3.RIGHT, -PI * 0.5))
	# Cozy knitted ochre-and-crimson wool scarf draped naturally off peg #2!
	u.surface(c.soft("cloth"))
	u.colour = _lin(SCARF_OCHRE)
	u.rounded_box(Vector3.ZERO, Vector3(0.14, 0.62, 0.055), 0.02,
			Transform3D(Basis(Vector3.BACK, deg_to_rad(5.0)), Vector3(rx - 0.10, 1.24, BZ - 0.11)), 1)
	u.colour = _lin(QUILT_CRIMSON)
	u.rounded_box(Vector3.ZERO, Vector3(0.13, 0.48, 0.045), 0.018,
			Transform3D(Basis(Vector3.BACK, deg_to_rad(-8.0)), Vector3(rx - 0.04, 1.30, BZ - 0.13)), 1)
	# Warm rustic wrought-iron entry wall lantern above the coat rack (`y = 2.08 m`).
	_brass_lantern(c, Vector3(rx, 1.88, BZ - 0.22), 0.26, "house")


## Forged-iron & timber wagon-wheel / antler-bracket beam chandelier hung cleanly from the soaring ridge beam
## (`(0.0, 4.95, -1.55)`, well over 2.5 m clear of every seat's sight line!).
static func _chandelier(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood: Material = c.tinted("wood")
	var iron: Material = c.tinted("iron")
	var brass: Material = _metal(c)
	var shade_m: Material = c.shade(LAMP_WARM)

	var ctr := Vector3(0.0, 4.24, -2.75)
	var r_in := 0.78
	var r_out := 0.92

	# Suspension iron rod & chain links descending from ridge beam (`y = 6.68`) to central forged-iron hub.
	s.surface(iron)
	s.colour = _lin(IRON)
	Shapes.cylinder(s, Vector3(ctr.x, ctr.y + 0.05, ctr.z), 0.032, RIDGE_Y - 0.22 - ctr.y, 8)
	# Four angled wrought-iron hanger chains supporting the wheel rim from a collar at y = 5.75.
	var collar := Vector3(ctr.x, ctr.y + 0.88, ctr.z)
	s.box(collar, Vector3(0.16, 0.12, 0.16))
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		var rim_p := ctr + Vector3(cos(a) * (r_out - 0.04), 0.05, sin(a) * (r_out - 0.04))
		Shapes.beam(s, collar, rim_p, Vector2(0.022, 0.022))

	# Dark heavy chamfered oak wagon-wheel ring (`Shapes.arch` full 360° circle lying flat in XZ!).
	var flat := Basis(Vector3.RIGHT, PI * 0.5)
	s.surface(wood)
	s.colour = _lin(FIR_DARK * 1.12)
	Shapes.arch(s, ctr, r_in, r_out, 0.12, 24, flat, 0.0, TAU)
	# Outer forged-iron wagon-wheel tire band + 8 radial iron spokes + central boss hub.
	s.surface(iron)
	s.colour = _lin(IRON)
	Shapes.arch(s, ctr, r_out, r_out + 0.024, 0.135, 24, flat, 0.0, TAU, ["outer", "front", "back"])
	Shapes.cylinder(s, ctr - Vector3(0.0, 0.11, 0.0), 0.13, 0.22, 12)
	for k in 8:
		var a := TAU * float(k) / 8.0
		var d := Vector3(cos(a), 0.0, sin(a))
		Shapes.beam(s, ctr + d * 0.11, ctr + d * (r_in + 0.02), Vector2(0.032, 0.036))

	# 8 warm frosted-amber candle lanterns crowning the wagon wheel rim (`PieceLamps` + gleaming brass cups!).
	for k in 8:
		var a := TAU * float(k) / 8.0 + PI / 8.0
		var pos := ctr + Vector3(cos(a) * ((r_in + r_out) * 0.5), 0.06, sin(a) * ((r_in + r_out) * 0.5))
		u.surface(brass)
		u.colour = _lin(BRASS)
		Shapes.lathe(u, [Vector2(0.075, 0.0), Vector2(0.085, 0.025), Vector2(0.045, 0.05)], pos, 10)
		c.lit.surface(shade_m)
		Shapes.lathe(c.lit, [
			Vector2(0.052, 0.05), Vector2(0.072, 0.14), Vector2(0.064, 0.26), Vector2(0.0, 0.28),
		], pos, 10)


## Low live-edge cedar coffee table (`y = 0.0..0.40 m <= 0.44 m` — zero sight-line block!) holding two glazed ceramic
## cocoa mugs with faint rising steam wisps, a glowing brass candle lantern, sculpted pinecones, and a folded tartan
## wool throw blanket.
static func _coffee_table(c: Object, h: Hall) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood: Material = c.tinted("wood")
	var iron: Material = c.tinted("iron")
	var ceramic: Material = _ceramic(c)

	var cx := TABLE_C.x
	var cz := TABLE_C.z
	var tw := 1.62
	var td := 0.78
	var top_y := TABLE_TOP_Y

	# 1. Thick chamfered live-edge red-cedar tabletop slab + rough dark bark live-edges along front & back.
	s.surface(wood)
	s.colour = _lin(CEDAR_LIVE)
	s.box(Vector3(cx, top_y - 0.032, cz), Vector3(tw, 0.064, td))
	s.colour = _lin(BARK_DARK)
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(cx, top_y - 0.034, cz + sd * (td * 0.5 + 0.014)), Vector3(tw - 0.04, 0.058, 0.028))

	# Sturdy splayed forged-iron trestle legs & lower stretcher bar resting cleanly on the Nordic rug (`y = 0.012`).
	s.surface(iron)
	s.colour = _lin(IRON)
	for sx: float in [-0.62, 0.62]:
		s.box(Vector3(cx + sx, top_y - 0.08, cz), Vector3(0.05, 0.03, td - 0.16))
		for sz: float in [-0.26, 0.26]:
			Shapes.beam(s, Vector3(cx + sx, top_y - 0.07, cz + sz),
					Vector3(cx + sx * 1.08, 0.012, cz + sz * 1.14), Vector2(0.036, 0.036))
	Shapes.beam(s, Vector3(cx - 0.65, 0.12, cz), Vector3(cx + 0.65, 0.12, cz), Vector2(0.03, 0.03))
	_solid(c, Vector3(cx, top_y * 0.5, cz), Vector3(tw, top_y, td))

	# 2. Softly folded heritage tartan wool throw blanket draped over the left corner of the coffee table
	#    (plump rounded wool folds in muted alpine tartan + soft overhang + cream wool fringe tassels!).
	u.surface(c.soft("cloth", true, "tartan_blanket"))
	u.colour = _lin(Color(0.56, 0.50, 0.46))
	var tb := Basis(Vector3.UP, deg_to_rad(9.0))
	# Bottom folded layer + soft top folded layer slightly offset for organic textile softness.
	u.rounded_box(Vector3.ZERO, Vector3(0.48, 0.048, 0.56), 0.022,
			Transform3D(tb, Vector3(cx - 0.56, top_y + 0.024, cz - 0.02)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
	u.rounded_box(Vector3.ZERO, Vector3(0.44, 0.044, 0.50), 0.020,
			Transform3D(Basis(Vector3.UP, deg_to_rad(13.0)), Vector3(cx - 0.55, top_y + 0.062, cz - 0.01)), 1)
	# Soft rounded blanket drape cascading naturally over the left cedar slab edge (`y = 0.14..0.41`).
	u.rounded_box(Vector3.ZERO, Vector3(0.048, 0.28, 0.50), 0.020,
			Transform3D(tb * Basis(Vector3.BACK, deg_to_rad(5.0)), Vector3(cx - 0.815, top_y - 0.105, cz - 0.02)), 1)
	# Cream wool fringe tassels along the draped blanket hem!
	u.surface(c.soft("cloth"))
	u.colour = _lin(QUILT_CREAM * 0.88)
	for k in 8:
		var fz := lerpf(-0.21, 0.21, float(k) / 7.0)
		u.box(Vector3(cx - 0.825, top_y - 0.265, cz - 0.02) + tb * Vector3(0.0, 0.0, fz),
				Vector3(0.014, 0.042, 0.016), tb)

	# 3. Two glazed ceramic hot-cocoa mugs (cream & spruce-green) with handles & rising steam wisps!
	var mugs: Array = [
		[Vector3(cx - 0.22, top_y, cz + 0.12), CREAM_MUG, 0.55],
		[Vector3(cx + 0.04, top_y, cz - 0.06), SPRUCE_MUG, -0.70],
	]
	for mg: Array in mugs:
		var pos: Vector3 = mg[0]
		var col: Color = mg[1]
		var yaw: float = mg[2]
		var mb := Basis(Vector3.UP, yaw)
		u.surface(ceramic)
		u.colour = _lin(col)
		Shapes.lathe(u, [
			Vector2(0.038, 0.0), Vector2(0.046, 0.02), Vector2(0.048, 0.095),
			Vector2(0.046, 0.105), Vector2(0.039, 0.105), Vector2(0.038, 0.082),
		], pos, 14)
		# Curved mug ear handle.
		var hpts: Array[Vector3] = [
			pos + mb * Vector3(0.044, 0.084, 0.0),
			pos + mb * Vector3(0.074, 0.076, 0.0),
			pos + mb * Vector3(0.078, 0.048, 0.0),
			pos + mb * Vector3(0.068, 0.024, 0.0),
			pos + mb * Vector3(0.044, 0.020, 0.0),
		]
		_tube(u, hpts, 0.006, 0.008, 6, mb.z)
		# Dark steaming hot cocoa surface disc inside the mug.
		u.colour = _lin(COCOA)
		var disc: Array = []
		for k in 12:
			var a := TAU * float(k) / 12.0
			disc.append(pos + Vector3(cos(a) * 0.038, 0.086, sin(a) * 0.038))
		u.face(disc, Vector3.UP)
		# Delicate rising steam wisp (`HearthShaft`, additive super-soft narrow ribbon).
		h.shaft.cone(pos + Vector3(0.0, 0.36, 0.0), pos + Vector3(0.0, 0.10, 0.0), 0.058, 0.022, 10,
				Color(0.92, 0.94, 0.98, 0.20), Color(0.92, 0.94, 0.98, 0.42))

	# 4. Small warm glowing brass candle lantern (`x = +0.48, z = -1.58`, top y = 0.64 m — well below sight lines!).
	_brass_lantern(c, Vector3(cx + 0.48, top_y, cz - 0.10), 0.24, "house")

	# 5. Cedar slice coaster & cluster of 3 sculpted alpine pinecones!
	u.surface(c.soft("wood"))
	u.colour = _lin(LOG_END * 0.88)
	Shapes.cylinder(u, Vector3(cx + 0.22, top_y, cz + 0.16), 0.11, 0.014, 14)
	u.surface(c.soft("cloth"))
	u.colour = _lin(PINECONE)
	for pc: Array in [[0.18, 0.14, 0.034, 0.078, 0.2], [0.26, 0.18, 0.030, 0.068, -0.35],
			[0.23, 0.11, 0.026, 0.058, 0.55]]:
		var p_at := Vector3(cx + float(pc[0]), top_y + 0.014, cz + float(pc[1]))
		var r := float(pc[2])
		var ph := float(pc[3])
		var pb := Basis(Vector3.UP, float(pc[4])) * Basis(Vector3.RIGHT, deg_to_rad(18.0))
		Shapes.lathe(u, [
			Vector2(0.008, 0.0), Vector2(r * 0.85, ph * 0.22), Vector2(r, ph * 0.48),
			Vector2(r * 0.78, ph * 0.75), Vector2(0.0, ph),
		], p_at, 8, pb)


## Built-in honey-pine winter bookcases along the port & starboard knee walls stacked with colorful winter hardcovers
## & reading lamp, plus the classic pair of bent-tip wooden alpine skis & bamboo ski poles leaning beside the aft door.
static func _side_bookcases_and_skis(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood: Material = c.tinted("wood")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026

	# 1. Port low winter bookcase (`x = -5.45, z = -2.10 .. +2.10, y = 0.0 .. 1.06 m`) + starboard aft bookcase
	#    (`x = +5.45, z = +0.20 .. +2.35, y = 0.0 .. 1.06 m`).
	var bookcases: Array = [
		[-1.0, -2.10, 2.10, 3],
		[ 1.0,  0.20, 2.35, 2],
	]
	var spines: Array[Color] = [
		Color(0.54, 0.13, 0.13), Color(0.12, 0.28, 0.20), Color(0.14, 0.21, 0.36),
		Color(0.66, 0.48, 0.18), Color(0.84, 0.78, 0.66), Color(0.46, 0.22, 0.12),
		Color(0.32, 0.14, 0.24), Color(0.24, 0.34, 0.26),
	]
	for bc: Array in bookcases:
		var sd: float = bc[0]
		var z0: float = bc[1]
		var z1: float = bc[2]
		var bays: int = bc[3]
		var depth := 0.38
		var bx := sd * (HW - depth * 0.5 - 0.04)
		var bw := z1 - z0
		var bzc := (z0 + z1) * 0.5

		s.surface(wood)
		s.colour = _lin(FIR_TIMBER * 0.90)
		# Top cap, base plinth, and two interior shelf boards.
		for sy: float in [0.06, 0.38, 0.72, 1.04]:
			s.box(Vector3(bx, sy, bzc), Vector3(depth, 0.04, bw))
		# Vertical bay dividers.
		for k in bays + 1:
			var dz := lerpf(z0 + 0.02, z1 - 0.02, float(k) / float(bays))
			s.box(Vector3(bx, 0.54, dz), Vector3(depth - 0.02, 1.02, 0.04), Basis(), [RoomMesh.DOWN])
		_solid(c, Vector3(bx, 0.54, bzc), Vector3(depth, 1.06, bw))

		# Packed jewel-toned winter books in PieceSoft (`c.u`, saves static lightmap atlas!).
		u.surface(c.soft("cloth"))
		for shelf_y: float in [0.08, 0.40, 0.74]:
			for b_i in bays:
				var bz0 := lerpf(z0 + 0.06, z1 - 0.06, float(b_i) / float(bays)) + 0.02
				var bz1 := lerpf(z0 + 0.06, z1 - 0.06, float(b_i + 1) / float(bays)) - 0.02
				var cur_z := bz0
				while cur_z < bz1 - 0.06:
					var bt := rng.randf_range(0.030, 0.056)
					var bh := rng.randf_range(0.19, 0.27)
					var bd := rng.randf_range(0.18, 0.25)
					if cur_z + bt > bz1 - 0.02:
						break
					var col: Color = spines[rng.randi() % spines.size()] * rng.randf_range(0.84, 1.08)
					u.colour = _lin(col)
					var fx := bx - sd * (depth * 0.5 - bd * 0.5 - 0.03)
					u.box(Vector3(fx, shelf_y + bh * 0.5, cur_z + bt * 0.5), Vector3(bd, bh, bt), Basis(),
							[RoomMesh.DOWN])
					cur_z += bt + 0.004

	# Cozy warm brass reading lamp & ceramic cocoa pitcher atop the port bookcase (`y = 1.06 m`, cleanly clear of truss!).
	_brass_lantern(c, Vector3(-HW + 0.24, 1.06, -1.28), 0.36, "house")
	u.surface(_ceramic(c))
	u.colour = _lin(CREAM_MUG)
	Shapes.lathe(u, [
		Vector2(0.055, 0.0), Vector2(0.085, 0.07), Vector2(0.078, 0.16),
		Vector2(0.048, 0.23), Vector2(0.056, 0.27), Vector2(0.044, 0.27),
	], Vector3(-HW + 0.24, 1.06, 0.65), 12)

	# 2. Pair of classic bent-tip wooden alpine skis & vintage bamboo ski poles leaning beside the aft entry door!
	var ski_z := BZ - 0.20
	var lean := Basis(Vector3.RIGHT, deg_to_rad(-7.0))
	for k in 2:
		var sx := 0.64 + float(k) * 0.20
		var sk_base := Vector3(sx, 0.0, ski_z)
		var sk_b := Basis(Vector3.UP, deg_to_rad(-6.0 + float(k) * 9.0)) * lean
		# Hickory ski shaft (`0.095 m` wide, `1.72 m` straight shaft + graceful curved shovel tip!).
		u.surface(c.soft("wood"))
		u.colour = _lin(SKI_HICKORY)
		u.box(sk_base + sk_b * Vector3(0.0, 0.86, 0.0), Vector3(0.095, 1.72, 0.022), sk_b)
		# Classic alpine crimson racing stripe down the ski front face.
		u.surface(c.soft("cloth"))
		u.colour = _lin(SKI_STRIPE)
		u.box(sk_base + sk_b * Vector3(0.0, 0.96, -0.013), Vector3(0.036, 1.24, 0.006), sk_b)
		# Bent-up curved wooden ski tip!
		u.surface(c.soft("wood"))
		u.colour = _lin(SKI_HICKORY * 1.05)
		var tip_p0 := sk_base + sk_b * Vector3(0.0, 1.71, 0.0)
		var tip_p1 := sk_base + sk_b * Vector3(0.0, 1.85, -0.045)
		var tip_p2 := sk_base + sk_b * Vector3(0.0, 1.94, -0.115)
		Shapes.beam(u, tip_p0, tip_p1, Vector2(0.088, 0.018))
		Shapes.beam(u, tip_p1, tip_p2, Vector2(0.056, 0.014))
		# Dark forged-iron & leather toe binding block mid-ski.
		u.surface(c.soft("iron"))
		u.colour = _lin(IRON)
		u.box(sk_base + sk_b * Vector3(0.0, 0.78, -0.032), Vector3(0.086, 0.14, 0.048), sk_b)
		u.box(sk_base + sk_b * Vector3(0.0, 0.62, -0.022), Vector3(0.075, 0.06, 0.032), sk_b)

	# Pair of vintage bamboo/birch alpine ski poles with round snow baskets & leather handles!
	for k in 2:
		var px := 1.04 + float(k) * 0.14
		var p_bot := Vector3(px, 0.0, BZ - 0.30 + float(k) * 0.05)
		var p_top := Vector3(px + 0.02, 1.32, BZ - 0.11)
		u.surface(c.soft("wood"))
		u.colour = _lin(LOG_END * 0.92)
		Shapes.beam(u, p_bot, p_top, Vector2(0.018, 0.018))
		# Dark leather grip at top.
		u.surface(c.soft("iron"))
		u.colour = _lin(BARK_DARK)
		Shapes.beam(u, p_bot.lerp(p_top, 0.87), p_top, Vector2(0.028, 0.028))
		# Classic round snow basket ring near the pole tip (`y ~ 0.11 m`).
		var b_at := p_bot.lerp(p_top, 0.09)
		var p_dir := (p_top - p_bot).normalized()
		var b_x := p_dir.cross(Vector3.RIGHT).normalized()
		var b_z := b_x.cross(p_dir).normalized()
		Shapes.arch(u, b_at, 0.045, 0.064, 0.012, 12, Basis(b_x, b_z, p_dir), 0.0, TAU)


## Reusable crafted hexagonal brass & frosted-glass chalet lantern (`PieceSoft` brass + `PieceLamps` warm glow).
static func _brass_lantern(c: Object, foot: Vector3, h: float, group := "house") -> void:
	var u: RoomMesh = c.u
	var r := h * 0.28
	u.surface(_metal(c))
	u.colour = _lin(BRASS)
	# Stepped brass base plinth & domed vent hood cap.
	Shapes.lathe(u, [
		Vector2(r * 1.15, 0.0), Vector2(r * 1.15, h * 0.09), Vector2(r * 0.92, h * 0.14),
	], foot, 6)
	Shapes.lathe(u, [
		Vector2(r * 1.05, h * 0.72), Vector2(r * 0.72, h * 0.86), Vector2(r * 0.28, h * 0.94),
		Vector2(0.0, h),
	], foot, 6)
	# 4 slender brass corner posts framing the glowing frosted candle glass core.
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		var p := foot + Vector3(cos(a) * r * 0.92, h * 0.12, sin(a) * r * 0.92)
		Shapes.cylinder(u, p, maxf(r * 0.075, 0.006), h * 0.62, 6, Basis(), false)
	# Glowing warm lantern glass core (`PieceLamps`, shared material per group).
	var glow_m: Material = c.shade(LAMP_WARM) if group == "house" else _accent_lamp(c, _hall(c))
	c.lit.surface(glow_m)
	Shapes.cylinder(c.lit, foot + Vector3(0.0, h * 0.14, 0.0), r * 0.76, h * 0.58, 8)


## Chalet interior bake lights & stand-in shader lamps (0 live lights: warm chandelier/loft/lamps + cool moonlight).
static func _chalet_lights(c: Object) -> void:
	# 1. Stand-in lamps for seats, soft meshes, and unbaked preview (leaves 2 slots for cabin_hearth!).
	c.kit._light.add_lamp(Vector3(0.0, 4.15, -2.75), LAMP_WARM * 1.95, -1.0)    # Wagon-wheel chandelier
	c.kit._light.add_lamp(Vector3(0.0, 3.65,  2.65), LAMP_WARM * 1.40, -1.0)    # Aft loft & back sofa glow
	c.kit._light.add_lamp(Vector3(-4.55, 1.40, -1.28), LAMP_WARM * 1.10, -1.0)  # Port bookcase reading lamp
	c.kit._light.add_lamp(Vector3(0.48, 0.66, -1.58), LAMP_WARM * 0.75, -1.0)   # Coffee-table brass lantern
	c.kit._light.add_lamp(Vector3(-2.10, 3.30, -6.90), MOON_FILL * 1.05, -1.0)  # Cool alpine moonlight through gable
	c.kit._light.add_lamp(Vector3(-0.90, 2.15,  4.85), LAMP_WARM * 0.95, -1.0)  # Aft entry door & skis lantern

	# 2. Hidden LightmapGI bake omnis & spots (0 live lights!).
	c.glow_lights.append([Vector3(0.0, 4.15, -2.75), LAMP_WARM, 2.4, 9.0])
	c.glow_lights.append([Vector3(0.72, LOFT_Y + 0.75, LOFT_Z0 + 0.92), LAMP_WARM, 1.4, 5.8])
	c.glow_lights.append([Vector3(-4.55, 1.45, -1.28), LAMP_WARM, 1.1, 4.5])
	c.glow_lights.append([Vector3(-0.20, 2.10, BZ - 0.55), LAMP_WARM, 1.0, 4.5])
	# Chandelier downward pool over coffee table & sofas.
	c.spots.append([Vector3(0.0, 4.15, -2.75), Vector3(0.0, 0.0, -0.80), LAMP_WARM, 2.8, 7.5, 44.0])
	# Crisp cool alpine moonlight raking in through the monumental forward gable & port dormer windows!
	c.spots.append([Vector3(-3.8, 7.2, -13.5), Vector3(0.8, 0.0, -4.5), MOON_FILL, 1.2, 18.0, 44.0])
	c.spots.append([Vector3(-10.5, 4.8, -3.5), Vector3(-2.5, 0.0, -3.2), MOON_FILL, 0.7, 14.0, 40.0])


# --- Moonlit Alpine Winter Valley Outside (`AlpineOutside`, 1 opaque draw!) -------------------------------------------

## Hero snow-laden evergreens framing the monumental forward gable view & port dormer window (set back 16-36 m so
## graceful multi-tree alpine conifer silhouettes frame the moonlit valley & jagged peaks cleanly through every pane!).
const HERO_SPRUCES: Array = [
	# Forward-left framing evergreens (seen cleanly across the left gable panes).
	[-9.2, -18.5, 11.2], [-14.2, -21.0, 12.6], [-6.8, -24.5, 10.4], [-18.5, -18.0, 11.8],
	[-11.8, -29.5, 13.4], [-21.0, -28.0, 14.0], [-15.0, -37.0, 14.4], [-5.2, -34.0, 10.8],
	# Forward-right framing evergreens (seen cleanly across the right gable panes).
	[9.0, -18.2, 11.5], [14.5, -21.5, 12.8], [7.0, -25.0, 10.6], [18.8, -18.5, 12.0],
	[12.0, -30.0, 13.6], [21.5, -28.5, 14.2], [15.2, -38.0, 14.6], [5.6, -35.5, 11.0],
	# Port dormer window scenic alpine evergreens (set cleanly back 11-26 m outside x = -5.85 for crisp silhouettes!).
	[-16.5, -7.8, 10.2], [-18.2, -3.2, 11.8], [-15.8, 1.4, 9.6], [-23.0, -9.2, 12.8],
	[-24.2, -1.5, 12.4], [-20.0, 5.2, 10.8], [-29.5, -5.0, 13.8],
	# Mid-valley scattered spruces framing the central alpine meadow corridor toward the Moon & peaks.
	[-8.5, -44.0, 14.2], [9.2, -46.0, 14.6], [-22.0, -42.0, 13.8], [23.5, -41.5, 13.4],
	[-3.8, -52.0, 11.8], [4.6, -54.0, 12.2], [-16.5, -53.0, 14.8], [17.5, -55.0, 14.4],
]


static func _alpine_outside(h: Hall) -> void:
	if h.outside_m == null:
		h.outside_m = ShaderMaterial.new()
		h.outside_m.shader = OUTSIDE_SHADER
		h.outside_m.set_shader_parameter("sky_gain", 1.45)
		h.outside_m.set_shader_parameter("glow", 1.35)
		h.outside_m.set_shader_parameter("glitter", 0.90)
		h.outside_m.set_shader_parameter("haze", 0.0026)
	var b: RoomMesh = h.outside
	b.surface(h.outside_m)
	var noise := FastNoiseLite.new()
	noise.seed = 4618
	noise.frequency = 0.032
	noise.fractal_octaves = 3

	# 1. Sculpted moonlit snowdrift terrain wrapping cleanly OUTSIDE the chalet footprint (never poking inside!).
	var hw_out := HW + 0.15
	var fz_out := FZ - 0.15
	var bz_out := BZ + 0.15
	var centre := Vector2(0.0, (fz_out + bz_out) * 0.5)
	var rings: Array[float] = [0.0, 0.6, 1.6, 3.2, 5.8, 9.5, 15.0, 23.0, 35.0, 52.0, 76.0, 110.0, 148.0]
	const SEGS := 72
	var rows: Array = []
	var normals: Array = []
	var colours: Array = []
	for r: float in rings:
		var row := PackedVector3Array()
		for k in SEGS + 1:
			var a := TAU * float(k % SEGS) / float(SEGS)
			var d := Vector2(cos(a), sin(a))
			var tx := hw_out / maxf(absf(d.x), 1e-4)
			var tz := ((bz_out if d.y > 0.0 else fz_out) - centre.y) / (d.y if absf(d.y) > 1e-4 else 1e-4)
			var edge := minf(tx, absf(tz))
			var q := centre + d * (edge + r)
			row.append(Vector3(q.x, _valley_y(q, hw_out, fz_out, bz_out, noise), q.y))
		rows.append(row)

	for i in rows.size():
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in SEGS + 1:
			var q: Vector3 = rows[i][k]
			var eps := 0.35
			var hx := _valley_y(Vector2(q.x + eps, q.z), hw_out, fz_out, bz_out, noise) \
					- _valley_y(Vector2(q.x - eps, q.z), hw_out, fz_out, bz_out, noise)
			var hz := _valley_y(Vector2(q.x, q.z + eps), hw_out, fz_out, bz_out, noise) \
					- _valley_y(Vector2(q.x, q.z - eps), hw_out, fz_out, bz_out, noise)
			var nrm := Vector3(-hx, 2.0 * eps, -hz).normalized()
			nrow.append(nrm)
			var drift_shade := clampf(0.5 + 0.5 * noise.get_noise_2d(q.x * 0.7, q.z * 0.7), 0.0, 1.0)
			var col := OUT_SNOW_SHADE.lerp(OUT_SNOW, 0.55 + 0.45 * drift_shade)
			crow.append(Color(col.r, col.g, col.b, 1.0))
		normals.append(nrow)
		colours.append(crow)
	b.grid(rows, normals, colours)

	# 2. Towering snow-laden evergreen spruces framing the forward gable & port dormer windows!
	var rng := RandomNumberGenerator.new()
	rng.seed = 4680
	for sp: Array in HERO_SPRUCES:
		var sx := float(sp[0])
		var sz := float(sp[1])
		var sh := float(sp[2])
		var sy := _valley_y(Vector2(sx, sz), hw_out, fz_out, bz_out, noise) - 0.15
		_spruce(b, Vector3(sx, sy, sz), sh, rng, 7)

	# Distant treeline spruces across the snowy forward valley horizon.
	for k in 28:
		var ang := deg_to_rad(rng.randf_range(-62.0, 62.0))
		var dist := rng.randf_range(54.0, 82.0)
		var sx := sin(ang) * dist
		var sz := -cos(ang) * dist
		if absf(sx - 18.0) < 7.0 and absf(sz - (-64.0)) < 7.0:
			continue
		var sy := _valley_y(Vector2(sx, sz), hw_out, fz_out, bz_out, noise) - 0.2
		_spruce(b, Vector3(sx, sy, sz), rng.randf_range(8.5, 14.0), rng, 5)

	# 3. Tiny cozy distant alpine chalet nestled down across the snowy valley with two warm glowing window specks!
	var far_c := Vector2(18.0, -64.0)
	_distant_chalet(b, Vector3(far_c.x, _valley_y(far_c, hw_out, fz_out, bz_out, noise), far_c.y))

	# 4. Dramatic layered moonlit jagged alpine mountain ridges ringing the distant winter horizon (`r = 122..162 m`)!
	_alpine_ridges(b)


static func _valley_y(q: Vector2, hw_out: float, fz_out: float, bz_out: float, noise: FastNoiseLite) -> float:
	var out := Vector2(maxf(absf(q.x) - hw_out, 0.0), maxf(maxf(fz_out - q.y, q.y - bz_out), 0.0)).length()
	var far := smoothstep(5.0, 58.0, out)
	# Gentle snowy valley bowl dipping slightly straight ahead before sweeping up into alpine foothills!
	var valley_dip := -1.8 * smoothstep(10.0, 48.0, -q.y) * exp(-pow(q.x / 36.0, 2.0))
	var climb := 4.5 * smoothstep(46.0, 130.0, out)
	var drift := noise.get_noise_2d(q.x, q.y) * (0.38 + 2.4 * far)
	# Pillowy snowdrifts banked cleanly right up against the outer cabin foundation (`y ~ +0.46 m` at edge).
	var bank := 0.46 * exp(-out / 1.35)
	return -0.08 + drift + bank + valley_dip + climb


static func _out_tri(b: RoomMesh, pts: Array, ns: Array, cols: Array) -> void:
	var rows := [PackedVector3Array([pts[0], pts[0]]), PackedVector3Array([pts[1], pts[2]])]
	var nrm := [PackedVector3Array([ns[0], ns[0]]), PackedVector3Array([ns[1], ns[2]])]
	var c0: Color = cols[0]
	var c1: Color = cols[1]
	var c2: Color = cols[2]
	var col := [PackedColorArray([Color(c0, 1.0), Color(c0, 1.0)]), PackedColorArray([Color(c1, 1.0), Color(c2, 1.0)])]
	b.grid(rows, nrm, col)


static func _out_quad(b: RoomMesh, pts: Array, n: Vector3, col: Color) -> void:
	var rows := [PackedVector3Array([pts[0], pts[1]]), PackedVector3Array([pts[3], pts[2]])]
	var nrm := [PackedVector3Array([n, n]), PackedVector3Array([n, n])]
	var cols := [PackedColorArray([col, col]), PackedColorArray([col, col])]
	b.grid(rows, nrm, cols)


## Sculpted snow-laden alpine spruce: multi-tiered drooping boughs crowned with heavy moonlit snow caps & dark needles.
static func _spruce(b: RoomMesh, foot: Vector3, height: float, rng: RandomNumberGenerator, sides := 7) -> void:
	var tiers := 7 if sides >= 7 else 5
	var turn := rng.randf() * TAU
	for t in tiers:
		var f := float(t) / float(tiers)
		var y0 := foot.y + height * lerpf(0.11, 0.86, f)
		var top := y0 + height * (0.21 if t < tiers - 1 else 0.25)
		var r := height * 0.21 * (1.0 - f * 0.85) * rng.randf_range(0.88, 1.12)
		var rim := PackedVector3Array()
		for k in sides + 1:
			var a := turn + TAU * float(k % sides) / float(sides) + t * 0.42
			var jag := 1.0 if k % 2 == 0 else 0.72
			rim.append(foot + Vector3(cos(a) * r * jag, y0 - foot.y - r * 0.16 * jag, sin(a) * r * jag))
		var apex := Vector3(foot.x, top, foot.z)
		var dark := OUT_NEEDLES.lerp(OUT_SNOW, 0.04)
		var snowy := OUT_SNOW * 1.02
		for k in sides:
			var a0 := rim[k]
			var a1 := rim[k + 1]
			var n := (a1 - a0).cross(apex - a0).normalized()
			if n.y < 0.0:
				n = -n
			var cap := rng.randf_range(0.48, 0.68)
			var m0 := apex.lerp(a0, cap)
			var m1 := apex.lerp(a1, cap)
			_out_tri(b, [apex, m0, m1], [n, n, n], [snowy, snowy, snowy])
			_out_tri(b, [m0, a0, a1], [n, n, n], [OUT_NEEDLES.lerp(OUT_SNOW, 0.42), dark, dark])
			_out_tri(b, [m0, a1, m1], [n, n, n], [OUT_NEEDLES.lerp(OUT_SNOW, 0.42), dark, OUT_NEEDLES.lerp(OUT_SNOW, 0.42)])
	# Trunk base beneath lowest boughs.
	var tr := height * 0.026
	for k in 5:
		var a0 := TAU * float(k) / 5.0
		var a1 := TAU * float(k + 1) / 5.0
		var p0 := foot + Vector3(cos(a0) * tr, 0.0, sin(a0) * tr)
		var p1 := foot + Vector3(cos(a1) * tr, 0.0, sin(a1) * tr)
		var up := Vector3(0.0, height * 0.16, 0.0)
		var n := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		_out_quad(b, [p0, p1, p1 + up, p0 + up], n, Color(OUT_TRUNK, 1.0))


## Tiny cozy A-frame sister cabin far across the snowy winter valley with two glowing warm amber windows.
static func _distant_chalet(b: RoomMesh, foot: Vector3) -> void:
	var fwd := (Vector3(0.0, 0.0, -8.0) - foot)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	var basis := Basis(right, Vector3.UP, fwd)
	var at := func(x: float, y: float, z: float) -> Vector3: return foot + basis * Vector3(x, y, z)
	var w := 4.8
	var d := 4.4
	var h := 4.2
	_out_tri(b, [at.call(-w * 0.5, 0.0, d * 0.5), at.call(w * 0.5, 0.0, d * 0.5), at.call(0.0, h, d * 0.5)],
			[fwd, fwd, fwd], [OUT_CABIN_WOOD, OUT_CABIN_WOOD, OUT_CABIN_WOOD])
	for sd: float in [-1.0, 1.0]:
		var n := (basis * Vector3(sd * h, w * 0.5, 0.0)).normalized()
		_out_quad(b, [
			at.call(0.0, h + 0.18, -d * 0.5 - 0.3),
			at.call(0.0, h + 0.18, d * 0.5 + 0.3),
			at.call(sd * (w * 0.5 + 0.4), -0.2, d * 0.5 + 0.3),
			at.call(sd * (w * 0.5 + 0.4), -0.2, -d * 0.5 - 0.3),
		], n, Color(OUT_SNOW, 1.0))
	# Two tiny warm self-lit amber cabin windows (`COLOR.a = 0.0` triggers self-emission in `env_ice_outside.gdshader`).
	var lit := Color(OUT_CABIN_WIN, 0.0)
	for wx: float in [-0.75, 0.75]:
		_out_quad(b, [
			at.call(wx - 0.38, 0.85, d * 0.5 + 0.04),
			at.call(wx + 0.38, 0.85, d * 0.5 + 0.04),
			at.call(wx + 0.38, 1.68, d * 0.5 + 0.04),
			at.call(wx - 0.38, 1.68, d * 0.5 + 0.04),
		], fwd, lit)


## Layered moonlit jagged alpine mountain ranges ringing the distant winter horizon (`r = 128 m` & `r = 158 m`).
static func _alpine_ridges(b: RoomMesh) -> void:
	const SEGS := 96
	var n1 := FastNoiseLite.new()
	n1.seed = 4810
	n1.frequency = 1.6
	n1.fractal_octaves = 3

	for layer in 2:
		var dist := 132.0 if layer == 0 else 158.0
		var base_h := 14.0 if layer == 0 else 28.0
		var peak_h := 18.0 if layer == 0 else 30.0
		var low := PackedVector3Array()
		var mid := PackedVector3Array()
		var top := PackedVector3Array()
		var nl := PackedVector3Array()
		var nt := PackedVector3Array()
		var cl := PackedColorArray()
		var cm := PackedColorArray()
		var ct := PackedColorArray()

		for k in SEGS + 1:
			var f := float(k % SEGS) / float(SEGS)
			var a := TAU * f
			var d := Vector3(sin(a), 0.0, -cos(a))
			# Dramatic peaked alpine silhouettes straight ahead through the gable window (`d.z < 0`) with a graceful
			# moon-framing saddle right near `moon_bearing` (`sin(a) ~ -0.31`).
			var nv := 0.5 + 0.5 * n1.get_noise_1d(f * (7.5 if layer == 0 else 5.2) + float(layer) * 19.0)
			var jagged := pow(absf(sin(a * (7.0 if layer == 0 else 5.0) + float(layer) * 1.4)), 0.72)
			var hgt := base_h + peak_h * (0.45 * nv + 0.55 * jagged)
			# Carve a subtle scenic valley dip right around the Moon's azimuth so the Moon gleams crisply above the peaks!
			var moon_gap := exp(-pow((d.x + 0.30) / 0.26, 2.0)) * clampf(-d.z, 0.0, 1.0)
			hgt *= lerpf(1.0, 0.58, moon_gap)
			low.append(d * dist + Vector3(0.0, -3.0, 0.0))
			mid.append(d * dist + Vector3(0.0, hgt * 0.42, 0.0))
			top.append(d * (dist + 6.0) + Vector3(0.0, hgt, 0.0))
			var slope_n := (-d + Vector3.UP * (0.55 if layer == 0 else 0.72)).normalized()
			nl.append(-d)
			nt.append(slope_n)
			var rock := OUT_NEEDLES if layer == 0 else OUT_ROCK
			cl.append(Color(rock, 1.0))
			cm.append(Color(OUT_ROCK.lerp(OUT_SNOW_SHADE, 0.45), 1.0))
			ct.append(Color(OUT_SNOW * (0.86 if layer == 0 else 0.96), 1.0))

		b.grid([low, mid], [nl, nl], [cl, cm])
		b.grid([mid, top], [nt, nt], [cm, ct])


# ======================================================================================================================
# Piece 2: cabin_hearth — Monumental River-Stone Chimney, Arched Firebox, Dancing Flames & Fireside Craft
# ======================================================================================================================

static func _hearth(c: Object, h: Hall) -> void:
	_stone_chimney_and_arch(c)
	_mantel_and_garland(c)
	_firebox_logs_and_flames(c, h)
	_fireside_craft_and_wood_alcove(c, h)


## Sculpted river-stone chimney breast (`x = HEARTH_FACE_X..HW`, `z = HEARTH_Z +- 1.10`), arched firebox opening with
## dressed stone voussoirs, raised slate-stone hearth apron (`y = 0.0..0.18`), and tapered chimney stack rising cleanly
## through the 45-degree timber roof with dark-iron roof flashing!
static func _stone_chimney_and_arch(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var stone: Material = c.tinted("stone")
	var iron: Material = c.tinted("iron")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3141

	var fx := HEARTH_FACE_X
	var zc := HEARTH_Z
	var hw := HEARTH_W * 0.5
	var z0 := zc - hw
	var z1 := zc + hw
	var fire_hw := 0.58
	var fz0 := zc - fire_hw
	var fz1 := zc + fire_hw
	var fire_y0 := HEARTH_APRON_Y
	var spring_y := 0.90
	var crown_y := spring_y + 0.34 # 1.24 m arched firebox opening!

	# 1. Stepped raised stone hearth apron slab (`x = HEARTH_APRON_X0..HW`, extending aft cleanly beneath the firewood
	#    alcove to `z = -0.74`, `y = 0..0.18`).
	s.surface(stone)
	s.colour = _lin(HEARTH_SLATE)
	var ap_z0 := z0 - 0.42
	var ap_z1 := -0.74
	var ap_zc := (ap_z0 + ap_z1) * 0.5
	s.box(Vector3((HEARTH_APRON_X0 + HW) * 0.5, HEARTH_APRON_Y * 0.5, ap_zc),
			Vector3(HW - HEARTH_APRON_X0, HEARTH_APRON_Y, ap_z1 - ap_z0), Basis(), [RoomMesh.DOWN, RoomMesh.RIGHT])
	# Slightly overhanging flagstone hearth lip edge slabs.
	s.colour = _lin(HEARTH_SLATE * 1.15)
	s.box(Vector3((HEARTH_APRON_X0 - 0.04 + HW) * 0.5, HEARTH_APRON_Y - 0.025, ap_zc),
			Vector3(HW - HEARTH_APRON_X0 + 0.04, 0.05, ap_z1 - ap_z0 + 0.06), Basis(), [RoomMesh.RIGHT])
	_solid(c, Vector3((HEARTH_APRON_X0 + HW) * 0.5, HEARTH_APRON_Y * 0.5, ap_zc),
			Vector3(HW - HEARTH_APRON_X0, HEARTH_APRON_Y, ap_z1 - ap_z0))

	# 2. Recessed darker mortar backing core of the chimney breast (cut cleanly around firebox opening) & tapered upper stack.
	s.colour = _lin(STONE_MORTAR)
	# Lower chimney breast face (y = fire_y0 .. MANTEL_Y) with firebox opening.
	var f_open := Rect2(z1 - fz1, fire_y0, fz1 - fz0, crown_y - fire_y0)
	Shapes.wall(s, Vector3(fx, 0.0, z1), Vector3.FORWARD, Vector3.LEFT, z1 - z0, MANTEL_Y, [f_open])
	# Side cheeks of lower breast (forward z0, aft z1).
	for sd: float in [-1.0, 1.0]:
		var sz := zc + sd * hw
		s.face([
			Vector3(fx, fire_y0, sz), Vector3(HW, fire_y0, sz),
			Vector3(HW, MANTEL_Y, sz), Vector3(fx, MANTEL_Y, sz),
		], Vector3(0.0, 0.0, sd))
	# Tapered upper river-stone chimney stack rising from mantel (`y = MANTEL_Y`) right up into the 45-deg roof (`y = 3.55`).
	var stack_top := 3.55
	var st_fx := fx + 0.16
	var st_hw0 := hw - 0.06
	var st_hw1 := hw - 0.34
	# Front tapered face facing -X.
	s.face([
		Vector3(fx + 0.02, MANTEL_Y, zc + st_hw0),
		Vector3(fx + 0.02, MANTEL_Y, zc - st_hw0),
		Vector3(st_fx, stack_top, zc - st_hw1),
		Vector3(st_fx, stack_top, zc + st_hw1),
	], Vector3(-1.0, 0.07, 0.0).normalized())
	# Tapered side cheeks (forward -Z and aft +Z).
	for sd: float in [-1.0, 1.0]:
		s.face([
			Vector3(fx + 0.02, MANTEL_Y, zc + sd * st_hw0),
			Vector3(HW, MANTEL_Y, zc + sd * st_hw0),
			Vector3(HW, stack_top, zc + sd * st_hw1),
			Vector3(st_fx, stack_top, zc + sd * st_hw1),
		], Vector3(0.0, 0.08, sd).normalized())

	# Clean physics box enclosing the monumental stone chimney breast.
	_solid(c, Vector3((fx + HW) * 0.5, 1.85, zc), Vector3(HW - fx, 3.70, HEARTH_W))

	# 3. Hand-laid sculpted river-stone boulder courses across the lower breast, upper stack, and cheeks!
	#    Placed into PieceSoft (`c.u`, rounded river cobbles with subtle warm/cool alpine granite colour shifts)
	#    so they stay crisp, smooth, and zero lightmap atlas bloat!
	var soft_stone: Material = c.soft("stone")
	u.surface(soft_stone)
	var stone_palette: Array[Color] = [
		Color(0.46, 0.44, 0.41), Color(0.38, 0.39, 0.40), Color(0.50, 0.45, 0.39),
		Color(0.34, 0.34, 0.35), Color(0.43, 0.40, 0.36), Color(0.52, 0.50, 0.46),
	]
	# Lower courses (y = 0.22 .. 1.62) on the room-facing front.
	var course_h := 0.165
	var n_low := 8
	for row in n_low:
		var cy := fire_y0 + 0.085 + float(row) * course_h
		var z_cur := z0 + 0.04 + (0.09 if row % 2 == 1 else 0.0)
		while z_cur < z1 - 0.12:
			var sw := rng.randf_range(0.22, 0.38)
			var mid_z := z_cur + sw * 0.5
			if mid_z + sw * 0.5 > z1 - 0.02:
				sw = z1 - 0.02 - z_cur
				mid_z = z_cur + sw * 0.5
			# Skip stones overlapping the arched firebox opening (the stone arch voussoirs frame it!).
			var in_open := absf(mid_z - zc) < (fire_hw + 0.08) and cy < (crown_y + 0.06)
			if not in_open and sw > 0.12:
				var col: Color = stone_palette[rng.randi() % stone_palette.size()] * rng.randf_range(0.88, 1.12)
				u.colour = _lin(col)
				var proud := rng.randf_range(0.045, 0.085)
				u.rounded_box(Vector3.ZERO, Vector3(proud + 0.04, course_h - 0.024, sw - 0.022), 0.032,
						Transform3D(Basis(), Vector3(fx - proud * 0.45, cy, mid_z)), 1, Vector3i.ZERO, 0.0,
						[RoomMesh.RIGHT])
			z_cur += sw + 0.015

	# Upper tapered chimney river-stone courses (y = 1.92 .. 3.20, stopping neatly where the 45-deg timber roof meets!).
	for row in 8:
		var cy := MANTEL_Y + 0.24 + float(row) * 0.16
		var frac := clampf((cy - MANTEL_Y) / (stack_top - MANTEL_Y), 0.0, 1.0)
		var cur_fx := lerpf(fx + 0.02, st_fx, frac)
		if cy > _roof_y(cur_fx) + 0.06:
			break
		var cur_hw := lerpf(st_hw0, st_hw1, frac)
		var z_cur := zc - cur_hw + 0.04 + (0.08 if row % 2 == 1 else 0.0)
		while z_cur < zc + cur_hw - 0.10:
			var sw := rng.randf_range(0.22, 0.36)
			if z_cur + sw > zc + cur_hw - 0.03:
				sw = zc + cur_hw - 0.03 - z_cur
			if sw > 0.11:
				var col: Color = stone_palette[rng.randi() % stone_palette.size()] * rng.randf_range(0.88, 1.12)
				u.colour = _lin(col)
				var proud := rng.randf_range(0.04, 0.078)
				u.rounded_box(Vector3.ZERO, Vector3(proud + 0.04, 0.138, sw - 0.022), 0.028,
						Transform3D(Basis(), Vector3(cur_fx - proud * 0.45, cy, z_cur + sw * 0.5)), 1,
						Vector3i.ZERO, 0.0, [RoomMesh.RIGHT])
			z_cur += sw + 0.014

	# River-stone boulder courses on the forward & aft side cheeks of the upper chimney stack so it reads as solid
	# hand-laid alpine masonry from wide/oblique angles too!
	for sd_c: float in [-1.0, 1.0]:
		for row in 7:
			var cy := MANTEL_Y + 0.24 + float(row) * 0.16
			var frac := clampf((cy - MANTEL_Y) / (stack_top - MANTEL_Y), 0.0, 1.0)
			var cur_fx := lerpf(fx + 0.02, st_fx, frac)
			var max_x := minf(HW - 0.06, RIDGE_Y - cy)
			if max_x <= cur_fx + 0.14:
				break
			var cur_hw := lerpf(st_hw0, st_hw1, frac)
			var x_cur := cur_fx + 0.02 + (0.08 if row % 2 == 1 else 0.0)
			while x_cur < max_x - 0.08:
				var sw := rng.randf_range(0.22, 0.34)
				if x_cur + sw > max_x:
					sw = max_x - x_cur
				if sw > 0.10:
					var col: Color = stone_palette[rng.randi() % stone_palette.size()] * rng.randf_range(0.86, 1.10)
					u.colour = _lin(col)
					var proud := rng.randf_range(0.035, 0.065)
					u.rounded_box(Vector3.ZERO, Vector3(sw - 0.02, 0.138, proud + 0.04), 0.026,
							Transform3D(Basis(), Vector3(x_cur + sw * 0.5, cy, zc + sd_c * (cur_hw + proud * 0.35))), 1)
				x_cur += sw + 0.014

	# Sculpted wedge river-stone arch voussoirs & keystone framing the arched firebox opening!
	var arch_n := 11
	var arch_rx := fire_hw + 0.08
	var arch_ry := crown_y - spring_y + 0.06
	for k in arch_n:
		var ang := lerpf(0.06, PI - 0.06, float(k) / float(arch_n - 1))
		var is_key := (k == arch_n / 2)
		var vz := zc - cos(ang) * arch_rx
		var vy := spring_y + sin(ang) * arch_ry
		var rot := Basis(Vector3.RIGHT, ang - PI * 0.5)
		var col: Color = STONE_BASE * (1.16 if is_key else rng.randf_range(0.86, 1.10))
		u.colour = _lin(col)
		var vh := 0.22 if is_key else 0.175
		var vw := 0.16 if is_key else 0.135
		u.rounded_box(Vector3.ZERO, Vector3(0.11 if is_key else 0.085, vh, vw), 0.026,
				Transform3D(rot, Vector3(fx - (0.042 if is_key else 0.032), vy, vz)), 1)

	# Sleek gunmetal iron roof-flashing trim strip hugging the 45-degree timber ceiling penetration cleanly!
	u.surface(_metal(c))
	u.colour = _lin(Color(0.22, 0.21, 0.22))
	var fl_y := _roof_y(fx + 0.14)
	u.box(Vector3(fx + 0.14, fl_y - 0.02, zc), Vector3(0.16, 0.055, st_hw1 * 2.0 + 0.34),
			Basis(Vector3.BACK, -PI * 0.25))


## Thick rough-hewn cedar mantel beam on carved timber corbels, evergreen spruce & pinecone garland with tiny amber
## berry lights, warm brass mantel lantern, and antique ceramic jug.
static func _mantel_and_garland(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood: Material = c.tinted("wood")
	var fx := HEARTH_FACE_X
	var zc := HEARTH_Z
	var mw := HEARTH_W + 0.42
	var m_top := MANTEL_Y + 0.18

	# Thick rough-hewn timber mantel beam (`y = 1.66 .. 1.86 m`) + two heavy timber corbel brackets.
	s.surface(wood)
	s.colour = _lin(FIR_DARK * 1.10)
	s.box(Vector3(fx - 0.14, MANTEL_Y + 0.09, zc), Vector3(0.42, 0.18, mw))
	s.colour = _lin(FIR_TIMBER * 0.88)
	for sd: float in [-0.88, 0.88]:
		s.box(Vector3(fx - 0.10, MANTEL_Y - 0.09, zc + sd), Vector3(0.28, 0.18, 0.18))
		s.box(Vector3(fx - 0.06, MANTEL_Y - 0.20, zc + sd), Vector3(0.18, 0.10, 0.16))

	# Lush evergreen spruce garland draped gracefully along the front lip of the mantel beam + pinecones + fairy lights!
	var rng := RandomNumberGenerator.new()
	rng.seed = 1225
	var g_pts := 18
	for k in g_pts:
		var f := float(k) / float(g_pts - 1)
		var gz := lerpf(zc - mw * 0.45, zc + mw * 0.45, f)
		# Gentle festive double-swag sag along the front of the rough-hewn mantel beam.
		var swag := -0.08 * absf(sin(f * PI * 2.0))
		var gp := Vector3(fx - 0.34, m_top - 0.04 + swag, gz)
		u.surface(c.soft("cloth"))
		u.colour = _lin(SPRUCE_GARLAND * rng.randf_range(0.84, 1.18))
		for j in 3:
			var j_off := Vector3(rng.randf_range(-0.025, 0.025), rng.randf_range(-0.03, 0.03),
					rng.randf_range(-0.05, 0.05))
			u.rounded_box(Vector3.ZERO, Vector3(0.08, 0.075, 0.14), 0.025,
					Transform3D(Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), gp + j_off), 1)
		# Pinecones nestled every 3rd bough cluster.
		if k % 3 == 1:
			u.colour = _lin(PINECONE)
			Shapes.lathe(u, [Vector2(0.01, 0.0), Vector2(0.026, 0.03), Vector2(0.02, 0.06), Vector2(0.0, 0.075)],
					gp + Vector3(-0.035, -0.02, 0.0), 6, Basis(Vector3.BACK, deg_to_rad(35.0)))
		# Tiny warm glowing fairy-amber berry dots tucked along the evergreen garland!
		if k % 2 == 0:
			c.lit.surface(c.shade(LAMP_WARM))
			Shapes.cylinder(c.lit, gp + Vector3(-0.042, 0.0, 0.0), 0.014, 0.022, 6)

	# Warm brass mantel lantern perched on forward mantel end (`z = zc - 0.78`, `y = m_top`).
	_brass_lantern(c, Vector3(fx - 0.14, m_top, zc - 0.78), 0.38, "accent")

	# Vintage glazed alpine stoneware jug (warm cream-ochre stoneware glaze) & brass candlestick at aft mantel end.
	u.surface(_ceramic(c))
	u.colour = _lin(Color(0.76, 0.62, 0.44))
	Shapes.lathe(u, [
		Vector2(0.06, 0.0), Vector2(0.10, 0.08), Vector2(0.095, 0.19),
		Vector2(0.055, 0.27), Vector2(0.065, 0.32), Vector2(0.05, 0.32),
	], Vector3(fx - 0.14, m_top, zc + 0.78), 12)
	u.surface(_metal(c))
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [
		Vector2(0.06, 0.0), Vector2(0.02, 0.04), Vector2(0.016, 0.16), Vector2(0.042, 0.19), Vector2(0.022, 0.21),
	], Vector3(fx - 0.14, m_top, zc + 0.44), 10)
	c.lit.surface(_accent_lamp(c, _hall(c)))
	Shapes.lathe(c.lit, [Vector2(0.016, 0.21), Vector2(0.016, 0.29), Vector2(0.008, 0.34), Vector2(0.0, 0.37)],
			Vector3(fx - 0.14, m_top, zc + 0.44), 8)


## Deep sooted firebox recess, forged-iron andirons/grate, charred stacked split-oak logs, glowing ruby ember bed,
## 14 animated dancing fire tongues (`HearthGlow`), warm flickering hearth rug wash, and soft warm volumetric hearth
## glow cone (`HearthShaft`) + dynamic stand-in firelight lamps!
static func _firebox_logs_and_flames(c: Object, h: Hall) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var fx := HEARTH_FACE_X
	var zc := HEARTH_Z
	var fz0 := zc - 0.58
	var fz1 := zc + 0.58
	var fy0 := HEARTH_APRON_Y
	var fy1 := 1.24
	var depth := 0.72

	# 1. Deep dark soot-blackened firebox cavity (`x = fx .. fx + depth`).
	s.surface(c.tinted("stone"))
	s.colour = _lin(Color(0.16, 0.12, 0.10))
	s.face([
		Vector3(fx + depth, fy0, fz0), Vector3(fx + depth, fy0, fz1),
		Vector3(fx + depth, fy1, fz1), Vector3(fx + depth, fy1, fz0),
	], Vector3.LEFT)
	for sz: float in [fz0, fz1]:
		s.face([
			Vector3(fx, fy0, sz), Vector3(fx + depth, fy0, sz),
			Vector3(fx + depth, fy1, sz), Vector3(fx, fy1, sz),
		], Vector3(0.0, 0.0, 1.0 if sz == fz0 else -1.0))
	s.colour = _lin(SOOT)
	s.face([
		Vector3(fx, fy1, fz0), Vector3(fx + depth, fy1, fz0),
		Vector3(fx + depth, fy1, fz1), Vector3(fx, fy1, fz1),
	], Vector3.DOWN)
	s.colour = _lin(Color(0.12, 0.09, 0.075))
	s.face([
		Vector3(fx, fy0 + 0.002, fz0), Vector3(fx + depth, fy0 + 0.002, fz0),
		Vector3(fx + depth, fy0 + 0.002, fz1), Vector3(fx, fy0 + 0.002, fz1),
	], Vector3.UP)

	# 2. Forged-iron log grate & scrolled andirons (`x = fx + 0.34`).
	var gx := fx + 0.34
	s.surface(c.tinted("iron"))
	s.colour = _lin(IRON)
	for gz: float in [fz0 + 0.18, zc, fz1 - 0.18]:
		s.box(Vector3(gx, fy0 + 0.08, gz), Vector3(0.42, 0.025, 0.025))
		for lx: float in [gx - 0.17, gx + 0.17]:
			s.box(Vector3(lx, fy0 + 0.04, gz), Vector3(0.025, 0.08, 0.025), Basis(), [RoomMesh.DOWN])
	for gz: float in [fz0 + 0.18, fz1 - 0.18]:
		# Front andiron finials.
		s.box(Vector3(fx + 0.09, fy0 + 0.19, gz), Vector3(0.032, 0.38, 0.032), Basis(), [RoomMesh.DOWN])
		u.surface(_metal(c))
		u.colour = _lin(BRASS)
		Shapes.lathe(u, [Vector2(0.02, 0.0), Vector2(0.044, 0.04), Vector2(0.036, 0.075), Vector2(0.0, 0.09)],
				Vector3(fx + 0.09, fy0 + 0.37, gz), 10)

	# 3. Five charred split-oak logs stacked in a rich crisscross fire lay over the ember bed!
	var base := fy0 + 0.10
	u.surface(c.soft("wood"))
	var logs: Array = [
		[Vector3(gx - 0.06, base + 0.055, zc - 0.02), 0.068, 0.84,  0.04,  0.00],
		[Vector3(gx + 0.10, base + 0.060, zc + 0.04), 0.065, 0.80, -0.07,  0.00],
		[Vector3(gx + 0.02, base + 0.165, zc - 0.08), 0.058, 0.72,  0.26,  0.14],
		[Vector3(gx - 0.01, base + 0.185, zc + 0.12), 0.054, 0.68, -0.34, -0.12],
		[Vector3(gx + 0.05, base + 0.275, zc + 0.01), 0.048, 0.62,  0.12, -0.06],
	]
	for lg: Array in logs:
		var centre: Vector3 = lg[0]
		var rad: float = lg[1]
		var length: float = lg[2]
		var lb := Basis(Vector3.UP, float(lg[3])) * Basis(Vector3.BACK, float(lg[4])) * Basis(Vector3.RIGHT, PI * 0.5)
		u.colour = _lin(CHARRED_LOG)
		Shapes.cylinder(u, centre - lb * Vector3(0.0, length * 0.5, 0.0), rad, length, 9, lb, false)
		u.colour = _lin(Color(0.54, 0.34, 0.16))
		for e_s: float in [-0.5, 0.5]:
			var cap: Array = []
			for k in 9:
				var a := TAU * float(k) / 9.0
				cap.append(centre + lb * Vector3(cos(a) * rad, length * e_s, sin(a) * rad))
			u.face(cap, (lb * Vector3(0.0, e_s, 0.0)).normalized())

	# 4. Glowing ember bed, dancing multi-tongue flames & flickering warm firelight washes (`HearthGlow`, 1 draw!).
	var g := h.glow
	# Glowing ruby-orange coal & ember bed beneath the logs (kind 2.0).
	var emb_c := _lin(Color(1.0, 0.36, 0.07))
	emb_c.a = 0.42
	g.quad(Vector3(fx + 0.08, fy0 + 0.018, fz0 + 0.08), Vector3(fx + depth - 0.06, fy0 + 0.018, fz0 + 0.08),
			Vector3(fx + depth - 0.06, fy0 + 0.018, fz1 - 0.08), Vector3(fx + 0.08, fy0 + 0.018, fz1 - 0.08),
			Vector3.UP, emb_c, 2.0)
	_radial(g, Vector3(gx, fy0 + 0.022, zc), Vector3(0.28, 0.0, 0.0), Vector3(0.0, 0.0, 0.44), Vector3.UP,
			_lin(Color(1.0, 0.48, 0.12)), 1.65)
	# Glowing hot core embers nestled right among the split logs (`PieceLamps`, shared `accent` group material).
	c.lit.surface(_accent_lamp(c, h))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4096
	for k in 10:
		var ep := Vector3(gx + rng.randf_range(-0.14, 0.14), fy0 + 0.04 + rng.randf_range(0.0, 0.05),
				zc + rng.randf_range(-0.34, 0.34))
		Shapes.cylinder(c.lit, ep, rng.randf_range(0.032, 0.055), 0.035, 6)

	# 14 crossed-quad animated dancing fire tongues licking warmly upward between the oak logs (kind 1.0)!
	var tongues := 14
	for k in tongues:
		var f := (float(k) + 0.5) / float(tongues)
		var tz := lerpf(fz0 + 0.16, fz1 - 0.16, f) + rng.randf_range(-0.03, 0.03)
		var tx := gx + rng.randf_range(-0.10, 0.10)
		var mid := 1.0 - absf(f * 2.0 - 1.0)
		var hgt := rng.randf_range(0.36, 0.68) * (0.62 + 0.38 * mid)
		var wdt := rng.randf_range(0.18, 0.28)
		var foot := Vector3(tx, base + 0.04, tz)
		var tint := Color(1.0, 0.96, 0.88, rng.randf())
		for turn: float in [0.58, -0.58]:
			var across := Vector3(sin(turn), 0.0, cos(turn)) * wdt * 0.5
			g.quad(foot - across, foot + across, foot + across + Vector3(0.0, hgt, 0.0),
					foot - across + Vector3(0.0, hgt, 0.0), across.cross(Vector3.UP).normalized(), tint, 1.0)

	# Firelight warm radial washes on the back firebox wall, raised stone hearth apron, and the woven Nordic rug!
	_radial(g, Vector3(fx + depth - 0.01, fy0 + 0.42, zc), Vector3(0.0, 0.44, 0.0), Vector3(0.0, 0.0, 0.56),
			Vector3.LEFT, _lin(FIRE_LIGHT) * 0.62, 1.0)
	_radial(g, Vector3((HEARTH_APRON_X0 + fx) * 0.5, fy0 + 0.005, zc), Vector3((fx - HEARTH_APRON_X0) * 0.52, 0.0, 0.0),
			Vector3(0.0, 0.0, 1.05), Vector3.UP, _lin(FIRE_LIGHT) * 0.40, 1.0)
	_radial(g, Vector3(HEARTH_APRON_X0 - 0.95, 0.018, zc + 0.18), Vector3(1.15, 0.0, 0.0), Vector3(0.0, 0.0, 1.65),
			Vector3.UP, _lin(FIRE_LIGHT) * 0.16, 1.0)

	# 5. Soft warm volumetric hearth glow cone radiating gently outward across the Nordic rug (`HearthShaft`, 1 draw!).
	h.shaft.cone(Vector3(fx - 0.05, fy0 + 0.52, zc), Vector3(1.75, 0.08, zc + 0.35), 0.46, 1.35, 18,
			Color(1.0, 0.56, 0.20, 0.55), Color(1.0, 0.44, 0.14, 0.10))

	# 6. Dynamic stand-in hearth lamps (2 slots, scaled live in Hall.tick()!) + bake hearth omni/spot lights!
	h.hearth_lamp_low = c.kit._light.add_lamp(Vector3(fx - 0.42, fy0 + 0.56, zc), FIRE_LIGHT * 3.1, -1.0)
	h.hearth_lamp_high = c.kit._light.add_lamp(Vector3(fx - 1.05, 1.72, zc), FIRE_LIGHT * 1.75, -1.0)
	c.glow_lights.append([Vector3(fx - 0.35, fy0 + 0.48, zc), FIRE_LIGHT, 2.8, 7.5])
	c.glow_lights.append([Vector3(fx + 0.24, fy0 + 0.42, zc), FIRE_LIGHT, 1.6, 2.2])
	c.spots.append([Vector3(fx - 0.15, fy0 + 0.65, zc), Vector3(1.2, 0.0, zc + 0.4), FIRE_LIGHT, 2.6, 6.5, 48.0])


## Wrought-iron folding spark fire screen, gleaming brass fireside poker/tongs/shovel tool stand, steaming burnished
## copper kettle on cast-iron trivet, and neat stacked firewood log alcove tucked beside the chimney!
static func _fireside_craft_and_wood_alcove(c: Object, h: Hall) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var fx := HEARTH_FACE_X
	var zc := HEARTH_Z
	var fy0 := HEARTH_APRON_Y
	var metal: Material = _metal(c)

	# 1. Wrought-iron folding spark fire screen standing cleanly on the stone apron (`x = fx - 0.12`).
	u.surface(c.soft("iron"))
	u.colour = _lin(IRON)
	var scr_x := fx - 0.13
	var scr_h := 0.72
	# Central rectangular arched frame (`z = zc +- 0.52`) + two subtly angled folding side wings.
	for sz: float in [zc - 0.52, zc + 0.52]:
		u.box(Vector3(scr_x, fy0 + scr_h * 0.5, sz), Vector3(0.018, scr_h, 0.018))
	u.box(Vector3(scr_x, fy0 + 0.025, zc), Vector3(0.018, 0.022, 1.06))
	u.box(Vector3(scr_x, fy0 + scr_h, zc), Vector3(0.020, 0.022, 1.06))
	# Slender vertical iron bars leaving rich unobstructed view of the dancing fire tongues!
	for k in 7:
		var bz := lerpf(zc - 0.44, zc + 0.44, float(k) / 6.0)
		u.box(Vector3(scr_x, fy0 + scr_h * 0.5, bz), Vector3(0.008, scr_h - 0.03, 0.008))
	# Folding side wings angled cleanly back toward the river-stone jambs.
	for sd: float in [-1.0, 1.0]:
		var wz0 := zc + sd * 0.52
		var wz1 := zc + sd * 0.68
		var wx1 := fx - 0.02
		var wing_c := Vector3((scr_x + wx1) * 0.5, fy0 + scr_h * 0.5, (wz0 + wz1) * 0.5)
		var wing_dir := Vector3(wx1 - scr_x, 0.0, wz1 - wz0)
		var wb := Basis(Vector3.UP, atan2(wing_dir.x, wing_dir.z))
		var wlen := wing_dir.length()
		u.box(Vector3(wx1, fy0 + scr_h * 0.5, wz1), Vector3(0.016, scr_h, 0.016))
		u.box(wing_c + Vector3(0.0, scr_h * 0.5, 0.0), Vector3(0.016, 0.018, wlen), wb)
		u.box(wing_c + Vector3(0.0, -scr_h * 0.5 + 0.025, 0.0), Vector3(0.016, 0.018, wlen), wb)

	# 2. Gleaming brass fireside poker, shovel & tongs tool stand (`x = fx - 0.42, z = zc - 1.18, y = fy0..0.96`).
	var st_p := Vector3(fx - 0.42, fy0, zc - 1.18)
	u.surface(metal)
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [
		Vector2(0.125, 0.0), Vector2(0.115, 0.025), Vector2(0.055, 0.05), Vector2(0.018, 0.07),
		Vector2(0.015, 0.72), Vector2(0.042, 0.75), Vector2(0.016, 0.78),
	], st_p, 12)
	Shapes.arch(u, st_p + Vector3(0.0, 0.81, 0.0), 0.034, 0.048, 0.014, 12, Basis(Vector3.UP, PI * 0.5), 0.0, TAU)
	# Three hanging fireside tools (poker, tongs, ash shovel) suspended cleanly from the brass rack collar!
	for ti in 3:
		var ang := TAU * float(ti) / 3.0 + 0.5
		var tp := st_p + Vector3(cos(ang) * 0.058, 0.04, sin(ang) * 0.058)
		u.surface(metal)
		u.colour = _lin(BRASS)
		Shapes.cylinder(u, tp + Vector3(0.0, 0.58, 0.0), 0.014, 0.12, 8)
		u.surface(c.soft("iron"))
		u.colour = _lin(IRON)
		Shapes.cylinder(u, tp + Vector3(0.0, 0.04, 0.0), 0.007, 0.54, 6)
		if ti == 2:
			# Ash shovel blade at bottom of tool #3.
			u.box(tp + Vector3(0.0, 0.06, 0.0), Vector3(0.085, 0.11, 0.012))

	# 3. Steaming burnished copper kettle resting cleanly on a cast-iron trivet on the hearth apron (`z = zc + 0.80`)!
	var kp := Vector3(fx - 0.42, fy0, zc + 0.82)
	u.surface(c.soft("iron"))
	u.colour = _lin(IRON)
	Shapes.cylinder(u, kp, 0.115, 0.022, 12)
	# Burnished copper kettle belly, domed lid & brass lid finial.
	u.surface(metal)
	u.colour = _lin(COPPER)
	Shapes.lathe(u, [
		Vector2(0.095, 0.022), Vector2(0.135, 0.075), Vector2(0.138, 0.145),
		Vector2(0.102, 0.205), Vector2(0.068, 0.222), Vector2(0.062, 0.242), Vector2(0.0, 0.258),
	], kp, 16)
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [Vector2(0.010, 0.255), Vector2(0.022, 0.275), Vector2(0.0, 0.292)], kp, 8)
	# Graceful S-curved copper pouring spout angled jauntily forward-left toward the viewer!
	var kb := Basis(Vector3.UP, deg_to_rad(28.0))
	var spout_pts: Array[Vector3] = [
		kp + kb * Vector3(-0.115, 0.095, 0.0),
		kp + kb * Vector3(-0.175, 0.135, 0.0),
		kp + kb * Vector3(-0.205, 0.215, 0.0),
		kp + kb * Vector3(-0.232, 0.248, 0.0),
	]
	u.colour = _lin(COPPER)
	_tube(u, spout_pts, 0.016, 0.018, 8, kb * Vector3.FORWARD)
	# Arched overhead forged-iron carry handle with turned wooden grip.
	u.surface(c.soft("iron"))
	u.colour = _lin(IRON)
	Shapes.arch(u, kp + Vector3(0.0, 0.205, 0.0), 0.115, 0.128, 0.014, 14, kb, 0.0, PI)
	u.surface(c.soft("wood"))
	u.colour = _lin(FIR_DARK)
	Shapes.cylinder(u, kp + kb * Vector3(-0.048, 0.328, 0.0), 0.015, 0.096, 8, kb * Basis(Vector3.BACK, -PI * 0.5))
	# Soft drifting steam ribbon rising from the copper kettle's spout (`HearthShaft`, 1 shared draw!).
	var tip := kp + kb * Vector3(-0.235, 0.26, 0.0)
	h.shaft.cone(tip + Vector3(0.0, 0.42, 0.0), tip, 0.085, 0.024, 10,
			Color(0.95, 0.96, 0.99, 0.18), Color(0.95, 0.96, 0.99, 0.48))

	# 4. Neat recessed firewood log alcove tucked right beside the aft flank of the chimney (`z = -1.65 .. -0.78`)!
	var alc_z0 := zc + HEARTH_W * 0.5 + 0.02 # -1.63
	var alc_z1 := -0.78
	var alc_x0 := fx + 0.14
	var alc_h := 1.24
	s.surface(c.tinted("wood"))
	s.colour = _lin(FIR_DARK)
	# Heavy timber firewood cubby surround framing the stacked logs cleanly against the starboard knee wall.
	s.box(Vector3((alc_x0 + HW) * 0.5, alc_h + 0.04, (alc_z0 + alc_z1) * 0.5),
			Vector3(HW - alc_x0, 0.08, alc_z1 - alc_z0 + 0.08), Basis(), [RoomMesh.RIGHT])
	s.box(Vector3((alc_x0 + HW) * 0.5, (fy0 + alc_h) * 0.5, alc_z1 + 0.03),
			Vector3(HW - alc_x0, alc_h - fy0, 0.06), Basis(), [RoomMesh.DOWN, RoomMesh.RIGHT])
	_solid(c, Vector3((alc_x0 + HW) * 0.5, alc_h * 0.5, (alc_z0 + alc_z1) * 0.5),
			Vector3(HW - alc_x0, alc_h, alc_z1 - alc_z0))

	# 26 tightly stacked split-oak firewood logs with dark bark sides & pale golden end-grain facing into the room!
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var r_log := 0.068
	var ly := fy0 + r_log + 0.005
	var row_i := 0
	var log_len := 0.58
	u.surface(c.soft("wood"))
	while ly + r_log < alc_h - 0.02:
		var lz := alc_z0 + r_log + (0.04 if row_i % 2 == 1 else 0.01)
		while lz + r_log < alc_z1 - 0.02:
			var rr := r_log * rng.randf_range(0.84, 1.06)
			var foot := Vector3(alc_x0 + rng.randf_range(0.0, 0.05), ly, lz)
			u.colour = _lin(BARK_DARK * rng.randf_range(0.85, 1.20))
			Shapes.cylinder(u, foot, rr, log_len, 7, Basis(Vector3.BACK, -PI * 0.5), false)
			u.colour = _lin(LOG_END * rng.randf_range(0.86, 1.12))
			var cap: Array = []
			for k in 7:
				var a := TAU * float(k) / 7.0
				cap.append(foot + Vector3(0.0, cos(a) * rr, sin(a) * rr))
			u.face(cap, Vector3.LEFT)
			lz += r_log * 2.02
		ly += r_log * 1.72
		row_i += 1
