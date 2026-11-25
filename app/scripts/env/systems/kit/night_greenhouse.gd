extends RefCounted

## Greenhouse at night kit (Cozy retreats: app/environments/night_greenhouse.env.json;
## docs/environments/rooms/night_greenhouse.md). A lush Victorian wrought-iron and ribbed-glass barrel-vault
## conservatory in the midnight rain, brimming with warm-lit kentia & fan palms, sword ferns, elephant-ear foliage,
## climbing ivy, potted dwarf lemon & tangerine trees, cedar-and-iron potting benches, glass bell cloches, brass
## hanging baskets, a trickling circular stone drip fountain, and warm brass pendant lamps. Built by Gemini 4 Neon
## Extra High. Everything is procedural (RoomMesh boxes, polygons, strips, beams, arches, lathes and leaves); zero
## people, zero trademarks, CC0 library materials only, zero live lights.
##
## Pieces (pieces.gd dispatches here; built over domestic shell "kit" + director seats):
##   greenhouse_vault   Victorian conservatory architecture, exterior midnight garden & curved rain-streaked glass:
##                      - warm terracotta-and-slate checkerboard quarry_tiles floor with recessed central cast-iron
##                        floor heating grate strip
##                      - weathered rose-brick dwarf walls (y = 0..0.95 m) with moulded pale limestone coping ledges
##                        wrapping port, starboard, 5-facet front apse and aft door flanks
##                      - heritage sage-green painted cast-iron fluted pilasters, 7 open-web twin-chord arched barrel-
##                        vault lattice trusses with circular spandrel rings, intermediate arched ribs, horizontal
##                        glazing purlins, Victorian filigree ridge cresting, ribbed front apse half-dome, and aft
##                        radial sunburst rose-fan glass gable above twin arched Victorian double glass doors
##                      - arched sage-green wrought-iron Victorian botanical trellis framing the cinema screen
##                        (center [0.0, 2.35, -8.0], size [4.8, 2.7], 100% clear aperture) over a low rose-brick fern
##                        trough so moonlight and dark rain-wet garden cypresses shine past the arch
##                      - shallow circular carved limestone drip fountain basin in the front-starboard alcove with
##                        animated rippling water & falling jet (PieceWater, env_fountain_water.gdshader)
##                      - concealed botanical uplight coves (PieceCove + 4 live-colour footlights) + 8 warm brass lamps
##                        (4 ridge pendants, 2 aft door sconces, 2 bench hurricane lanterns; PieceLamps)
##                      - GreenhouseAtmosphereHall (c.halls): opaque midnight garden outside (wet lawn, low stone
##                        garden wall, 24 rain-wet cypresses & hedges; 1 draw), curved rain-beaded barrel-vault glass
##                        roof driven live by weather.rain/wet (1 draw), and 3 subtle moonbeam shafts when rain clears
##   greenhouse_flora   abundant sculpted Victorian botanical collection & potting craft (batched into shared surfaces):
##                      - slatted western red-cedar & scrolled iron potting benches along port & starboard walls packed
##                        with turned terracotta clay pots, pot stacks, 4 translucent glass bell cloches (PieceGlass),
##                        a vintage coiled-handle brass watering can, hand trowel, and painted botanical seed tins
##                      - 6 towering sculpted kentia feather palms & pleated fan palms in ornate ribbed urns
##                      - 4 potted dwarf citrus (lemon & tangerine) trees studded with glowing yellow & orange fruits
##                      - 6 hanging brass fern baskets, layered sword fern clumps, broad elephant-ear botanical leaves,
##                        climbing ivy hugging the iron pilasters & outer screen trellis, and an aft scrolled cast-iron
##                        potting table with warm brass hurricane lantern

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const OUTSIDE_SHADER := preload("res://shaders/env_ice_outside.gdshader")
const RAIN_PANE_SHADER := preload("res://shaders/env_rain_pane.gdshader")
const SHAFT_SHADER := preload("res://shaders/env_world_shaft.gdshader")

const PIECES: Array[String] = ["greenhouse_vault", "greenhouse_flora"]

## Conservatory dimensions (metres, viewer's dead-centre seat at (0, 0, 0) facing -Z).
const HW := 5.60
const INNER_X := 5.48
const ARCH_HW := 5.56
const FRONT_SIDE_Z := -7.60
const FRONT_APSE_Z := -8.80
const BACK_Z := 6.20
const DWARF_H := 0.95
const EAVE_Y := 3.05
const ARCH_RISE := 2.95
const CROWN_Y := 6.00 # EAVE_Y + ARCH_RISE

## Seven main structural cast-iron rib Z-stations (6 equal 2.30 m side bays).
const RIB_ZS: Array[float] = [-7.60, -5.30, -3.00, -0.70, 1.60, 3.90, 6.20]

## Six vertices forming the graceful 5-facet front canted glass apse (clockwise from above -> along x UP points inward).
const APSE: Array[Vector2] = [
	Vector2(-5.60, -7.60), # 0: Port front corner
	Vector2(-4.20, -8.55), # 1: Port-front cant
	Vector2(-1.90, -8.80), # 2: Centre-left apse
	Vector2(1.90, -8.80),  # 3: Centre-right apse
	Vector2(4.20, -8.55),  # 4: Starboard-front cant
	Vector2(5.60, -7.60),  # 5: Starboard front corner
]

## Fountain position (front-starboard alcove, clearly visible from seats and > 5.7 m clear of origin).
const FOUNTAIN_POS := Vector3(3.35, 0.0, -4.65)

## Moon direction matching sky params (facing 180, moon_bearing 212, moon_altitude 46).
const MOON_DIR := Vector3(0.368, 0.719, -0.589)

## Palette (sRGB): heritage sage cast iron, weathered rose brick, terracotta & slate quarry tiles, cedar, brass, flora.
const IRON_SAGE := Color(0.22, 0.34, 0.28)
const IRON_SAGE_LIGHT := Color(0.30, 0.44, 0.36)
const IRON_SAGE_DARK := Color(0.14, 0.22, 0.19)
const IRON_CHARCOAL := Color(0.11, 0.13, 0.14)
const BRICK_ROSE := Color(0.64, 0.33, 0.27)
const BRICK_DEEP := Color(0.46, 0.24, 0.20)
const STONE_COPING := Color(0.76, 0.73, 0.66)
const STONE_AGED := Color(0.60, 0.59, 0.54)
const STONE_BASIN := Color(0.68, 0.67, 0.62)
const TILE_TERRACOTTA := Color(0.74, 0.38, 0.25)
const TILE_SLATE := Color(0.23, 0.26, 0.29)
const TILE_BORDER := Color(0.32, 0.29, 0.27)
const CEDAR_WARM := Color(0.56, 0.33, 0.20)
const CEDAR_RICH := Color(0.42, 0.24, 0.14)
const CLAY_WARM := Color(0.74, 0.38, 0.24)
const CLAY_PALE := Color(0.82, 0.50, 0.33)
const CLAY_DEEP := Color(0.56, 0.27, 0.18)
const SOIL_DARK := Color(0.14, 0.10, 0.08)
const BARK_PALM := Color(0.38, 0.29, 0.21)
const BARK_CITRUS := Color(0.30, 0.22, 0.15)
const BRASS_BRIGHT := Color(0.95, 0.78, 0.38)
const BRASS_WARM := Color(0.80, 0.60, 0.26)
const BRASS_AGED := Color(0.60, 0.44, 0.20)
const LAMP_WARM := Color(1.0, 0.80, 0.46)
const COVE_STONE := Color(0.46, 0.42, 0.36)
const LEAF_DEEP := Color(0.08, 0.28, 0.12)
const LEAF_EMERALD := Color(0.14, 0.42, 0.17)
const LEAF_FERN := Color(0.20, 0.52, 0.20)
const LEAF_BRIGHT := Color(0.30, 0.62, 0.24)
const LEAF_IVY := Color(0.11, 0.33, 0.14)
const LEAF_CITRUS := Color(0.12, 0.37, 0.14)
const FRUIT_LEMON := Color(0.98, 0.88, 0.24)
const FRUIT_TANGERINE := Color(0.96, 0.48, 0.12)
const TIN_SAGE := Color(0.42, 0.56, 0.46)
const TIN_CREAM := Color(0.88, 0.83, 0.70)
const TIN_OCHRE := Color(0.80, 0.58, 0.24)

## Three graceful parallel silver-blue moonbeam shafts entering along -MOON_DIR (-0.368, -0.719, +0.589) through the
## arched glass vault when the rain clears (strictly clear of the screen aperture & viewer origin, slender for low
## blend overdraw): [top_pos, bot_pos, r_top, r_bot, alpha_weight].
const MOON_SHAFTS: Array = [
	[Vector3(-1.55, 5.50, -5.85), Vector3(-3.95, 0.80, -2.02), 0.38, 0.72, 0.86],
	[Vector3(4.55, 4.58, -6.95), Vector3(2.65, 0.86, -3.90), 0.36, 0.68, 0.92],
	[Vector3(1.45, 5.72, 1.35), Vector3(-1.05, 0.82, 5.35), 0.42, 0.78, 0.76],
]


## Custom `c.halls` atmospheric exterior & curved rain-glass manager:
##   1. GreenhouseGarden (1 opaque draw, zero blend): dark rain-wet midnight lawn, low stone garden wall, 24 wet
##      cypresses, garden hedges & tree crowns outside the glasshouse, catching silver moonlight when rain clears.
##   2. GreenhouseRoofGlass (1 draw, env_rain_pane.gdshader, env_see_through): single-surface curved barrel-vault &
##      front apse roof glass with live raindrops & streaming trails following weather.rain / weather.wet.
##   3. GreenhouseMoonShafts (1 draw when rain clears, hidden in steady rain, env_world_shaft.gdshader): subtle
##      silvery moonbeams slanting through the arched glass roof onto the foliage and fountain.
class GreenhouseAtmosphereHall:
	var kit: Node
	var garden_node: MeshInstance3D
	var garden_m: ShaderMaterial
	var roof_node: MeshInstance3D
	var roof_m: ShaderMaterial
	var shaft_node: MeshInstance3D
	var shaft_m: ShaderMaterial
	var _clock := 0.0
	var _shaft_lvl := 0.0
	var _moon_lvl := 0.35

	func finish(k: Node) -> void:
		kit = k
		# Tune PieceGlass (bell cloches, aft glass doors & rose-fan gable) to crisp conservatory Fresnel glazing.
		for n: Node in k.owned():
			if n is MeshInstance3D and str(n.name).begins_with("PieceGlass"):
				var gm := (n as MeshInstance3D).material_override as ShaderMaterial
				if gm != null:
					gm.set_shader_parameter("alpha", 0.045)
					gm.set_shader_parameter("rim", 0.18)
					gm.set_shader_parameter("sky_colour", Color(0.18, 0.28, 0.42))
					gm.set_shader_parameter("sky_mix", 0.30)

		_build_garden(k)
		_build_roof_rain_glass(k)
		_build_moon_shafts(k)
		tick(0.0)

	func _build_garden(k: Node) -> void:
		garden_m = ShaderMaterial.new()
		garden_m.shader = OUTSIDE_SHADER
		garden_m.set_shader_parameter("moon_dir", MOON_DIR.normalized())
		garden_m.set_shader_parameter("aurora_dir", Vector3.UP)
		garden_m.set_shader_parameter("aurora_light", Vector3(0.02, 0.04, 0.06))
		garden_m.set_shader_parameter("glitter", 0.0)
		garden_m.set_shader_parameter("haze", 0.022)
		garden_m.set_shader_parameter("glow", 1.0)

		var b := RoomMesh.new()
		b.surface(garden_m)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1889

		# 1. Wet dark midnight garden lawn & soil encircling the glasshouse (y = -0.08 m, r = 60 m).
		var lawn := Color(0.055, 0.085, 0.060).srgb_to_linear()
		b.colour = Color(lawn.r, lawn.g, lawn.b, 1.0)
		var ring_pts := PackedVector3Array()
		for i in 28:
			var a := TAU * float(i) / 28.0
			ring_pts.append(Vector3(cos(a) * 60.0, -0.08, sin(a) * 60.0))
		b.polygon(ring_pts, Vector3.UP)

		# 2. Low weathered stone garden boundary wall & corner piers around the conservatory grounds (~15 m out).
		var wall_c := Color(0.18, 0.19, 0.21).srgb_to_linear()
		var cap_c := Color(0.26, 0.27, 0.28).srgb_to_linear()
		var wall_ring: Array[Vector2] = [
			Vector2(-15.5, -16.5), Vector2(15.5, -16.5),
			Vector2(15.5, 14.5), Vector2(-15.5, 14.5),
		]
		for wi in wall_ring.size():
			var a2 := wall_ring[wi]
			var b2 := wall_ring[(wi + 1) % wall_ring.size()]
			var pa := Vector3(a2.x, 0.0, a2.y)
			var pb := Vector3(b2.x, 0.0, b2.y)
			var flen := pa.distance_to(pb)
			var along := (pb - pa) / flen
			var n := along.cross(Vector3.UP).normalized()
			var wb := Basis(along, Vector3.UP, n)
			b.colour = Color(wall_c.r, wall_c.g, wall_c.b, 1.0)
			b.box((pa + pb) * 0.5 + Vector3(0.0, 0.62, 0.0), Vector3(flen, 1.40, 0.42), wb, [RoomMesh.DOWN])
			b.colour = Color(cap_c.r, cap_c.g, cap_c.b, 1.0)
			b.box((pa + pb) * 0.5 + Vector3(0.0, 1.36, 0.0), Vector3(flen + 0.12, 0.12, 0.52), wb)
			# Stone gate/corner piers along the garden perimeter wall.
			var piers := 5
			for pk in piers:
				var pp := pa.lerp(pb, float(pk) / float(piers))
				b.colour = Color(wall_c.r * 1.08, wall_c.g * 1.08, wall_c.b * 1.08, 1.0)
				b.box(pp + Vector3(0.0, 0.90, 0.0), Vector3(0.62, 1.96, 0.62), wb, [RoomMesh.DOWN])
				b.colour = Color(cap_c.r, cap_c.g, cap_c.b, 1.0)
				b.box(pp + Vector3(0.0, 1.92, 0.0), Vector3(0.74, 0.14, 0.74), wb)

		# 3. Sculpted dark rain-wet boxwood garden hedges hugging just outside the stone wall & conservatory path.
		var hedge_c := Color(0.06, 0.13, 0.08).srgb_to_linear()
		b.colour = Color(hedge_c.r, hedge_c.g, hedge_c.b, 1.0)
		var hedges: Array = [
			[Vector3(-8.6, 0.65, -4.0), Vector3(1.15, 1.45, 7.6), 0.0],
			[Vector3(-8.8, 0.65, 3.8), Vector3(1.15, 1.38, 6.2), 0.0],
			[Vector3(8.6, 0.65, -4.0), Vector3(1.15, 1.45, 7.6), 0.0],
			[Vector3(8.8, 0.65, 3.8), Vector3(1.15, 1.38, 6.2), 0.0],
			[Vector3(-4.2, 0.68, -11.6), Vector3(4.2, 1.50, 1.2), 0.28],
			[Vector3(4.2, 0.68, -11.6), Vector3(4.2, 1.50, 1.2), -0.28],
			[Vector3(-4.8, 0.65, 9.6), Vector3(4.6, 1.42, 1.2), 0.0],
			[Vector3(4.8, 0.65, 9.6), Vector3(4.6, 1.42, 1.2), 0.0],
		]
		for h: Array in hedges:
			b.rounded_box(Vector3.ZERO, h[1] as Vector3, 0.28,
					Transform3D(Basis(Vector3.UP, float(h[2])), h[0] as Vector3), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])

		# 4. Twenty-four dark rain-wet Italian cypress spires & garden trees framing the glasshouse in 360 degrees!
		# [pos_xz, height, radius, is_cypress]
		var trees: Array = [
			# Front garden flanking the glazed apse (leaving upper-right Moon corridor clear!).
			[Vector2(-7.8, -11.8), 10.6, 1.15, true],
			[Vector2(-5.4, -14.2), 11.8, 1.25, true],
			[Vector2(-1.8, -14.8), 8.2, 2.35, false],
			[Vector2(2.6, -15.4), 7.8, 2.20, false],
			[Vector2(7.6, -12.4), 10.2, 1.10, true],
			[Vector2(10.4, -10.8), 11.4, 1.25, true],
			# Port side midnight cypress avenue & garden oaks.
			[Vector2(-10.2, -7.8), 11.2, 1.20, true],
			[Vector2(-11.4, -3.5), 9.6, 2.65, false],
			[Vector2(-9.8, 0.2), 10.8, 1.18, true],
			[Vector2(-11.8, 4.2), 10.0, 2.75, false],
			[Vector2(-9.6, 8.2), 11.5, 1.22, true],
			# Starboard side midnight cypresses & garden trees.
			[Vector2(10.2, -6.5), 10.4, 1.15, true],
			[Vector2(11.8, -2.0), 9.2, 2.55, false],
			[Vector2(9.8, 1.6), 11.0, 1.18, true],
			[Vector2(11.6, 5.6), 9.8, 2.70, false],
			[Vector2(9.4, 9.2), 10.6, 1.16, true],
			# Aft garden behind the Victorian double conservatory doors.
			[Vector2(-6.2, 12.6), 10.4, 1.18, true],
			[Vector2(-3.2, 14.8), 9.0, 2.50, false],
			[Vector2(3.4, 14.6), 9.4, 2.60, false],
			[Vector2(6.5, 12.4), 11.2, 1.24, true],
			# Outer background silhouettes giving depth beyond the low stone garden wall.
			[Vector2(-18.5, -13.5), 13.0, 3.4, false],
			[Vector2(18.5, -13.0), 12.5, 3.2, false],
			[Vector2(-18.0, 6.0), 12.8, 3.3, false],
			[Vector2(18.0, 7.5), 12.2, 3.2, false],
		]
		var trunk_c := Color(0.11, 0.09, 0.08).srgb_to_linear()
		for tr: Array in trees:
			var p2: Vector2 = tr[0]
			var h := float(tr[1])
			var r := float(tr[2])
			var is_cyp := bool(tr[3])
			var foot := Vector3(p2.x, -0.10, p2.y)
			# Trunk.
			b.colour = Color(trunk_c.r, trunk_c.g, trunk_c.b, 1.0)
			Shapes.cylinder(b, foot, 0.24 if is_cyp else 0.34, h * (0.20 if is_cyp else 0.42), 6, Basis(), false)
			var g := Color(0.06, 0.14, 0.08).lerp(Color(0.09, 0.18, 0.11), rng.randf()).srgb_to_linear()
			b.colour = Color(g.r, g.g, g.b, 1.0)
			if is_cyp:
				# Multi-tiered organic dark Italian cypress spire rooted cleanly behind the garden wall (no floating gap!).
				Shapes.lathe(b, [
					Vector2(r * 0.42, h * 0.04),
					Vector2(r * 0.88, h * 0.12),
					Vector2(r * 1.04, h * 0.22),
					Vector2(r * 0.92, h * 0.31),
					Vector2(r * 0.98, h * 0.42),
					Vector2(r * 0.80, h * 0.53),
					Vector2(r * 0.84, h * 0.63),
					Vector2(r * 0.62, h * 0.74),
					Vector2(r * 0.44, h * 0.84),
					Vector2(r * 0.20, h * 0.93),
					Vector2(0.0, h),
				], foot, 8)
				# Companion offset side bough / twin cypress shoot for natural estate garden silhouette!
				var sa := rng.randf() * TAU
				var sh := h * rng.randf_range(0.56, 0.74)
				var sr := r * rng.randf_range(0.52, 0.68)
				var soff := Vector3(cos(sa) * r * 0.52, 0.0, sin(sa) * r * 0.52)
				Shapes.lathe(b, [
					Vector2(sr * 0.45, sh * 0.06),
					Vector2(sr * 0.98, sh * 0.26),
					Vector2(sr * 0.86, sh * 0.52),
					Vector2(sr * 0.48, sh * 0.78),
					Vector2(0.0, sh),
				], foot + soff, 7)
			else:
				# Multi-lobed dark wet deciduous garden tree crown.
				var cy := h * 0.62
				Shapes.lathe(b, [
					Vector2(0.0, cy - r * 0.72),
					Vector2(r * 0.94, cy - r * 0.36),
					Vector2(r * 1.06, cy + r * 0.04),
					Vector2(r * 0.82, cy + r * 0.54),
					Vector2(0.0, cy + r * 0.82),
				], foot, 9)
				for lk in 3:
					var ang := TAU * float(lk) / 3.0 + rng.randf_range(-0.4, 0.4)
					var off := Vector3(cos(ang) * r * 0.58, r * rng.randf_range(-0.22, 0.24), sin(ang) * r * 0.58)
					var sr := r * rng.randf_range(0.56, 0.70)
					Shapes.lathe(b, [
						Vector2(0.0, -sr * 0.68),
						Vector2(sr, -sr * 0.08),
						Vector2(sr * 0.82, sr * 0.34),
						Vector2(0.0, sr * 0.74),
					], foot + Vector3(0.0, cy, 0.0) + off, 7)

		# 5. Subtle warm amber glow from a distant cottage / garden-house window far across the hedge (COLOR.a = 0!).
		b.colour = Color(0.88, 0.62, 0.30, 0.0)
		b.box(Vector3(-24.0, 2.2, -21.0), Vector3(0.95, 1.15, 0.15), Basis(Vector3.UP, 0.65))
		b.box(Vector3(-22.4, 2.2, -22.2), Vector3(0.95, 1.15, 0.15), Basis(Vector3.UP, 0.65))
		b.colour = Color.WHITE

		garden_node = k._add_unbaked("GreenhouseGarden", b)

	## Builds the single-surface curved barrel-vault & front apse roof glass using env_rain_pane.gdshader so
	## sparkling rain beads and running rain trails stream smoothly down the arched glass vault overhead!
	func _build_roof_rain_glass(k: Node) -> void:
		roof_m = ShaderMaterial.new()
		roof_m.shader = RAIN_PANE_SHADER
		roof_m.set_shader_parameter("colour", Color(0.76, 0.86, 0.96))
		roof_m.set_shader_parameter("opacity", 0.58)
		roof_m.set_shader_parameter("salt", 0.0)
		roof_m.set_shader_parameter("drift", 0.12)

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		# A. Main curved barrel-vault roof (two symmetric slopes from ridge down to port & starboard eaves).
		var len_z := BACK_Z - FRONT_SIDE_Z # 13.8 m
		const ARC_SEGS := 8
		var arc_len := 0.0
		var half_pts: Array[Vector2] = []
		for i in ARC_SEGS + 1:
			var th := lerpf(PI * 0.5, 0.0, float(i) / float(ARC_SEGS)) # ridge (PI/2) -> eave (0)
			var pt := Vector2(ARCH_HW * cos(th), EAVE_Y + ARCH_RISE * sin(th))
			if i > 0:
				arc_len += pt.distance_to(half_pts[i - 1])
			half_pts.append(pt)

		var cum_s: Array[float] = [0.0]
		for i in range(1, ARC_SEGS + 1):
			cum_s.append(cum_s[i - 1] + half_pts[i].distance_to(half_pts[i - 1]))

		for side: float in [-1.0, 1.0]:
			var seed_v := 0.19 if side < 0.0 else 0.63
			var col := Color(seed_v, 1.0 if side > 0.0 else 0.0, 0.0, 1.0)
			var size_uv2 := Vector2(len_z, arc_len)
			for i in ARC_SEGS:
				var p0 := half_pts[i]
				var p1 := half_pts[i + 1]
				var v0 := cum_s[i] / arc_len # UV.y: 0 at ridge (top), 1 at eave (bottom)
				var v1 := cum_s[i + 1] / arc_len
				var a0 := Vector3(side * p0.x, p0.y, FRONT_SIDE_Z)
				var a1 := Vector3(side * p0.x, p0.y, BACK_Z)
				var b1 := Vector3(side * p1.x, p1.y, BACK_Z)
				var b0 := Vector3(side * p1.x, p1.y, FRONT_SIDE_Z)
				var mid_x := side * (p0.x + p1.x) * 0.5
				var mid_y := (p0.y + p1.y) * 0.5 - EAVE_Y
				var n := Vector3(-mid_x / ARCH_HW, -mid_y / ARCH_RISE, 0.0).normalized()
				var u_left := 0.0 if side > 0.0 else 1.0
				var u_right := 1.0 if side > 0.0 else 0.0
				_add_rain_quad(st, a0, a1, b1, b0, n, col, size_uv2,
						Vector2(u_left, v0), Vector2(u_right, v0), Vector2(u_right, v1), Vector2(u_left, v1))

		# B. Front 5-facet curved apse half-dome roof gores converging cleanly from the apse eave up to the front crown!
		var apex := Vector3(0.0, CROWN_Y, FRONT_SIDE_Z)
		const DOME_RINGS := 5
		for ei in APSE.size() - 1:
			var ea := Vector3(APSE[ei].x, EAVE_Y, APSE[ei].y)
			var eb := Vector3(APSE[ei + 1].x, EAVE_Y, APSE[ei + 1].y)
			var w_base := ea.distance_to(eb)
			var col := Color(fmod(0.31 + float(ei) * 0.17, 1.0), 0.5, 0.0, 1.0)
			var gore_h := 4.4
			var size_uv2 := Vector2(w_base, gore_h)
			for ri in DOME_RINGS:
				var t0 := float(ri) / float(DOME_RINGS) # 0 = apex (top), 1 = eave (bottom)
				var t1 := float(ri + 1) / float(DOME_RINGS)
				var p00 := _apse_dome_pt(apex, ea, t0)
				var p10 := _apse_dome_pt(apex, eb, t0)
				var p11 := _apse_dome_pt(apex, eb, t1)
				var p01 := _apse_dome_pt(apex, ea, t1)
				var n := ((p10 - p00).cross(p01 - p00)).normalized()
				var to_in := Vector3(0.0, 2.0, -5.0) - (p00 + p11) * 0.5
				if n.dot(to_in) < 0.0:
					n = -n
				_add_rain_quad(st, p00, p10, p11, p01, n, col, size_uv2,
						Vector2(0.0, t0), Vector2(1.0, t0), Vector2(1.0, t1), Vector2(0.0, t1))

		var mesh := st.commit()
		mesh.surface_set_material(0, roof_m)
		roof_node = k._add_mesh("GreenhouseRoofGlass", mesh)
		if roof_node != null:
			roof_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			roof_node.add_to_group("env_see_through")

	static func _apse_dome_pt(apex: Vector3, eave: Vector3, t: float) -> Vector3:
		# Elliptic vault curvature matching the barrel-vault arch profile!
		var horiz := sin(t * PI * 0.5)
		var drop := 1.0 - cos(t * PI * 0.5)
		return Vector3(lerpf(apex.x, eave.x, horiz), lerpf(apex.y, eave.y, drop), lerpf(apex.z, eave.z, horiz))

	static func _add_rain_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3,
			col: Color, uv2: Vector2, uv0: Vector2, uv1: Vector2, uv2p: Vector2, uv3: Vector2) -> void:
		for tri: Array in [[p0, uv0], [p1, uv1], [p2, uv2p], [p0, uv0], [p2, uv2p], [p3, uv3]]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(tri[1])
			st.set_uv2(uv2)
			st.add_vertex(tri[0])

	func _build_moon_shafts(k: Node) -> void:
		shaft_m = ShaderMaterial.new()
		shaft_m.shader = SHAFT_SHADER
		shaft_m.set_shader_parameter("noise_map", SkySys.noise_texture())
		shaft_m.set_shader_parameter("shaft_colour", Color(0.58, 0.76, 1.0))
		shaft_m.set_shader_parameter("edge_softness", 2.4)
		shaft_m.set_shader_parameter("wisp_strength", 0.48)

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		const SEGS := 16
		const RINGS := 5
		for sh: Array in MOON_SHAFTS:
			var top_c: Vector3 = sh[0]
			var bot_c: Vector3 = sh[1]
			var r_top := float(sh[2])
			var r_bot := float(sh[3])
			var alpha := float(sh[4])
			var axis := (bot_c - top_c).normalized()
			var ref := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var bx := axis.cross(ref).normalized()
			var bz := bx.cross(axis).normalized()
			var col := Color(0.86, 0.93, 1.0, alpha)
			for ri in RINGS:
				var v0 := float(ri) / float(RINGS)
				var v1 := float(ri + 1) / float(RINGS)
				var c0 := top_c.lerp(bot_c, v0)
				var c1 := top_c.lerp(bot_c, v1)
				var rad0 := lerpf(r_top, r_bot, v0)
				var rad1 := lerpf(r_top, r_bot, v1)
				for si in SEGS:
					var u0 := float(si) / float(SEGS)
					var u1 := float(si + 1) / float(SEGS)
					var d0 := (bx * cos(u0 * TAU) + bz * sin(u0 * TAU)).normalized()
					var d1 := (bx * cos(u1 * TAU) + bz * sin(u1 * TAU)).normalized()
					var p00 := c0 + d0 * rad0
					var p10 := c0 + d1 * rad0
					var p11 := c1 + d1 * rad1
					var p01 := c1 + d0 * rad1
					for tv: Array in [
						[p00, d0, Vector2(u0, v0)], [p10, d1, Vector2(u1, v0)], [p11, d1, Vector2(u1, v1)],
						[p00, d0, Vector2(u0, v0)], [p11, d1, Vector2(u1, v1)], [p01, d0, Vector2(u0, v1)],
					]:
						st.set_color(col)
						st.set_normal(tv[1])
						st.set_uv(tv[2])
						st.add_vertex(tv[0])
		var mesh := st.commit()
		mesh.surface_set_material(0, shaft_m)
		shaft_node = k._add_mesh("GreenhouseMoonShafts", mesh)
		if shaft_node != null:
			shaft_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			shaft_node.add_to_group("env_see_through")

	func tick(delta: float) -> void:
		if kit == null or kit.host == null:
			return
		var host: Node = kit.host
		var motion := 1.0
		var mv: Variant = host.setting("motion")
		if mv != null:
			motion = clampf(float(mv), 0.0, 1.0)
		_clock += maxf(delta, 0.0) * motion

		var rain_setting := "steady"
		var rv: Variant = host.setting("rain")
		if rv != null:
			rain_setting = str(rv)
		var playing := false
		if host.get("timeline") != null:
			playing = str(host.timeline.state) in ["starting", "playing", "credits"]

		# Read live rain & wet from the weather system (plus any faked signal for tests).
		var rain_amt := 0.0
		var wet_amt := 0.0
		var wsys: Node = host.system("weather")
		if wsys != null:
			rain_amt = float(wsys.call("rain_amount"))
			wet_amt = float(wsys.call("wet_amount"))
		if host.get("signals") != null:
			rain_amt = maxf(rain_amt, float(host.signals.values.get("weather.rain", 0.0)))
			wet_amt = maxf(wet_amt, float(host.signals.values.get("weather.wet", 0.0)))

		# Update curved barrel-vault rain-streaked glass roof!
		if roof_m != null:
			roof_m.set_shader_parameter("rain", rain_amt)
			roof_m.set_shader_parameter("wet", wet_amt)
			roof_m.set_shader_parameter("drift", 0.24 * rain_amt)
		if roof_node != null and is_instance_valid(roof_node):
			roof_node.visible = (rain_amt > 0.005 or wet_amt > 0.01)
			roof_node.set_meta("rain_amount", rain_amt)
			roof_node.set_meta("wet_amount", wet_amt)

		# Moonbeam shafts bloom gently as the rain clears (off in steady rain for zero extra blend cost!).
		var target_shaft := 0.0
		var target_moon := 0.35
		match rain_setting:
			"clear":
				target_shaft = 0.09 if playing else 0.19
				target_moon = 0.95
			"drizzle":
				target_shaft = 0.03 if playing else 0.07
				target_moon = 0.65
			_:
				target_shaft = 0.0
				target_moon = 0.32

		if delta <= 0.0:
			_shaft_lvl = target_shaft
			_moon_lvl = target_moon
		else:
			var rate := clampf(delta * 0.9, 0.0, 1.0)
			_shaft_lvl = lerpf(_shaft_lvl, target_shaft, rate)
			_moon_lvl = lerpf(_moon_lvl, target_moon, rate)

		if shaft_m != null:
			shaft_m.set_shader_parameter("shaft_level", _shaft_lvl)
			shaft_m.set_shader_parameter("clock", _clock)
		if shaft_node != null and is_instance_valid(shaft_node):
			shaft_node.visible = _shaft_lvl > 0.005
			shaft_node.set_meta("moon_shaft_level", _shaft_lvl)
			shaft_node.set_meta("clock", _clock)

		# Update midnight garden moonlight & sky tint (dimming slightly when film plays).
		if garden_m != null:
			var ext := 0.52 if playing else 1.0
			garden_m.set_shader_parameter("sky_top", Color(0.035, 0.055, 0.11) * ext)
			garden_m.set_shader_parameter("sky_low", Color(0.075, 0.11, 0.16) * ext)
			garden_m.set_shader_parameter("moon_light", Vector3(0.42, 0.56, 0.78) * _moon_lvl * ext)
			garden_m.set_shader_parameter("glow", 0.55 if playing else 1.0)
		if garden_node != null and is_instance_valid(garden_node):
			garden_node.set_meta("moon_level", _moon_lvl)


# --- Entry point ------------------------------------------------------------------------------------------------------

static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"greenhouse_vault":
			_build_vault(c)
			c.halls.append(GreenhouseAtmosphereHall.new())
		"greenhouse_flora":
			_build_flora(c)
	_reset_colours(c)


static func _reset_colours(c: Object) -> void:
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE
	c.lit.colour = Color.WHITE
	c.cove.colour = Color.WHITE
	c.water.colour = Color.WHITE


static func _brass_mat(c: Object) -> Material:
	return c.shiny("gilt", 0.88, 0.65, 0.18)


static func _towards(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.FORWARD.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# ======================================================================================================================
# PIECE 1: greenhouse_vault — Victorian wrought-iron & glass barrel-vault conservatory, floor, screen trellis, fountain
# ======================================================================================================================

static func _build_vault(c: Object) -> void:
	# Slightly coarser static texel keeps the entire conservatory lightmap atlas compact (<= 512..768 px).
	c.s.texel = 0.16
	_floor_and_heating_grate(c)
	_dwarf_walls_and_coping(c)
	_wrought_iron_structure_and_vault(c)
	_front_apse_and_screen_trellis(c)
	_aft_double_doors_and_rose_gable(c)
	_stone_drip_fountain(c)
	_pendant_lamps_and_coves(c)


## Terracotta-and-slate checkerboard quarry_tiles floor (Procedural "quarry_tiles"), dark slate perimeter border, and
## recessed central cast-iron floor heating grate strip with soft warm underglow.
static func _floor_and_heating_grate(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var tile_m: Material = c.tinted("stone", "quarry_tiles")

	# 1. Main warm fired terracotta quarry_tiles floor slab spanning straight hall + 5-facet canted front apse.
	s.surface(tile_m)
	s.colour = TILE_TERRACOTTA.srgb_to_linear()
	var floor_poly := PackedVector3Array()
	for v: Vector2 in APSE:
		floor_poly.append(Vector3(v.x, 0.0, v.y))
	floor_poly.append(Vector3(HW, 0.0, BACK_Z))
	floor_poly.append(Vector3(-HW, 0.0, BACK_Z))
	s.polygon(floor_poly, Vector3.UP)

	# 2. Crisp alternating dark Victorian slate-charcoal checkerboard quarry_tiles squares along the conservatory floor!
	#    Grid of 0.78 m squares across x in [-3.12, +3.12] (8 cols), z in [-7.02, +5.46] (16 rows) -> 60 slate tiles!
	s.colour = TILE_SLATE.srgb_to_linear()
	var step := 0.78
	for ix in 8:
		var x0 := -3.12 + float(ix) * step
		var x1 := x0 + step
		var xm := (x0 + x1) * 0.5
		for iz in 16:
			if (ix + iz) % 2 != 0:
				continue
			var z0 := -7.02 + float(iz) * step
			var z1 := z0 + step
			var zm := (z0 + z1) * 0.5
			# Leave central floor heating grate strip & stone fountain footprint completely crisp.
			if absf(xm) < 0.52 and zm > -7.0 and zm < -1.55:
				continue
			if Vector2(xm - FOUNTAIN_POS.x, zm - FOUNTAIN_POS.z).length() < 1.18:
				continue
			s.face([Vector3(x0, 0.0025, z0), Vector3(x1, 0.0025, z0),
					Vector3(x1, 0.0025, z1), Vector3(x0, 0.0025, z1)], Vector3.UP)

	# Warm slate-stone border band framing the central checkerboard carpet of tiles.
	s.colour = TILE_BORDER.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		s.face([Vector3(side * 3.12, 0.003, -7.02), Vector3(side * 3.30, 0.003, -7.02),
				Vector3(side * 3.30, 0.003, 5.46), Vector3(side * 3.12, 0.003, 5.46)], Vector3.UP)

	# 3. Recessed central cast-iron floor heating grate strip down the forward walkway (z = -6.75 .. -1.65 m)!
	var gz0 := -6.75
	var gz1 := -1.65
	var gmid := (gz0 + gz1) * 0.5
	var glen := gz1 - gz0
	var ghw := 0.40

	# Deep pitch-dark recessed iron floor trench bottom (authentic unlit Victorian iron pit).
	s.surface(c.tinted("iron"))
	s.colour = Color(0.014, 0.016, 0.018).srgb_to_linear()
	s.face([Vector3(-ghw, 0.002, gz0), Vector3(ghw, 0.002, gz0),
			Vector3(ghw, 0.002, gz1), Vector3(-ghw, 0.002, gz1)], Vector3.UP)

	# Twin burnished oxidised-copper Victorian steam heating pipes resting cleanly inside the dark trench!
	u.surface(_brass_mat(c))
	u.colour = Color(0.58, 0.32, 0.15).srgb_to_linear()
	var pipe_b := Basis(Vector3.RIGHT, PI * 0.5)
	for px: float in [-0.15, 0.15]:
		Shapes.cylinder(u, Vector3(px, 0.009, gz0 + 0.10), 0.015, glen - 0.20, 6, pipe_b, false)

	# Moulded dark-sage cast-iron surround curb & crisp gunmetal Victorian slotted grille lattice bars!
	u.surface(c.soft("iron", true))
	u.colour = IRON_SAGE_DARK.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		u.box(Vector3(sx * (ghw + 0.038), 0.015, gmid), Vector3(0.076, 0.030, glen + 0.15), Basis(), [RoomMesh.DOWN])
	for sz: float in [gz0 - 0.038, gz1 + 0.038]:
		u.box(Vector3(0.0, 0.015, sz), Vector3(ghw * 2.0 + 0.15, 0.030, 0.076), Basis(), [RoomMesh.DOWN])
	# Three longitudinal grate stringers + 24 bold spaced transverse Victorian cast-iron grille slats!
	u.colour = Color(0.24, 0.29, 0.27).srgb_to_linear()
	for lx: float in [-0.22, 0.0, 0.22]:
		u.box(Vector3(lx, 0.025, gmid), Vector3(0.026, 0.010, glen), Basis(), [RoomMesh.DOWN])
	const SLATS := 24
	for k in SLATS:
		var sz := lerpf(gz0 + 0.10, gz1 - 0.10, float(k) / float(SLATS - 1))
		u.box(Vector3(0.0, 0.027, sz), Vector3(ghw * 2.0 - 0.02, 0.010, 0.034), Basis(), [RoomMesh.DOWN])


## Weathered rose-brick perimeter dwarf walls (y = 0..0.95 m) with plinth courses and moulded pale limestone coping
## ledges along port, starboard, the 5-facet front apse, and aft door flanks.
static func _dwarf_walls_and_coping(c: Object) -> void:
	var s: RoomMesh = c.s
	var brick_m: Material = c.tinted("roof")
	var stone_m: Material = c.tinted("stone", "quarry_tiles")

	# Helper segments: [p_a (Vector2), p_b (Vector2)] running clockwise from above (inward normal = along x UP).
	var wall_segs: Array = [
		# Port straight side wall (running from aft to front so along x UP points +X inward!)
		[Vector2(-HW, BACK_Z), Vector2(-HW, FRONT_SIDE_Z)],
		# 5 front apse segments
		[APSE[0], APSE[1]], [APSE[1], APSE[2]], [APSE[2], APSE[3]], [APSE[3], APSE[4]], [APSE[4], APSE[5]],
		# Starboard straight side wall (front to aft -> along x UP points -X inward!)
		[Vector2(HW, FRONT_SIDE_Z), Vector2(HW, BACK_Z)],
		# Aft wall segments flanking the central Victorian double glass doors (x in [-1.44, +1.44] open!).
		[Vector2(HW, BACK_Z), Vector2(1.44, BACK_Z)],
		[Vector2(-1.44, BACK_Z), Vector2(-HW, BACK_Z)],
	]

	for seg: Array in wall_segs:
		var a2: Vector2 = seg[0]
		var b2: Vector2 = seg[1]
		var pa := Vector3(a2.x, 0.0, a2.y)
		var pb := Vector3(b2.x, 0.0, b2.y)
		var flen := pa.distance_to(pb)
		var along := (pb - pa) / flen
		var n := along.cross(Vector3.UP).normalized()
		var wb := Basis(along, Vector3.UP, n)
		var mid := (pa + pb) * 0.5

		# Main weathered rose-brick masonry dwarf wall (y = 0.0 .. 0.94 m, thickness 0.24 m).
		s.surface(brick_m)
		s.colour = BRICK_ROSE.srgb_to_linear()
		s.box(mid + Vector3(0.0, DWARF_H * 0.5, 0.0), Vector3(flen + 0.14, DWARF_H, 0.24), wb, [RoomMesh.DOWN])
		# Darker weathered base plinth course (y = 0.0 .. 0.16 m).
		s.colour = BRICK_DEEP.srgb_to_linear()
		s.box(mid + n * 0.125 + Vector3(0.0, 0.08, 0.0), Vector3(flen + 0.06, 0.16, 0.03), wb, [RoomMesh.DOWN])

		# Moulded pale limestone coping sill crowning the brick dwarf wall (y = 0.94 .. 1.02 m).
		s.surface(stone_m)
		s.colour = STONE_COPING.srgb_to_linear()
		s.box(mid + n * 0.02 + Vector3(0.0, DWARF_H + 0.035, 0.0), Vector3(flen + 0.20, 0.08, 0.34), wb)


## Heritage sage-green painted cast-iron Victorian conservatory skeleton: fluted wall pilasters, 7 open-web arched
## barrel-vault lattice trusses with circular iron spandrel rings, intermediate arched ribs, glazing mullions &
## fanlight eyebrows, horizontal roof purlins, and ornate Victorian ridge lantern cresting finials.
static func _wrought_iron_structure_and_vault(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var iron_s: Material = c.tinted("iron")
	var iron_u: Material = c.soft("iron", true)

	# 1. Seven grand open-web twin-chord arched barrel-vault lattice trusses & fluted side pilasters!
	const ARCH_SEGS := 16
	const RING_COUNT := 13
	for rz: float in RIB_ZS:
		# Left & right vertical cast-iron fluted pilasters rising from stone coping (y = 1.00 .. 3.05 m).
		for side: float in [-1.0, 1.0]:
			var px := side * ARCH_HW
			s.surface(iron_s)
			s.colour = IRON_SAGE.srgb_to_linear()
			s.box(Vector3(px, (DWARF_H + 0.07 + EAVE_Y) * 0.5, rz), Vector3(0.16, EAVE_Y - DWARF_H - 0.07, 0.16))
			# Plinth shoe & ornate moulded capital collar.
			u.surface(iron_u)
			u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
			u.box(Vector3(px, DWARF_H + 0.12, rz), Vector3(0.22, 0.10, 0.22))
			u.box(Vector3(px, EAVE_Y - 0.08, rz), Vector3(0.24, 0.12, 0.22))
			# Decorative iron knee spandrel bracket tucking the pilaster gracefully into the arch rib!
			var bx := px - side * 0.24
			Shapes.beam(u, Vector3(px - side * 0.08, EAVE_Y - 0.58, rz), Vector3(px - side * 0.42, EAVE_Y + 0.04, rz),
					Vector2(0.036, 0.042))
			Shapes.arch(u, Vector3(bx, EAVE_Y - 0.22, rz), 0.10, 0.13, 0.032, 10, Basis(), 0.0, TAU,
					["front", "back", "inner", "outer"])

		# Outer & inner arch truss chords sweeping across the barrel-vault ceiling (theta = 0 .. PI).
		s.surface(iron_s)
		s.colour = IRON_SAGE.srgb_to_linear()
		u.surface(iron_u)
		u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
		var prev_out := Vector3(ARCH_HW, EAVE_Y, rz)
		var prev_in := Vector3(ARCH_HW - 0.32, EAVE_Y, rz)
		for k in range(1, ARCH_SEGS + 1):
			var th := PI * float(k) / float(ARCH_SEGS)
			var cur_out := Vector3(ARCH_HW * cos(th), EAVE_Y + ARCH_RISE * sin(th), rz)
			var cur_in := Vector3((ARCH_HW - 0.32) * cos(th), EAVE_Y + (ARCH_RISE - 0.32) * sin(th), rz)
			Shapes.beam(s, prev_out, cur_out, Vector2(0.095, 0.11))
			Shapes.beam(u, prev_in, cur_in, Vector2(0.055, 0.068))
			prev_out = cur_out
			prev_in = cur_in

		# Ornate circular cast-iron Victorian spandrel rings nestled between outer & inner arch chords!
		u.surface(iron_u)
		u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
		for rk in RING_COUNT:
			var th := lerpf(0.14, PI - 0.14, float(rk) / float(RING_COUNT - 1))
			var rm_x := (ARCH_HW - 0.16) * cos(th)
			var rm_y := EAVE_Y + (ARCH_RISE - 0.16) * sin(th)
			Shapes.arch(u, Vector3(rm_x, rm_y, rz), 0.112, 0.145, 0.038, 10, Basis(), 0.0, TAU,
					["front", "back", "inner", "outer"])

	# 2. Six intermediate slender arched glazing ribs bisecting each 2.30 m bay cleanly!
	u.surface(iron_u)
	u.colour = IRON_SAGE.srgb_to_linear()
	for bi in RIB_ZS.size() - 1:
		var mz := (RIB_ZS[bi] + RIB_ZS[bi + 1]) * 0.5
		var prev := Vector3(ARCH_HW, EAVE_Y, mz)
		for k in range(1, 13):
			var th := PI * float(k) / 12.0
			var cur := Vector3(ARCH_HW * cos(th), EAVE_Y + ARCH_RISE * sin(th), mz)
			Shapes.beam(u, prev, cur, Vector2(0.042, 0.052))
			prev = cur

	# 3. Continuous longitudinal eave cornice beams, 6 horizontal arched-roof glazing purlins & ridge spine!
	var hall_len := BACK_Z - FRONT_SIDE_Z
	var hall_mid_z := (BACK_Z + FRONT_SIDE_Z) * 0.5
	s.surface(iron_s)
	s.colour = IRON_SAGE_DARK.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		# Main eave gutter cornice beam at y = 3.05 m.
		s.box(Vector3(side * ARCH_HW, EAVE_Y + 0.03, hall_mid_z), Vector3(0.22, 0.16, hall_len + 0.16))
		# Wall transom rail at y = 2.48 m dividing main side glass from upper arched fanlights.
		u.surface(iron_u)
		u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
		u.box(Vector3(side * ARCH_HW, 2.48, hall_mid_z), Vector3(0.075, 0.055, hall_len))
		# Three horizontal glazing purlins along each curved roof slope.
		for deg: float in [24.0, 50.0, 74.0]:
			var th := deg_to_rad(deg)
			var px := side * ARCH_HW * cos(th)
			var py := EAVE_Y + ARCH_RISE * sin(th)
			u.box(Vector3(px, py, hall_mid_z), Vector3(0.045, 0.055, hall_len), Basis(Vector3.BACK, side * th))

		# Delicate side-wall glazing mullions, arched fanlight eyebrows & circular spandrel eyelets in every bay!
		for bi in RIB_ZS.size() - 1:
			var z0 := RIB_ZS[bi]
			var z1 := RIB_ZS[bi + 1]
			var bw := z1 - z0
			var wb := Basis(Vector3.UP, PI * 0.5 * side)
			for m in range(1, 3):
				var mz := lerpf(z0, z1, float(m) / 3.0)
				u.colour = IRON_SAGE.srgb_to_linear()
				u.box(Vector3(side * ARCH_HW, (DWARF_H + 0.07 + EAVE_Y) * 0.5, mz),
						Vector3(0.045, EAVE_Y - DWARF_H - 0.07, 0.045))
			# Three dainty arched fanlight heads per side bay (y = 2.48..2.98 m).
			u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
			for sub in 3:
				var sz := z0 + bw * (float(sub) + 0.5) / 3.0
				Shapes.arch(u, Vector3(side * (ARCH_HW - 0.01), 2.50, sz), 0.31, 0.345, 0.036, 8, wb, 0.0, PI,
						["front", "back", "inner", "outer"])
			# Ornate circular eyelet spandrels between the arched fanlights!
			for sub in 2:
				var ez := z0 + bw * float(sub + 1) / 3.0
				Shapes.arch(u, Vector3(side * (ARCH_HW - 0.01), 2.84, ez), 0.065, 0.092, 0.034, 8, wb, 0.0, TAU,
						["front", "back", "inner", "outer"])

	# 4. Ornate Victorian cast-iron ridge lantern beam & decorative filigree cresting finial spine along crown (y = 6.00..6.38 m)!
	s.surface(iron_s)
	s.colour = IRON_SAGE_DARK.srgb_to_linear()
	s.box(Vector3(0.0, CROWN_Y + 0.05, hall_mid_z), Vector3(0.18, 0.14, hall_len + 0.16))
	u.surface(iron_u)
	u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
	u.box(Vector3(0.0, CROWN_Y + 0.34, hall_mid_z), Vector3(0.06, 0.04, hall_len + 0.08))
	var ridge_b := Basis(Vector3.UP, PI * 0.5)
	const CREST_COUNT := 20
	for k in CREST_COUNT:
		var cz := lerpf(FRONT_SIDE_Z + 0.35, BACK_Z - 0.35, float(k) / float(CREST_COUNT - 1))
		Shapes.arch(u, Vector3(0.0, CROWN_Y + 0.21, cz), 0.09, 0.118, 0.03, 8, ridge_b, 0.0, TAU,
				["front", "back", "inner", "outer"])
		u.box(Vector3(0.0, CROWN_Y + 0.42, cz), Vector3(0.025, 0.16, 0.025))


## Front 5-facet glazed conservatory apse half-dome + arched sage-green wrought-iron Victorian botanical trellis
## framing the cinema screen (center [0.0, 2.35, -8.0], size [4.8, 2.7], 100% clear of sight lines!) over a low
## weathered rose-brick fern trough.
static func _front_apse_and_screen_trellis(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var iron_s: Material = c.tinted("iron")
	var iron_u: Material = c.soft("iron", true)
	var brick_m: Material = c.tinted("roof")
	var stone_m: Material = c.tinted("stone", "quarry_tiles")

	# --- A. Five-facet front apse iron piers, curved half-dome hip ribs & central apse glazing ---
	var apex := Vector3(0.0, CROWN_Y, FRONT_SIDE_Z)
	for i in range(1, APSE.size() - 1):
		var v := APSE[i]
		s.surface(iron_s)
		s.colour = IRON_SAGE.srgb_to_linear()
		s.box(Vector3(v.x, (DWARF_H + 0.07 + EAVE_Y) * 0.5, v.y), Vector3(0.14, EAVE_Y - DWARF_H - 0.07, 0.14))
		# Curved wrought-iron hip arch rib sweeping cleanly from each apse pilaster up to the front vault apex!
		u.surface(iron_u)
		u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
		var eave_p := Vector3(v.x, EAVE_Y, v.y)
		var prev := apex
		for k in range(1, 9):
			var t := float(k) / 8.0
			var cur := GreenhouseAtmosphereHall._apse_dome_pt(apex, eave_p, t)
			Shapes.beam(u, prev, cur, Vector2(0.075, 0.085))
			prev = cur

	# Horizontal apse eave cornice, wall transoms & curved dome purlins across all 5 apse facets.
	for ei in APSE.size() - 1:
		var a2 := APSE[ei]
		var b2 := APSE[ei + 1]
		var pa := Vector3(a2.x, 0.0, a2.y)
		var pb := Vector3(b2.x, 0.0, b2.y)
		var flen := pa.distance_to(pb)
		var along := (pb - pa) / flen
		var n := along.cross(Vector3.UP).normalized()
		var wb := Basis(along, Vector3.UP, n)
		var mid := (pa + pb) * 0.5

		s.surface(iron_s)
		s.colour = IRON_SAGE_DARK.srgb_to_linear()
		s.box(mid + Vector3(0.0, EAVE_Y + 0.03, 0.0), Vector3(flen + 0.14, 0.15, 0.18), wb)
		u.surface(iron_u)
		u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
		u.box(mid + Vector3(0.0, 2.48, 0.0), Vector3(flen, 0.05, 0.065), wb)
		# Intermediate vertical mullion per apse facet.
		u.colour = IRON_SAGE.srgb_to_linear()
		var subs := 3 if ei == 2 else 2
		for m in range(1, subs):
			var mp := pa.lerp(pb, float(m) / float(subs))
			u.box(mp + Vector3(0.0, (DWARF_H + 0.07 + EAVE_Y) * 0.5, 0.0),
					Vector3(0.042, EAVE_Y - DWARF_H - 0.07, 0.042), wb)
		# Curved dome purlin rings at two elevations across the apse half-dome.
		for tf: float in [0.42, 0.72]:
			var qa := GreenhouseAtmosphereHall._apse_dome_pt(apex, pa + Vector3(0.0, EAVE_Y, 0.0), tf)
			var qb := GreenhouseAtmosphereHall._apse_dome_pt(apex, pb + Vector3(0.0, EAVE_Y, 0.0), tf)
			Shapes.beam(u, qa, qb, Vector2(0.042, 0.048))

	# Single-surface PieceGlass ONLY on the central rear-of-screen apse panel (facets 0, 1, 3, 4 use weather.panes!)
	glass.surface(c.kit.GLASS)
	var c0 := Vector3(APSE[2].x, DWARF_H + 0.06, APSE[2].y)
	var c1 := Vector3(APSE[3].x, DWARF_H + 0.06, APSE[3].y)
	glass.face([c0, c1, c1 + Vector3(0.0, EAVE_Y - DWARF_H - 0.06, 0.0),
			c0 + Vector3(0.0, EAVE_Y - DWARF_H - 0.06, 0.0)], Vector3.BACK)

	# --- B. Victorian Botanical Wrought-Iron Screen Trellis Mount (center [0.0, 2.35, -8.0], size [4.8, 2.7]) ---
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 2.35, -8.0)))
	var sc_sz: Vector2 = scr.get("size", Vector2(4.8, 2.7))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y # 2.35
	var cz := sc_xf.origin.z # -8.00
	var hw := sc_sz.x * 0.5 # 2.40
	var hh := sc_sz.y * 0.5 # 1.35
	var sc_bot := cy - hh   # 1.00
	var sc_top := cy + hh   # 3.70

	# 1. Slim matte dark-iron screen backing panel strictly behind the picture plane (z = -8.04 .. -8.14 m)
	#    so moonlight and rain outside never wash out the film, with a crisp thin dark-sage bezel!
	s.surface(iron_s)
	s.colour = Color(0.045, 0.055, 0.052).srgb_to_linear()
	s.box(Vector3(cx, cy, cz - 0.095), Vector3(sc_sz.x + 0.14, sc_sz.y + 0.14, 0.11))
	u.surface(iron_u)
	u.colour = IRON_SAGE_DARK.srgb_to_linear()
	var bt := 0.055
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * (hw + bt * 0.5 + 0.015), cy, cz - 0.03), Vector3(bt, sc_sz.y + bt * 2.0 + 0.04, 0.07))
	u.box(Vector3(cx, sc_bot - bt * 0.5 - 0.015, cz - 0.03), Vector3(sc_sz.x + bt * 2.0 + 0.04, bt, 0.07))
	u.box(Vector3(cx, sc_top + bt * 0.5 + 0.015, cz - 0.03), Vector3(sc_sz.x + bt * 2.0 + 0.04, bt, 0.07))

	# 2. Low weathered rose-brick & limestone fern planter trough beneath the screen (y = 0.0 .. 0.72 m, z = -8.10).
	s.surface(brick_m)
	s.colour = BRICK_ROSE.srgb_to_linear()
	s.box(Vector3(cx, 0.34, cz - 0.12), Vector3(sc_sz.x + 1.36, 0.68, 0.54), Basis(), [RoomMesh.DOWN])
	s.surface(stone_m)
	s.colour = STONE_COPING.srgb_to_linear()
	s.box(Vector3(cx, 0.71, cz - 0.10), Vector3(sc_sz.x + 1.48, 0.07, 0.64))
	# Dark soil bed inside the brick screen planter trough.
	u.surface(c.soft("wood", true))
	u.colour = SOIL_DARK.srgb_to_linear()
	u.box(Vector3(cx, 0.69, cz - 0.10), Vector3(sc_sz.x + 0.90, 0.04, 0.42))
	c.shapes.append(PhysicsShapes.box(Vector3(cx, 0.38, cz - 0.12), Vector3(sc_sz.x + 1.48, 0.76, 0.64)))

	# 3. Flanking ornate sage-green cast-iron Victorian botanical trellis columns (strictly outside |x| >= 2.58 m!).
	for side: float in [-1.0, 1.0]:
		var x_in := cx + side * 2.60
		var x_out := cx + side * 3.04
		var xm := (x_in + x_out) * 0.5
		var tz := cz - 0.08
		# Brick & stone pedestal foot anchoring each trellis pier cleanly to the quarry-tile floor.
		s.surface(brick_m)
		s.colour = BRICK_DEEP.srgb_to_linear()
		s.box(Vector3(xm, 0.44, tz), Vector3(0.62, 0.88, 0.56), Basis(), [RoomMesh.DOWN])
		s.surface(stone_m)
		s.colour = STONE_COPING.srgb_to_linear()
		s.box(Vector3(xm, 0.91, tz), Vector3(0.70, 0.08, 0.64))
		# Twin vertical sage-green cast-iron trellis standards + decorative diamond latticework!
		u.surface(iron_u)
		u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
		Shapes.cylinder(u, Vector3(x_in, 0.94, tz), 0.036, 2.94, 8)
		Shapes.cylinder(u, Vector3(x_out, 0.94, tz), 0.042, 2.94, 8)
		# Horizontal trellis transom bars & open diamond X-lattice scrollwork between the twin posts.
		for k in 6:
			var y0 := 1.02 + float(k) * 0.46
			var y1 := y0 + 0.46
			u.box(Vector3(xm, y0, tz), Vector3(0.44, 0.026, 0.032))
			Shapes.beam(u, Vector3(x_in, y0, tz), Vector3(x_out, y1, tz), Vector2(0.018, 0.020))
			Shapes.beam(u, Vector3(x_out, y0, tz), Vector3(x_in, y1, tz), Vector2(0.018, 0.020))
		# Cast-iron capital collar + decorative finial urn boss crowning the outer post!
		u.box(Vector3(xm, 3.88, tz), Vector3(0.56, 0.08, 0.14))
		Shapes.lathe(u, [Vector2(0.05, 0.0), Vector2(0.075, 0.07), Vector2(0.03, 0.14), Vector2(0.0, 0.22)],
				Vector3(x_out, 3.92, tz), 8)
		# Rear strut bracing the trellis solidly back to the front apse iron structure.
		Shapes.beam(u, Vector3(x_out, 3.84, tz), Vector3(x_out * 1.06, 3.05, FRONT_APSE_Z + 0.12), Vector2(0.035, 0.035))
		c.shapes.append(PhysicsShapes.box(Vector3(xm, 2.0, tz), Vector3(0.62, 4.0, 0.56)))

	# 4. Sweeping Victorian arched wrought-iron botanical trellis crown soaring above the screen (y = 3.80 .. 5.25 m)!
	#    Openwork double-chord iron arch + circular filigree spandrel rings + radial cresting finials!
	var tz := cz - 0.08
	u.surface(iron_u)
	u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
	# Horizontal tie chord right above the screen bezel (y = 3.82 m, strictly above screen top 3.70 m!).
	u.box(Vector3(cx, 3.84, tz), Vector3(6.14, 0.065, 0.09))
	const TRELLIS_SEGS := 18
	var prev_a := Vector3(cx + 3.04, 3.84, tz)
	var prev_b := Vector3(cx + 2.60, 3.84, tz)
	for k in range(1, TRELLIS_SEGS + 1):
		var th := PI * float(k) / float(TRELLIS_SEGS)
		var cur_a := Vector3(cx + 3.04 * cos(th), 3.84 + 1.38 * sin(th), tz)
		var cur_b := Vector3(cx + 2.60 * cos(th), 3.84 + 1.02 * sin(th), tz)
		Shapes.beam(u, prev_a, cur_a, Vector2(0.055, 0.068))
		Shapes.beam(u, prev_b, cur_b, Vector2(0.040, 0.048))
		prev_a = cur_a
		prev_b = cur_b
	# Eleven ornate Victorian cast-iron spandrel rings between the twin trellis arch chords!
	for rk in 11:
		var th := lerpf(0.22, PI - 0.22, float(rk) / 10.0)
		var rx := cx + 2.82 * cos(th)
		var ry := 3.84 + 1.20 * sin(th)
		Shapes.arch(u, Vector3(rx, ry, tz), 0.11, 0.142, 0.036, 10, Basis(), 0.0, TAU,
				["front", "back", "inner", "outer"])
	# Delicate open sunburst trellis spokes & central king-post anchoring the rosette medallion cleanly!
	for sk in 9:
		var th := lerpf(0.25, PI - 0.25, float(sk) / 8.0)
		var p_top := Vector3(cx + 2.58 * cos(th), 3.84 + 1.00 * sin(th), tz)
		var p_bot := Vector3(cx + 0.55 * cos(th), 3.84, tz)
		Shapes.beam(u, p_bot, p_top, Vector2(0.022, 0.024))
	# Central cast-iron king-post tying the horizontal bar (y = 3.84) straight through the medallion to the crown!
	Shapes.beam(u, Vector3(cx, 3.84, tz), Vector3(cx, 5.24, tz), Vector2(0.036, 0.038))
	var med := Vector3(cx, 4.34, tz)
	Shapes.arch(u, med, 0.21, 0.26, 0.038, 16, Basis(), 0.0, TAU, ["front", "back", "inner", "outer"])
	# Central gilded brass & sage-iron botanical rosette medallion & finial spire crowning the screen trellis!
	var crest := Vector3(cx, 5.26, tz)
	Shapes.lathe(u, [Vector2(0.06, -0.04), Vector2(0.09, 0.06), Vector2(0.03, 0.20), Vector2(0.0, 0.42)], crest, 8)
	u.surface(_brass_mat(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.arch(u, med, 0.14, 0.18, 0.032, 14, Basis(), 0.0, TAU, ["front", "back", "inner", "outer"])
	for rk in 8:
		var ra := TAU * float(rk) / 8.0
		Shapes.beam(u, med, med + Vector3(cos(ra) * 0.21, sin(ra) * 0.21, 0.0), Vector2(0.016, 0.016))
	Shapes.lathe(u, [Vector2(0.0, 0.0), Vector2(0.055, 0.06), Vector2(0.0, 0.12)], crest + Vector3(0.0, 0.36, 0.0), 8)


## Aft Victorian double glass-and-iron conservatory doors (z = +6.15 m) with ornate brass lever handles, glazed
## semicircular fanlight, and soaring radial sunburst rose-fan glass gable arch (y = 3.05..6.00 m).
static func _aft_double_doors_and_rose_gable(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var iron_s: Material = c.tinted("iron")
	var iron_u: Material = c.soft("iron", true)
	var stone_m: Material = c.tinted("stone", "quarry_tiles")

	var dz := BACK_Z - 0.04
	var door_hw := 1.40
	var door_h := 2.78

	# 1. Weathered limestone threshold sill & outer cast-iron door surround jambs.
	s.surface(stone_m)
	s.colour = STONE_COPING.srgb_to_linear()
	s.box(Vector3(0.0, 0.025, dz), Vector3(door_hw * 2.0 + 0.30, 0.05, 0.38), Basis(), [RoomMesh.DOWN])

	s.surface(iron_s)
	s.colour = IRON_SAGE_DARK.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(side * (door_hw + 0.06), (EAVE_Y + 0.04) * 0.5, dz), Vector3(0.14, EAVE_Y, 0.20), Basis(),
				[RoomMesh.DOWN])
	s.box(Vector3(0.0, EAVE_Y + 0.03, dz), Vector3(HW * 2.0, 0.16, 0.20))

	# 2. Twin Victorian cast-iron & glass conservatory door leaves (left & right).
	u.surface(iron_u)
	for side: float in [-1.0, 1.0]:
		var lx := side * (door_hw * 0.5)
		var lw := door_hw - 0.04
		# Solid moulded sage-green cast-iron lower kick panel (y = 0.05..0.94 m) with recessed bead panel.
		s.surface(iron_s)
		s.colour = IRON_SAGE.srgb_to_linear()
		s.box(Vector3(lx, 0.50, dz), Vector3(lw, 0.88, 0.07))
		u.surface(iron_u)
		u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
		u.box(Vector3(lx, 0.50, dz - 0.04), Vector3(lw - 0.20, 0.62, 0.024))
		# Door stiles, top rail, and 2x3 fine Georgian/Victorian glazing bars (y = 0.94..2.74 m)!
		u.colour = IRON_SAGE.srgb_to_linear()
		for sx: float in [-1.0, 1.0]:
			u.box(Vector3(lx + sx * (lw * 0.5 - 0.045), 1.84, dz), Vector3(0.09, 1.84, 0.07))
		u.box(Vector3(lx, door_h - 0.045, dz), Vector3(lw, 0.09, 0.07))
		u.box(Vector3(lx, 1.84, dz), Vector3(0.032, 1.74, 0.04))
		for gy: float in [1.46, 2.02, 2.48]:
			u.box(Vector3(lx, gy, dz), Vector3(lw - 0.10, 0.032, 0.04))
		# Gleaming curved Victorian brass lever door handles & lock backplates!
		u.surface(_brass_mat(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		var hx := side * 0.11
		u.box(Vector3(hx, 1.06, dz - 0.045), Vector3(0.045, 0.24, 0.018))
		Shapes.cylinder(u, Vector3(hx, 1.08, dz - 0.085), 0.014, 0.055, 8, Basis(Vector3.RIGHT, PI * 0.5))
		Shapes.beam(u, Vector3(hx, 1.08, dz - 0.095), Vector3(hx + side * 0.12, 1.06, dz - 0.095), Vector2(0.022, 0.022))
		# Gleaming brass threshold kickstrip along bottom of each door leaf.
		u.colour = BRASS_WARM.srgb_to_linear()
		u.box(Vector3(lx, 0.11, dz - 0.04), Vector3(lw - 0.06, 0.10, 0.014))

	# Glazed upper door panes + overhead transom fanlight (`PieceGlass`).
	glass.surface(c.kit.GLASS)
	glass.face([Vector3(-door_hw + 0.04, 0.94, dz), Vector3(door_hw - 0.04, 0.94, dz),
			Vector3(door_hw - 0.04, EAVE_Y, dz), Vector3(-door_hw + 0.04, EAVE_Y, dz)], Vector3.FORWARD)

	# Aft vertical wall mullions flanking the double doors (x in [-5.56..-1.46] and [+1.46..+5.56]).
	u.surface(iron_u)
	for side: float in [-1.0, 1.0]:
		u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
		u.box(Vector3(side * 3.50, 2.48, dz), Vector3(4.10, 0.055, 0.07))
		u.colour = IRON_SAGE.srgb_to_linear()
		for mx: float in [2.35, 3.42, 4.48]:
			u.box(Vector3(side * mx, (DWARF_H + 0.07 + EAVE_Y) * 0.5, dz),
					Vector3(0.045, EAVE_Y - DWARF_H - 0.07, 0.05))

	# 3. Soaring Aft Arched Glass Gable (y = 3.05..6.00 m, z = +6.18 m) with radial Victorian sunburst iron tracery!
	u.surface(iron_u)
	u.colour = IRON_SAGE_LIGHT.srgb_to_linear()
	# Concentric inner semicircular iron rose-fan rings.
	for frac: float in [0.32, 0.64]:
		var prev := Vector3(ARCH_HW * frac, EAVE_Y, dz)
		for k in range(1, 15):
			var th := PI * float(k) / 14.0
			var cur := Vector3(ARCH_HW * frac * cos(th), EAVE_Y + ARCH_RISE * frac * sin(th), dz)
			Shapes.beam(u, prev, cur, Vector2(0.042, 0.048))
			prev = cur
	# Twelve radial Victorian iron sunburst mullions fanning out from the gable spring centre (0, EAVE_Y, dz)!
	for k in range(1, 12):
		var th := PI * float(k) / 12.0
		var p_in := Vector3(ARCH_HW * 0.14 * cos(th), EAVE_Y + ARCH_RISE * 0.14 * sin(th), dz)
		var p_out := Vector3(ARCH_HW * cos(th), EAVE_Y + ARCH_RISE * sin(th), dz)
		Shapes.beam(u, p_in, p_out, Vector2(0.036, 0.042))
	# Central half-sunburst brass boss medallion crowning the aft door entablature.
	u.surface(_brass_mat(c))
	u.colour = BRASS_WARM.srgb_to_linear()
	Shapes.arch(u, Vector3(0.0, EAVE_Y + 0.04, dz - 0.03), 0.16, 0.24, 0.035, 12, Basis(), 0.0, PI,
			["front", "back", "inner", "outer"])

	# Single-surface PieceGlass filling the entire aft arched gable!
	var gable_pts: Array = []
	for k in 17:
		var th := PI * float(k) / 16.0
		gable_pts.append(Vector3(ARCH_HW * cos(th), EAVE_Y + ARCH_RISE * sin(th), dz + 0.02))
	glass.face(gable_pts, Vector3.FORWARD)


## Shallow circular carved limestone Victorian drip fountain basin (front-starboard alcove at FOUNTAIN_POS) with
## central tiered pedestal, bronze leaf-lip spout, and animated rippling water & falling jet (`PieceWater`).
static func _stone_drip_fountain(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var w: RoomMesh = c.water
	var fc := FOUNTAIN_POS

	# 1. Stepped octagonal stone floor plinth + carved circular limestone basin rim (r_out = 0.94 m, h = 0.50 m).
	s.surface(c.tinted("stone", "quarry_tiles"))
	s.colour = STONE_AGED.srgb_to_linear()
	Shapes.lathe(s, [Vector2(1.06, 0.0), Vector2(1.04, 0.08), Vector2(0.92, 0.10)], fc, 16)
	s.colour = STONE_BASIN.srgb_to_linear()
	Shapes.lathe(s, [
		Vector2(0.92, 0.08), Vector2(0.90, 0.42), Vector2(0.98, 0.45), Vector2(0.98, 0.51),
		Vector2(0.84, 0.52), Vector2(0.76, 0.48), Vector2(0.76, 0.14), Vector2(0.0, 0.14),
	], fc, 20)

	# 2. Central carved Victorian fluted limestone pedestal, upper catch-bowl & patinated bronze finial spout!
	u.surface(c.soft("stone", true))
	u.colour = STONE_COPING.srgb_to_linear()
	Shapes.lathe(u, [
		Vector2(0.26, 0.14), Vector2(0.24, 0.24), Vector2(0.14, 0.36), Vector2(0.12, 0.72),
		Vector2(0.18, 0.80), Vector2(0.36, 0.88), Vector2(0.38, 0.94), Vector2(0.30, 0.95),
		Vector2(0.24, 0.89), Vector2(0.08, 0.92), Vector2(0.09, 1.12), Vector2(0.0, 1.16),
	], fc, 14)

	# Patinated bronze fountain nozzle crown & four delicate arched side spouts!
	u.surface(_brass_mat(c))
	u.colour = BRASS_AGED.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.06, 1.12), Vector2(0.04, 1.24), Vector2(0.025, 1.30), Vector2(0.0, 1.32)], fc, 10)

	# 3. Animated dark reflective basin water with concentric ripples + shimmering falling water streams (`PieceWater`)!
	w.surface(c.kit.water_material())
	# Basin disc at y = 0.42 m (UV starts at 0..1.54 m so centre sits at UV (0.77, 0.77) -> COLOR.gb = 0.77/4 = 0.1925!).
	w.colour = Color(0.0, 0.1925, 0.1925, 1.0)
	var disc: Array = []
	for k in 20:
		var a := TAU * float(k) / 20.0
		disc.append(fc + Vector3(cos(a) * 0.77, 0.42, sin(a) * 0.77))
	w.face(disc, Vector3.UP)
	# Upper catch-bowl water disc at y = 0.92 m.
	w.colour = Color(0.0, 0.075, 0.075, 1.0)
	var top_disc: Array = []
	for k in 14:
		var a := TAU * float(k) / 14.0
		top_disc.append(fc + Vector3(cos(a) * 0.30, 0.92, sin(a) * 0.30))
	w.face(top_disc, Vector3.UP)
	# Four slender shimmering falling drip streams cascading from the upper bowl lip into the main basin (COLOR.r = 1!).
	w.colour = Color(1.0, 0.0, 0.0, 1.0)
	for k in 4:
		var a := float(k) * PI * 0.5 + PI * 0.25
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := dir.cross(Vector3.UP).normalized() * 0.018
		var a_line := PackedVector3Array()
		var b_line := PackedVector3Array()
		var ns := PackedVector3Array()
		for j in 7:
			var t := float(j) / 6.0
			var pt := fc + dir * (0.34 + 0.16 * t) + Vector3(0.0, lerpf(0.93, 0.41, t * t), 0.0)
			a_line.append(pt - side)
			b_line.append(pt + side)
			ns.append((dir + Vector3.UP * 0.25).normalized())
		w.strip(a_line, b_line, ns)

	# Physics collider strictly clear of origin (distance 5.73 m!).
	c.shapes.append(PhysicsShapes.box(fc + Vector3(0.0, 0.62, 0.0), Vector3(1.96, 1.24, 1.96)))


## Four hanging Victorian brass-and-opal-glass pendant lanterns along the vault crown (`c.lamps`), 2 aft door brass
## bracket sconces (`c.glow_lights`), concealed botanical uplight coves (`PieceCove`), and 4 live-colour botanical
## dwarf-wall uplight footlights (`c.footlights`: warm amber in `warm_brass`, emerald jade in `botanical`, soft in `dim`).
static func _pendant_lamps_and_coves(c: Object) -> void:
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove
	var shade_m: Material = c.shade(LAMP_WARM)
	lit.surface(shade_m)
	lit.colour = Color.WHITE

	# 1. Four glowing Victorian brass hanging pendant lanterns suspended cleanly along the vault crown!
	#    y = 4.68 m keeps them soaring high above screen top (3.70 m) and every sight line!
	var pendant_zs: Array[float] = [-5.30, -1.85, 1.60, 4.45]
	for pz: float in pendant_zs:
		var top_p := Vector3(0.0, CROWN_Y - 0.02, pz)
		var cup_p := Vector3(0.0, 4.86, pz)
		# Brass ceiling rosette, suspension rod, bell hood & protective cage!
		u.surface(_brass_mat(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.09, -0.06), Vector2(0.05, -0.02), Vector2(0.02, 0.0)], top_p, 10)
		Shapes.cylinder(u, cup_p, 0.015, top_p.y - cup_p.y, 6)
		Shapes.lathe(u, [
			Vector2(0.03, 0.08), Vector2(0.11, 0.03), Vector2(0.24, -0.05), Vector2(0.22, -0.08),
		], cup_p, 12)
		# Lower brass acorn finial beneath the frosted opal lantern globe.
		Shapes.lathe(u, [
			Vector2(0.0, -0.44), Vector2(0.035, -0.38), Vector2(0.08, -0.32), Vector2(0.11, -0.30),
		], cup_p, 10)
		for k in 4:
			var a := float(k) * PI * 0.5 + PI * 0.25
			var off := Vector3(cos(a) * 0.145, 0.0, sin(a) * 0.145)
			Shapes.beam(u, cup_p + off + Vector3(0.0, -0.06, 0.0), cup_p + off + Vector3(0.0, -0.31, 0.0),
					Vector2(0.012, 0.012))
		# Glowing frosted-opal glass lantern globe (`PieceLamps`).
		lit.surface(shade_m)
		Shapes.lathe(lit, [
			Vector2(0.08, -0.31), Vector2(0.14, -0.25), Vector2(0.155, -0.16),
			Vector2(0.13, -0.08), Vector2(0.08, -0.05),
		], cup_p, 12)
		# Register as stand-in & bake lamp (4 overhead lamps + 4 botanical footlights = 8 MAX_LAMPS!).
		c.lamps.append([cup_p + Vector3(0.0, -0.22, 0.0), LAMP_WARM, 0.95])

	# 2. Two scrolled Victorian brass wall sconces flanking the aft conservatory double doors!
	for side: float in [-1.0, 1.0]:
		var base := Vector3(side * 1.76, 2.22, BACK_Z - 0.12)
		var cup := base + Vector3(0.0, 0.08, -0.24)
		u.surface(_brass_mat(c))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.cylinder(u, base, 0.085, 0.035, 10, Basis(Vector3.RIGHT, -PI * 0.5))
		Shapes.beam(u, base, cup + Vector3(0.0, -0.04, 0.0), Vector2(0.018, 0.018))
		Shapes.lathe(u, [Vector2(0.02, -0.04), Vector2(0.07, 0.0), Vector2(0.085, 0.03)], cup, 10)
		Shapes.lathe(u, [Vector2(0.13, 0.24), Vector2(0.06, 0.30), Vector2(0.0, 0.33)], cup, 10)
		lit.surface(shade_m)
		Shapes.lathe(lit, [
			Vector2(0.065, 0.02), Vector2(0.10, 0.09), Vector2(0.10, 0.19), Vector2(0.075, 0.24),
		], cup, 10)
		c.glow_lights.append([cup + Vector3(0.0, 0.12, -0.08), LAMP_WARM, 0.55, 5.0])

	# 3. Concealed botanical uplight coves (`PieceCove`) tucked cleanly beneath the rose-brick dwarf-wall stone coping
	#    overhangs and inside the recessed under-screen fern trough (realistic weathered stone/brick vertex albedo +
	#    gentle alpha gradient 0.54 -> 0.0 so they softly bathe brick & foliage without glowing like neon tubes!).
	cove.surface(c.kit.cove_material())
	var st_lin := COVE_STONE.srgb_to_linear()
	var stone_hi := Color(st_lin.r, st_lin.g, st_lin.b, 0.52)
	var stone_lo := Color(st_lin.r, st_lin.g, st_lin.b, 0.02)

	# Port & starboard narrow under-coping stone frieze cove tucked right beneath the limestone sill overhang
	# (y = 0.87..0.945 m so 100% of the weathered rose-brick courses below remain crisp and textured!) + concealed
	# uplight reveal tucked behind a slim dark sage-iron curb on the coping sill!
	u.surface(c.soft("iron", true))
	u.colour = IRON_SAGE_DARK.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var x_w := side * (INNER_X - 0.014)
		var rows := [
			PackedVector3Array([Vector3(x_w, 0.87, FRONT_SIDE_Z + 0.14), Vector3(x_w, 0.87, BACK_Z - 0.14)]),
			PackedVector3Array([Vector3(x_w, 0.945, FRONT_SIDE_Z + 0.14), Vector3(x_w, 0.945, BACK_Z - 0.14)]),
		]
		var n_in := Vector3(-side, -0.22, 0.0).normalized()
		var norms := [PackedVector3Array([n_in, n_in]), PackedVector3Array([n_in, n_in])]
		var cols := [PackedColorArray([stone_lo, stone_lo]), PackedColorArray([stone_hi, stone_hi])]
		if side < 0.0:
			rows.reverse()
			cols.reverse()
		cove.grid(rows, norms, cols)

		# Slim sage-iron lip curb along inner edge of stone coping concealing the upward botanical sill wash!
		var x_lip := side * (INNER_X - 0.14)
		u.box(Vector3(x_lip, DWARF_H + 0.095, (FRONT_SIDE_Z + BACK_Z) * 0.5),
				Vector3(0.032, 0.042, BACK_Z - FRONT_SIDE_Z - 0.20))
		# Softly washed recessed stone sill strip tucked behind the iron curb (visible from above & glancing angles).
		var x_in := side * (INNER_X - 0.12)
		var x_out := side * (INNER_X + 0.05)
		var s_rows := [
			PackedVector3Array([Vector3(x_in, DWARF_H + 0.079, FRONT_SIDE_Z + 0.15),
					Vector3(x_in, DWARF_H + 0.079, BACK_Z - 0.15)]),
			PackedVector3Array([Vector3(x_out, DWARF_H + 0.079, FRONT_SIDE_Z + 0.15),
					Vector3(x_out, DWARF_H + 0.079, BACK_Z - 0.15)]),
		]
		var up_n := PackedVector3Array([Vector3.UP, Vector3.UP])
		var s_cols := [PackedColorArray([stone_hi, stone_hi]), PackedColorArray([stone_lo, stone_lo])]
		if side > 0.0:
			s_rows.reverse()
			s_cols.reverse()
		cove.grid(s_rows, [up_n, up_n], s_cols)

	# Under-screen recessed fern trough back-wall wash (z = -8.28 behind the ferns, strictly clear of coping & screen!).
	var scr_rows := [
		PackedVector3Array([Vector3(-2.48, 0.72, -8.28), Vector3(2.48, 0.72, -8.28)]),
		PackedVector3Array([Vector3(-2.48, 0.93, -8.28), Vector3(2.48, 0.93, -8.28)]),
	]
	var bk_n := PackedVector3Array([Vector3.BACK, Vector3.BACK])
	var scr_cols := [
		PackedColorArray([Color(st_lin.r, st_lin.g, st_lin.b, 0.52), Color(st_lin.r, st_lin.g, st_lin.b, 0.52)]),
		PackedColorArray([Color(st_lin.r, st_lin.g, st_lin.b, 0.0), Color(st_lin.r, st_lin.g, st_lin.b, 0.0)]),
	]
	cove.grid(scr_rows, [bk_n, bk_n], scr_cols)

	# Four live-colour botanical uplight stand-in footlights tucked above the dwarf walls bathing palms, ferns & citrus!
	# (kit.gd binds c.footlights live to kit.cove_colour & kit.cove -> warm amber in warm_brass, emerald in botanical!)
	c.footlights.append([Vector3(-4.40, 1.32, -5.20), -1.0, 0.88])
	c.footlights.append([Vector3(4.40, 1.32, -5.20), -1.0, 0.88])
	c.footlights.append([Vector3(-4.40, 1.32, 1.80), -1.0, 0.78])
	c.footlights.append([Vector3(4.40, 1.32, 1.80), -1.0, 0.78])


# ======================================================================================================================
# PIECE 2: greenhouse_flora — Palms, ferns, citrus trees, ivy, potting benches, terracotta pots, bell cloches & props
# ======================================================================================================================

static func _build_flora(c: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1894
	_potting_benches_and_props(c, rng)
	_palms_and_elephant_ears(c, rng)
	_dwarf_citrus_trees(c, rng)
	_hanging_fern_baskets(c, rng)
	_ferns_and_climbing_ivy(c, rng)
	_aft_potting_table_and_lanterns(c, rng)


## Slatted western red-cedar & scrolled sage-iron potting benches along port & starboard walls, packed with turned
## terracotta clay pots, pot stacks, 4 glass bell cloches (PieceGlass), coiled brass watering can, trowel & seed tins!
static func _potting_benches_and_props(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var wood_s: Material = c.tinted("wood")
	var iron_u: Material = c.soft("iron", true)
	var stone_u: Material = c.soft("stone", true)
	var leaf_m: Material = c.soft("leaves", true)

	# Two cedar-and-iron potting benches: [side (-1 port / +1 starboard), z0, z1]
	var benches: Array = [
		[-1.0, -3.40, 3.80], # Port bench (7.20 m long!)
		[1.0, -2.15, 3.80],  # Starboard bench (5.95 m long, leaves front-starboard open for fountain!)
	]
	var bench_h := 0.84
	var bench_d := 0.84
	var shelf_y := 0.24

	for bdef: Array in benches:
		var side := float(bdef[0])
		var z0 := float(bdef[1])
		var z1 := float(bdef[2])
		var blen := z1 - z0
		var bmid := (z0 + z1) * 0.5
		var bx := side * (INNER_X - bench_d * 0.5 - 0.14) # +-4.92 m

		# Slatted warm western red-cedar tabletop (5 longitudinal cedar planks with narrow ventilation gaps!).
		s.surface(wood_s)
		for pl in 5:
			var px := bx - bench_d * 0.5 + 0.085 + float(pl) * 0.168
			s.colour = (CEDAR_WARM if pl % 2 == 0 else CEDAR_RICH).srgb_to_linear()
			s.box(Vector3(px, bench_h - 0.02, bmid), Vector3(0.142, 0.036, blen))
		# Lower slatted cedar pot shelf (3 planks at y = 0.24 m).
		for pl in 3:
			var px := bx - 0.26 + float(pl) * 0.26
			s.colour = CEDAR_RICH.srgb_to_linear()
			s.box(Vector3(px, shelf_y, bmid), Vector3(0.20, 0.028, blen - 0.20))

		# Ornate scrolled sage-green cast-iron bench legs & cross-stretchers!
		u.surface(iron_u)
		u.colour = IRON_SAGE_DARK.srgb_to_linear()
		var n_legs := 5 if blen > 6.5 else 4
		for li in n_legs:
			var lz := lerpf(z0 + 0.22, z1 - 0.22, float(li) / float(n_legs - 1))
			for sx: float in [-1.0, 1.0]:
				var lx := bx + sx * (bench_d * 0.5 - 0.06)
				u.box(Vector3(lx, bench_h * 0.5, lz), Vector3(0.045, bench_h, 0.045), Basis(), [RoomMesh.DOWN])
			u.box(Vector3(bx, bench_h - 0.06, lz), Vector3(bench_d - 0.08, 0.04, 0.04))
			u.box(Vector3(bx, shelf_y - 0.025, lz), Vector3(bench_d - 0.12, 0.035, 0.035))
			# Decorative iron knee scroll brace under the outer bench edge!
			var in_x := bx - side * (bench_d * 0.5 - 0.06)
			Shapes.beam(u, Vector3(in_x, bench_h - 0.30, lz), Vector3(in_x + side * 0.24, bench_h - 0.06, lz),
					Vector2(0.024, 0.024))
		# Longitudinal iron under-apron rails.
		for sx: float in [-1.0, 1.0]:
			u.box(Vector3(bx + sx * (bench_d * 0.5 - 0.06), bench_h - 0.07, bmid), Vector3(0.035, 0.055, blen - 0.20))

		c.shapes.append(PhysicsShapes.box(Vector3(bx, bench_h * 0.5, bmid), Vector3(bench_d, bench_h, blen)))

		# --- Populate each bench with rich terracotta clay pots, ferns, seedlings, cloches & stacks! ---
		var pot_count := 16 if side < 0.0 else 13
		for pi in pot_count:
			var pz := lerpf(z0 + 0.35, z1 - 0.35, (float(pi) + 0.35 * rng.randf()) / float(pot_count))
			# Keep clear of hero port watering can / hurricane lantern spots.
			if side < 0.0 and absf(pz - 0.12) < 0.36:
				continue
			if side < 0.0 and absf(pz + 0.42) < 0.24:
				continue
			var px := bx + rng.randf_range(-0.24, 0.24)
			var pr := rng.randf_range(0.085, 0.145)
			var ph := pr * rng.randf_range(1.35, 1.75)
			var clay := CLAY_WARM.lerp(CLAY_PALE if pi % 3 == 0 else CLAY_DEEP, rng.randf() * 0.65)
			_terracotta_pot(u, stone_u, c.soft("wood", true), Vector3(px, bench_h, pz), pr, ph, clay, true)
			# Plant lush small ferns or rosette foliage in each pot!
			if pi % 3 == 0:
				_fern_clump(u, leaf_m, Vector3(px, bench_h + ph - 0.02, pz), pr * 2.5, pr * 2.2, 6, rng)
			else:
				_rosette_plant(u, leaf_m, Vector3(px, bench_h + ph - 0.01, pz), pr * 1.45, rng)

		# Lower-shelf nested terracotta pot stacks (3–4 clay pots stacked snugly together!).
		for st_i in 3:
			var sz := lerpf(z0 + 0.90, z1 - 0.85, float(st_i) / 2.0)
			var sx := bx - side * 0.08
			for k in 3:
				_terracotta_pot(u, stone_u, c.soft("wood", true),
						Vector3(sx, shelf_y + 0.014 + float(k) * 0.068, sz), 0.11, 0.15,
						CLAY_WARM.lerp(CLAY_PALE, float(k) * 0.25), false)
			# Companion single terracotta pot beside the stack.
			_terracotta_pot(u, stone_u, c.soft("wood", true),
					Vector3(sx + side * 0.24, shelf_y + 0.014, sz + 0.22), 0.125, 0.19, CLAY_DEEP, false)

	# --- Four translucent Victorian Glass Bell Cloches (`PieceGlass`) protecting tender seedlings on the benches! ---
	var cloches: Array = [
		[Vector3(-4.72, bench_h, -1.65), 0.18, 0.36],
		[Vector3(-4.78, bench_h, 1.35), 0.16, 0.33],
		[Vector3(4.74, bench_h, -0.85), 0.18, 0.36],
		[Vector3(4.78, bench_h, 2.05), 0.16, 0.32],
	]
	glass.surface(c.kit.GLASS)
	for cl: Array in cloches:
		var cp: Vector3 = cl[0]
		var cr := float(cl[1])
		var ch := float(cl[2])
		# Small dark ceramic saucer & vibrant bright-green fern seedling tucked inside the glass bell cloche!
		_terracotta_pot(u, stone_u, c.soft("wood", true), cp, cr * 0.62, 0.085, CLAY_DEEP, true)
		_rosette_plant(u, leaf_m, cp + Vector3(0.0, 0.08, 0.0), cr * 0.72, rng)
		# Single-surface translucent Victorian glass bell dome + delicate round finial knob (`PieceGlass`).
		Shapes.lathe(glass, [
			Vector2(cr, 0.0), Vector2(cr, ch * 0.56), Vector2(cr * 0.88, ch * 0.78),
			Vector2(cr * 0.52, ch * 0.94), Vector2(0.025, ch), Vector2(0.042, ch + 0.03),
			Vector2(0.025, ch + 0.055), Vector2(0.0, ch + 0.062),
		], cp, 12)

	# --- Hero Coiled-Handle Vintage Brass Watering Can on the Port Potting Bench (right beside the viewer!) ---
	_brass_watering_can(c, Vector3(-4.66, bench_h, 0.12), deg_to_rad(58.0))

	# --- Hand Gardening Trowel & Painted Vintage Botanical Seed Tins on the Port Bench ---
	_hand_trowel(c, Vector3(-4.64, bench_h + 0.015, 0.76), deg_to_rad(-34.0))
	var tins: Array = [
		[Vector3(-4.98, bench_h, 0.56), 0.058, 0.145, TIN_SAGE],
		[Vector3(-4.84, bench_h, 0.64), 0.048, 0.125, TIN_CREAM],
		[Vector3(-5.02, bench_h, 0.74), 0.052, 0.115, TIN_OCHRE],
		[Vector3(4.92, bench_h, 0.45), 0.055, 0.14, TIN_SAGE],
		[Vector3(4.96, bench_h, 0.62), 0.048, 0.12, TIN_CREAM],
	]
	for tn: Array in tins:
		var tp: Vector3 = tn[0]
		var tr := float(tn[1])
		var th := float(tn[2])
		var tc: Color = tn[3]
		u.surface(stone_u)
		u.colour = tc.srgb_to_linear()
		Shapes.cylinder(u, tp, tr, th, 10)
		u.surface(_brass_mat(c))
		u.colour = BRASS_WARM.srgb_to_linear()
		Shapes.cylinder(u, tp + Vector3(0.0, th - 0.018, 0.0), tr + 0.005, 0.022, 10)


## One turned terracotta clay pot (optional dark soil fill), cleanly lathed into PieceSoft.
static func _terracotta_pot(u: RoomMesh, clay_m: Material, soil_m: Material, at: Vector3, r: float, h: float,
		col: Color, with_soil: bool) -> void:
	u.surface(clay_m)
	u.colour = col.srgb_to_linear()
	Shapes.lathe(u, [
		Vector2(r * 0.66, 0.0), Vector2(r * 0.94, h * 0.80), Vector2(r * 1.06, h * 0.83),
		Vector2(r * 1.06, h), Vector2(r * 0.90, h), Vector2(r * 0.84, h * 0.86),
	], at, 9)
	if with_soil:
		u.surface(soil_m)
		u.colour = SOIL_DARK.srgb_to_linear()
		Shapes.cylinder(u, at + Vector3(0.0, h * 0.84, 0.0), r * 0.86, 0.025, 8)


## Vintage coiled-handle brass conservatory watering can (body, conical breast, long angled spout, perforated rose head,
## sweeping arched top carry handle + coiled rear grip handle).
static func _brass_watering_can(c: Object, at: Vector3, yaw: float) -> void:
	var u: RoomMesh = c.u
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	u.surface(_brass_mat(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	# Tapered oval-round brass body + beaded base & top collar.
	Shapes.lathe(u, [
		Vector2(0.115, 0.0), Vector2(0.122, 0.015), Vector2(0.112, 0.025),
		Vector2(0.098, 0.22), Vector2(0.105, 0.235), Vector2(0.075, 0.245), Vector2(0.0, 0.238),
	], at, 12)
	# Long slender angled brass pouring spout + flared perforated sprinkler rose head!
	var sp_base := xf * Vector3(0.0, 0.06, 0.095)
	var sp_tip := xf * Vector3(0.0, 0.27, 0.39)
	Shapes.beam(u, sp_base, sp_tip, Vector2(0.024, 0.024))
	var sp_dir := (sp_tip - sp_base).normalized()
	Shapes.lathe(u, [Vector2(0.016, 0.0), Vector2(0.048, 0.048), Vector2(0.046, 0.058), Vector2(0.0, 0.060)],
			sp_tip, 10, _towards(sp_dir))
	# Sweeping Victorian curved carry arch handle & coiled back grip handle!
	u.colour = BRASS_WARM.srgb_to_linear()
	var h_pts: Array[Vector3] = [
		xf * Vector3(0.0, 0.23, 0.085),
		xf * Vector3(0.0, 0.34, 0.02),
		xf * Vector3(0.0, 0.35, -0.09),
		xf * Vector3(0.0, 0.25, -0.18),
		xf * Vector3(0.0, 0.13, -0.19),
		xf * Vector3(0.0, 0.06, -0.11),
	]
	for i in h_pts.size() - 1:
		Shapes.beam(u, h_pts[i], h_pts[i + 1], Vector2(0.014, 0.018))


## Victorian hand gardening trowel: turned cedar grip, brass ferrule, curved dark-iron scoop blade.
static func _hand_trowel(c: Object, at: Vector3, yaw: float) -> void:
	var u: RoomMesh = c.u
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	var hb := xf.basis * Basis(Vector3.RIGHT, PI * 0.5)
	u.surface(c.soft("wood", true))
	u.colour = CEDAR_WARM.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.0, 0.0), Vector2(0.017, 0.02), Vector2(0.019, 0.09), Vector2(0.014, 0.13)],
			xf * Vector3(0.0, 0.012, -0.13), 8, hb)
	u.surface(_brass_mat(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.cylinder(u, xf * Vector3(0.0, 0.012, 0.0), 0.014, 0.022, 8, hb)
	u.surface(c.soft("iron", true))
	u.colour = IRON_CHARCOAL.srgb_to_linear()
	Shapes.beam(u, xf * Vector3(0.0, 0.012, 0.02), xf * Vector3(0.0, 0.012, 0.06), Vector2(0.012, 0.008))
	var b0 := xf * Vector3(-0.032, 0.014, 0.06)
	var b1 := xf * Vector3(0.032, 0.014, 0.06)
	var b2 := xf * Vector3(0.024, 0.004, 0.17)
	var b3 := xf * Vector3(-0.024, 0.004, 0.17)
	var tip := xf * Vector3(0.0, 0.010, 0.22)
	u.face([b0, b1, b2, b3], Vector3.UP)
	u.face([b3, b2, tip], Vector3.UP)


## Compact leafy tropical rosette seedling for small bench pots & bell cloches.
static func _rosette_plant(u: RoomMesh, leaf_m: Material, origin: Vector3, radius: float,
		rng: RandomNumberGenerator) -> void:
	u.surface(leaf_m)
	var shades: Array[Color] = [LEAF_EMERALD.srgb_to_linear(), LEAF_FERN.srgb_to_linear(), LEAF_BRIGHT.srgb_to_linear()]
	for k in 8:
		var a := TAU * float(k) / 8.0 + rng.randf_range(-0.2, 0.2)
		var lift := 0.35 if k % 2 == 0 else 0.72
		var dir := Vector3(sin(a), lift, cos(a)).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var llen := radius * rng.randf_range(0.75, 1.15)
		u.colour = shades[k % shades.size()]
		Shapes.leaf(u, origin + Vector3(0.0, 0.01, 0.0), dir * llen, side * (llen * 0.42),
				dir.cross(side).normalized())


## Six towering sculpted kentia feather palms & broad pleated fan palms in ornate terracotta conservatory urns, plus
## 8 broad elephant-ear tropical foliage clumps nestled around their feet and behind the stone fountain!
static func _palms_and_elephant_ears(c: Object, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	var clay_m: Material = c.soft("stone", true)
	var wood_u: Material = c.soft("wood", true)
	var leaf_m: Material = c.soft("leaves", true)

	# [pos, trunk_h, spread, lean_dir (Vector2), is_fan_palm, screen_safe_side]
	var palms: Array = [
		# Front apse flanking hero kentia palms silhouetting dramatically against the arched glass vault!
		[Vector3(-4.22, 0.0, -6.55), 3.05, 1.72, Vector2(0.18, 0.14), false, -1.0],
		[Vector3(4.22, 0.0, -6.55), 2.95, 1.68, Vector2(-0.18, 0.14), false, 1.0],
		# Mid-forward Victorian pleated fan palms!
		[Vector3(-4.52, 0.0, -4.65), 2.05, 1.48, Vector2(0.28, 0.06), true, -1.0],
		[Vector3(4.56, 0.0, -2.92), 1.98, 1.44, Vector2(-0.26, -0.05), true, 1.0],
		# Aft-corner soaring kentia palms flanking the Victorian double doors!
		[Vector3(-4.28, 0.0, 4.95), 3.05, 1.80, Vector2(0.24, -0.22), false, 0.0],
		[Vector3(4.32, 0.0, 4.95), 3.15, 1.82, Vector2(-0.24, -0.22), false, 0.0],
	]

	for pm: Array in palms:
		var pos: Vector3 = pm[0]
		var th := float(pm[1])
		var spread := float(pm[2])
		var lean2: Vector2 = pm[3]
		var is_fan := bool(pm[4])
		var safe_side := float(pm[5])

		# Large ornate ringed Victorian terracotta palm urn (r = 0.42 m, h = 0.62 m).
		var urn_h := 0.62
		u.surface(clay_m)
		u.colour = CLAY_DEEP.lerp(CLAY_WARM, 0.45).srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.30, 0.0), Vector2(0.32, 0.08), Vector2(0.26, 0.14), Vector2(0.38, 0.44),
			Vector2(0.43, 0.54), Vector2(0.45, 0.62), Vector2(0.37, 0.62), Vector2(0.34, 0.54),
		], pos, 12)
		u.surface(wood_u)
		u.colour = SOIL_DARK.srgb_to_linear()
		Shapes.cylinder(u, pos + Vector3(0.0, urn_h - 0.07, 0.0), 0.35, 0.05, 10)
		c.shapes.append(PhysicsShapes.box(pos + Vector3(0.0, 0.70, 0.0), Vector3(0.84, 1.40, 0.84)))

		# Gently curved ringed palm trunk rising from the urn soil (slender taper + subtle organic bark rings!).
		var base := pos + Vector3(0.0, urn_h - 0.04, 0.0)
		var segs := 10 if not is_fan else 7
		var prev := base
		u.surface(wood_u)
		for i in range(1, segs + 1):
			var t := float(i) / float(segs)
			var cur := base + Vector3(lean2.x * t * t, th * t, lean2.y * t * t)
			var r0 := lerpf(0.098, 0.056, float(i - 1) / float(segs))
			var r1 := lerpf(0.098, 0.056, t)
			u.colour = (BARK_PALM * (0.91 + 0.09 * float(i % 2))).srgb_to_linear()
			Shapes.lathe(u, [
				Vector2(r0, 0.0), Vector2(r1 * 1.06, prev.distance_to(cur) * 0.84),
				Vector2(r1, prev.distance_to(cur)),
			], prev, 7, _towards(cur - prev))
			prev = cur
		var crown := prev
		# Fibrous crownshaft bulb transitioning softly from bark to lush palm green.
		u.surface(leaf_m)
		u.colour = LEAF_DEEP.srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.062, -0.09), Vector2(0.096, 0.06), Vector2(0.052, 0.24)], crown, 7)

		if is_fan:
			_fan_palm_crown(u, leaf_m, crown, spread, safe_side, rng)
		else:
			_kentia_palm_crown(u, leaf_m, crown, spread, safe_side, rng)

	# Eight lush broad elephant-ear / monstera-like tropical foliage clumps around palm bases & fountain!
	var elephant_spots: Array = [
		[Vector3(-3.65, 0.0, -6.10), 0.78],
		[Vector3(3.65, 0.0, -6.15), 0.74],
		[Vector3(-4.58, 0.0, -5.65), 0.84],
		[Vector3(4.42, 0.0, -4.15), 0.82],
		[Vector3(2.45, 0.0, -5.55), 0.68],
		[Vector3(-3.55, 0.0, 4.75), 0.82],
		[Vector3(3.55, 0.0, 4.75), 0.80],
		[Vector3(-4.65, 0.0, 4.15), 0.76],
	]
	for es: Array in elephant_spots:
		var ep: Vector3 = es[0]
		var sc := float(es[1])
		_terracotta_pot(u, clay_m, wood_u, ep, 0.21 * sc, 0.30 * sc, CLAY_WARM, true)
		_elephant_ear_clump(u, leaf_m, ep + Vector3(0.0, 0.26 * sc, 0.0), sc, rng)


## Graceful arching feather-frond kentia palm crown (12 sweeping fronds with slender tapering paired leaflets).
static func _kentia_palm_crown(u: RoomMesh, leaf_m: Material, crown: Vector3, spread: float, safe_side: float,
		rng: RandomNumberGenerator) -> void:
	u.surface(leaf_m)
	var shades: Array[Color] = [LEAF_DEEP.srgb_to_linear(), LEAF_EMERALD.srgb_to_linear(), LEAF_FERN.srgb_to_linear()]
	const FRONDS := 12
	for f in FRONDS:
		var az := TAU * float(f) / float(FRONDS) + rng.randf_range(-0.14, 0.14)
		var out := Vector3(sin(az), 0.0, cos(az))
		# Keep front palm fronds gracefully arching upward/outward away from the cinema screen rectangle!
		var reach := spread * rng.randf_range(0.86, 1.12)
		var up_lift := rng.randf_range(0.36, 0.90)
		if safe_side != 0.0 and signf(out.x) == -safe_side and out.z < 0.25:
			reach *= 0.68
			up_lift = maxf(up_lift, 0.68)
		var side := out.cross(Vector3.UP).normalized()
		var last := crown + Vector3(0.0, 0.10, 0.0)
		u.colour = shades[f % shades.size()]
		const SEGS := 9
		for j in range(1, SEGS + 1):
			var t := float(j) / float(SEGS)
			var p := crown + Vector3(0.0, 0.10, 0.0) + out * (reach * t) \
					+ Vector3.UP * (reach * (up_lift * t - 0.62 * t * t))
			var along := p - last
			var pinna := reach * 0.23 * sin(PI * clampf(t * 0.92 + 0.06, 0.0, 1.0))
			for sgn: float in [-1.0, 1.0]:
				var tip := last.lerp(p, 0.55) + side * (sgn * pinna) + Vector3.DOWN * (pinna * 0.52)
				var nn := along.cross(tip - last).normalized()
				u.face([last, p, tip], nn)
				u.face([last, tip, p], -nn)
			last = p


## Sculpted Victorian pleated fan-palm crown (10 arching petioles crowned with slender 9-fingered arching fans!).
static func _fan_palm_crown(u: RoomMesh, leaf_m: Material, crown: Vector3, spread: float, safe_side: float,
		rng: RandomNumberGenerator) -> void:
	u.surface(leaf_m)
	var shades: Array[Color] = [LEAF_EMERALD.srgb_to_linear(), LEAF_FERN.srgb_to_linear(), LEAF_BRIGHT.srgb_to_linear()]
	const STEMS := 10
	for f in STEMS:
		var az := TAU * float(f) / float(STEMS) + rng.randf_range(-0.14, 0.14)
		var out := Vector3(sin(az), 0.0, cos(az))
		var len_s := spread * rng.randf_range(0.72, 1.04)
		var lift := rng.randf_range(0.30, 0.80)
		if safe_side != 0.0 and signf(out.x) == -safe_side:
			len_s *= 0.72
		var mid_stem := crown + Vector3(0.0, 0.14, 0.0) + out * (len_s * 0.36) + Vector3.UP * (len_s * (lift * 0.65))
		var hub := crown + Vector3(0.0, 0.12, 0.0) + out * (len_s * 0.72) + Vector3.UP * (len_s * (lift - 0.10))
		# Gently arched slender petiole stem from crown to fan hub.
		u.colour = LEAF_DEEP.srgb_to_linear()
		Shapes.beam(u, crown + Vector3(0.0, 0.08, 0.0), mid_stem, Vector2(0.018, 0.018))
		Shapes.beam(u, mid_stem, hub, Vector2(0.015, 0.015))
		# Graceful pleated palmate fan of 9 slender, drooping pointed leaflets!
		var fwd := (hub - mid_stem).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var tilt_up := right.cross(fwd).normalized()
		u.colour = shades[f % shades.size()]
		var fan_r := spread * 0.44 * rng.randf_range(0.86, 1.12)
		for b in 9:
			var ba := lerpf(-1.35, 1.35, float(b) / 8.0)
			var base_dir := (fwd * cos(ba) + right * sin(ba) + Vector3.DOWN * 0.16).normalized()
			var bside := base_dir.cross(tilt_up).normalized()
			var blen := fan_r * (1.0 - 0.18 * absf(ba))
			# Two-segment arching leaflet (basal fan blade + softly drooping pointed tip!).
			var p0 := hub
			var p1 := hub + base_dir * (blen * 0.52) + tilt_up * (0.04 * (1.0 if b % 2 == 0 else -0.6))
			var p2 := p1 + (base_dir * 0.82 + Vector3.DOWN * 0.56).normalized() * (blen * 0.52)
			var hw := blen * 0.095
			var l1 := p1 - bside * hw
			var r1 := p1 + bside * hw
			var n := ((r1 - p0).cross(p1 - p0)).normalized()
			if n.y < 0.0:
				n = -n
			u.face([p0, l1, r1], n)
			u.face([p0, r1, l1], -n)
			u.face([l1, p2, r1], n)
			u.face([l1, r1, p2], -n)


## Broad sculpted heart-shaped elephant-ear / monstera-like tropical leaves on arched stems.
static func _elephant_ear_clump(u: RoomMesh, leaf_m: Material, origin: Vector3, sc: float,
		rng: RandomNumberGenerator) -> void:
	u.surface(leaf_m)
	var shades: Array[Color] = [LEAF_DEEP.srgb_to_linear(), LEAF_EMERALD.srgb_to_linear(), LEAF_BRIGHT.srgb_to_linear()]
	for k in 6:
		var a := TAU * float(k) / 6.0 + rng.randf_range(-0.25, 0.25)
		var out := Vector3(sin(a), 0.0, cos(a))
		var side := out.cross(Vector3.UP).normalized()
		var h := sc * rng.randf_range(0.62, 1.02)
		var reach := sc * rng.randf_range(0.32, 0.56)
		var tip_stem := origin + out * reach + Vector3.UP * h
		u.colour = LEAF_DEEP.srgb_to_linear()
		Shapes.beam(u, origin, tip_stem, Vector2(0.022 * sc, 0.022 * sc))
		# Broad arched spade/heart leaf blade (two tilted halves creating a real central midrib crease!).
		u.colour = shades[k % shades.size()]
		var blen := sc * rng.randf_range(0.46, 0.64)
		var bw := blen * 0.40
		var blade_dir := (out * 0.78 + Vector3.DOWN * 0.52).normalized()
		var p_base := tip_stem - blade_dir * (blen * 0.18)
		var p_mid := tip_stem + blade_dir * (blen * 0.36)
		var p_tip := tip_stem + blade_dir * blen
		for sgn: float in [-1.0, 1.0]:
			var wing := p_mid + side * (sgn * bw) + Vector3.UP * (0.045 * sc)
			var lobe := p_base + side * (sgn * bw * 0.68) + Vector3.UP * (0.03 * sc)
			var n := ((wing - p_base).cross(p_tip - p_base)).normalized()
			if n.y < 0.0:
				n = -n
			u.face([p_base, lobe, wing, p_tip], n)
			u.face([p_base, p_tip, wing, lobe], -n)


## Four potted Victorian dwarf citrus trees (2 Lemon + 2 Tangerine) studded with glowing warm-yellow & orange fruits!
static func _dwarf_citrus_trees(c: Object, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	var clay_m: Material = c.soft("stone", true)
	var wood_u: Material = c.soft("wood", true)
	var leaf_m: Material = c.soft("leaves", true)

	# [pos, trunk_h, crown_r, fruit_color, is_lemon]
	var trees: Array = [
		[Vector3(-3.68, 0.0, -2.85), 0.96, 0.66, FRUIT_LEMON, true],
		[Vector3(3.68, 0.0, 0.55), 0.92, 0.64, FRUIT_TANGERINE, false],
		[Vector3(-3.68, 0.0, 2.55), 0.94, 0.62, FRUIT_TANGERINE, false],
		[Vector3(4.32, 0.0, -5.28), 0.98, 0.64, FRUIT_LEMON, true],
	]

	for td: Array in trees:
		var pos: Vector3 = td[0]
		var tr_h := float(td[1])
		var cr := float(td[2])
		var fcol: Color = td[3]
		var is_lemon := bool(td[4])

		# Handsome flared terracotta citrus tub (r = 0.32 m, h = 0.48 m).
		_terracotta_pot(u, clay_m, wood_u, pos, 0.32, 0.48, CLAY_WARM, true)
		c.shapes.append(PhysicsShapes.box(pos + Vector3(0.0, 0.95, 0.0), Vector3(0.76, 1.90, 0.76)))

		# Sculpted branching citrus trunk & 4 spreading limbs.
		var base := pos + Vector3(0.0, 0.44, 0.0)
		var fork := base + Vector3(0.0, tr_h * 0.65, 0.0)
		u.surface(wood_u)
		u.colour = BARK_CITRUS.srgb_to_linear()
		Shapes.cylinder(u, base, 0.048, tr_h * 0.68, 7)

		var crown_ctr := base + Vector3(0.0, tr_h + cr * 0.30, 0.0)
		var limb_tips: Array[Vector3] = [crown_ctr + Vector3(0.0, cr * 0.22, 0.0), crown_ctr]
		for k in 4:
			var a := TAU * float(k) / 4.0 + rng.randf_range(-0.3, 0.3)
			var tip := fork + Vector3(sin(a) * cr * 0.48, cr * 0.56, cos(a) * cr * 0.48)
			Shapes.beam(u, fork, tip, Vector2(0.030, 0.030))
			limb_tips.append(tip)

		# Lush dense canopy of glossy dark-citrus leaves clustered tightly around every branch tip & inner crown!
		u.surface(leaf_m)
		var cshades: Array[Color] = [LEAF_CITRUS.srgb_to_linear(), LEAF_EMERALD.srgb_to_linear(),
				LEAF_DEEP.srgb_to_linear(), LEAF_FERN.srgb_to_linear()]
		for tip: Vector3 in limb_tips:
			for j in 18:
				var th := rng.randf() * TAU
				var ph := rng.randf_range(-0.55, 0.95)
				var rad := cr * rng.randf_range(0.10, 0.52)
				var lp := tip + Vector3(cos(th) * cos(ph), sin(ph) * 0.72, sin(th) * cos(ph)) * rad
				var ldir := Vector3(cos(th), rng.randf_range(-0.35, 0.60), sin(th)).normalized()
				var lside := ldir.cross(Vector3.UP).normalized()
				if lside.length() < 0.01:
					lside = Vector3.RIGHT
				var llen := rng.randf_range(0.18, 0.26)
				u.colour = cshades[j % cshades.size()]
				Shapes.leaf(u, lp, ldir * llen, lside * (llen * 0.50), ldir.cross(lside).normalized())

		# Ten plump glowing lemons or tangerines nestled snugly inside the lush citrus foliage!
		u.surface(clay_m)
		u.colour = fcol.srgb_to_linear()
		for fi in 10:
			var fa := TAU * float(fi) / 10.0 + rng.randf_range(-0.18, 0.18)
			var fy := rng.randf_range(-0.20, 0.30) * cr
			var fr_out := cr * rng.randf_range(0.42, 0.70)
			var fp := crown_ctr + Vector3(sin(fa) * fr_out, fy, cos(fa) * fr_out)
			if is_lemon:
				# Oval pointed Victorian lemon profile.
				Shapes.lathe(u, [
					Vector2(0.0, -0.054), Vector2(0.034, -0.034), Vector2(0.041, 0.0),
					Vector2(0.034, 0.034), Vector2(0.0, 0.054),
				], fp, 7)
			else:
				# Plump slightly oblate tangerine profile.
				Shapes.lathe(u, [
					Vector2(0.0, -0.042), Vector2(0.046, -0.022), Vector2(0.049, 0.0),
					Vector2(0.044, 0.024), Vector2(0.0, 0.042),
				], fp, 7)


## Six hanging Victorian brass fern baskets suspended by slender brass chains from the arched cast-iron vault ribs,
## overflowing with cascading emerald sword ferns and trailing ivy!
static func _hanging_fern_baskets(c: Object, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	var leaf_m: Material = c.soft("leaves", true)
	var wood_u: Material = c.soft("wood", true)

	var basket_zs: Array[float] = [-5.30, -0.70, 3.90]
	var bx_abs := 3.68
	var by := 3.38
	# Exact vault arch height directly above x = +-3.68 m!
	var cos_th := bx_abs / ARCH_HW
	var arch_y := EAVE_Y + ARCH_RISE * sqrt(maxf(1.0 - cos_th * cos_th, 0.0))

	for side: float in [-1.0, 1.0]:
		for bz: float in basket_zs:
			var bp := Vector3(side * bx_abs, by, bz)
			var r := 0.27
			# Stepped Victorian hammered-brass hanging bowl with moulded lip bead & bottom acorn finial drop!
			u.surface(_brass_mat(c))
			u.colour = BRASS_AGED.srgb_to_linear()
			Shapes.lathe(u, [
				Vector2(0.0, -0.15), Vector2(0.028, -0.12), Vector2(0.042, -0.09), Vector2(0.024, -0.06),
				Vector2(0.14, -0.02), Vector2(0.22, 0.05), Vector2(0.25, 0.12), Vector2(r, 0.17),
				Vector2(r + 0.025, 0.20), Vector2(r + 0.015, 0.22), Vector2(r - 0.02, 0.21),
			], bp, 12)
			# Three slender brass suspension chains meeting at a hook on the arched iron rib overhead!
			var hook := Vector3(side * bx_abs, arch_y - 0.06, bz)
			var ring := bp + Vector3(0.0, 0.72, 0.0)
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			Shapes.beam(u, ring, hook, Vector2(0.012, 0.012))
			for k in 3:
				var a := TAU * float(k) / 3.0
				var rim_p := bp + Vector3(cos(a) * r, 0.20, sin(a) * r)
				Shapes.beam(u, rim_p, ring, Vector2(0.010, 0.010))
			# Soil mound + overflowing cascading sword-fern canopy + trailing emerald ivy tendrils!
			u.surface(wood_u)
			u.colour = SOIL_DARK.srgb_to_linear()
			Shapes.cylinder(u, bp + Vector3(0.0, 0.14, 0.0), r - 0.03, 0.06, 8)
			_fern_clump(u, leaf_m, bp + Vector3(0.0, 0.18, 0.0), 0.80, 0.44, 10, rng, true)
			for tk in 4:
				var ta := TAU * float(tk) / 4.0 + rng.randf_range(-0.25, 0.25)
				var tdir := Vector3(cos(ta), 0.0, sin(ta))
				var rim_s := bp + tdir * (r + 0.01) + Vector3(0.0, 0.18, 0.0)
				var trail_e := rim_s + tdir * 0.14 + Vector3(0.0, -rng.randf_range(0.38, 0.56), 0.0)
				_ivy_vine(u, wood_u, leaf_m, rim_s, trail_e, tdir * 0.08, 6, rng)


## Layered sword fern clumps (under-screen fern trough, flanking aft doors, floor urns) + organic climbing ivy vines
## twining up the wrought-iron conservatory pilasters and framing the outer iron posts of the screen trellis!
static func _ferns_and_climbing_ivy(c: Object, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	var clay_m: Material = c.soft("stone", true)
	var wood_u: Material = c.soft("wood", true)
	var leaf_m: Material = c.soft("leaves", true)

	# 1. Under-screen brick trough packed with lush low sword ferns (strictly capped below y = 0.94 m, screen = 1.00 m!).
	for k in 7:
		var fx := lerpf(-2.40, 2.40, float(k) / 6.0)
		_fern_clump(u, leaf_m, Vector3(fx, 0.71, -8.10), 0.48, 0.21, 7, rng)

	# 2. Floor-standing terracotta fern urns flanking the aft doors, fountain & aisles!
	var urn_ferns: Array = [
		[Vector3(-1.95, 0.0, 5.45), 0.24, 0.36, 0.78, 0.62],
		[Vector3(1.95, 0.0, 5.45), 0.24, 0.36, 0.78, 0.62],
		[Vector3(-2.95, 0.0, 5.15), 0.28, 0.44, 0.88, 0.72],
		[Vector3(2.35, 0.0, -4.10), 0.20, 0.28, 0.58, 0.44],
		[Vector3(4.15, 0.0, -3.75), 0.22, 0.32, 0.66, 0.50],
		[Vector3(-3.85, 0.0, -4.15), 0.22, 0.32, 0.68, 0.52],
	]
	for uf: Array in urn_ferns:
		var p: Vector3 = uf[0]
		var r := float(uf[1])
		var h := float(uf[2])
		_terracotta_pot(u, clay_m, wood_u, p, r, h, CLAY_WARM.lerp(CLAY_DEEP, rng.randf() * 0.5), true)
		_fern_clump(u, leaf_m, p + Vector3(0.0, h - 0.02, 0.0), float(uf[3]), float(uf[4]), 8, rng)

	# 3. Lush twin-vine climbing ivy twining organically up the outer cast-iron screen trellis posts & upper trellis arch!
	#    Strictly kept at |x| >= 2.70 on the sides and y >= 3.92 on the arch -> ZERO overlap with screen aperture!
	for side: float in [-1.0, 1.0]:
		var x_outer := side * 3.04
		var x_mid := side * 2.86
		_ivy_vine(u, wood_u, leaf_m, Vector3(x_outer, 0.96, -8.02), Vector3(x_outer - side * 0.04, 3.90, -8.02),
				Vector3(side * 0.16, 0.0, 0.18), 24, rng, 1.35)
		_ivy_vine(u, wood_u, leaf_m, Vector3(x_mid, 1.12, -8.00), Vector3(x_mid + side * 0.12, 3.88, -8.00),
				Vector3(side * 0.10, 0.0, 0.16), 20, rng, 1.25)
		# Lush ivy garlands curving cleanly along the OUTER rim of the overhead screen trellis arch!
		var prev := Vector3(side * 3.06, 3.90, -8.02)
		for k in range(1, 9):
			var th := lerpf(0.08 if side > 0.0 else PI - 0.08, PI * 0.5 - side * 0.18, float(k) / 8.0)
			var nxt := Vector3(3.10 * cos(th), 3.88 + 1.44 * sin(th), -8.02)
			_ivy_vine(u, wood_u, leaf_m, prev, nxt, Vector3(0.0, 0.10, 0.14), 6, rng, 1.30)
			prev = nxt

	# 4. Climbing ivy hugging selected side-wall cast-iron conservatory pilasters & arch knees!
	for side: float in [-1.0, 1.0]:
		for rz: float in [-5.30, -0.70, 3.90]:
			var p0 := Vector3(side * (ARCH_HW - 0.10), DWARF_H + 0.08, rz)
			var p1 := Vector3(side * (ARCH_HW - 0.14), EAVE_Y + 0.35, rz)
			_ivy_vine(u, wood_u, leaf_m, p0, p1, Vector3(-side * 0.14, 0.0, 0.0), 14, rng, 1.15)


## Draws a lush arching Victorian sword-fern clump (if `cascade`, outer fronds drape gracefully over a hanging basket!).
static func _fern_clump(u: RoomMesh, leaf_m: Material, origin: Vector3, reach: float, lift_max: float, fronds: int,
		rng: RandomNumberGenerator, cascade := false) -> void:
	u.surface(leaf_m)
	var shades: Array[Color] = [LEAF_DEEP.srgb_to_linear(), LEAF_EMERALD.srgb_to_linear(),
			LEAF_FERN.srgb_to_linear(), LEAF_BRIGHT.srgb_to_linear()]
	for f in fronds:
		var a := TAU * float(f) / float(fronds) + rng.randf_range(-0.20, 0.20)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var side := dir.cross(Vector3.UP).normalized()
		var rf := reach * rng.randf_range(0.75, 1.08)
		var lift := lift_max * rng.randf_range(0.55, 1.0)
		var droop := (0.68 if (cascade and f % 2 == 0) else 0.18) * rf
		var prev := origin
		u.colour = shades[f % shades.size()]
		const PAIRS := 6
		for i in range(1, PAIRS + 1):
			var t := float(i) / float(PAIRS)
			var p := origin + dir * (rf * t) + Vector3.UP * (lift * sin(t * PI * 0.78) - droop * t * t)
			var along := p - prev
			var llen := 0.14 * (1.0 - t * 0.48) * (reach / 0.55)
			for sgn: float in [-1.0, 1.0]:
				Shapes.leaf(u, p, side * (sgn * llen) + along * 0.35, along.normalized() * (llen * 0.34), Vector3.UP)
			prev = p


## Draws a climbing ivy stem with alternating dark-emerald pointed ivy leaves between `p0` and `p1`.
static func _ivy_vine(u: RoomMesh, wood_u: Material, leaf_m: Material, p0: Vector3, p1: Vector3, out_bias: Vector3,
		leaves: int, rng: RandomNumberGenerator, leaf_scale := 1.0) -> void:
	u.surface(wood_u)
	u.colour = BARK_CITRUS.srgb_to_linear()
	Shapes.beam(u, p0, p1, Vector2(0.018, 0.018))
	u.surface(leaf_m)
	var dir_main := (p1 - p0).normalized()
	var perp := dir_main.cross(Vector3.BACK)
	if perp.length() < 0.05:
		perp = dir_main.cross(Vector3.RIGHT)
	perp = perp.normalized()
	for i in leaves:
		var t := (float(i) + 0.5) / float(leaves)
		var sgn := -1.0 if i % 2 == 0 else 1.0
		var at := p0.lerp(p1, t) + perp * (sgn * rng.randf_range(0.02, 0.08)) + out_bias * rng.randf_range(0.25, 0.90)
		var llen := rng.randf_range(0.088, 0.142) * leaf_scale
		var ldir := (perp * sgn * 0.65 + out_bias.normalized() * 0.50 + Vector3.DOWN * 0.32).normalized()
		var lacross := ldir.cross(dir_main).normalized()
		if lacross.length() < 0.05:
			lacross = Vector3.RIGHT
		u.colour = LEAF_IVY.lerp(LEAF_FERN, rng.randf() * 0.65).srgb_to_linear()
		Shapes.leaf(u, at, ldir * llen, lacross * (llen * 0.56), ldir.cross(lacross).normalized())


## Aft scrolled Victorian cast-iron potting table (x = +2.85, z = +4.85) with warm glowing brass conservatory
## hurricane lantern, painted seed tins & pots, PLUS matching glowing brass hurricane lantern on the port potting bench!
static func _aft_potting_table_and_lanterns(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var stone_u: Material = c.soft("stone", true)
	var iron_u: Material = c.soft("iron", true)

	# 1. Aft scrolled cast-iron & cedar conservatory potting table at (+2.85, 0.0, +4.85).
	var tp := Vector3(2.85, 0.0, 4.85)
	var tw := 1.18
	var th := 0.76
	var td := 0.66

	s.surface(c.tinted("wood"))
	for pl in 4:
		var pz := tp.z - td * 0.5 + 0.085 + float(pl) * 0.162
		s.colour = (CEDAR_WARM if pl % 2 == 0 else CEDAR_RICH).srgb_to_linear()
		s.box(Vector3(tp.x, th - 0.018, pz), Vector3(tw, 0.034, 0.138))

	u.surface(iron_u)
	u.colour = IRON_SAGE_DARK.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lx := tp.x + sx * (tw * 0.5 - 0.06)
			var lz := tp.z + sz * (td * 0.5 - 0.06)
			u.box(Vector3(lx, th * 0.5, lz), Vector3(0.04, th, 0.04), Basis(), [RoomMesh.DOWN])
		# Decorative Victorian circular iron leg scroll ring at each table end!
		var ex := tp.x + sx * (tw * 0.5 - 0.06)
		u.box(Vector3(ex, 0.24, tp.z), Vector3(0.03, 0.03, td - 0.12))
		Shapes.arch(u, Vector3(ex, 0.50, tp.z), 0.14, 0.17, 0.028, 10, Basis(Vector3.UP, PI * 0.5), 0.0, TAU,
				["front", "back", "inner", "outer"])
	u.box(Vector3(tp.x, 0.24, tp.z), Vector3(tw - 0.12, 0.032, 0.032))
	c.shapes.append(PhysicsShapes.box(tp + Vector3(0.0, th * 0.5, 0.0), Vector3(tw, th, td)))

	# Vintage seed tins & small potted fern on the aft potting table!
	_terracotta_pot(u, stone_u, c.soft("wood", true), Vector3(tp.x - 0.34, th, tp.z - 0.08), 0.10, 0.15, CLAY_PALE, true)
	_rosette_plant(u, c.soft("leaves", true), Vector3(tp.x - 0.34, th + 0.14, tp.z - 0.08), 0.16, rng)
	for td_i: Array in [
		[Vector3(tp.x + 0.32, th, tp.z - 0.10), 0.055, 0.135, TIN_OCHRE],
		[Vector3(tp.x + 0.42, th, tp.z + 0.06), 0.048, 0.115, TIN_SAGE],
	]:
		u.surface(stone_u)
		u.colour = (td_i[3] as Color).srgb_to_linear()
		Shapes.cylinder(u, td_i[0] as Vector3, float(td_i[1]), float(td_i[2]), 10)

	# 2. Two warm glowing Victorian brass conservatory hurricane lanterns (aft table + port potting bench!).
	_brass_hurricane_lantern(c, Vector3(tp.x + 0.04, th, tp.z + 0.05))
	_brass_hurricane_lantern(c, Vector3(-4.68, 0.84, -0.44))


## Warm glowing Victorian brass conservatory hurricane table lantern (PieceLamps + hidden bake light).
static func _brass_hurricane_lantern(c: Object, at: Vector3) -> void:
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	u.surface(_brass_mat(c))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	# Stepped brass oil-lamp reservoir base, protective ribs, vented chimney cap & wire carry bail!
	Shapes.lathe(u, [
		Vector2(0.095, 0.0), Vector2(0.10, 0.03), Vector2(0.082, 0.075), Vector2(0.062, 0.09),
	], at, 10)
	Shapes.lathe(u, [
		Vector2(0.075, 0.26), Vector2(0.095, 0.28), Vector2(0.055, 0.34), Vector2(0.032, 0.38), Vector2(0.0, 0.39),
	], at, 10)
	for k in 4:
		var a := float(k) * PI * 0.5
		var off := Vector3(cos(a) * 0.078, 0.0, sin(a) * 0.078)
		Shapes.beam(u, at + off + Vector3(0.0, 0.08, 0.0), at + off + Vector3(0.0, 0.27, 0.0), Vector2(0.009, 0.009))
	lit.surface(c.shade(LAMP_WARM))
	lit.colour = Color.WHITE
	Shapes.lathe(lit, [
		Vector2(0.052, 0.088), Vector2(0.072, 0.15), Vector2(0.070, 0.22), Vector2(0.048, 0.265),
	], at, 10)
	c.glow_lights.append([at + Vector3(0.0, 0.22, 0.0), LAMP_WARM, 0.45, 4.2])
