extends RefCounted

## Lighthouse watchroom kit (Cozy retreats: app/environments/lighthouse_watchroom.env.json;
## docs/environments/rooms/lighthouse_watchroom.md).
## A circular whitewashed-stone and painted cast-iron coastal lighthouse lantern/watchroom perched 26 m high on a dark
## stormy Atlantic headland, crowned overhead by a live rotating first-order brass-and-crystal Fresnel dioptric optical
## drum projecting twin volumetric golden-ivory beams out across the rainy coastal night.
##
## Pieces (pieces.gd dispatches here):
##   lighthouse_tower  Circular watchroom deck (riveted dark-iron perimeter flange, weathered oak planks with open aft
##                     circular spiral-stair hatch, inlaid central brass-and-slate compass rose), waist-height heritage
##                     crimson & dark-navy riveted cast-iron panelled parapet with whitewashed lime-plaster stone sill
##                     reveals & warm indirect sill coves (`PieceCove`), 16-bay 360-degree panoramic storm lantern
##                     glazing cage (`PieceGlass`) with iconic criss-crossing helical brass-and-iron astragal mullions,
##                     ribbed patinated dark-copper conical lantern dome with bronze cornice & brass ventilator ball,
##                     exterior stone gallery corbels & riveted iron sea-spray catwalk balustrade outside the glass,
##                     twin brushed-brass & dark-iron nautical screen stanchions suspending the cinema screen inside
##                     the forward arc, aft circular spiral staircase & brass handrail loop, port oak watchkeeper's
##                     chart desk (unrolled sea chart, brass sextant, logbook, speaking tube), port-forward brass
##                     telescope on mahogany tripod, starboard signal locker, ship's Fortin & aneroid barometer
##                     (`PieceWindows` + `PieceGlass`), coiled hemp hawser rope, four gimbal brass oil storm lanterns
##                     (`PieceLamps`), and aft mahogany-mounted working brass ship's chronometer clock (`PieceClock`).
##   lighthouse_lens   Custom `c.halls` live rig (`LighthouseHall`):
##                     - `LighthouseLensRig` suspended cleanly overhead at (0.0, 4.62, 0.10) (well clear of all sight
##                       lines): sculpted first-order rotating brass-and-crystal Fresnel dioptric optical drum
##                       (`LighthouseLensBrass` + `LighthouseLensCrystal`, opaque 2 draws) with twin opposite stepped
##                       bullseye facets, catadioptric prism tiers, visible brass clockwork gear crown, warm ivory lamp
##                       core, and twin outward-flaring volumetric golden-ivory light cones (`LighthouseBeams`,
##                       `env_world_shaft.gdshader`, `env_see_through`, passing cleanly above the cinema screen out
##                       over the dark Atlantic mist). Smoothly rotates at 0.09 rad/s scaled by `Motion`, controlled
##                       live by `setting.beam` (`sweeping` / `steady` / `lantern`).
##                     - `AtlanticOcean` (`env_world_water.gdshader`, opaque 1 draw, y = -24 m, r = 172 m): dark moody
##                       Atlantic swells with moonlit specular glints and churning white surf caustics around the rocks.
##                     - `HeadlandOutside` (`env_ice_outside.gdshader`, opaque 1 draw): tapered whitewashed-and-crimson
##                       exterior lighthouse shaft, craggy wet dark basalt cliff base, outlying basalt sea stacks &
##                       headland reefs, and distant dark coastal hills dotted with warm harbour lights.
##                     - `ChannelBuoy` (`env_ice_outside.gdshader`, opaque 1 draw): bobbing red-iron harbour channel
##                       bell buoy out seaward at (-22, -24, -38) with a gently pulsing navigation beacon (< 0.4 Hz).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const WATER_SHADER := preload("res://shaders/env_world_water.gdshader")
const SHAFT_SHADER := preload("res://shaders/env_world_shaft.gdshader")
const OUTSIDE_SHADER := preload("res://shaders/env_ice_outside.gdshader")

## Circular watchroom geometry constants.
const CX := 0.0
const CZ := 0.10
const R_INNER := 5.55
const R_GLASS := 5.375 # apothem of 16-gon at r = 5.48 m so all 16 glass bays meet flush at the stanchions
const R_MULLION := 5.45
const R_OUTER := 5.88
const R_GALLERY := 6.95
const BAYS := 16
const PARAPET_H := 1.02
const CAGE_TOP := 5.40
const DOME_TOP := 7.62

## Cinema screen geometry (matches app/environments/lighthouse_watchroom.env.json).
const SCREEN_C := Vector3(0.0, 2.45, -4.55)
const SCREEN_W := 4.10
const SCREEN_H := 2.31

## Overhead rotating first-order Fresnel optical drum centre (cleanly above all screen sight lines).
const LENS_Y := 4.62
const LENS_ROT_SPEED := 0.09 # rad/s (~5.16 deg/s, ~70 s per full revolution)
const BEAM_START_YAW_DEG := -58.0
const BEAM_STEADY_YAW_DEG := -34.0

## Aft circular spiral-stair floor hatch centre and radius.
const HATCH_C := Vector3(0.0, 0.0, 3.75)
const HATCH_R := 0.92
const HATCH_DEPTH := 3.80

## Exterior stormy Atlantic ocean, basalt headland and distant harbour channel buoy constants.
const SEA_Y := -24.0
const SEA_RADIUS := 172.0 # strictly inside SkyDome (190 m) & camera far plane (200 m)
const BUOY_BASE := Vector3(-22.0, SEA_Y, -38.0)
const BUOY_PULSE_HZ := 0.28 # well under 3 Hz photosensitivity ceiling

## Outlying basalt sea-stacks & foaming headland reefs breaking the Atlantic swells: [x, z, base_r, height, seed].
const SEA_STACKS: Array = [
	[-18.0, -28.0, 5.2, 11.8, 11],
	[17.0, -30.0, 5.8, 13.4, 17],
	[-38.0, -56.0, 10.2, 28.2, 23],
	[48.0, -50.0, 11.0, 27.6, 31],
	[-62.0, -14.0, 10.6, 27.0, 37],
	[58.0, 18.0, 11.4, 28.2, 53],
	[-42.0, 48.0, 9.0, 25.8, 71],
]

## Palette (sRGB; converted to linear per vertex where needed).
const OAK_DECK := Color(0.46, 0.32, 0.19)
const OAK_DARK := Color(0.28, 0.18, 0.10)
const MAHOGANY := Color(0.26, 0.11, 0.08)
const WHITEWASH := Color(0.86, 0.84, 0.79)
const WHITEWASH_SHADE := Color(0.68, 0.66, 0.62)
const IRON_NAVY := Color(0.11, 0.14, 0.19)
const IRON_DARK := Color(0.08, 0.09, 0.11)
const CRIMSON_PANEL := Color(0.38, 0.10, 0.10)
const CRIMSON_BAND := Color(0.56, 0.13, 0.12)
const COPPER_DARK := Color(0.14, 0.20, 0.18)
const COPPER_BRONZE := Color(0.26, 0.20, 0.15)
const BRASS_BRIGHT := Color(0.95, 0.76, 0.36)
const BRASS_WARM := Color(0.78, 0.59, 0.25)
const PARCHMENT := Color(0.88, 0.82, 0.68)
const CHART_INK := Color(0.18, 0.24, 0.28)
const HEMP_ROPE := Color(0.66, 0.54, 0.34)
const BASALT_DARK := Color(0.09, 0.11, 0.14)
const BASALT_WET := Color(0.15, 0.18, 0.22)
const FOAM_PALE := Color(0.42, 0.50, 0.58)
const LAMP_AMBER := Color(1.0, 0.74, 0.38)
const BEAM_GOLD := Color(1.0, 0.88, 0.64)
const CRYSTAL_CORE := Color(1.0, 0.94, 0.76)
const CRYSTAL_PRISM := Color(0.74, 0.86, 0.88)
const BUOY_RED := Color(0.62, 0.14, 0.12)
const BUOY_BEACON := Color(0.42, 1.0, 0.68)


## Compact indexed mesh builder for custom shader meshes (ocean, headland, buoy, Fresnel crystal & volumetric beams).
class Verts:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	func count() -> int:
		return idx.size()

	func vert(p: Vector3, nrm: Vector3, col: Color, t := Vector2.ZERO) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		return v.size() - 1

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, cols: Variant,
			uvs: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]) -> void:
		var cs: Array = cols if cols is Array else [cols, cols, cols, cols]
		var k0 := vert(a, nrm, cs[0], uvs[0])
		vert(b, nrm, cs[1], uvs[1])
		vert(cc, nrm, cs[2], uvs[2])
		vert(d, nrm, cs[3], uvs[3])
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			idx.append_array([k0, k0 + 2, k0 + 1, k0, k0 + 3, k0 + 2])
		else:
			idx.append_array([k0, k0 + 1, k0 + 2, k0, k0 + 2, k0 + 3])

	func tri(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, col: Color) -> void:
		var k0 := vert(a, nrm, col, Vector2.ZERO)
		vert(b, nrm, col, Vector2.ZERO)
		vert(cc, nrm, col, Vector2.ZERO)
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			idx.append_array([k0, k0 + 2, k0 + 1])
		else:
			idx.append_array([k0, k0 + 1, k0 + 2])

	func box(centre: Vector3, size: Vector3, basis: Basis, col: Color, skip: Array = []) -> void:
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
			quad(p0, p1, p2, p3, (basis * fn).normalized(), col)

	func lathe(profile: Array, centre: Vector3, sides: int, col: Variant, basis := Basis()) -> void:
		for i in profile.size() - 1:
			var p0: Vector2 = profile[i]
			var p1: Vector2 = profile[i + 1]
			if p0.distance_to(p1) < 0.0001:
				continue
			var c0: Color = col[i] if col is Array else col
			var c1: Color = col[i + 1] if col is Array else col
			var slope := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
			for k in sides:
				var a0 := TAU * float(k) / float(sides)
				var a1 := TAU * float((k + 1) % sides) / float(sides)
				var d0 := Vector3(sin(a0), 0.0, cos(a0))
				var d1 := Vector3(sin(a1), 0.0, cos(a1))
				var q0 := centre + basis * (d0 * p0.x + Vector3.UP * p0.y)
				var q1 := centre + basis * (d1 * p0.x + Vector3.UP * p0.y)
				var q2 := centre + basis * (d1 * p1.x + Vector3.UP * p1.y)
				var q3 := centre + basis * (d0 * p1.x + Vector3.UP * p1.y)
				var nrm := (basis * (((d0 + d1) * 0.5) * slope.x + Vector3.UP * slope.y)).normalized()
				quad(q0, q1, q2, q3, nrm, [c0, c0, c1, c1])

	func commit(m: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, m)
		return mesh


## Live manager for the rotating Fresnel lens & beams, animated Atlantic swells, basalt headland, and bobbing buoy.
class LighthouseHall:
	var kit: Node
	var brass_mat: Material

	var lens_rig: Node3D
	var lens_brass_mi: MeshInstance3D
	var lens_crystal_mi: MeshInstance3D
	var beams_mi: MeshInstance3D
	var ocean_mi: MeshInstance3D
	var headland_mi: MeshInstance3D
	var buoy_mi: MeshInstance3D

	var crystal_m: ShaderMaterial
	var beam_m: ShaderMaterial
	var ocean_m: ShaderMaterial
	var outside_m: ShaderMaterial
	var buoy_m: ShaderMaterial

	var _beam_yaw := deg_to_rad(BEAM_START_YAW_DEG)
	var _shaft_level := 0.54
	var _core_glow := 1.45
	var _ocean_clock := 0.0
	var _buoy_t := 0.0
	var _initialized := false

	static func _lin(colour: Color, alpha := 1.0) -> Color:
		var l := colour.srgb_to_linear()
		return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))

	func finish(k: Node) -> void:
		kit = k
		# Tune PieceGlass to crisp coastal storm glazing with subtle moonlit rim & faint screen glint.
		for n: Node in k.owned():
			if n is MeshInstance3D and str(n.name).begins_with("PieceGlass"):
				var gm := (n as MeshInstance3D).material_override as ShaderMaterial
				if gm != null:
					gm.set_shader_parameter("alpha", 0.036)
					gm.set_shader_parameter("rim", 0.16)
					gm.set_shader_parameter("sky_colour", Color(0.24, 0.36, 0.56))
					gm.set_shader_parameter("sky_mix", 0.22)
					gm.set_shader_parameter("screen_reflect", 0.16)

		var noise := SkySys.noise_texture()
		var caustics := Procedural.caustic_map()

		# 1. Rotating first-order Fresnel optical drum & twin volumetric beams rig (centred overhead at LENS_Y).
		lens_rig = Node3D.new()
		lens_rig.name = "LighthouseLensRig"
		lens_rig.position = Vector3(CX, LENS_Y, CZ)
		k.own(lens_rig)

		var lb := RoomMesh.new()
		lb.surface(brass_mat)
		_build_lens_brass(lb)
		lens_brass_mi = MeshInstance3D.new()
		lens_brass_mi.name = "LighthouseLensBrass"
		lens_brass_mi.mesh = lb.commit(false)
		lens_brass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lens_brass_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		lens_rig.add_child(lens_brass_mi)

		crystal_m = ShaderMaterial.new()
		crystal_m.shader = OUTSIDE_SHADER
		crystal_m.set_shader_parameter("sky_top", Color(0.32, 0.26, 0.18))
		crystal_m.set_shader_parameter("sky_low", Color(0.24, 0.18, 0.12))
		crystal_m.set_shader_parameter("sky_gain", 1.0)
		crystal_m.set_shader_parameter("moon_dir", Vector3(0.0, 1.0, 0.0))
		crystal_m.set_shader_parameter("moon_light", Vector3(0.45, 0.38, 0.28))
		crystal_m.set_shader_parameter("glitter", 0.0)
		crystal_m.set_shader_parameter("haze", 0.0)
		crystal_m.set_shader_parameter("glow", 1.45)
		var lc := Verts.new()
		_build_lens_crystal(lc)
		lens_crystal_mi = MeshInstance3D.new()
		lens_crystal_mi.name = "LighthouseLensCrystal"
		lens_crystal_mi.mesh = lc.commit(crystal_m)
		lens_crystal_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lens_crystal_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		lens_rig.add_child(lens_crystal_mi)

		beam_m = ShaderMaterial.new()
		beam_m.shader = SHAFT_SHADER
		beam_m.set_shader_parameter("noise_map", noise)
		beam_m.set_shader_parameter("shaft_colour", BEAM_GOLD)
		beam_m.set_shader_parameter("shaft_level", _shaft_level)
		beam_m.set_shader_parameter("edge_softness", 2.45)
		beam_m.set_shader_parameter("wisp_strength", 0.48)
		var bm := Verts.new()
		_build_twin_beams(bm)
		beams_mi = MeshInstance3D.new()
		beams_mi.name = "LighthouseBeams"
		beams_mi.mesh = bm.commit(beam_m)
		beams_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beams_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		beams_mi.extra_cull_margin = 128.0
		beams_mi.add_to_group("env_see_through")
		lens_rig.add_child(beams_mi)

		# 2. Dark stormy Atlantic Ocean disc far below (y = -24 m, r = 165 m, opaque 1 draw).
		ocean_m = ShaderMaterial.new()
		ocean_m.shader = WATER_SHADER
		ocean_m.set_shader_parameter("caustic_map", caustics)
		ocean_m.set_shader_parameter("house_reference", float(k.room.get("ambient_level")))
		ocean_m.set_shader_parameter("ripple_scale", 10.5)
		ocean_m.set_shader_parameter("spill_strength", 0.18)
		ocean_m.set_shader_parameter("ambient_floor", 0.46)
		var ov := Verts.new()
		_build_atlantic_ocean(ov)
		ocean_mi = k._add_mesh("AtlanticOcean", ov.commit(ocean_m))
		ocean_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		ocean_mi.extra_cull_margin = 200.0

		# 3. Basalt headland cliff, exterior lighthouse tower drum, 5 outlying sea stacks & distant coastal lights.
		outside_m = ShaderMaterial.new()
		outside_m.shader = OUTSIDE_SHADER
		outside_m.set_shader_parameter("glitter", 0.0)
		outside_m.set_shader_parameter("haze", 0.0055)
		outside_m.set_shader_parameter("glow", 1.35)
		var hv := Verts.new()
		_build_headland_and_exterior_tower(hv)
		headland_mi = k._add_mesh("HeadlandOutside", hv.commit(outside_m))
		headland_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		headland_mi.extra_cull_margin = 200.0

		# 4. Distant bobbing & slowly flashing red harbour channel buoy seaward at BUOY_BASE.
		buoy_m = ShaderMaterial.new()
		buoy_m.shader = OUTSIDE_SHADER
		buoy_m.set_shader_parameter("glitter", 0.0)
		buoy_m.set_shader_parameter("haze", 0.0045)
		buoy_m.set_shader_parameter("glow", 1.8)
		var bv := Verts.new()
		_build_channel_buoy(bv)
		buoy_mi = k._add_mesh("ChannelBuoy", bv.commit(buoy_m))
		buoy_mi.position = BUOY_BASE
		buoy_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		buoy_mi.extra_cull_margin = 32.0

		tick(0.0)

	func tick(delta: float) -> void:
		if kit == null or lens_rig == null:
			return
		var host: Node = kit.host
		var sky: Node = host.system_of_kind("sky") if host != null else null

		var beam_mode := "sweeping"
		var storm_mode := "gale"
		var motion := 1.0
		var flicker_on := true
		var playing := false
		if host != null and host.has_method("setting"):
			var bm_v: Variant = host.setting("beam")
			if bm_v != null and str(bm_v) != "":
				beam_mode = str(bm_v)
			var st_v: Variant = host.setting("storm")
			if st_v != null and str(st_v) != "":
				storm_mode = str(st_v)
			var mot_v: Variant = host.setting("motion")
			if mot_v != null:
				motion = clampf(float(mot_v), 0.0, 1.0)
			var fl_v: Variant = host.setting("flicker")
			if fl_v != null:
				flicker_on = bool(fl_v)
			if host.get("timeline") != null:
				playing = str(host.timeline.state) in ["starting", "playing", "credits"]

		# 1. Rotate / hold the first-order Fresnel optical drum and twin beams serenely.
		if beam_mode == "sweeping":
			if delta > 0.0:
				_beam_yaw = fposmod(_beam_yaw + LENS_ROT_SPEED * motion * delta, TAU)
		elif beam_mode == "steady":
			var target_yaw := deg_to_rad(BEAM_STEADY_YAW_DEG)
			if not _initialized or delta <= 0.0:
				_beam_yaw = target_yaw
			else:
				var diff := wrapf(target_yaw - _beam_yaw, -PI, PI)
				_beam_yaw = fposmod(_beam_yaw + diff * (1.0 - exp(-delta * 1.4)), TAU)
		lens_rig.rotation.y = _beam_yaw

		# Volumetric beam intensity & warm crystal core level by setting.beam and film playback.
		var storm_mist := 1.0 if storm_mode == "gale" else (0.86 if storm_mode == "rain" else 0.72)
		var target_shaft := 0.0
		var target_core := 1.45
		match beam_mode:
			"sweeping":
				target_shaft = (0.34 if playing else 0.56) * storm_mist
				target_core = 1.12 if playing else 1.48
			"steady":
				target_shaft = (0.32 if playing else 0.52) * storm_mist
				target_core = 1.08 if playing else 1.42
			"lantern":
				target_shaft = 0.0
				target_core = 0.72 if playing else 1.02

		if not _initialized or delta <= 0.0:
			_shaft_level = target_shaft
			_core_glow = target_core
		else:
			var k_fade := 1.0 - exp(-delta * 1.8)
			_shaft_level = lerpf(_shaft_level, target_shaft, k_fade)
			_core_glow = lerpf(_core_glow, target_core, k_fade)

		var swell_rate := 1.0 if storm_mode == "gale" else (0.72 if storm_mode == "rain" else 0.45)
		if delta > 0.0:
			_ocean_clock += delta * motion * swell_rate
			_buoy_t += delta

		if beam_m != null:
			beam_m.set_shader_parameter("shaft_level", _shaft_level)
			beam_m.set_shader_parameter("clock", _ocean_clock)
			beam_m.set_shader_parameter("shaft_colour",
					BEAM_GOLD.lerp(Color(1.0, 0.80, 0.50), 0.25 if storm_mode == "gale" else 0.0))
		if beams_mi != null:
			beams_mi.visible = _shaft_level > 0.005
			beams_mi.set_meta("shaft_level", _shaft_level)
		if crystal_m != null:
			crystal_m.set_shader_parameter("glow", _core_glow)
		lens_rig.set_meta("beam_mode", beam_mode)
		lens_rig.set_meta("beam_yaw", _beam_yaw)
		lens_rig.set_meta("beam_level", _shaft_level)
		lens_rig.set_meta("core_glow", _core_glow)

		# 2. Sync Atlantic ocean & headland lighting to sky moon and storm mode.
		var moon_dir := Vector3(0.46, 0.28, -0.84).normalized()
		var moon_lvl := 0.72
		if sky != null and sky.has_method("moon_shine"):
			var ms: Dictionary = sky.moon_shine()
			var md: Vector3 = ms.get("direction", moon_dir)
			if md.length() > 0.01:
				moon_dir = md.normalized()
			moon_lvl = clampf(float(ms.get("level", 0.72)), 0.0, 1.0)
		var clear_k := 1.0 if storm_mode == "clear" else (0.52 if storm_mode == "rain" else 0.26)

		if ocean_m != null:
			ocean_m.set_shader_parameter("clock", _ocean_clock)
			ocean_m.set_shader_parameter("deep_colour",
					Color(0.010, 0.020, 0.048).lerp(Color(0.016, 0.036, 0.082), clear_k))
			ocean_m.set_shader_parameter("shallow_colour",
					Color(0.036, 0.068, 0.118).lerp(Color(0.052, 0.105, 0.175), clear_k))
			ocean_m.set_shader_parameter("sky_colour",
					Color(0.09, 0.14, 0.24).lerp(Color(0.18, 0.28, 0.46), clear_k))
			ocean_m.set_shader_parameter("caustic_colour",
					Color(0.32, 0.46, 0.62).lerp(Color(0.55, 0.72, 0.92), clear_k))
			ocean_m.set_shader_parameter("caustic_level", lerpf(0.62, 0.85, clear_k))
			ocean_m.set_shader_parameter("glint_dir", moon_dir)
			ocean_m.set_shader_parameter("glint_colour", Color(0.68, 0.82, 1.0))
			ocean_m.set_shader_parameter("glint_level", lerpf(0.42, 1.05, clear_k) * maxf(moon_lvl, 0.35))
			ocean_m.set_shader_parameter("ambient_floor", lerpf(0.44, 0.62, clear_k))
		if ocean_mi != null:
			ocean_mi.set_meta("clock", _ocean_clock)
			ocean_mi.set_meta("storm_mode", storm_mode)

		var sky_top := Color(0.025, 0.042, 0.085).lerp(Color(0.055, 0.095, 0.18), clear_k)
		var sky_low := Color(0.052, 0.078, 0.132).lerp(Color(0.10, 0.16, 0.27), clear_k)
		var m_light := Vector3(0.45, 0.56, 0.78) * lerpf(0.38, 1.05, clear_k) * maxf(moon_lvl, 0.35)
		var haze_val := 0.0068 if storm_mode == "gale" else (0.0046 if storm_mode == "rain" else 0.0024)
		for em: ShaderMaterial in [outside_m, buoy_m]:
			if em == null:
				continue
			em.set_shader_parameter("sky_top", sky_top)
			em.set_shader_parameter("sky_low", sky_low)
			em.set_shader_parameter("sky_gain", 1.15)
			em.set_shader_parameter("moon_dir", moon_dir)
			em.set_shader_parameter("moon_light", m_light)
			em.set_shader_parameter("haze", haze_val)

		# 3. Gently bob the harbour channel buoy on Atlantic swells & pulse its emerald beacon (< 0.4 Hz).
		if buoy_mi != null:
			var bob_amp := 0.34 if storm_mode == "gale" else (0.22 if storm_mode == "rain" else 0.12)
			var bob_y := bob_amp * sin(_ocean_clock * 1.18)
			var roll := deg_to_rad((6.2 if storm_mode == "gale" else 3.2) * sin(_ocean_clock * 0.92 + 0.7))
			var pitch := deg_to_rad((4.5 if storm_mode == "gale" else 2.4) * cos(_ocean_clock * 0.78))
			buoy_mi.position = BUOY_BASE + Vector3(0.0, bob_y, 0.0)
			buoy_mi.rotation = Vector3(pitch, 0.0, roll)
			var pulse := 1.65 if not flicker_on else (0.35 + 2.25 * pow(0.5 + 0.5 * cos(TAU * BUOY_PULSE_HZ * _buoy_t), 3.0))
			buoy_m.set_shader_parameter("glow", pulse)
			buoy_mi.set_meta("bob_y", bob_y)
			buoy_mi.set_meta("buoy_glow", pulse)

		_initialized = true

	## Sculpted burnished-brass framework, meridian ribs, twin bullseye bezels, upper clockwork gear crown, and
	## underside counterweight finial of the first-order Fresnel optical drum (in rig local coordinates).
	static func _build_lens_brass(b: RoomMesh) -> void:
		var flat_b := Basis(Vector3.RIGHT, -PI * 0.5)
		b.colour = _lin(BRASS_BRIGHT)
		# Heavy flanged upper & lower brass compression rings (y = -0.68, -0.38, +0.38, +0.68).
		for rd: Array in [[-0.68, 0.62, 0.70, 0.055], [-0.38, 0.84, 0.92, 0.055],
				[0.38, 0.84, 0.92, 0.055], [0.68, 0.62, 0.70, 0.055]]:
			Shapes.arch(b, Vector3(0.0, float(rd[0]), 0.0), float(rd[1]), float(rd[2]), float(rd[3]), 24,
					flat_b, 0.0, TAU, ["front", "back", "inner", "outer"])
		# Upper brass clockwork rotation gear ring & 16 radial gear teeth + top turntable drum.
		Shapes.arch(b, Vector3(0.0, 0.78, 0.0), 0.50, 0.64, 0.075, 24, flat_b, 0.0, TAU, ["front", "back", "inner", "outer"])
		for k in 16:
			var a := TAU * float(k) / 16.0
			var pb := Basis(Vector3.UP, a)
			b.box(Vector3(sin(a) * 0.66, 0.78, cos(a) * 0.66), Vector3(0.045, 0.068, 0.055), pb)
		# 8 vertical curved brass meridian ribs connecting lower & upper prism rings around the drum.
		b.colour = _lin(BRASS_WARM)
		for k in 8:
			var a := TAU * float(k) / 8.0 + PI / 8.0
			var d := Vector3(sin(a), 0.0, cos(a))
			Shapes.beam(b, d * 0.66 + Vector3(0.0, -0.68, 0.0), d * 0.89 + Vector3(0.0, -0.38, 0.0), Vector2(0.036, 0.036))
			Shapes.beam(b, d * 0.89 + Vector3(0.0, -0.38, 0.0), d * 0.89 + Vector3(0.0, 0.38, 0.0), Vector2(0.042, 0.042))
			Shapes.beam(b, d * 0.89 + Vector3(0.0, 0.38, 0.0), d * 0.66 + Vector3(0.0, 0.68, 0.0), Vector2(0.036, 0.036))
			# Inner radial brass spokes linking drum to central lamp gallery & underside counterweight!
			Shapes.beam(b, Vector3(0.0, -0.74, 0.0), d * 0.64 + Vector3(0.0, -0.68, 0.0), Vector2(0.032, 0.032))
			Shapes.beam(b, Vector3(0.0, 0.74, 0.0), d * 0.64 + Vector3(0.0, 0.68, 0.0), Vector2(0.032, 0.032))

		# Twin opposite sculpted circular brass bullseye bezels projecting along local -Z and +Z (matching beams!).
		b.colour = _lin(BRASS_BRIGHT)
		for side: float in [-1.0, 1.0]:
			var bz := Basis(Vector3.UP, 0.0 if side > 0.0 else PI)
			var bc := Vector3(0.0, 0.0, side * 0.88)
			Shapes.arch(b, bc, 0.34, 0.40, 0.065, 22, bz, 0.0, TAU, ["front", "back", "inner", "outer"])
			Shapes.arch(b, bc + Vector3(0.0, 0.0, side * 0.04), 0.21, 0.245, 0.045, 18, bz, 0.0, TAU,
					["front", "back", "inner", "outer"])
			Shapes.arch(b, bc + Vector3(0.0, 0.0, side * 0.07), 0.11, 0.135, 0.036, 16, bz, 0.0, TAU,
					["front", "back", "inner", "outer"])
			for sp in 4:
				var sa := float(sp) * PI * 0.5 + PI * 0.25
				var p0 := bc + Vector3(cos(sa) * 0.12, sin(sa) * 0.12, side * 0.045)
				var p1 := bc + Vector3(cos(sa) * 0.37, sin(sa) * 0.37, side * 0.01)
				Shapes.beam(b, p0, p1, Vector2(0.022, 0.022))

		# Jewel-like turned brass underside optical counterweight & mercury bath finial boss (seen looking up!).
		Shapes.lathe(b, [
			Vector2(0.0, -0.96), Vector2(0.06, -0.90), Vector2(0.11, -0.82),
			Vector2(0.24, -0.76), Vector2(0.28, -0.68), Vector2(0.18, -0.62),
			Vector2(0.16, -0.44), Vector2(0.24, -0.38),
		], Vector3.ZERO, 16)
		# Brass chimney vent flue rising from the central lamp core through the turntable crown.
		Shapes.cylinder(b, Vector3(0.0, 0.36, 0.0), 0.14, 0.54, 14)

	## Stepped concentric crystal catadioptric prism rings, warm glowing multi-wick ivory lamp core, and twin luminous
	## stepped Fresnel bullseye lenses (opaque self-lit optical shader, zero blend overdraw!).
	static func _build_lens_crystal(v: Verts) -> void:
		var core_c := _lin(CRYSTAL_CORE, 0.0)
		var warm_c := _lin(Color(1.0, 0.87, 0.58), 0.0)
		var prism_hi := _lin(Color(0.95, 0.92, 0.78), 0.0)
		var prism_lo := _lin(CRYSTAL_PRISM * 0.72, 0.0)

		# 1. Central warm glowing ivory incandescent mantle core (y = -0.34 .. +0.34, r = 0.24).
		v.lathe([
			Vector2(0.0, -0.36), Vector2(0.18, -0.32), Vector2(0.25, -0.14),
			Vector2(0.26, 0.14), Vector2(0.18, 0.32), Vector2(0.0, 0.36),
		], Vector3.ZERO, 16, [warm_c, warm_c, core_c, core_c, warm_c, warm_c])

		# 2. Concentric stepped catadioptric crystal prism drum (lower, central belt & upper stepped sawtooth rings!).
		var prof: Array = [
			Vector2(0.62, -0.66), Vector2(0.70, -0.61), Vector2(0.66, -0.56),
			Vector2(0.77, -0.50), Vector2(0.73, -0.44), Vector2(0.86, -0.37),
			Vector2(0.84, -0.18), Vector2(0.87, 0.00), Vector2(0.84, 0.18),
			Vector2(0.86, 0.37), Vector2(0.73, 0.44), Vector2(0.77, 0.50),
			Vector2(0.66, 0.56), Vector2(0.70, 0.61), Vector2(0.62, 0.66),
		]
		var cols: Array = [
			prism_lo, prism_hi, prism_lo,
			prism_hi, prism_lo, warm_c,
			prism_hi, warm_c, prism_hi,
			warm_c, prism_lo, prism_hi,
			prism_lo, prism_hi, prism_lo,
		]
		v.lathe(prof, Vector3.ZERO, 24, cols)

		# 3. Twin dramatic stepped Fresnel crystal bullseyes protruding cleanly along local -Z and +Z!
		for side: float in [-1.0, 1.0]:
			var b_bull := Basis(Vector3.RIGHT, side * PI * 0.5)
			v.lathe([
				Vector2(0.35, 0.0), Vector2(0.33, 0.03), Vector2(0.24, 0.045),
				Vector2(0.22, 0.075), Vector2(0.13, 0.09), Vector2(0.11, 0.125),
				Vector2(0.0, 0.145),
			], Vector3(0.0, 0.0, side * 0.87), 20, [prism_lo, prism_hi, warm_c, warm_c, core_c, core_c, core_c], b_bull)

	## Twin outward-flaring volumetric golden-ivory Fresnel light cones along local -Z and +Z, angled gently (-1.4 deg)
	## so they stay cleanly ABOVE the cinema screen (y > 4.0 m at screen plane) while sweeping out over the Atlantic!
	static func _build_twin_beams(v: Verts) -> void:
		var sides := 24
		var pitch := deg_to_rad(-1.4)
		# Stations: [dist_from_lens, cone_radius, uv_y, alpha_weight]
		var stations: Array = [
			[0.95, 0.26, 0.00, 0.16],
			[1.85, 0.34, 0.12, 0.62],
			[5.35, 0.56, 0.24, 0.78],
			[16.0, 1.18, 0.42, 0.96],
			[48.0, 2.85, 0.68, 0.80],
			[98.0, 5.40, 1.00, 0.00],
		]
		for side: float in [-1.0, 1.0]:
			var dir := Vector3(0.0, sin(pitch), side * cos(pitch)).normalized()
			var ax := Vector3.RIGHT * side
			var ay := dir.cross(ax).normalized()
			for ri in stations.size() - 1:
				var s0: Array = stations[ri]
				var s1: Array = stations[ri + 1]
				var c0 := dir * float(s0[0])
				var c1 := dir * float(s1[0])
				var r0 := float(s0[1])
				var r1 := float(s1[1])
				var v0 := float(s0[2])
				var v1 := float(s1[2])
				var col0 := Color(1.0, 0.97, 0.90, float(s0[3]))
				var col1 := Color(1.0, 0.95, 0.85, float(s1[3]))
				for si in sides:
					var u0 := float(si) / float(sides)
					var u1 := float(si + 1) / float(sides)
					var a0 := u0 * TAU
					var a1 := u1 * TAU
					var d0 := ax * cos(a0) + ay * sin(a0)
					var d1 := ax * cos(a1) + ay * sin(a1)
					var p00 := c0 + d0 * r0
					var p10 := c0 + d1 * r0
					var p11 := c1 + d1 * r1
					var p01 := c1 + d0 * r1
					var nrm := ((d0 + d1) * 0.5).normalized()
					v.quad(p00, p10, p11, p01, nrm, [col0, col0, col1, col1],
							[Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])

	## Circular moody Atlantic ocean disc at y = -24 m (r = 172 m, 1 draw, opaque): COLOR.r marks frothy surf rings
	## around the headland base and outlying sea-stacks; COLOR.g softly boosts the moonlit seaward sheen.
	static func _build_atlantic_ocean(v: Verts) -> void:
		var radii: Array[float] = [6.0, 10.5, 16.0, 22.0, 30.0, 40.0, 54.0, 72.0, 96.0, 122.0, 148.0, SEA_RADIUS]
		var segs := 48
		for ri in radii.size() - 1:
			var r0 := radii[ri]
			var r1 := radii[ri + 1]
			for si in segs:
				var a0 := TAU * float(si) / float(segs)
				var a1 := TAU * float((si + 1) % segs) / float(segs)
				var p00 := Vector3(CX + sin(a0) * r0, SEA_Y, CZ - cos(a0) * r0)
				var p10 := Vector3(CX + sin(a1) * r0, SEA_Y, CZ - cos(a1) * r0)
				var p11 := Vector3(CX + sin(a1) * r1, SEA_Y, CZ - cos(a1) * r1)
				var p01 := Vector3(CX + sin(a0) * r1, SEA_Y, CZ - cos(a0) * r1)
				v.quad(p00, p10, p11, p01, Vector3.UP, [
					_ocean_col(p00), _ocean_col(p10), _ocean_col(p11), _ocean_col(p01)
				])

	static func _ocean_col(p: Vector3) -> Color:
		var d_tower := Vector2(p.x - CX, p.z - CZ).length()
		var foam := clampf(1.0 - smoothstep(10.0, 23.0, d_tower), 0.0, 1.0) * 0.92
		for st: Array in SEA_STACKS:
			var ds := Vector2(p.x - float(st[0]), p.z - float(st[1])).length()
			foam = maxf(foam, (1.0 - smoothstep(float(st[2]) * 0.7, float(st[2]) + 7.5, ds)) * 0.85)
		# Gentle moonlight sheen boost along the forward-starboard Atlantic horizon.
		var dir2 := Vector2(p.x - CX, p.z - CZ).normalized()
		var moon2 := Vector2(0.48, -0.88).normalized()
		var road := pow(maxf(dir2.dot(moon2), 0.0), 5.0) * smoothstep(20.0, 110.0, d_tower) * 0.45
		return Color(foam, road, 0.0, 1.0)

	## Tapered whitewashed-and-crimson exterior lighthouse tower shaft, jagged dark wet basalt headland promontory,
	## five outlying Atlantic sea stacks, and distant dark coastal headland hills with tiny warm harbour lights.
	static func _build_headland_and_exterior_tower(v: Verts) -> void:
		# 1. Tapered exterior lighthouse masonry drum (y = -15.5 .. -0.35 m) with classic red coastal daymark band!
		var ww := _lin(WHITEWASH, 1.0)
		var wws := _lin(WHITEWASH_SHADE, 1.0)
		var red := _lin(CRIMSON_BAND, 1.0)
		v.lathe([
			Vector2(7.55, -15.5), Vector2(7.00, -11.0), Vector2(6.55, -8.5),
			Vector2(6.55, -8.45), Vector2(6.22, -4.85), Vector2(6.22, -4.80),
			Vector2(5.88, -1.25), Vector2(5.78, -0.35),
		], Vector3(CX, 0.0, CZ), 24, [wws, ww, ww, red, red, ww, ww, wws])

		# 2. Craggy wet dark basalt headland cliff directly beneath the tower (y = -24.6 .. -14.2 m).
		var rock_lo := _lin(BASALT_DARK, 1.0)
		var rock_hi := _lin(BASALT_WET, 1.0)
		var foam_c := _lin(FOAM_PALE, 1.0)
		var cliff_segs := 28
		var cliff_rings: Array = [
			[7.35, -14.8, rock_hi],
			[10.2, -16.4, rock_hi],
			[13.8, -19.2, rock_lo],
			[17.6, -22.2, rock_lo],
			[20.4, -24.6, foam_c],
		]
		for ri in cliff_rings.size() - 1:
			var r0_d: Array = cliff_rings[ri]
			var r1_d: Array = cliff_rings[ri + 1]
			for si in cliff_segs:
				var a0 := TAU * float(si) / float(cliff_segs)
				var a1 := TAU * float((si + 1) % cliff_segs) / float(cliff_segs)
				var p00 := _cliff_pt(a0, float(r0_d[0]), float(r0_d[1]), ri)
				var p10 := _cliff_pt(a1, float(r0_d[0]), float(r0_d[1]), ri)
				var p11 := _cliff_pt(a1, float(r1_d[0]), float(r1_d[1]), ri + 1)
				var p01 := _cliff_pt(a0, float(r1_d[0]), float(r1_d[1]), ri + 1)
				var nrm := (p10 - p00).cross(p01 - p00).normalized()
				if nrm.dot(Vector3(sin(a0), 0.35, -cos(a0))) < 0.0:
					nrm = -nrm
				v.quad(p00, p10, p11, p01, nrm, [r0_d[2], r0_d[2], r1_d[2], r1_d[2]])

		# 3. Five outlying jagged basalt sea-stacks breaking the Atlantic surf.
		for st: Array in SEA_STACKS:
			_add_sea_stack(v, float(st[0]), float(st[1]), float(st[2]), float(st[3]), int(st[4]))

		# 4. Distant dark mainland coastal headland silhouette (aft-starboard & aft arc, r = 132 m) + 20 warm
		# harbour village & pierhead lights glowing softly across the dark horizon!
		var coast_segs := 24
		var az_start := deg_to_rad(104.0)
		var az_end := deg_to_rad(256.0)
		var hill_lo := _lin(Color(0.05, 0.065, 0.095), 1.0)
		var hill_hi := _lin(Color(0.095, 0.12, 0.165), 1.0)
		for k in coast_segs:
			var t0 := float(k) / float(coast_segs)
			var t1 := float(k + 1) / float(coast_segs)
			var a0 := lerpf(az_start, az_end, t0)
			var a1 := lerpf(az_start, az_end, t1)
			var h0 := -24.0 + 28.5 * sin(t0 * PI) * (0.68 + 0.32 * sin(t0 * 11.0 + 0.6))
			var h1 := -24.0 + 28.5 * sin(t1 * PI) * (0.68 + 0.32 * sin(t1 * 11.0 + 0.6))
			var r_c := 132.0
			var b0 := Vector3(CX + sin(a0) * r_c, -24.6, CZ - cos(a0) * r_c)
			var b1 := Vector3(CX + sin(a1) * r_c, -24.6, CZ - cos(a1) * r_c)
			var top1 := Vector3(CX + sin(a1) * (r_c + 8.0), h1, CZ - cos(a1) * (r_c + 8.0))
			var top0 := Vector3(CX + sin(a0) * (r_c + 8.0), h0, CZ - cos(a0) * (r_c + 8.0))
			var into := Vector3(-sin((a0 + a1) * 0.5), 0.25, cos((a0 + a1) * 0.5)).normalized()
			v.quad(b0, b1, top1, top0, into, [hill_lo, hill_lo, hill_hi, hill_hi])
		# Distant warm harbour village & breakwater lights along the coast (COLOR.a = 0.0 -> self-lit).
		var lit_warm := _lin(Color(1.0, 0.78, 0.42), 0.0)
		for k in 20:
			var tf := (float(k) + 0.5) / 20.0
			var az := lerpf(deg_to_rad(118.0), deg_to_rad(242.0), tf)
			var rr := 124.0 + fmod(float(k) * 3.7, 9.0)
			var ly := -2.2 + fmod(float(k) * 1.37, 4.4)
			var lp := Vector3(CX + sin(az) * rr, ly, CZ - cos(az) * rr)
			v.box(lp, Vector3(0.95, 0.72, 0.95), Basis(Vector3.UP, az), lit_warm)

	static func _cliff_pt(az: float, base_r: float, y: float, ring_i: int) -> Vector3:
		# Extend rocky headland ridge aft-starboard (+Z/+X) toward the mainland while keeping seaward side precipitous.
		var land_ext := maxf(0.0, sin(az - 2.4)) * float(ring_i) * 3.6
		var jag := 1.0 + 0.16 * sin(az * 5.0 + float(ring_i) * 1.4) + 0.10 * cos(az * 9.0 - float(ring_i) * 2.1)
		var r := base_r * jag + land_ext
		var dy := (0.65 * sin(az * 7.0 + float(ring_i))) if ring_i < 4 else 0.0
		return Vector3(CX + sin(az) * r, y + dy, CZ - cos(az) * r)

	static func _add_sea_stack(v: Verts, x: float, z: float, r: float, h: float, sd: int) -> void:
		var rock_lo := _lin(BASALT_DARK, 1.0)
		var rock_hi := _lin(BASALT_WET, 1.0)
		var foam_c := _lin(FOAM_PALE, 1.0)
		var sides := 10
		var apex := Vector3(x + sin(float(sd)) * 1.1, SEA_Y + h, z + cos(float(sd)) * 1.1)
		for k in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var k1 := (k + 1) % sides
			var j0 := 0.80 + 0.34 * fposmod(sin(float(sd * 13 + k * 7)) * 4375.5, 1.0)
			var j1 := 0.80 + 0.34 * fposmod(sin(float(sd * 13 + k1 * 7)) * 4375.5, 1.0)
			var d0 := Vector3(sin(a0), 0.0, cos(a0))
			var d1 := Vector3(sin(a1), 0.0, cos(a1))
			var b0 := Vector3(x, SEA_Y - 0.8, z) + d0 * (r * j0)
			var b1 := Vector3(x, SEA_Y - 0.8, z) + d1 * (r * j1)
			var m0 := b0.lerp(apex, 0.58) + d0 * (r * 0.14) + Vector3(0.0, 0.4, 0.0)
			var m1 := b1.lerp(apex, 0.58) + d1 * (r * 0.14) + Vector3(0.0, 0.4, 0.0)
			var nrm := ((d0 + d1).normalized() + Vector3(0.0, 0.35, 0.0)).normalized()
			v.quad(b0, b1, m1, m0, nrm, [foam_c, foam_c, rock_lo, rock_lo])
			v.tri(m0, m1, apex, nrm, rock_hi)

	## Red-iron maritime harbour channel bell buoy with high lattice tower frame & pulsing emerald navigation beacon.
	static func _build_channel_buoy(v: Verts) -> void:
		var red := _lin(BUOY_RED, 1.0)
		var dark := _lin(IRON_DARK, 1.0)
		var beacon := _lin(BUOY_BEACON, 0.0) # self-lit pulsing navigation light!
		# Floating red steel pontoon hull.
		v.lathe([
			Vector2(1.65, -0.6), Vector2(2.05, 0.30), Vector2(1.90, 1.35),
			Vector2(1.30, 1.95), Vector2(0.0, 2.05),
		], Vector3.ZERO, 12, [dark, red, red, red, red])
		# Four tapered red-iron lattice legs supporting the high-focal-plane beacon lantern gallery.
		for k in 4:
			var a := float(k) * PI * 0.5 + PI * 0.25
			var p0 := Vector3(sin(a) * 1.30, 1.80, cos(a) * 1.30)
			var p1 := Vector3(sin(a) * 0.48, 7.15, cos(a) * 0.48)
			var mid := (p0 + p1) * 0.5
			var dir := (p1 - p0).normalized()
			var right := Vector3.UP.cross(dir)
			right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
			var b := Basis(right, dir, right.cross(dir))
			v.box(mid, Vector3(0.16, p0.distance_to(p1), 0.16), b, red)
		v.box(Vector3(0.0, 7.15, 0.0), Vector3(1.26, 0.22, 1.26), Basis(), dark)
		# Glowing emerald-green channel beacon lantern globe on top (y = 7.28 .. 8.48 m).
		v.lathe([
			Vector2(0.38, 7.28), Vector2(0.56, 7.66), Vector2(0.54, 8.12),
			Vector2(0.34, 8.40), Vector2(0.0, 8.52),
		], Vector3.ZERO, 12, beacon)


# --- Entry point ------------------------------------------------------------------------------------------------------

static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"lighthouse_tower":
			_build_tower(c)
		"lighthouse_lens":
			var h := _hall(c)
			h.brass_mat = _brass(c)
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove]:
		b.colour = Color.WHITE


static func _hall(c: Object) -> LighthouseHall:
	for h: Object in c.halls:
		if h is LighthouseHall:
			return h
	var h := LighthouseHall.new()
	h.kit = c.kit
	c.halls.append(h)
	return h


# --- Shared helpers ---------------------------------------------------------------------------------------------------

static func _lin(colour: Color, alpha := 1.0) -> Color:
	var l := colour.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _brass(c: Object) -> Material:
	return c.shiny("gilt", 1.0, 0.80, 0.18)


static func _solid(c: Object, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, basis))


static func _bay_az(bay_i: int) -> float:
	# 16 bays around 360 deg: bay 0 sits squarely at az = 0 (directly ahead -Z); bay 8 squarely aft (+Z).
	return float(bay_i) * TAU / float(BAYS)


static func _post_az(post_i: int) -> float:
	# 16 vertical iron stanchions straddling each bay (az = +/-11.25 deg, +/-33.75 deg, ...).
	return (float(post_i) + 0.5) * TAU / float(BAYS)


static func _ring_pt(r: float, az: float, y: float) -> Vector3:
	return Vector3(CX + sin(az) * r, y, CZ - cos(az) * r)


static func _bay_basis(az: float) -> Basis:
	# Local +Z points INWARD toward the tower centre; local +X runs clockwise along the perimeter.
	var into := Vector3(-sin(az), 0.0, cos(az)).normalized()
	var tang := Vector3(cos(az), 0.0, sin(az)).normalized()
	return Basis(tang, Vector3.UP, into)


# --- Piece 1: lighthouse_tower ----------------------------------------------------------------------------------------

static func _build_tower(c: Object) -> void:
	# Compact lightmap atlas (keeps atlas well under 1024x1024 and build fast).
	c.s.texel = 0.16
	_floor_and_compass_rose(c)
	_parapet_drum_and_coves(c)
	_glazing_cage_and_astragals(c)
	_copper_lantern_dome(c)
	_exterior_catwalk_gallery(c)
	_screen_mount(c)
	_aft_spiral_stair_and_chronometer(c)
	_port_chart_desk_and_telescope(c)
	_starboard_locker_barometer_and_rope(c)
	_gimbal_storm_lanterns_and_bake_lights(c)


## Oak plank watchroom floor with clean circular cutout for the aft spiral-stair hatch, dark riveted iron perimeter
## flange ring, and ornate inlaid brass & slate compass rose radiating across the central deck.
static func _floor_and_compass_rose(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood: Material = c.tinted("wood")
	var iron: Material = c.tinted("iron")
	var brass: Material = _brass(c)

	# 1. Main circular oak plank deck (r = 5.55 m around (CX, CZ)) with exact circular cutout at HATCH_C (r = HATCH_R)!
	s.surface(wood)
	s.colour = _lin(OAK_DECK)
	var segs := 32
	var inner_ring := PackedVector3Array()
	var outer_ring := PackedVector3Array()
	var ups := PackedVector3Array()
	var dx := HATCH_C.x - CX
	var dz := HATCH_C.z - CZ
	var c_term := dx * dx + dz * dz - R_INNER * R_INNER
	for k in segs + 1:
		var a := TAU * float(k % segs) / float(segs)
		var vx := sin(a)
		var vz := cos(a)
		var b_term := dx * vx + dz * vz
		var t_hit := -b_term + sqrt(maxf(b_term * b_term - c_term, 0.01))
		inner_ring.append(Vector3(HATCH_C.x + vx * HATCH_R, 0.0, HATCH_C.z + vz * HATCH_R))
		outer_ring.append(Vector3(HATCH_C.x + vx * t_hit, 0.0, HATCH_C.z + vz * t_hit))
		ups.append(Vector3.UP)
	s.strip(inner_ring, outer_ring, ups)

	# 2. Riveted dark-iron perimeter deck flange ring (r = 5.08 .. 5.55 m) & raised cast-iron deck rivets.
	s.surface(iron)
	s.colour = _lin(IRON_DARK)
	_annulus(s, 5.08, R_INNER, 0.004, 32)
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	_annulus(u, 5.04, 5.09, 0.007, 40)
	for k in 32:
		var az := TAU * float(k) / 32.0
		u.box(_ring_pt(5.26, az, 0.011), Vector3(0.036, 0.014, 0.036), Basis(Vector3.UP, az), [RoomMesh.DOWN])

	# 3. Ornate inlaid brass & dark-slate nautical compass rose centred at (0.0, 0.006, -0.55), radiating prominently
	# around and ahead of the central captain's club chairs!
	var rc := Vector3(0.0, 0.006, -0.55)
	var flat_b := Basis(Vector3.RIGHT, -PI * 0.5)
	# Dark slate circular inlay disc beneath the brass star.
	u.surface(c.soft("iron", true))
	u.colour = _lin(IRON_NAVY * 0.85)
	Shapes.cylinder(u, rc - Vector3(0.0, 0.003, 0.0), 2.48, 0.005, 32)
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.arch(u, rc + Vector3(0.0, 0.004, 0.0), 2.38, 2.50, 0.006, 40, flat_b, 0.0, TAU, ["front"])
	Shapes.arch(u, rc + Vector3(0.0, 0.004, 0.0), 1.98, 2.04, 0.006, 36, flat_b, 0.0, TAU, ["front"])
	Shapes.arch(u, rc + Vector3(0.0, 0.004, 0.0), 0.44, 0.50, 0.006, 24, flat_b, 0.0, TAU, ["front"])
	# 32 compass degree ticks around the outer azimuth chapter ring.
	for k in 32:
		var a := float(k) * TAU / 32.0
		var major := (k % 4 == 0)
		var r_mid := 2.21
		u.box(rc + Vector3(sin(a) * r_mid, 0.004, cos(a) * r_mid),
				Vector3(0.032 if major else 0.016, 0.006, 0.34 if major else 0.20),
				Basis(Vector3.UP, a), [RoomMesh.DOWN])
	# 8-point alternating burnished-brass & dark-iron compass rose star needles!
	for k in 8:
		var a := float(k) * PI * 0.25
		var tip_r := 2.36 if k % 2 == 0 else 1.72
		var half_w := 0.28 if k % 2 == 0 else 0.19
		var dir := Vector3(sin(a), 0.0, cos(a))
		var side := Vector3(cos(a), 0.0, -sin(a))
		var p_c := rc + Vector3(0.0, 0.007, 0.0)
		var p_t := p_c + dir * tip_r
		var p_l := p_c + dir * 0.32 - side * half_w
		var p_r := p_c + dir * 0.32 + side * half_w
		u.surface(brass)
		u.colour = _lin(BRASS_BRIGHT)
		u.face([p_c, p_t, p_r], Vector3.UP)
		u.surface(c.soft("iron", true))
		u.colour = _lin(IRON_DARK)
		u.face([p_c, p_l, p_t], Vector3.UP)
	# Central polished brass hub medallion.
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.cylinder(u, rc + Vector3(0.0, 0.005, 0.0), 0.16, 0.008, 16)


static func _annulus(b: RoomMesh, r_in: float, r_out: float, y: float, sides: int) -> void:
	var a := PackedVector3Array()
	var bb := PackedVector3Array()
	var ns := PackedVector3Array()
	for k in sides + 1:
		var ang := TAU * float(k % sides) / float(sides)
		var d := Vector3(sin(ang), 0.0, cos(ang))
		a.append(Vector3(CX, y, CZ) + d * r_in)
		bb.append(Vector3(CX, y, CZ) + d * r_out)
		ns.append(Vector3.UP)
	b.strip(a, bb, ns)


## Circular thick whitewashed stone drum & waist-height painted crimson/navy riveted cast-iron panelled parapet
## (y = 0.0 .. 1.15 m) with oak/brass sill rail, heavy brass rivets, and subtle recessed warm indirect cove wash.
static func _parapet_drum_and_coves(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var iron: Material = c.tinted("iron")
	var plaster: Material = c.tinted("plaster", "lime_wash")
	var wood: Material = c.tinted("wood")
	var brass: Material = _brass(c)
	var cove_m: Material = c.kit.cove_material()

	# 1. Thick exterior whitewashed lime-stone parapet drum (r = 5.56 .. 5.88 m, y = -0.35 .. 1.14 m) seen through
	# lower glazing & window sills, giving genuine thick coastal stone lighthouse mass!
	s.surface(plaster)
	s.colour = _lin(WHITEWASH)
	Shapes.lathe(s, [Vector2(R_OUTER, -0.35), Vector2(R_OUTER, PARAPET_H)], Vector3(CX, 0.0, CZ), 32)
	s.colour = _lin(WHITEWASH_SHADE)
	_annulus(s, R_INNER, R_OUTER, PARAPET_H, 32)

	# 2. Inner watchroom circular painted cast-iron dado drum (y = 0.0 .. PARAPET_H - 0.06, r = 5.55 m, facing inward).
	s.surface(iron)
	s.colour = _lin(IRON_NAVY)
	Shapes.lathe(s, [Vector2(R_INNER, PARAPET_H - 0.06), Vector2(R_INNER, 0.0)], Vector3(CX, 0.0, CZ), 32)
	# Heavy dark-iron base skirting kerb (y = 0.0 .. 0.13 m).
	s.colour = _lin(IRON_DARK)
	Shapes.lathe(s, [Vector2(R_INNER - 0.07, 0.13), Vector2(R_INNER - 0.07, 0.0)], Vector3(CX, 0.0, CZ), 32)
	_annulus(s, R_INNER - 0.07, R_INNER, 0.13, 32)

	# 3. Sixteen recessed painted crimson cast-iron parapet panels with navy bolted stile ribs, whitewashed stone
	# upper frieze reveals, gleaming raised brass rivets, and per-bay recessed warm indirect sill coves!
	var chord := 2.0 * R_INNER * sin(PI / float(BAYS))
	c.cove.surface(cove_m)
	for i in BAYS:
		var az := _bay_az(i)
		var bb := _bay_basis(az)
		var p_wall := _ring_pt(R_INNER - 0.015, az, 0.0)
		# Deep heritage crimson cast-iron panel field (baked, y = 0.18 .. 0.78 m).
		s.surface(iron)
		s.colour = _lin(CRIMSON_PANEL)
		s.box(p_wall + Vector3(0.0, 0.48, 0.0) + bb.z * 0.018, Vector3(chord - 0.24, 0.60, 0.042), bb, [RoomMesh.FRONT])
		# Whitewashed stone reveal band tucked neatly beneath the oak sill coping (y = 0.79 .. 0.99 m, inner face r ~ 5.505 m).
		s.surface(plaster)
		s.colour = _lin(WHITEWASH)
		s.box(p_wall + Vector3(0.0, 0.89, 0.0) + bb.z * 0.010, Vector3(chord - 0.16, 0.20, 0.045), bb, [RoomMesh.FRONT])
		# Per-bay recessed warm oil-amber indirect sill cove strictly 0.015 m inside the flat whitewashed reveal &
		# cleanly between the cast-iron stile posts (zero polygon clipping!).
		var half_cw := (chord - 0.20) * 0.5
		var bay_rows: Array = []
		var bay_norms: Array = []
		var bay_cols: Array = []
		for c_def: Array in [[0.985, 0.56], [0.895, 0.20], [0.795, 0.0]]:
			var yy := float(c_def[0])
			var w := float(c_def[1])
			var mid_c := p_wall + Vector3(0.0, yy, 0.0) + bb.z * 0.046
			bay_rows.append(PackedVector3Array([mid_c - bb.x * half_cw, mid_c + bb.x * half_cw]))
			bay_norms.append(PackedVector3Array([bb.z, bb.z]))
			bay_cols.append(PackedColorArray([_lin(WHITEWASH, w), _lin(WHITEWASH, w)]))
		c.cove.grid(bay_rows, bay_norms, bay_cols)
		# Polished oak & brushed-brass panoramic sill coping ledge along each bay (y = 0.99 .. 1.05 m).
		s.surface(wood)
		s.colour = _lin(OAK_DARK)
		s.box(_ring_pt(R_INNER - 0.02, az, PARAPET_H), Vector3(chord + 0.04, 0.06, 0.30), bb)
		# Cast-iron bolted stile post between bays + heavy gleaming brass flange rivets & brass sill lip trim!
		var paz := _post_az(i)
		var pb := _bay_basis(paz)
		var pp := _ring_pt(R_INNER - 0.05, paz, 0.50)
		s.surface(iron)
		s.colour = _lin(IRON_NAVY)
		s.box(pp, Vector3(0.14, 0.96, 0.11), pb, [RoomMesh.FRONT, RoomMesh.DOWN])
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		for ry: float in [0.20, 0.49, 0.78]:
			u.box(pp + Vector3(0.0, ry - 0.50, 0.0) + pb.z * 0.06, Vector3(0.032, 0.032, 0.024), pb)
		# Continuous brass top sill beading rail inside each bay.
		u.colour = _lin(BRASS_BRIGHT)
		u.box(_ring_pt(R_INNER - 0.16, az, PARAPET_H + 0.006), Vector3(chord - 0.04, 0.028, 0.032), bb)
		# Heavy brass inspection boss plate centred on every second parapet panel.
		if i % 2 == 1:
			u.colour = _lin(BRASS_WARM)
			u.box(p_wall + Vector3(0.0, 0.48, 0.0) + bb.z * 0.052, Vector3(0.24, 0.13, 0.024), bb)


## Soaring 360-degree panoramic curved lantern glazing cage (y = 1.18 .. 5.40 m, 16 bays) with sleek dark-iron
## structural standards, horizontal brass transom rings, iconic criss-crossing helical diamond brass astragal bars,
## and single-surface curved storm glazing (`PieceGlass`).
static func _glazing_cage_and_astragals(c: Object) -> void:
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var iron_u: Material = c.soft("iron", true)
	var brass: Material = _brass(c)
	glass.surface(c.kit.GLASS)

	var y0 := PARAPET_H + 0.03 # 1.05 m (top of oak sill coping)
	var y1 := CAGE_TOP
	var h := y1 - y0
	var chord_g := 2.0 * R_GLASS * tan(PI / float(BAYS))

	# 1. Sixteen dark-iron main vertical lantern cage standards + brass collar rings + physics boxes.
	for i in BAYS:
		var paz := _post_az(i)
		var pb := _bay_basis(paz)
		var p_mid := _ring_pt(R_MULLION, paz, (y0 + y1) * 0.5)
		u.surface(iron_u)
		u.colour = _lin(IRON_DARK)
		u.box(p_mid, Vector3(0.068, h, 0.088), pb)
		u.surface(brass)
		u.colour = _lin(BRASS_BRIGHT)
		for cy: float in [1.12, 2.50, 3.95, 5.34]:
			u.box(_ring_pt(R_MULLION, paz, cy), Vector3(0.092, 0.055, 0.112), pb)
		# Physics box along outer glazing standard (r = 5.45 m, completely clear of seats & viewer).
		_solid(c, p_mid, Vector3(0.14, h, 0.16), pb)

	# 2. Horizontal brass transom rings (y = 2.50 m and 3.95 m -> 3 equal 1.45 m tiers) + iconic helical diamond brass
	# astragal bars across every bay + single-surface storm glazing (`PieceGlass`)!
	var tiers: Array = [[y0, 2.50], [2.50, 3.95], [3.95, y1]]
	for i in BAYS:
		var az_l := _post_az(i)
		var az_r := _post_az((i + 1) % BAYS)
		var az_m := _bay_az((i + 1) % BAYS)
		var bb := _bay_basis(az_m)

		# Horizontal brass transoms across the bay.
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		for ty: float in [2.50, 3.95]:
			var p_l := _ring_pt(R_MULLION, az_l, ty)
			var p_r := _ring_pt(R_MULLION, az_r, ty)
			Shapes.beam(u, p_l, p_r, Vector2(0.034, 0.036))

		# Iconic helical diamond brass astragal mullions criss-crossing cleanly in all 3 vertical tiers!
		for tier: Array in tiers:
			var ty0 := float(tier[0])
			var ty1 := float(tier[1])
			var bl := _ring_pt(R_MULLION, az_l, ty0)
			var br := _ring_pt(R_MULLION, az_r, ty0)
			var tl := _ring_pt(R_MULLION, az_l, ty1)
			var tr := _ring_pt(R_MULLION, az_r, ty1)
			Shapes.beam(u, bl, tr, Vector2(0.024, 0.028))
			Shapes.beam(u, br, tl, Vector2(0.024, 0.028))

		# Single-surface storm lantern glass pane (`PieceGlass`, 1 quad per bay, facing inward).
		var gc := _ring_pt(R_GLASS, az_m, (y0 + y1) * 0.5)
		Shapes.quad(glass, gc, bb.x * (chord_g * 0.5), Vector3.UP * (h * 0.5), bb.z)


## Ribbed patinated dark-copper conical lantern dome (y = 5.40 .. 7.62 m) with bronze cornice ring, warm dome uplight
## cove (`PieceCove`), 16 converging structural copper-and-brass ribs, central louvered brass ventilator ball, and
## gleaming brass suspension collar holding the rotating Fresnel lens rig overhead!
static func _copper_lantern_dome(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var iron: Material = c.tinted("iron")
	var brass: Material = _brass(c)
	var cove_m: Material = c.kit.cove_material()

	# 1. Heavy cast-bronze upper cornice ring & moulded eave gallery crown (y = 5.36 .. 5.66 m).
	s.surface(iron)
	s.colour = _lin(COPPER_BRONZE)
	Shapes.lathe(s, [
		Vector2(R_INNER + 0.15, 5.66), Vector2(R_INNER - 0.12, 5.66),
		Vector2(R_INNER - 0.24, 5.52), Vector2(R_INNER - 0.14, 5.36),
		Vector2(R_OUTER + 0.24, 5.36), Vector2(R_OUTER + 0.24, 5.62),
	], Vector3(CX, 0.0, CZ), 32)

	# Gleaming burnished-brass cornice astragal collar band & dentil bosses.
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.arch(u, Vector3(CX, 5.42, CZ), R_INNER - 0.25, R_INNER - 0.16, 0.06, 32,
			Basis(Vector3.RIGHT, -PI * 0.5), 0.0, TAU, ["front", "back", "inner"])

	# 2. Ribbed patinated dark-copper conical/ogee lantern dome shell (32-segment baked interior face, y = 5.64 .. 7.56 m,
	# aligned cleanly with the 32-segment bronze cornice, 16 brass ribs, and 32-segment golden dome uplight cove!).
	s.surface(iron)
	s.colour = _lin(COPPER_DARK)
	var dome_prof: Array = [
		Vector2(0.86, 7.56), Vector2(1.75, 7.22), Vector2(2.85, 6.80),
		Vector2(3.98, 6.32), Vector2(4.92, 5.90), Vector2(R_INNER - 0.08, 5.64),
	]
	Shapes.lathe(s, dome_prof, Vector3(CX, 0.0, CZ), 32)

	# 3. Sixteen converging raised copper-and-brass structural dome ribs meeting the central brass cupola ring!
	for i in BAYS:
		var paz := _post_az(i)
		var d := Vector3(sin(paz), 0.0, -cos(paz))
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		for k in dome_prof.size() - 1:
			var q0: Vector2 = dome_prof[k + 1]
			var q1: Vector2 = dome_prof[k]
			var p0 := Vector3(CX, q0.y - 0.03, CZ) + d * (q0.x - 0.04)
			var p1 := Vector3(CX, q1.y - 0.03, CZ) + d * (q1.x - 0.04)
			Shapes.beam(u, p0, p1, Vector2(0.055, 0.065))

	# 4. Central brass cupola throat ring, louvered brass ventilator ball & 8-strut Fresnel suspension spider!
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.arch(u, Vector3(CX, 7.52, CZ), 0.78, 0.94, 0.14, 24, Basis(Vector3.RIGHT, -PI * 0.5),
			0.0, TAU, ["front", "back", "inner", "outer"])
	# Louvered dark-copper dome apex cap + central gleaming brass ventilator sphere visible looking up!
	s.surface(iron)
	s.colour = _lin(COPPER_BRONZE * 0.75)
	Shapes.cylinder(s, Vector3(CX, 7.52, CZ), 0.84, 0.30, 16)
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.dome(u, Vector3(CX, 7.50, CZ), 0.42, 6, 16, false, -PI * 0.5, 0.0)
	# Heavy fixed brass central ceiling suspension column & 4 curved brace struts holding the rotating Fresnel rig!
	Shapes.cylinder(u, Vector3(CX, LENS_Y + 0.80, CZ), 0.11, 7.50 - (LENS_Y + 0.80), 12)
	Shapes.arch(u, Vector3(CX, LENS_Y + 0.86, CZ), 0.42, 0.58, 0.08, 20, Basis(Vector3.RIGHT, -PI * 0.5),
			0.0, TAU, ["front", "back", "inner", "outer"])
	for k in 4:
		var a := float(k) * PI * 0.5 + PI * 0.25
		var d := Vector3(sin(a), 0.0, cos(a))
		Shapes.beam(u, Vector3(CX, LENS_Y + 0.88, CZ) + d * 0.52,
				Vector3(CX, 7.46, CZ) + d * 0.84, Vector2(0.042, 0.042))
		# Slender tension rods anchoring upper turntable stability out to the bronze cornice ring (y = 5.48 m).
		Shapes.beam(u, Vector3(CX, LENS_Y + 0.88, CZ) + d * 0.55,
				Vector3(CX, 5.48, CZ) + d * (R_INNER - 0.22), Vector2(0.022, 0.022))

	# 5. Soft warm golden architectural uplight cove inset cleanly beneath the 32-segment ribbed copper dome (zero
	# facet intersection — every ring matches the exact 32-segment dome profile shifted 0.06 m inward & 0.04 m below!).
	c.cove.surface(cove_m)
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for d_def: Array in [[R_INNER - 0.16, 5.60, 0.46], [4.84, 5.85, 0.18], [3.90, 6.26, 0.00]]:
		var rr := float(d_def[0])
		var yy := float(d_def[1])
		var w := float(d_def[2])
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in 33:
			var az := TAU * float(k % 32) / 32.0
			row.append(_ring_pt(rr, az, yy))
			nrow.append(Vector3(-sin(az) * 0.42, -0.90, cos(az) * 0.42).normalized())
			crow.append(_lin(Color(0.95, 0.78, 0.52), w))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	c.cove.grid(rows, norms, cols)


## Exterior granite gallery corbels, riveted dark-iron exterior catwalk deck ring (r = 5.75 .. 6.95 m), and authentic
## sea-spray iron balustrade visible directly outside the panoramic storm windows!
static func _exterior_catwalk_gallery(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var plaster: Material = c.tinted("plaster", "lime_wash")
	var iron: Material = c.tinted("iron")
	var iron_u: Material = c.soft("iron", true)
	var brass: Material = _brass(c)

	# Exterior riveted iron catwalk floor ring (y = -0.06 m) & thick underside edge fascia.
	s.surface(iron)
	s.colour = _lin(IRON_DARK)
	_annulus(s, R_OUTER - 0.05, R_GALLERY, -0.05, 32)
	Shapes.lathe(s, [Vector2(R_GALLERY, -0.26), Vector2(R_GALLERY, -0.04)], Vector3(CX, 0.0, CZ), 32)

	# Sixteen sculpted whitewashed granite corbel brackets flaring under the catwalk gallery.
	s.surface(plaster)
	s.colour = _lin(WHITEWASH_SHADE)
	for i in BAYS:
		var az := _post_az(i)
		var bb := _bay_basis(az)
		var p_corb := _ring_pt(R_OUTER + 0.48, az, -0.62)
		s.box(p_corb, Vector3(0.32, 0.92, 1.04), bb * Basis(Vector3.RIGHT, deg_to_rad(-28.0)))

	# 32-post maritime iron exterior catwalk balustrade (r = 6.84 m, y = -0.05 .. 1.24 m) + triple horizontal storm
	# rails + gleaming spherical brass rail finials clearly visible right outside the panoramic storm glazing!
	var r_rail := R_GALLERY - 0.10
	var posts := 32
	for k in posts:
		var a0 := TAU * float(k) / float(posts)
		var a1 := TAU * float((k + 1) % posts) / float(posts)
		var p0 := _ring_pt(r_rail, a0, 0.0)
		var p1 := _ring_pt(r_rail, a1, 0.0)
		u.surface(iron_u)
		u.colour = _lin(Color(0.24, 0.28, 0.34))
		Shapes.cylinder(u, p0 + Vector3(0.0, -0.06, 0.0), 0.030 if k % 2 == 0 else 0.022, 1.30, 6)
		for ry: float in [0.38, 0.80, 1.22]:
			u.colour = _lin(Color(0.32, 0.36, 0.42) if ry > 1.10 else Color(0.20, 0.24, 0.30))
			Shapes.beam(u, p0 + Vector3(0.0, ry, 0.0), p1 + Vector3(0.0, ry, 0.0),
					Vector2(0.040 if ry > 1.10 else 0.024, 0.040 if ry > 1.10 else 0.024))
		if k % 2 == 0:
			u.surface(brass)
			u.colour = _lin(BRASS_BRIGHT)
			Shapes.dome(u, p0 + Vector3(0.0, 1.26, 0.0), 0.052, 4, 8, false, -PI * 0.5, PI * 0.5)


## Cinema screen suspended cleanly on twin heavy brushed-brass & dark-iron nautical stanchions inside the forward
## lantern arc (SCREEN_C = (0, 2.45, -4.55), size 4.10 x 2.31 m), leaving dramatic storm-glass views on both sides
## and all across the top arch above the screen!
static func _screen_mount(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var iron: Material = c.tinted("iron")
	var brass: Material = _brass(c)
	var cove_m: Material = c.kit.cove_material()

	var hw := SCREEN_W * 0.5
	var hh := SCREEN_H * 0.5
	var z_back := SCREEN_C.z - 0.075 # cleanly behind z = -4.55 (0 sight-line overlap!)
	var y_bot := SCREEN_C.y - hh
	var y_top := SCREEN_C.y + hh

	# 1. Opaque dark charcoal-iron acoustic screen backing slab & crisp perimeter frame (sits behind screen plane).
	s.surface(iron)
	s.colour = _lin(IRON_DARK * 0.85)
	s.box(Vector3(0.0, SCREEN_C.y, z_back), Vector3(SCREEN_W + 0.16, SCREEN_H + 0.16, 0.09))

	# Burnished-brass inner fillet lip & outer riveted nautical picture frame with corner gusset plates!
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	u.box(Vector3(0.0, y_top + 0.055, z_back + 0.02), Vector3(SCREEN_W + 0.24, 0.09, 0.11))
	u.box(Vector3(0.0, y_bot - 0.055, z_back + 0.02), Vector3(SCREEN_W + 0.24, 0.09, 0.11))
	for sx: float in [-1.0, 1.0]:
		u.box(Vector3(sx * (hw + 0.055), SCREEN_C.y, z_back + 0.02), Vector3(0.09, SCREEN_H + 0.04, 0.11))
		# Brass corner gusset brackets + raised rivets.
		u.colour = _lin(BRASS_BRIGHT)
		for sy: float in [-1.0, 1.0]:
			u.box(Vector3(sx * (hw + 0.07), SCREEN_C.y + sy * (hh + 0.07), z_back + 0.055),
					Vector3(0.14, 0.14, 0.036))

	# 2. Twin heavy brushed-brass & dark-iron nautical deck stanchions (x = +/-2.16, z = -4.62), bolted to the oak deck
	# with octagonal cast-iron flanges & twin slender brass suspension tie-rods rising cleanly to the bronze cornice!
	for sx: float in [-1.0, 1.0]:
		var px := sx * (hw + 0.11)
		var pz := z_back
		s.surface(iron)
		s.colour = _lin(IRON_NAVY)
		# Heavy flanged deck base plinth & lower cast-iron pedestal shaft (y = 0.0 .. 1.32 m).
		Shapes.lathe(s, [
			Vector2(0.18, 0.0), Vector2(0.18, 0.07), Vector2(0.12, 0.14),
			Vector2(0.085, 0.22), Vector2(0.075, 1.32),
		], Vector3(px, 0.0, pz), 12)
		# Gleaming brushed-brass upper vertical stanchion tube framing the screen edges (y = 1.24 .. 3.82 m).
		u.surface(brass)
		u.colour = _lin(BRASS_BRIGHT)
		Shapes.cylinder(u, Vector3(px, 1.24, pz), 0.052, y_top + 0.22 - 1.24, 12)
		# Turned brass collar rings & spherical finial caps.
		for cy: float in [0.16, 1.26, y_bot, y_top, y_top + 0.22]:
			Shapes.lathe(u, [Vector2(0.054, 0.0), Vector2(0.078, 0.025), Vector2(0.078, 0.055), Vector2(0.054, 0.08)],
					Vector3(px, cy - 0.04, pz), 12)
		Shapes.dome(u, Vector3(px, y_top + 0.25, pz), 0.068, 5, 12, false, -PI * 0.5, PI * 0.5)
		# Slender angled brass tension suspension rod anchoring stanchion top up to the bronze cornice ring!
		u.colour = _lin(BRASS_WARM)
		Shapes.beam(u, Vector3(px, y_top + 0.22, pz), Vector3(px * 1.05, CAGE_TOP - 0.02, -4.96), Vector2(0.026, 0.026))
		# Low aft diagonal deck brace struts anchoring each stanchion to the forward parapet base.
		Shapes.beam(u, Vector3(px, 0.72, pz), Vector3(px * 1.04, 0.14, -4.96), Vector2(0.036, 0.036))

	# Subtle brass crossbar rail below the screen & warm indirect downward deck cove wash.
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.beam(u, Vector3(-hw - 0.11, 0.42, z_back), Vector3(hw + 0.11, 0.42, z_back), Vector2(0.034, 0.034))
	c.cove.surface(cove_m)
	c.cove.colour = _lin(Color(0.95, 0.76, 0.46), 0.65)
	Shapes.quad(c.cove, Vector3(0.0, y_bot - 0.105, z_back + 0.02),
			Vector3(hw, 0.0, 0.0), Vector3(0.0, 0.0, 0.03), Vector3.DOWN)

	_solid(c, Vector3(0.0, SCREEN_C.y, z_back), Vector3(SCREEN_W + 0.34, SCREEN_H + 0.24, 0.22))


## Aft circular floor hatch (0, 0, +3.75) with sculpted cast-iron spiral staircase descending into the warm-lit tower
## shaft below, gleaming curved brass handrail loop, and aft mahogany-mounted working brass ship's chronometer clock!
static func _aft_spiral_stair_and_chronometer(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var plaster: Material = c.tinted("plaster", "lime_wash")
	var iron: Material = c.tinted("iron")
	var iron_u: Material = c.soft("iron", true)
	var wood: Material = c.tinted("wood")
	var brass: Material = _brass(c)

	# 1. Whitewashed stone cylindrical stairwell shaft descending below the hatch (y = -3.80 .. 0.0 m).
	s.surface(plaster)
	s.colour = _lin(WHITEWASH_SHADE * 0.72)
	Shapes.lathe(s, [Vector2(HATCH_R + 0.02, 0.0), Vector2(HATCH_R + 0.02, -HATCH_DEPTH)], HATCH_C, 20)
	s.surface(iron)
	s.colour = _lin(IRON_DARK * 0.7)
	var floor_bot: Array = []
	for k in 16:
		var a := TAU * float(k) / 16.0
		floor_bot.append(HATCH_C + Vector3(sin(a) * (HATCH_R + 0.04), -HATCH_DEPTH, cos(a) * (HATCH_R + 0.04)))
	s.face(floor_bot, Vector3.UP)
	# Warm lantern glow disc far down the spiral stairwell (PieceLamps, gives cozy depth when peering down!).
	c.lit.surface(c.shade(LAMP_AMBER))
	Shapes.quad(c.lit, HATCH_C + Vector3(0.0, -HATCH_DEPTH + 0.08, 0.0),
			Vector3(0.36, 0.0, 0.0), Vector3(0.0, 0.0, 0.36), Vector3.UP)

	# 2. Riveted dark-iron hatch coaming ring around the circular floor opening.
	u.surface(iron_u)
	u.colour = _lin(IRON_DARK)
	Shapes.arch(u, HATCH_C + Vector3(0.0, 0.032, 0.0), HATCH_R - 0.01, HATCH_R + 0.13, 0.064, 24,
			Basis(Vector3.RIGHT, -PI * 0.5), 0.0, TAU, ["front", "back", "inner", "outer"])

	# 3. Central sculpted cast-iron spiral newel column with turned brass finial ball + 14 cast-iron spiral treads!
	u.surface(iron_u)
	u.colour = _lin(IRON_NAVY)
	Shapes.cylinder(u, HATCH_C + Vector3(0.0, -HATCH_DEPTH, 0.0), 0.082, HATCH_DEPTH + 0.98, 12)
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.lathe(u, [Vector2(0.086, 0.96), Vector2(0.11, 1.00), Vector2(0.06, 1.05),
			Vector2(0.095, 1.13), Vector2(0.0, 1.22)], HATCH_C, 12)

	var treads := 14
	var prev_rail := Vector3.ZERO
	for k in treads:
		var ang := deg_to_rad(-42.0 + float(k) * 26.0) # spirals cleanly downward clockwise from entry!
		var ty := -0.18 - float(k) * 0.23
		var d := Vector3(sin(ang), 0.0, cos(ang))
		var tang := Vector3(cos(ang), 0.0, -sin(ang))
		var tb := Basis(tang, Vector3.UP, d)
		u.surface(iron_u)
		u.colour = _lin(IRON_DARK if k % 2 == 0 else IRON_NAVY)
		u.box(HATCH_C + d * 0.49 + Vector3(0.0, ty, 0.0), Vector3(0.32, 0.036, 0.80), tb)
		# Gleaming brass anti-slip stair nosing strip on each step!
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		u.box(HATCH_C + d * 0.50 + tang * -0.145 + Vector3(0.0, ty + 0.022, 0.0), Vector3(0.026, 0.012, 0.78), tb)
		# Outer iron spindle & spiralling brass handrail descending down the stairwell.
		var rail_pt := HATCH_C + d * 0.84 + Vector3(0.0, ty + 0.90, 0.0)
		u.surface(iron_u)
		u.colour = _lin(IRON_DARK)
		Shapes.cylinder(u, HATCH_C + d * 0.84 + Vector3(0.0, ty, 0.0), 0.014, 0.90, 6)
		if k > 0:
			u.surface(brass)
			u.colour = _lin(BRASS_BRIGHT)
			Shapes.beam(u, prev_rail, rail_pt, Vector2(0.032, 0.032))
		prev_rail = rail_pt

	# 4. Gleaming curved brass watchroom hatch safety handrail loop (260-degree arc around the circular opening,
	# leaving a clear stair entry gap facing forward-port!).
	var r_hand := HATCH_R + 0.08
	var h_segs := 14
	var a_start := deg_to_rad(30.0)
	var a_end := deg_to_rad(298.0)
	for k in h_segs + 1:
		var a := lerpf(a_start, a_end, float(k) / float(h_segs))
		var p_post := HATCH_C + Vector3(sin(a) * r_hand, 0.05, cos(a) * r_hand)
		if k % 2 == 0 or k == h_segs:
			u.surface(iron_u)
			u.colour = _lin(IRON_NAVY)
			Shapes.cylinder(u, p_post, 0.024 if (k == 0 or k == h_segs) else 0.017, 0.92, 8)
			if k == 0 or k == h_segs:
				u.surface(brass)
				u.colour = _lin(BRASS_BRIGHT)
				Shapes.dome(u, p_post + Vector3(0.0, 0.95, 0.0), 0.044, 4, 8, false, -PI * 0.5, PI * 0.5)
		if k < h_segs:
			var a_next := lerpf(a_start, a_end, float(k + 1) / float(h_segs))
			var p_next := HATCH_C + Vector3(sin(a_next) * r_hand, 0.05, cos(a_next) * r_hand)
			u.surface(brass)
			u.colour = _lin(BRASS_BRIGHT)
			Shapes.beam(u, p_post + Vector3(0.0, 0.92, 0.0), p_next + Vector3(0.0, 0.92, 0.0), Vector2(0.036, 0.036))
			u.colour = _lin(BRASS_WARM)
			Shapes.beam(u, p_post + Vector3(0.0, 0.48, 0.0), p_next + Vector3(0.0, 0.48, 0.0), Vector2(0.020, 0.020))

	_solid(c, HATCH_C + Vector3(0.0, 0.50, 0.0), Vector3(2.10, 1.00, 2.10))

	# 5. Aft Mahogany Instrument Pillar & Wall-Mounted Brass Ship's Chronometer Clock (`PieceClock`) at (0, 1.92, +5.22)!
	var bz := CZ + R_INNER - 0.24 # +5.41 m
	var b_aft := Basis(Vector3.UP, PI) # local +Z faces -Z (into the watchroom), local +X faces -X
	s.surface(wood)
	s.colour = _lin(MAHOGANY)
	# Carved mahogany instrument pier rising from aft parapet to y = 2.46 m (leaving y = 2.46..5.40 glazing wide open!).
	s.box(Vector3(0.0, 1.24, bz), Vector3(0.92, 2.48, 0.24), Basis(), [RoomMesh.DOWN])
	s.colour = _lin(OAK_DARK)
	s.box(Vector3(0.0, 2.49, bz - 0.02), Vector3(1.04, 0.08, 0.30))
	s.box(Vector3(0.0, 1.22, bz - 0.04), Vector3(0.98, 0.06, 0.26))
	# Gleaming burnished-brass ship's chronometer bezel, hinge clasp, top ship's bell & 12 brass hour lugs!
	var clk_c := Vector3(0.0, 1.88, bz - 0.14)
	var clk_r := 0.28
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.arch(u, clk_c, clk_r, clk_r + 0.062, 0.085, 28, b_aft, 0.0, TAU, ["front", "back", "inner", "outer"])
	Shapes.arch(u, clk_c + Vector3(0.0, 0.0, -0.025), clk_r - 0.008, clk_r + 0.018, 0.036, 24, b_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Brass hinge barrel on left & knurled bezel latch screw on right.
	Shapes.cylinder(u, clk_c + Vector3(-clk_r - 0.06, -0.04, -0.02), 0.022, 0.08, 8)
	Shapes.cylinder(u, clk_c + Vector3(clk_r + 0.055, 0.0, -0.02), 0.022, 0.05, 8, Basis(Vector3.BACK, PI * 0.5))
	# Brass ship's watch bell mounted cleanly atop the mahogany chronometer cornice!
	Shapes.lathe(u, [
		Vector2(0.11, 0.0), Vector2(0.095, 0.03), Vector2(0.068, 0.09),
		Vector2(0.052, 0.14), Vector2(0.018, 0.17), Vector2(0.0, 0.18),
	], Vector3(0.0, 2.53, bz - 0.02), 14)
	# Register live working `PieceClock` dial facing -Z into the watchroom.
	c.clocks.append([clk_c + Vector3(0.0, 0.0, -0.046), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])
	_solid(c, Vector3(0.0, 1.25, bz), Vector3(1.06, 2.52, 0.34))


## Heavy oak watchkeeper's chart desk along the port parapet with unrolled nautical sea chart, brass sextant, parallel
## ruler, logbook, gleaming brass speaking tube, and a port-forward brass telescope on a mahogany tripod aimed seaward!
static func _port_chart_desk_and_telescope(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood: Material = c.tinted("wood")
	var brass: Material = _brass(c)
	var paper: Material = c.soft("plastic", true)

	# --- 1. Port Heavy Oak Watchkeeper's Chart Desk (x = -4.52, z = -0.15, facing inward +X) ---
	var dp := Vector3(-4.52, 0.0, -0.15)
	var db := Basis(Vector3.UP, PI * 0.5) # local +Z faces +X (into room), local +X faces -Z
	var xf := Transform3D(db, dp)
	var dw := 1.72
	var dh := 0.84
	var dd := 0.78

	s.surface(wood)
	s.colour = _lin(OAK_DECK * 0.92)
	s.box(xf * Vector3(0.0, dh - 0.03, 0.0), Vector3(dw, 0.06, dd), db)
	s.colour = _lin(OAK_DARK)
	# Twin solid oak chart-drawer pedestals flanking a central kneehole.
	for sx: float in [-0.58, 0.58]:
		s.box(xf * Vector3(sx, (dh - 0.06) * 0.5, -0.02), Vector3(0.46, dh - 0.06, dd - 0.08), db, [RoomMesh.DOWN])
	# Recessed oak modesty back panel & brass cup drawer pulls + desktop fiddle rail!
	s.box(xf * Vector3(0.0, 0.52, -dd * 0.5 + 0.06), Vector3(0.76, 0.52, 0.04), db)
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	for sx: float in [-0.58, 0.58]:
		for dy: float in [0.22, 0.44, 0.66]:
			u.box(xf * Vector3(sx, dy, dd * 0.5 - 0.03), Vector3(0.11, 0.026, 0.026), db)
	# Brass chart-desk fiddle rail keeping instruments from sliding in an Atlantic gale.
	u.box(xf * Vector3(0.0, dh + 0.028, -dd * 0.5 + 0.025), Vector3(dw - 0.04, 0.036, 0.018), db)
	for sx: float in [-1.0, 1.0]:
		u.box(xf * Vector3(sx * (dw * 0.5 - 0.025), dh + 0.028, 0.0), Vector3(0.018, 0.036, dd - 0.04), db)

	# Unrolled ivory-parchment nautical sea chart with scrolled mahogany rollers, headland ink lines & compass lines!
	u.surface(paper)
	u.colour = _lin(PARCHMENT)
	u.box(xf * Vector3(-0.10, dh + 0.008, 0.02), Vector3(0.96, 0.008, 0.56), db * Basis(Vector3.UP, 0.04))
	# Inked coastline & rhumb-line courses across the chart.
	u.colour = _lin(CHART_INK)
	u.box(xf * Vector3(-0.22, dh + 0.014, -0.06), Vector3(0.32, 0.004, 0.16), db * Basis(Vector3.UP, 0.28))
	u.box(xf * Vector3(0.05, dh + 0.014, 0.06), Vector3(0.68, 0.003, 0.010), db * Basis(Vector3.UP, -0.22))
	u.box(xf * Vector3(-0.02, dh + 0.014, -0.02), Vector3(0.56, 0.003, 0.010), db * Basis(Vector3.UP, 0.42))
	# Turned mahogany chart scroll cylinders pinning both edges of the unrolled map.
	u.surface(c.soft("wood", true))
	u.colour = _lin(MAHOGANY)
	for sx: float in [-0.58, 0.38]:
		Shapes.cylinder(u, xf * Vector3(sx, dh + 0.024, -0.26), 0.022, 0.56, 8, db * Basis(Vector3.RIGHT, PI * 0.5))

	# Sculpted Brass Sextant resting neatly on the right side of the chart desk!
	var sx_c := xf * Vector3(0.54, dh + 0.018, 0.08)
	var sx_b := db * Basis(Vector3.UP, -0.45) * Basis(Vector3.RIGHT, -PI * 0.5)
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.arch(u, sx_c, 0.145, 0.175, 0.018, 12, sx_b, -0.55, 0.55, ["front", "back", "inner", "outer"])
	for rad_a: float in [-0.52, 0.0, 0.52]:
		var tip := sx_c + sx_b * Vector3(cos(rad_a) * 0.16, sin(rad_a) * 0.16, 0.0)
		Shapes.beam(u, sx_c, tip, Vector2(0.014, 0.016))
	# Sextant brass sighting tube & index mirror block.
	Shapes.cylinder(u, sx_c + db * Vector3(0.02, 0.03, -0.05), 0.014, 0.14, 8, db * Basis(Vector3.RIGHT, PI * 0.5))
	# Brass parallel ruler lying diagonally across the sea chart.
	u.box(xf * Vector3(-0.18, dh + 0.016, 0.15), Vector3(0.36, 0.008, 0.036), db * Basis(Vector3.UP, -0.22))
	u.box(xf * Vector3(-0.15, dh + 0.016, 0.21), Vector3(0.36, 0.008, 0.036), db * Basis(Vector3.UP, -0.22))

	# Leatherbound Watchroom Logbook on the left desk wing.
	u.surface(paper)
	u.colour = _lin(CRIMSON_PANEL * 1.15)
	u.box(xf * Vector3(-0.68, dh + 0.022, 0.08), Vector3(0.24, 0.038, 0.32), db * Basis(Vector3.UP, 0.14))
	u.colour = _lin(PARCHMENT)
	u.box(xf * Vector3(-0.67, dh + 0.022, 0.08), Vector3(0.22, 0.030, 0.30), db * Basis(Vector3.UP, 0.14))

	_solid(c, xf * Vector3(0.0, dh * 0.5, 0.0), Vector3(dw, dh, dd), db)

	# --- 2. Gleaming Brass Speaking Tube rising beside the aft end of the chart desk (x = -4.60, z = +1.02) ---
	var sp_base := Vector3(-4.60, 0.0, 1.02)
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.lathe(u, [Vector2(0.085, 0.0), Vector2(0.085, 0.03), Vector2(0.042, 0.06), Vector2(0.030, 0.12)], sp_base, 12)
	Shapes.cylinder(u, sp_base + Vector3(0.0, 0.06, 0.0), 0.026, 1.24, 10)
	# Twin brass parapet tie-clamps bracing the speaking tube cleanly into the port parapet drum!
	var sp_wall := Vector3(CX, 0.0, CZ) + Vector3(sp_base.x - CX, 0.0, sp_base.z - CZ).normalized() * (R_INNER - 0.07)
	u.colour = _lin(BRASS_WARM)
	for by: float in [0.52, 0.96]:
		Shapes.beam(u, sp_base + Vector3(0.0, by, 0.0), sp_wall + Vector3(0.0, by, 0.0), Vector2(0.028, 0.028))
		Shapes.cylinder(u, sp_base + Vector3(0.0, by - 0.025, 0.0), 0.036, 0.05, 10)
	# Curved gooseneck elbow & flared brass mouthpiece horn aimed inward toward the watchkeeper.
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.beam(u, sp_base + Vector3(0.0, 1.30, 0.0), sp_base + Vector3(0.14, 1.38, -0.04), Vector2(0.046, 0.046))
	var horn_b := Basis(Vector3.UP, -0.28) * Basis(Vector3.BACK, -PI * 0.38)
	Shapes.lathe(u, [Vector2(0.026, 0.0), Vector2(0.032, 0.05), Vector2(0.062, 0.11), Vector2(0.072, 0.13)],
			sp_base + Vector3(0.14, 1.38, -0.04), 12, horn_b)
	_solid(c, sp_base + Vector3(0.05, 0.72, 0.0), Vector3(0.28, 1.44, 0.24))

	# --- 3. Brass Telescope on Mahogany Tripod (Port-Forward Viewing Bay, (-3.60, 0.0, -2.55)) ---
	# Aimed seaward (-X / -Z) out through the storm glass toward the distant flashing harbour buoy; 2.6 m clear of all sight lines!
	var tp := Vector3(-3.60, 0.0, -2.55)
	var head := tp + Vector3(0.0, 1.34, 0.0)
	# Three splayed tapered mahogany tripod legs with gleaming brass ferrules & central brass spreader collar.
	for k in 3:
		var a := float(k) * TAU / 3.0 + 0.35
		var foot := tp + Vector3(sin(a) * 0.48, 0.0, cos(a) * 0.48)
		u.surface(c.soft("wood", true))
		u.colour = _lin(MAHOGANY)
		Shapes.beam(u, foot + Vector3(0.0, 0.06, 0.0), head, Vector2(0.036, 0.036))
		u.surface(brass)
		u.colour = _lin(BRASS_BRIGHT)
		Shapes.cylinder(u, foot, 0.024, 0.08, 8)
		Shapes.beam(u, tp + Vector3(0.0, 0.56, 0.0), foot.lerp(head, 0.42), Vector2(0.018, 0.018))
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.cylinder(u, head - Vector3(0.0, 0.06, 0.0), 0.062, 0.14, 12)
	# Azimuth yoke & long stepped gleaming brass refractor telescope tube aimed seaward toward BUOY_BASE!
	var aim := (BUOY_BASE + Vector3(0.0, 8.0, 0.0) - head).normalized()
	var aim_r := Vector3.UP.cross(aim).normalized()
	var aim_u := aim.cross(aim_r).normalized()
	var scope_b := Basis(aim_r, aim, aim_u) # local +Y runs along aim!
	Shapes.lathe(u, [
		Vector2(0.020, -0.46), Vector2(0.024, -0.34), Vector2(0.034, -0.32),
		Vector2(0.044, 0.12), Vector2(0.056, 0.58), Vector2(0.066, 0.62),
		Vector2(0.066, 0.78), Vector2(0.058, 0.78),
	], head + Vector3(0.0, 0.14, 0.0), 14, scope_b)
	# Parallel slender brass finder scope perched atop the main barrel.
	Shapes.cylinder(u, head + Vector3(0.0, 0.14, 0.0) + aim_u * 0.088 - aim * 0.12, 0.015, 0.36, 8, scope_b)
	_solid(c, tp + Vector3(0.0, 0.80, 0.0), Vector3(0.95, 1.60, 0.95))


## Starboard oak maritime signal locker, mahogany-mounted Fortin mercury & aneroid ship's barometer (`PieceGlass` +
## `PieceWindows`), and heavy stacked coil of braided hemp hawser rope on deck!
static func _starboard_locker_barometer_and_rope(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var wood: Material = c.tinted("wood")
	var brass: Material = _brass(c)
	var paper: Material = c.soft("plastic", true)
	var gw: Array = c.glows.get("window", [])

	# --- 1. Starboard Oak Signal Locker & Sea Chest (x = +4.55, z = +0.25, facing inward -X) ---
	var lp := Vector3(4.55, 0.0, 0.25)
	var lb := Basis(Vector3.UP, -PI * 0.5) # local +Z faces -X (inward)
	var xf := Transform3D(lb, lp)
	s.surface(wood)
	s.colour = _lin(OAK_DARK)
	s.box(xf * Vector3(0.0, 0.42, 0.0), Vector3(1.48, 0.84, 0.58), lb, [RoomMesh.DOWN])
	s.colour = _lin(OAK_DECK)
	s.box(xf * Vector3(0.0, 0.855, 0.0), Vector3(1.56, 0.05, 0.64), lb)
	# Brass corner protection straps, recessed chest handles & twin brass marine belaying pins.
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	for sx: float in [-0.74, 0.74]:
		u.box(xf * Vector3(sx, 0.42, 0.295), Vector3(0.06, 0.84, 0.02), lb)
		u.box(xf * Vector3(sx * 0.52, 0.58, 0.305), Vector3(0.14, 0.032, 0.024), lb)
		u.box(xf * Vector3(sx * 0.52, 0.28, 0.305), Vector3(0.14, 0.032, 0.024), lb)
	# Resting atop the locker: folded navy wool storm blanket & gleaming brass fog-bell hand lamp.
	u.surface(paper)
	u.colour = _lin(IRON_NAVY * 1.45)
	u.box(xf * Vector3(-0.36, 0.94, 0.0), Vector3(0.46, 0.12, 0.38), lb * Basis(Vector3.UP, 0.08))
	_solid(c, xf * Vector3(0.0, 0.44, 0.0), Vector3(1.56, 0.88, 0.64), lb)

	# --- 2. Ship's Barometer Station (Mahogany Stanchion Plaque anchored solidly onto starboard glazing post #3 & oak sill!) ---
	var b_az := _post_az(3)
	var bp := _ring_pt(R_MULLION - 0.10, b_az, 0.0)
	var bb := _bay_basis(b_az)
	var bxf := Transform3D(bb, bp)
	var sill_y := PARAPET_H + 0.03
	s.surface(wood)
	s.colour = _lin(MAHOGANY)
	# Solid mahogany instrument backboard resting squarely on the oak parapet sill coping (y = 1.05 .. 2.09 m) and
	# clamped flush to the vertical iron glazing standard behind it!
	s.box(bxf * Vector3(0.0, sill_y + 0.52, 0.0), Vector3(0.50, 1.04, 0.085), bb)
	s.colour = _lin(OAK_DARK)
	s.box(bxf * Vector3(0.0, sill_y + 0.035, 0.015), Vector3(0.56, 0.07, 0.14), bb)
	s.box(bxf * Vector3(0.0, sill_y + 1.055, 0.010), Vector3(0.56, 0.05, 0.12), bb)
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	# Twin brass post-clamp brackets bolting the mahogany plaque cleanly around the iron glazing standard behind it.
	for cy: float in [sill_y + 0.24, sill_y + 0.86]:
		u.box(bxf * Vector3(0.0, cy, -0.08), Vector3(0.13, 0.055, 0.14), bb)
	u.colour = _lin(BRASS_BRIGHT)
	# Circular brass aneroid storm-barometer dial (`PieceWindows` backlit warm amber dial + crimson needle!).
	var dial_c := bxf * Vector3(0.09, sill_y + 0.62, 0.052)
	Shapes.arch(u, dial_c, 0.11, 0.14, 0.042, 20, bb, 0.0, TAU, ["front", "inner", "outer"])
	gw.append([dial_c + bb.z * 0.010, bb.x * 0.105, Vector3.UP * 0.105, bb.z])
	u.surface(paper)
	u.colour = _lin(CRIMSON_BAND)
	u.box(dial_c + bb.z * 0.022, Vector3(0.012, 0.15, 0.008), bb * Basis(Vector3.BACK, -0.58))
	# Vertical Fortin mercury marine barometer beside the dial (`PieceGlass` tube + gleaming silver mercury column).
	var merc_p := bxf * Vector3(-0.14, sill_y + 0.14, 0.062)
	u.surface(brass)
	u.colour = _lin(BRASS_BRIGHT)
	Shapes.cylinder(u, merc_p, 0.036, 0.08, 10)
	Shapes.cylinder(u, merc_p + Vector3(0.0, 0.72, 0.0), 0.032, 0.07, 10)
	Shapes.cylinder(glass, merc_p + Vector3(0.0, 0.08, 0.0), 0.022, 0.64, 8, Basis(), false)
	u.surface(paper)
	u.colour = _lin(Color(0.84, 0.88, 0.92))
	Shapes.cylinder(u, merc_p + Vector3(0.0, 0.08, 0.0), 0.009, 0.46, 8)
	c.glows["window"] = gw

	# --- 3. Coiled Hemp Hawser Rope stacked naturally on the starboard-aft oak deck (+3.85, 0.0, +2.35) ---
	var rp := Vector3(3.85, 0.0, 2.35)
	u.surface(paper)
	var flat_b := Basis(Vector3.RIGHT, -PI * 0.5)
	for tier in 4:
		var ty := 0.038 + float(tier) * 0.068
		var r_in := 0.21 + float(tier) * 0.025
		var r_out := 0.44 - float(tier) * 0.022
		u.colour = _lin(HEMP_ROPE * (0.86 + 0.08 * float(tier % 2)))
		Shapes.arch(u, rp + Vector3(0.0, ty, 0.0), r_in, r_out, 0.066, 20, flat_b, 0.0, TAU,
				["front", "back", "inner", "outer"])
	# Loose hemp hawser tail curving onto the deck planks.
	u.colour = _lin(HEMP_ROPE * 0.94)
	Shapes.beam(u, rp + Vector3(-0.32, 0.04, 0.16), rp + Vector3(-0.78, 0.03, 0.34), Vector2(0.064, 0.056))
	_solid(c, rp + Vector3(0.0, 0.16, 0.0), Vector3(0.92, 0.32, 0.92))


## Four glowing brass oil storm lanterns on gimbals (1 on chart desk, 1 on signal locker, 2 on aft chronometer flank
## brackets) with protective brass cages & warm glowing amber glass chimneys (`PieceLamps`), plus 8 warm stand-in/bake
## lamps (0 live lights!).
static func _gimbal_storm_lanterns_and_bake_lights(c: Object) -> void:
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var brass: Material = _brass(c)
	var glow_m: Material = c.shade(LAMP_AMBER)

	# Four gimbal brass oil storm lantern positions: [centre_base, has_wall_bracket, bracket_dir_to_wall].
	var lanterns: Array = [
		[Vector3(-4.48, 0.84, -0.78), false, Vector3.ZERO],    # Port chart desk oil storm lantern
		[Vector3(4.52, 0.88, 0.78), false, Vector3.ZERO],      # Starboard signal locker oil storm lantern
		[Vector3(-0.62, 1.72, 5.18), true, Vector3.BACK],      # Aft port chronometer gimbal sconce lantern
		[Vector3(0.62, 1.72, 5.18), true, Vector3.BACK],       # Aft starboard chronometer gimbal sconce lantern
	]
	for ld: Array in lanterns:
		var base: Vector3 = ld[0]
		var has_br: bool = ld[1]
		var br_dir: Vector3 = ld[2]
		u.surface(brass)
		u.colour = _lin(BRASS_BRIGHT)
		# Brass oil reservoir font & gimbal pivot ring.
		Shapes.lathe(u, [
			Vector2(0.095, 0.0), Vector2(0.105, 0.04), Vector2(0.088, 0.09), Vector2(0.068, 0.12),
		], base, 12)
		# Gimbal ring encircling the oil lamp reservoir.
		Shapes.arch(u, base + Vector3(0.0, 0.075, 0.0), 0.106, 0.122, 0.022, 16,
				Basis(Vector3.RIGHT, -PI * 0.5), 0.0, TAU, ["front", "back", "inner", "outer"])
		# Brass hood cap & ventilator chimney top.
		Shapes.lathe(u, [
			Vector2(0.075, 0.30), Vector2(0.11, 0.33), Vector2(0.055, 0.39), Vector2(0.04, 0.43), Vector2(0.0, 0.44),
		], base, 12)
		# Four slim brass storm-cage guard rods around the glowing glass chimney.
		for k in 4:
			var a := float(k) * PI * 0.5 + PI * 0.25
			Shapes.cylinder(u, base + Vector3(sin(a) * 0.082, 0.10, cos(a) * 0.082), 0.008, 0.22, 6)
		if has_br:
			Shapes.beam(u, base + Vector3(0.0, 0.075, 0.0) + br_dir * 0.11,
					base + Vector3(0.0, 0.075, 0.0) + br_dir * 0.24, Vector2(0.024, 0.024))
		# Warm glowing amber oil-lamp glass chimney (`PieceLamps`, house group).
		lit.surface(glow_m)
		Shapes.lathe(lit, [
			Vector2(0.056, 0.11), Vector2(0.070, 0.18), Vector2(0.064, 0.26), Vector2(0.050, 0.31),
		], base, 12)
		c.lamps.append([base + Vector3(0.0, 0.22, 0.0), LAMP_AMBER, 0.78])

	# Four additional warm watchroom bake/stand-in lamps (overhead Fresnel glow, central deck warmth, screen & dome).
	c.lamps.append([Vector3(CX, LENS_Y, CZ), CRYSTAL_CORE, 1.10])
	c.lamps.append([Vector3(-2.6, 2.2, -2.4), LAMP_AMBER, 0.52])
	c.lamps.append([Vector3(2.6, 2.2, -2.4), LAMP_AMBER, 0.52])
	c.lamps.append([Vector3(0.0, 2.6, 3.2), LAMP_AMBER, 0.58])

	# Two hidden bake-only spots washing warm golden glow up into the ribbed dark-copper lantern dome.
	c.spots.append([Vector3(CX, 4.90, CZ), Vector3(CX, 7.55, CZ), LAMP_AMBER, 1.4, 7.5, 68.0])
	c.spots.append([Vector3(0.0, 1.25, -4.45), Vector3(0.0, 0.0, -3.50), LAMP_AMBER, 0.85, 5.5, 58.0])
