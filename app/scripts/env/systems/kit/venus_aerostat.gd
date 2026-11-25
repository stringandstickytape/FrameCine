extends RefCounted

## Venus aerostat kit (Other worlds; docs/environments/rooms/venus_aerostat.md): a gilded hammered-copper, brass and
## cream-enamel Art Nouveau cloud gondola suspended 52 km above Venus inside sunlit golden-amber cloud canyons beneath
## a glowing ivory-and-gold buoyant gas envelope. Built by Gemini 4 Neon Extra High. Everything is ours, drawn from
## boxes, polygons, strips, beams, arches and lathes; zero people, zero real marks, zero live lights.
##
##   venus_gondola  the pressurised octagonal Art Nouveau observation gondola (r ~ 6.5 m, height ~ 7.4 m):
##                  - inlaid herringbone parquet oak floor with dark walnut border inlay, gleaming central brass &
##                    walnut compass rose, and a deep sea-teal velvet salon rug under the 3x3 lounge seating island
##                  - patinated hammered-copper lower pressure dado with verdigris plinths, riveted burnished-brass
##                    pressure bands and sculpted walnut panoramic viewing sills wrapping port, starboard, diagonals
##                    and aft
##                  - 16 sweeping arched brass-and-copper panoramic observation bays with delicate Art Nouveau
##                    whiplash botanical filigree spandrels and crystal-clear single-surface glazing (`PieceGlass`)
##                  - wrought-brass mezzanine inspection catwalk balustrade supported on curved brass scroll brackets,
##                    surmounted by 8 curved riveted copper-and-brass dome ribs framing a 7.1 m skylight oculus
##                  - ornate Art Nouveau cream-enamel & brass screen proscenium on a two-step oak-and-brass dais with
##                    curved botanical filigree arches, sunburst crest, indirect cove troughs (`PieceCove`, live
##                    `cabin_coves`: Warm brass / Botanical emerald / Dim), and 8 warm frosted-opal tulip wall sconces
##                    plus 4 mezzanine tulip pendants (`PieceLamps`, `bake_lamps: 8`)
##                  - scientific cloud-city props around the perimeter (clear of sight lines and >= 0.5 m from origin):
##                    aft-starboard brass atmospheric barometer & spectrometer console with backlit amber dials
##                    (`PieceWindows`), forward-starboard brass altitude binnacle column, two hanging geodesic glass
##                    botanical terrariums packed with lush emerald ferns (`PieceGlass` + `PieceSoft`), two aft copper
##                    fern urns, riveted circular aft airlock hatch with spoked brass wheel, and working brass
##                    astronomical gondola clock (`PieceClock`) crowning the aft arch
##   venus_clouds   custom `c.halls` exterior world:
##                  - enveloping 360-degree opaque Venusian golden-amber cloud canyon sphere (`r = 160 m`, 1 draw,
##                    zero blend cost, `shaders/env_venus_clouds.gdshader`), live `cloud_light` moods (Amber noon /
##                    Copper sunset / Stormy gold), slow drifting cloud strata scaled by `Motion`, and very slow soft
##                    distant lower-deck sheet lightning (< 0.25 Hz, off when `lightning == "off"` or Flickering off)
##                  - vast glowing ivory-and-gold fluted buoyant aerostat gas envelope hovering 13-28 m overhead with
##                    gilded load bands, stabilizing tail fins, and 16 taut bronze rigging cables (`VenusEnvelope`)
##                  - 4 distant floating companion buoyant aerostats gliding peacefully across the cloud canyons at
##                    70-106 m distance (`VenusCompanions`, 1 draw)
##                  - 5 soft slanting golden Venusian cloud shafts (`VenusCloudShafts`, `env_world_shaft.gdshader`,
##                    group `env_see_through`, strictly outside the gondola)

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const CLOUDS_SHADER := preload("res://shaders/env_venus_clouds.gdshader")
const OUTSIDE_SHADER := preload("res://shaders/env_ice_outside.gdshader")
const SHAFT_SHADER := preload("res://shaders/env_world_shaft.gdshader")

const PIECES: Array[String] = ["venus_gondola", "venus_clouds"]

## Gondola octagonal plan vertices (clockwise from above so `along x UP` always points inward into the cabin).
## Front screen wall sits at z = -7.35 (edge 0, width 7.30 m); aft airlock wall at z = +6.35 (edge 4); port/starboard
## broadsides at x = +-6.45 (edges 2 and 6). All vertices stay inside domestic box x[-6.5, 6.5], z[-7.5, 6.5].
const OCT: Array[Vector2] = [
	Vector2(-3.65, -7.35), # 0: Front-Left
	Vector2(3.65, -7.35),  # 1: Front-Right
	Vector2(6.45, -4.25),  # 2: Starboard-Front
	Vector2(6.45, 3.25),   # 3: Starboard-Aft
	Vector2(3.65, 6.35),   # 4: Aft-Right
	Vector2(-3.65, 6.35),  # 5: Aft-Left
	Vector2(-6.45, 3.25),  # 6: Port-Aft
	Vector2(-6.45, -4.25), # 7: Port-Front
]

const CENTER_Z := -0.50
const DADO_H := 1.05
const WALL_TOP := 4.88
const MEZZ_Y := 4.65
const MEZZ_INSET := 0.78
const OCULUS_Y := 7.38
const OCULUS_R := 3.55
const CLOUD_RADIUS := 160.0
const MOTION_FLOOR := 0.25

## Palette (sRGB): hammered copper, burnished brass, Art Nouveau cream enamel, oak parquet, sea-teal velvet, ferns.
const OAK_WARM := Color(0.66, 0.47, 0.27)
const OAK_PALE := Color(0.79, 0.61, 0.38)
const WALNUT_RICH := Color(0.32, 0.19, 0.11)
const WALNUT_DARK := Color(0.19, 0.11, 0.06)
const ENAMEL_CREAM := Color(0.95, 0.90, 0.79)
const ENAMEL_WARM := Color(0.87, 0.80, 0.67)
const PARCHMENT := Color(0.93, 0.87, 0.72)
const COPPER_HAMMERED := Color(0.70, 0.36, 0.20)
const COPPER_DEEP := Color(0.45, 0.22, 0.13)
const COPPER_BRIGHT := Color(0.86, 0.49, 0.28)
const VERDIGRIS_DARK := Color(0.18, 0.34, 0.30)
const BRASS_BRIGHT := Color(0.95, 0.77, 0.38)
const BRASS_WARM := Color(0.82, 0.62, 0.27)
const BRASS_BRONZE := Color(0.56, 0.40, 0.18)
const TEAL_VELVET := Color(0.08, 0.28, 0.30)
const TEAL_DEEP := Color(0.04, 0.15, 0.18)
const SOIL_DARK := Color(0.16, 0.11, 0.08)
const FERN_DEEP := Color(0.09, 0.35, 0.15)
const FERN_EMERALD := Color(0.16, 0.51, 0.22)
const FERN_BRIGHT := Color(0.30, 0.66, 0.27)
const RUBY_DIAL := Color(0.78, 0.18, 0.14)
const LAMP_OPAL := Color(1.0, 0.87, 0.62)
const LAMP_GOLD := Color(1.0, 0.76, 0.42)
const ENVELOPE_IVORY := Color(0.96, 0.90, 0.74)
const ENVELOPE_GOLD := Color(0.92, 0.74, 0.38)
const ENVELOPE_COPPER := Color(0.68, 0.35, 0.20)
const SUN_DIR := Vector3(0.64, 0.42, -0.64)

## Mood palettes for `cloud_light` (`Amber noon` / `Copper sunset` / `Stormy gold`), sRGB.
const MOODS := {
	"amber": {
		"zenith": Color(0.96, 0.88, 0.69),
		"horizon": Color(0.92, 0.68, 0.35),
		"crest": Color(1.0, 0.85, 0.54),
		"mid": Color(0.78, 0.44, 0.17),
		"deep": Color(0.35, 0.15, 0.06),
		"sun": Color(1.0, 0.94, 0.76),
		"shaft": Color(1.0, 0.82, 0.46),
		"lightning": Color(1.0, 0.89, 0.70),
		"lightning_gain": 0.62,
		"env_top": Color(0.42, 0.37, 0.27),
		"env_low": Color(0.56, 0.35, 0.16),
		"env_sun": Vector3(0.98, 0.84, 0.56),
		"env_bounce": Vector3(0.72, 0.42, 0.14),
		"shaft_level": 0.38,
	},
	"copper": {
		"zenith": Color(0.84, 0.54, 0.36),
		"horizon": Color(0.92, 0.44, 0.20),
		"crest": Color(1.0, 0.67, 0.40),
		"mid": Color(0.64, 0.23, 0.11),
		"deep": Color(0.24, 0.07, 0.04),
		"sun": Color(1.0, 0.62, 0.30),
		"shaft": Color(1.0, 0.56, 0.28),
		"lightning": Color(1.0, 0.76, 0.56),
		"lightning_gain": 0.55,
		"env_top": Color(0.36, 0.23, 0.15),
		"env_low": Color(0.58, 0.24, 0.10),
		"env_sun": Vector3(1.02, 0.58, 0.28),
		"env_bounce": Vector3(0.76, 0.28, 0.10),
		"shaft_level": 0.40,
	},
	"stormy": {
		"zenith": Color(0.64, 0.52, 0.34),
		"horizon": Color(0.72, 0.48, 0.21),
		"crest": Color(0.88, 0.68, 0.34),
		"mid": Color(0.36, 0.22, 0.11),
		"deep": Color(0.14, 0.08, 0.04),
		"sun": Color(0.88, 0.70, 0.40),
		"shaft": Color(0.86, 0.68, 0.36),
		"lightning": Color(1.0, 0.90, 0.74),
		"lightning_gain": 1.0,
		"env_top": Color(0.26, 0.21, 0.14),
		"env_low": Color(0.40, 0.25, 0.11),
		"env_sun": Vector3(0.74, 0.58, 0.32),
		"env_bounce": Vector3(0.56, 0.34, 0.12),
		"shaft_level": 0.28,
	},
}

## Distant companion aerostats: [world position, yaw_deg, scale, drift_phase].
const COMPANIONS: Array = [
	[Vector3(72.0, 8.5, -34.0), 22.0, 1.08, 0.0],
	[Vector3(-76.0, 4.5, -10.0), -18.0, 0.96, 1.8],
	[Vector3(86.0, -4.5, 42.0), 148.0, 1.14, 3.4],
	[Vector3(-92.0, 13.0, 30.0), -145.0, 0.92, 5.1],
]

## Soft slanting golden Venusian cloud shafts strictly outside the gondola: [mid_pos, radius_top, radius_bot, len, weight].
const SHAFTS: Array = [
	[Vector3(23.0, 2.5, -14.0), 2.1, 3.6, 34.0, 0.90],
	[Vector3(-23.0, 2.5, -12.0), 2.0, 3.4, 34.0, 0.84],
	[Vector3(24.0, 1.5, 11.0), 2.3, 4.0, 36.0, 0.78],
	[Vector3(-24.0, 1.5, 13.0), 2.2, 3.8, 36.0, 0.74],
	[Vector3(6.0, 2.0, 28.0), 2.0, 3.4, 34.0, 0.68],
]


## Custom `c.halls` exterior world manager: 360-degree Venusian cloud canyon sphere, vast overhead buoyant gas envelope
## & rigging, 4 distant companion aerostats, and slanting golden cloud shafts. Driven live in tick(delta).
class VenusCloudsHall:
	var kit: Node
	var cloud_node: MeshInstance3D
	var cloud_m: ShaderMaterial
	var env_node: MeshInstance3D
	var env_m: ShaderMaterial
	var comp_node: MultiMeshInstance3D
	var comp_mm: MultiMesh
	var comp_m: ShaderMaterial
	var comp_rest: Array[Transform3D] = []
	var shaft_node: MeshInstance3D
	var shaft_m: ShaderMaterial
	var _cloud_t := 0.0
	var _lightning_t := 0.0
	var _exterior := 1.0
	var _lightning_cur := 0.0
	var _cur_zenith: Color = MOODS["amber"]["zenith"]
	var _cur_horizon: Color = MOODS["amber"]["horizon"]
	var _cur_crest: Color = MOODS["amber"]["crest"]
	var _cur_mid: Color = MOODS["amber"]["mid"]
	var _cur_deep: Color = MOODS["amber"]["deep"]
	var _cur_sun: Color = MOODS["amber"]["sun"]
	var _cur_shaft: Color = MOODS["amber"]["shaft"]
	var _cur_light: Color = MOODS["amber"]["lightning"]
	var _cur_env_top: Color = MOODS["amber"]["env_top"]
	var _cur_env_low: Color = MOODS["amber"]["env_low"]
	var _cur_env_sun: Vector3 = MOODS["amber"]["env_sun"]
	var _cur_env_bounce: Vector3 = MOODS["amber"]["env_bounce"]
	var _cur_shaft_lvl: float = MOODS["amber"]["shaft_level"]

	func finish(k: Node) -> void:
		kit = k
		# Tune PieceGlass to crystal-clear golden-ivory Fresnel glazing so the Venusian cloud canyons shine cleanly.
		for n: Node in k.owned():
			if n is MeshInstance3D and str(n.name).begins_with("PieceGlass"):
				var gm := (n as MeshInstance3D).material_override as ShaderMaterial
				if gm != null:
					gm.set_shader_parameter("alpha", 0.045)
					gm.set_shader_parameter("rim", 0.16)
					gm.set_shader_parameter("sky_colour", Color(0.96, 0.78, 0.45))
					gm.set_shader_parameter("sky_mix", 0.35)
		var noise := SkySys.noise_texture()

		# 1. Enveloping 360-degree opaque Venusian golden-amber cloud canyon sphere (r = 160 m, 1 draw, 0 blend).
		cloud_m = ShaderMaterial.new()
		cloud_m.shader = CLOUDS_SHADER
		cloud_m.set_shader_parameter("noise_map", noise)
		cloud_m.set_shader_parameter("sun_dir", SUN_DIR.normalized())
		var sb := RoomMesh.new()
		sb.surface(cloud_m)
		sb.colour = Color.WHITE
		Shapes.dome(sb, Vector3.ZERO, CLOUD_RADIUS, 28, 56, true, -PI * 0.5, PI * 0.5)
		cloud_node = k._add_unbaked("VenusCloudSphere", sb)
		if cloud_node != null:
			cloud_node.add_to_group("env_see_through")

		# 2. Vast overhead glowing ivory-and-gold buoyant aerostat gas envelope + 16 suspension rigging cables (1 draw).
		env_m = ShaderMaterial.new()
		env_m.shader = OUTSIDE_SHADER
		env_m.set_shader_parameter("moon_dir", SUN_DIR.normalized())
		env_m.set_shader_parameter("aurora_dir", Vector3.DOWN)
		env_m.set_shader_parameter("glitter", 0.0)
		env_m.set_shader_parameter("haze", 0.0052)
		env_m.set_shader_parameter("glow", 1.35)
		var eb := RoomMesh.new()
		eb.surface(env_m)
		_build_overhead_envelope(eb)
		env_node = k._add_unbaked("VenusEnvelope", eb)

		# 3. Four distant floating companion buoyant aerostats gliding peacefully across the cloud canyons (1 draw).
		comp_m = ShaderMaterial.new()
		comp_m.shader = OUTSIDE_SHADER
		comp_m.set_shader_parameter("moon_dir", SUN_DIR.normalized())
		comp_m.set_shader_parameter("aurora_dir", Vector3.DOWN)
		comp_m.set_shader_parameter("glitter", 0.0)
		comp_m.set_shader_parameter("haze", 0.0082)
		comp_m.set_shader_parameter("glow", 1.5)
		var cb := RoomMesh.new()
		cb.surface(comp_m)
		_build_companion_aerostat(cb)
		var comp_mesh := cb.commit(false)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = comp_mesh
		mm.instance_count = COMPANIONS.size()
		comp_rest.clear()
		for i in COMPANIONS.size():
			var cd: Array = COMPANIONS[i]
			var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(cd[1]))).scaled(Vector3.ONE * float(cd[2])),
					cd[0] as Vector3)
			mm.set_instance_transform(i, xf)
			comp_rest.append(xf)
		comp_mm = mm
		comp_node = MultiMeshInstance3D.new()
		comp_node.name = "VenusCompanions"
		comp_node.multimesh = mm
		comp_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		comp_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		comp_node.set_meta("instances", COMPANIONS.size())
		comp_node.set_meta("env_placed", comp_rest.duplicate())
		k.own(comp_node)

		# 4. Soft slanting golden Venusian sunbeam shafts strictly outside the gondola (1 draw, env_see_through).
		shaft_m = ShaderMaterial.new()
		shaft_m.shader = SHAFT_SHADER
		shaft_m.set_shader_parameter("noise_map", noise)
		shaft_m.set_shader_parameter("edge_softness", 2.0)
		shaft_m.set_shader_parameter("wisp_strength", 0.42)
		var sh_mesh := _build_shafts_mesh(shaft_m)
		shaft_node = k._add_mesh("VenusCloudShafts", sh_mesh)
		if shaft_node != null:
			shaft_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			shaft_node.add_to_group("env_see_through")

		# Snap immediately to initial mood/settings.
		tick(0.0)

	func tick(delta: float) -> void:
		if cloud_m == null or kit == null:
			return
		var host: Node = kit.host
		var mood_key := "amber"
		var lightning_setting := "glow"
		var flicker_on := true
		var motion := 1.0
		var playing := false
		if host != null:
			var mv: Variant = host.setting("cloud_light")
			if mv != null and MOODS.has(str(mv)):
				mood_key = str(mv)
			var lv: Variant = host.setting("lightning")
			if lv != null:
				lightning_setting = str(lv)
			var fv: Variant = host.setting("flicker")
			if fv != null:
				flicker_on = bool(fv)
			var mot: Variant = host.setting("motion")
			if mot != null:
				motion = clampf(float(mot), 0.0, 1.0)
			if host.get("timeline") != null:
				playing = str(host.timeline.state) in ["starting", "playing", "credits"]

		var md: Dictionary = MOODS[mood_key]
		var target_ext := 0.42 if playing else 1.0
		var want_lightning := (lightning_setting != "off" and flicker_on)
		var target_light := (float(md["lightning_gain"]) * (0.42 if playing else 1.0)) if want_lightning else 0.0

		if delta <= 0.0:
			_exterior = target_ext
			_lightning_cur = target_light
			_cur_zenith = md["zenith"]
			_cur_horizon = md["horizon"]
			_cur_crest = md["crest"]
			_cur_mid = md["mid"]
			_cur_deep = md["deep"]
			_cur_sun = md["sun"]
			_cur_shaft = md["shaft"]
			_cur_light = md["lightning"]
			_cur_env_top = md["env_top"]
			_cur_env_low = md["env_low"]
			_cur_env_sun = md["env_sun"]
			_cur_env_bounce = md["env_bounce"]
			_cur_shaft_lvl = float(md["shaft_level"])
		else:
			_cloud_t += delta * motion
			if want_lightning:
				_lightning_t += delta
			var rate := clampf(delta * 1.4, 0.0, 1.0)
			var ext_rate := clampf(delta * 0.45, 0.0, 1.0)
			_exterior = lerpf(_exterior, target_ext, ext_rate)
			_lightning_cur = 0.0 if not want_lightning else lerpf(_lightning_cur, target_light, rate)
			_cur_zenith = _cur_zenith.lerp(md["zenith"], rate)
			_cur_horizon = _cur_horizon.lerp(md["horizon"], rate)
			_cur_crest = _cur_crest.lerp(md["crest"], rate)
			_cur_mid = _cur_mid.lerp(md["mid"], rate)
			_cur_deep = _cur_deep.lerp(md["deep"], rate)
			_cur_sun = _cur_sun.lerp(md["sun"], rate)
			_cur_shaft = _cur_shaft.lerp(md["shaft"], rate)
			_cur_light = _cur_light.lerp(md["lightning"], rate)
			_cur_env_top = _cur_env_top.lerp(md["env_top"], rate)
			_cur_env_low = _cur_env_low.lerp(md["env_low"], rate)
			_cur_env_sun = _cur_env_sun.lerp(md["env_sun"], rate)
			_cur_env_bounce = _cur_env_bounce.lerp(md["env_bounce"], rate)
			_cur_shaft_lvl = lerpf(_cur_shaft_lvl, float(md["shaft_level"]), rate)

		cloud_m.set_shader_parameter("clock", _cloud_t)
		cloud_m.set_shader_parameter("zenith_col", _cur_zenith)
		cloud_m.set_shader_parameter("horizon_col", _cur_horizon)
		cloud_m.set_shader_parameter("cloud_crest_col", _cur_crest)
		cloud_m.set_shader_parameter("canyon_mid_col", _cur_mid)
		cloud_m.set_shader_parameter("canyon_deep_col", _cur_deep)
		cloud_m.set_shader_parameter("sun_glow_col", _cur_sun)
		cloud_m.set_shader_parameter("exterior_level", _exterior)
		cloud_m.set_shader_parameter("lightning_level", _lightning_cur)
		cloud_m.set_shader_parameter("lightning_clock", _lightning_t)
		cloud_m.set_shader_parameter("lightning_col", _cur_light)

		# Subtle slow sheet-lightning sympathetic underglow on the giant buoyant envelope belly (< 0.25 Hz!).
		var belly_flash := 0.0
		if _lightning_cur > 0.001:
			belly_flash = pow(0.5 + 0.5 * cos(TAU * 0.11 * _lightning_t + 0.4), 5.0) * _lightning_cur * 0.18
		for em: ShaderMaterial in [env_m, comp_m]:
			if em == null:
				continue
			em.set_shader_parameter("sky_top", _cur_env_top * _exterior)
			em.set_shader_parameter("sky_low", _cur_env_low * _exterior)
			em.set_shader_parameter("sky_gain", 1.0)
			em.set_shader_parameter("moon_light", _cur_env_sun * _exterior)
			em.set_shader_parameter("aurora_light", (_cur_env_bounce + Vector3(1.0, 0.85, 0.62) * belly_flash) * _exterior)

		if shaft_m != null:
			shaft_m.set_shader_parameter("shaft_colour", _cur_shaft)
			shaft_m.set_shader_parameter("shaft_level", _cur_shaft_lvl * _exterior)
			shaft_m.set_shader_parameter("clock", _cloud_t)

		# Gentle slow buoyant hover of the 4 distant companion aerostats (zero drift when Motion < 0.25).
		if comp_mm != null and motion >= MOTION_FLOOR and delta > 0.0:
			for i in comp_rest.size():
				var ph := float(COMPANIONS[i][3])
				var bob := 0.34 * sin(_cloud_t * 0.18 + ph)
				var sway := 0.55 * sin(_cloud_t * 0.07 + ph * 1.7)
				var base := comp_rest[i]
				var xf := Transform3D(base.basis, base.origin + Vector3(sway, bob, 0.0))
				comp_mm.set_instance_transform(i, xf)

		if cloud_node != null and is_instance_valid(cloud_node):
			cloud_node.set_meta("cloud_mood", mood_key)
			cloud_node.set_meta("lightning_level", _lightning_cur)
			cloud_node.set_meta("exterior_level", _exterior)
			cloud_node.set_meta("cloud_clock", _cloud_t)

	## Builds the vast glowing ivory-and-gold fluted buoyant aerostat gas envelope curving 13-28 m overhead,
	## plus gilded equatorial bands, swept stabilizing tail fins, belly keel harness and 16 rigging cables.
	static func _build_overhead_envelope(b: RoomMesh) -> void:
		var env_c := Vector3(0.0, 20.8, CENTER_Z)
		var half_len := 20.5
		var max_r := 7.6
		var segs_z := 22
		var segs_a := 28
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		var ivory := ENVELOPE_IVORY.srgb_to_linear()
		var gold := ENVELOPE_GOLD.srgb_to_linear()
		var copper := ENVELOPE_COPPER.srgb_to_linear()

		for iz in segs_z + 1:
			var t := float(iz) / float(segs_z) # 0 = nose (-Z), 1 = tail (+Z)
			var u := t * 2.0 - 1.0 # -1 .. +1
			# Classic aerodynamic dirigible profile: fuller forward nose, gracefully tapering stern.
			var bulge := maxf(pow(maxf(1.0 - u * u, 0.0), 0.54) * (1.0 - 0.15 * u), 0.04)
			var r_base := max_r * bulge
			var z := env_c.z + u * half_len
			# Circumferential gilded Art Nouveau load bands at 5 structural ring stations.
			var is_band := iz in [4, 8, 12, 16, 19]
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for ia in segs_a + 1:
				var a := TAU * float(ia % segs_a) / float(segs_a)
				# Subtle 14-lobe buoyant gas-cell gores along the hull!
				var gore := 1.0 + 0.022 * absf(sin(a * 7.0))
				var r := r_base * (1.022 if is_band else gore)
				var ca := cos(a)
				var sa := sin(a)
				var pt := Vector3(ca * r, env_c.y + sa * r, z)
				# Approximate smooth outward normal.
				var dz_slope := -u * 0.35
				var n := Vector3(ca, sa, dz_slope).normalized()
				row.append(pt)
				nrow.append(n)
				var col: Color
				if is_band:
					col = gold
				elif absf(sa) < 0.14:
					# Gilded Art Nouveau equatorial belt along both flanks!
					col = gold * 0.94
				elif ia % 2 == 0:
					col = ivory
				else:
					col = ivory * 0.91
				crow.append(Color(col.r, col.g, col.b, 1.0))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		b.grid(rows, norms, cols)

		# Nose mooring cone cap + stern copper finial cone.
		b.colour = Color(gold.r, gold.g, gold.b, 1.0)
		Shapes.lathe(b, [Vector2(1.4, 0.0), Vector2(0.55, 1.0), Vector2(0.18, 1.8), Vector2(0.0, 2.2)],
				Vector3(0.0, env_c.y, env_c.z - half_len + 0.3), 14, Basis(Vector3.RIGHT, -PI * 0.5))
		Shapes.lathe(b, [Vector2(1.1, 0.0), Vector2(0.4, 0.9), Vector2(0.0, 1.6)],
				Vector3(0.0, env_c.y, env_c.z + half_len - 0.3), 14, Basis(Vector3.RIGHT, PI * 0.5))

		# Four sweeping Art Nouveau gilded tail stabilizer fins (dorsal, ventral, port, starboard) at stern.
		b.colour = Color(copper.r, copper.g, copper.b, 1.0)
		for k in 4:
			var ang := float(k) * PI * 0.5
			var fin_b := Basis(Vector3.BACK, ang)
			var fin_c := Vector3(0.0, env_c.y, env_c.z + 13.8) + fin_b * Vector3(5.6, 0.0, 0.0)
			b.box(fin_c, Vector3(4.2, 0.24, 7.6), fin_b)
			b.colour = Color(gold.r, gold.g, gold.b, 1.0)
			b.box(fin_c + fin_b * Vector3(2.15, 0.0, 0.0), Vector3(0.22, 0.30, 7.8), fin_b)
			b.colour = Color(copper.r, copper.g, copper.b, 1.0)

		# Sculpted narrow Art Nouveau brass-and-copper lattice keel spine suspended cleanly beneath the envelope belly
		# (belly bottom sits at y = 13.03 m; keel spine at y = 12.45..12.82 m stays completely clear of the hull skin!).
		var keel_y := 12.48
		b.colour = Color(copper.r, copper.g, copper.b, 1.0)
		b.box(Vector3(0.0, keel_y + 0.24, CENTER_Z), Vector3(0.50, 0.30, 15.4))
		b.colour = Color(gold.r, gold.g, gold.b, 1.0)
		for side: float in [-1.0, 1.0]:
			b.box(Vector3(side * 1.18, keel_y + 0.20, CENTER_Z), Vector3(0.14, 0.18, 15.2))
			# Warm glowing amber navigation beacons along the open lattice keel ribs (COLOR.a = 0.0 -> self-lit!).
			b.colour = Color(1.0, 0.80, 0.38, 0.0)
			for bz: float in [-6.8, -2.3, 2.3, 6.8]:
				b.box(Vector3(side * 1.32, keel_y + 0.12, CENTER_Z + bz), Vector3(0.18, 0.15, 0.24))
			b.colour = Color(gold.r, gold.g, gold.b, 1.0)
		# Open transverse brass spreader ribs & diagonal X-braces connecting the twin gilded keel rails!
		for kz: float in [-7.2, -4.8, -2.4, 0.0, 2.4, 4.8, 7.2]:
			b.box(Vector3(0.0, keel_y + 0.22, CENTER_Z + kz), Vector3(2.44, 0.14, 0.18))
		for kz: float in [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0]:
			Shapes.beam(b, Vector3(-1.12, keel_y + 0.20, CENTER_Z + kz - 1.1),
					Vector3(1.12, keel_y + 0.20, CENTER_Z + kz + 1.1), Vector2(0.08, 0.08))
			Shapes.beam(b, Vector3(1.12, keel_y + 0.20, CENTER_Z + kz - 1.1),
					Vector3(-1.12, keel_y + 0.20, CENTER_Z + kz + 1.1), Vector2(0.08, 0.08))

		# Sixteen taut bronze-brass suspension rigging cables fanning cleanly from the envelope load-frame down to the
		# gondola's exterior octagonal compression ring (y = 4.95 m) and upper skylight ring (y = 7.42 m)!
		b.colour = Color(gold.r * 0.85, gold.g * 0.85, gold.b * 0.85, 1.0)
		for i in OCT.size():
			var v := OCT[i]
			var out_p := Vector3(v.x * 1.015, WALL_TOP + 0.06, v.y)
			var top_x := signf(v.x) * (3.6 if absf(v.x) > 4.5 else 2.2)
			var top_z := clampf(v.y * 0.95, CENTER_Z - 7.8, CENTER_Z + 7.8)
			var top_y := keel_y + 0.95
			Shapes.beam(b, out_p, Vector3(top_x, top_y, top_z), Vector2(0.055, 0.055))
			var ang := atan2(v.x, v.y - CENTER_Z)
			var ring_p := Vector3(sin(ang) * (OCULUS_R + 0.22), OCULUS_Y + 0.08, CENTER_Z + cos(ang) * (OCULUS_R + 0.22))
			var keel_p := Vector3(signf(v.x) * 1.18, keel_y + 0.16, clampf(ring_p.z * 1.15, CENTER_Z - 7.2, CENTER_Z + 7.2))
			Shapes.beam(b, ring_p, keel_p, Vector2(0.042, 0.042))
		b.colour = Color.WHITE

	## Builds one streamlined distant floating companion aerostat (teardrop ivory-gold gas hull, copper girdle bands,
	## tail fins, suspension wires, hanging passenger gondola & warm glowing amber window strip).
	static func _build_companion_aerostat(b: RoomMesh) -> void:
		var ivory := ENVELOPE_IVORY.srgb_to_linear()
		var gold := ENVELOPE_GOLD.srgb_to_linear()
		var copper := ENVELOPE_COPPER.srgb_to_linear()
		var half_len := 10.5
		var max_r := 3.6
		var prof: Array = []
		for k in 13:
			var t := float(k) / 12.0
			var u := t * 2.0 - 1.0
			var r := max_r * pow(maxf(1.0 - u * u, 0.0), 0.56) * (1.0 - 0.14 * u)
			prof.append(Vector2(maxf(r, 0.02), u * half_len))
		b.colour = Color(ivory.r, ivory.g, ivory.b, 1.0)
		Shapes.lathe(b, prof, Vector3(0.0, 4.8, 0.0), 16, Basis(Vector3.RIGHT, PI * 0.5))
		# Gilded equatorial bands around the companion envelope.
		b.colour = Color(gold.r, gold.g, gold.b, 1.0)
		for z_off: float in [-3.4, 0.2, 3.8]:
			var u := z_off / half_len
			var r := max_r * pow(maxf(1.0 - u * u, 0.0), 0.56) * (1.0 - 0.14 * u) + 0.08
			Shapes.cylinder(b, Vector3(0.0, 4.8, z_off - 0.22), r, 0.44, 16, Basis(Vector3.RIGHT, PI * 0.5), false)
		# Swept tail stabilizer fins.
		b.colour = Color(copper.r, copper.g, copper.b, 1.0)
		b.box(Vector3(0.0, 4.8, 7.6), Vector3(6.2, 0.22, 3.6))
		b.box(Vector3(0.0, 4.8, 7.6), Vector3(0.22, 5.8, 3.6))
		# Suspended miniature hammered-copper passenger gondola underneath + 4 slim rigging cables.
		b.box(Vector3(0.0, -0.4, -0.6), Vector3(2.4, 1.5, 5.8))
		b.colour = Color(gold.r, gold.g, gold.b, 1.0)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-2.2, 1.2]:
				Shapes.beam(b, Vector3(sx * 1.1, 0.3, sz), Vector3(sx * 1.6, 2.0, sz * 1.2), Vector2(0.07, 0.07))
		# Warm glowing amber observation windows along the companion gondola (COLOR.a = 0.0 -> self-lit!).
		b.colour = Color(1.0, 0.80, 0.42, 0.0)
		b.box(Vector3(0.0, -0.25, -0.6), Vector3(2.48, 0.58, 4.4))
		b.colour = Color.WHITE

	## Builds the 5 soft slanting golden Venusian sunbeams strictly outside the gondola (env_world_shaft.gdshader).
	static func _build_shafts_mesh(mat: Material) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var dir := Vector3(-0.45, -0.78, 0.43).normalized()
		var up_ref := Vector3.RIGHT if absf(dir.y) > 0.95 else Vector3.UP
		var ax := up_ref.cross(dir).normalized()
		var ay := dir.cross(ax).normalized()
		var sides := 14
		var rings := 4
		for sh: Array in SHAFTS:
			var mid: Vector3 = sh[0]
			var r0 := float(sh[1])
			var r1 := float(sh[2])
			var length := float(sh[3])
			var top := mid - dir * (length * 0.5)
			var w := float(sh[4])
			for ri in rings:
				var v0 := float(ri) / float(rings)
				var v1 := float(ri + 1) / float(rings)
				var c0 := top + dir * (v0 * length)
				var c1 := top + dir * (v1 * length)
				var rad0 := lerpf(r0, r1, v0)
				var rad1 := lerpf(r0, r1, v1)
				for si in sides:
					var u0 := float(si) / float(sides)
					var u1 := float(si + 1) / float(sides)
					var a0 := u0 * TAU
					var a1 := u1 * TAU
					var d0 := ax * cos(a0) + ay * sin(a0)
					var d1 := ax * cos(a1) + ay * sin(a1)
					var p00 := c0 + d0 * rad0
					var p10 := c0 + d1 * rad0
					var p11 := c1 + d1 * rad1
					var p01 := c1 + d0 * rad1
					var col := Color(1.0, 0.96, 0.88, w)
					for tri_v: Array in [
						[p00, d0, Vector2(u0, v0)], [p10, d1, Vector2(u1, v0)], [p11, d1, Vector2(u1, v1)],
						[p00, d0, Vector2(u0, v0)], [p11, d1, Vector2(u1, v1)], [p01, d0, Vector2(u0, v1)],
					]:
						st.set_color(col)
						st.set_normal(tri_v[1])
						st.set_uv(tri_v[2])
						st.add_vertex(tri_v[0])
		var mesh := st.commit()
		mesh.surface_set_material(0, mat)
		return mesh


# --- Entry point ------------------------------------------------------------------------------------------------------

static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"venus_gondola":
			_build_gondola(c)
		"venus_clouds":
			c.halls.append(VenusCloudsHall.new())


# --- Geometry helpers -------------------------------------------------------------------------------------------------

static func _edge(i: int) -> Dictionary:
	var a2 := OCT[i]
	var b2 := OCT[(i + 1) % OCT.size()]
	var a := Vector3(a2.x, 0.0, a2.y)
	var b := Vector3(b2.x, 0.0, b2.y)
	var length := a.distance_to(b)
	var along := (b - a) / length
	var n := along.cross(Vector3.UP).normalized()
	return {"a": a, "b": b, "mid": (a + b) * 0.5, "len": length, "along": along, "n": n,
			"basis": Basis(along, Vector3.UP, n)}


static func _pt(e: Dictionary, u: float, y: float, inset := 0.0) -> Vector3:
	return (e["a"] as Vector3) + (e["along"] as Vector3) * u + Vector3.UP * y + (e["n"] as Vector3) * inset


static func _metal_brass(c: Object) -> Material:
	return c.shiny("gilt", 0.90, 0.72, 0.16)


static func _metal_copper(c: Object) -> Material:
	return c.shiny("chrome", 0.84, 0.56, 0.22)


# --- The Art Nouveau pressurised observation gondola ------------------------------------------------------------------

static func _build_gondola(c: Object) -> void:
	_floor_and_compass_rose(c)
	_hull_dado_and_panoramic_bays(c)
	_mezzanine_catwalk_and_skylight_dome(c)
	_screen_proscenium(c)
	_tulip_sconces_and_pendants(c)
	_hanging_terrariums_and_planters(c)
	_barometer_spectrometer_and_binnacle(c)
	_aft_airlock_and_clock(c)
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE
	c.cove.colour = Color.WHITE


## Warm inlaid herringbone parquet oak floor, dark walnut perimeter border with inlaid brass fillet lines, central
## inlaid brass & walnut compass rose in the forward viewing gallery, deep sea-teal velvet salon rug under the
## seating island, and an exterior copper-bronze hull keel skirt beneath floor level.
static func _floor_and_compass_rose(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# 1. Full octagonal inlaid parquet oak floor slab (y = 0.0).
	s.surface(c.tinted("wood"))
	s.colour = OAK_WARM.srgb_to_linear()
	var poly := PackedVector3Array()
	for v: Vector2 in OCT:
		poly.append(Vector3(v.x, 0.0, v.y))
	s.polygon(poly, Vector3.UP)

	# Outer dark walnut perimeter border strips + gleaming inlaid brass floor fillets along all 8 walls.
	s.colour = WALNUT_DARK.srgb_to_linear()
	u.surface(_metal_brass(c))
	u.colour = BRASS_WARM.srgb_to_linear()
	for i in OCT.size():
		var e := _edge(i)
		var b_w: Basis = e["basis"]
		var flen: float = e["len"]
		s.box((e["mid"] as Vector3) + (e["n"] as Vector3) * 0.28 + Vector3(0.0, 0.002, 0.0),
				Vector3(flen - 0.12, 0.004, 0.56), b_w, [RoomMesh.DOWN])
		u.box((e["mid"] as Vector3) + (e["n"] as Vector3) * 0.58 + Vector3(0.0, 0.004, 0.0),
				Vector3(flen - 0.48, 0.005, 0.036), b_w, [RoomMesh.DOWN])
		u.box((e["mid"] as Vector3) + (e["n"] as Vector3) * 0.66 + Vector3(0.0, 0.004, 0.0),
				Vector3(flen - 0.56, 0.005, 0.018), b_w, [RoomMesh.DOWN])

	# 2. Grand inlaid brass, walnut & cream-enamel compass rose centred in the open forward gallery (0, 0, -4.45)!
	var rc := Vector3(0.0, 0.005, -4.45)
	var flat_b := Basis(Vector3.RIGHT, -PI * 0.5)
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.arch(u, rc + Vector3(0.0, 0.003, 0.0), 1.38, 1.48, 0.006, 32, flat_b, 0.0, TAU, ["front"])
	Shapes.arch(u, rc + Vector3(0.0, 0.003, 0.0), 1.04, 1.10, 0.006, 32, flat_b, 0.0, TAU, ["front"])
	Shapes.arch(u, rc + Vector3(0.0, 0.003, 0.0), 0.34, 0.39, 0.006, 24, flat_b, 0.0, TAU, ["front"])
	# 16 fine radial brass degree ticks between the outer rings.
	for k in 16:
		var a := float(k) * TAU / 16.0
		var r_mid := 1.24
		u.box(rc + Vector3(sin(a) * r_mid, 0.003, cos(a) * r_mid), Vector3(0.022, 0.006, 0.24),
				Basis(Vector3.UP, a), [RoomMesh.DOWN])
	# 8-point alternating burnished-brass and dark-walnut compass rose star points!
	for k in 8:
		var a := float(k) * PI * 0.25
		var tip_r := 1.36 if k % 2 == 0 else 0.98
		var half_w := 0.22 if k % 2 == 0 else 0.16
		var dir := Vector3(sin(a), 0.0, cos(a))
		var side := Vector3(cos(a), 0.0, -sin(a))
		var p_ctr := rc + Vector3(0.0, 0.006, 0.0)
		var p_tip := p_ctr + dir * tip_r
		var p_l := p_ctr + dir * 0.24 - side * half_w
		var p_r := p_ctr + dir * 0.24 + side * half_w
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		u.face([p_ctr, p_tip, p_r], Vector3.UP)
		u.surface(c.soft("plastic", true))
		u.colour = WALNUT_DARK.srgb_to_linear()
		u.face([p_ctr, p_l, p_tip], Vector3.UP)
	# Central cream-enamel & brass astrolabe medallion boss.
	u.surface(c.soft("plastic", true))
	u.colour = ENAMEL_CREAM.srgb_to_linear()
	Shapes.cylinder(u, rc, 0.22, 0.007, 16)
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.cylinder(u, rc + Vector3(0.0, 0.005, 0.0), 0.10, 0.008, 14)

	# 3. Sculpted octagonal deep sea-teal velvet salon rug tucked neatly beneath the 3x3 lounge seating island.
	var rx := 2.32
	var rz := 2.62
	var ch := 0.58
	var rug_pts := PackedVector3Array([
		Vector3(-rx + ch, 0.008, -rz), Vector3(rx - ch, 0.008, -rz),
		Vector3(rx, 0.008, -rz + ch), Vector3(rx, 0.008, rz - ch),
		Vector3(rx - ch, 0.008, rz), Vector3(-rx + ch, 0.008, rz),
		Vector3(-rx, 0.008, rz - ch), Vector3(-rx, 0.008, -rz + ch),
	])
	s.surface(c.tinted("fabric"))
	s.colour = TEAL_VELVET.srgb_to_linear()
	s.polygon(rug_pts, Vector3.UP)
	# Warm gold-brass braided border trim framing the octagonal sea-teal salon rug.
	u.surface(_metal_brass(c))
	u.colour = BRASS_WARM.srgb_to_linear()
	for i in rug_pts.size():
		var pa := rug_pts[i]
		var pb := rug_pts[(i + 1) % rug_pts.size()]
		Shapes.beam(u, pa + Vector3(0.0, 0.003, 0.0), pb + Vector3(0.0, 0.003, 0.0), Vector2(0.055, 0.008))

	# 4. Exterior copper-bronze hull keel skirt beneath the gondola deck so downward exterior views look solid.
	s.surface(c.tinted("iron"))
	s.colour = COPPER_DEEP.srgb_to_linear()
	for i in OCT.size():
		var e := _edge(i)
		var b_w: Basis = e["basis"]
		s.box((e["mid"] as Vector3) - (e["n"] as Vector3) * 0.18 + Vector3(0.0, -0.55, 0.0),
				Vector3(float(e["len"]) + 0.3, 1.1, 0.36), b_w)


## Patinated hammered-copper lower pressure dado with riveted brass bands & walnut sills, 8 master corner piers, and
## 16 sweeping arched brass-and-copper panoramic observation bays wrapping port, starboard, diagonals and aft.
static func _hull_dado_and_panoramic_bays(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	glass.surface(c.kit.GLASS)

	# 1. Eight monumental Art Nouveau corner master piers (V0..V7, y = 0 .. WALL_TOP).
	for i in OCT.size():
		var v := OCT[i]
		var to_c := Vector3(-v.x, 0.0, CENTER_Z - v.y).normalized()
		var pb := Basis(Vector3.UP.cross(to_c).normalized(), Vector3.UP, to_c)
		var p_at := Vector3(v.x, 0.0, v.y) + to_c * 0.14
		# Patinated hammered-copper structural pier body (static baked).
		s.surface(c.tinted("iron"))
		s.colour = COPPER_DEEP.srgb_to_linear()
		s.box(p_at + Vector3(0.0, WALL_TOP * 0.5, 0.0), Vector3(0.38, WALL_TOP, 0.32), pb, [RoomMesh.DOWN])
		# Verdigris bronze pedestal base plinth.
		s.colour = VERDIGRIS_DARK.srgb_to_linear()
		s.box(p_at + Vector3(0.0, 0.24, 0.0) + to_c * 0.04, Vector3(0.46, 0.48, 0.38), pb, [RoomMesh.DOWN])
		# Gleaming burnished-brass twin Art Nouveau fluted colonnettes & collar rings up the inner pier face.
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		for sx: float in [-0.14, 0.14]:
			Shapes.cylinder(u, p_at + pb.x * sx + to_c * 0.16, 0.042, WALL_TOP - 0.12, 8)
		for cy: float in [0.49, DADO_H, 2.35, 3.65, 4.55]:
			u.box(p_at + Vector3(0.0, cy, 0.0) + to_c * 0.04, Vector3(0.44, 0.065, 0.38), pb)
		# Hammered-copper & brass flared Art Nouveau capital springing toward the dome ribs.
		u.surface(_metal_copper(c))
		u.colour = COPPER_BRIGHT.srgb_to_linear()
		u.box(p_at + Vector3(0.0, WALL_TOP - 0.16, 0.0) + to_c * 0.07, Vector3(0.50, 0.26, 0.42), pb)
		# Physics box for each corner master pier (all at r >= 6.1 m, completely clear of origin and seats).
		c.shapes.append(PhysicsShapes.box(p_at + Vector3(0.0, WALL_TOP * 0.5, 0.0), Vector3(0.42, WALL_TOP, 0.36), pb))

	# 2. All 7 panoramic / aft walls (Edges 1..7; Edge 0 is the solid screen proscenium).
	for ei in range(1, 8):
		var e := _edge(ei)
		var flen: float = e["len"]
		var b_w: Basis = e["basis"]
		var n: Vector3 = e["n"]

		# --- A. Solid patinated hammered-copper lower pressure dado (y = 0 .. DADO_H = 1.05 m) ---
		if ei != 4:
			_dado_segment(c, e, 0.18, flen - 0.18)
		else:
			# Edge 4 (aft wall): dado flanks the central circular airlock hatch (u = 2.0 .. 5.3 is airlock bulkhead).
			_dado_segment(c, e, 0.18, 2.02)
			_dado_segment(c, e, flen - 2.02, flen - 0.18)

		# --- B. Upper cream-enamel & hammered-copper cornice frieze band (y = 4.66 .. WALL_TOP) ---
		s.surface(c.tinted("plaster"))
		s.colour = ENAMEL_CREAM.srgb_to_linear()
		s.box(_pt(e, flen * 0.5, 4.78, -0.02), Vector3(flen, 0.24, 0.22), b_w)
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		u.box(_pt(e, flen * 0.5, 4.66, 0.10), Vector3(flen, 0.048, 0.07), b_w)
		u.box(_pt(e, flen * 0.5, WALL_TOP - 0.02, 0.10), Vector3(flen, 0.055, 0.08), b_w)

		# --- C. Sweeping arched brass-and-copper panoramic observation bays (y = DADO_H .. 4.66 m) ---
		var spans: Array = [] # Array of [u0, u1] bay apertures
		if ei == 2 or ei == 6:
			# Broadsides (7.50 m): 3 sweeping grand panoramic arched bays!
			var inner := flen - 0.44
			for k in 3:
				spans.append([0.22 + inner * float(k) / 3.0, 0.22 + inner * float(k + 1) / 3.0])
		elif ei == 4:
			# Aft wall (7.30 m): 2 tall flanking arched panoramic bays either side of the central airlock bulkhead!
			spans.append([0.22, 2.02])
			spans.append([flen - 2.02, flen - 0.22])
		else:
			# Four diagonal walls (4.18 m): 2 sweeping arched panoramic bays each!
			var inner := flen - 0.44
			for k in 2:
				spans.append([0.22 + inner * float(k) / 2.0, 0.22 + inner * float(k + 1) / 2.0])

		for bi in spans.size():
			var u0 := float(spans[bi][0])
			var u1 := float(spans[bi][1])
			var um := (u0 + u1) * 0.5
			var bw := u1 - u0
			var half_w := bw * 0.5 - 0.07
			var spring_y := 3.68
			var arch_r := minf(half_w, 0.94)
			var arch_cy := 4.62 - arch_r

			# Intermediate structural brass-and-copper mullion pier between bays.
			if bi > 0 and ei != 4:
				u.surface(_metal_copper(c))
				u.colour = COPPER_HAMMERED.srgb_to_linear()
				u.box(_pt(e, u0, (DADO_H + 4.66) * 0.5, 0.02), Vector3(0.14, 4.66 - DADO_H, 0.18), b_w)
				u.surface(_metal_brass(c))
				u.colour = BRASS_BRIGHT.srgb_to_linear()
				Shapes.cylinder(u, _pt(e, u0, DADO_H, 0.11), 0.032, 4.66 - DADO_H, 8)
				u.box(_pt(e, u0, spring_y, 0.09), Vector3(0.18, 0.06, 0.12), b_w)

			# Sweeping Art Nouveau brass bay arch & slim decorative transom fin (keeps y = 1.08..3.64 WIDE OPEN!).
			u.surface(_metal_brass(c))
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			# Outer bay jamb bead rails.
			for sx: float in [-1.0, 1.0]:
				u.box(_pt(e, um + sx * half_w, (DADO_H + 4.62) * 0.5, 0.04), Vector3(0.055, 4.62 - DADO_H, 0.11), b_w)
			# Semicircular/elliptical Art Nouveau brass arch ring crowning the bay.
			Shapes.arch(u, _pt(e, um, arch_cy, 0.04), arch_r - 0.065, arch_r + 0.025, 0.11, 14, b_w, 0.0, PI)
			# Delicate inner brass spandrel botanical whiplash scroll rings tucked cleanly in the upper bay corners!
			for sx: float in [-1.0, 1.0]:
				var sp_u := um + sx * (half_w - 0.18)
				Shapes.arch(u, _pt(e, sp_u, 4.44, 0.04), 0.09, 0.125, 0.055, 10, b_w, 0.0, TAU, ["front", "inner", "outer"])
			# Ultra-slim Art Nouveau arched transom bar at y = 3.68 m + dainty upper fanlight mullion.
			u.colour = BRASS_WARM.srgb_to_linear()
			u.box(_pt(e, um, spring_y, 0.03), Vector3(half_w * 2.0, 0.028, 0.05), b_w)
			u.box(_pt(e, um, (spring_y + 4.60) * 0.5, 0.03), Vector3(0.026, 4.60 - spring_y, 0.045), b_w)
			# Subtle low brass safety handrail bar just above the walnut viewing sill (y = 1.24 m).
			Shapes.beam(u, _pt(e, u0 + 0.08, DADO_H + 0.19, 0.14), _pt(e, u1 - 0.08, DADO_H + 0.19, 0.14),
					Vector2(0.022, 0.022))

			# Single-surface crystal-clear pressurized panoramic window glazing (PieceGlass).
			var p_bl := _pt(e, u0 + 0.06, DADO_H + 0.02, -0.02)
			var p_br := _pt(e, u1 - 0.06, DADO_H + 0.02, -0.02)
			var p_tr := _pt(e, u1 - 0.06, 4.64, -0.02)
			var p_tl := _pt(e, u0 + 0.06, 4.64, -0.02)
			glass.face([p_bl, p_br, p_tr, p_tl], n)


## Helper: builds one stretch of patinated hammered-copper lower pressure dado with riveted brass bands, recessed
## copper Art Nouveau wall coffers, domed brass rivets, and a warm walnut & brass viewing sill ledge.
static func _dado_segment(c: Object, e: Dictionary, u0: float, u1: float) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var b_w: Basis = e["basis"]
	var span := u1 - u0
	var um := (u0 + u1) * 0.5

	# Main hammered-copper pressure dado hull plate (baked static).
	s.surface(c.tinted("iron"))
	s.colour = COPPER_HAMMERED.srgb_to_linear()
	s.box(_pt(e, um, DADO_H * 0.5, -0.06), Vector3(span, DADO_H, 0.20), b_w, [RoomMesh.DOWN])
	# Lower verdigris-patina baseboard skirting.
	s.colour = VERDIGRIS_DARK.srgb_to_linear()
	s.box(_pt(e, um, 0.09, 0.055), Vector3(span, 0.18, 0.04), b_w, [RoomMesh.DOWN])

	# Recessed dark-copper coffers + gleaming brass Art Nouveau panel mouldings.
	var n_pan := maxi(int(roundf(span / 1.15)), 1)
	var pw := (span - 0.14) / float(n_pan)
	u.surface(_metal_brass(c))
	for k in n_pan:
		var pu := u0 + 0.07 + (float(k) + 0.5) * pw
		s.surface(c.tinted("iron"))
		s.colour = COPPER_DEEP.srgb_to_linear()
		s.box(_pt(e, pu, 0.58, 0.048), Vector3(pw - 0.14, 0.54, 0.024), b_w)
		u.colour = BRASS_WARM.srgb_to_linear()
		var fw := pw - 0.12
		var fh := 0.56
		for sy: float in [-fh * 0.5, fh * 0.5]:
			u.box(_pt(e, pu, 0.58 + sy, 0.064), Vector3(fw, 0.022, 0.018), b_w)
		for sx: float in [-fw * 0.5, fw * 0.5]:
			u.box(_pt(e, pu + sx, 0.58, 0.064), Vector3(0.022, fh, 0.018), b_w)

	# Three continuous riveted burnished-brass horizontal pressure bands with domed brass rivets.
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	for by: float in [0.19, 0.96]:
		u.box(_pt(e, um, by, 0.062), Vector3(span, 0.044, 0.026), b_w)
		var rivets := maxi(int(span / 0.34), 2)
		for r in rivets:
			var ru := u0 + (float(r) + 0.5) * span / float(rivets)
			u.box(_pt(e, ru, by, 0.080), Vector3(0.022, 0.022, 0.014), b_w)

	# Sculpted warm walnut & burnished-brass panoramic viewing sill ledge (y = DADO_H = 1.05 m).
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_RICH.srgb_to_linear()
	s.box(_pt(e, um, DADO_H - 0.018, 0.06), Vector3(span + 0.04, 0.044, 0.26), b_w)
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	u.box(_pt(e, um, DADO_H - 0.016, 0.195), Vector3(span + 0.04, 0.024, 0.022), b_w)


## Wrought-brass mezzanine inspection catwalk balustrade (y = 4.65 .. 5.56 m), tucked indirect perimeter cove wash
## (`PieceCove`), 8 sweeping riveted copper-and-brass vaulted skylight dome ribs, intermediate brass purlin ring, and
## the grand 7.1 m skylight oculus compression ring framing the glowing buoyant gas envelope overhead!
static func _mezzanine_catwalk_and_skylight_dome(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var glass: RoomMesh = c.glass

	# Compute inner octagonal balustrade vertices inset by MEZZ_INSET along each edge's bisector.
	var inner_v: Array[Vector2] = []
	for i in OCT.size():
		var p := OCT[i]
		var to_c := Vector2(-p.x, CENTER_Z - p.y).normalized()
		inner_v.append(p + to_c * (MEZZ_INSET * 1.08))

	cove.surface(c.kit.cove_material())
	var cove_lin := ENAMEL_CREAM.srgb_to_linear()

	# 1. Wrought-brass mezzanine catwalk gallery running along walls 1..7 (keeps front screen wall 0 soaring open!).
	for ei in range(1, 8):
		var e := _edge(ei)
		var b_w: Basis = e["basis"]
		var n: Vector3 = e["n"]
		var a_out := OCT[ei]
		var b_out := OCT[(ei + 1) % OCT.size()]
		var a_in := inner_v[ei]
		var b_in := inner_v[(ei + 1) % OCT.size()]

		# Catwalk oak deck floor & hammered-copper underside soffit (y = MEZZ_Y - 0.08 .. MEZZ_Y).
		s.surface(c.tinted("wood"))
		s.colour = WALNUT_RICH.srgb_to_linear()
		s.face([Vector3(a_out.x, MEZZ_Y, a_out.y), Vector3(b_out.x, MEZZ_Y, b_out.y),
				Vector3(b_in.x, MEZZ_Y, b_in.y), Vector3(a_in.x, MEZZ_Y, a_in.y)], Vector3.UP)
		s.surface(c.tinted("iron"))
		s.colour = COPPER_DEEP.srgb_to_linear()
		s.face([Vector3(a_out.x, MEZZ_Y - 0.08, a_out.y), Vector3(a_in.x, MEZZ_Y - 0.08, a_in.y),
				Vector3(b_in.x, MEZZ_Y - 0.08, b_in.y), Vector3(b_out.x, MEZZ_Y - 0.08, b_out.y)], Vector3.DOWN)

		# Inner edge fascia, wrought-brass Art Nouveau balustrade, and walnut handrail (y = 4.65 .. 5.56 m).
		var p0 := Vector3(a_in.x, MEZZ_Y, a_in.y)
		var p1 := Vector3(b_in.x, MEZZ_Y, b_in.y)
		var blen := p0.distance_to(p1)
		var bdir := (p1 - p0) / blen
		var bn := bdir.cross(Vector3.UP).normalized()
		var bb := Basis(bdir, Vector3.UP, bn)
		var bmid := (p0 + p1) * 0.5

		u.surface(_metal_copper(c))
		u.colour = COPPER_HAMMERED.srgb_to_linear()
		u.box(bmid + Vector3(0.0, -0.02, 0.0), Vector3(blen + 0.06, 0.14, 0.06), bb)
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		# Top & bottom brass railing chords.
		u.box(bmid + Vector3(0.0, 0.06, 0.0), Vector3(blen + 0.06, 0.036, 0.05), bb)
		u.box(bmid + Vector3(0.0, 0.84, 0.0), Vector3(blen + 0.06, 0.032, 0.045), bb)
		# Walnut top handrail cap.
		s.surface(c.tinted("wood"))
		s.colour = WALNUT_RICH.srgb_to_linear()
		s.box(bmid + Vector3(0.0, 0.89, 0.0), Vector3(blen + 0.08, 0.055, 0.085), bb)
		# Repeating Art Nouveau brass stanchions and elliptical brass filigree scrollwork ovals!
		var panels := maxi(int(roundf(blen / 0.82)), 2)
		u.surface(_metal_brass(c))
		for k in panels + 1:
			var t := float(k) / float(panels)
			var sp := p0.lerp(p1, t)
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			Shapes.cylinder(u, sp + Vector3(0.0, 0.04, 0.0), 0.022 if (k == 0 or k == panels) else 0.014, 0.82, 8)
			if k < panels:
				var mp := p0.lerp(p1, (float(k) + 0.5) / float(panels))
				u.colour = BRASS_WARM.srgb_to_linear()
				Shapes.arch(u, mp + Vector3(0.0, 0.45, 0.0), 0.24, 0.275, 0.024, 12, bb, 0.0, TAU,
						["front", "back", "inner", "outer"])
				u.box(mp + Vector3(0.0, 0.45, 0.0), Vector3(0.018, 0.74, 0.022), bb)

		# Curved Art Nouveau brass cantilever support brackets aligned strictly with structural bay mullions
		# (NEVER hovering in open panoramic glass arches!).
		u.colour = BRASS_WARM.srgb_to_linear()
		var flen_e := float(e["len"])
		var bracket_us: Array[float] = []
		if ei == 2 or ei == 6:
			var inner_e := flen_e - 0.44
			bracket_us = [0.22 + inner_e / 3.0, 0.22 + inner_e * 2.0 / 3.0]
		elif ei == 4:
			bracket_us = [2.02, flen_e - 2.02]
		else:
			bracket_us = [flen_e * 0.5]
		for bu: float in bracket_us:
			var outer_p := _pt(e, bu, MEZZ_Y - 0.56, 0.06)
			var mid_p := _pt(e, bu, MEZZ_Y - 0.24, MEZZ_INSET * 0.46)
			var tip_p := _pt(e, bu, MEZZ_Y - 0.06, MEZZ_INSET * 0.90)
			Shapes.beam(u, outer_p, mid_p, Vector2(0.046, 0.056))
			Shapes.beam(u, mid_p, tip_p, Vector2(0.046, 0.056))
			# Tiny curved brass brace ring nestled cleanly in the structural bracket knee.
			Shapes.arch(u, _pt(e, bu, MEZZ_Y - 0.22, MEZZ_INSET * 0.24), 0.08, 0.105, 0.032, 10,
					Basis(e["n"] as Vector3, Vector3.UP, -(e["along"] as Vector3)), 0.0, TAU,
					["front", "back", "inner", "outer"])

		# Tucked indirect perimeter cove glow washing softly along the underside of the mezzanine & upper frieze!
		cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.82)
		var za := p0 + Vector3(0.0, -0.095, 0.0) - bn * 0.04
		var zb := p1 + Vector3(0.0, -0.095, 0.0) - bn * 0.04
		var zc := _pt(e, float(e["len"]) - 0.15, MEZZ_Y - 0.095, 0.08)
		var zd := _pt(e, 0.15, MEZZ_Y - 0.095, 0.08)
		cove.face([za, zb, zc, zd], Vector3.DOWN)

	# End-return wrought-brass guardrails closing off both ends of the mezzanine catwalk at V0 and V1.
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	for idx: int in [0, 1]:
		var pa := Vector3(OCT[idx].x, MEZZ_Y, OCT[idx].y)
		var pb := Vector3(inner_v[idx].x, MEZZ_Y, inner_v[idx].y)
		Shapes.beam(u, pa + Vector3(0.0, 0.86, 0.0), pb + Vector3(0.0, 0.86, 0.0), Vector2(0.05, 0.05))
		Shapes.beam(u, pa + Vector3(0.0, 0.45, 0.0), pb + Vector3(0.0, 0.45, 0.0), Vector2(0.03, 0.03))

	# 2. Eight monumental curved riveted copper-and-brass dome arch ribs sweeping up to the 7.1 m skylight oculus!
	var oculus_pts: Array[Vector3] = []
	var mid_pts: Array[Vector3] = []
	for i in OCT.size():
		var v := OCT[i]
		var ang := atan2(v.x, v.y - CENTER_Z)
		oculus_pts.append(Vector3(sin(ang) * OCULUS_R, OCULUS_Y, CENTER_Z + cos(ang) * OCULUS_R))
		var p_start := Vector3(v.x, WALL_TOP - 0.04, v.y)
		var p_end := oculus_pts[i]
		# Curved elliptic arch rib from (v, WALL_TOP) up to (oculus, OCULUS_Y).
		var segs := 8
		var prev := p_start
		for k in range(1, segs + 1):
			var t := float(k) / float(segs)
			# Elliptic quarter-arch curve: steep rise from walls, sweeping smoothly into the overhead oculus ring!
			var ease_r := 1.0 - cos(t * PI * 0.5)
			var ease_y := sin(t * PI * 0.5)
			var cur := Vector3(lerpf(p_start.x, p_end.x, ease_r), lerpf(p_start.y, p_end.y, ease_y),
					lerpf(p_start.z, p_end.z, ease_r))
			if k == 4:
				mid_pts.append(cur)
			u.surface(_metal_copper(c))
			u.colour = COPPER_HAMMERED.srgb_to_linear()
			Shapes.beam(u, prev, cur, Vector2(0.24, 0.28))
			u.surface(_metal_brass(c))
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			var inward := Vector3(-cur.x, -0.35, CENTER_Z - cur.z).normalized() * 0.15
			Shapes.beam(u, prev + inward, cur + inward, Vector2(0.11, 0.045))
			prev = cur

	# 3. Intermediate brass dome purlin ring + grand gilded skylight oculus compression ring + glowing ring cove!
	u.surface(_metal_brass(c))
	for i in OCT.size():
		var j := (i + 1) % OCT.size()
		# Intermediate dome purlin ring at mid-elevation (y ~ 6.6 m).
		u.colour = BRASS_WARM.srgb_to_linear()
		Shapes.beam(u, mid_pts[i], mid_pts[j], Vector2(0.11, 0.14))
		# Decorative curved brass Art Nouveau dome rib bisecting each skylight haunch.
		var base_mid := Vector3((OCT[i].x + OCT[j].x) * 0.5, WALL_TOP, (OCT[i].y + OCT[j].y) * 0.5)
		var mid_m := (mid_pts[i] + mid_pts[j]) * 0.5
		var top_m := (oculus_pts[i] + oculus_pts[j]) * 0.5
		Shapes.beam(u, base_mid, mid_m, Vector2(0.065, 0.08))
		Shapes.beam(u, mid_m, top_m, Vector2(0.065, 0.08))

		# Grand circular-feeling 8-sided riveted hammered-copper & brass skylight oculus compression ring!
		u.surface(_metal_copper(c))
		u.colour = COPPER_DEEP.srgb_to_linear()
		Shapes.beam(u, oculus_pts[i], oculus_pts[j], Vector2(0.26, 0.34))
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.beam(u, oculus_pts[i] + Vector3(0.0, -0.17, 0.0), oculus_pts[j] + Vector3(0.0, -0.17, 0.0),
				Vector2(0.29, 0.055))

		# Single-surface crystal skylight glass on the outer dome haunches (central 7.1 m oculus stays crystal-clear
		# open view straight up to the towering buoyant gas envelope, keeping blend_layers ultra-low!).
		var b0 := Vector3(OCT[i].x, WALL_TOP, OCT[i].y)
		var b1 := Vector3(OCT[j].x, WALL_TOP, OCT[j].y)
		var n_low := (b1 - b0).cross(mid_pts[i] - b0).normalized()
		if n_low.y > 0.0:
			n_low = -n_low
		glass.face([b0, b1, mid_pts[j], mid_pts[i]], n_low)
		glass.face([mid_pts[i], mid_pts[j], oculus_pts[j], oculus_pts[i]], n_low)

		# Glowing Art Nouveau cove wash band hugging the underside inner collar of the grand skylight oculus ring!
		cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.88)
		var oi := oculus_pts[i]
		var oj := oculus_pts[j]
		var in_i := Vector3(-oi.x, 0.0, CENTER_Z - oi.z).normalized()
		var in_j := Vector3(-oj.x, 0.0, CENTER_Z - oj.z).normalized()
		var p_a := oi + in_i * 0.16 + Vector3(0.0, -0.18, 0.0)
		var p_b := oj + in_j * 0.16 + Vector3(0.0, -0.18, 0.0)
		var p_c := oj + in_j * 0.16 + Vector3(0.0, 0.06, 0.0)
		var p_d := oi + in_i * 0.16 + Vector3(0.0, 0.06, 0.0)
		cove.face([p_a, p_b, p_c, p_d], (in_i + in_j).normalized())


## Ornate Art Nouveau brass-and-cream-enamel screen proscenium on the front wall (z = -7.35 .. -6.85 m): two-step oak &
## brass dais, cream-enamel fluted pilasters, sweeping curved botanical brass filigree arches, sunburst crest medallion,
## midnight-teal screen masking, and indirect proscenium cove troughs (`PieceCove`). Strictly clear of the 5.2 x 2.925 m
## screen aperture (`x in [-2.60, +2.60], y in [1.0875, 4.0125], z = -6.90`).
static func _screen_proscenium(c: Object) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 2.55, -6.9)))
	var sc_sz: Vector2 = scr.get("size", Vector2(5.2, 2.925))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var cz := sc_xf.origin.z
	var hw := sc_sz.x * 0.5
	var hh := sc_sz.y * 0.5
	var sc_bot := cy - hh # 1.0875
	var sc_top := cy + hh # 4.0125
	var fz := -7.35

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# 1. Two-step warm oak, walnut & brass proscenium dais (y = 0 .. 0.24 m, z = -7.35 .. -6.30 m).
	var dais_h := 0.24
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_RICH.srgb_to_linear()
	s.box(Vector3(cx, 0.06, -6.82), Vector3(7.20, 0.12, 1.06), Basis(), [RoomMesh.DOWN])
	s.colour = OAK_PALE.srgb_to_linear()
	s.box(Vector3(cx, 0.18, -6.92), Vector3(6.88, 0.12, 0.86), Basis(), [RoomMesh.DOWN])
	c.shapes.append(PhysicsShapes.box(Vector3(cx, dais_h * 0.5, -6.82), Vector3(7.20, dais_h, 1.06), Basis()))
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx, 0.118, -6.285), Vector3(7.22, 0.024, 0.024))
	u.box(Vector3(cx, 0.238, -6.485), Vector3(6.90, 0.026, 0.024))

	# 2. Solid back bulkhead & midnight-teal velvet masking strictly BEHIND the screen (z <= -6.96 m), plus warm
	#    cream-enamel side cove trough backing closing the recess cleanly between the brass screen bezel and piers!
	s.surface(c.tinted("fabric"))
	s.colour = TEAL_DEEP.srgb_to_linear()
	s.box(Vector3(cx, 2.55, -7.18), Vector3(7.30, 4.70, 0.34), Basis(), [RoomMesh.DOWN])
	s.surface(c.tinted("plaster"))
	s.colour = ENAMEL_WARM.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * (hw + 0.16), 2.55, -6.99), Vector3(0.30, 4.55, 0.06), Basis(), [RoomMesh.DOWN])

	# 3. Cream-enamel & hammered-copper Art Nouveau lower dado beneath the screen (y = 0.24 .. 1.04 m).
	var under_h := sc_bot - 0.05 - dais_h
	s.surface(c.tinted("plaster"))
	s.colour = ENAMEL_CREAM.srgb_to_linear()
	s.box(Vector3(cx, dais_h + under_h * 0.5, -6.98), Vector3(sc_sz.x + 0.14, under_h, 0.12))
	# Central hammered-copper & brass acoustic vent grille + flanking recessed cream cartouche frames.
	u.surface(_metal_copper(c))
	u.colour = COPPER_DEEP.srgb_to_linear()
	u.box(Vector3(cx, dais_h + under_h * 0.5, -6.91), Vector3(1.86, under_h - 0.22, 0.03))
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	for k in 9:
		var gx := cx - 0.80 + float(k) * 0.20
		u.box(Vector3(gx, dais_h + under_h * 0.5, -6.89), Vector3(0.024, under_h - 0.26, 0.018))
	for side: float in [-1.0, 1.0]:
		var px := cx + side * 1.76
		var py := dais_h + under_h * 0.5
		var pw := 1.24
		var ph := under_h - 0.24
		for sy: float in [-ph * 0.5, ph * 0.5]:
			u.box(Vector3(px, py + sy, -6.90), Vector3(pw, 0.024, 0.020))
		for sx: float in [-pw * 0.5, pw * 0.5]:
			u.box(Vector3(px + sx, py, -6.90), Vector3(0.024, ph, 0.020))

	# 4. Crisp burnished-brass inner screen surround bezel (strictly outside |x| >= 2.63, y <= 1.055 or y >= 4.045).
	var bt := 0.065
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * (hw + bt * 0.5 + 0.015), cy, cz - 0.02), Vector3(bt, sc_sz.y + bt * 2.0 + 0.03, 0.08))
	u.box(Vector3(cx, sc_bot - bt * 0.5 - 0.015, cz - 0.02), Vector3(sc_sz.x + bt * 2.0 + 0.03, bt, 0.08))
	u.box(Vector3(cx, sc_top + bt * 0.5 + 0.015, cz - 0.02), Vector3(sc_sz.x + bt * 2.0 + 0.03, bt, 0.08))

	# 5. Monumental flanking Art Nouveau cream-enamel, hammered-copper & brass proscenium piers (x = +-(2.76 .. 3.62)).
	for side: float in [-1.0, 1.0]:
		var px := cx + side * 3.24
		# Patinated hammered-copper lower pier pedestal (y = 0.24 .. 1.15).
		s.surface(c.tinted("iron"))
		s.colour = COPPER_HAMMERED.srgb_to_linear()
		s.box(Vector3(px, 0.70, -6.96), Vector3(0.76, 0.92, 0.44), Basis(), [RoomMesh.DOWN])
		# Sculpted cream-enamel fluted Art Nouveau pilaster rising cleanly to the upper arch (y = 1.15 .. 4.78).
		s.surface(c.tinted("plaster"))
		s.colour = ENAMEL_CREAM.srgb_to_linear()
		s.box(Vector3(px, 2.96, -7.00), Vector3(0.70, 3.64, 0.36))
		# Stepped gilded brass capital & riveted copper collar bands.
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		u.box(Vector3(px, 1.17, -6.94), Vector3(0.82, 0.065, 0.48))
		u.box(Vector3(px, 4.18, -6.94), Vector3(0.82, 0.075, 0.46))
		u.box(Vector3(px, 4.78, -6.92), Vector3(0.88, 0.12, 0.50))
		# Vertical fluted brass botanical ribs up each cream-enamel pilaster face.
		for dx: float in [-0.22, 0.0, 0.22]:
			Shapes.cylinder(u, Vector3(px + dx, 1.20, -6.80), 0.022, 2.96, 8)
		# Curved Art Nouveau botanical brass filigree whiplash arch springing from pier into the header spandrel!
		var arch_c := Vector3(cx + side * (hw - 0.12), sc_top + 0.10, -6.84)
		var a0 := 0.0 if side > 0.0 else PI * 0.5
		var a1 := PI * 0.5 if side > 0.0 else PI
		Shapes.arch(u, arch_c, 0.52, 0.62, 0.075, 10, Basis(), a0, a1)
		Shapes.arch(u, arch_c + Vector3(-side * 0.18, 0.08, 0.02), 0.34, 0.40, 0.045, 10, Basis(), a0, a1)
		# Physics box for each flanking proscenium pier.
		c.shapes.append(PhysicsShapes.box(Vector3(px, 2.50, -6.96), Vector3(0.76, 4.60, 0.44), Basis()))

	# 6. Ornate Art Nouveau cream-enamel header fascia & central gilded sunburst/orchid cartouche crest (y = 4.06 .. 4.90).
	s.surface(c.tinted("plaster"))
	s.colour = ENAMEL_CREAM.srgb_to_linear()
	s.box(Vector3(cx, 4.48, -7.02), Vector3(6.10, 0.72, 0.32))
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx, 4.84, -6.86), Vector3(7.30, 0.085, 0.14))
	u.box(Vector3(cx, 4.14, -6.86), Vector3(5.96, 0.055, 0.10))
	# Sweeping twin botanical Art Nouveau brass tendrils curving across the cream-enamel header frieze!
	for side: float in [-1.0, 1.0]:
		var prev := Vector3(cx + side * 0.42, 4.50, -6.83)
		for k in 8:
			var t := float(k + 1) / 8.0
			var nx := cx + side * lerpf(0.42, 2.75, t)
			var ny := 4.50 + 0.17 * sin(t * PI * 1.5)
			var nxt := Vector3(nx, ny, -6.83)
			Shapes.beam(u, prev, nxt, Vector2(0.036, 0.034))
			prev = nxt
	# Central Art Nouveau gilded brass sunburst & cream-enamel medallion crest crowning the proscenium!
	var crest := Vector3(cx, 4.54, -6.82)
	Shapes.arch(u, crest, 0.22, 0.30, 0.055, 20, Basis(), 0.0, TAU, ["front", "inner", "outer"])
	for k in 12:
		var ang := float(k) * TAU / 12.0
		var r_len := 0.44 if k % 2 == 0 else 0.34
		u.box(crest + Vector3(0.0, 0.0, 0.01), Vector3(0.022, r_len * 2.0, 0.020), Basis(Vector3.BACK, ang))
	u.surface(c.soft("plastic", true))
	u.colour = TEAL_VELVET.srgb_to_linear()
	Shapes.cylinder(u, crest + Vector3(0.0, 0.0, 0.012), 0.19, 0.035, 16, Basis(Vector3.RIGHT, PI * 0.5))
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.cylinder(u, crest + Vector3(0.0, 0.0, 0.036), 0.085, 0.025, 14, Basis(Vector3.RIGHT, PI * 0.5))

	# 7. Warm indirect proscenium cove lighting troughs (`PieceCove`: vertical flanks + overhead header arch wash!).
	cove.surface(c.kit.cove_material())
	var cove_lin := ENAMEL_CREAM.srgb_to_linear()
	cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.90)
	for side: float in [-1.0, 1.0]:
		var x_in := cx + side * (hw + 0.095)
		var x_out := cx + side * (hw + 0.285)
		var c_hi := Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.92)
		var c_lo := Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.36)
		var rows_v := [
			PackedVector3Array([Vector3(x_in, dais_h + 0.04, -6.955), Vector3(x_in, sc_top + 0.12, -6.955)]),
			PackedVector3Array([Vector3(x_out, dais_h + 0.04, -6.955), Vector3(x_out, sc_top + 0.12, -6.955)]),
		]
		var norms_v := [
			PackedVector3Array([Vector3.BACK, Vector3.BACK]),
			PackedVector3Array([Vector3.BACK, Vector3.BACK]),
		]
		var cols_v := [
			PackedColorArray([c_hi, c_hi]),
			PackedColorArray([c_lo, c_lo]),
		]
		if side < 0.0:
			rows_v.reverse()
			cols_v.reverse()
		cove.grid(rows_v, norms_v, cols_v)
	# Overhead proscenium header cove wash band illuminating the Art Nouveau brass tendrils!
	cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.86)
	cove.face([
		Vector3(cx - hw - 0.18, 4.18, -6.855),
		Vector3(cx + hw + 0.18, 4.18, -6.855),
		Vector3(cx + hw + 0.18, 4.78, -6.855),
		Vector3(cx - hw - 0.18, 4.78, -6.855),
	], Vector3.BACK)
	# Subtle warm lower dais step cove strip beneath the top step lip.
	cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.72)
	cove.face([
		Vector3(cx - 3.35, 0.13, -6.485),
		Vector3(cx + 3.35, 0.13, -6.485),
		Vector3(cx + 3.35, 0.22, -6.485),
		Vector3(cx - 3.35, 0.22, -6.485),
	], Vector3.BACK)


## Eight Art Nouveau brass gooseneck wall sconces with glowing frosted-opal tulip globes (`PieceLamps`, `bake_lamps: 8`)
## plus four delicate hanging tulip pendant lanterns under the mezzanine catwalk soffit.
static func _tulip_sconces_and_pendants(c: Object) -> void:
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	lit.surface(c.shade(LAMP_OPAL))
	lit.colour = Color.WHITE

	# 1. Two forward proscenium pier tulip sconces + 6 corner master pier sconces (8 lamps total = bake_lamps: 8!).
	var sconce_spots: Array = [
		[Vector3(-3.24, 2.62, -6.78), Vector3.BACK],
		[Vector3(3.24, 2.62, -6.78), Vector3.BACK],
	]
	for idx: int in [2, 3, 4, 5, 6, 7]:
		var v := OCT[idx]
		var to_c := Vector3(-v.x, 0.0, CENTER_Z - v.y).normalized()
		sconce_spots.append([Vector3(v.x, 2.68, v.y) + to_c * 0.30, to_c])

	for sc: Array in sconce_spots:
		var base: Vector3 = sc[0]
		var n: Vector3 = sc[1]
		var b := Basis(Vector3.UP.cross(n).normalized(), Vector3.UP, n)
		# Hammered-copper rosette wall plaque.
		u.surface(_metal_copper(c))
		u.colour = COPPER_BRIGHT.srgb_to_linear()
		Shapes.cylinder(u, base - n * 0.02, 0.115, 0.04, 12, b * Basis(Vector3.RIGHT, PI * 0.5))
		# S-curved Art Nouveau brass gooseneck arm cradling the inverted frosted-opal tulip globe!
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		var p1 := base + n * 0.14 + Vector3(0.0, 0.10, 0.0)
		var p2 := base + n * 0.26 + Vector3(0.0, 0.02, 0.0)
		var p3 := base + n * 0.28 + Vector3(0.0, -0.08, 0.0)
		Shapes.beam(u, base, p1, Vector2(0.020, 0.020))
		Shapes.beam(u, p1, p2, Vector2(0.018, 0.018))
		Shapes.beam(u, p2, p3, Vector2(0.016, 0.016))
		# Brass floral calyx cup.
		Shapes.lathe(u, [Vector2(0.018, 0.02), Vector2(0.048, -0.02), Vector2(0.068, -0.06)], p3, 10)
		# Lathed glowing frosted-opal tulip shade!
		Shapes.lathe(lit, [
			Vector2(0.056, -0.04), Vector2(0.095, -0.10), Vector2(0.115, -0.18),
			Vector2(0.104, -0.25), Vector2(0.072, -0.30), Vector2(0.0, -0.31)
		], p3, 12)
		# Stand-in & bake lamp for each of the 8 sconces!
		c.lamps.append([p3 + Vector3(0.0, -0.18, 0.0) + n * 0.12, LAMP_GOLD, 0.85])

	# 2. Four delicate hanging Art Nouveau frosted-opal tulip pendants under the mezzanine catwalk soffit.
	var pendants: Array[Vector3] = [
		Vector3(-5.55, MEZZ_Y - 0.08, -0.50),
		Vector3(5.55, MEZZ_Y - 0.08, -0.50),
		Vector3(-4.50, MEZZ_Y - 0.08, 3.85),
		Vector3(4.50, MEZZ_Y - 0.08, 3.85),
	]
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	for top_p: Vector3 in pendants:
		var drop := 0.56
		var cup := top_p - Vector3(0.0, drop, 0.0)
		Shapes.cylinder(u, cup, 0.012, drop, 6)
		Shapes.lathe(u, [Vector2(0.022, 0.04), Vector2(0.075, -0.01), Vector2(0.088, -0.05)], cup, 10)
		Shapes.lathe(lit, [
			Vector2(0.078, -0.04), Vector2(0.125, -0.11), Vector2(0.135, -0.20),
			Vector2(0.105, -0.28), Vector2(0.0, -0.32)
		], cup, 12)


## Two hanging geodesic glass & brass botanical terrariums packed with lush emerald ferns (port & starboard mid-forward
## bays, strictly clear of sight lines!) plus two matching hammered-copper aft corner botanical fern urns.
static func _hanging_terrariums_and_planters(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var rng := RandomNumberGenerator.new()
	rng.seed = 5200

	# 1. Two hanging glass botanical terrariums suspended cleanly from the mezzanine catwalk cornice!
	var terrariums: Array[Vector3] = [
		Vector3(-5.05, 2.08, -1.25), # Port mid-forward bay
		Vector3(5.05, 2.08, -1.25),  # Starboard mid-forward bay
	]
	for ti in terrariums.size():
		var ctr := terrariums[ti]
		var r := 0.54
		var bowl_top := ctr.y + 0.34
		var dome_base := bowl_top + 0.48
		var dome_top := dome_base + 0.44
		var hang_y := MEZZ_Y - 0.08

		# Sculpted hammered-copper & burnished-brass hanging chalice bowl + decorative finial drop underneath.
		u.surface(_metal_copper(c))
		u.colour = COPPER_HAMMERED.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.0, -0.22), Vector2(0.055, -0.14), Vector2(0.032, -0.06),
			Vector2(0.24, 0.0), Vector2(0.46, 0.14), Vector2(r, 0.32), Vector2(r - 0.04, 0.34)
		], ctr, 12)
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		# Upper & lower brass conservatory cage rings, crown ring, and hanging brass chain rod up to mezzanine.
		Shapes.arch(u, Vector3(ctr.x, bowl_top, ctr.z), r - 0.03, r + 0.025, 0.035, 16,
				Basis(Vector3.RIGHT, -PI * 0.5), 0.0, TAU, ["front", "back", "outer"])
		Shapes.arch(u, Vector3(ctr.x, dome_base, ctr.z), r - 0.02, r + 0.02, 0.028, 16,
				Basis(Vector3.RIGHT, -PI * 0.5), 0.0, TAU, ["front", "back", "outer"])
		Shapes.cylinder(u, Vector3(ctr.x, dome_top, ctr.z), 0.085, 0.05, 10)
		Shapes.cylinder(u, Vector3(ctr.x, dome_top + 0.04, ctr.z), 0.015, hang_y - dome_top - 0.04, 6)
		# Curved brass mezzanine crane bracket anchoring the chain cleanly back to the side wall!
		var wall_side := signf(ctr.x)
		Shapes.beam(u, Vector3(ctr.x, hang_y - 0.04, ctr.z), Vector3(wall_side * 6.38, hang_y - 0.04, ctr.z),
				Vector2(0.045, 0.045))
		Shapes.beam(u, Vector3(ctr.x + wall_side * 0.45, hang_y - 0.04, ctr.z),
				Vector3(wall_side * 6.38, hang_y - 0.65, ctr.z), Vector2(0.035, 0.035))

		# 10-sided ribbed brass geodesic conservatory cage + clean single-surface glass facets (`PieceGlass`)!
		var sides := 10
		for k in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var d0 := Vector3(sin(a0), 0.0, cos(a0))
			var d1 := Vector3(sin(a1), 0.0, cos(a1))
			var p0_lo := Vector3(ctr.x, bowl_top, ctr.z) + d0 * r
			var p1_lo := Vector3(ctr.x, bowl_top, ctr.z) + d1 * r
			var p0_md := Vector3(ctr.x, dome_base, ctr.z) + d0 * r
			var p1_md := Vector3(ctr.x, dome_base, ctr.z) + d1 * r
			var p0_hi := Vector3(ctr.x, dome_top, ctr.z) + d0 * 0.08
			var p1_hi := Vector3(ctr.x, dome_top, ctr.z) + d1 * 0.08
			# Slim brass conservatory rib.
			u.surface(_metal_brass(c))
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			Shapes.beam(u, p0_lo, p0_md, Vector2(0.016, 0.016))
			Shapes.beam(u, p0_md, p0_hi, Vector2(0.014, 0.014))
			# Single-surface crystal glass wall & conical dome facet (clean single surface, zero double-layer blur!).
			var n_side := (d0 + d1).normalized()
			glass.face([p0_lo, p1_lo, p1_md, p0_md], n_side)
			var n_dome := (n_side * 0.65 + Vector3.UP * 0.76).normalized()
			glass.face([p0_md, p1_md, p1_hi, p0_hi], n_dome)

		# Low dark botanical soil bed tucked neatly inside the copper chalice rim (leaving the glass dome wide open
		# for lush multi-layered emerald ferns!).
		s.surface(c.tinted("fabric"))
		s.colour = SOIL_DARK.srgb_to_linear()
		Shapes.cylinder(s, Vector3(ctr.x, bowl_top - 0.07, ctr.z), r - 0.05, 0.08, 12)

		# Lush multi-layered emerald, viridian & chartreuse fern canopy packing the glass conservatory dome!
		_fern_clump(u, c.soft("leaves", true), Vector3(ctr.x, bowl_top + 0.02, ctr.z), 0.50, 0.52, 16, rng)
		_fern_clump(u, c.soft("leaves", true), Vector3(ctr.x, bowl_top + 0.24, ctr.z), 0.38, 0.58, 12, rng)

	# 2. Two matching floor-standing hammered-copper botanical fern planters in the aft-port & aft-starboard corners!
	for side: float in [-1.0, 1.0]:
		var pc := Vector3(side * 4.95, 0.0, 3.25)
		u.surface(_metal_copper(c))
		u.colour = COPPER_HAMMERED.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.28, 0.0), Vector2(0.30, 0.06), Vector2(0.18, 0.16),
			Vector2(0.22, 0.36), Vector2(0.38, 0.62), Vector2(0.42, 0.78), Vector2(0.36, 0.80)
		], pc, 14)
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.arch(u, pc + Vector3(0.0, 0.78, 0.0), 0.38, 0.44, 0.036, 16, Basis(Vector3.RIGHT, -PI * 0.5),
				0.0, TAU, ["front", "back", "outer"])
		Shapes.arch(u, pc + Vector3(0.0, 0.36, 0.0), 0.21, 0.245, 0.028, 16, Basis(Vector3.RIGHT, -PI * 0.5),
				0.0, TAU, ["front", "back", "outer"])
		s.surface(c.tinted("fabric"))
		s.colour = SOIL_DARK.srgb_to_linear()
		Shapes.cylinder(s, pc + Vector3(0.0, 0.70, 0.0), 0.36, 0.08, 12)
		_fern_clump(u, c.soft("leaves", true), pc + Vector3(0.0, 0.76, 0.0), 0.62, 0.86, 12, rng)
		c.shapes.append(PhysicsShapes.box(pc + Vector3(0.0, 0.65, 0.0), Vector3(0.84, 1.30, 0.84), Basis()))


## Draws a lush multi-shade emerald botanical fern clump with arching curved fronds and paired leaflets.
static func _fern_clump(u: RoomMesh, leaf_mat: Material, origin: Vector3, reach: float, lift_max: float, fronds: int,
		rng: RandomNumberGenerator) -> void:
	u.surface(leaf_mat)
	var shades: Array[Color] = [FERN_DEEP.srgb_to_linear(), FERN_EMERALD.srgb_to_linear(), FERN_BRIGHT.srgb_to_linear()]
	for f in fronds:
		var a := TAU * float(f) / float(fronds) + rng.randf_range(-0.18, 0.18)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var side := dir.cross(Vector3.UP).normalized()
		var r_f := reach * rng.randf_range(0.72, 1.04)
		var lift := lift_max * rng.randf_range(0.58, 1.0)
		var prev := origin
		u.colour = shades[f % shades.size()]
		for i in range(1, 8):
			var t := float(i) / 7.0
			var p := origin + dir * (r_f * t) + Vector3.UP * (lift * sin(t * PI * 0.78))
			var along := p - prev
			var leaf_len := 0.145 * (1.0 - t * 0.52) * (reach / 0.45)
			for sgn: float in [-1.0, 1.0]:
				Shapes.leaf(u, p, side * sgn * leaf_len + along * 0.35, along.normalized() * leaf_len * 0.36,
						Vector3.UP)
			prev = p
		# Graceful terminal tip leaflet.
		Shapes.leaf(u, prev, (dir * 0.8 + Vector3.DOWN * 0.4).normalized() * 0.10, side * 0.032, Vector3.UP)


## Gleaming brass atmospheric barometer & spectrometer scientific console (aft-starboard gallery) with 3 backlit warm
## amber instrument dials (`PieceWindows`), vertical glass-and-brass mercury barometer column, coiled copper optical
## spectrometer prism assembly, plus a forward-starboard brass altitude binnacle pedestal!
static func _barometer_spectrometer_and_binnacle(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var gw: Array = c.glows.get("window", [])

	# --- 1. Aft-Starboard Brass Atmospheric Barometer & Spectrometer Console ---
	var con_pos := Vector3(4.35, 0.0, 4.35)
	# Facing inward toward the gondola centre (0, 0, -0.5).
	var to_c := (Vector3(0.0, 0.0, CENTER_Z) - con_pos).normalized()
	var cb := Basis(Vector3.UP.cross(to_c).normalized(), Vector3.UP, to_c)
	var xf := Transform3D(cb, con_pos)
	var cw := 1.72
	var ch := 0.94
	var cd := 0.64

	# Sculpted walnut & hammered-copper console desk carcass (static baked).
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_RICH.srgb_to_linear()
	s.box(xf * Vector3(0.0, ch - 0.03, 0.0), Vector3(cw, 0.06, cd), cb)
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(xf * Vector3(0.0, 0.24, 0.0), Vector3(cw - 0.18, 0.04, cd - 0.14), cb)
	s.surface(c.tinted("iron"))
	s.colour = COPPER_HAMMERED.srgb_to_linear()
	# Recessed hammered-copper lower instrument cabinet housing.
	s.box(xf * Vector3(0.0, 0.58, -0.02), Vector3(cw - 0.24, 0.62, cd - 0.14), cb)
	# Sloped brass-and-copper upper instrument console housing (y = 0.94 .. 1.54 m).
	s.colour = COPPER_DEEP.srgb_to_linear()
	s.box(xf * Vector3(0.0, 1.24, -0.14), Vector3(cw - 0.16, 0.58, 0.30), cb)

	# Four turned burnished-brass legs, fiddle rails, toggle levers & 3 backlit amber circular atmospheric dials!
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Shapes.cylinder(u, xf * Vector3(sx * (cw * 0.5 - 0.07), 0.0, sz * (cd * 0.5 - 0.07)), 0.026, ch - 0.05, 8)
	# Brass desk fiddle gallery rail.
	u.box(xf * Vector3(0.0, ch + 0.025, -cd * 0.5 + 0.02), Vector3(cw, 0.032, 0.018), cb)
	for sx: float in [-1.0, 1.0]:
		u.box(xf * Vector3(sx * (cw * 0.5 - 0.02), ch + 0.025, 0.0), Vector3(0.018, 0.032, cd), cb)

	# Three backlit warm amber atmospheric pressure & spectrometer dials (`PieceWindows`) framed by brass bezels!
	var dials: Array = [
		[Vector3(0.0, 1.28, 0.02), 0.145, 0.55],     # Central barometric altitude dial (52 km!)
		[Vector3(-0.38, 1.24, 0.02), 0.105, -0.70],  # Left sulfur-vapor spectrometer dial
		[Vector3(0.38, 1.24, 0.02), 0.105, 0.85],    # Right envelope buoyancy-pressure dial
	]
	for d: Array in dials:
		var dp: Vector3 = d[0]
		var dr := float(d[1])
		var needle_a := float(d[2])
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.arch(u, xf * dp, dr - 0.012, dr + 0.024, 0.042, 18, cb, 0.0, TAU, ["front", "inner", "outer"])
		# Backlit amber glass dial quad (`PieceWindows`).
		gw.append([xf * (dp + Vector3(0.0, 0.0, 0.008)), cb.x * (dr * 0.86), cb.y * (dr * 0.86), cb.z])
		# Crisp crimson indicator needle standing just proud of the glowing dial!
		u.surface(c.soft("plastic", true))
		u.colour = RUBY_DIAL.srgb_to_linear()
		u.box(xf * (dp + Vector3(0.0, 0.0, 0.020)), Vector3(0.012, dr * 1.35, 0.008), cb * Basis(Vector3.BACK, needle_a))
		# Small brass toggle switches below each gauge.
		u.surface(_metal_brass(c))
		u.colour = BRASS_WARM.srgb_to_linear()
		for ts: float in [-0.04, 0.04]:
			Shapes.cylinder(u, xf * (dp + Vector3(ts, -dr - 0.06, 0.01)), 0.010, 0.032, 6,
					cb * Basis(Vector3.RIGHT, PI * 0.5))

	# Vertical glass-and-brass Fortin mercury barometer column rising from the console's left wing (y = 0.94 .. 2.24 m)!
	var baro_p := Vector3(-0.68, ch, -0.14)
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.075, 0.0), Vector2(0.075, 0.08), Vector2(0.055, 0.14), Vector2(0.048, 0.24)],
			xf * baro_p, 12)
	for sx: float in [-0.048, 0.048]:
		Shapes.cylinder(u, xf * (baro_p + Vector3(sx, 0.12, 0.0)), 0.012, 1.12, 8)
	Shapes.lathe(u, [Vector2(0.062, 1.22), Vector2(0.062, 1.28), Vector2(0.018, 1.34), Vector2(0.0, 1.38)],
			xf * baro_p, 12)
	# Single-surface vertical glass barometer cylinder (`PieceGlass`) with gleaming mercury core inside!
	Shapes.cylinder(glass, xf * (baro_p + Vector3(0.0, 0.22, 0.0)), 0.030, 1.00, 10, Basis(), false)
	u.surface(_metal_copper(c))
	u.colour = Color(0.84, 0.86, 0.90).srgb_to_linear()
	Shapes.cylinder(u, xf * (baro_p + Vector3(0.0, 0.22, 0.0)), 0.012, 0.74, 8)

	# Brass optical atmospheric spectrometer collimator & coiled copper sampling tube on the right wing!
	var spec_p := Vector3(0.64, ch + 0.24, -0.10)
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.cylinder(u, xf * (spec_p - Vector3(0.0, 0.24, 0.0)), 0.042, 0.24, 10)
	Shapes.cylinder(u, xf * spec_p, 0.072, 0.14, 12)
	# Optical collimator tube aimed out toward the golden clouds + eyepiece tube.
	var tube_b := cb * Basis(Vector3.UP, 0.42) * Basis(Vector3.RIGHT, PI * 0.44)
	Shapes.cylinder(u, xf * (spec_p + Vector3(0.0, 0.07, 0.0)), 0.036, 0.38, 10, tube_b)
	Shapes.cylinder(u, xf * (spec_p + Vector3(0.0, 0.07, 0.0)), 0.026, 0.26, 10,
			cb * Basis(Vector3.UP, -0.65) * Basis(Vector3.RIGHT, PI * 0.52))
	# Folded parchment atmospheric altitude chart resting on the console desktop.
	u.surface(c.soft("plastic", true))
	u.colour = PARCHMENT.srgb_to_linear()
	u.box(xf * Vector3(-0.18, ch + 0.008, 0.14), Vector3(0.56, 0.008, 0.28), cb * Basis(Vector3.UP, -0.08))
	u.colour = RUBY_DIAL.srgb_to_linear()
	u.box(xf * Vector3(-0.18, ch + 0.014, 0.14), Vector3(0.42, 0.004, 0.012), cb * Basis(Vector3.UP, 0.12))

	c.shapes.append(PhysicsShapes.box(xf * Vector3(0.0, 0.82, 0.0), Vector3(cw, 1.64, cd), cb))

	# --- 2. Forward-Starboard Brass Altitude & Compass Binnacle Pedestal ---
	var bp := Vector3(4.95, 0.0, -3.45)
	var b_to_c := (Vector3(0.0, 0.0, CENTER_Z) - bp).normalized()
	var bb := Basis(Vector3.UP.cross(b_to_c).normalized(), Vector3.UP, b_to_c)
	u.surface(_metal_copper(c))
	u.colour = COPPER_HAMMERED.srgb_to_linear()
	Shapes.lathe(u, [
		Vector2(0.24, 0.0), Vector2(0.24, 0.06), Vector2(0.16, 0.14),
		Vector2(0.11, 0.28), Vector2(0.095, 0.86), Vector2(0.17, 0.96), Vector2(0.17, 1.06)
	], bp, 14)
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	# Domed brass binnacle hood, collar rings & twin port-crimson / starboard-emerald quadrantal corrector spheres!
	Shapes.dome(u, bp + Vector3(0.0, 1.06, 0.0), 0.165, 6, 14, false, 0.0, PI * 0.5)
	Shapes.arch(u, bp + Vector3(0.0, 0.96, 0.0), 0.15, 0.185, 0.032, 16, Basis(Vector3.RIGHT, -PI * 0.5),
			0.0, TAU, ["front", "back", "outer"])
	Shapes.arch(u, bp + Vector3(0.0, 0.07, 0.0), 0.22, 0.255, 0.036, 16, Basis(Vector3.RIGHT, -PI * 0.5),
			0.0, TAU, ["front", "back", "outer"])
	for sx: float in [-0.26, 0.26]:
		u.surface(_metal_brass(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.beam(u, bp + Vector3(0.0, 1.00, 0.0), bp + bb.x * sx + Vector3(0.0, 1.00, 0.0), Vector2(0.028, 0.028))
		u.surface(c.soft("plastic", true))
		u.colour = (RUBY_DIAL if sx < 0.0 else FERN_EMERALD).srgb_to_linear()
		Shapes.dome(u, bp + bb.x * sx + Vector3(0.0, 1.00, 0.0), 0.074, 5, 10, false, -PI * 0.5, PI * 0.5)
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	# Warm glowing backlit amber binnacle compass lens (`PieceWindows`).
	var lens_p := bp + Vector3(0.0, 1.12, 0.0) + b_to_c * 0.155
	gw.append([lens_p, bb.x * 0.075, Vector3.UP * 0.065, b_to_c])
	c.shapes.append(PhysicsShapes.box(bp + Vector3(0.0, 0.62, 0.0), Vector3(0.58, 1.24, 0.44), bb))

	c.glows["window"] = gw


## Riveted circular aft airlock hatch with spoked 6-spoke burnished-brass dogging handwheel, bolted brass flange ring,
## heavy hinges & glowing amber sight port, crowned by a working brass astronomical gondola clock (`PieceClock`)!
static func _aft_airlock_and_clock(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var gw: Array = c.glows.get("window", [])
	var bz := 6.32
	var b_aft := Basis(Vector3.UP, PI) # local +Z faces -Z (into the salon), local +X faces -X

	# 1. Heavy riveted patinated hammered-copper & bronze central aft airlock bulkhead bay (x = -1.66 .. +1.66).
	s.surface(c.tinted("iron"))
	s.colour = COPPER_DEEP.srgb_to_linear()
	s.box(Vector3(0.0, 2.34, bz), Vector3(3.32, 4.68, 0.24), Basis(), [RoomMesh.DOWN])
	# Flanking structural riveted copper-and-brass bulkhead pilasters.
	u.surface(_metal_brass(c))
	u.colour = BRASS_WARM.srgb_to_linear()
	for sx: float in [-1.62, 1.62]:
		u.box(Vector3(sx, 2.34, bz - 0.12), Vector3(0.14, 4.64, 0.14))
	# Horizontal brass transom beam separating the circular airlock from the astronomical clock tympanum above.
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	u.box(Vector3(0.0, 2.94, bz - 0.13), Vector3(3.26, 0.08, 0.12))

	# 2. Monumental circular riveted hammered-copper pressure airlock hatch (centre = (0, 1.48, 6.18), r = 1.06 m)!
	var hc := Vector3(0.0, 1.48, bz - 0.14)
	# Heavy bolted burnished-brass pressure frame collar (r = 1.00 .. 1.22 m) studded with 16 hex pressure bolts.
	u.surface(_metal_brass(c))
	u.colour = BRASS_WARM.srgb_to_linear()
	Shapes.arch(u, hc, 0.98, 1.22, 0.14, 28, b_aft, 0.0, TAU, ["front", "inner", "outer"])
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.arch(u, hc + Vector3(0.0, 0.0, -0.05), 0.96, 1.04, 0.08, 28, b_aft, 0.0, TAU, ["front", "inner", "outer"])
	var bolt_b := b_aft * Basis(Vector3.RIGHT, PI * 0.5)
	for k in 16:
		var ang := float(k) * TAU / 16.0
		var bp := hc + Vector3(cos(ang) * 1.12, sin(ang) * 1.12, -0.075)
		Shapes.cylinder(u, bp, 0.026, 0.026, 6, bolt_b)

	# Gently dished hammered-copper circular airlock door disc + embossed concentric stiffening ring + 12 copper rivets.
	u.surface(_metal_copper(c))
	u.colour = COPPER_HAMMERED.srgb_to_linear()
	Shapes.lathe(u, [
		Vector2(0.99, 0.0), Vector2(0.95, 0.055), Vector2(0.70, 0.105),
		Vector2(0.35, 0.130), Vector2(0.0, 0.138)
	], hc + Vector3(0.0, 0.0, -0.01), 24, bolt_b)
	u.surface(_metal_brass(c))
	u.colour = BRASS_WARM.srgb_to_linear()
	Shapes.arch(u, hc + Vector3(0.0, 0.0, -0.105), 0.66, 0.72, 0.032, 24, b_aft, 0.0, TAU, ["front", "inner", "outer"])
	for k in 12:
		var ang := float(k) * TAU / 12.0
		u.box(hc + Vector3(cos(ang) * 0.84, sin(ang) * 0.84, -0.095), Vector3(0.028, 0.028, 0.022))

	# Heavy twin cast-brass door pintle hinges (left) & dogging clamps (right).
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	for hy: float in [-0.46, 0.46]:
		u.box(hc + Vector3(-1.12, hy, -0.09), Vector3(0.28, 0.12, 0.12))
		Shapes.cylinder(u, hc + Vector3(-1.22, hy - 0.10, -0.12), 0.036, 0.20, 8)
		u.box(hc + Vector3(1.10, hy, -0.09), Vector3(0.20, 0.09, 0.10))

	# Central 6-spoke burnished-brass dogging handwheel (r = 0.36 m) standing proud at z = 5.90 m!
	var wc := hc + Vector3(0.0, 0.0, -0.28)
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.cylinder(u, hc + Vector3(0.0, 0.0, -0.12), 0.056, 0.20, 12, bolt_b)
	Shapes.cylinder(u, wc + Vector3(0.0, 0.0, -0.045), 0.086, 0.08, 12, bolt_b)
	Shapes.arch(u, wc, 0.30, 0.365, 0.044, 24, b_aft, 0.0, TAU, ["front", "back", "inner", "outer"])
	for sp in 6:
		var ang := float(sp) * TAU / 6.0
		var tip := wc + Vector3(cos(ang) * 0.33, sin(ang) * 0.33, 0.0)
		Shapes.beam(u, wc, tip, Vector2(0.032, 0.032))

	# Small circular backlit amber airlock equalizer viewport lens in the upper-right quadrant (`PieceWindows`).
	var vp := hc + Vector3(0.42, 0.42, -0.12)
	Shapes.arch(u, vp, 0.11, 0.145, 0.038, 16, b_aft, 0.0, TAU, ["front", "inner", "outer"])
	gw.append([vp + Vector3(0.0, 0.0, -0.012), Vector3(-0.105, 0.0, 0.0), Vector3(0.0, 0.105, 0.0), Vector3.FORWARD])
	c.glows["window"] = gw

	# 3. Working brass astronomical gondola clock (`PieceClock`) crowning the aft arch at (0.0, 3.74, 6.14)!
	var clk_c := Vector3(0.0, 3.74, bz - 0.16)
	var clk_r := 0.42
	# Cream-enamel arched tympanum backplate behind the astronomical clock.
	s.surface(c.tinted("plaster"))
	s.colour = ENAMEL_CREAM.srgb_to_linear()
	s.box(Vector3(0.0, 3.74, bz - 0.12), Vector3(2.86, 1.48, 0.06))
	# Ornate Art Nouveau burnished-brass astronomical bezel ring, 12 hour bosses, sweeping wings & celestial crescent!
	u.surface(_metal_brass(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.arch(u, clk_c + Vector3(0.0, 0.0, -0.03), clk_r, clk_r + 0.085, 0.075, 28, b_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Outer meridian armillary ring arching around the clock!
	u.colour = BRASS_WARM.srgb_to_linear()
	Shapes.arch(u, clk_c + Vector3(0.0, 0.0, -0.02), clk_r + 0.15, clk_r + 0.19, 0.036, 28, b_aft, 0.0, TAU,
			["front", "inner", "outer"])
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	for k in 12:
		var ang := float(k) * TAU / 12.0
		var big := (k % 3 == 0)
		var mp := clk_c + Vector3(sin(ang) * (clk_r + 0.042), cos(ang) * (clk_r + 0.042), -0.072)
		u.box(mp, Vector3(0.026 if big else 0.016, 0.058 if big else 0.034, 0.020), Basis(Vector3.BACK, -ang))
	# Twin Art Nouveau sweeping brass filigree wing scrolls flanking the astronomical clock!
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var w_len := 0.68 - 0.15 * float(k)
			var wy := clk_c.y + (1.0 - float(k)) * 0.12
			u.box(Vector3(side * (clk_r + 0.22 + w_len * 0.5), wy, clk_c.z - 0.03), Vector3(w_len, 0.026, 0.026))
	# Register live working `PieceClock` face (facing -Z into the salon, UV right = -X, UV up = +Y).
	c.clocks.append([clk_c + Vector3(0.0, 0.0, -0.062), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# Physics box for aft airlock bulkhead & hatch protrusion.
	c.shapes.append(PhysicsShapes.box(Vector3(0.0, 2.34, bz - 0.06), Vector3(3.32, 4.68, 0.42), Basis()))
