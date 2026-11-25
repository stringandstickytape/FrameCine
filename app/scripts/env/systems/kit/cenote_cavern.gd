extends RefCounted

## Cenote cavern kit (docs/environments/rooms/cenote_cavern.md): an underground Yucatan limestone karst sinkhole and
## bioluminescent crystal grotto cinema (Other worlds). Everything is procedurally sculpted from smooth per-vertex-shaded
## karst sheets, stepped travertine ledges, organic flowstone formations, faceted mineral prisms and tropical foliage;
## zero people, zero trademarks, CC0 library materials only, zero live lights.
##
## Pieces (pieces.gd dispatches here; built over domestic shell "kit" + cushion seats):
##   cenote_shell   sculpted tiered limestone viewing island & mossy ledges, rounded river-stone steps into the pool,
##                  weathered timber boardwalk bridge to a natural arched rear grotto cave portal, towering 20-ring
##                  organic per-vertex-shaded karst limestone cavern dome with wall-anchored rocky strata ledges,
##                  multi-spired flowstone stalagmites, clustered karst stalactites, mossy water islets, wide jagged
##                  overhead jungle oculus framed by gnarled strangler-fig aerial roots, cascading liana vines & lush
##                  silhouetted tropical fern fronds, twin carved dark-basalt screen pylons anchored in volcanic reef
##                  boulders with aged-bronze clasps, 8 warm hanging wrought-bronze cave lanterns (PieceLamps + bake
##                  lamps), and 14 firmly-anchored glowing faceted mineral crystal clusters (PieceCove, live-bound to
##                  room setting `crystals`)
##   cenote_water   custom c.halls builder (CenoteWaterHall): wide mirror-rippling emerald-turquoise underground cenote
##                  pool (CenotePool, opaque env_world_water.gdshader, zero blend cost) + two parallel silky-soft
##                  volumetric moonlight/sunlight shafts descending cleanly from the overhead jungle oculus into the
##                  pool (CenoteShaft, env_world_shaft.gdshader, group env_see_through), scaled by Motion and live-
##                  reactive to room settings `time` and `crystals` and playback state

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const WATER_SHADER := preload("res://shaders/env_world_water.gdshader")
const SHAFT_SHADER := preload("res://shaders/env_world_shaft.gdshader")

const PIECES: Array[String] = ["cenote_shell", "cenote_water"]

## Key cavern coordinates (metres, viewer's own seat at origin facing -Z).
const WATER_Y := -0.42
const CAVERN_CX := 0.0
const CAVERN_CZ := -1.6
const OCULUS_CX := 0.0
const OCULUS_CZ := -2.2
const OCULUS_Y := 13.4
const ISLAND_CZ := 0.65

## Palette (sRGB): Yucatan karst limestone strata, wet basalt, weathered boardwalk timber, bronze, tropical foliage.
const LIME_CREAM := Color(0.66, 0.60, 0.50)
const LIME_OCHRE := Color(0.54, 0.47, 0.37)
const LIME_WARM := Color(0.60, 0.53, 0.42)
const LIME_GREY := Color(0.41, 0.42, 0.39)
const LIME_UMBER := Color(0.35, 0.31, 0.26)
const LIME_WET := Color(0.22, 0.27, 0.26)
const LIME_DARK := Color(0.15, 0.19, 0.19)
const LIME_MOSSY := Color(0.24, 0.33, 0.20)
const BASALT_DARK := Color(0.15, 0.18, 0.20)
const BASALT_MID := Color(0.23, 0.26, 0.29)
const BASALT_TRIM := Color(0.32, 0.36, 0.38)
const TIMBER_WARM := Color(0.37, 0.24, 0.14)
const TIMBER_WEATHERED := Color(0.27, 0.19, 0.13)
const TIMBER_WET := Color(0.18, 0.13, 0.09)
const ROOT_BARK := Color(0.25, 0.17, 0.11)
const IRON_DARK := Color(0.11, 0.12, 0.13)
const BRONZE_AGED := Color(0.76, 0.56, 0.26)
const BRONZE_WARM := Color(0.88, 0.68, 0.34)
const LANTERN_AMBER := Color(1.0, 0.78, 0.46)
const MOSS_DEEP := Color(0.14, 0.32, 0.13)
const MOSS_BRIGHT := Color(0.24, 0.46, 0.18)
const FERN_LUSH := Color(0.18, 0.42, 0.15)
const FERN_DARK := Color(0.10, 0.26, 0.10)
const VINE_GREEN := Color(0.16, 0.37, 0.14)
const CRYSTAL_QUARTZ := Color(0.84, 0.94, 0.98)

## Two parallel, physically aligned volumetric moonlight/sunlight columns descending cleanly from the overhead jungle
## oculus into the turquoise pool (leaving the center of the oculus, Moon and screen sight line crystal clear!):
## [top_center, bottom_center, top_radius, bottom_radius, alpha_weight].
## Parallel angle matches Moon direction (-0.12, -0.92, -0.35 -> slanted gently down-left-forward from oculus!).
const SHAFTS: Array = [
	# Hero left-lagoon moonlight shaft pouring from the western oculus rim onto the turquoise pool beside the island.
	[Vector3(-2.65, 13.75, -3.45), Vector3(-4.85, -0.45, -5.85), 1.55, 2.55, 1.00],
	# Soft companion aft shaft descending parallel behind the seats onto the rear lagoon & timber boardwalk bridge.
	[Vector3(1.85, 13.75, 1.45), Vector3(-0.35, -0.45, 6.25), 1.35, 2.25, 0.78],
]

## Four mossy limestone islets emerging from the emerald cenote water: [pos_xz, radius, top_y].
const ISLETS: Array = [
	[Vector2(-5.7, -2.5), 1.25, 0.26],
	[Vector2(6.0, -1.8), 1.32, 0.34],
	[Vector2(-5.1, 4.4), 1.18, 0.22],
	[Vector2(5.4, 4.0), 1.24, 0.28],
]

## Six wall-anchored terraced karst cliff buttresses rising straight out of the lagoon along the cavern walls:
## [theta_deg, top_y, width, reach_in].
const WALL_LEDGES: Array = [
	[210.0, 2.35, 4.4, 2.35],
	[332.0, 2.55, 4.5, 2.35],
	[182.0, 3.65, 5.0, 2.45],
	[356.0, 3.45, 4.8, 2.40],
	[142.0, 2.45, 4.6, 2.25],
	[38.0, 2.65, 4.6, 2.25],
]


## Animated reflective emerald-turquoise cenote pool + silky volumetric oculus shafts (c.halls).
class CenoteWaterHall:
	var kit: Node
	var pool_node: MeshInstance3D
	var shaft_node: MeshInstance3D
	var pool_m: ShaderMaterial
	var shaft_m: ShaderMaterial
	var sky: Node
	var _clock := 0.0
	var _shaft_level := 0.26
	var _time_key := ""
	var _crystals_key := ""
	var _playing_key := -1

	func finish(k: Node) -> void:
		kit = k
		for s: Node in k.host.systems_of_kind("sky"):
			if s.has_method("sky_light"):
				sky = s
				break
		_build_pool(k)
		_build_shafts(k)
		tick(0.0)

	func _build_pool(k: Node) -> void:
		pool_m = ShaderMaterial.new()
		pool_m.shader = WATER_SHADER
		pool_m.set_shader_parameter("caustic_map", Procedural.caustic_map())
		pool_m.set_shader_parameter("house_reference", float(k.room.get("ambient_level")))
		pool_m.set_shader_parameter("ripple_scale", 2.35)
		pool_m.set_shader_parameter("spill_strength", 0.92)
		pool_m.set_shader_parameter("glint_dir", Vector3(-0.15, 0.92, -0.36).normalized())
		pool_m.set_shader_parameter("ambient_floor", 0.46)

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		const RADIAL := 22
		const SEGS := 48
		const MAX_R := 16.8
		var rings: Array = []
		var cols: Array = []
		for ri in RADIAL + 1:
			var t := float(ri) / float(RADIAL)
			var r := MAX_R * pow(t, 1.15)
			var ring := PackedVector3Array()
			var col_row := PackedColorArray()
			for si in SEGS + 1:
				var ang := TAU * float(si % SEGS) / float(SEGS)
				var px := CAVERN_CX + cos(ang) * r
				var pz := CAVERN_CZ + sin(ang) * r
				ring.append(Vector3(px, WATER_Y, pz))
				col_row.append(_pool_vertex_color(px, pz))
			rings.append(ring)
			cols.append(col_row)

		for ri in RADIAL:
			var r0: PackedVector3Array = rings[ri]
			var r1: PackedVector3Array = rings[ri + 1]
			var c0: PackedColorArray = cols[ri]
			var c1: PackedColorArray = cols[ri + 1]
			for si in SEGS:
				_st_tri(st, r0[si], r0[si + 1], r1[si + 1], Vector3.UP, c0[si], c0[si + 1], c1[si + 1])
				_st_tri(st, r0[si], r1[si + 1], r1[si], Vector3.UP, c0[si], c1[si + 1], c1[si])

		var mesh := st.commit()
		mesh.surface_set_material(0, pool_m)
		pool_node = MeshInstance3D.new()
		pool_node.name = "CenotePool"
		pool_node.mesh = mesh
		pool_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pool_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		k.own(pool_node)

	## Vertex COLOR.r = shallow emerald-turquoise shelf glow around island, steps, basalt reef, islets & cavern shore;
	## Vertex COLOR.g = radiant aquamarine pool bloom where the volumetric shafts strike the water!
	static func _pool_vertex_color(px: float, pz: float) -> Color:
		var ie := Vector2(px / 4.0, (pz - ISLAND_CZ) / 4.85).length()
		var shallow := clampf(1.0 - smoothstep(0.80, 1.62, ie), 0.0, 1.0)
		var sd := Vector2(maxf(absf(px) - 4.5, 0.0), maxf(absf(pz + 11.0) - 1.2, 0.0)).length()
		shallow = maxf(shallow, (1.0 - smoothstep(0.0, 2.4, sd)) * 0.94)
		for isl: Array in ISLETS:
			var ic: Vector2 = isl[0]
			var ir: float = isl[1]
			var d := Vector2(px - ic.x, pz - ic.y).length()
			shallow = maxf(shallow, (1.0 - smoothstep(ir * 0.75, ir + 1.55, d)) * 0.88)
		if pz > 3.5 and pz < 11.8:
			var bd := maxf(absf(px) - 1.20, 0.0)
			shallow = maxf(shallow, (1.0 - smoothstep(0.0, 1.7, bd)) * 0.58)
		var cr := Vector2((px - CAVERN_CX) / 13.6, (pz - CAVERN_CZ) / 14.2).length()
		shallow = maxf(shallow, smoothstep(0.84, 1.04, cr) * 0.42)

		var glow := 0.0
		for sh: Array in SHAFTS:
			var bot: Vector3 = sh[1]
			var rad: float = float(sh[3]) * 1.45
			var weight: float = float(sh[4])
			var d := Vector2(px - bot.x, pz - bot.z).length()
			var g := exp(-(d * d) / (rad * rad * 0.68)) * weight
			glow = maxf(glow, g)
		# Gentle sunlit/moonlit ripple highlight directly across the front lagoon between island and screen.
		var front_d := Vector2((px + 0.8) / 4.2, (pz + 6.4) / 3.0).length()
		glow = maxf(glow, exp(-front_d * front_d * 0.8) * 0.45)
		return Color(clampf(shallow, 0.0, 1.0), clampf(glow, 0.0, 1.0), 0.0, 1.0)

	func _build_shafts(k: Node) -> void:
		shaft_m = ShaderMaterial.new()
		shaft_m.shader = SHAFT_SHADER
		shaft_m.set_shader_parameter("noise_map", SkySys.noise_texture())
		shaft_m.set_shader_parameter("edge_softness", 2.95)
		shaft_m.set_shader_parameter("wisp_strength", 0.65)

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		const SEGS := 24
		const RINGS := 8
		for sh: Array in SHAFTS:
			var top_c: Vector3 = sh[0]
			var bot_c: Vector3 = sh[1]
			var r_top: float = float(sh[2])
			var r_bot: float = float(sh[3])
			var alpha: float = float(sh[4])
			var axis := (bot_c - top_c).normalized()
			var ref := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var bx := axis.cross(ref).normalized()
			var bz := bx.cross(axis).normalized()
			var col := Color(1.0, 1.0, 1.0, alpha)

			var grid_p: Array = []
			var grid_n: Array = []
			var grid_uv: Array = []
			for ri in RINGS + 1:
				var v := float(ri) / float(RINGS)
				var ctr := top_c.lerp(bot_c, v)
				var rad := lerpf(r_top, r_bot, v)
				var row_p := PackedVector3Array()
				var row_n := PackedVector3Array()
				var row_uv := PackedVector2Array()
				for si in SEGS + 1:
					var u := float(si) / float(SEGS)
					var ang := u * TAU
					var radial := (bx * cos(ang) + bz * sin(ang)).normalized()
					row_p.append(ctr + radial * rad)
					row_n.append(radial)
					row_uv.append(Vector2(u, v))
				grid_p.append(row_p)
				grid_n.append(row_n)
				grid_uv.append(row_uv)

			for ri in RINGS:
				var p0: PackedVector3Array = grid_p[ri]
				var p1: PackedVector3Array = grid_p[ri + 1]
				var n0: PackedVector3Array = grid_n[ri]
				var n1: PackedVector3Array = grid_n[ri + 1]
				var u0: PackedVector2Array = grid_uv[ri]
				var u1: PackedVector2Array = grid_uv[ri + 1]
				for si in SEGS:
					st.set_color(col)
					st.set_normal(n0[si])
					st.set_uv(u0[si])
					st.add_vertex(p0[si])
					st.set_normal(n0[si + 1])
					st.set_uv(u0[si + 1])
					st.add_vertex(p0[si + 1])
					st.set_normal(n1[si + 1])
					st.set_uv(u1[si + 1])
					st.add_vertex(p1[si + 1])

					st.set_normal(n0[si])
					st.set_uv(u0[si])
					st.add_vertex(p0[si])
					st.set_normal(n1[si + 1])
					st.set_uv(u1[si + 1])
					st.add_vertex(p1[si + 1])
					st.set_normal(n1[si])
					st.set_uv(u1[si])
					st.add_vertex(p1[si])

		var mesh := st.commit()
		mesh.surface_set_material(0, shaft_m)
		shaft_node = MeshInstance3D.new()
		shaft_node.name = "CenoteShaft"
		shaft_node.mesh = mesh
		shaft_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shaft_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		shaft_node.add_to_group("env_see_through")
		k.own(shaft_node)

	func tick(delta: float) -> void:
		if pool_m == null or shaft_m == null or kit == null or kit.host == null:
			return
		var motion := 1.0
		var m_val: Variant = kit.host.setting("motion")
		if m_val != null:
			motion = clampf(float(m_val), 0.0, 1.0)
		_clock += maxf(delta, 0.0) * motion
		pool_m.set_shader_parameter("clock", _clock)
		shaft_m.set_shader_parameter("clock", _clock)

		var t_val: Variant = kit.host.setting("time")
		var time_mode := str(t_val) if t_val != null else "moonlight"
		var c_val: Variant = kit.host.setting("crystals")
		var cryst_mode := str(c_val) if c_val != null else "cyan"
		var playing := false
		if kit.host.get("timeline") != null:
			playing = str(kit.host.timeline.state) in ["starting", "playing", "credits"]
		var play_i := 1 if playing else 0

		# Ethereal, translucent volumetric light columns (subtle additive mist, never milky or blinding!).
		var want_shaft := 0.25
		var shaft_col := Color(0.56, 0.90, 0.98)
		match time_mode:
			"dusk":
				want_shaft = 0.13 if playing else 0.30
				shaft_col = Color(0.98, 0.84, 0.54)
			"starlight":
				want_shaft = 0.04 if playing else 0.08
				shaft_col = Color(0.36, 0.60, 0.90)
			_:
				want_shaft = 0.12 if playing else 0.25
				shaft_col = Color(0.52, 0.88, 0.98)

		if delta <= 0.0 or _time_key == "":
			_shaft_level = want_shaft
		else:
			_shaft_level = move_toward(_shaft_level, want_shaft, delta * 0.12)
		shaft_m.set_shader_parameter("shaft_level", _shaft_level)
		shaft_m.set_shader_parameter("shaft_colour", shaft_col)

		if time_mode != _time_key or cryst_mode != _crystals_key or play_i != _playing_key:
			_time_key = time_mode
			_crystals_key = cryst_mode
			_playing_key = play_i
			_apply_water_palette(time_mode, cryst_mode, playing)

		if pool_node != null and is_instance_valid(pool_node):
			pool_node.set_meta("cenote_clock", _clock)
			pool_node.set_meta("cenote_time", time_mode)
		if shaft_node != null and is_instance_valid(shaft_node):
			shaft_node.set_meta("cenote_shaft_level", _shaft_level)

	func _apply_water_palette(time_mode: String, cryst_mode: String, playing: bool) -> void:
		var deep := Color(0.012, 0.14, 0.19)
		var shallow := Color(0.06, 0.48, 0.49)
		var sky_c := Color(0.14, 0.32, 0.42)
		var caust := Color(0.34, 0.96, 0.92)
		var glint := Color(0.80, 0.96, 1.0)
		var caust_lvl := 1.08
		var glint_lvl := 0.68
		var floor_amb := 0.48
		match time_mode:
			"dusk":
				deep = Color(0.018, 0.16, 0.17)
				shallow = Color(0.09, 0.50, 0.40)
				sky_c = Color(0.34, 0.32, 0.26)
				caust = Color(0.46, 0.98, 0.78)
				glint = Color(1.0, 0.86, 0.56)
				caust_lvl = 1.15
				glint_lvl = 0.76
				floor_amb = 0.52
			"starlight":
				deep = Color(0.008, 0.08, 0.14)
				shallow = Color(0.04, 0.28, 0.36)
				sky_c = Color(0.08, 0.14, 0.26)
				caust = Color(0.24, 0.78, 0.90)
				glint = Color(0.64, 0.80, 1.0)
				caust_lvl = 0.72
				glint_lvl = 0.40
				floor_amb = 0.36
		if cryst_mode == "amethyst":
			caust = caust.lerp(Color(0.78, 0.42, 0.98), 0.52)
			shallow = shallow.lerp(Color(0.24, 0.22, 0.50), 0.32)
		elif cryst_mode == "lanterns":
			caust = caust.lerp(Color(0.92, 0.74, 0.44), 0.24)
		if playing:
			floor_amb *= 0.66
			glint_lvl *= 0.65
		pool_m.set_shader_parameter("deep_colour", deep)
		pool_m.set_shader_parameter("shallow_colour", shallow)
		pool_m.set_shader_parameter("sky_colour", sky_c)
		pool_m.set_shader_parameter("caustic_colour", caust)
		pool_m.set_shader_parameter("caustic_level", caust_lvl)
		pool_m.set_shader_parameter("glint_colour", glint)
		pool_m.set_shader_parameter("glint_level", glint_lvl)
		pool_m.set_shader_parameter("ambient_floor", floor_amb)

	static func _st_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, c0: Color, c1: Color,
			c2: Color) -> void:
		var cw := (p2 - p0).cross(p1 - p0).dot(n) >= 0.0
		st.set_normal(n)
		if cw:
			st.set_color(c0)
			st.add_vertex(p0)
			st.set_color(c1)
			st.add_vertex(p1)
			st.set_color(c2)
			st.add_vertex(p2)
		else:
			st.set_color(c0)
			st.add_vertex(p0)
			st.set_color(c2)
			st.add_vertex(p2)
			st.set_color(c1)
			st.add_vertex(p1)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"cenote_shell":
			_shell(c)
		"cenote_water":
			c.halls.append(CenoteWaterHall.new())


# --- Cenote cavern shell ----------------------------------------------------------------------------------------------

static func _shell(c: Object) -> void:
	# Coarser lightmap texel for this monumental ~28 m karst cavern so its atlas stays compact and fast to bake.
	c.s.texel = 0.24
	var rng := RandomNumberGenerator.new()
	rng.seed = 4208

	_viewing_island_and_steps(c, rng)
	_boardwalk_and_rear_landing(c, rng)
	_karst_cavern_dome(c, rng)
	var ledge_tops := _rock_shelves_islets_and_formations(c, rng)
	_oculus_roots_vines_and_ferns(c, rng)
	_screen_basalt_pylons(c, rng)
	_cave_lanterns(c)
	_mineral_crystal_clusters(c, rng, ledge_tops)

	# One hidden downward moonlight spot from the overhead jungle oculus for lightmap baking only.
	c.spots.append([Vector3(-2.4, 13.8, -3.5), Vector3(-4.2, -0.4, -5.6), Color(0.68, 0.90, 1.0), 3.2, 22.0, 38.0])

	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE
	c.cove.colour = Color.WHITE


# --- Organic karst surface maths --------------------------------------------------------------------------------------

static func _island_outline(ang: float, rx: float, rz: float, amp: float) -> Vector2:
	var bump := 1.0 + amp * (0.45 * sin(ang * 3.0 + 0.6) + 0.35 * cos(ang * 5.0 - 0.8) + 0.20 * sin(ang * 7.0 + 1.9))
	return Vector2(cos(ang) * rx * bump, ISLAND_CZ + sin(ang) * rz * bump)


static func _oculus_radius(ang: float) -> float:
	return 5.15 + 0.48 * sin(ang * 3.0 + 0.5) + 0.30 * cos(ang * 5.0 - 1.0) + 0.18 * sin(ang * 7.0 + 2.1)


## Returns a point on the 20-ring organic karst limestone cavern dome for ring fraction v (0 = submerged base y=-1.6,
## 1 = jagged jungle oculus rim y=13.4) and angle theta around the cavern.
static func _cavern_pt(theta: float, v: float) -> Vector3:
	var y := lerpf(-1.6, OCULUS_Y, v)
	var bulge := sin(clampf(v * 1.15, 0.0, 1.0) * PI * 0.5)
	var bell := pow(maxf(1.0 - pow(v, 1.52), 0.0), 0.60)
	var r_base := lerpf(_oculus_radius(theta), 14.2, bell)
	# Wave-cut karst undercut gallery near waterline + irregular sedimentary bedding ripples.
	var undercut := 0.85 * exp(-pow((v - 0.14) / 0.11, 2.0))
	var strata := (0.30 * sin(v * TAU * 4.2 + 0.45 * sin(theta * 3.0))
			+ 0.16 * cos(v * TAU * 8.5 - 0.35 * cos(theta * 5.0))) * (1.0 - smoothstep(0.84, 1.0, v))
	var crag := (1.05 * sin(theta * 3.0 + 0.7) + 0.72 * cos(theta * 5.0 - 1.3) + 0.46 * sin(theta * 8.0 + 0.4)
			+ 0.28 * cos(theta * 11.0 + v * 5.2)) * (0.30 + 0.70 * bulge) * (1.0 - 0.50 * smoothstep(0.82, 1.0, v))
	var r := maxf(r_base + undercut + strata + crag, _oculus_radius(theta) - 0.15)
	var cx := lerpf(CAVERN_CX, OCULUS_CX, smoothstep(0.25, 1.0, v))
	var cz := lerpf(CAVERN_CZ, OCULUS_CZ, smoothstep(0.25, 1.0, v))
	var sx := lerpf(0.98, 1.0, v)
	var sz := lerpf(1.05, 1.0, v)
	return Vector3(cx + cos(theta) * r * sx, y, cz + sin(theta) * r * sz)


static func _cavern_normal(theta: float, v: float) -> Vector3:
	var dt := 0.04
	var dv := 0.025
	var p_t0 := _cavern_pt(theta - dt, v)
	var p_t1 := _cavern_pt(theta + dt, v)
	var p_v0 := _cavern_pt(theta, maxf(v - dv, 0.0))
	var p_v1 := _cavern_pt(theta, minf(v + dv, 1.0))
	var n := (p_v1 - p_v0).cross(p_t1 - p_t0).normalized()
	var inward := Vector3(CAVERN_CX, 3.5, CAVERN_CZ) - _cavern_pt(theta, v)
	if n.dot(inward) < 0.0:
		n = -n
	return n


## Smooth, organically mottled per-vertex karst limestone bedrock color (no hard cartoon stripes!): blends damp dark
## slate-umber at the waterline, warm Yucatan ochre & travertine strata with undulating veins, crevice darkening in
## concave folds, and weathered mossy cliff tones right at the jungle oculus rim.
static func _cavern_color(theta: float, v: float) -> Color:
	var wave := v + 0.045 * sin(theta * 3.0 + 0.6) + 0.025 * cos(theta * 6.0 - 1.1)
	var grain := 0.5 + 0.5 * sin(wave * TAU * 5.5 + 0.9 * sin(theta * 4.0))
	var fine := 0.5 + 0.5 * cos(wave * TAU * 11.0 - theta * 5.0)
	var pocket := 0.5 + 0.5 * sin(theta * 5.0 - 1.3 + v * 3.5)
	var rock := LIME_UMBER.lerp(LIME_OCHRE, grain * 0.72 + fine * 0.28)
	rock = rock.lerp(LIME_CREAM, smoothstep(0.55, 0.95, grain * pocket) * 0.36)
	rock = rock.lerp(LIME_GREY, (1.0 - pocket) * 0.32)
	# Wet mineral-stained dark zone rising softly above the water surface (v < 0.19).
	var wet := 1.0 - smoothstep(0.04, 0.21, v)
	rock = rock.lerp(LIME_DARK.lerp(LIME_WET, 0.45), wet * 0.86)
	# Subtle weathered olive-moss dappling near the high sunlit/moonlit jungle oculus lip (v > 0.78).
	var moss := smoothstep(0.76, 0.98, v) * (0.58 + 0.42 * sin(theta * 7.0 + 1.4))
	rock = rock.lerp(LIME_MOSSY, clampf(moss, 0.0, 0.85))
	# Crevice depth modulation so rock folds read with rich 3D relief.
	var shade := 0.82 + 0.28 * pocket
	return (rock * shade).srgb_to_linear()


# --- Zone A: Viewing island, mossy stepped terraces & rounded river-stone water steps ---------------------------------

static func _viewing_island_and_steps(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var stone_m: Material = c.tinted("stone")
	var lime_m: Material = c.tinted("plaster")
	var soft_stone: Material = c.soft("stone", true)
	var leaf_m: Material = c.soft("leaves", true)

	# Three sculpted natural travertine limestone shelves stepping organically into the turquoise water:
	# [top_y, bot_y, rx, rz, wobble_amp, top_col, side_col]
	var tiers: Array = [
		[0.0, -0.20, 2.86, 3.66, 0.065, LIME_CREAM, LIME_OCHRE],
		[-0.20, -0.45, 3.54, 4.36, 0.095, LIME_OCHRE, LIME_WET],
		[-0.45, -1.30, 4.38, 5.18, 0.115, LIME_WET, LIME_DARK],
	]
	const SIDES := 32
	for ti in tiers.size():
		var t: Array = tiers[ti]
		var y_top: float = t[0]
		var y_bot: float = t[1]
		var rx: float = t[2]
		var rz: float = t[3]
		var amp: float = t[4]
		var c_top: Color = t[5]
		var c_side: Color = t[6]
		var top_poly := PackedVector3Array()
		var ring_hi := PackedVector3Array()
		var ring_lo := PackedVector3Array()
		var norms := PackedVector3Array()
		for k in SIDES + 1:
			var ang := TAU * float(k % SIDES) / float(SIDES)
			var p2 := _island_outline(ang, rx, rz, amp)
			var p2_lo := _island_outline(ang, rx * 1.07, rz * 1.06, amp)
			if k < SIDES:
				top_poly.append(Vector3(p2.x, y_top, p2.y))
			ring_hi.append(Vector3(p2.x, y_top, p2.y))
			ring_lo.append(Vector3(p2_lo.x, y_bot, p2_lo.y))
			norms.append(Vector3(cos(ang), 0.18, sin(ang)).normalized())
		s.surface(stone_m if ti == 0 else lime_m)
		s.colour = c_top.srgb_to_linear()
		s.polygon(top_poly, Vector3.UP)
		s.colour = c_side.srgb_to_linear()
		s.strip(ring_lo, ring_hi, norms)

	# Three broad natural curved limestone steps descending from the front island edge right into the turquoise water.
	s.surface(stone_m)
	for si in 3:
		var sy := -0.10 - float(si) * 0.135
		var sz := -3.02 - float(si) * 0.42
		var sw := 2.40 + float(si) * 0.34
		s.colour = LIME_CREAM.lerp(LIME_WET, float(si) * 0.42).srgb_to_linear()
		s.box(Vector3(0.0, sy - 0.065, sz), Vector3(sw, 0.13, 0.45), Basis(), [RoomMesh.DOWN])

	# Smooth water-worn rounded limestone stepping boulders emerging naturally from the clear turquoise shallows!
	u.surface(soft_stone)
	var river_stones: Array = [
		[Vector3(-1.38, -0.34, -4.42), 0.48, 0.42, 0.24],
		[Vector3(-0.22, -0.35, -4.78), 0.54, 0.46, 0.22],
		[Vector3(1.16, -0.34, -4.50), 0.46, 0.40, 0.24],
		[Vector3(2.68, -0.32, -3.65), 0.56, 0.48, 0.26],
		[Vector3(-2.88, -0.32, -3.45), 0.58, 0.50, 0.26],
	]
	for rs: Array in river_stones:
		var rp: Vector3 = rs[0]
		var rx_s: float = rs[1]
		var h_s: float = rs[3]
		u.colour = LIME_WET.lerp(LIME_GREY, rng.randf() * 0.4).srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(rx_s * 1.18, -0.22),
			Vector2(rx_s * 1.05, -0.02),
			Vector2(rx_s * 0.86, h_s * 0.35),
			Vector2(rx_s * 0.52, h_s * 0.46),
			Vector2(0.0, h_s * 0.48),
		], rp, 10)

	# Natural low weathered karst edge boulders & lush mossy fern pockets softening the outer island rim!
	for k in 16:
		var ang := TAU * float(k) / 16.0 + 0.16
		var p2 := _island_outline(ang, 3.16, 3.92, 0.07)
		# Keep front water steps and aft timber boardwalk approach wide open!
		if (absf(p2.x) < 1.65 and p2.y < -2.5) or (absf(p2.x) < 1.35 and p2.y > 3.1):
			continue
		var mp := Vector3(p2.x, -0.20, p2.y)
		if k % 3 == 0:
			u.surface(soft_stone)
			u.colour = LIME_GREY.lerp(LIME_WET, 0.45).srgb_to_linear()
			var br := rng.randf_range(0.32, 0.48)
			Shapes.lathe(u, [
				Vector2(br * 1.15, -0.18),
				Vector2(br, 0.08),
				Vector2(br * 0.72, 0.22),
				Vector2(0.0, 0.28),
			], mp, 8)
		u.surface(leaf_m)
		u.colour = MOSS_DEEP.lerp(MOSS_BRIGHT, rng.randf()).srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(rng.randf_range(0.58, 0.96), rng.randf_range(0.11, 0.18),
				rng.randf_range(0.46, 0.82)), 0.055, Transform3D(Basis(Vector3.UP, ang), mp + Vector3(0, 0.05, 0)),
				1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		if k % 2 == 0 and p2.y > -1.7:
			_fern_clump(u, mp + Vector3(0, 0.09, 0), rng.randf_range(0.52, 0.76), rng)

	# Physics boxes strictly outside >= 2.8 m from origin (viewer clear!).
	c.shapes.append(PhysicsShapes.box(Vector3(-3.35, -0.25, 0.6), Vector3(0.8, 0.5, 5.2)))
	c.shapes.append(PhysicsShapes.box(Vector3(3.35, -0.25, 0.6), Vector3(0.8, 0.5, 5.2)))


# --- Zone A2: Weathered timber boardwalk bridge & natural arched aft grotto cave portal -------------------------------

static func _boardwalk_and_rear_landing(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood_m: Material = c.tinted("wood")
	var stone_m: Material = c.tinted("stone")
	var soft_stone: Material = c.soft("stone", true)
	var leaf_m: Material = c.soft("leaves", true)

	var z_start := 3.92
	var z_end := 10.15
	var span := z_end - z_start
	var mid_z := (z_start + z_end) * 0.5
	var bw := 1.88

	# Heavy dark-timber longitudinal stringers under the bridge planks.
	s.surface(wood_m)
	s.colour = TIMBER_WET.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		Shapes.beam(s, Vector3(side * 0.68, -0.09, z_start), Vector3(side * 0.68, 0.09, z_end), Vector2(0.12, 0.14))

	# 25 weathered timber planks with subtle water-glimpse gaps and organic tonal variation.
	const PLANKS := 25
	for i in PLANKS:
		var t := (float(i) + 0.5) / float(PLANKS)
		var pz := lerpf(z_start, z_end, t)
		var py := lerpf(-0.015, 0.165, t)
		var shade := rng.randf_range(0.82, 1.14)
		var tilt_z := rng.randf_range(-0.012, 0.012)
		s.colour = (TIMBER_WARM.lerp(TIMBER_WEATHERED, rng.randf()) * shade).srgb_to_linear()
		s.box(Vector3(0.0, py, pz), Vector3(bw + rng.randf_range(-0.04, 0.04), 0.052, 0.21),
				Basis(Vector3.FORWARD, tilt_z))

	# 10 sturdy round timber pilings sunk deep into the turquoise cenote water + rustic handrails.
	var post_zs: Array[float] = [4.55, 5.95, 7.35, 8.75, 10.05]
	for pi in post_zs.size():
		var pz := post_zs[pi]
		var t := (pz - z_start) / span
		var py := lerpf(-0.015, 0.165, t)
		var post_top := py + 0.86
		for side: float in [-1.0, 1.0]:
			var px := side * (bw * 0.5 + 0.05)
			s.surface(wood_m)
			s.colour = TIMBER_WET.srgb_to_linear()
			Shapes.cylinder(s, Vector3(px, -1.25, pz), 0.072, post_top + 1.25, 8)
			s.colour = TIMBER_WARM.srgb_to_linear()
			s.box(Vector3(px, post_top + 0.03, pz), Vector3(0.17, 0.06, 0.17))

	s.surface(wood_m)
	for side: float in [-1.0, 1.0]:
		var px := side * (bw * 0.5 + 0.05)
		var y0 := lerpf(-0.015, 0.165, (post_zs[0] - z_start) / span)
		var y1 := lerpf(-0.015, 0.165, (post_zs[-1] - z_start) / span)
		s.colour = TIMBER_WARM.srgb_to_linear()
		Shapes.beam(s, Vector3(px, y0 + 0.80, post_zs[0]), Vector3(px, y1 + 0.80, post_zs[-1]), Vector2(0.075, 0.065))
		s.colour = TIMBER_WEATHERED.srgb_to_linear()
		Shapes.beam(s, Vector3(px, y0 + 0.44, post_zs[0]), Vector3(px, y1 + 0.44, post_zs[-1]), Vector2(0.048, 0.048))
		c.shapes.append(PhysicsShapes.box(Vector3(px, 0.5, mid_z), Vector3(0.18, 1.1, span)))

	# Aft terraced limestone landing & natural curved rocky grotto cave arch portal (z = 10.1 .. 12.6).
	s.surface(stone_m)
	s.colour = LIME_OCHRE.srgb_to_linear()
	s.box(Vector3(0.0, -0.45, 11.2), Vector3(5.6, 1.32, 2.4), Basis(), [RoomMesh.DOWN])
	s.colour = LIME_CREAM.srgb_to_linear()
	s.box(Vector3(0.0, 0.34, 11.7), Vector3(3.2, 0.28, 1.2), Basis(), [RoomMesh.DOWN])
	s.box(Vector3(0.0, 0.62, 12.15), Vector3(2.6, 0.28, 0.9), Basis(), [RoomMesh.DOWN])

	# Organic arched natural karst stone portal (curved stone arch + flanking boulders + lush ferns, zero sharp box!).
	u.surface(soft_stone)
	u.colour = LIME_GREY.lerp(LIME_UMBER, 0.45).srgb_to_linear()
	Shapes.arch(u, Vector3(0.0, 2.05, 11.95), 1.48, 2.55, 1.45, 12, Basis(), 0.0, PI)
	for side: float in [-1.0, 1.0]:
		# Sculpted organic cavern entrance pillars tapering up into the stone arch!
		Shapes.lathe(u, [
			Vector2(1.15, -0.5),
			Vector2(1.02, 0.8),
			Vector2(0.88, 2.05),
			Vector2(0.68, 2.65),
			Vector2(0.0, 2.85),
		], Vector3(side * 2.05, 0.0, 11.95), 9)
	# Deep shadowed arched tunnel mouth recessed neatly inside the curved stone portal.
	s.surface(stone_m)
	s.colour = Color(0.025, 0.032, 0.042).srgb_to_linear()
	var arch_back := PackedVector3Array()
	arch_back.append(Vector3(-1.52, 0.15, 12.52))
	arch_back.append(Vector3(1.52, 0.15, 12.52))
	for k in 13:
		var a := PI * float(k) / 12.0
		arch_back.append(Vector3(cos(a) * 1.52, 2.05 + sin(a) * 1.52, 12.52))
	s.polygon(arch_back, Vector3.FORWARD)
	u.surface(leaf_m)
	_fern_clump(u, Vector3(-2.35, 0.25, 10.4), 0.82, rng)
	_fern_clump(u, Vector3(2.35, 0.25, 10.4), 0.85, rng)
	_fern_clump(u, Vector3(-0.9, 4.15, 11.35), 0.72, rng)
	_fern_clump(u, Vector3(0.95, 4.10, 11.35), 0.72, rng)


# --- Zone B: Towering 20-ring smoothly-shaded karst limestone cavern dome & craggy mossy oculus cliff collar ----------

static func _karst_cavern_dome(c: Object, _rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var lime_m: Material = c.tinted("plaster")
	s.surface(lime_m)

	const RINGS := 20
	const SECTORS := 6
	const SEC_SEGS := 8
	const TOTAL_SEGS := SECTORS * SEC_SEGS # 48 smooth sides around the entire cavern!

	# Six smooth curved sectors using s.sheet() with true per-vertex organic karst bedrock shading (zero stripes!).
	for si in SECTORS:
		var th_mid := TAU * (float(si) + 0.5) / float(SECTORS)
		var u_axis := Vector3(-sin(th_mid), 0.0, cos(th_mid)).normalized()
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		for ri in RINGS + 1:
			var v := float(ri) / float(RINGS)
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for k in SEC_SEGS + 1:
				var idx := (si * SEC_SEGS + k) % TOTAL_SEGS
				var th := TAU * float(idx) / float(TOTAL_SEGS)
				row.append(_cavern_pt(th, v))
				nrow.append(_cavern_normal(th, v))
				crow.append(_cavern_color(th, v))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		s.sheet(rows, norms, cols, u_axis, Vector3.UP)

	# Craggy 2.2 m-thick mossy jungle oculus cliff collar rising above y = OCULUS_Y so the sky opening has real depth!
	for si in SECTORS:
		var th_mid := TAU * (float(si) + 0.5) / float(SECTORS)
		var u_axis := Vector3(-sin(th_mid), 0.0, cos(th_mid)).normalized()
		var r0 := PackedVector3Array()
		var r1 := PackedVector3Array()
		var r2 := PackedVector3Array()
		var n0 := PackedVector3Array()
		var c0 := PackedColorArray()
		var c1 := PackedColorArray()
		var c2 := PackedColorArray()
		for k in SEC_SEGS + 1:
			var idx := (si * SEC_SEGS + k) % TOTAL_SEGS
			var th := TAU * float(idx) / float(TOTAL_SEGS)
			var p0 := _cavern_pt(th, 1.0)
			var out_dir := Vector3(cos(th), 0.0, sin(th))
			var h_var := 0.36 * sin(th * 4.0 + 0.9) + 0.20 * cos(th * 7.0 - 0.5)
			r0.append(p0)
			r1.append(p0 + out_dir * 0.38 + Vector3(0.0, 1.08 + h_var * 0.5, 0.0))
			r2.append(p0 + out_dir * 0.92 + Vector3(0.0, 2.25 + h_var, 0.0))
			n0.append((-out_dir * 0.92 + Vector3.DOWN * 0.38).normalized())
			c0.append(_cavern_color(th, 1.0))
			c1.append((LIME_MOSSY * (0.85 + 0.2 * sin(th * 5.0))).srgb_to_linear())
			c2.append((MOSS_DEEP * (0.82 + 0.25 * cos(th * 6.0))).srgb_to_linear())
		s.sheet([r0, r1, r2], [n0, n0, n0], [c0, c1, c2], u_axis, Vector3.UP)


# --- Zone B2: Wall-anchored organic karst ledges, mossy water islets, clustered stalactites & flowstone columns -------

## Builds wall-anchored organic rocky ledges (returning each ledge's crystal anchor point on top!), mossy water islets,
## hanging stalactite clusters and multi-spired karst flowstone pillars.
static func _rock_shelves_islets_and_formations(c: Object, rng: RandomNumberGenerator) -> Array[Vector3]:
	var u: RoomMesh = c.u
	var soft_stone: Material = c.soft("stone", true)
	var leaf_m: Material = c.soft("leaves", true)
	var ledge_tops: Array[Vector3] = []

	# 1. Six wall-anchored terraced karst cliff buttresses rising straight out of the deep cenote lagoon (-1.35 m) up
	#    to mossy crystal shelves embedded deep into the cavern walls (zero hovering floating rocks!).
	for ld: Array in WALL_LEDGES:
		var th := deg_to_rad(float(ld[0]))
		var top_y: float = float(ld[1])
		var l_w: float = float(ld[2])
		var reach: float = float(ld[3])
		var v := clampf((top_y + 1.6) / (OCULUS_Y + 1.6), 0.05, 0.85)
		var wall_p := _cavern_pt(th, v)
		var inward := Vector3(CAVERN_CX - wall_p.x, 0.0, CAVERN_CZ - wall_p.z).normalized()
		var side_v := inward.cross(Vector3.UP).normalized()
		var base_y := -1.35
		var h := top_y - base_y
		var shelf_c := Vector3(wall_p.x, base_y, wall_p.z) + inward * (reach * 0.25)
		ledge_tops.append(Vector3(wall_p.x, top_y - 0.04, wall_p.z) + inward * (reach * 0.62))

		u.surface(soft_stone)
		# Three overlapping grounded karst limestone buttress columns rising from beneath the water to a stepped terrace!
		for lobe in [-1, 0, 1]:
			var off_s := float(lobe) * l_w * 0.28
			var off_in := (0.45 if lobe == 0 else -0.05)
			var lp := shelf_c + side_v * off_s + inward * off_in
			var rad := (l_w * 0.36 if lobe == 0 else l_w * 0.28)
			var lh := h * (1.0 if lobe == 0 else 0.78)
			u.colour = LIME_WET.lerp(LIME_OCHRE, 0.38 if lobe == 0 else 0.22).srgb_to_linear()
			Shapes.lathe(u, [
				Vector2(rad * 1.48, 0.0),
				Vector2(rad * 1.32, lh * 0.30),
				Vector2(rad * 1.18, lh * 0.62),
				Vector2(rad * 1.06, lh * 0.88),
				Vector2(rad * 0.86, lh * 0.98),
				Vector2(0.0, lh),
			], lp, 9)

		# Velvety moss pad & cascading ferns crowning each solid limestone cliff buttress!
		u.surface(leaf_m)
		u.colour = MOSS_DEEP.lerp(MOSS_BRIGHT, rng.randf()).srgb_to_linear()
		var b_xf := Basis(side_v, Vector3.UP, inward)
		u.rounded_box(Vector3.ZERO, Vector3(l_w * 0.56, 0.16, reach * 0.70), 0.065,
				Transform3D(b_xf, Vector3(wall_p.x, top_y + 0.02, wall_p.z) + inward * (reach * 0.45)), 1,
				Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		_fern_clump(u, Vector3(wall_p.x, top_y + 0.06, wall_p.z) + inward * (reach * 0.62),
				rng.randf_range(0.68, 0.94), rng)

	# 2. Four mossy limestone rock islets emerging from the emerald cenote water around the viewing island.
	u.surface(soft_stone)
	for isl: Array in ISLETS:
		var ic: Vector2 = isl[0]
		var ir: float = isl[1]
		var top_y: float = isl[2]
		var base := Vector3(ic.x, -1.30, ic.y)
		var h := top_y - base.y
		u.colour = LIME_WET.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(ir * 1.32, 0.0),
			Vector2(ir * 1.14, h * 0.45),
			Vector2(ir * 0.96, h * 0.76),
			Vector2(ir * 0.74, h * 0.94),
			Vector2(0.0, h),
		], base, 11)
		u.colour = LIME_GREY.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(ir * 0.62, 0.0),
			Vector2(ir * 0.52, h * 0.55),
			Vector2(ir * 0.30, h * 0.82),
			Vector2(0.0, h * 0.86),
		], base + Vector3(ir * 0.72 * signf(ic.x), 0.0, 0.42), 8)
		u.surface(leaf_m)
		u.colour = MOSS_BRIGHT.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(ir * 1.18, 0.14, ir * 1.08), 0.055,
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(ic.x, top_y - 0.03, ic.y)), 1,
				Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		_fern_clump(u, Vector3(ic.x, top_y + 0.03, ic.y), rng.randf_range(0.68, 0.96), rng)
		u.surface(soft_stone)
		c.shapes.append(PhysicsShapes.box(Vector3(ic.x, 0.0, ic.y), Vector3(ir * 1.6, 1.2, ir * 1.6)))

	# 3. 44 sculpted hanging karst stalactites clustered around the upper dome vault & oculus overhang
	#    (anchored firmly into the ceiling bedrock, strictly above y >= 5.5 m for 100% clear sight lines!).
	u.surface(soft_stone)
	for i in 44:
		var th := TAU * float(i) / 44.0 + rng.randf_range(-0.06, 0.06)
		var v := rng.randf_range(0.60, 0.96)
		var anchor := _cavern_pt(th, v)
		var inward := (Vector3(OCULUS_CX, anchor.y, OCULUS_CZ) - anchor).normalized()
		var crown := anchor + inward * 0.16 + Vector3(0.0, 0.55, 0.0)
		var max_len := maxf(crown.y - 5.6, 0.90)
		var length := minf(rng.randf_range(1.25, 3.75), max_len)
		if anchor.z < -6.8 and absf(anchor.x) < 4.8:
			length = minf(length, 1.95)
		var rad := rng.randf_range(0.15, 0.36)
		var col := LIME_WARM.lerp(LIME_UMBER, rng.randf() * 0.7) * rng.randf_range(0.84, 1.08)
		u.colour = col.srgb_to_linear()
		_stalactite(u, crown, rad, length, rng)
		if i % 2 == 0:
			var off := Vector3(rng.randf_range(-0.38, 0.38), 0.18, rng.randf_range(-0.38, 0.38))
			_stalactite(u, crown + off, rad * 0.56, length * 0.64, rng)

	# 4. 12 dramatic multi-spired organic karst flowstone & stalagmite reef columns rising out of the turquoise pool!
	var pillar_specs: Array = [
		[Vector2(-7.8, -7.8), 0.72, 5.5],
		[Vector2(7.9, -7.6), 0.74, 5.9],
		[Vector2(-9.6, -4.4), 0.62, 4.2],
		[Vector2(9.7, -4.1), 0.64, 4.4],
		[Vector2(-10.2, 0.2), 0.68, 4.7],
		[Vector2(10.3, 0.5), 0.66, 4.9],
		[Vector2(-9.1, 5.1), 0.62, 4.0],
		[Vector2(9.2, 4.9), 0.60, 4.2],
		[Vector2(-6.4, 8.6), 0.56, 3.5],
		[Vector2(6.5, 8.4), 0.58, 3.7],
		[Vector2(-7.2, -11.6), 0.64, 4.5],
		[Vector2(7.3, -11.4), 0.62, 4.3],
	]
	for ps: Array in pillar_specs:
		var pc: Vector2 = ps[0]
		var rad: float = ps[1]
		var h: float = ps[2]
		# Broad submerged & water-line travertine reef skirt grounding each flowstone cluster!
		u.colour = LIME_WET.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(rad * 2.15, 0.0),
			Vector2(rad * 1.85, 0.85),
			Vector2(rad * 1.48, 1.38),
			Vector2(rad * 1.05, 1.75),
			Vector2(0.0, 1.85),
		], Vector3(pc.x, -1.35, pc.y), 10)
		# Main lumpy organic dripstone spire.
		u.colour = LIME_WET.lerp(LIME_OCHRE, 0.52).srgb_to_linear()
		_stalagmite(u, Vector3(pc.x, -1.35, pc.y), rad, h + 1.35, rng)
		# Two irregular companion dripstone spires forming a realistic karst cluster!
		u.colour = LIME_GREY.srgb_to_linear()
		_stalagmite(u, Vector3(pc.x - signf(pc.x) * rad * 0.92, -1.35, pc.y + 0.42), rad * 0.54,
				h * 0.58 + 1.35, rng)
		u.colour = LIME_UMBER.srgb_to_linear()
		_stalagmite(u, Vector3(pc.x + signf(pc.x) * rad * 0.58, -1.35, pc.y - 0.52), rad * 0.44,
				h * 0.40 + 1.35, rng)

	return ledge_tops


static func _stalactite(u: RoomMesh, crown: Vector3, rad: float, length: float, rng: RandomNumberGenerator) -> void:
	var b0 := rng.randf_range(0.76, 1.04)
	var b1 := rng.randf_range(0.46, 0.68)
	var b2 := rng.randf_range(0.28, 0.44)
	Shapes.lathe(u, [
		Vector2(rad * 1.24, 0.0),
		Vector2(rad * b0, length * 0.20),
		Vector2(rad * b1, length * 0.44),
		Vector2(rad * (b1 * 0.82), length * 0.58),
		Vector2(rad * b2, length * 0.78),
		Vector2(0.014, length),
	], crown, 8, Basis(Vector3.RIGHT, PI))


static func _stalagmite(u: RoomMesh, base: Vector3, rad: float, height: float, rng: RandomNumberGenerator) -> void:
	var w1 := rng.randf_range(0.78, 0.96)
	var w2 := rng.randf_range(0.54, 0.74)
	var w3 := rng.randf_range(0.30, 0.48)
	# Organic undulating karst travertine dripstone profile (not a plain geometric cone!).
	Shapes.lathe(u, [
		Vector2(rad * 1.36, 0.0),
		Vector2(rad * 1.12, height * 0.18),
		Vector2(rad * w1, height * 0.36),
		Vector2(rad * (w1 * 0.92), height * 0.48),
		Vector2(rad * w2, height * 0.64),
		Vector2(rad * w3, height * 0.82),
		Vector2(rad * 0.14, height * 0.95),
		Vector2(0.0, height),
	], base, 9)


# --- Zone C: Overhead jungle oculus — gnarled roots, cascading hanging vines & lush silhouetted tropical ferns --------

static func _oculus_roots_vines_and_ferns(c: Object, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	var wood_soft: Material = c.soft("wood", true)
	var leaf_m: Material = c.soft("leaves", true)

	# 1. 22 gnarled strangler-fig aerial tree roots curling over the jagged oculus lip and hanging down the walls!
	u.surface(wood_soft)
	for i in 22:
		var th := TAU * float(i) / 22.0 + rng.randf_range(-0.08, 0.08)
		var rim_r := _oculus_radius(th)
		var out_dir := Vector3(cos(th), 0.0, sin(th))
		var top_p := Vector3(OCULUS_CX + out_dir.x * (rim_r + 0.85), OCULUS_Y + 1.65,
				OCULUS_CZ + out_dir.z * (rim_r + 0.85))
		var lip_p := Vector3(OCULUS_CX + out_dir.x * (rim_r - 0.16), OCULUS_Y - 0.15,
				OCULUS_CZ + out_dir.z * (rim_r - 0.16))
		var in_front := out_dir.z < -0.45 and absf(out_dir.x) < 0.75
		var drop := rng.randf_range(2.6, 4.4) if in_front else rng.randf_range(5.0, 9.0)
		var thick := rng.randf_range(0.085, 0.175)
		u.colour = (ROOT_BARK * rng.randf_range(0.80, 1.15)).srgb_to_linear()
		Shapes.beam(u, top_p, lip_p, Vector2(thick * 1.32, thick * 1.32))
		var prev := lip_p
		const SEGS := 5
		for k in range(1, SEGS + 1):
			var t := float(k) / float(SEGS)
			var sway := Vector3(sin(t * PI * 2.2 + float(i) * 1.7) * 0.40, 0.0,
					cos(t * PI * 1.9 + float(i) * 2.3) * 0.40)
			var nxt := lip_p + Vector3(out_dir.x * (0.48 * t), -drop * t, out_dir.z * (0.48 * t)) + sway
			var seg_w := thick * lerpf(1.0, 0.24, t)
			Shapes.beam(u, prev, nxt, Vector2(seg_w, seg_w))
			if k == 2 and i % 2 == 0:
				var fork := nxt + Vector3(out_dir.z * 0.62, -1.85, -out_dir.x * 0.62)
				Shapes.beam(u, nxt, fork, Vector2(seg_w * 0.55, seg_w * 0.55))
			prev = nxt

	# 2. 32 cascading hanging jungle liana vines dangling gracefully from the oculus perimeter!
	for i in 32:
		var th := TAU * float(i) / 32.0 + rng.randf_range(-0.07, 0.07)
		var rim_r := _oculus_radius(th) - rng.randf_range(0.05, 0.52)
		var out_dir := Vector3(cos(th), 0.0, sin(th))
		var start := Vector3(OCULUS_CX + out_dir.x * rim_r, OCULUS_Y + 0.60, OCULUS_CZ + out_dir.z * rim_r)
		var in_front := out_dir.z < -0.35 and absf(out_dir.x) < 0.78
		var drop := rng.randf_range(2.2, 4.3) if in_front else rng.randf_range(4.4, 8.6)
		u.surface(wood_soft)
		u.colour = (ROOT_BARK * 0.85).srgb_to_linear()
		var p_prev := start
		var stem_pts: Array[Vector3] = [start]
		const V_SEGS := 5
		for k in range(1, V_SEGS + 1):
			var t := float(k) / float(V_SEGS)
			var p := start + Vector3(sin(t * 4.5 + float(i)) * 0.22, -drop * t, cos(t * 3.8 + float(i) * 1.4) * 0.22)
			Shapes.beam(u, p_prev, p, Vector2(0.024, 0.024))
			stem_pts.append(p)
			p_prev = p
		u.surface(leaf_m)
		u.colour = VINE_GREEN.lerp(FERN_DARK, rng.randf() * 0.6).srgb_to_linear()
		for k in V_SEGS:
			var a_pt := stem_pts[k]
			var b_pt := stem_pts[k + 1]
			for j in 3:
				var f := (float(j) + 0.5) / 3.0
				var at := a_pt.lerp(b_pt, f)
				var side_ang := float(i * 7 + k * 3 + j) * 1.9
				var dir := Vector3(cos(side_ang), -0.45, sin(side_ang)).normalized()
				var l_len := rng.randf_range(0.20, 0.34)
				var across := dir.cross(Vector3.UP).normalized() * l_len * 0.45
				Shapes.leaf(u, at, dir * l_len, across, dir.cross(across).normalized())

	# 3. 34 sweeping broad tropical fern & jungle palm fronds arching gracefully INWARD across the jagged oculus rim,
	#    creating a breathtaking rainforest canopy silhouette against the tropical stars, Milky Way & glowing Moon!
	u.surface(leaf_m)
	for i in 34:
		var th := TAU * float(i) / 34.0 + rng.randf_range(-0.06, 0.06)
		var rim_r := _oculus_radius(th) + 0.18
		var in_dir := Vector3(-cos(th), 0.0, -sin(th)).normalized()
		var base := Vector3(OCULUS_CX - in_dir.x * rim_r, OCULUS_Y + rng.randf_range(0.42, 1.48),
				OCULUS_CZ - in_dir.z * rim_r)
		var reach := rng.randf_range(1.95, 3.15)
		var lift := rng.randf_range(0.62, 1.25)
		var col := FERN_LUSH.lerp(FERN_DARK, rng.randf())
		u.colour = col.srgb_to_linear()
		_arch_frond(u, base, in_dir, reach, lift, 9)


static func _arch_frond(u: RoomMesh, base: Vector3, dir: Vector3, reach: float, lift: float, pairs: int) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var prev := base
	for i in range(1, pairs + 1):
		var t := float(i) / float(pairs)
		var p := base + dir * (reach * t) + Vector3.UP * (lift * sin(t * PI * 0.82) - 0.34 * t * t)
		var along := (p - prev).normalized()
		var pinna := reach * 0.26 * sin(clampf(t, 0.08, 0.98) * PI)
		for sgn: float in [-1.0, 1.0]:
			var l_dir := (side * sgn + along * 0.38 + Vector3.DOWN * 0.18).normalized() * pinna
			var l_across := along * (pinna * 0.28)
			Shapes.leaf(u, p, l_dir, l_across, l_dir.cross(l_across).normalized())
		prev = p


static func _fern_clump(u: RoomMesh, at: Vector3, scale: float, rng: RandomNumberGenerator) -> void:
	const FRONDS := 6
	for f in FRONDS:
		var a := TAU * float(f) / float(FRONDS) + rng.randf_range(-0.25, 0.25)
		var dir := Vector3(sin(a), 0.0, cos(a))
		u.colour = FERN_LUSH.lerp(MOSS_BRIGHT, rng.randf() * 0.5).srgb_to_linear()
		_arch_frond(u, at, dir, scale * rng.randf_range(0.75, 1.12), scale * rng.randf_range(0.42, 0.65), 5)


# --- Zone D: Natural carved dark-basalt screen pylons & volcanic lagoon reef ------------------------------------------

static func _screen_basalt_pylons(c: Object, rng: RandomNumberGenerator) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 2.45, -10.8)))
	var sc_sz: Vector2 = scr.get("size", Vector2(5.8, 3.26))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var cz := sc_xf.origin.z
	var hw := sc_sz.x * 0.5
	var hh := sc_sz.y * 0.5
	var sc_bot := cy - hh
	var sc_top := cy + hh

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var stone_m: Material = c.tinted("stone")
	var soft_stone: Material = c.soft("stone", true)
	var iron_m: Material = c.tinted("iron")
	var bronze_m: Material = c.shiny("gilt", 0.84, 0.56, 0.22)
	var leaf_m: Material = c.soft("leaves", true)

	# 1. Stepped submerged dark-basalt lagoon reef plinth rising from beneath the water (y = -1.35 .. +0.62 m).
	s.surface(stone_m)
	s.colour = BASALT_DARK.srgb_to_linear()
	s.box(Vector3(cx, -0.68, cz - 0.30), Vector3(sc_sz.x + 4.4, 1.36, 2.10), Basis(), [RoomMesh.DOWN])
	s.colour = BASALT_MID.srgb_to_linear()
	s.box(Vector3(cx, 0.22, cz - 0.25), Vector3(sc_sz.x + 3.2, 0.44, 1.55), Basis(), [RoomMesh.DOWN])
	s.colour = BASALT_TRIM.srgb_to_linear()
	s.box(Vector3(cx, 0.54, cz - 0.16), Vector3(sc_sz.x + 1.35, 0.20, 0.92), Basis(), [RoomMesh.DOWN])

	# Craggy natural volcanic basalt reef boulders clasping the outer flanks of the screen plinth in the water!
	u.surface(soft_stone)
	for side: float in [-1.0, 1.0]:
		u.colour = BASALT_DARK.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(1.45, -1.35),
			Vector2(1.22, -0.35),
			Vector2(0.88, 0.22),
			Vector2(0.0, 0.42),
		], Vector3(cx + side * (hw + 1.95), 0.0, cz + 0.28), 9)
		u.colour = BASALT_MID.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.95, -1.35),
			Vector2(0.76, -0.25),
			Vector2(0.45, 0.12),
			Vector2(0.0, 0.22),
		], Vector3(cx + side * (hw + 2.75), 0.0, cz + 0.65), 8)

	# 2. Matte dark-basalt screen backing slab & slim recessed surround frame (strictly behind z = cz - 0.025!).
	s.surface(iron_m)
	s.colour = Color(0.06, 0.07, 0.08).srgb_to_linear()
	s.box(Vector3(cx, cy, cz - 0.14), Vector3(sc_sz.x + 0.30, sc_sz.y + 0.30, 0.20))
	s.surface(stone_m)
	s.colour = BASALT_DARK.srgb_to_linear()
	var ft := 0.12
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * (hw + ft * 0.5), cy, cz - 0.085), Vector3(ft, sc_sz.y + ft * 2.0, 0.11))
	s.box(Vector3(cx, sc_bot - ft * 0.5, cz - 0.085), Vector3(sc_sz.x + ft * 2.0, ft, 0.11))
	s.box(Vector3(cx, sc_top + ft * 0.5, cz - 0.085), Vector3(sc_sz.x + ft * 2.0, ft, 0.11))

	# Patinated aged-bronze Mayan-inspired geometric corner clasps on the screen surround.
	u.surface(bronze_m)
	u.colour = BRONZE_AGED.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var kx := cx + sx * (hw + ft * 0.55)
			var ky := cy + sy * (hh + ft * 0.55)
			u.box(Vector3(kx - sx * 0.14, ky, cz - 0.028), Vector3(0.36, 0.048, 0.030))
			u.box(Vector3(kx, ky - sy * 0.14, cz - 0.028), Vector3(0.048, 0.36, 0.030))
			u.box(Vector3(kx, ky, cz - 0.022), Vector3(0.095, 0.095, 0.036))

	# 3. Twin monumental carved dark-basalt screen pylons flanking the picture (inner edge |x| = 3.12 m, strictly clear!).
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (hw + 0.72)
		var pz := cz - 0.24
		s.surface(stone_m)
		s.colour = BASALT_DARK.srgb_to_linear()
		s.box(Vector3(px, -0.20, pz), Vector3(1.18, 2.30, 1.24), Basis(), [RoomMesh.DOWN])
		s.colour = BASALT_MID.srgb_to_linear()
		s.box(Vector3(px, 2.65, pz), Vector3(0.94, 3.40, 1.02))
		s.colour = BASALT_DARK.srgb_to_linear()
		for df: float in [-0.24, 0.0, 0.24]:
			s.box(Vector3(px + df, 2.65, pz + 0.52), Vector3(0.09, 2.85, 0.045))
		s.colour = BASALT_TRIM.srgb_to_linear()
		for band_y: float in [1.02, 2.45, 4.18]:
			s.box(Vector3(px, band_y, pz), Vector3(1.06, 0.14, 1.12))
		s.colour = BASALT_MID.srgb_to_linear()
		s.box(Vector3(px, 4.65, pz), Vector3(1.16, 0.60, 1.18))
		s.colour = BASALT_DARK.srgb_to_linear()
		s.box(Vector3(px, 5.10, pz), Vector3(0.96, 0.34, 0.98))
		u.surface(bronze_m)
		u.colour = BRONZE_WARM.srgb_to_linear()
		for cy_b: float in [1.14, 4.06]:
			u.box(Vector3(px, cy_b, pz), Vector3(0.98, 0.055, 1.06))
		u.surface(leaf_m)
		u.colour = MOSS_BRIGHT.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(0.98, 0.18, 0.96), 0.06,
				Transform3D(Basis(), Vector3(px, 5.28, pz)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		_fern_clump(u, Vector3(px, 5.34, pz), 0.88, rng)
		c.shapes.append(PhysicsShapes.box(Vector3(px, 2.2, pz), Vector3(1.18, 6.4, 1.24)))

	# 4. Rugged carved basalt architrave lintel spanning cleanly above the screen (y = 4.34 .. 4.92, well above 4.08!).
	s.surface(stone_m)
	s.colour = BASALT_DARK.srgb_to_linear()
	s.box(Vector3(cx, sc_top + 0.44, cz - 0.24), Vector3(sc_sz.x + 2.45, 0.42, 0.92))
	s.colour = BASALT_TRIM.srgb_to_linear()
	s.box(Vector3(cx, sc_top + 0.72, cz - 0.22), Vector3(sc_sz.x + 2.75, 0.20, 1.06))
	s.colour = BASALT_MID.srgb_to_linear()
	for k in 9:
		var dx := cx - 2.6 + float(k) * 0.65
		s.box(Vector3(dx, sc_top + 0.22, cz + 0.22), Vector3(0.24, 0.14, 0.10))
	s.box(Vector3(cx, sc_top + 0.60, cz + 0.28), Vector3(0.56, 0.46, 0.18))
	u.surface(bronze_m)
	u.colour = BRONZE_WARM.srgb_to_linear()
	u.box(Vector3(cx, sc_top + 0.60, cz + 0.38), Vector3(0.26, 0.26, 0.04), Basis(Vector3.BACK, PI * 0.25))
	u.surface(leaf_m)
	for lx: float in [-2.0, 0.0, 2.0]:
		u.colour = MOSS_DEEP.lerp(MOSS_BRIGHT, 0.5).srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(1.35, 0.15, 0.78), 0.05,
				Transform3D(Basis(), Vector3(cx + lx, sc_top + 0.86, cz - 0.22)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])


# --- Zone D2: Hanging wrought-bronze cave lanterns (PieceLamps + warm bake lamps) -------------------------------------

static func _cave_lanterns(c: Object) -> void:
	# 8 hero hanging wrought-bronze cave lanterns (matching bake_lamps: 8), carefully spaced so none visually stack!
	# [glow_center, hang_top, anchor_point, strength]
	var specs: Array = [
		# 1-2: Cantilevered off the outer flanks of the basalt screen pylons.
		[Vector3(-4.48, 3.15, -10.35), Vector3(-4.48, 3.85, -10.35), Vector3(-3.92, 3.92, -10.95), 1.15],
		[Vector3(4.48, 3.15, -10.35), Vector3(4.48, 3.85, -10.35), Vector3(3.92, 3.92, -10.95), 1.15],
		# 3-4: Forged dark-iron shepherd hooks emerging from mossy stone cairns on the island flanks!
		[Vector3(-3.28, 1.24, -1.45), Vector3(-3.28, 1.72, -1.45), Vector3(-3.48, -0.22, -1.55), 0.95],
		[Vector3(3.28, 1.24, -1.45), Vector3(3.28, 1.72, -1.45), Vector3(3.48, -0.22, -1.55), 0.95],
		# 5-6: Perched on weathered crooked timber crooks atop the mossy water islets (well offset in Z from island hooks!).
		[Vector3(-5.65, 1.68, -2.95), Vector3(-5.65, 2.18, -2.95), Vector3(-5.85, 0.18, -3.05), 1.05],
		[Vector3(5.95, 1.74, -2.25), Vector3(5.95, 2.24, -2.25), Vector3(6.15, 0.24, -2.35), 1.05],
		# 7-8: Flanking the weathered timber boardwalk bridge behind the seats.
		[Vector3(-1.35, 1.48, 5.95), Vector3(-1.35, 1.92, 5.95), Vector3(-1.02, 0.88, 5.95), 0.85],
		[Vector3(1.35, 1.48, 5.95), Vector3(1.35, 1.92, 5.95), Vector3(1.02, 0.88, 5.95), 0.85],
	]

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var iron_m: Material = c.tinted("iron")
	var wood_m: Material = c.tinted("wood")
	var soft_stone: Material = c.soft("stone", true)
	var bronze_m: Material = c.shiny("gilt", 0.86, 0.58, 0.20)
	var shade_m: Material = c.shade(LANTERN_AMBER)

	for i in specs.size():
		var sp: Array = specs[i]
		var ctr: Vector3 = sp[0]
		var top: Vector3 = sp[1]
		var anchor: Vector3 = sp[2]
		var strength: float = float(sp[3])

		if i < 2:
			s.surface(iron_m)
			s.colour = IRON_DARK.srgb_to_linear()
			Shapes.beam(s, anchor, top, Vector2(0.052, 0.052))
			Shapes.beam(s, anchor + Vector3(0.0, -0.58, 0.0), top.lerp(anchor, 0.35), Vector2(0.038, 0.038))
		elif i < 4:
			# Sculpted mossy stone lantern cairn + slender curved dark-iron shepherd hook!
			u.surface(soft_stone)
			u.colour = BASALT_DARK.srgb_to_linear()
			Shapes.lathe(u, [
				Vector2(0.32, -0.25),
				Vector2(0.28, 0.12),
				Vector2(0.20, 0.32),
				Vector2(0.0, 0.38),
			], anchor, 8)
			s.surface(iron_m)
			s.colour = IRON_DARK.srgb_to_linear()
			var elbow := Vector3(anchor.x, top.y + 0.08, anchor.z)
			Shapes.beam(s, anchor + Vector3(0.0, 0.24, 0.0), elbow, Vector2(0.042, 0.042))
			Shapes.beam(s, elbow, top + Vector3(0.0, 0.03, 0.0), Vector2(0.036, 0.036))
		elif i < 6:
			s.surface(wood_m)
			s.colour = TIMBER_WET.srgb_to_linear()
			var elbow := Vector3(anchor.x, top.y + 0.08, anchor.z)
			Shapes.beam(s, anchor + Vector3(0.0, -0.35, 0.0), elbow, Vector2(0.072, 0.072))
			Shapes.beam(s, elbow, top + Vector3(0.0, 0.04, 0.0), Vector2(0.056, 0.056))
		else:
			s.surface(iron_m)
			s.colour = IRON_DARK.srgb_to_linear()
			var elbow := Vector3(anchor.x, top.y + 0.06, anchor.z)
			Shapes.beam(s, anchor, elbow, Vector2(0.042, 0.042))
			Shapes.beam(s, elbow, top, Vector2(0.038, 0.038))

		# Suspension iron chain rod from hook to lantern finial.
		s.surface(iron_m)
		s.colour = IRON_DARK.srgb_to_linear()
		Shapes.beam(s, top, ctr + Vector3(0.0, 0.24, 0.0), Vector2(0.020, 0.020))

		# Sculpted octagonal patinated-bronze lantern hood, base dish & 4-rib wrought-iron cage.
		u.surface(bronze_m)
		u.colour = BRONZE_AGED.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.02, 0.26),
			Vector2(0.06, 0.22),
			Vector2(0.19, 0.14),
			Vector2(0.16, 0.11),
		], ctr, 8)
		Shapes.lathe(u, [
			Vector2(0.02, -0.22),
			Vector2(0.14, -0.15),
			Vector2(0.16, -0.11),
		], ctr, 8)
		s.surface(iron_m)
		s.colour = IRON_DARK.srgb_to_linear()
		for k in 4:
			var a := float(k) * PI * 0.5 + PI * 0.25
			var off := Vector3(cos(a) * 0.135, 0.0, sin(a) * 0.135)
			Shapes.beam(s, ctr + off + Vector3(0.0, -0.12, 0.0), ctr + off + Vector3(0.0, 0.12, 0.0),
					Vector2(0.014, 0.014))

		lit.surface(shade_m)
		lit.colour = Color.WHITE
		Shapes.lathe(lit, [
			Vector2(0.06, -0.11),
			Vector2(0.11, -0.06),
			Vector2(0.115, 0.05),
			Vector2(0.075, 0.11),
		], ctr, 8)

		c.lamps.append([ctr, LANTERN_AMBER, strength])

	# Four low stone-cradled amber marker lanterns beside the front steps & aft landing.
	var low_markers: Array[Vector3] = [
		Vector3(-1.85, 0.12, -2.92),
		Vector3(1.85, 0.12, -2.92),
		Vector3(-1.32, 0.24, 9.85),
		Vector3(1.32, 0.24, 9.85),
	]
	for mp: Vector3 in low_markers:
		u.surface(bronze_m)
		u.colour = BRONZE_AGED.srgb_to_linear()
		Shapes.cylinder(u, mp + Vector3(0.0, -0.12, 0.0), 0.10, 0.06, 8)
		Shapes.lathe(u, [Vector2(0.12, 0.11), Vector2(0.06, 0.17), Vector2(0.0, 0.19)], mp, 8)
		lit.surface(shade_m)
		lit.colour = Color.WHITE
		Shapes.cylinder(lit, mp + Vector3(0.0, -0.06, 0.0), 0.072, 0.17, 8)


# --- Zone E: Firmly-anchored glowing mineral crystal clusters (PieceCove, live-bound to setting `crystals`) -----------

static func _mineral_crystal_clusters(c: Object, rng: RandomNumberGenerator, ledge_tops: Array[Vector3]) -> void:
	# 14 sculpted multi-spire hexagonal mineral crystal clusters — EVERY SINGLE ONE firmly embedded in solid rock,
	# reef skirts, mossy islets, or wall-anchored karst ledges (zero floating crystals!):
	# [base_pos, scale, count, lean_inward_dir, root_depth]
	var clusters: Array = [
		# 1-2: Hero monumental crystal outcrops erupting from the wet basalt reef boulders beside the screen pylons!
		[Vector3(-4.82, -0.28, -10.15), 1.38, 10, Vector3(0.35, 0.0, 0.55), 0.95],
		[Vector3(4.82, -0.28, -10.15), 1.38, 10, Vector3(-0.35, 0.0, 0.55), 0.95],
		# 3-4: Intimate crystal clusters nestled on the viewing island's mossy lower terrace shelves!
		[Vector3(-3.38, -0.22, 0.35), 0.90, 9, Vector3(0.20, 0.0, -0.10), 0.55],
		[Vector3(3.42, -0.22, 0.85), 0.86, 9, Vector3(-0.20, 0.0, -0.10), 0.55],
		# 5-6: Emerald water-islet crystal formations crowning the left & right mossy islets!
		[Vector3(-6.05, 0.10, -2.75), 1.15, 9, Vector3(0.45, 0.0, 0.15), 0.85],
		[Vector3(6.35, 0.18, -2.05), 1.18, 9, Vector3(-0.45, 0.0, 0.15), 0.85],
		# 7-8: Grounded on the wet travertine reef skirts at the feet of the flanking forward flowstone columns!
		[Vector3(-7.05, -0.24, -7.25), 1.24, 9, Vector3(0.55, 0.0, 0.35), 1.10],
		[Vector3(7.15, -0.24, -7.05), 1.24, 9, Vector3(-0.55, 0.0, 0.35), 1.10],
		# 9-12: Anchored snugly inside the tops of the solid grounded karst cliff buttresses!
		[ledge_tops[0], 1.18, 8, Vector3(0.65, 0.0, 0.25), 0.32],
		[ledge_tops[1], 1.18, 8, Vector3(-0.65, 0.0, 0.25), 0.32],
		[ledge_tops[2], 1.22, 8, Vector3(0.75, 0.0, 0.05), 0.32],
		[ledge_tops[3], 1.22, 8, Vector3(-0.75, 0.0, 0.05), 0.32],
		# 13-14: Aft grotto crystal formations anchored firmly onto the rear mossy islets beside the boardwalk!
		[Vector3(-4.85, 0.10, 4.60), 1.10, 8, Vector3(0.40, 0.0, -0.30), 0.85],
		[Vector3(5.15, 0.16, 4.20), 1.12, 8, Vector3(-0.40, 0.0, -0.30), 0.85],
	]

	var cove: RoomMesh = c.cove
	var u: RoomMesh = c.u
	cove.surface(c.kit.cove_material())
	var soft_stone: Material = c.soft("stone", true)

	for cl: Array in clusters:
		var base_pos: Vector3 = cl[0]
		var sc: float = float(cl[1])
		var count: int = int(cl[2])
		var lean: Vector3 = cl[3]
		var root_d: float = float(cl[4])
		# Deep wet mineral rock plinth anchoring every crystal cluster seamlessly into rock or below the water!
		u.surface(soft_stone)
		u.colour = BASALT_DARK.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.72 * sc, -root_d),
			Vector2(0.58 * sc, -root_d * 0.35),
			Vector2(0.46 * sc, 0.06),
			Vector2(0.32 * sc, 0.18),
			Vector2(0.0, 0.22),
		], base_pos, 8)

		for k in count:
			var hero := (k == 0)
			var ang := TAU * float(k) / float(maxi(count - 1, 1)) + rng.randf_range(-0.22, 0.22)
			var tilt := rng.randf_range(0.05, 0.16) if hero else rng.randf_range(0.22, 0.68)
			var dir := (Vector3(cos(ang) * sin(tilt), cos(tilt), sin(ang) * sin(tilt)) + lean * 0.25).normalized()
			var h := sc * (rng.randf_range(1.15, 1.48) if hero else rng.randf_range(0.42, 1.02))
			var rad := sc * (rng.randf_range(0.11, 0.15) if hero else rng.randf_range(0.055, 0.105))
			var foot := base_pos + Vector3(cos(ang) * 0.18 * sc, -0.05, sin(ang) * 0.18 * sc)
			_crystal_spire(cove, foot, dir, rad, h)

	# Two live-coloured footlights following kit.cove_colour & kit.cove beside the hero flanking crystal clusters!
	c.footlights.append([Vector3(-4.5, 0.9, -9.5), -1.0, 0.65])
	c.footlights.append([Vector3(4.5, 0.9, -9.5), -1.0, 0.65])


## One sharp 6-sided hexagonal quartz/mineral crystal spire in PieceCove with glowing base->tip gradient.
static func _crystal_spire(cove: RoomMesh, foot: Vector3, dir: Vector3, rad: float, height: float) -> void:
	const SIDES := 6
	var up := dir.normalized()
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var ax := up.cross(ref).normalized()
	var az := ax.cross(up).normalized()
	var shoulder_h := height * 0.74
	var tip := foot + up * height

	var base_lin := CRYSTAL_QUARTZ.srgb_to_linear()
	var col_root := Color(base_lin.r * 0.62, base_lin.g * 0.66, base_lin.b * 0.70, 0.26)
	var col_mid := Color(base_lin.r * 0.92, base_lin.g * 0.96, base_lin.b, 0.84)
	var col_tip := Color(base_lin.r, base_lin.g, base_lin.b, 1.0)

	var ring0 := PackedVector3Array()
	var ring1 := PackedVector3Array()
	for k in SIDES:
		var a := TAU * float(k) / float(SIDES)
		var radial := ax * cos(a) + az * sin(a)
		ring0.append(foot + radial * (rad * 1.08))
		ring1.append(foot + up * shoulder_h + radial * (rad * 0.86))

	for k in SIDES:
		var kn := (k + 1) % SIDES
		var p0 := ring0[k]
		var p1 := ring0[kn]
		var p2 := ring1[kn]
		var p3 := ring1[k]
		var fn := ((p1 - p0).cross(p3 - p0)).normalized()
		var out_mid := (p0 + p1) * 0.5 - foot
		if fn.dot(out_mid) < 0.0:
			fn = -fn
		cove.grid(
			[PackedVector3Array([p0, p1]), PackedVector3Array([p3, p2])],
			[PackedVector3Array([fn, fn]), PackedVector3Array([fn, fn])],
			[PackedColorArray([col_root, col_root]), PackedColorArray([col_mid, col_mid])]
		)
		var t_fn := ((p2 - p3).cross(tip - p3)).normalized()
		if t_fn.dot(out_mid + up * 0.4) < 0.0:
			t_fn = -t_fn
		cove.grid(
			[PackedVector3Array([p3, p2]), PackedVector3Array([tip, tip])],
			[PackedVector3Array([t_fn, t_fn]), PackedVector3Array([t_fn, t_fn])],
			[PackedColorArray([col_mid, col_mid]), PackedColorArray([col_tip, col_tip])]
		)
