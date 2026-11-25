extends RefCounted

## Cloud temple kit (Other worlds: app/environments/cloud_temple.env.json; docs/environments/rooms/cloud_temple.md).
## A luminous open-air classical white-marble sky-sanctuary suspended serenely above an endless 360-degree
## golden-dusk sea of clouds that deepens into the rising Milky Way over the film.
##
## Pieces (pieces.gd dispatches here):
##   cloud_sanctuary  stepped circular white-marble & warm travertine floating sanctuary platform (r ~ 12.6 m) with
##                    underside carved corbel, inlaid mosaic_medallion plaza, gleaming brass astrolabe floor rings,
##                    16 tall fluted classical columns (h = 6.8 m) carrying a dramatic open broken entablature &
##                    dentil cornice, carved marble seating plinth benches under the temple cushions, shallow
##                    sky-reflecting marble water basin directly before the cinema screen, twin fluted marble screen
##                    pylons with gilt capitals & stepped cornice, four cast-bronze tripod braziers with slow
##                    animated flames, aft gleaming brass armillary astrolabe on a stepped marble altar plinth, and
##                    soft golden architectural uplight coves (PieceCove).
##   cloud_sky_sea    endless 360-degree billowing cloud sea (r = 185 m, env_cloud_sea.gdshader, opaque 1 draw)
##                    curving smoothly to merge with the sky horizon and transitioning from golden sunset to
##                    silver-blue starlight with sky.dusk; four distant floating marble sky-island ruin arches &
##                    obelisks (58-94 m out); and six slanting golden sunset god-ray light shafts through the
##                    sunward outer colonnade bays (env_world_shaft.gdshader, env_see_through).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const CLOUD_SEA_SHADER := preload("res://shaders/env_cloud_sea.gdshader")
const WATER_SHADER := preload("res://shaders/env_world_water.gdshader")
const SHAFT_SHADER := preload("res://shaders/env_world_shaft.gdshader")
const FLAME_SHADER := preload("res://shaders/env_screening_glow.gdshader")

## Sanctuary plan centre (midway between domestic front_z -12.0 and back_z +9.0), plaza floor height (seating plinth
## bench tops sit cleanly at y = 0.0 under the cushions), and major radii.
const CX := 0.0
const CZ := -1.5
const FLOOR_Y := -0.24
const R_OUTER := 12.6
const R_MID := 12.0
const R_DECK := 11.4
const R_COL := 10.35
const R_MOSAIC := 4.2
const COL_H := 6.80
const ENTAB_Y0 := FLOOR_Y + COL_H
const ENTAB_TOP := ENTAB_Y0 + 1.06

## Cinema screen geometry (matches app/environments/cloud_temple.env.json).
const SCREEN_C := Vector3(0.0, 3.05, -11.4)
const SCREEN_W := 6.8
const SCREEN_H := 3.82

## Reflecting water basin bounds (directly beneath and in front of the cinema screen).
const BASIN_X0 := -4.25
const BASIN_X1 := 4.25
const BASIN_Z0 := -10.88
const BASIN_Z1 := -6.28
const WATER_Y := -0.20

## Four bronze tripod brazier centres (well clear of every seat's sight line).
const BRAZIERS: Array[Vector3] = [
	Vector3(-5.65, FLOOR_Y, -6.25),
	Vector3(5.65, FLOOR_Y, -6.25),
	Vector3(-6.35, FLOOR_Y, 2.65),
	Vector3(6.35, FLOOR_Y, 2.65),
]
## Four seating row Z coordinates (domestic: rows_front 1, rows_back 2, row_pitch 1.65).
const SEAT_ROWS: Array[float] = [-1.65, 0.0, 1.65, 3.30]
## Aft astrolabe altar plinth position (framed by the aft colonnade portal).
const ALTAR_AT := Vector3(0.0, FLOOR_Y, 7.05)

## Cloud sea radius (strictly inside SkyDome 190 m and camera far 200 m from every seat).
const SEA_RADIUS := 185.0
const SEA_BASE_Y := -11.5
const SEA_RIM_Y := 2.2

## Slow sub-3 Hz flicker frequencies (photosensitivity ceiling: every frequency < 3 Hz).
const FLICKER_HZ: Array[float] = [0.37, 0.83, 1.31, 2.07]

## Classical marble, travertine, weathered bronze and gilt palette (sRGB; meshes receive linear).
const MARBLE := Color(0.94, 0.91, 0.85)
const MARBLE_WARM := Color(0.88, 0.83, 0.74)
const TRAVERTINE := Color(0.81, 0.74, 0.63)
const MARBLE_SHADE := Color(0.68, 0.63, 0.57)
const SLATE_BACK := Color(0.08, 0.085, 0.11)
const BRONZE := Color(0.24, 0.18, 0.13)
const BRONZE_DARK := Color(0.14, 0.11, 0.085)
const GILT := Color(0.95, 0.76, 0.36)
const EMBER_LIGHT := Color(1.0, 0.62, 0.24)
const SUN_WARM := Color(1.0, 0.76, 0.46)
const UPLIGHT_GLOW := Color(1.0, 0.80, 0.48)


## Hall holding the Cloud temple's custom meshes (CloudSea, SkyIslands, ReflectingBasin, BrazierFlames, SunsetShafts)
## and driving their live dusk, motion, flicker and room-setting responses each frame.
class Hall:
	var kit: Node
	var cloud_sea := Verts.new()
	var sky_islands := Verts.new()
	var water := Verts.new()
	var flames := Verts.new()
	var shafts := Verts.new()

	var cloud_sea_m: ShaderMaterial
	var water_m: ShaderMaterial
	var flame_m: ShaderMaterial
	var shaft_m: ShaderMaterial

	var cloud_sea_mi: MeshInstance3D
	var sky_islands_mi: MeshInstance3D
	var water_mi: MeshInstance3D
	var flames_mi: MeshInstance3D
	var shafts_mi: MeshInstance3D

	var cloud_clock := 0.0
	var water_clock := 0.0
	var flame_clock := 0.0
	var shaft_clock := 0.0
	var flicker_t := 0.0
	var fire_level := 1.0
	var shaft_level := 0.42
	var last_dusk := 0.18
	var last_sky_mood := "sunset_to_stars"
	var sky_mood_held := false
	var _initialized := false

	func finish(k: Node) -> void:
		var noise := SkySys.noise_texture()
		var caustics := Procedural.caustic_map()

		if cloud_sea.count() > 0 or sky_islands.count() > 0:
			cloud_sea_m = ShaderMaterial.new()
			cloud_sea_m.shader = CLOUD_SEA_SHADER
			cloud_sea_m.set_shader_parameter("noise_map", noise)
			cloud_sea_m.set_shader_parameter("sea_radius", SEA_RADIUS)
			if cloud_sea.count() > 0:
				cloud_sea_mi = k._add_mesh("CloudSea", cloud_sea.commit(cloud_sea_m))
				cloud_sea_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				cloud_sea_mi.extra_cull_margin = 256.0
			if sky_islands.count() > 0:
				sky_islands_mi = k._add_mesh("SkyIslands", sky_islands.commit(cloud_sea_m))
				sky_islands_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				sky_islands_mi.extra_cull_margin = 256.0

		if water.count() > 0:
			water_m = ShaderMaterial.new()
			water_m.shader = WATER_SHADER
			water_m.set_shader_parameter("caustic_map", caustics)
			water_m.set_shader_parameter("house_reference", float(k.room.get("ambient_level")))
			water_m.set_shader_parameter("ripple_scale", 1.55)
			water_m.set_shader_parameter("spill_strength", 0.85)
			water_m.set_shader_parameter("ambient_floor", 0.46)
			water_mi = k._add_mesh("ReflectingBasin", water.commit(water_m))
			water_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

		if flames.count() > 0:
			flame_m = ShaderMaterial.new()
			flame_m.shader = FLAME_SHADER
			flame_m.set_shader_parameter("noise_map", noise)
			flame_m.set_shader_parameter("caustic_map", caustics)
			flame_m.set_shader_parameter("pool_level", 0.0)
			flame_m.set_shader_parameter("city_level", 0.0)
			flame_m.set_shader_parameter("fire_level", 1.0)
			flames_mi = k._add_mesh("BrazierFlames", flames.commit(flame_m))
			flames_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			flames_mi.add_to_group("env_see_through")

		if shafts.count() > 0:
			shaft_m = ShaderMaterial.new()
			shaft_m.shader = SHAFT_SHADER
			shaft_m.set_shader_parameter("noise_map", noise)
			shaft_m.set_shader_parameter("shaft_colour", Color(1.0, 0.78, 0.44))
			shaft_m.set_shader_parameter("shaft_level", 0.36)
			shaft_m.set_shader_parameter("edge_softness", 2.35)
			shaft_m.set_shader_parameter("wisp_strength", 0.45)
			shafts_mi = k._add_mesh("SunsetShafts", shafts.commit(shaft_m))
			shafts_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			shafts_mi.add_to_group("env_see_through")

		tick(0.0)

	func tick(delta: float) -> void:
		var host: Node = kit.host
		var sky: Node = host.system_of_kind("sky") if host != null else null

		# 1. Honour live sky_mood setting: let timeline track drive dusk by default, or smoothly hold sunset / starlight.
		if host != null and host.has_method("setting") and sky != null:
			var mood := str(host.setting("sky_mood"))
			if mood == "":
				mood = "sunset_to_stars"
			if mood != last_sky_mood:
				last_sky_mood = mood
				if mood == "golden_dusk":
					host.fade("sky.dusk", 0.18, 1.5)
					sky_mood_held = true
				elif mood == "starlight_clouds":
					host.fade("sky.dusk", 0.92, 1.5)
					sky_mood_held = true
				else:
					if sky_mood_held:
						host.release("sky.dusk", 1.5)
						sky_mood_held = false

		# 2. Read current sky state and advance motion-scaled clocks.
		var dusk := 0.18
		var glow_dir := Vector3(0.743, 0.0, -0.669)
		var glow_col := Color("#ff9a4a")
		var tw_zen := Color("#233878")
		var tw_hor := Color("#ea8652")
		var belt_col := Color("#b05e76")
		var nt_zen := Color("#050814")
		var nt_hor := Color("#121a30")
		var afterglow := 0.90
		if sky != null:
			dusk = clampf(float(sky.params.get("dusk", 0.18)), 0.0, 1.0)
			glow_dir = sky.glow_direction()
			glow_col = sky.color_param("glow")
			tw_zen = sky.color_param("twilight_zenith")
			tw_hor = sky.color_param("twilight_horizon")
			belt_col = sky.color_param("belt_colour")
			nt_zen = sky.color_param("night_zenith")
			nt_hor = sky.color_param("night_horizon")
			afterglow = float(sky.params.get("afterglow", 0.90))
		last_dusk = dusk

		var motion := float(kit.params.get("water_motion", 1.0))
		cloud_clock += delta * motion
		water_clock += delta * motion
		shaft_clock += delta * motion
		flame_clock += delta * (0.25 + 0.75 * motion)
		flicker_t += delta

		if cloud_sea_m != null:
			cloud_sea_m.set_shader_parameter("clock", cloud_clock)
			cloud_sea_m.set_shader_parameter("dusk", dusk)
			cloud_sea_m.set_shader_parameter("afterglow", afterglow)
			cloud_sea_m.set_shader_parameter("glow_dir", glow_dir)
			cloud_sea_m.set_shader_parameter("glow_colour", glow_col)
			cloud_sea_m.set_shader_parameter("twilight_zenith", tw_zen)
			cloud_sea_m.set_shader_parameter("twilight_horizon", tw_hor)
			cloud_sea_m.set_shader_parameter("belt_colour", belt_col)
			cloud_sea_m.set_shader_parameter("night_zenith", nt_zen)
			cloud_sea_m.set_shader_parameter("night_horizon", nt_hor)
		if cloud_sea_mi != null:
			cloud_sea_mi.set_meta("dusk", dusk)
			cloud_sea_mi.set_meta("clock", cloud_clock)

		# 3. Sync reflecting basin palette with golden sunset -> starlight night (jewel twilight-azure mirror water).
		if water_m != null:
			var dk := smoothstep(0.08, 0.94, dusk)
			water_m.set_shader_parameter("clock", water_clock)
			water_m.set_shader_parameter("deep_colour", Color(0.025, 0.085, 0.22).lerp(Color(0.014, 0.032, 0.088), dk))
			water_m.set_shader_parameter("shallow_colour", Color(0.06, 0.23, 0.38).lerp(Color(0.042, 0.095, 0.20), dk))
			water_m.set_shader_parameter("sky_colour", Color(0.56, 0.42, 0.50).lerp(Color(0.16, 0.26, 0.50), dk))
			water_m.set_shader_parameter("caustic_colour", Color(1.0, 0.80, 0.42).lerp(Color(0.46, 0.68, 1.0), dk))
			water_m.set_shader_parameter("caustic_level", lerpf(1.35, 0.75, dk))
			water_m.set_shader_parameter("glint_dir", Vector3(glow_dir.x, 0.36, glow_dir.z).normalized())
			water_m.set_shader_parameter("glint_colour", Color(1.0, 0.84, 0.48).lerp(Color(0.70, 0.82, 1.0), dk))
			water_m.set_shader_parameter("glint_level", lerpf(1.35, 0.52, dk))

		# 4. Bronze brazier flames: follow accent level (bound to setting.braziers) + slow sub-3 Hz flicker.
		var steady: bool = host != null and host.has_method("setting") and host.setting("flicker") == false
		var w := 0.0
		if not steady:
			for i in FLICKER_HZ.size():
				w += sin(TAU * FLICKER_HZ[i] * flicker_t + 1.1 * (i + 1)) / float(i + 1)
		var brazier_mode := str(host.setting("braziers")) if (host != null and host.has_method("setting")) else "lit"
		var accent: float = kit._group_level("accent")
		fire_level = maxf(0.0, accent * (1.0 + 0.10 * float(kit.params.get("flicker", 0.0)) * w))
		if flame_m != null:
			flame_m.set_shader_parameter("flame_clock", flame_clock)
			flame_m.set_shader_parameter("fire_level", fire_level)
		if flames_mi != null:
			flames_mi.visible = fire_level > 0.005
			flames_mi.set_meta("fire_level", fire_level)
			flames_mi.set_meta("brazier_mode", brazier_mode)

		# 5. Sunset god-ray light shafts: controlled by setting.god_rays and fade gracefully as dusk falls.
		var rays_mode := str(host.setting("god_rays")) if (host != null and host.has_method("setting")) else "soft"
		var sunset_k := 1.0 - smoothstep(0.18, 0.82, dusk)
		var target_shaft := (0.36 * sunset_k) if rays_mode == "soft" else 0.0
		if not _initialized or delta <= 0.0:
			shaft_level = target_shaft
		else:
			shaft_level = lerpf(shaft_level, target_shaft, 1.0 - exp(-delta * 2.2))
		if shaft_m != null:
			shaft_m.set_shader_parameter("clock", shaft_clock)
			shaft_m.set_shader_parameter("shaft_level", shaft_level)
			shaft_m.set_shader_parameter("shaft_colour", Color(1.0, 0.72, 0.38).lerp(Color(0.92, 0.48, 0.34),
					clampf(dusk * 1.1, 0.0, 1.0)))
		if shafts_mi != null:
			shafts_mi.visible = shaft_level > 0.004
			shafts_mi.set_meta("shaft_level", shaft_level)

		_initialized = true


## Compact indexed mesh builder for the Cloud temple's custom shader surfaces.
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

	func box(centre: Vector3, size: Vector3, basis: Basis, col: Color, kind := 1.0, skip: Array = []) -> void:
		var h := size * 0.5
		for fn: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK]:
			if fn in skip:
				continue
			var a1 := Vector3(fn.y, fn.z, fn.x).abs()
			var a2 := fn.cross(a1).abs()
			var p0 := centre + basis * (fn * h - a1 * h - a2 * h)
			var p1 := centre + basis * (fn * h + a1 * h - a2 * h)
			var p2 := centre + basis * (fn * h + a1 * h + a2 * h)
			var p3 := centre + basis * (fn * h - a1 * h + a2 * h)
			quad(p0, p1, p2, p3, (basis * fn).normalized(), col, kind)

	func cylinder(base: Vector3, r0: float, r1: float, height: float, sides: int, col: Color, kind := 1.0,
			caps := true) -> void:
		for k in sides:
			var a0 := TAU * float(k) / sides
			var a1 := TAU * float((k + 1) % sides) / sides
			var d0 := Vector3(sin(a0), 0.0, cos(a0))
			var d1 := Vector3(sin(a1), 0.0, cos(a1))
			var p0 := base + d0 * r0
			var p1 := base + d1 * r0
			var p2 := base + d1 * r1 + Vector3(0.0, height, 0.0)
			var p3 := base + d0 * r1 + Vector3(0.0, height, 0.0)
			var nrm := ((d0 + d1) * 0.5 * height + Vector3.UP * (r0 - r1)).normalized()
			quad(p0, p1, p2, p3, nrm, col, kind)
		if caps:
			var top_c := base + Vector3(0.0, height, 0.0)
			for k in sides:
				var a0 := TAU * float(k) / sides
				var a1 := TAU * float((k + 1) % sides) / sides
				var t0 := vert(top_c, Vector3.UP, col, Vector2.ZERO, kind)
				var t1 := vert(top_c + Vector3(sin(a1) * r1, 0.0, cos(a1) * r1), Vector3.UP, col, Vector2.ZERO, kind)
				var t2 := vert(top_c + Vector3(sin(a0) * r1, 0.0, cos(a0) * r1), Vector3.UP, col, Vector2.ZERO, kind)
				idx.append_array([t0, t1, t2])

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
		"cloud_sanctuary":
			_sanctuary(c, h)
		"cloud_sky_sea":
			_sky_sea(c, h)
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove]:
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

static func _lin(colour: Color, alpha := 1.0) -> Color:
	var l := colour.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _gilt(c: Object) -> Material:
	return c.shiny("gilt", 1.0, 0.78, 0.22)


static func _solid(c: Object, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, basis))


## 16 column azimuths around (CX, CZ), 8 on the left arc and 8 on the right arc, framing the wide front screen
## opening (+-27 deg) and the aft astrolabe portal (+-168 deg).
static func column_azimuths() -> Array[float]:
	var out: Array[float] = []
	for side: float in [-1.0, 1.0]:
		for i in 8:
			var deg := lerpf(27.0, 168.0, float(i) / 7.0)
			out.append(deg_to_rad(side * deg))
	return out


static func _ring_pt(r: float, az: float, y: float) -> Vector3:
	return Vector3(CX + sin(az) * r, y, CZ - cos(az) * r)


# --- Piece 1: cloud_sanctuary -----------------------------------------------------------------------------------------

static func _sanctuary(c: Object, h: Hall) -> void:
	# Compact lightmap atlas (keeps build fast and well under MAX_ATLAS = 2048).
	c.s.texel = 0.16
	_platform(c)
	_colonnade(c)
	_seating_plinths(c)
	_screen_and_basin(c, h)
	_braziers(c, h)
	_aft_astrolabe(c)
	_sanctuary_lights(c)


## Stepped circular white-marble & warm travertine floating sanctuary platform with underside carved corbel, central
## mosaic_medallion plaza, and concentric gleaming inlaid brass astrolabe floor rings.
static func _platform(c: Object) -> void:
	var stone: Material = c.tinted("stone")
	var mosaic: ShaderMaterial = c.tinted("plaster", "mosaic_medallion")
	# Fit the concentric jade-and-gold medallion circle (r_uv <= 0.86) cleanly inside the circular brass floor ring.
	var med_tiling := R_MOSAIC * 2.0 / 0.86
	mosaic.set_shader_parameter("tiling", med_tiling)
	mosaic.set_shader_parameter("uv_offset", Vector2(0.5 - CX / med_tiling, 0.5 - CZ / med_tiling))
	var gilt: Material = _gilt(c)
	var sides := 32

	# 1. Underside floating stepped marble corbel (gives monumental stone mass hovering above the clouds).
	c.s.surface(stone)
	c.s.colour = _lin(MARBLE_SHADE)
	var corbel_prof: Array = [
		Vector2(5.2, -2.18), Vector2(7.8, -1.85), Vector2(9.6, -1.48),
		Vector2(11.4, -1.08), Vector2(R_OUTER, -0.68),
	]
	Shapes.lathe(c.s, corbel_prof, Vector3(CX, 0.0, CZ), sides)
	# Flat bottom soffit cap.
	var bot: Array = []
	for k in sides:
		var a := TAU * float(k) / sides
		bot.append(Vector3(CX + sin(a) * 5.2, -2.18, CZ + cos(a) * 5.2))
	c.s.face(bot, Vector3.DOWN)

	# 2. Three classical crepidoma marble steps rising to the stylobate deck (FLOOR_Y = -0.24).
	var steps: Array = [
		[R_OUTER, -0.68, -0.52, TRAVERTINE],
		[R_MID, -0.52, -0.38, MARBLE_WARM],
		[R_DECK, -0.38, FLOOR_Y, MARBLE],
	]
	for st: Array in steps:
		var r := float(st[0])
		var y0 := float(st[1])
		var y1 := float(st[2])
		var col: Color = st[3]
		c.s.colour = _lin(col * 0.90)
		Shapes.lathe(c.s, [Vector2(r, y0), Vector2(r, y1)], Vector3(CX, 0.0, CZ), sides)

	# Annular horizontal step treads (Step 1 -> Step 2, Step 2 -> Step 3, and stylobate outer promenade).
	_annulus_top(c.s, stone, R_MID, R_OUTER, -0.52, sides, TRAVERTINE)
	_annulus_top(c.s, stone, R_DECK, R_MID, -0.38, sides, MARBLE_WARM)
	_annulus_top(c.s, stone, R_MOSAIC, R_DECK, FLOOR_Y, sides, MARBLE)

	# Low carved marble outer coping curb around the stylobate perimeter (open at front & aft views).
	c.s.surface(stone)
	c.s.colour = _lin(MARBLE_WARM)
	for side: float in [-1.0, 1.0]:
		_curved_band(c.s, R_DECK - 0.34, R_DECK - 0.04, FLOOR_Y, FLOOR_Y + 0.12,
				deg_to_rad(side * 24.0), deg_to_rad(side * 170.0), 22)

	# 3. Central mosaic_medallion circular plaza (r = 4.2 m centred at (CX, CZ)).
	c.s.surface(mosaic)
	c.s.colour = _lin(Color(0.84, 0.80, 0.72))
	var med: Array = []
	for k in sides:
		var a := TAU * float(k) / sides
		med.append(Vector3(CX + sin(a) * R_MOSAIC, FLOOR_Y + 0.002, CZ + cos(a) * R_MOSAIC))
	c.s.face(med, Vector3.UP)

	# 4. Concentric inlaid brass astrolabe floor rings & radial compass spokes (cleanly clear of the reflecting basin!).
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	# Full inner medallion border ring (r = R_MOSAIC) and outer colonnade floor ring (r = 9.30, broken at basin).
	_annulus_top(c.u, gilt, R_MOSAIC - 0.042, R_MOSAIC + 0.042, FLOOR_Y + 0.006, 48, GILT)
	_annulus_arc_top(c.u, gilt, 6.65 - 0.032, 6.65 + 0.032, FLOOR_Y + 0.006, deg_to_rad(46.0), deg_to_rad(314.0), 40, GILT)
	_annulus_arc_top(c.u, gilt, 9.30 - 0.042, 9.30 + 0.042, FLOOR_Y + 0.006, deg_to_rad(32.0), deg_to_rad(328.0), 44, GILT)
	# 7 radial astrolabe compass lines clear of the front basin sector (|az| >= 58 deg) & pointing aft to the astrolabe.
	for deg: float in [-148.0, -104.0, -58.0, 58.0, 104.0, 148.0, 180.0]:
		var az := deg_to_rad(deg)
		var r0 := R_MOSAIC + 0.042
		var r1 := 9.26
		var dir := Vector3(sin(az), 0.0, -cos(az))
		var side_v := Vector3(dir.z, 0.0, -dir.x) * 0.024
		var p0 := Vector3(CX, FLOOR_Y + 0.006, CZ) + dir * r0
		var p1 := Vector3(CX, FLOOR_Y + 0.006, CZ) + dir * r1
		c.u.face([p0 - side_v, p0 + side_v, p1 + side_v, p1 - side_v], Vector3.UP)


static func _annulus_arc_top(b: RoomMesh, mat: Material, r_in: float, r_out: float, y: float, az0: float, az1: float,
		segs: int, col: Color) -> void:
	b.surface(mat)
	b.colour = _lin(col)
	var a := PackedVector3Array()
	var bb := PackedVector3Array()
	var ns := PackedVector3Array()
	for k in segs + 1:
		var az := lerpf(az0, az1, float(k) / segs)
		var dir := Vector3(sin(az), 0.0, -cos(az))
		a.append(Vector3(CX, y, CZ) + dir * r_in)
		bb.append(Vector3(CX, y, CZ) + dir * r_out)
		ns.append(Vector3.UP)
	b.strip(a, bb, ns)


static func _annulus_top(b: RoomMesh, mat: Material, r_in: float, r_out: float, y: float, sides: int,
		col: Color) -> void:
	b.surface(mat)
	b.colour = _lin(col)
	var a := PackedVector3Array()
	var bb := PackedVector3Array()
	var ns := PackedVector3Array()
	for k in sides + 1:
		var ang := TAU * float(k % sides) / sides
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		a.append(Vector3(CX, y, CZ) + dir * r_in)
		bb.append(Vector3(CX, y, CZ) + dir * r_out)
		ns.append(Vector3.UP)
	b.strip(a, bb, ns)


static func _curved_band(b: RoomMesh, r_in: float, r_out: float, y0: float, y1: float, az0: float, az1: float,
		segs: int) -> void:
	var a0 := minf(az0, az1)
	var a1 := maxf(az0, az1)
	var i0 := PackedVector3Array()
	var i1 := PackedVector3Array()
	var o0 := PackedVector3Array()
	var o1 := PackedVector3Array()
	var nin := PackedVector3Array()
	var nout := PackedVector3Array()
	var nup := PackedVector3Array()
	var ndn := PackedVector3Array()
	for k in segs + 1:
		var az := lerpf(a0, a1, float(k) / segs)
		var d := Vector3(sin(az), 0.0, -cos(az))
		i0.append(Vector3(CX, y0, CZ) + d * r_in)
		i1.append(Vector3(CX, y1, CZ) + d * r_in)
		o0.append(Vector3(CX, y0, CZ) + d * r_out)
		o1.append(Vector3(CX, y1, CZ) + d * r_out)
		nin.append(-d)
		nout.append(d)
		nup.append(Vector3.UP)
		ndn.append(Vector3.DOWN)
	b.strip(i0, i1, nin)
	b.strip(o0, o1, nout)
	b.strip(i1, o1, nup)
	b.strip(i0, o0, ndn)
	# End caps.
	for end_i: int in [0, segs]:
		var az := a0 if end_i == 0 else a1
		var tang := Vector3(-cos(az), 0.0, -sin(az)) * (1.0 if end_i == 0 else -1.0)
		b.face([i0[end_i], o0[end_i], o1[end_i], i1[end_i]], tang)


## 16 tall fluted white-marble classical columns (h = 6.8 m) ringing the sanctuary, carrying a dramatic open broken
## entablature with triglyph frieze, dentil cornice, acroteria finials, and warm architectural uplight coves.
static func _colonnade(c: Object) -> void:
	var stone: Material = c.tinted("stone")
	var gilt: Material = _gilt(c)
	var cove_m: Material = c.kit.cove_material()
	var uplight_m: Material = c.shade(UPLIGHT_GLOW)

	for az: float in column_azimuths():
		var base := _ring_pt(R_COL, az, FLOOR_Y)
		var into := Vector3(-sin(az), 0.0, cos(az)).normalized()
		var tang := Vector3(cos(az), 0.0, sin(az)).normalized()
		var col_basis := Basis(tang, Vector3.UP, into)
		_fluted_column(c, stone, gilt, cove_m, uplight_m, base, col_basis, COL_H, 0.40)
		_solid(c, base + Vector3(0.0, COL_H * 0.5, 0.0), Vector3(0.92, COL_H, 0.92), col_basis)

	# Open broken classical entablature running along left and right arcs (open overhead & open at front/aft!).
	for side: float in [-1.0, 1.0]:
		var a0 := deg_to_rad(side * 25.5)
		var a1 := deg_to_rad(side * 169.5)
		# 1. Architrave beam + recessed golden architectural soffit cove along its underside.
		c.s.surface(stone)
		c.s.colour = _lin(MARBLE)
		_curved_band(c.s, R_COL - 0.44, R_COL + 0.44, ENTAB_Y0, ENTAB_Y0 + 0.40, a0, a1, 24)
		c.cove.surface(cove_m)
		var sf_rows: Array = []
		var sf_norms: Array = []
		var sf_cols: Array = []
		for r_def: Array in [[R_COL - 0.40, 0.18], [R_COL - 0.16, 0.85], [R_COL + 0.14, 0.72], [R_COL + 0.36, 0.12]]:
			var rr := float(r_def[0])
			var w := float(r_def[1])
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for k in 25:
				var az := lerpf(minf(a0, a1), maxf(a0, a1), float(k) / 24.0)
				row.append(_ring_pt(rr, az, ENTAB_Y0 - 0.004))
				nrow.append(Vector3.DOWN)
				crow.append(_lin(MARBLE, w))
			sf_rows.append(row)
			sf_norms.append(nrow)
			sf_cols.append(crow)
		c.cove.grid(sf_rows, sf_norms, sf_cols)
		# Golden taenia moulding band along inner architrave lip.
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		_curved_band(c.u, R_COL - 0.47, R_COL - 0.43, ENTAB_Y0 + 0.36, ENTAB_Y0 + 0.42, a0, a1, 24)
		# 2. Recessed warm-travertine frieze.
		c.s.surface(stone)
		c.s.colour = _lin(TRAVERTINE)
		_curved_band(c.s, R_COL - 0.39, R_COL + 0.39, ENTAB_Y0 + 0.40, ENTAB_Y0 + 0.80, a0, a1, 24)
		# Projecting marble triglyphs & gilt metope rosettes along the frieze (neatly inset from broken ends).
		var ta0 := lerpf(a0, a1, 0.025)
		var ta1 := lerpf(a0, a1, 0.975)
		for k in 15:
			var az := lerpf(ta0, ta1, float(k) / 14.0)
			var p := _ring_pt(R_COL - 0.42, az, ENTAB_Y0 + 0.60)
			var into := Vector3(-sin(az), 0.0, cos(az)).normalized()
			var tang := Vector3(cos(az), 0.0, sin(az)).normalized()
			var b := Basis(tang, Vector3.UP, into)
			c.s.surface(stone)
			c.s.colour = _lin(MARBLE)
			c.s.box(p, Vector3(0.24, 0.36, 0.09), b, [RoomMesh.FRONT])
			if k < 14:
				var az_m := lerpf(ta0, ta1, (float(k) + 0.5) / 14.0)
				var pm := _ring_pt(R_COL - 0.40, az_m, ENTAB_Y0 + 0.60)
				var bm := Basis(Vector3(cos(az_m), 0.0, sin(az_m)), Vector3.UP, Vector3(-sin(az_m), 0.0, cos(az_m)))
				c.u.surface(gilt)
				c.u.colour = _lin(GILT)
				c.u.box(pm, Vector3(0.11, 0.11, 0.04), bm * Basis(Vector3.BACK, PI * 0.25))
		# 3. Projecting upper dentil cornice.
		c.s.surface(stone)
		c.s.colour = _lin(MARBLE)
		_curved_band(c.s, R_COL - 0.60, R_COL + 0.56, ENTAB_Y0 + 0.80, ENTAB_TOP, a0, a1, 24)
		# Crisp rhythmic dentils under the inner cornice lip.
		c.s.colour = _lin(MARBLE_WARM)
		for k in 27:
			var az := lerpf(ta0, ta1, (float(k) + 0.5) / 27.0)
			var pd := _ring_pt(R_COL - 0.49, az, ENTAB_Y0 + 0.77)
			var bd := Basis(Vector3(cos(az), 0.0, sin(az)), Vector3.UP, Vector3(-sin(az), 0.0, cos(az)))
			c.s.box(pd, Vector3(0.14, 0.09, 0.16), bd, [RoomMesh.UP])
		# Sculpted gilt acroteria palmette finials centred squarely above both end columns (27 deg and 168 deg).
		for end_az: float in [deg_to_rad(side * 27.0), deg_to_rad(side * 168.0)]:
			var pe := _ring_pt(R_COL, end_az, ENTAB_TOP)
			var be := Basis(Vector3(cos(end_az), 0.0, sin(end_az)), Vector3.UP, Vector3(-sin(end_az), 0.0, cos(end_az)))
			c.s.surface(stone)
			c.s.colour = _lin(MARBLE)
			c.s.box(pe + Vector3(0.0, 0.12, 0.0), Vector3(0.48, 0.24, 0.48), be, [RoomMesh.DOWN])
			c.u.surface(gilt)
			c.u.colour = _lin(GILT)
			Shapes.lathe(c.u, [Vector2(0.18, 0.24), Vector2(0.09, 0.38), Vector2(0.22, 0.56), Vector2(0.0, 0.78)],
					pe, 10, be)


## Single classical 16-flute white-marble column with Attic base, subtle entasis taper, gilt astragal necking collar,
## Doric/Ionic echinus + bolster scrolls, square abacus, and soft golden uplight cove washing up the lower shaft.
static func _fluted_column(c: Object, stone: Material, gilt: Material, cove_m: Material, uplight_m: Material,
		base: Vector3, basis: Basis, h: float, r0: float) -> void:
	# Square plinth + Attic double-torus base.
	c.s.surface(stone)
	c.s.colour = _lin(MARBLE_WARM)
	c.s.box(base + Vector3(0.0, 0.08, 0.0), Vector3(r0 * 2.55, 0.16, r0 * 2.55), basis, [RoomMesh.DOWN])
	c.s.colour = _lin(MARBLE)
	Shapes.lathe(c.s, [
		Vector2(r0 * 1.24, 0.16), Vector2(r0 * 1.28, 0.22), Vector2(r0 * 1.12, 0.27),
		Vector2(r0 * 1.16, 0.32), Vector2(r0 * 1.02, 0.38),
	], base, 14, basis)

	# 16-flute classical shaft with entasis, split into two 180-deg non-overlapping UV2 sheets for clean baking.
	var flutes := 16
	var n_ang := flutes * 2
	var y_top := h - 0.66
	var stations: Array = [
		[0.38, r0 * 1.00],
		[lerpf(0.38, y_top, 0.32), r0 * 0.965],
		[lerpf(0.38, y_top, 0.68), r0 * 0.90],
		[y_top, r0 * 0.825],
	]
	c.s.surface(stone)
	for half in 2:
		var j_start := half * flutes
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		for st: Array in stations:
			var yy := float(st[0])
			var rad := float(st[1])
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for step_j in flutes + 1:
				var k := (j_start + step_j) % n_ang
				var ang := TAU * float(k) / n_ang - PI * 0.5
				var hollow := (k % 2 == 1)
				var rr := rad - (0.028 if hollow else 0.0)
				var d := Vector3(sin(ang), 0.0, cos(ang))
				row.append(base + basis * (d * rr + Vector3.UP * yy))
				nrow.append((basis * d).normalized())
				var shade := 0.83 if hollow else 1.0
				var v_ao := 0.92 + 0.08 * sin(PI * clampf((yy - 0.38) / (y_top - 0.38), 0.0, 1.0))
				crow.append(_lin(MARBLE * shade * v_ao))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		c.s.sheet(rows, norms, cols, basis.x * (1.0 if half == 0 else -1.0), Vector3.UP)

	# Gilt brass astragal necking ring right beneath the capital.
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	var rn := r0 * 0.825
	Shapes.lathe(c.u, [
		Vector2(rn, y_top), Vector2(rn + 0.036, y_top + 0.03), Vector2(rn + 0.036, y_top + 0.065),
		Vector2(rn, y_top + 0.09),
	], base, 14, basis)

	# Carved marble echinus bell + Ionic bolster drums + square abacus.
	c.s.surface(stone)
	c.s.colour = _lin(MARBLE)
	Shapes.lathe(c.s, [
		Vector2(rn, y_top + 0.09), Vector2(rn * 1.06, y_top + 0.16),
		Vector2(r0 * 1.18, y_top + 0.42), Vector2(r0 * 1.24, y_top + 0.50),
	], base, 14, basis)
	# Twin Ionic bolster volute rolls on the tangential sides of the capital.
	c.s.colour = _lin(MARBLE_WARM)
	var vol_basis := basis * Basis(Vector3.RIGHT, PI * 0.5)
	for sd: float in [-1.0, 1.0]:
		var vc := base + basis * Vector3(sd * r0 * 1.02, y_top + 0.40, 0.0)
		Shapes.cylinder(c.s, vc - basis.z * (r0 * 0.92), 0.145, r0 * 1.84, 10, vol_basis)
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		c.u.box(vc + basis.z * (r0 * 0.94), Vector3(0.11, 0.11, 0.025), basis * Basis(Vector3.BACK, PI * 0.25))
	c.s.surface(stone)
	c.s.colour = _lin(MARBLE)
	c.s.box(base + Vector3(0.0, h - 0.075, 0.0), Vector3(r0 * 2.62, 0.15, r0 * 2.62), basis)

	# Recessed golden architectural light-channel tucked cleanly inside the Attic plinth base (never hiding flutes!).
	c.cove.surface(cove_m)
	var cove_rows: Array = []
	var cove_norms: Array = []
	var cove_cols: Array = []
	for c_def: Array in [[0.162, r0 * 1.24, 0.92], [0.225, r0 * 1.13, 0.58], [0.295, r0 * 1.15, 0.12]]:
		var yy := float(c_def[0])
		var rad := float(c_def[1]) + 0.008
		var w := float(c_def[2])
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for j in 13:
			var ang := TAU * float(j % 12) / 12.0
			var d := Vector3(sin(ang), 0.0, cos(ang))
			row.append(base + basis * (d * rad + Vector3.UP * yy))
			nrow.append((basis * d).normalized())
			crow.append(_lin(MARBLE, w))
		cove_rows.append(row)
		cove_norms.append(nrow)
		cove_cols.append(crow)
	c.cove.grid(cove_rows, cove_norms, cove_cols)

	# Small recessed warm-gold uplight lens tucked into the inward plinth rim (PieceLamps, house group).
	c.lit.surface(uplight_m)
	var lp := base + basis * Vector3(0.0, 0.165, r0 * 1.18)
	Shapes.quad(c.lit, lp, basis.x * 0.22, basis.z * 0.045, Vector3.UP)


## Four low carved marble plinth benches resting on the plaza floor (y = -0.24 .. 0.0) directly beneath the four
## rows of saffron-gold & ivory temple cushions.
static func _seating_plinths(c: Object) -> void:
	var stone: Material = c.tinted("stone")
	var gilt: Material = _gilt(c)
	var bench_w := 3.84
	var bench_d := 0.74
	var h := -FLOOR_Y # 0.24 m (top flush at y = -0.002 right under the cushions at y = 0.0!)
	for rz: float in SEAT_ROWS:
		var zc := rz - 0.05
		c.s.surface(stone)
		# Lower stepped base foot.
		c.s.colour = _lin(TRAVERTINE)
		c.s.box(Vector3(0.0, FLOOR_Y + 0.025, zc), Vector3(bench_w + 0.08, 0.05, bench_d + 0.08), Basis(),
				[RoomMesh.DOWN])
		# Recessed fluted marble plinth body.
		c.s.colour = _lin(MARBLE_WARM)
		c.s.box(Vector3(0.0, FLOOR_Y + 0.12, zc), Vector3(bench_w - 0.06, 0.14, bench_d - 0.08), Basis(),
				[RoomMesh.DOWN, RoomMesh.UP])
		# Carved marble top seat slab with subtle overhanging cornice lip (sits right under y = 0.0 cushions).
		c.s.colour = _lin(MARBLE)
		c.s.box(Vector3(0.0, -0.027, zc), Vector3(bench_w, 0.05, bench_d))
		# Low sculpted marble end-bolsters with gilt corner medallions (strictly outside cushions, well below eye line).
		for sd: float in [-1.0, 1.0]:
			var ex := sd * (bench_w * 0.5 - 0.12)
			c.s.surface(stone)
			c.s.colour = _lin(MARBLE)
			c.s.box(Vector3(ex, 0.055, zc), Vector3(0.18, 0.11, bench_d - 0.04), Basis(), [RoomMesh.DOWN])
			c.u.surface(gilt)
			c.u.colour = _lin(GILT)
			c.u.box(Vector3(ex + sd * 0.095, 0.055, zc), Vector3(0.018, 0.075, 0.18))
		# Physics boxes only on rows clear of (0, 0, 0) (domestic floor & seats cushion already cover row 0).
		if absf(rz) > 0.5:
			_solid(c, Vector3(0.0, FLOOR_Y + h * 0.5, zc), Vector3(bench_w, h, bench_d))


## Shallow sky-reflecting marble water basin directly before the screen, flanked by twin fluted marble screen pylons
## with gilt capitals, stepped classical cornice & central sunburst acroterion. Everything stays strictly outside the
## screen aperture and behind z = -11.45 so sight lines are 100% clear from every seat.
static func _screen_and_basin(c: Object, h: Hall) -> void:
	var stone: Material = c.tinted("stone")
	var iron: Material = c.tinted("iron")
	var gilt: Material = _gilt(c)
	var cove_m: Material = c.kit.cove_material()
	var uplight_m: Material = c.shade(UPLIGHT_GLOW)

	# 1. Raised white-marble reflecting basin coping rim (z = -10.88 .. -6.28, x = -4.25 .. +4.25).
	var rim_w := 0.28
	var rim_h := 0.14
	var rim_y := FLOOR_Y + rim_h * 0.5
	var bw := BASIN_X1 - BASIN_X0
	var bd := BASIN_Z1 - BASIN_Z0
	var bzc := (BASIN_Z0 + BASIN_Z1) * 0.5
	c.s.surface(stone)
	# Lower stepped marble apron plinth anchoring the basin coping cleanly onto the stylobate floor.
	c.s.colour = _lin(TRAVERTINE)
	c.s.box(Vector3(0.0, FLOOR_Y + 0.028, BASIN_Z1 + rim_w + 0.05), Vector3(bw + rim_w * 2.0 + 0.20, 0.056, 0.10),
			Basis(), [RoomMesh.DOWN])
	for sd: float in [-1.0, 1.0]:
		c.s.box(Vector3(sd * (BASIN_X1 + rim_w + 0.05), FLOOR_Y + 0.028, bzc + 0.05), Vector3(0.10, 0.056, bd + rim_w * 2.0),
				Basis(), [RoomMesh.DOWN])
	c.s.colour = _lin(MARBLE)
	# Front & back basin coping bars.
	c.s.box(Vector3(0.0, rim_y, BASIN_Z1 + rim_w * 0.5), Vector3(bw + rim_w * 2.0, rim_h, rim_w), Basis(),
			[RoomMesh.DOWN])
	c.s.box(Vector3(0.0, rim_y, BASIN_Z0 - rim_w * 0.5), Vector3(bw + rim_w * 2.0, rim_h, rim_w), Basis(),
			[RoomMesh.DOWN])
	# Left & right basin coping bars.
	for sd: float in [-1.0, 1.0]:
		c.s.box(Vector3(sd * (BASIN_X1 + rim_w * 0.5), rim_y, bzc), Vector3(rim_w, rim_h, bd), Basis(),
				[RoomMesh.DOWN])
	# Recessed warm golden cove inner-lip channel inside the water basin coping (y = WATER_Y .. FLOOR_Y + rim_h).
	c.cove.surface(cove_m)
	var b_y0 := WATER_Y + 0.002
	var b_y1 := FLOOR_Y + rim_h - 0.005
	for side_def: Array in [
		[Vector3(BASIN_X0, b_y0, BASIN_Z0 + 0.004), Vector3(BASIN_X1, b_y0, BASIN_Z0 + 0.004), Vector3.BACK],
		[Vector3(BASIN_X1, b_y0, BASIN_Z1 - 0.004), Vector3(BASIN_X0, b_y0, BASIN_Z1 - 0.004), Vector3.FORWARD],
		[Vector3(BASIN_X0 + 0.004, b_y0, BASIN_Z1), Vector3(BASIN_X0 + 0.004, b_y0, BASIN_Z0), Vector3.RIGHT],
		[Vector3(BASIN_X1 - 0.004, b_y0, BASIN_Z0), Vector3(BASIN_X1 - 0.004, b_y0, BASIN_Z1), Vector3.LEFT],
	]:
		var pa: Vector3 = side_def[0]
		var pb: Vector3 = side_def[1]
		var nr: Vector3 = side_def[2]
		var up_d := Vector3(0.0, b_y1 - b_y0, 0.0)
		c.cove.grid([
			PackedVector3Array([pa, pb]),
			PackedVector3Array([pa + up_d, pb + up_d]),
		], [
			PackedVector3Array([nr, nr]),
			PackedVector3Array([nr, nr]),
		], [
			PackedColorArray([_lin(MARBLE, 0.85), _lin(MARBLE, 0.85)]),
			PackedColorArray([_lin(MARBLE, 0.25), _lin(MARBLE, 0.25)]),
		])
	# Fine gilt brass inner inlay bead along the basin coping top.
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	c.u.box(Vector3(0.0, FLOOR_Y + rim_h + 0.004, BASIN_Z1 + 0.06), Vector3(bw + 0.12, 0.008, 0.03), Basis(),
			[RoomMesh.DOWN])
	for sd: float in [-1.0, 1.0]:
		c.u.box(Vector3(sd * (BASIN_X1 + 0.06), FLOOR_Y + rim_h + 0.004, bzc), Vector3(0.03, 0.008, bd + 0.12),
				Basis(), [RoomMesh.DOWN])

	# 2. Subdivided sky-reflecting water surface (env_world_water.gdshader, opaque 1 draw).
	var nx := 16
	var nz := 10
	for iz in nz:
		for ix in nx:
			var u0 := float(ix) / nx
			var u1 := float(ix + 1) / nx
			var v0 := float(iz) / nz
			var v1 := float(iz + 1) / nz
			var x0 := lerpf(BASIN_X0, BASIN_X1, u0)
			var x1 := lerpf(BASIN_X0, BASIN_X1, u1)
			var z0 := lerpf(BASIN_Z0, BASIN_Z1, v0)
			var z1 := lerpf(BASIN_Z0, BASIN_Z1, v1)
			var cols: Array = []
			for pt: Vector2 in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]:
				var edge := 1.0 - minf(minf(pt.x, 1.0 - pt.x), minf(pt.y, 1.0 - pt.y)) * 2.0
				var shallow := clampf(0.28 + 0.65 * pow(edge, 1.4), 0.0, 1.0)
				var glow := clampf((1.0 - pt.y) * 0.55, 0.0, 1.0)
				cols.append(Color(shallow, glow, 0.0, 1.0))
			h.water.quad(Vector3(x0, WATER_Y, z0), Vector3(x1, WATER_Y, z0), Vector3(x1, WATER_Y, z1),
					Vector3(x0, WATER_Y, z1), Vector3.UP, cols, 0.0,
					[Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])

	# 3. Twin Monumental Fluted Marble Screen Pylons (x = +-4.06, z = -11.54, clear of screen x = +-3.40, z = -11.40).
	var sc_top := SCREEN_C.y + SCREEN_H * 0.5 # 4.96 m
	var sc_bot := SCREEN_C.y - SCREEN_H * 0.5 # 1.14 m
	var pylon_z := -11.62
	var pylon_h := 6.08 # reaches y = 5.84 m
	for sd: float in [-1.0, 1.0]:
		var px := sd * 4.06
		c.s.surface(stone)
		# Stepped pedestal base rising from the basin edge.
		c.s.colour = _lin(TRAVERTINE)
		c.s.box(Vector3(px, FLOOR_Y + 0.16, pylon_z), Vector3(1.18, 0.32, 1.02), Basis(), [RoomMesh.DOWN])
		c.s.colour = _lin(MARBLE_WARM)
		c.s.box(Vector3(px, FLOOR_Y + 0.62, pylon_z), Vector3(1.04, 0.60, 0.90), Basis(), [RoomMesh.DOWN])
		# Tall monumental pylon shaft with sculpted front marble flutes (crisp vertical ribs & shadow grooves).
		c.s.colour = _lin(MARBLE_WARM)
		c.s.box(Vector3(px, FLOOR_Y + 3.22, pylon_z - 0.04), Vector3(0.92, 4.60, 0.72), Basis(), [RoomMesh.DOWN])
		c.s.colour = _lin(MARBLE)
		for fl in 4:
			var fx := px + lerpf(-0.34, 0.34, float(fl) / 3.0)
			c.s.box(Vector3(fx, FLOOR_Y + 3.22, pylon_z + 0.35), Vector3(0.115, 4.54, 0.085), Basis(), [RoomMesh.FRONT])
		# Gleaming gilt brass capital band & lotus collar!
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		c.u.box(Vector3(px, FLOOR_Y + 5.58, pylon_z), Vector3(1.02, 0.14, 0.86))
		c.u.box(Vector3(px, FLOOR_Y + 5.74, pylon_z), Vector3(1.12, 0.10, 0.94))
		# Stepped marble pylon crown cap + gilt urn-finial atop each pylon.
		c.s.surface(stone)
		c.s.colour = _lin(MARBLE)
		c.s.box(Vector3(px, FLOOR_Y + 5.94, pylon_z), Vector3(1.20, 0.28, 1.00))
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		Shapes.lathe(c.u, [Vector2(0.18, 0.0), Vector2(0.10, 0.12), Vector2(0.24, 0.34), Vector2(0.16, 0.50),
				Vector2(0.0, 0.62)], Vector3(px, FLOOR_Y + pylon_h, pylon_z), 12)
		# Recessed golden architectural cove reveal tucked strictly inside the inner screen jamb (never covering flutes!).
		var rx := sd * (SCREEN_W * 0.5 + 0.15)
		c.cove.surface(cove_m)
		c.cove.grid([
			PackedVector3Array([Vector3(rx, sc_bot, pylon_z + 0.28), Vector3(rx, sc_bot, pylon_z + 0.06)]),
			PackedVector3Array([Vector3(rx, sc_top, pylon_z + 0.28), Vector3(rx, sc_top, pylon_z + 0.06)]),
		], [
			PackedVector3Array([Vector3(-sd, 0.0, 0.0), Vector3(-sd, 0.0, 0.0)]),
			PackedVector3Array([Vector3(-sd, 0.0, 0.0), Vector3(-sd, 0.0, 0.0)]),
		], [
			PackedColorArray([_lin(MARBLE, 0.15), _lin(MARBLE, 0.88)]),
			PackedColorArray([_lin(MARBLE, 0.15), _lin(MARBLE, 0.88)]),
		])
		c.lit.surface(uplight_m)
		Shapes.quad(c.lit, Vector3(px, FLOOR_Y + 0.93, pylon_z + 0.44), Vector3(0.32, 0.0, 0.0),
				Vector3(0.0, 0.0, 0.045), Vector3.UP)
		_solid(c, Vector3(px, FLOOR_Y + pylon_h * 0.5, pylon_z), Vector3(1.16, pylon_h, 0.98))

	# 4. Delicate stepped classical cornice & lintel spanning strictly ABOVE the screen (y = 5.14 .. 5.88 m).
	var lintel_w := 9.20
	c.s.surface(stone)
	c.s.colour = _lin(MARBLE)
	c.s.box(Vector3(0.0, sc_top + 0.32, pylon_z), Vector3(lintel_w, 0.30, 0.72))
	# Recessed golden soffit cove tucked along the underside of the screen cornice.
	c.cove.surface(cove_m)
	c.cove.grid([
		PackedVector3Array([Vector3(-SCREEN_W * 0.5 - 0.14, sc_top + 0.165, pylon_z + 0.32),
				Vector3(SCREEN_W * 0.5 + 0.14, sc_top + 0.165, pylon_z + 0.32)]),
		PackedVector3Array([Vector3(-SCREEN_W * 0.5 - 0.14, sc_top + 0.165, pylon_z + 0.04),
				Vector3(SCREEN_W * 0.5 + 0.14, sc_top + 0.165, pylon_z + 0.04)]),
	], [
		PackedVector3Array([Vector3.DOWN, Vector3.DOWN]),
		PackedVector3Array([Vector3.DOWN, Vector3.DOWN]),
	], [
		PackedColorArray([_lin(MARBLE, 0.18), _lin(MARBLE, 0.18)]),
		PackedColorArray([_lin(MARBLE, 0.85), _lin(MARBLE, 0.85)]),
	])
	c.s.colour = _lin(TRAVERTINE)
	c.s.box(Vector3(0.0, sc_top + 0.58, pylon_z), Vector3(lintel_w + 0.16, 0.22, 0.78))
	c.s.colour = _lin(MARBLE)
	c.s.box(Vector3(0.0, sc_top + 0.78, pylon_z + 0.04), Vector3(lintel_w + 0.44, 0.18, 0.96))
	# Central gilded sunburst acroterion medallion crowning the screen entablature!
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	var crest_y := sc_top + 0.87
	c.u.box(Vector3(0.0, sc_top + 0.46, pylon_z + 0.38), Vector3(SCREEN_W + 0.40, 0.045, 0.045))
	for k in 9:
		var ang := lerpf(-PI * 0.42, PI * 0.42, float(k) / 8.0)
		var r_len := 0.58 if (k % 2 == 0) else 0.40
		var tip := Vector3(sin(ang) * r_len, crest_y + cos(ang) * r_len, pylon_z + 0.08)
		Shapes.beam(c.u, Vector3(0.0, crest_y + 0.04, pylon_z + 0.08), tip, Vector2(0.04, 0.04))
	Shapes.lathe(c.u, [Vector2(0.18, 0.0), Vector2(0.18, 0.06), Vector2(0.0, 0.09)],
			Vector3(0.0, crest_y + 0.14, pylon_z + 0.08), 14, Basis(Vector3.RIGHT, PI * 0.5))

	# 5. Low marble sill plinth strictly BELOW the screen (y = -0.24 .. 0.98 m) + slim dark-bronze & gilt frame
	#    strictly behind the screen plane (z = -11.48 .. -11.62).
	c.s.surface(stone)
	c.s.colour = _lin(MARBLE_WARM)
	c.s.box(Vector3(0.0, (FLOOR_Y + sc_bot - 0.16) * 0.5, pylon_z),
			Vector3(SCREEN_W + 0.48, (sc_bot - 0.16) - FLOOR_Y, 0.64), Basis(), [RoomMesh.DOWN])
	c.s.colour = _lin(MARBLE)
	c.s.box(Vector3(0.0, sc_bot - 0.14, pylon_z + 0.05), Vector3(SCREEN_W + 0.64, 0.08, 0.78))
	# Dark backing panel behind screen (z = -11.54) so bright sunset sky never bleeds behind the film picture.
	c.s.surface(iron)
	c.s.colour = _lin(SLATE_BACK)
	c.s.box(Vector3(0.0, SCREEN_C.y, -11.54), Vector3(SCREEN_W + 0.24, SCREEN_H + 0.24, 0.08))
	# Fine gilt brass inner frame fillet surrounding the picture at z = -11.48.
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	var fw := 0.045
	for sd: float in [-1.0, 1.0]:
		c.u.box(Vector3(sd * (SCREEN_W * 0.5 + 0.06), SCREEN_C.y, -11.48), Vector3(fw, SCREEN_H + 0.18, 0.04))
		c.u.box(Vector3(0.0, SCREEN_C.y + sd * (SCREEN_H * 0.5 + 0.06), -11.48), Vector3(SCREEN_W + 0.18, fw, 0.04))
	_solid(c, Vector3(0.0, SCREEN_C.y, -11.56), Vector3(SCREEN_W + 0.4, SCREEN_H + 0.4, 0.24))


## Four ornate cast-bronze tripod braziers around the colonnade perimeter with carved marble plinths, curved bronze
## legs, fluted fire bowls, glowing ember crowns, and slow animated golden-amber flames.
static func _braziers(c: Object, h: Hall) -> void:
	var stone: Material = c.tinted("stone")
	var iron: Material = c.tinted("iron")
	var gilt: Material = _gilt(c)
	var ember_m: Material = c.kit._lamp(EMBER_LIGHT, 1.45, 0.0, "accent")
	var rng := RandomNumberGenerator.new()
	rng.seed = 407

	for bi in BRAZIERS.size():
		var at := BRAZIERS[bi]
		# Stepped circular marble brazier plinth (h = 0.22 m).
		c.s.surface(stone)
		c.s.colour = _lin(TRAVERTINE)
		Shapes.cylinder(c.s, at, 0.72, 0.10, 16)
		c.s.colour = _lin(MARBLE)
		Shapes.cylinder(c.s, at + Vector3(0.0, 0.10, 0.0), 0.58, 0.12, 16)
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		Shapes.lathe(c.u, [Vector2(0.60, 0.10), Vector2(0.61, 0.13)], at, 16)

		# Three sculptural cast-bronze tripod legs + lion-paw feet + decorative stretcher rings.
		var leg_y0 := at.y + 0.22
		var bowl_y := at.y + 1.32
		c.s.surface(iron)
		c.s.colour = _lin(BRONZE)
		for k in 3:
			var ang := TAU * float(k) / 3.0 + float(bi) * 0.55
			var d := Vector3(sin(ang), 0.0, cos(ang))
			var foot := Vector3(at.x, leg_y0, at.z) + d * 0.46
			var knee := Vector3(at.x, leg_y0 + 0.62, at.z) + d * 0.26
			var rim := Vector3(at.x, bowl_y + 0.12, at.z) + d * 0.44
			# Claw foot pad + two-segment graceful curved tripod leg.
			c.s.box(foot + Vector3(0.0, 0.04, 0.0), Vector3(0.13, 0.08, 0.16), Basis(Vector3.UP, ang), [RoomMesh.DOWN])
			Shapes.beam(c.s, foot + Vector3(0.0, 0.06, 0.0), knee, Vector2(0.055, 0.055))
			Shapes.beam(c.s, knee, rim, Vector2(0.05, 0.05))
			# Gilt brass scroll knee boss.
			c.u.surface(gilt)
			c.u.colour = _lin(GILT)
			c.u.box(knee + d * 0.03, Vector3(0.08, 0.08, 0.08), Basis(Vector3.UP, ang))
		# Central bronze stretcher ring connecting the three knees.
		c.s.surface(iron)
		c.s.colour = _lin(BRONZE_DARK)
		Shapes.lathe(c.s, [
			Vector2(0.24, 0.0), Vector2(0.28, 0.03), Vector2(0.28, 0.07), Vector2(0.24, 0.10),
		], Vector3(at.x, leg_y0 + 0.57, at.z), 14)

		# Wide fluted cast-bronze fire bowl (r = 0.52 m) with gilded upper rim lip.
		c.s.colour = _lin(BRONZE)
		Shapes.lathe(c.s, [
			Vector2(0.10, -0.10), Vector2(0.24, -0.06), Vector2(0.42, 0.04),
			Vector2(0.51, 0.16), Vector2(0.54, 0.24), Vector2(0.48, 0.26), Vector2(0.42, 0.14),
		], Vector3(at.x, bowl_y, at.z), 18)
		c.u.surface(gilt)
		c.u.colour = _lin(GILT)
		Shapes.lathe(c.u, [Vector2(0.545, 0.19), Vector2(0.555, 0.24), Vector2(0.52, 0.265)],
				Vector3(at.x, bowl_y, at.z), 18)

		# Dark charred charcoal heap & glowing live ember crown (PieceLamps on accent group).
		c.s.surface(iron)
		c.s.colour = _lin(Color(0.07, 0.055, 0.05))
		Shapes.lathe(c.s, [Vector2(0.42, 0.16), Vector2(0.30, 0.25), Vector2(0.14, 0.30), Vector2(0.0, 0.31)],
				Vector3(at.x, bowl_y, at.z), 12)
		c.lit.surface(ember_m)
		Shapes.lathe(c.lit, [Vector2(0.32, 0.21), Vector2(0.22, 0.27), Vector2(0.08, 0.32), Vector2(0.0, 0.325)],
				Vector3(at.x, bowl_y, at.z), 10)

		# Graceful golden-amber flames (crossed quads in BrazierFlames, kind = 1.0) + warm ember halo (kind = 2.0).
		var fire_c := Vector3(at.x, bowl_y + 0.24, at.z)
		for t in 6:
			var ang := TAU * float(t) / 6.0 + rng.randf_range(-0.18, 0.18)
			var off_r := 0.06 if t < 2 else rng.randf_range(0.10, 0.20)
			var f_base := fire_c + Vector3(sin(ang) * off_r, 0.0, cos(ang) * off_r)
			var f_w := rng.randf_range(0.24, 0.38) if t < 2 else rng.randf_range(0.18, 0.28)
			var f_h := rng.randf_range(0.62, 0.88) if t < 2 else rng.randf_range(0.42, 0.64)
			var tint := Color(1.0, 0.94, 0.78, rng.randf())
			for turn: float in [ang, ang + PI * 0.5]:
				var across := Vector3(sin(turn), 0.0, cos(turn)) * f_w * 0.5
				h.flames.quad(f_base - across, f_base + across,
						f_base + across + Vector3(0.0, f_h, 0.0), f_base - across + Vector3(0.0, f_h, 0.0),
						across.cross(Vector3.UP).normalized(), tint, 1.0)
		# Soft warm radial ember-glow bloom over the fire bowl (kind = 2.0).
		_radial_glow(h.flames, fire_c + Vector3(0.0, 0.04, 0.0), Vector3(0.46, 0.0, 0.0), Vector3(0.0, 0.0, 0.46),
				Vector3.UP, _lin(Color(1.0, 0.48, 0.14)), 0.75)

		_solid(c, at + Vector3(0.0, 0.80, 0.0), Vector3(1.12, 1.60, 1.12))


static func _radial_glow(g: Verts, centre: Vector3, u: Vector3, v: Vector3, nrm: Vector3, col: Color,
		peak: float) -> void:
	var c_mid := Color(col.r, col.g, col.b, peak)
	var c_out := Color(col.r, col.g, col.b, 0.0)
	var k0 := g.vert(centre, nrm, c_mid, Vector2(0.5, 0.5), 2.0)
	var sides := 12
	for k in sides:
		var a := TAU * float(k) / sides
		g.vert(centre + u * cos(a) + v * sin(a), nrm, c_out, Vector2.ZERO, 2.0)
	for k in sides:
		var a := k0 + 1 + k
		var b := k0 + 1 + ((k + 1) % sides)
		if (g.v[a] - centre).cross(g.v[b] - centre).dot(nrm) > 0.0:
			g.idx.append_array([k0, b, a])
		else:
			g.idx.append_array([k0, a, b])


## Aft gleaming cast-brass armillary astrolabe sphere on a stepped octagonal white-marble altar plinth, framed by
## the aft colonnade portal looking out over the golden cloud sea.
static func _aft_astrolabe(c: Object) -> void:
	var stone: Material = c.tinted("stone")
	var gilt: Material = _gilt(c)
	var cove_m: Material = c.kit.cove_material()
	var orb_m: Material = c.shade(Color(1.0, 0.84, 0.44))
	var at := ALTAR_AT

	# Stepped octagonal marble altar plinth (y = -0.24 .. +1.18 m) with fluted marble drum & recessed under-rim cove.
	c.s.surface(stone)
	c.s.colour = _lin(TRAVERTINE)
	Shapes.cylinder(c.s, at, 1.48, 0.16, 8)
	c.s.colour = _lin(MARBLE_WARM)
	Shapes.cylinder(c.s, at + Vector3(0.0, 0.16, 0.0), 1.16, 0.16, 8)
	c.s.colour = _lin(MARBLE)
	Shapes.cylinder(c.s, at + Vector3(0.0, 0.32, 0.0), 0.72, 0.84, 12)
	# 12 carved vertical marble pilasters around the altar drum.
	for k in 12:
		var ang := TAU * float(k) / 12.0
		var d := Vector3(sin(ang), 0.0, cos(ang))
		var b_p := Basis(Vector3(cos(ang), 0.0, -sin(ang)), Vector3.UP, d)
		c.s.box(Vector3(at.x, at.y + 0.74, at.z) + d * 0.71, Vector3(0.085, 0.80, 0.055), b_p, [RoomMesh.DOWN, RoomMesh.UP])
	c.s.colour = _lin(MARBLE)
	Shapes.cylinder(c.s, at + Vector3(0.0, 1.30, 0.0), 0.94, 0.12, 8)
	# Gilt brass accent fillet encircling the altar cornice.
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	Shapes.lathe(c.u, [Vector2(0.955, 1.32), Vector2(0.96, 1.37)], at, 8)

	# Recessed golden cove shadow-gap frieze tucked neatly under the overhanging marble tabletop (y = 1.16..1.30).
	c.cove.surface(cove_m)
	var a_rows: Array = []
	var a_norms: Array = []
	var a_cols: Array = []
	for rd: Array in [[1.16, 0.68, 0.35], [1.23, 0.67, 0.92], [1.30, 0.68, 0.55]]:
		var yy := at.y + float(rd[0])
		var rad := float(rd[1])
		var w := float(rd[2])
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for j in 13:
			var ang := TAU * float(j % 12) / 12.0
			var d := Vector3(sin(ang), 0.0, cos(ang))
			row.append(Vector3(at.x, yy, at.z) + d * rad)
			nrow.append(d)
			crow.append(_lin(MARBLE, w))
		a_rows.append(row)
		a_norms.append(nrow)
		a_cols.append(crow)
	c.cove.grid(a_rows, a_norms, a_cols)

	# Gleaming cast-brass armillary astrolabe sphere (centre y = 2.34 m, radius = 0.92 m).
	var sphere_c := Vector3(at.x, at.y + 2.58, at.z)
	c.u.surface(gilt)
	c.u.colour = _lin(GILT)
	# Turned brass pedestal foot + cradle yoke supporting the horizon ring.
	Shapes.lathe(c.u, [
		Vector2(0.46, 0.0), Vector2(0.42, 0.08), Vector2(0.18, 0.18), Vector2(0.12, 0.34),
		Vector2(0.16, 0.44), Vector2(0.08, 0.56),
	], at + Vector3(0.0, 1.42, 0.0), 14)
	for k in 4:
		var ang := TAU * float(k) / 4.0 + PI * 0.25
		var d := Vector3(sin(ang), 0.0, cos(ang))
		Shapes.beam(c.u, at + Vector3(0.0, 1.78, 0.0), sphere_c + d * 0.92, Vector2(0.042, 0.042))
	# Horizontal Horizon Ring, vertical Meridian Ring, tilted Equatorial Ring, and wide Ecliptic Zodiac Band!
	_brass_ring(c.u, sphere_c, 0.96, 0.055, 0.07, Basis(), 32)
	_brass_ring(c.u, sphere_c, 0.90, 0.045, 0.055, Basis(Vector3.FORWARD, PI * 0.5), 32)
	_brass_ring(c.u, sphere_c, 0.84, 0.042, 0.05, Basis(Vector3.RIGHT, deg_to_rad(38.0)), 28)
	_brass_ring(c.u, sphere_c, 0.77, 0.095, 0.035,
			Basis(Vector3.RIGHT, deg_to_rad(38.0)) * Basis(Vector3.FORWARD, deg_to_rad(23.4)), 28)
	# Polar celestial axis spear piercing diagonally through the armillary sphere.
	var axis_dir := (Basis(Vector3.RIGHT, deg_to_rad(38.0)) * Vector3.UP).normalized()
	Shapes.beam(c.u, sphere_c - axis_dir * 1.08, sphere_c + axis_dir * 1.24, Vector2(0.032, 0.032))
	# Pointed finial tip at north pole.
	Shapes.lathe(c.u, [Vector2(0.06, 0.0), Vector2(0.0, 0.18)], sphere_c + axis_dir * 1.22, 8,
			Basis(Vector3.RIGHT, deg_to_rad(38.0)))
	# Glowing golden celestial sun orb at the heart of the astrolabe (PieceLamps, house group).
	c.lit.surface(orb_m)
	Shapes.dome(c.lit, sphere_c, 0.13, 6, 12, false, -PI * 0.5, PI * 0.5)

	_solid(c, at + Vector3(0.0, 1.85, 0.0), Vector3(2.4, 3.7, 2.4))


## A sculpted brass ring of radius r, band height h, radial thickness t, oriented by basis.
static func _brass_ring(b: RoomMesh, centre: Vector3, r: float, h: float, t: float, basis: Basis,
		segs: int) -> void:
	var r0 := r - t * 0.5
	var r1 := r + t * 0.5
	var hy := h * 0.5
	var o0 := PackedVector3Array()
	var o1 := PackedVector3Array()
	var i0 := PackedVector3Array()
	var i1 := PackedVector3Array()
	var no := PackedVector3Array()
	var ni := PackedVector3Array()
	var nu := PackedVector3Array()
	var nd := PackedVector3Array()
	var up := (basis * Vector3.UP).normalized()
	for k in segs + 1:
		var ang := TAU * float(k % segs) / segs
		var d := (basis * Vector3(sin(ang), 0.0, cos(ang))).normalized()
		o0.append(centre + d * r1 - up * hy)
		o1.append(centre + d * r1 + up * hy)
		i0.append(centre + d * r0 - up * hy)
		i1.append(centre + d * r0 + up * hy)
		no.append(d)
		ni.append(-d)
		nu.append(up)
		nd.append(-up)
	b.strip(o0, o1, no)
	b.strip(i0, i1, ni)
	b.strip(i1, o1, nu)
	b.strip(i0, o0, nd)


## Stand-in & bake lights (zero live lights: every omni/spot is hidden for LightmapGI bake only).
static func _sanctuary_lights(c: Object) -> void:
	# 4 warm amber brazier stand-in + bake omni lights (up to bake_lamps = 8).
	for b_at: Vector3 in BRAZIERS:
		c.lamps.append([b_at + Vector3(0.0, 1.95, 0.0), EMBER_LIGHT, 1.10])
	# 2 warm golden sunset grazing lamps on the sunward right colonnade.
	c.lamps.append([Vector3(8.4, 5.2, -5.2), SUN_WARM, 1.05])
	c.lamps.append([Vector3(8.4, 5.2, 1.6), SUN_WARM, 0.90])
	# 1 screen basin & pylon uplight lamp + 1 aft astrolabe lamp.
	c.lamps.append([Vector3(0.0, 2.2, -9.2), UPLIGHT_GLOW, 0.75])
	c.lamps.append([Vector3(0.0, 2.6, 6.5), UPLIGHT_GLOW, 0.85])
	# Hidden directional-style sunset spots for bake only.
	c.spots.append([Vector3(16.0, 9.5, -13.5), Vector3(-2.0, 0.5, -1.5), SUN_WARM, 4.5, 32.0, 48.0])
	c.spots.append([Vector3(14.5, 8.0, 5.5), Vector3(-2.5, 0.0, 2.0), Color(1.0, 0.68, 0.42), 3.2, 28.0, 46.0])


# --- Piece 2: cloud_sky_sea -------------------------------------------------------------------------------------------

static func _sky_sea(_c: Object, h: Hall) -> void:
	_build_cloud_sea_disc(h.cloud_sea)
	_build_sky_islands(h.sky_islands)
	_build_sunset_shafts(h.shafts)


## Endless 360-degree billowing cloud sea disc (r = 185 m) sitting at y = -11.5 m beneath the temple and curving
## gently upward toward y = +2.2 m at the horizon rim so it merges seamlessly with SkyDome at every compass bearing.
static func _build_cloud_sea_disc(g: Verts) -> void:
	var rings := 28
	var segs := 64
	# Centre vertex.
	var c_idx := g.vert(Vector3(0.0, SEA_BASE_Y, 0.0), Vector3.UP, Color.WHITE, Vector2(0.5, 0.5), 0.0)
	var ring_start: Array[int] = []
	for ir in range(1, rings + 1):
		var t := float(ir) / rings
		# Non-linear radial spacing: denser near/mid cloud billows, broader near the distant horizon.
		var r := SEA_RADIUS * pow(t, 1.48)
		var lift := pow(smoothstep(0.18, 1.0, t), 1.85)
		var y := lerpf(SEA_BASE_Y, SEA_RIM_Y, lift)
		ring_start.append(g.v.size())
		for ia in segs:
			var ang := TAU * float(ia) / segs
			var p := Vector3(sin(ang) * r, y, cos(ang) * r)
			g.vert(p, Vector3.UP, Color.WHITE, Vector2(p.x / SEA_RADIUS * 0.5 + 0.5, p.z / SEA_RADIUS * 0.5 + 0.5), 0.0)
	# Inner triangle fan (clockwise viewed from above -> front face faces +Y).
	var r0 := ring_start[0]
	for ia in segs:
		var ib := (ia + 1) % segs
		g.idx.append_array([c_idx, r0 + ib, r0 + ia])
	# Concentric quad strips outward (front face faces +Y).
	for ir in range(ring_start.size() - 1):
		var a0 := ring_start[ir]
		var b0 := ring_start[ir + 1]
		for ia in segs:
			var ib := (ia + 1) % segs
			g.idx.append_array([a0 + ia, b0 + ib, b0 + ia, a0 + ia, a0 + ib, b0 + ib])


## Four poetic distant floating marble sky-island ruin arches, colonnades and obelisks rising out of the cloud sea
## 66-96 m out (baked/unshaded via env_cloud_sea.gdshader, UV2.x = 1.0).
static func _build_sky_islands(g: Verts) -> void:
	# 1. Front-right sunset sanctuary arch & obelisk (~76 m out — bathed in golden sunset backlight!).
	_floating_island(g, Vector3(54.0, -4.6, -54.0), 12.0, 10.5, deg_to_rad(-36.0), "arch_obelisk", 1.1)
	# 2. Front-left twin colonnade ruin (~84 m out — catching warm golden key light across the abyss!).
	_floating_island(g, Vector3(-66.0, -3.4, -52.0), 13.5, 11.5, deg_to_rad(42.0), "colonnade", 2.7)
	# 3. Left-aft lofty monopteros tholos ruin spire (~92 m out).
	_floating_island(g, Vector3(-84.0, -1.8, 36.0), 11.5, 12.5, deg_to_rad(20.0), "tholos", 4.3)
	# 4. Aft grand cloud-arch portal (~78 m out — framed softly through the aft astrolabe opening!).
	_floating_island(g, Vector3(22.0, -4.2, 74.0), 12.5, 10.5, deg_to_rad(165.0), "arch_obelisk", 5.9)


static func _floating_island(g: Verts, at: Vector3, radius: float, crag_depth: float, yaw: float,
		kind: String, crag_seed: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var rock_col := _lin(Color(0.68, 0.61, 0.56), 0.88)
	var rock_mid := _lin(Color(0.50, 0.44, 0.45), 0.80)
	var rock_deep := _lin(Color(0.32, 0.28, 0.34), 0.72)
	var ruin_col := _lin(Color(0.92, 0.88, 0.80), 1.0)
	var ruin_warm := _lin(Color(0.84, 0.77, 0.67), 0.94)

	# Sculpted multi-tiered jagged limestone crag plunging cleanly into the cloud sea mist (y ~ -14 m).
	var sides := 14
	var tiers: Array = [
		[-crag_depth, radius * 0.42, rock_deep, 0.32],
		[-crag_depth * 0.62, radius * 0.78, rock_mid, 0.28],
		[-crag_depth * 0.26, radius * 0.96, rock_col, 0.22],
		[0.0, radius * 0.88, rock_col, 0.14],
	]
	var ring_pts: Array = []
	for ti in tiers.size():
		var td: Array = tiers[ti]
		var yy := at.y + float(td[0])
		var rad := float(td[1])
		var jag := float(td[3])
		var pts := PackedVector3Array()
		for k in sides:
			var a := TAU * float(k) / sides
			var mod := 1.0 + jag * (0.58 * sin(3.0 * a + crag_seed + float(ti) * 0.65)
					+ 0.42 * cos(5.0 * a - crag_seed * 1.4))
			pts.append(Vector3(at.x + sin(a) * rad * mod, yy, at.z + cos(a) * rad * mod))
		ring_pts.append(pts)
	for ti in range(tiers.size() - 1):
		var r_lo: PackedVector3Array = ring_pts[ti]
		var r_hi: PackedVector3Array = ring_pts[ti + 1]
		var col_lo: Color = tiers[ti][2]
		var col_hi: Color = tiers[ti + 1][2]
		for k in sides:
			var kn := (k + 1) % sides
			var p0 := r_lo[k]
			var p1 := r_lo[kn]
			var p2 := r_hi[kn]
			var p3 := r_hi[k]
			var nrm := (p1 - p0).cross(p3 - p0).normalized()
			if nrm.dot((p0 + p2) * 0.5 - Vector3(at.x, (p0.y + p2.y) * 0.5, at.z)) < 0.0:
				nrm = -nrm
			g.quad(p0, p1, p2, p3, nrm, [col_lo, col_lo, col_hi, col_hi], 1.0)
	# Top plateau surface.
	var top_ring: PackedVector3Array = ring_pts[tiers.size() - 1]
	var tc := g.vert(at, Vector3.UP, rock_col, Vector2.ZERO, 1.0)
	for k in sides:
		var kn := (k + 1) % sides
		var a_i := g.vert(top_ring[kn], Vector3.UP, rock_col, Vector2.ZERO, 1.0)
		var b_i := g.vert(top_ring[k], Vector3.UP, rock_col, Vector2.ZERO, 1.0)
		g.idx.append_array([tc, a_i, b_i])
	# Stepped classical marble ruin terrace crowning the crag plateau.
	g.cylinder(at, radius * 0.72, radius * 0.68, 0.85, 10, ruin_warm, 1.0, true)
	var y0 := at.y + 0.85

	match kind:
		"arch_obelisk":
			# Grand broken classical triumphal sky-arch + flanking weathered columns + slender obelisk!
			for sd: float in [-1.0, 1.0]:
				g.box(at + basis * Vector3(sd * 3.8, 5.4, 0.0), Vector3(1.8, 9.2, 1.9), basis, ruin_col, 1.0)
				g.box(at + basis * Vector3(sd * 3.8, 10.2, 0.0), Vector3(2.2, 0.6, 2.3), basis, ruin_warm, 1.0)
			# Broken arch lintel spanning between the twin piers.
			g.box(at + basis * Vector3(0.0, 11.0, 0.0), Vector3(10.8, 1.35, 2.1), basis, ruin_col, 1.0)
			g.box(at + basis * Vector3(-1.4, 12.1, 0.0), Vector3(6.8, 0.85, 2.4), basis, ruin_warm, 1.0)
			# Slender sunlit obelisk perched to one side of the terrace.
			var ob_p := at + basis * Vector3(radius * 0.44, 0.85, -2.4)
			g.cylinder(ob_p, 0.78, 0.42, 12.0, 4, ruin_col, 1.0, false)
			g.cylinder(ob_p + Vector3(0.0, 12.0, 0.0), 0.42, 0.02, 1.5, 4, ruin_warm, 1.0, false)
		"colonnade":
			# Sweeping ruined row of 5 columns (two broken half-height) carrying a partial entablature + tall obelisk.
			var heights: Array[float] = [8.8, 8.8, 8.8, 5.4, 3.8]
			for i in heights.size():
				var lx := lerpf(-6.8, 6.8, float(i) / 4.0)
				var cp := at + basis * Vector3(lx, 0.85, 0.0)
				g.cylinder(cp, 0.62, 0.50, heights[i], 8, ruin_col, 1.0, true)
			g.box(at + basis * Vector3(-3.4, 10.2, 0.0), Vector3(8.2, 1.25, 1.6), basis, ruin_col, 1.0)
			g.box(at + basis * Vector3(-4.0, 11.1, 0.0), Vector3(6.8, 0.65, 1.9), basis, ruin_warm, 1.0)
			var ob_p := at + basis * Vector3(6.4, 0.85, 2.8)
			g.cylinder(ob_p, 0.75, 0.38, 13.2, 4, ruin_col, 1.0, false)
			g.cylinder(ob_p + Vector3(0.0, 13.2, 0.0), 0.38, 0.02, 1.6, 4, ruin_warm, 1.0, false)
		_:
			# Classical circular monopteros tholos pavilion ruin (6 columns + broken ring architrave).
			for k in 6:
				var ang := TAU * float(k) / 6.0
				var h_col := 9.2 if k < 4 else 5.6
				var cp := at + Vector3(sin(ang) * 4.8, y0 - at.y, cos(ang) * 4.8)
				g.cylinder(cp, 0.56, 0.44, h_col, 8, ruin_col, 1.0, true)
			# Partial curved architrave beams linking the tall columns.
			for k in 3:
				var a0 := TAU * float(k) / 6.0
				var a1 := TAU * float(k + 1) / 6.0
				var p0 := at + Vector3(sin(a0) * 4.8, y0 - at.y + 9.6, cos(a0) * 4.8)
				var p1 := at + Vector3(sin(a1) * 4.8, y0 - at.y + 9.6, cos(a1) * 4.8)
				var mid := (p0 + p1) * 0.5
				var dir := (p1 - p0).normalized()
				var sb := Basis(dir, Vector3.UP, dir.cross(Vector3.UP).normalized())
				g.box(mid, Vector3(p0.distance_to(p1) + 0.8, 1.15, 1.3), sb, ruin_col, 1.0)


## Five soft, silky slanting golden sunset god-ray light shafts pouring through the sunward (front-right / right) outer
## colonnade intercolumniations onto the right marble promenade (env_world_shaft.gdshader, env_see_through).
static func _build_sunset_shafts(g: Verts) -> void:
	# Slanting down at ~34 deg from the front-right sunset azimuth so beams stay cleanly on the right promenade
	# (x >= +1.5 m), never overlapping the viewer's head or the cinema screen's sight line.
	var sun_dir := Vector3(0.60, 0.56, -0.57).normalized()
	var bay_degs: Array[float] = [37.0, 57.2, 77.4, 97.5, 117.6]
	for i in bay_degs.size():
		var az := deg_to_rad(bay_degs[i])
		var gap := _ring_pt(R_COL - 0.15, az, 4.7)
		var top := gap + sun_dir * 4.4
		var bot := gap - sun_dir * 7.6
		var r_top := 0.88 if i < 3 else 0.78
		var r_bot := 1.65 if i < 3 else 1.48
		var alpha := 0.85 if i < 3 else 0.65
		var tint := Color(1.0, 0.86, 0.58, alpha) if i < 3 else Color(1.0, 0.74, 0.48, alpha)
		_shaft_frustum(g, top, bot, r_top, r_bot, 12, tint)


static func _shaft_frustum(g: Verts, top: Vector3, bot: Vector3, r_top: float, r_bot: float, sides: int,
		col: Color) -> void:
	var axis := (bot - top).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := u.cross(axis).normalized()
	for k in sides:
		var f0 := float(k) / sides
		var f1 := float(k + 1) / sides
		var a0 := TAU * f0
		var a1 := TAU * f1
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		var p0 := top + d0 * r_top
		var p1 := top + d1 * r_top
		var p2 := bot + d1 * r_bot
		var p3 := bot + d0 * r_bot
		var k0 := g.vert(p0, d0, col, Vector2(f0, 0.0), 0.0)
		var k1 := g.vert(p1, d1, col, Vector2(f1, 0.0), 0.0)
		var k2 := g.vert(p2, d1, col, Vector2(f1, 1.0), 0.0)
		var k3 := g.vert(p3, d0, col, Vector2(f0, 1.0), 0.0)
		g.idx.append_array([k0, k1, k2, k0, k2, k3])
