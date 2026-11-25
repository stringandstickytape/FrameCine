extends RefCounted

## Sunken rotunda (docs/environments/rooms/sunken_rotunda.md): a dreamlike flooded classical marble Atlantis rotunda
## resting on the sunlit ocean floor beneath shimmering underwater caustics, surrounded by schooling fish,
## bioluminescent jellies, a gliding manta ray, and a rare whale.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, beams, arches, domes and lathed
## shapes; zero people, zero trademarks, CC0 library materials and procedural patterns only.
##
## Pieces (pieces.gd dispatches here; read by domestic builder with shell "kit"):
##   rotunda_hall   the flooded classical marble sanctuary architecture and sunken ruins:
##                  - circular stepped dry marble sanctuary dais (r = 5.8 m, y = 0 at viewer's seat) inlaid with our
##                    procedural mosaic_medallion star rosette and jade/gold border rings, ringed by carved marble steps
##                    descending cleanly into the knee-deep flooded marble peristyle ring canal (r = 5.8..11.6 m)
##                  - 12 towering fluted veined-marble Classical columns on r = 9.2 m (one romantically broken aft-right
##                    with tumbled fluted drums resting on the submerged steps), rounded coffered colonnade arches,
##                    sculpted bronze-accented frieze & dentil cornice ring, and a partially ruined open-sky coffered
##                    dome ring framing a vast central ocean oculus (y = 10.85 m, r = 4.8 m)
##                  - monumental twin carved white-marble & tarnished-bronze screen pylons rising from the forward edge
##                    of the flooded canal with a sculpted wave-scroll architrave, sun-shell tympanum crest, broken
##                    raking pediment, dark matte backing slab, and indirect bronze/crystal cove glow (PieceCove)
##                  - 8 waterproof bronze-and-crystal Atlantis floor lanterns on carved rim pedestals plus 2 pylon-top
##                    crystal braziers (PieceLamps + 8 stand-in / hidden bake lamps, live Warm gold / Sea cyan / Dim)
##                  - sunken terracotta amphorae, tumbled classical frieze fragments, vibrant coral reef clusters and
##                    swaying underwater sea-ferns clinging organically to the outer submerged steps & plinths
##   rotunda_water  live animated ocean-world hall (c.halls, 3 draws total, 0 live lights):
##                  - RotundaWater: mirror-rippling turquoise flooded marble peristyle ring & outer ocean seabed using
##                    res://shaders/env_world_water.gdshader (Procedural.caustic_map(), live clock scaled by Motion,
##                    bright underwater caustics web, screen spill reflection, golden/cyan lantern glints)
##                  - RotundaShafts: sunlit pelagic volumetric light shafts slanting down through the ruined dome oculus
##                    using res://shaders/env_world_shaft.gdshader (in group "env_see_through", live clock, strictly
##                    clear of the picture so blend_layers stays well within budget)
##                  - RotundaAqueducts: distant silhouetted ruined outer aqueduct arches & monoliths (r = 24..36 m)
##                    shifting smoothly into pelagic blue-green mist with setting.water_light

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")

const WATER_SHADER := preload("res://shaders/env_world_water.gdshader")
const SHAFT_SHADER := preload("res://shaders/env_world_shaft.gdshader")
const SEE_THROUGH := "env_see_through"

const PIECES: Array[String] = ["rotunda_hall", "rotunda_water"]

## Rotunda plan geometry (metres; viewer sits at (0, 0, 0) facing -Z; domestic room spans x=-10..10, z=-11..9).
const ROT_C := Vector3(0.0, 0.0, -1.0)
const DAIS_R := 5.80
const WATER_Y := -0.25
const COL_R := 9.20
const COL_COUNT := 12
const COL_SPRING_Y := 5.85
const ENTAB_Y := 7.75
const CORNICE_Y := 8.65
const OCULUS_Y := 11.10
const OCULUS_R := 4.85
## Index of the romantically ruined column on the aft-starboard arc (bay breach spans its flanking arches & dome).
const BROKEN_COL_IDX := 9
const MOTION_FLOOR := 0.25

## Twelve symmetrical column azimuths (degrees clockwise from -Z forward, leaving a wide 66-deg forward screen bay
## and eleven equal 26.73-deg classical arched bays all around the sides and aft).
const COL_ANGLES_DEG: Array[float] = [
	-33.00, -59.73, -86.45, -113.18, -139.91, -166.64,
	166.64, 139.91, 113.18, 86.45, 59.73, 33.00,
]

## Palette (sRGB): sunlit Atlantis veined marble, wet sea-stone, sea-jade inlay, tarnished bronze, terracotta, corals.
const MARBLE_WARM := Color(0.92, 0.90, 0.85)
const MARBLE_CREAM := Color(0.84, 0.83, 0.78)
const MARBLE_COOL := Color(0.70, 0.77, 0.76)
const MARBLE_WET := Color(0.46, 0.56, 0.56)
const MARBLE_SUBMERGED := Color(0.30, 0.44, 0.46)
const MARBLE_BREAK := Color(0.76, 0.74, 0.68)
const JADE_INLAY := Color(0.14, 0.42, 0.44)
const JADE_DEEP := Color(0.09, 0.28, 0.32)
const BRONZE_BRIGHT := Color(0.90, 0.74, 0.38)
const BRONZE_WARM := Color(0.74, 0.58, 0.28)
const BRONZE_VERDIGRIS := Color(0.34, 0.54, 0.48)
const TERRACOTTA := Color(0.68, 0.38, 0.24)
const TERRACOTTA_DARK := Color(0.50, 0.27, 0.17)
const BACKING_DARK := Color(0.03, 0.04, 0.05)
const LANTERN_GOLD := Color(1.0, 0.80, 0.44)

const CORAL_PALETTE: Array[Color] = [
	Color(0.86, 0.38, 0.36), # reef coral pink
	Color(0.86, 0.58, 0.24), # amber staghorn
	Color(0.52, 0.38, 0.72), # sea violet
	Color(0.28, 0.74, 0.66), # luminous seafoam
	Color(0.82, 0.46, 0.54), # rose fan coral
]
const FERN_DEEP := Color(0.10, 0.38, 0.28)
const FERN_BRIGHT := Color(0.20, 0.54, 0.38)


## Live ocean-world hall registered in c.halls: animated water ring, pelagic volumetric shafts & outer aqueduct ruins.
class RotundaWaterHall:
	var kit: Node
	var water_mat: ShaderMaterial
	var shaft_mat: ShaderMaterial
	var aqueduct_mat: StandardMaterial3D
	var water_node: MeshInstance3D
	var shaft_node: MeshInstance3D
	var aqueduct_node: MeshInstance3D
	var _clock := 0.0
	var _water_mode := ""
	var _lantern_mode := ""
	var _playing := false
	## Smoothed palette values for gentle transitions (photosensitivity comfort).
	var _cur_deep := Color(0.02, 0.16, 0.24)
	var _cur_shallow := Color(0.10, 0.48, 0.54)
	var _cur_sky := Color(0.16, 0.56, 0.66)
	var _cur_caustic := Color(0.38, 0.94, 0.98)
	var _cur_caustic_lvl := 0.95
	var _cur_glint := Color(1.0, 0.82, 0.50)
	var _cur_glint_lvl := 0.62
	var _cur_shaft_col := Color(0.36, 0.90, 0.94)
	var _cur_shaft_lvl := 0.48
	var _cur_aq_col := Color(0.11, 0.36, 0.44)
	var _inited := false

	func finish(k: Node) -> void:
		kit = k
		_build_water(k)
		_build_shafts(k)
		_build_aqueducts(k)
		_sync(0.0, true)

	func tick(delta: float) -> void:
		if kit == null or kit.host == null:
			return
		var motion := 1.0
		var mv: Variant = kit.host.setting("motion")
		if mv != null:
			motion = clampf(float(mv), 0.0, 1.0)
		_clock += delta * motion
		if water_mat != null:
			water_mat.set_shader_parameter("clock", _clock)
		if shaft_mat != null:
			shaft_mat.set_shader_parameter("clock", _clock)
		_sync(delta, motion < MOTION_FLOOR or delta <= 0.0)

	func _sync(delta: float, snap: bool) -> void:
		var wm := "sunlit"
		var lm := "gold"
		var playing := false
		if kit != null and kit.host != null:
			var wv: Variant = kit.host.setting("water_light")
			if wv != null:
				wm = str(wv)
			var lv: Variant = kit.host.setting("lanterns")
			if lv != null:
				lm = str(lv)
			if kit.host.get("timeline") != null:
				playing = str(kit.host.timeline.state) in ["starting", "playing", "credits"]

		var t_deep: Color
		var t_shallow: Color
		var t_sky: Color
		var t_caustic: Color
		var t_caustic_lvl: float
		var t_glint_lvl: float
		var t_shaft_col: Color
		var t_shaft_lvl: float
		var t_aq_col: Color

		match wm:
			"sapphire":
				t_deep = Color(0.010, 0.048, 0.140)
				t_shallow = Color(0.040, 0.175, 0.340)
				t_sky = Color(0.085, 0.240, 0.460)
				t_caustic = Color(0.24, 0.64, 0.98)
				t_caustic_lvl = 0.56
				t_glint_lvl = 0.52
				t_shaft_col = Color(0.24, 0.56, 0.92)
				t_shaft_lvl = 0.28
				t_aq_col = Color(0.055, 0.155, 0.310)
			"bioluminescent":
				t_deep = Color(0.005, 0.022, 0.058)
				t_shallow = Color(0.020, 0.120, 0.175)
				t_sky = Color(0.036, 0.130, 0.215)
				t_caustic = Color(0.18, 0.92, 0.80)
				t_caustic_lvl = 0.38
				t_glint_lvl = 0.44
				t_shaft_col = Color(0.18, 0.86, 0.76)
				t_shaft_lvl = 0.16
				t_aq_col = Color(0.032, 0.115, 0.155)
			_: # sunlit
				t_deep = Color(0.020, 0.170, 0.255)
				t_shallow = Color(0.110, 0.500, 0.560)
				t_sky = Color(0.175, 0.590, 0.690)
				t_caustic = Color(0.40, 0.95, 0.98)
				t_caustic_lvl = 0.95
				t_glint_lvl = 0.65
				t_shaft_col = Color(0.42, 0.92, 0.96)
				t_shaft_lvl = 0.46
				t_aq_col = Color(0.115, 0.385, 0.465)

		if playing:
			t_shaft_lvl *= 0.62

		var t_glint: Color
		match lm:
			"cyan":
				t_glint = Color(0.40, 0.96, 0.94)
			"dim":
				t_glint = Color(0.55, 0.78, 0.88)
				t_glint_lvl *= 0.55
			_: # gold
				t_glint = Color(1.0, 0.82, 0.50)

		var k := 1.0 if (snap or not _inited) else clampf(delta / 1.8, 0.0, 1.0)
		_inited = true
		_cur_deep = _cur_deep.lerp(t_deep, k)
		_cur_shallow = _cur_shallow.lerp(t_shallow, k)
		_cur_sky = _cur_sky.lerp(t_sky, k)
		_cur_caustic = _cur_caustic.lerp(t_caustic, k)
		_cur_caustic_lvl = lerpf(_cur_caustic_lvl, t_caustic_lvl, k)
		_cur_glint = _cur_glint.lerp(t_glint, k)
		_cur_glint_lvl = lerpf(_cur_glint_lvl, t_glint_lvl, k)
		_cur_shaft_col = _cur_shaft_col.lerp(t_shaft_col, k)
		_cur_shaft_lvl = lerpf(_cur_shaft_lvl, t_shaft_lvl, k)
		_cur_aq_col = _cur_aq_col.lerp(t_aq_col, k)
		_water_mode = wm
		_lantern_mode = lm
		_playing = playing

		if water_mat != null:
			water_mat.set_shader_parameter("deep_colour", _cur_deep)
			water_mat.set_shader_parameter("shallow_colour", _cur_shallow)
			water_mat.set_shader_parameter("sky_colour", _cur_sky)
			water_mat.set_shader_parameter("caustic_colour", _cur_caustic)
			water_mat.set_shader_parameter("caustic_level", _cur_caustic_lvl)
			water_mat.set_shader_parameter("glint_colour", _cur_glint)
			water_mat.set_shader_parameter("glint_level", _cur_glint_lvl)
		if shaft_mat != null:
			shaft_mat.set_shader_parameter("shaft_colour", _cur_shaft_col)
			shaft_mat.set_shader_parameter("shaft_level", _cur_shaft_lvl)
		if aqueduct_mat != null:
			aqueduct_mat.albedo_color = _cur_aq_col
		if water_node != null and is_instance_valid(water_node):
			water_node.set_meta("water_light", wm)
			water_node.set_meta("lanterns", lm)
			water_node.set_meta("clock", _clock)
			water_node.set_meta("caustic_level", _cur_caustic_lvl)
			water_node.set_meta("shaft_level", _cur_shaft_lvl)

	## Builds the flooded marble peristyle ring canal & outer ocean seabed water sheet (1 opaque draw, 0 blend layers).
	func _build_water(k: Node) -> void:
		var m := ShaderMaterial.new()
		m.shader = WATER_SHADER
		m.set_shader_parameter("caustic_map", Procedural.caustic_map())
		m.set_shader_parameter("house_reference", float(k.room.get("ambient_level")))
		m.set_shader_parameter("ripple_scale", 3.8)
		m.set_shader_parameter("spill_strength", 0.90)
		m.set_shader_parameter("glint_dir", Vector3(-0.18, 0.72, -0.67).normalized())
		m.set_shader_parameter("ambient_floor", 0.44)
		water_mat = m

		var b := RoomMesh.new()
		b.surface(m)
		var radii: Array[float] = [5.65, 6.25, 6.95, 7.80, 8.65, 9.50, 10.50, 11.60, 13.50, 17.50, 24.0, 36.0, 56.0, 92.0, 155.0]
		var segs := 64
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		for ri in radii.size():
			var r := radii[ri]
			var y := WATER_Y - clampf((r - 12.0) / 140.0, 0.0, 1.0) * 0.20
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for si in segs + 1:
				var ang := TAU * float(si % segs) / float(segs)
				var sx := sin(ang)
				var cz := -cos(ang)
				var p := Vector3(ROT_C.x + sx * r, y, ROT_C.z + cz * r)
				row.append(p)
				nrow.append(Vector3.UP)
				# COLOR.r: shallow marble step & canal brightness (subtle submerged flagstone modulation in r=5.8..11.6).
				var shallow := 0.0
				if r <= 6.95:
					shallow = 0.96
				elif r <= 11.60:
					var flag := 0.5 + 0.5 * sin(ang * 24.0) * cos(r * 2.8)
					shallow = lerpf(0.86, 0.62, (r - 6.95) / 4.65) + (flag - 0.5) * 0.14
				else:
					shallow = clampf(0.36 * exp(-(r - 11.6) / 6.5), 0.0, 0.36)
				# COLOR.g: bright oculus caustic pool glow in the forward/flanking canal and beneath the open dome.
				var pool := clampf(exp(-pow((r - 7.8) / 3.4, 2.0)), 0.0, 1.0) * (0.55 + 0.45 * maxf(cz, -0.2))
				crow.append(Color(clampf(shallow, 0.0, 1.0), clampf(pool, 0.0, 1.0), 0.0, 1.0))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		b.grid(rows, norms, cols)
		var mi: MeshInstance3D = k._add_unbaked("RotundaWater", b)
		water_node = mi

	## Builds six sunlit pelagic underwater light shafts slanting through the ruined dome oculus (1 additive draw,
	## in env_see_through, strictly framing the sanctuary & flanking bays without crossing the screen's picture).
	func _build_shafts(k: Node) -> void:
		var m := ShaderMaterial.new()
		m.shader = SHAFT_SHADER
		m.set_shader_parameter("noise_map", SkySys.noise_texture())
		m.set_shader_parameter("edge_softness", 2.1)
		m.set_shader_parameter("wisp_strength", 0.40)
		shaft_mat = m

		# Each shaft: [top_pos, bot_pos, top_radius, bot_radius, color_tint, alpha_weight]
		var defs: Array = [
			# Forward-port and forward-starboard canal shafts framing the twin screen pylons cleanly outside sight line!
			[Vector3(-3.6, 15.8, -5.6), Vector3(-6.4, WATER_Y, -7.2), 0.72, 1.45, Color(0.88, 1.0, 1.0), 0.85],
			[Vector3(3.8, 15.8, -5.4), Vector3(6.5, WATER_Y, -7.0), 0.72, 1.45, Color(0.88, 1.0, 1.0), 0.82],
			# Port and starboard colonnade shafts descending through the oculus into the flooded peristyle arches.
			[Vector3(-4.2, 15.6, -0.8), Vector3(-7.6, WATER_Y, -1.6), 0.85, 1.65, Color(0.82, 0.98, 1.0), 0.78],
			[Vector3(4.2, 15.6, -0.4), Vector3(7.6, WATER_Y, -1.2), 0.82, 1.60, Color(0.82, 0.98, 1.0), 0.76],
			# Overhead central oculus sunbeam terminating gently at y=5.4 above the sanctuary (magical looking UP!).
			[Vector3(-0.6, 16.5, -1.6), Vector3(-2.0, 5.4, -3.2), 1.05, 1.75, Color(0.95, 1.0, 1.0), 0.70],
			# Aft-starboard shaft pouring dramatically through the ruined dome breach onto the broken column!
			[Vector3(4.8, 15.2, 3.8), Vector3(7.4, WATER_Y, 4.6), 0.95, 1.85, Color(0.86, 0.98, 1.0), 0.88],
		]

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sides := 14
		for d: Array in defs:
			var p0: Vector3 = d[0]
			var p1: Vector3 = d[1]
			var r0: float = d[2]
			var r1: float = d[3]
			var col: Color = d[4]
			var aw: float = d[5]
			var axis := (p1 - p0).normalized()
			var right := axis.cross(Vector3.FORWARD)
			if right.length() < 0.05:
				right = axis.cross(Vector3.RIGHT)
			right = right.normalized()
			var fwd := right.cross(axis).normalized()
			var c_top := Color(col.r, col.g, col.b, aw)
			var c_bot := Color(col.r, col.g, col.b, aw * 0.85)
			for i in sides:
				var u0 := float(i) / float(sides)
				var u1 := float(i + 1) / float(sides)
				var a0 := u0 * TAU
				var a1 := u1 * TAU
				var n0 := (right * cos(a0) + fwd * sin(a0)).normalized()
				var n1 := (right * cos(a1) + fwd * sin(a1)).normalized()
				var v00 := p0 + n0 * r0
				var v10 := p0 + n1 * r0
				var v01 := p1 + n0 * r1
				var v11 := p1 + n1 * r1
				# Two triangles per quad (cull_disabled in shader).
				st.set_normal(n0); st.set_uv(Vector2(u0, 0.0)); st.set_color(c_top); st.add_vertex(v00)
				st.set_normal(n1); st.set_uv(Vector2(u1, 0.0)); st.set_color(c_top); st.add_vertex(v10)
				st.set_normal(n1); st.set_uv(Vector2(u1, 1.0)); st.set_color(c_bot); st.add_vertex(v11)
				st.set_normal(n0); st.set_uv(Vector2(u0, 0.0)); st.set_color(c_top); st.add_vertex(v00)
				st.set_normal(n1); st.set_uv(Vector2(u1, 1.0)); st.set_color(c_bot); st.add_vertex(v11)
				st.set_normal(n0); st.set_uv(Vector2(u0, 1.0)); st.set_color(c_bot); st.add_vertex(v01)

		var mesh := st.commit()
		mesh.surface_set_material(0, m)
		var mi: MeshInstance3D = k._add_mesh("RotundaShafts", mesh)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.add_to_group(SEE_THROUGH)
		shaft_node = mi

	static func _pt(radius: float, ang_rad: float, y: float) -> Vector3:
		return Vector3(ROT_C.x + sin(ang_rad) * radius, y, ROT_C.z - cos(ang_rad) * radius)

	## Builds distant silhouetted ruined outer aqueduct arches & monoliths (r = 24..36 m) fading into pelagic blue-green
	## depth (1 opaque unshaded draw, 0 lights, color shifted live with setting.water_light).
	func _build_aqueducts(k: Node) -> void:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_color = _cur_aq_col
		aqueduct_mat = m

		var b := RoomMesh.new()
		b.surface(m)
		# Four sweeping ruined outer aqueduct arcs leaving dead-ahead behind the screen open for the whale!
		# [radius, start_deg, bays, bay_deg, height, broken_end_flag, depth_shade]
		var arcs: Array = [
			[27.0, -76.0, 4, 10.5, 11.8, true, 0.92],   # forward-port aqueduct
			[27.5, 36.0, 4, 10.5, 12.2, true, 0.92],    # forward-starboard aqueduct
			[32.5, -148.0, 5, 10.0, 13.5, false, 0.74], # far port-aft double-tier ruin
			[25.5, 96.0, 4, 11.5, 11.5, true, 0.98],    # starboard-aft visible through the dome breach!
		]
		for arc: Array in arcs:
			var r: float = arc[0]
			var a_start: float = arc[1]
			var bays: int = arc[2]
			var step_deg: float = arc[3]
			var h: float = arc[4]
			var broken: bool = arc[5]
			var shade: float = arc[6]
			var pier_w := 1.05
			var pier_d := 1.15
			var spring_y := h - 2.6

			for i in bays + 1:
				var ang := deg_to_rad(a_start + float(i) * step_deg)
				var p := _pt(r, ang, 0.0)
				var radial := Vector3(sin(ang), 0.0, -cos(ang))
				var tang := Vector3(cos(ang), 0.0, sin(ang))
				var bs := Basis(tang, Vector3.UP, radial)
				var ph := h
				if broken and i == bays:
					ph = h * 0.56
				elif broken and i == 0:
					ph = h * 0.78
				# Subtle vertical gradient: brighter sunlit crown, darker seabed foot.
				b.colour = Color(shade * 0.80, shade * 0.86, shade * 0.90)
				b.box(Vector3(p.x, WATER_Y + ph * 0.5 - 0.6, p.z), Vector3(pier_w, ph + 1.2, pier_d), bs, [RoomMesh.DOWN])
				b.colour = Color(shade * 1.10, shade * 1.14, shade * 1.15)
				b.box(Vector3(p.x, WATER_Y + ph - 0.25, p.z), Vector3(pier_w + 0.36, 0.45, pier_d + 0.36), bs)

			# Arches & entablature lintel spanning between intact piers.
			for i in bays:
				if broken and i == bays - 1:
					continue
				var a0 := deg_to_rad(a_start + float(i) * step_deg)
				var a1 := deg_to_rad(a_start + float(i + 1) * step_deg)
				var p0 := _pt(r, a0, 0.0)
				var p1 := _pt(r, a1, 0.0)
				var chord := p0.distance_to(p1)
				var mid := (p0 + p1) * 0.5
				var tang := (p1 - p0).normalized()
				var radial := tang.cross(Vector3.UP).normalized()
				var bs := Basis(tang, Vector3.UP, radial)
				var r_in := maxf(chord * 0.5 - pier_w * 0.45, 0.8)
				var r_out := r_in + 0.72
				b.colour = Color(shade * 0.98, shade * 1.04, shade * 1.08)
				Shapes.arch(b, Vector3(mid.x, WATER_Y + spring_y, mid.z), r_in, r_out, pier_d * 0.92, 10, bs, 0.0, PI)
				# Continuous upper conduit channel lintel.
				b.colour = Color(shade * 1.16, shade * 1.20, shade * 1.22)
				b.box(Vector3(mid.x, WATER_Y + h - 0.12, mid.z), Vector3(chord + 0.2, 0.85, pier_d + 0.18), bs)

		# Three lone weathered outer monolith pillars / broken obelisks standing in the distant turquoise mist.
		var monoliths: Array = [
			[35.0, -24.0, 9.5, 1.3],
			[36.5, 22.0, 10.8, 1.4],
			[34.0, 174.0, 11.4, 1.5],
		]
		for ml: Array in monoliths:
			var ang := deg_to_rad(float(ml[1]))
			var p := _pt(float(ml[0]), ang, 0.0)
			var mh := float(ml[2])
			var mw := float(ml[3])
			b.colour = Color(0.72, 0.80, 0.86)
			b.box(Vector3(p.x, WATER_Y + mh * 0.5 - 0.5, p.z), Vector3(mw, mh + 1.0, mw),
					Basis(Vector3.UP, ang + 0.2), [RoomMesh.DOWN])

		var mi: MeshInstance3D = k._add_unbaked("RotundaAqueducts", b)
		aqueduct_node = mi


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"rotunda_hall":
			_build_hall(c)
		"rotunda_water":
			c.halls.append(RotundaWaterHall.new())


static func _ring_pt(radius: float, ang_rad: float, y: float) -> Vector3:
	return Vector3(ROT_C.x + sin(ang_rad) * radius, y, ROT_C.z - cos(ang_rad) * radius)


static func _reset_colours(c: Object) -> void:
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE
	c.lit.colour = Color.WHITE
	c.cove.colour = Color.WHITE


# --- Main Sunken Rotunda Architecture --------------------------------------------------------------------------------

static func _build_hall(c: Object) -> void:
	# Slightly coarser lightmap texel keeps the grand 20 m marble rotunda & coffered dome atlas compact and fast to bake.
	c.s.texel = 0.14
	_build_sanctuary_dais(c)
	_build_colonnade_and_arches(c)
	_build_entablature_and_dome(c)
	_build_screen_pylons(c)
	_build_lanterns_and_coves(c)
	_build_ruins_and_reef(c)
	_reset_colours(c)


## Builds the circular stepped dry Atlantis marble sanctuary dais (r = 5.8 m, y = 0 at viewer's seat) inlaid with
## Procedural.maps("mosaic_medallion"), carved sea-jade & tarnished-bronze rim bands, four ceremonial stepped canal
## landings descending into the flooded marble peristyle water, and subtle underwater cove glow under the rim lip.
static func _build_sanctuary_dais(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# 1. Central circular Atlantis mosaic medallion disk (r = 4.25 m, centered at ROT_C = (0, 0, -1.0)).
	#    Uses Procedural.maps("mosaic_medallion") directly on a white_marble house material so its authentic cream,
	#    sea-jade, warm gold star rosette and mortar grout joints render crisply without clipping.
	var mos_r := 4.25
	var mos_tiling := mos_r * 2.0 / 0.865
	var mos_mat: ShaderMaterial = c.kit._light.library("white_marble", Color(0.95, 0.96, 0.94),
			{"tiling": mos_tiling, "spill": 1.15})
	var mp: Dictionary = Procedural.maps("mosaic_medallion")
	mos_mat.set_shader_parameter("albedo_map", mp["albedo"])
	mos_mat.set_shader_parameter("normal_map", mp["normal"])
	mos_mat.set_shader_parameter("orm_map", mp["orm"])
	mos_mat.set_shader_parameter("normal_strength", 1.0)
	mos_mat.set_shader_parameter("uv_offset",
			Vector2(0.5 - ROT_C.x / mos_tiling, 0.5 - ROT_C.z / mos_tiling))

	s.surface(mos_mat)
	s.colour = Color.WHITE
	var segs := 40
	var mos_pts: Array = []
	for i in segs:
		var ang := TAU * float(i) / float(segs)
		mos_pts.append(_ring_pt(mos_r, ang, 0.002))
	s.face(mos_pts, Vector3.UP)

	# 2. Concentric dry veined-marble outer promenade ring (r = 4.25 .. 5.80 m) framed by bronze & sea-jade rings,
	#    descending in two graceful wet marble steps into the knee-deep turquoise canal (y = 0.0 -> -0.11 -> -0.22 -> -0.52).
	var marble: Material = c.tinted("stone")
	var bronze: Material = c.shiny("gilt", 0.88, 0.56, 0.22)

	# Flat outer marble deck rings: [r_in, r_out, y, colour]
	var deck_rings: Array = [
		[4.24, 4.44, 0.003, JADE_INLAY],
		[4.44, 5.44, 0.001, MARBLE_WARM],
		[5.44, 5.60, 0.003, JADE_DEEP],
		[5.60, DAIS_R, 0.002, MARBLE_CREAM],
		# First broad wet marble step descending toward the canal (y = -0.11).
		[DAIS_R, 6.28, -0.11, MARBLE_COOL],
		# Second awash marble step barely kissing the rippling turquoise canal (y = -0.22, visible wet stone lip!).
		[6.28, 6.72, -0.22, MARBLE_WET],
	]
	s.surface(marble)
	for dr: Array in deck_rings:
		s.colour = (dr[3] as Color).srgb_to_linear()
		_flat_ring(s, float(dr[0]), float(dr[1]), float(dr[2]), segs)

	# Vertical marble risers & sculpted overhanging bullnose rim lips around the dais steps.
	var risers: Array = [
		[DAIS_R, -0.11, 0.002, MARBLE_CREAM],
		[6.28, -0.22, -0.11, MARBLE_COOL],
		[6.72, -0.55, -0.22, MARBLE_SUBMERGED],
	]
	for rs: Array in risers:
		s.colour = (rs[3] as Color).srgb_to_linear()
		_cyl_wall(s, float(rs[0]), float(rs[1]), float(rs[2]), segs, true)

	# Gleaming inlaid tarnished-bronze circular border rings at the mosaic collar (r=4.26) & dais lip (r=5.76).
	u.surface(bronze)
	u.colour = BRONZE_BRIGHT.srgb_to_linear()
	_flat_ring(u, 4.22, 4.28, 0.006, segs)
	_flat_ring(u, 5.58, 5.63, 0.006, segs)
	_flat_ring(u, DAIS_R - 0.04, DAIS_R + 0.02, 0.007, segs)
	_cyl_wall(u, DAIS_R + 0.02, -0.022, 0.007, segs, true)

	# 3. Low sculpted classical marble parapet curb segments along the dais perimeter between the four ceremonial
	#    stepped landings (North -26..+26 deg, East 72..108 deg, South 154..206 deg, West -108..-72 deg open!).
	#    Curb height is only 0.14 m so it enriches the sanctuary edge without ever obstructing any sight line.
	var curb_arcs: Array = [
		[28.0, 70.0],
		[110.0, 152.0],
		[-152.0, -110.0],
		[-70.0, -28.0],
	]
	s.surface(marble)
	for ca: Array in curb_arcs:
		var a0 := deg_to_rad(float(ca[0]))
		var a1 := deg_to_rad(float(ca[1]))
		var steps_c := 8
		s.colour = MARBLE_CREAM.srgb_to_linear()
		for i in steps_c:
			var t0 := lerpf(a0, a1, float(i) / float(steps_c))
			var t1 := lerpf(a0, a1, float(i + 1) / float(steps_c))
			var p0 := _ring_pt(DAIS_R - 0.14, t0, 0.0)
			var p1 := _ring_pt(DAIS_R - 0.14, t1, 0.0)
			var mid := (p0 + p1) * 0.5
			var tang := (p1 - p0).normalized()
			var radial := tang.cross(Vector3.UP).normalized()
			var chord := p0.distance_to(p1) + 0.03
			var bs := Basis(tang, Vector3.UP, radial)
			s.box(Vector3(mid.x, 0.075, mid.z), Vector3(chord, 0.15, 0.24), bs, [RoomMesh.DOWN])
			u.surface(bronze)
			u.colour = BRONZE_WARM.srgb_to_linear()
			u.box(Vector3(mid.x, 0.156, mid.z), Vector3(chord + 0.01, 0.018, 0.12), bs, [RoomMesh.DOWN])
		# Carved end-bollard cheek blocks flanking the landings.
		for ea: float in [a0, a1]:
			var ep := _ring_pt(DAIS_R - 0.14, ea, 0.0)
			var eb := Basis(Vector3.UP, -ea)
			s.surface(marble)
			s.colour = MARBLE_WARM.srgb_to_linear()
			s.box(Vector3(ep.x, 0.12, ep.z), Vector3(0.32, 0.24, 0.34), eb, [RoomMesh.DOWN])

	# 4. Warm architectural cove wash tucked beneath the dais rim lip, casting glowing reflections across the wet steps!
	cove.surface(c.kit.cove_material())
	var cove_lin := Color(0.95, 0.90, 0.80).srgb_to_linear()
	var a_top := PackedVector3Array()
	var a_bot := PackedVector3Array()
	var ns := PackedVector3Array()
	var c_top := PackedColorArray()
	var c_bot := PackedColorArray()
	for i in segs + 1:
		var ang := TAU * float(i % segs) / float(segs)
		var out := Vector3(sin(ang), 0.0, -cos(ang))
		a_top.append(_ring_pt(DAIS_R + 0.012, ang, -0.025))
		a_bot.append(_ring_pt(DAIS_R + 0.012, ang, -0.105))
		ns.append(out)
		c_top.append(Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.82))
		c_bot.append(Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.08))
	cove.grid([a_top, a_bot], [ns, ns], [c_top, c_bot])


## Builds the 12 towering fluted veined-marble Classical columns on r = 9.2 m and the 11 rounded coffered colonnade
## arches spanning between them (leaving the wide 66-deg forward screen bay open and romantically breaking one
## aft-starboard column & its flanking arches to frame the sunlit deep ocean).
static func _build_colonnade_and_arches(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var marble: Material = c.tinted("stone")
	var bronze: Material = c.shiny("gilt", 0.88, 0.56, 0.22)
	var stone_alt: Material = c.tinted("plaster")

	for idx in COL_COUNT:
		var ang := deg_to_rad(COL_ANGLES_DEG[idx])
		var pos := _ring_pt(COL_R, ang, 0.0)
		var bs := Basis(Vector3.UP, -ang)
		var broken := (idx == BROKEN_COL_IDX)

		# 1. Stepped submerged & emergent marble pedestal plinth rising out of the y = -0.25 canal.
		s.surface(marble)
		s.colour = MARBLE_SUBMERGED.srgb_to_linear()
		s.box(Vector3(pos.x, -0.34, pos.z), Vector3(1.52, 0.42, 1.52), bs, [RoomMesh.DOWN])
		s.colour = MARBLE_WET.srgb_to_linear()
		s.box(Vector3(pos.x, 0.04, pos.z), Vector3(1.32, 0.36, 1.32), bs, [RoomMesh.DOWN])
		s.colour = MARBLE_CREAM.srgb_to_linear()
		s.box(Vector3(pos.x, 0.34, pos.z), Vector3(1.16, 0.24, 1.16), bs, [RoomMesh.DOWN])

		# 2. Attic double-torus marble column base (y = 0.46 .. 0.84).
		var base_prof := [
			Vector2(0.54, 0.46), Vector2(0.56, 0.54), Vector2(0.47, 0.61),
			Vector2(0.51, 0.69), Vector2(0.49, 0.76), Vector2(0.42, 0.84),
		]
		Shapes.lathe(s, base_prof, pos, 16, bs)

		# 3. Fluted entasis-tapered Classical marble shaft rising cleanly to the capital necking!
		var shaft_top := 3.45 if broken else 5.20
		s.surface(marble)
		_fluted_shaft(s, pos, 0.84, shaft_top, 0.41, 0.37 if broken else 0.35, 12, bs, MARBLE_WARM, MARBLE_COOL)

		if broken:
			# Jagged fractured marble crown on the broken column shaft.
			s.surface(marble)
			s.colour = MARBLE_BREAK.srgb_to_linear()
			s.box(Vector3(pos.x - 0.08, shaft_top + 0.12, pos.z + 0.05), Vector3(0.46, 0.32, 0.42),
					bs * Basis(Vector3.RIGHT, 0.24) * Basis(Vector3.BACK, -0.18))
			s.box(Vector3(pos.x + 0.14, shaft_top + 0.04, pos.z - 0.08), Vector3(0.32, 0.18, 0.36),
					bs * Basis(Vector3.RIGHT, -0.20))
		else:
			# Tarnished-bronze astragal necking ring + flared sculpted Classical capital + square abacus at y=5.85 m.
			u.surface(bronze)
			u.colour = BRONZE_BRIGHT.srgb_to_linear()
			Shapes.lathe(u, [Vector2(0.355, 5.16), Vector2(0.395, 5.21), Vector2(0.355, 5.26)], pos, 16, bs)

			s.surface(marble)
			s.colour = MARBLE_WARM.srgb_to_linear()
			var cap_prof := [
				Vector2(0.35, 5.26), Vector2(0.38, 5.34), Vector2(0.47, 5.52),
				Vector2(0.55, 5.66), Vector2(0.57, 5.71),
			]
			Shapes.lathe(s, cap_prof, pos, 16, bs)
			# Four sculpted corner volute scrolls & bronze echinus accents under the square abacus.
			u.colour = BRONZE_WARM.srgb_to_linear()
			for cx: float in [-0.39, 0.39]:
				for cz: float in [-0.39, 0.39]:
					var vp := pos + bs * Vector3(cx, 5.64, cz)
					u.box(vp, Vector3(0.13, 0.13, 0.13), bs)
			# Moulded square marble abacus block (top flush at COL_SPRING_Y = 5.85 m so arches spring right off it!)
			# plus a sculpted classical impost pier rising solidly from y=5.85 to ENTAB_Y=7.75 m so adjacent arches and
			# entablature lock seamlessly with zero spandrel gaps!
			s.colour = MARBLE_CREAM.srgb_to_linear()
			s.box(Vector3(pos.x, 5.78, pos.z), Vector3(1.16, 0.14, 1.16), bs)
			s.colour = MARBLE_WARM.srgb_to_linear()
			s.box(Vector3(pos.x, 6.80, pos.z), Vector3(0.86, 1.90, 0.78), bs)
			s.colour = MARBLE_CREAM.srgb_to_linear()
			s.box(Vector3(pos.x, 7.62, pos.z), Vector3(1.00, 0.24, 0.90), bs)
			u.colour = BRONZE_BRIGHT.srgb_to_linear()
			u.box(Vector3(pos.x, 7.46, pos.z), Vector3(0.94, 0.055, 0.84), bs)

		# Physics box strictly around each column shaft (at r = 9.2 m, far clear of (0,0,0) and all sight lines).
		var col_h := (shaft_top + 0.4) if broken else ENTAB_Y
		c.shapes.append(PhysicsShapes.box(Vector3(pos.x, col_h * 0.5, pos.z), Vector3(1.05, col_h, 1.05), bs))

	# 4. Rounded Classical colonnade arches spanning the 11 bays around the sides and aft!
	#    Column order around the circle (excluding the wide forward bay between index 11 (+33 deg) and index 0 (-33 deg)):
	#    pairs (0,1), (1,2), (2,3), (3,4), (4,5), (5,6), (6,7), (7,8), (8,9), (9,10), (10,11).
	for b_i in COL_COUNT - 1:
		var i0 := b_i
		var i1 := b_i + 1
		var a0 := deg_to_rad(COL_ANGLES_DEG[i0])
		var a1 := deg_to_rad(COL_ANGLES_DEG[i1])
		var p0 := _ring_pt(COL_R, a0, 0.0)
		var p1 := _ring_pt(COL_R, a1, 0.0)
		var mid := (p0 + p1) * 0.5
		var tang := (p1 - p0).normalized()
		var radial := tang.cross(Vector3.UP).normalized()
		# Ensure radial points outward from ROT_C.
		if radial.dot((mid - ROT_C).normalized()) < 0.0:
			radial = -radial
			tang = -tang
		var bs := Basis(tang, Vector3.UP, radial)
		var chord := p0.distance_to(p1)
		var r_in := chord * 0.5 - 0.44
		var r_out := r_in + 0.44
		var spring_c := Vector3(mid.x, COL_SPRING_Y, mid.z)

		# Bays flanking the broken column break off cleanly into jagged cantilevered stone haunches attached to the intact peer!
		if i0 == BROKEN_COL_IDX or i1 == BROKEN_COL_IDX:
			var intact_p := p0 if i1 == BROKEN_COL_IDX else p1
			var at_plus := (intact_p - mid).dot(tang) > 0.0
			s.surface(marble)
			s.colour = MARBLE_BREAK.srgb_to_linear()
			var from_a := 0.0 if at_plus else PI * 0.66
			var to_a := PI * 0.34 if at_plus else PI
			Shapes.arch(s, spring_c, r_in, r_out, 0.72, 5, bs, from_a, to_a)
			continue

		# Intact semicircular moulded marble arch + projecting inner archivolt trim + keystone + bronze boss!
		s.surface(marble)
		s.colour = MARBLE_WARM.srgb_to_linear()
		Shapes.arch(s, spring_c, r_in, r_out, 0.76, 12, bs, 0.0, PI)
		s.colour = MARBLE_CREAM.srgb_to_linear()
		Shapes.arch(s, spring_c - radial * 0.41, r_in - 0.04, r_in + 0.17, 0.09, 12, bs, 0.0, PI, ["front", "back", "inner", "outer"])
		var crown_p := spring_c + Vector3(0.0, (r_in + r_out) * 0.5 + 0.04, 0.0)
		s.colour = MARBLE_WARM.srgb_to_linear()
		s.box(crown_p, Vector3(0.36, 0.56, 0.90), bs)
		u.surface(bronze)
		u.colour = BRONZE_BRIGHT.srgb_to_linear()
		u.box(crown_p - radial * 0.46, Vector3(0.19, 0.22, 0.05), bs)

		# Spandrel masonry blocks neatly filling the haunches between the arch extrados, impost piers and entablature.
		s.surface(stone_alt)
		s.colour = MARBLE_COOL.srgb_to_linear()
		for sd: float in [-1.0, 1.0]:
			var sx := sd * (chord * 0.34)
			s.box(Vector3(mid.x, ENTAB_Y - 0.56, mid.z) + tang * sx, Vector3(chord * 0.32, 1.12, 0.66), bs)


## Builds the continuous circular classical entablature (architrave, bronze-accented frieze, dentil cornice) and the
## partially ruined open-sky coffered dome ring framing the vast central ocean oculus (y = 10.85 m, r = 4.85 m).
static func _build_entablature_and_dome(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var marble: Material = c.tinted("stone")
	var stone_alt: Material = c.tinted("plaster")
	var bronze: Material = c.shiny("gilt", 0.88, 0.56, 0.22)

	# Ruined breach spans azimuth +63..+110 deg (strictly between intact columns at +59.73 and +113.18 deg, directly
	# over the broken starboard column at +86.45 deg!), opening a dramatic slice of sunlit ocean into the colonnade.
	var breach_a0 := 63.0
	var breach_a1 := 110.0

	# 1. Circular Classical Entablature Ring (y = 7.75 .. 8.65 m) built in 32 crisp facets.
	var segs := 32
	for i in segs:
		var deg0 := -180.0 + 360.0 * float(i) / float(segs)
		var deg1 := -180.0 + 360.0 * float(i + 1) / float(segs)
		var deg_m := (deg0 + deg1) * 0.5
		if deg_m > breach_a0 and deg_m < breach_a1:
			continue
		var a0 := deg_to_rad(deg0)
		var a1 := deg_to_rad(deg1)
		var p0 := _ring_pt(COL_R, a0, 0.0)
		var p1 := _ring_pt(COL_R, a1, 0.0)
		var mid := (p0 + p1) * 0.5
		var tang := (p1 - p0).normalized()
		var radial := (mid - ROT_C)
		radial.y = 0.0
		radial = radial.normalized()
		var bs := Basis(tang, Vector3.UP, radial)
		var chord := p0.distance_to(p1) + 0.08

		# Lower architrave beam (y = 7.75 .. 8.05).
		s.surface(marble)
		s.colour = MARBLE_CREAM.srgb_to_linear()
		s.box(Vector3(mid.x, ENTAB_Y + 0.15, mid.z), Vector3(chord, 0.30, 1.02), bs)
		# Recessed jade-tinted classical frieze band (y = 8.05 .. 8.40).
		s.surface(stone_alt)
		s.colour = JADE_DEEP.srgb_to_linear()
		s.box(Vector3(mid.x, ENTAB_Y + 0.47, mid.z), Vector3(chord, 0.35, 0.90), bs)
		# Projecting upper dentil cornice crown (y = 8.40 .. 8.68).
		s.surface(marble)
		s.colour = MARBLE_WARM.srgb_to_linear()
		s.box(Vector3(mid.x, ENTAB_Y + 0.79, mid.z), Vector3(chord + 0.04, 0.28, 1.24), bs)

		# Tarnished-bronze classical triglyph & wave boss ornaments spaced cleanly along the inner frieze face!
		u.surface(bronze)
		u.colour = BRONZE_BRIGHT.srgb_to_linear()
		u.box(Vector3(mid.x, ENTAB_Y + 0.47, mid.z) - radial * 0.47, Vector3(0.24, 0.22, 0.05), bs)
		u.colour = BRONZE_WARM.srgb_to_linear()
		u.box(Vector3(mid.x, ENTAB_Y + 0.64, mid.z) - radial * 0.54, Vector3(chord + 0.02, 0.045, 0.045), bs)
		u.box(Vector3(mid.x, ENTAB_Y + 0.29, mid.z) - radial * 0.52, Vector3(chord + 0.02, 0.040, 0.040), bs)

	# Weathered jagged fracture blocks stepping out from both broken entablature ends so the breach reads authentically
	# crumbled by ancient collapse rather than flat-cut!
	s.surface(marble)
	s.colour = MARBLE_BREAK.srgb_to_linear()
	for edge_deg: float in [breach_a0 + 2.5, breach_a1 - 2.5]:
		var ea := deg_to_rad(edge_deg)
		var ep := _ring_pt(COL_R, ea, 0.0)
		var ebs := Basis(Vector3.UP, -ea)
		s.box(Vector3(ep.x, ENTAB_Y + 0.14, ep.z), Vector3(0.68, 0.34, 0.86), ebs * Basis(Vector3.BACK, 0.14))
		s.box(Vector3(ep.x, ENTAB_Y + 0.44, ep.z), Vector3(0.46, 0.30, 0.72), ebs * Basis(Vector3.BACK, -0.10))

	# 2. Partially Ruined Open-Sky Coffered Dome Ring (r = 9.05 -> OCULUS_R = 4.85, y = 8.65 -> OCULUS_Y = 11.10 m)!
	#    16 radial marble ribs + 3 concentric stepped coffer rings + golden bronze coffer rosettes + moulded oculus ring.
	var ribs := 16
	var rings := 3
	var ring_r: Array[float] = [9.05, 7.80, 6.38, OCULUS_R]
	var ring_y: Array[float] = [CORNICE_Y, 9.68, 10.54, OCULUS_Y]

	for i in ribs:
		var deg0 := -180.0 + 360.0 * float(i) / float(ribs)
		var deg1 := -180.0 + 360.0 * float(i + 1) / float(ribs)
		var deg_m := (deg0 + deg1) * 0.5
		var a0 := deg_to_rad(deg0)
		var a1 := deg_to_rad(deg1)

		# Determine how many coffer tiers survive in this bay (ruined jagged silhouette around the breach!).
		var max_tier := rings
		if deg_m > breach_a0 + 6.0 and deg_m < breach_a1 - 6.0:
			max_tier = 0 # completely open to sunlit ocean water!
		elif deg_m > breach_a0 - 16.0 and deg_m < breach_a1 + 16.0:
			max_tier = 1 # jagged half-ruined stepped coffer edge!
		elif deg_m > 122.0 and deg_m < 152.0:
			max_tier = 2 # weathered stepped transition back to the intact dome!

		# Radial marble dome rib on edge a0 (if either adjacent bay survives to that tier).
		var rib_tiers := max_tier
		if deg0 > breach_a0 + 6.0 and deg0 < breach_a1 - 6.0:
			rib_tiers = 0
		for ti in rib_tiers:
			var p0 := _ring_pt(ring_r[ti], a0, ring_y[ti])
			var p1 := _ring_pt(ring_r[ti + 1], a0, ring_y[ti + 1])
			s.surface(marble)
			s.colour = MARBLE_WARM.srgb_to_linear()
			Shapes.beam(s, p0, p1, Vector2(0.34, 0.34), Vector3.UP)

		# Concentric coffered dome bays between a0 and a1!
		for ti in max_tier:
			var r_lo := ring_r[ti]
			var r_hi := ring_r[ti + 1]
			var y_lo := ring_y[ti]
			var y_hi := ring_y[ti + 1]
			var p00 := _ring_pt(r_lo, a0, y_lo)
			var p10 := _ring_pt(r_lo, a1, y_lo)
			var p11 := _ring_pt(r_hi, a1, y_hi)
			var p01 := _ring_pt(r_hi, a0, y_hi)
			var mid := (p00 + p10 + p11 + p01) * 0.25
			var n_in := ((p10 - p00).cross(p01 - p00)).normalized()
			if n_in.dot(ROT_C - mid) < 0.0:
				n_in = -n_in

			# Horizontal ring purlin rib separating each tier of coffers.
			s.surface(marble)
			s.colour = MARBLE_CREAM.srgb_to_linear()
			Shapes.beam(s, p01, p11, Vector2(0.28, 0.30), Vector3.UP)

			# Outer marble coffer surround frame + recessed stepped inner coffer back!
			var q00 := p00.lerp(mid, 0.24) - n_in * 0.14
			var q10 := p10.lerp(mid, 0.24) - n_in * 0.14
			var q11 := p11.lerp(mid, 0.24) - n_in * 0.14
			var q01 := p01.lerp(mid, 0.24) - n_in * 0.14

			# Four sloped bevel walls framing the sunken coffer (catches bright caustics on upward-sloped bevels!).
			s.colour = MARBLE_CREAM.srgb_to_linear()
			s.face([p00, p10, q10, q00], ((p10 - p00).cross(q00 - p00)).normalized())
			s.face([p10, p11, q11, q10], ((p11 - p10).cross(q10 - p10)).normalized())
			s.face([p11, p01, q01, q11], ((p01 - p11).cross(q11 - p11)).normalized())
			s.face([p01, p00, q00, q01], ((p00 - p01).cross(q01 - p01)).normalized())

			# Recessed coffer back panel (cool sea-tinted marble) + gilded bronze rosette boss in its center!
			s.surface(stone_alt)
			s.colour = (MARBLE_COOL if ti % 2 == 0 else JADE_DEEP.lerp(MARBLE_COOL, 0.65)).srgb_to_linear()
			s.face([q00, q10, q11, q01], n_in)
			# Outer shell cap behind coffer so dome reads solid from below & through the breach.
			s.surface(marble)
			s.colour = MARBLE_WET.srgb_to_linear()
			s.face([p00 - n_in * 0.24, p01 - n_in * 0.24, p11 - n_in * 0.24, p10 - n_in * 0.24], -n_in)

			# Tarnished-gold central coffer rosette boss!
			var ross := (q00 + q10 + q11 + q01) * 0.25 + n_in * 0.05
			var tang := (p10 - p00).normalized()
			var up_c := tang.cross(n_in).normalized()
			var bs_c := Basis(tang, up_c, n_in)
			u.surface(bronze)
			u.colour = BRONZE_BRIGHT.srgb_to_linear()
			u.box(ross, Vector3(0.32, 0.32, 0.08), bs_c)
			u.colour = BRONZE_WARM.srgb_to_linear()
			u.box(ross + n_in * 0.04, Vector3(0.18, 0.18, 0.07), bs_c * Basis(Vector3.BACK, PI * 0.25))

		# 3. Thick moulded circular marble & bronze-rimmed Oculus Collar along every intact top bay!
		if max_tier == rings:
			var oc0 := _ring_pt(OCULUS_R, a0, OCULUS_Y)
			var oc1 := _ring_pt(OCULUS_R, a1, OCULUS_Y)
			var omid := (oc0 + oc1) * 0.5
			var otang := (oc1 - oc0).normalized()
			var orad := (omid - ROT_C)
			orad.y = 0.0
			orad = orad.normalized()
			var obs := Basis(otang, Vector3.UP, orad)
			var ochord := oc0.distance_to(oc1) + 0.14
			s.surface(marble)
			s.colour = MARBLE_WARM.srgb_to_linear()
			s.box(Vector3(omid.x, OCULUS_Y + 0.12, omid.z) + orad * 0.26, Vector3(ochord, 0.42, 0.68), obs)
			u.surface(bronze)
			u.colour = BRONZE_BRIGHT.srgb_to_linear()
			u.box(Vector3(omid.x, OCULUS_Y + 0.02, omid.z) - orad * 0.09, Vector3(ochord + 0.02, 0.14, 0.08), obs)


## Builds the monumental twin carved white-marble & tarnished-bronze screen pylons rising from the forward edge of the
## flooded canal (z = -10.2 m, framing the 6.2 x 3.49 m screen cleanly with >0.25 m sight-line margin from EVERY seat!),
## carved wave-scroll architrave, sun-shell tympanum crest, broken raking pediment, and dark backing slab.
static func _build_screen_pylons(c: Object) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 2.75, -10.2)))
	var sc_sz: Vector2 = scr.get("size", Vector2(6.2, 3.49))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var cz := sc_xf.origin.z
	var hw := sc_sz.x * 0.5   # 3.10 m
	var hh := sc_sz.y * 0.5   # 1.745 m
	var sc_bot := cy - hh     # 1.005 m
	var sc_top := cy + hh     # 4.495 m

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var marble: Material = c.tinted("stone")
	var stone_alt: Material = c.tinted("plaster")
	var bronze: Material = c.shiny("gilt", 0.88, 0.56, 0.22)
	var backing: Material = c.tinted("fabric")

	# 1. Submerged & emergent stepped classical marble screen terrace plinth rising out of the flooded canal.
	s.surface(marble)
	s.colour = MARBLE_SUBMERGED.srgb_to_linear()
	s.box(Vector3(cx, -0.35, cz - 0.10), Vector3(sc_sz.x + 3.40, 0.44, 1.35), Basis(), [RoomMesh.DOWN])
	s.colour = MARBLE_WET.srgb_to_linear()
	s.box(Vector3(cx, 0.12, cz - 0.10), Vector3(sc_sz.x + 3.00, 0.50, 1.15), Basis(), [RoomMesh.DOWN])
	s.colour = MARBLE_CREAM.srgb_to_linear()
	s.box(Vector3(cx, 0.62, cz - 0.12), Vector3(sc_sz.x + 2.60, 0.52, 0.92), Basis(), [RoomMesh.DOWN])
	# Sculpted altar-ledge cornice lip directly under the picture (top at 0.94 m, cleanly below sc_bot = 1.005 m).
	s.colour = MARBLE_WARM.srgb_to_linear()
	s.box(Vector3(cx, 0.90, cz - 0.08), Vector3(sc_sz.x + 2.84, 0.08, 1.04))

	# Recessed sea-jade inlay dado panels & tarnished-bronze wave bands across the front of the screen plinth.
	s.surface(stone_alt)
	s.colour = JADE_INLAY.srgb_to_linear()
	for k in 5:
		var px := cx - 2.40 + float(k) * 1.20
		s.box(Vector3(px, 0.60, cz + 0.35), Vector3(0.92, 0.32, 0.04))
	u.surface(bronze)
	u.colour = BRONZE_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx, 0.945, cz + 0.42), Vector3(sc_sz.x + 2.86, 0.028, 0.032))
	u.box(Vector3(cx, 0.38, cz + 0.45), Vector3(sc_sz.x + 2.96, 0.028, 0.032))

	# 2. Dark matte screen backing slab strictly behind the picture plane (front face at cz - 0.06 m).
	s.surface(backing)
	s.colour = BACKING_DARK.srgb_to_linear()
	s.box(Vector3(cx, cy, cz - 0.12), Vector3(sc_sz.x + 0.16, sc_sz.y + 0.12, 0.12))
	# Slim tarnished-bronze outer frame bezel surrounding the picture (strictly outside hw + 0.06 & hh + 0.05).
	u.surface(bronze)
	u.colour = BRONZE_WARM.srgb_to_linear()
	var bt := 0.07
	for sd: float in [-1.0, 1.0]:
		u.box(Vector3(cx + sd * (hw + 0.08 + bt * 0.5), cy, cz - 0.04), Vector3(bt, sc_sz.y + 0.24, 0.09))
	u.box(Vector3(cx, sc_bot - 0.04 - bt * 0.5, cz - 0.04), Vector3(sc_sz.x + 0.30, bt, 0.09))
	u.box(Vector3(cx, sc_top + 0.04 + bt * 0.5, cz - 0.04), Vector3(sc_sz.x + 0.30, bt, 0.09))

	# 3. Twin monumental carved white-marble & tarnished-bronze Atlantis screen pylons (x = +-3.88 m, inner edge +-3.28 m).
	for sd: float in [-1.0, 1.0]:
		var px := cx + sd * (hw + 0.78) # +-3.88 m
		# Main carved veined-marble pylon shaft (width 1.20 m -> inner face at +-3.28 m, 18 cm outside screen edge!).
		s.surface(marble)
		s.colour = MARBLE_WARM.srgb_to_linear()
		s.box(Vector3(px, 3.05, cz - 0.14), Vector3(1.20, 4.30, 0.84), Basis(), [RoomMesh.DOWN])
		# Paired engaged fluted half-pilasters flanking each pylon's recessed sea-jade panel.
		s.colour = MARBLE_CREAM.srgb_to_linear()
		for dx: float in [-0.42, 0.42]:
			s.box(Vector3(px + dx, 3.05, cz + 0.31), Vector3(0.24, 4.10, 0.12))
		# Recessed vertical sea-jade tablet inlay on each pylon face!
		s.surface(stone_alt)
		s.colour = JADE_INLAY.srgb_to_linear()
		s.box(Vector3(px, 3.02, cz + 0.29), Vector3(0.52, 3.62, 0.04))
		# Stepped classical pylon cornice cap (y = 5.20 .. 5.64 m).
		s.surface(marble)
		s.colour = MARBLE_WARM.srgb_to_linear()
		s.box(Vector3(px, 5.28, cz - 0.14), Vector3(1.36, 0.22, 0.98))
		s.box(Vector3(px, 5.50, cz - 0.14), Vector3(1.52, 0.24, 1.12))

		# Tarnished-bronze vertical inlay flutes, diamond sea-medallions & capital bands on each pylon!
		u.surface(bronze)
		u.colour = BRONZE_BRIGHT.srgb_to_linear()
		for dx: float in [-0.42, 0.42]:
			u.box(Vector3(px + dx, 3.05, cz + 0.38), Vector3(0.036, 3.85, 0.025))
		for my: float in [1.75, 3.02, 4.28]:
			u.box(Vector3(px, my, cz + 0.33), Vector3(0.22, 0.22, 0.035), Basis(Vector3.BACK, PI * 0.25))
		u.box(Vector3(px, 5.15, cz - 0.12), Vector3(1.38, 0.055, 0.96))
		u.box(Vector3(px, 0.96, cz - 0.12), Vector3(1.38, 0.055, 0.96))

		# Physics box strictly around each pylon.
		c.shapes.append(PhysicsShapes.box(Vector3(px, 2.85, cz - 0.14), Vector3(1.24, 5.70, 0.90), Basis()))

	# 4. Carved Wave-Scroll Architrave & Broken Pediment Crown spanning above the picture (y = 4.64 .. 5.75 m)!
	var arch_w := sc_sz.x + 2.84 # 9.04 m
	s.surface(marble)
	s.colour = MARBLE_CREAM.srgb_to_linear()
	s.box(Vector3(cx, 4.78, cz - 0.14), Vector3(arch_w, 0.28, 0.86))
	s.surface(stone_alt)
	s.colour = JADE_DEEP.srgb_to_linear()
	s.box(Vector3(cx, 5.10, cz - 0.14), Vector3(arch_w - 0.20, 0.38, 0.78))
	s.surface(marble)
	s.colour = MARBLE_WARM.srgb_to_linear()
	s.box(Vector3(cx, 5.42, cz - 0.14), Vector3(arch_w + 0.24, 0.26, 1.06))

	# Sculpted continuous bronze wave-scroll frieze running across the architrave above the screen!
	u.surface(bronze)
	u.colour = BRONZE_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx, 4.92, cz + 0.30), Vector3(arch_w - 0.12, 0.036, 0.04))
	u.box(Vector3(cx, 5.28, cz + 0.30), Vector3(arch_w - 0.12, 0.036, 0.04))
	var waves := 11
	for wi in waves:
		var wx := cx - 3.30 + float(wi) * 6.60 / float(waves - 1)
		Shapes.arch(u, Vector3(wx, 5.06, cz + 0.29), 0.10, 0.15, 0.05, 8, Basis(), 0.0, PI * 1.35,
				["front", "inner", "outer"])
		u.box(Vector3(wx + 0.04, 5.10, cz + 0.30), Vector3(0.06, 0.06, 0.05))

	# Broken classical raking pediment slopes flanking a central Atlantis radiant sun-shell medallion crest!
	s.surface(marble)
	s.colour = MARBLE_WARM.srgb_to_linear()
	for sd: float in [-1.0, 1.0]:
		var p_out := Vector3(cx + sd * 3.85, 5.56, cz - 0.10)
		var p_in := Vector3(cx + sd * 1.05, 6.26, cz - 0.10)
		Shapes.beam(s, p_out, p_in, Vector2(0.82, 0.24), Vector3.UP)
		u.surface(bronze)
		u.colour = BRONZE_WARM.srgb_to_linear()
		Shapes.beam(u, p_out + Vector3(0.0, 0.13, 0.38), p_in + Vector3(0.0, 0.13, 0.38), Vector2(0.045, 0.045), Vector3.UP)
	# Central bronze Atlantis solar-compass / shell crest medallion crowning the screen pediment!
	var crest := Vector3(cx, 5.98, cz + 0.16)
	u.surface(bronze)
	u.colour = BRONZE_BRIGHT.srgb_to_linear()
	Shapes.arch(u, crest, 0.26, 0.36, 0.07, 20, Basis(), 0.0, TAU, ["front", "inner", "outer"])
	for rk in 9:
		var ra := deg_to_rad(-80.0 + float(rk) * 20.0)
		var r_len := 0.56 if (rk % 2 == 0) else 0.42
		u.box(crest + Vector3(sin(ra) * r_len * 0.5, cos(ra) * r_len * 0.5, 0.01),
				Vector3(0.045, r_len, 0.04), Basis(Vector3.BACK, -ra))
	u.box(crest + Vector3(0.0, 0.0, 0.02), Vector3(0.22, 0.22, 0.08), Basis(Vector3.BACK, PI * 0.25))

	# 5. Indirect architectural cove light washes inside the pylon reveals & under the wave-scroll soffit (PieceCove).
	cove.surface(c.kit.cove_material())
	var cove_lin := Color(0.95, 0.90, 0.80).srgb_to_linear()
	cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.88)
	for sd: float in [-1.0, 1.0]:
		var vx := cx + sd * (hw + 0.19)
		cove.face([
			Vector3(vx - 0.05, sc_bot, cz - 0.06), Vector3(vx + 0.05, sc_bot, cz - 0.06),
			Vector3(vx + 0.05, sc_top, cz - 0.06), Vector3(vx - 0.05, sc_top, cz - 0.06),
		], Vector3.BACK)
	# Under-architrave soft cove wash above the picture.
	cove.face([
		Vector3(cx - hw - 0.18, 4.63, cz + 0.24), Vector3(cx + hw + 0.18, 4.63, cz + 0.24),
		Vector3(cx + hw + 0.18, 4.63, cz - 0.06), Vector3(cx - hw - 0.18, 4.63, cz - 0.06),
	], Vector3.DOWN)


## Builds 8 waterproof glowing bronze-and-crystal Atlantis floor lanterns on carved marble pedestals around the dry
## sanctuary rim (r = 5.48 m) plus 2 towering pylon-top bronze crystal braziers (PieceLamps + 8 stand-in/bake lamps).
static func _build_lanterns_and_coves(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove
	var marble: Material = c.tinted("stone")
	var bronze: Material = c.shiny("gilt", 0.88, 0.56, 0.22)
	# Waterproof lantern crystal core: bright warm amber/cyan in pre-show, dimming gracefully to a romantic candlelit
	# ember during the film (follows_house 0.25 avoids going muddy black when room env_light drops to 0.016!).
	var shade_m: Material = c.kit._lamp(LANTERN_GOLD, 1.35, 0.25, "house")

	# Eight symmetrical rim lantern pedestals (strictly clear of sight lines & >= 5.0 m from viewer's seat!).
	var lantern_degs: Array[float] = [-44.0, -82.0, -120.0, -158.0, 158.0, 120.0, 82.0, 44.0]
	var cove_lin := Color(0.95, 0.90, 0.80).srgb_to_linear()

	for ld: float in lantern_degs:
		var ang := deg_to_rad(ld)
		var p := _ring_pt(DAIS_R - 0.34, ang, 0.0) # r = 5.46 m
		var bs := Basis(Vector3.UP, -ang)

		# Carved octagonal marble plinth pedestal (y = 0.0 .. 0.42 m).
		s.surface(marble)
		s.colour = MARBLE_CREAM.srgb_to_linear()
		Shapes.lathe(s, [
			Vector2(0.26, 0.0), Vector2(0.26, 0.08), Vector2(0.19, 0.14),
			Vector2(0.17, 0.34), Vector2(0.23, 0.38), Vector2(0.23, 0.42), Vector2(0.0, 0.42),
		], p, 8, bs)

		# Ornate bronze lantern frame (base collar, 4 protective ribs, domed pierced finial cap: y = 0.42 .. 0.96 m).
		u.surface(bronze)
		u.colour = BRONZE_WARM.srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.16, 0.42), Vector2(0.18, 0.47), Vector2(0.13, 0.50)], p, 8, bs)
		for k in 4:
			var ra := float(k) * PI * 0.5 + PI * 0.25
			var rp := p + bs * Vector3(cos(ra) * 0.135, 0.65, sin(ra) * 0.135)
			u.box(rp, Vector3(0.022, 0.32, 0.022), bs)
		u.colour = BRONZE_BRIGHT.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.16, 0.79), Vector2(0.18, 0.82), Vector2(0.11, 0.87),
			Vector2(0.04, 0.92), Vector2(0.0, 0.97),
		], p, 8, bs)

		# Faceted glowing crystal core inside the bronze lantern cage (PieceLamps -> dims smoothly & shifts color!).
		lit.surface(shade_m)
		lit.colour = Color.WHITE
		Shapes.lathe(lit, [
			Vector2(0.0, 0.49), Vector2(0.095, 0.54), Vector2(0.11, 0.65),
			Vector2(0.095, 0.76), Vector2(0.0, 0.80),
		], p, 8, bs)

		# Soft glowing pool on the marble collar beneath each lantern (PieceCove, keeps gentle glow via cove_floor!).
		cove.surface(c.kit.cove_material())
		cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.75)
		var ring_pts: Array = []
		for k in 8:
			var ka := TAU * float(k) / 8.0
			ring_pts.append(p + Vector3(cos(ka) * 0.21, 0.425, sin(ka) * 0.21))
		cove.face(ring_pts, Vector3.UP)

		# Register all 8 sanctuary lanterns as stand-in & hidden bake lamps (bake_lamps: 8).
		c.lamps.append([p + Vector3(0.0, 0.72, 0.0), LANTERN_GOLD, 0.90])
		c.shapes.append(PhysicsShapes.box(p + Vector3(0.0, 0.48, 0.0), Vector3(0.46, 0.96, 0.46), bs))

	# Two monumental pylon-top bronze tripod crystal braziers crowning the twin screen pylons (y = 5.62 .. 6.42 m)!
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 2.75, -10.2)))
	var sc_sz: Vector2 = scr.get("size", Vector2(6.2, 3.49))
	var hw := sc_sz.x * 0.5
	for sd: float in [-1.0, 1.0]:
		var bp := Vector3(sc_xf.origin.x + sd * (hw + 0.78), 5.62, sc_xf.origin.z - 0.14)
		u.surface(bronze)
		u.colour = BRONZE_BRIGHT.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.28, 0.0), Vector2(0.24, 0.08), Vector2(0.14, 0.18),
			Vector2(0.32, 0.34), Vector2(0.36, 0.42), Vector2(0.30, 0.44),
		], bp, 10)
		lit.surface(shade_m)
		lit.colour = Color.WHITE
		Shapes.lathe(lit, [
			Vector2(0.0, 0.34), Vector2(0.22, 0.44), Vector2(0.18, 0.62),
			Vector2(0.08, 0.78), Vector2(0.0, 0.86),
		], bp, 8)
	# Glowing crystal jewel orb inside the central Atlantis solar-compass crest crowning the screen pediment!
	var crest_p := Vector3(sc_xf.origin.x, 5.98, sc_xf.origin.z + 0.22)
	lit.surface(shade_m)
	lit.colour = Color.WHITE
	Shapes.dome(lit, crest_p, 0.11, 4, 8, false, -PI * 0.5, PI * 0.5)


## Builds sunken classical terracotta amphorae, tumbled fluted column drums & carved frieze blocks, vibrant branching
## coral reef clusters, and swaying underwater sea-ferns clinging organically to the outer submerged steps & plinths.
static func _build_ruins_and_reef(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var marble: Material = c.tinted("stone")
	var clay: Material = c.tinted("plaster")
	var coral_mat: Material = c.soft("plaster", true)
	var fern_mat: Material = c.soft("leaves", true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7742

	# 1. Nine sunken terracotta amphorae clustered along the canal steps, leaning against plinths & near aft ruins.
	#    Each stands or tilts out of the y = -0.25 shallow canal water so its curved terracotta neck & handles read clearly!
	var amphorae: Array = [
		[-62.0, 6.55, -0.34, 0.22, 0.10, 1.05],
		[-66.5, 6.72, -0.36, -0.45, 0.35, 0.88],
		[-126.0, 6.60, -0.34, 0.18, -0.14, 1.00],
		[62.0, 6.58, -0.35, -0.26, 0.12, 1.02],
		[66.0, 6.78, -0.38, 0.58, -0.28, 0.85],
		[92.0, 8.20, -0.34, 0.30, 0.20, 1.12],
		[118.0, 7.15, -0.34, -0.38, 0.18, 0.96],
		[152.0, 6.65, -0.34, 0.14, -0.12, 1.08],
		[-156.0, 6.70, -0.35, -0.52, 0.25, 0.92],
	]
	s.surface(clay)
	for am: Array in amphorae:
		var ang := deg_to_rad(float(am[0]))
		var p := _ring_pt(float(am[1]), ang, float(am[2]))
		var tilt_x := float(am[3])
		var tilt_z := float(am[4])
		var sc := float(am[5])
		var bs := Basis(Vector3.UP, -ang) * Basis(Vector3.RIGHT, tilt_x) * Basis(Vector3.BACK, tilt_z)
		s.colour = (TERRACOTTA if rng.randf() > 0.35 else TERRACOTTA_DARK).srgb_to_linear()
		var prof := [
			Vector2(0.05, 0.0), Vector2(0.11, 0.14), Vector2(0.24, 0.38), Vector2(0.25, 0.56),
			Vector2(0.17, 0.72), Vector2(0.09, 0.84), Vector2(0.095, 0.98), Vector2(0.14, 1.05),
			Vector2(0.12, 1.08), Vector2(0.07, 1.04),
		]
		var sprof: Array = []
		for v: Vector2 in prof:
			sprof.append(v * sc)
		Shapes.lathe(s, sprof, p, 12, bs)
		# Twin curved terracotta amphora loop handles!
		for hd: float in [-1.0, 1.0]:
			var h0 := p + bs * (Vector3(hd * 0.20, 0.68, 0.0) * sc)
			var h1 := p + bs * (Vector3(hd * 0.22, 0.90, 0.0) * sc)
			var h2 := p + bs * (Vector3(hd * 0.10, 0.95, 0.0) * sc)
			Shapes.beam(s, h0, h1, Vector2(0.036, 0.036) * sc, bs.z)
			Shapes.beam(s, h1, h2, Vector2(0.034, 0.034) * sc, bs.z)

	# 2. Tumbled fluted marble column drums & weathered classical frieze blocks resting in the flooded canal!
	#    Dramatic cluster right below the broken aft-starboard column (+86.45 deg) plus accents around the canal.
	var drums: Array = [
		[84.0, 7.35, -0.10, 1.15, 0.38, 1.48, 0.35], # fallen fluted drum near broken column
		[96.0, 7.80, -0.06, 0.92, 0.37, 1.56, 1.12], # second tumbled drum
		[-98.0, 7.60, -0.14, 0.88, 0.38, 1.52, -0.70], # weathered port-side drum
	]
	s.surface(marble)
	for dr: Array in drums:
		var ang := deg_to_rad(float(dr[0]))
		var p := _ring_pt(float(dr[1]), ang, float(dr[2]))
		var bs := Basis(Vector3.UP, float(dr[6])) * Basis(Vector3.RIGHT, float(dr[5]))
		var d_len := float(dr[3])
		var d_rad := float(dr[4])
		_fluted_shaft(s, p, 0.0, d_len, d_rad, d_rad * 0.96, 12, bs, MARBLE_WET, MARBLE_SUBMERGED)
		# Crisp fractured stone circular end-caps on each fallen fluted drum.
		s.colour = MARBLE_BREAK.srgb_to_linear()
		for end_top: bool in [false, true]:
			var cap_r := d_rad * (0.91 if end_top else 0.95)
			var cap_y := d_len if end_top else 0.0
			var cap_pts: Array = []
			for k in 12:
				var ca := TAU * float(k) / 12.0
				cap_pts.append(p + bs * Vector3(sin(ca) * cap_r, cap_y, cos(ca) * cap_r))
			s.face(cap_pts, (bs * (Vector3.UP if end_top else Vector3.DOWN)).normalized())

	# Tumbled carved frieze stone blocks emerging from the turquoise water around the canal perimeter.
	var rubble: Array = [
		[78.0, 8.35, -0.14, Vector3(1.10, 0.44, 0.62), 0.35, 0.18],
		[104.0, 8.60, -0.10, Vector3(0.95, 0.52, 0.58), -0.42, -0.14],
		[-132.0, 8.10, -0.16, Vector3(1.18, 0.46, 0.64), 0.62, 0.12],
		[176.0, 7.65, -0.12, Vector3(1.25, 0.48, 0.66), 0.15, -0.08],
		[-48.0, 8.20, -0.16, Vector3(0.86, 0.40, 0.54), -0.25, 0.16],
	]
	s.surface(marble)
	for rb: Array in rubble:
		var ang := deg_to_rad(float(rb[0]))
		var p := _ring_pt(float(rb[1]), ang, float(rb[2]))
		var bs := Basis(Vector3.UP, float(rb[4])) * Basis(Vector3.RIGHT, float(rb[5]))
		s.colour = MARBLE_WET.srgb_to_linear()
		s.box(p, rb[3] as Vector3, bs)

	# 3. Vibrant branching coral reef clusters clinging to column plinths, submerged steps, and fallen stone blocks!
	var coral_spots: Array = [
		[-36.0, 8.55, -0.20, 0.85], [-56.0, 6.72, -0.22, 0.72], [-63.0, 8.65, -0.16, 0.92],
		[-88.0, 8.50, -0.18, 0.98], [-110.0, 6.75, -0.22, 0.78], [-118.0, 8.65, -0.15, 0.95],
		[-144.0, 8.55, -0.18, 0.88], [-170.0, 8.60, -0.18, 0.82],
		[36.0, 8.55, -0.20, 0.85], [55.0, 6.70, -0.22, 0.76], [64.0, 8.62, -0.16, 0.96],
		[82.0, 7.65, -0.16, 1.05], [90.0, 8.55, -0.12, 1.15], [108.0, 6.80, -0.22, 0.80],
		[118.0, 8.60, -0.16, 0.94], [142.0, 8.55, -0.18, 0.90], [168.0, 8.55, -0.18, 0.86],
		[-22.0, 9.70, -0.18, 0.74], [22.0, 9.70, -0.18, 0.74], # flanking the forward screen plinth!
	]
	u.surface(coral_mat)
	for ci in coral_spots.size():
		var cs: Array = coral_spots[ci]
		var ang := deg_to_rad(float(cs[0]))
		var base := _ring_pt(float(cs[1]), ang, float(cs[2]))
		var sc := float(cs[3])
		var col: Color = CORAL_PALETTE[ci % CORAL_PALETTE.size()]
		u.colour = col.srgb_to_linear()
		if ci % 3 == 0:
			# Sculpted brain-coral dome mounds.
			for k in 3:
				var off := Vector3(rng.randf_range(-0.32, 0.32), 0.0, rng.randf_range(-0.32, 0.32)) * sc
				var rad := rng.randf_range(0.18, 0.32) * sc
				Shapes.dome(u, base + off, rad, 4, 8, false, 0.0, PI * 0.5)
		else:
			# Branching staghorn / elkhorn coral antlers fanning upward out of the shallow water!
			var stems := 6
			for k in stems:
				var a := TAU * float(k) / float(stems) + rng.randf_range(-0.35, 0.35)
				var spread := rng.randf_range(0.24, 0.46) * sc
				var h_mid := rng.randf_range(0.32, 0.56) * sc
				var tip := base + Vector3(cos(a) * spread, h_mid, sin(a) * spread)
				Shapes.beam(u, base, tip, Vector2(0.065, 0.065) * sc)
				for fork: float in [-1.0, 1.0]:
					var fa := a + fork * 0.45
					var tip2 := tip + Vector3(cos(fa) * 0.18 * sc, 0.24 * sc, sin(fa) * 0.18 * sc)
					Shapes.beam(u, tip, tip2, Vector2(0.042, 0.042) * sc)

	# 4. Lush swaying underwater sea-ferns & kelp fronds arching around the outer column bases and submerged steps!
	var fern_spots: Array = [
		[-40.0, 8.70], [-58.0, 8.85], [-76.0, 6.70], [-88.0, 8.80], [-104.0, 8.75],
		[-126.0, 8.80], [-148.0, 8.70], [-168.0, 8.75],
		[40.0, 8.70], [58.0, 8.85], [76.0, 6.70], [88.0, 8.65], [104.0, 8.75],
		[126.0, 8.80], [148.0, 8.70], [168.0, 8.75],
		[-25.0, 9.85], [25.0, 9.85],
	]
	u.surface(fern_mat)
	for fi in fern_spots.size():
		var fs: Array = fern_spots[fi]
		var ang := deg_to_rad(float(fs[0]))
		var base := _ring_pt(float(fs[1]), ang, WATER_Y - 0.12)
		var fronds := 7
		for k in fronds:
			var fa := TAU * float(k) / float(fronds) + rng.randf_range(-0.25, 0.25)
			var dir := Vector3(sin(fa), 0.0, cos(fa))
			var side := Vector3(dir.z, 0.0, -dir.x)
			var h_max := rng.randf_range(0.75, 1.45)
			var reach := rng.randf_range(0.45, 0.85)
			u.colour = (FERN_DEEP if k % 2 == 0 else FERN_BRIGHT).srgb_to_linear()
			for step_i in range(1, 7):
				var t := float(step_i) / 6.0
				var p := base + dir * (reach * t * t) + Vector3.UP * (h_max * t)
				var lf := 0.22 * (1.0 - t * 0.55)
				for sd: float in [-1.0, 1.0]:
					var along := (side * sd * 0.72 + dir * 0.35 + Vector3.UP * 0.32).normalized() * lf
					var across := (dir * 0.45 - Vector3.UP * 0.45).normalized() * (lf * 0.38)
					Shapes.leaf(u, p, along, across, along.cross(across).normalized())


# --- Geometry Helpers ------------------------------------------------------------------------------------------------

## Draws a flat annular ring in the XZ plane around ROT_C at height y.
static func _flat_ring(b: RoomMesh, r_in: float, r_out: float, y: float, segs: int) -> void:
	var a := PackedVector3Array()
	var c := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in segs + 1:
		var ang := TAU * float(i % segs) / float(segs)
		a.append(_ring_pt(r_in, ang, y))
		c.append(_ring_pt(r_out, ang, y))
		ns.append(Vector3.UP)
	b.strip(a, c, ns)


## Draws a vertical cylindrical wall around ROT_C from y0 to y1 (outward = true faces away from center).
static func _cyl_wall(b: RoomMesh, r: float, y0: float, y1: float, segs: int, outward: bool) -> void:
	var a := PackedVector3Array()
	var c := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in segs + 1:
		var ang := TAU * float(i % segs) / float(segs)
		var n := Vector3(sin(ang), 0.0, -cos(ang)) * (1.0 if outward else -1.0)
		a.append(_ring_pt(r, ang, y0))
		c.append(_ring_pt(r, ang, y1))
		ns.append(n)
	b.strip(a, c, ns)


## Draws a genuine 12-flute scalloped Classical marble column shaft with gentle entasis bulge & alternating flute
## shading (24 radial vertices x 4 vertical bands = crisp fluted silhouette in just ~192 triangles per column!).
static func _fluted_shaft(b: RoomMesh, base: Vector3, y0: float, y1: float, r0: float, r1: float, flutes: int,
		bs: Basis, col_arris: Color, col_flute: Color) -> void:
	var bands := 4
	var steps := flutes * 2
	var c_hi := col_arris.srgb_to_linear()
	var c_lo := col_flute.srgb_to_linear()
	for bi in bands:
		var t0 := float(bi) / float(bands)
		var t1 := float(bi + 1) / float(bands)
		var ya := lerpf(y0, y1, t0)
		var yb := lerpf(y0, y1, t1)
		# Classical Greek entasis: subtle outward swell around 1/3 height.
		var ra := lerpf(r0, r1, t0) + 0.018 * sin(t0 * PI)
		var rb := lerpf(r0, r1, t1) + 0.018 * sin(t1 * PI)
		for si in steps:
			var a0 := TAU * float(si) / float(steps)
			var a1 := TAU * float(si + 1) / float(steps)
			var k0 := 1.0 if (si % 2 == 0) else 0.915
			var k1 := 1.0 if ((si + 1) % 2 == 0) else 0.915
			var d0 := Vector3(sin(a0), 0.0, cos(a0))
			var d1 := Vector3(sin(a1), 0.0, cos(a1))
			var p00 := base + bs * (d0 * (ra * k0) + Vector3.UP * ya)
			var p10 := base + bs * (d1 * (ra * k1) + Vector3.UP * ya)
			var p11 := base + bs * (d1 * (rb * k1) + Vector3.UP * yb)
			var p01 := base + bs * (d0 * (rb * k0) + Vector3.UP * yb)
			var nm := (bs * ((d0 + d1) * 0.5)).normalized()
			# Alternate warm sunlit arris flank & cool recessed flute shade so fluting pops in VR!
			b.colour = c_hi if (si % 2 == 0) else c_lo
			b.face([p00, p10, p11, p01], nm)
