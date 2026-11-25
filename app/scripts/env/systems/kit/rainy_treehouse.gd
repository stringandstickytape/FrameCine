extends RefCounted

## Rainy treehouse kit (app/environments/rainy_treehouse.env.json; docs/environments/rooms/rainy_treehouse.md):
## a Cozy retreats room built by Gemini 4 Neon Extra High. A hand-built cedar-plank and pitched-corrugated-tin canopy
## hideaway nestled 14 metres up inside the sprawling gnarled boughs of an ancient mossy forest oak on a warm rainy
## twilight night. 100% procedural/CC0, zero people, zero trademarks, zero live lights.
##
## Pieces (dispatched from kit/pieces.gd):
##   treehouse_deck    weathered cedar-plank treehouse floor (notched around the aft-starboard oak trunk and open
##                     trapdoor hatch) and wrap-around slatted cedar deck with log railings & under-deck timber knee
##                     braces; timber-framed cedar cabin walls with six wide propped-open plank shutter windows on
##                     angled wooden stay rods acting as rain awnings; exposed cedar rafters, purlins, king-post collar
##                     ties and pitched weathered corrugated-tin roof (`Procedural` "corrugated") with deep overhanging
##                     rain eaves (`|x| = 5.12 m`, `z = -6.55..+5.15 m`); hand-lashed cedar-pole screen frame with
##                     rolled weathered canvas weather flaps; woven mossy-terracotta floor rug (`NordicRug`,
##                     `Procedural.maps("nordic_rug")`) with braided trim & throw pillows; low live-edge cedar & crate
##                     coffee table (`y_top = 0.36 m`) with forest-green enamel teapot, camp mugs, glowing brass oil
##                     lantern and stacked field guides; port windowsill shelf with glowing jam-jar candles, brass
##                     spyglass, vintage tin biscuit box and potted fern; open aft Z-braced balcony door, naturalist's
##                     bookshelf, hinged open trapdoor hatch with wooden-rung rope ladder, curving 34-slat wooden rope
##                     suspension bridge vanishing into neighbouring oaks, and festoons of glowing brass & paper fairy
##                     lanterns (`PieceCove` + `PieceLamps` + hidden bake lights + live-tinted footlights).
##   treehouse_canopy  monumental fluted ancient mossy forest oak rising straight through the aft-starboard corner of
##                     the deck (`x = 3.95, z = 2.35`, descending 15 m into misty depths and rising 14.5 m overhead)
##                     with flaring root buttresses, massive twisting under-deck cradle boughs, flanking screen-carrying
##                     limbs, high overarching crown boughs and layered mossy-green oak foliage clusters, encircled by
##                     21 tall dark misty neighbouring oak & cedar silhouettes (11..38 m out) and a shadowed forest
##                     canopy floor far below the mist.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")

const PIECES: Array[String] = ["treehouse_deck", "treehouse_canopy"]

## Cabin footprint and roof geometry (metres; viewer dead-centre seat at (0, 0, 0) facing -Z).
const CABIN_HW := 4.15
const CABIN_FZ := -5.75
const CABIN_BZ := 4.15
const DECK_HW := 5.12
const DECK_FZ := -6.32
const DECK_BZ := 5.65

## Pitched corrugated-tin roof profile (deep rain eaves overhang strictly covering |x| <= 5.12, z in [-6.55, 5.15]).
const WALL_H := 3.05
const RIDGE_Y := 4.68
const ROOF_SLOPE := 0.3855
const EAVE_X := 5.12
const EAVE_FZ := -6.55
const EAVE_BZ := 5.15

## Monumental host oak trunk centre & aft-starboard trapdoor hatch opening.
const TRUNK_X := 3.95
const TRUNK_Z := 2.35
const HATCH_X0 := 0.72
const HATCH_X1 := 1.78
const HATCH_Z0 := 2.68
const HATCH_Z1 := 3.74

## Woven Nordic floor rug extents (under all 6 seats: x in [-1.15, 1.15], z in [0.0, 1.55]).
const RUG_X0 := -2.28
const RUG_X1 := 2.28
const RUG_Z0 := -1.12
const RUG_Z1 := 2.48
const RUG_Y := 0.008

## Palette (sRGB; converted to linear on vertex colours).
const CEDAR_WARM := Color(0.50, 0.31, 0.17)
const CEDAR_HONEY := Color(0.58, 0.38, 0.21)
const CEDAR_WEATHERED := Color(0.36, 0.24, 0.15)
const CEDAR_DARK := Color(0.24, 0.16, 0.10)
const CEDAR_DECK := Color(0.32, 0.22, 0.14)
const BARK_DEEP := Color(0.22, 0.16, 0.11)
const BARK_WARM := Color(0.32, 0.23, 0.15)
const BARK_MOSS := Color(0.19, 0.30, 0.13)
const TIN_BASE := Color(0.54, 0.56, 0.55)
const TIN_PATINA := Color(0.44, 0.43, 0.40)
const IRON_DARK := Color(0.08, 0.085, 0.09)
const BRASS_WARM := Color(0.88, 0.70, 0.34)
const BRASS_AGED := Color(0.70, 0.52, 0.24)
const CANVAS_CREAM := Color(0.74, 0.66, 0.52)
const CANVAS_WEATHERED := Color(0.54, 0.46, 0.36)
const ROPE_HEMP := Color(0.58, 0.46, 0.30)
const ENAMEL_FOREST := Color(0.08, 0.24, 0.16)
const ENAMEL_CREAM := Color(0.76, 0.70, 0.58)
const ENAMEL_TERRA := Color(0.52, 0.21, 0.13)
const BISCUIT_TEAL := Color(0.14, 0.34, 0.32)
const PILLOW_MOSS := Color(0.22, 0.38, 0.20)
const PILLOW_OCHRE := Color(0.70, 0.48, 0.18)
const PILLOW_BERRY := Color(0.52, 0.18, 0.16)
const BLANKET_PLAID := Color(0.44, 0.17, 0.15)
const PAPER_CREAM := Color(0.95, 0.88, 0.72)
const LANTERN_AMBER := Color(1.0, 0.72, 0.36)
const CANDLE_WAX := Color(0.88, 0.82, 0.68)
const LEAF_SHADOW := Color(0.055, 0.13, 0.07)
const LEAF_MOSS := Color(0.13, 0.28, 0.12)
const LEAF_SAGE := Color(0.22, 0.37, 0.19)
const LEAF_DISTANT := Color(0.07, 0.135, 0.13)
const FOREST_FLOOR := Color(0.035, 0.075, 0.055)


## Custom Hall for Rainy treehouse: builds the baked static woven Nordic floor rug with exact 0..1 UVs
## (`Procedural.maps("nordic_rug")`) and tunes `PieceGlass` for warm clear jam-jar candles and oil lantern chimney.
class TreehouseHall:
	var has_deck := false
	var rug_node: MeshInstance3D

	func finish(k: Node) -> void:
		if not has_deck:
			return
		_build_rug(k)
		for n: Node in k.owned():
			if n is MeshInstance3D and str(n.name).begins_with("PieceGlass"):
				var gm := (n as MeshInstance3D).material_override as ShaderMaterial
				if gm != null:
					gm.set_shader_parameter("alpha", 0.22)
					gm.set_shader_parameter("rim", 0.52)

	func _build_rug(k: Node) -> void:
		var m: ShaderMaterial = k._light.from_param({"library": "corduroy", "color": [1.0, 1.0, 1.0]}, false)
		var maps: Dictionary = Procedural.maps("nordic_rug")
		m.set_shader_parameter("albedo_map", maps["albedo"])
		m.set_shader_parameter("normal_map", maps["normal"])
		m.set_shader_parameter("orm_map", maps["orm"])
		# Warm wool tint over the oatmeal, crimson, spruce and ochre diamond rug bands.
		m.set_shader_parameter("tint", Color(0.95, 0.90, 0.78))
		m.set_shader_parameter("use_mesh_uv", true)
		m.set_shader_parameter("uv_repeat", Vector2(1.0, 1.0))
		m.set_shader_parameter("normal_strength", 1.1)
		m.set_shader_parameter("specular", 0.18)

		var v := PackedVector3Array([
			Vector3(RUG_X0, RUG_Y, RUG_Z0),
			Vector3(RUG_X1, RUG_Y, RUG_Z0),
			Vector3(RUG_X1, RUG_Y, RUG_Z1),
			Vector3(RUG_X0, RUG_Y, RUG_Z1),
		])
		var n := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		var t := PackedFloat32Array([
			1.0, 0.0, 0.0, 1.0,
			1.0, 0.0, 0.0, 1.0,
			1.0, 0.0, 0.0, 1.0,
			1.0, 0.0, 0.0, 1.0,
		])
		var uv := PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
		var uv2 := PackedVector2Array([Vector2(0.05, 0.05), Vector2(0.95, 0.05), Vector2(0.95, 0.95), Vector2(0.05, 0.95)])
		var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TANGENT] = t
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, m)
		mesh.lightmap_size_hint = Vector2i(128, 128)
		rug_node = k._add_mesh("NordicRug", mesh)
		rug_node.gi_mode = GeometryInstance3D.GI_MODE_STATIC

	func tick(_delta: float) -> void:
		pass


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	# Compact static lightmap atlas well under 1024x1024.
	c.s.texel = maxf(float(c.s.texel), 0.22)
	var h := _hall(c)
	match piece:
		"treehouse_deck":
			h.has_deck = true
			_build_deck_and_cabin(c)
		"treehouse_canopy":
			_build_oak_and_woodland(c)
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove, c.glass]:
		b.colour = Color.WHITE


static func _hall(c: Object) -> TreehouseHall:
	for obj: Object in c.halls:
		if obj is TreehouseHall:
			return obj
	var h := TreehouseHall.new()
	c.halls.append(h)
	return h


static func _roof_y(x: float) -> float:
	return RIDGE_Y - absf(x) * ROOF_SLOPE


static func _lin(col: Color, alpha := 1.0) -> Color:
	var l := col.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _solid(c: Object, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, basis))


# --- Piece 1: Treehouse cabin, pitched corrugated-tin roof, shutters, props & rope bridge -----------------------------

static func _build_deck_and_cabin(c: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4114

	_floor_and_wrap_deck(c, rng)
	_walls_and_propped_shutters(c, rng)
	_pitched_tin_roof_and_rafters(c, rng)
	_screen_cedar_frame(c)
	_rug_border_and_pillows(c)
	_coffee_table_and_props(c)
	_port_windowsill_props(c, rng)
	_aft_trapdoor_shelf_and_door(c, rng)
	_rope_suspension_bridge(c, rng)
	_fairy_lanterns_and_lamps(c)

	# One hidden cool-silver twilight moon SpotLight3D for lightmap baking only.
	c.spots.append([Vector3(-9.5, 11.5, -10.0), Vector3(1.5, 0.5, 1.0), Color(0.58, 0.72, 0.96), 2.1, 24.0, 44.0])


static func _floor_and_wrap_deck(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var wood_m: Material = c.tinted("wood")
	s.surface(wood_m)

	# Cabin interior cedar floor planks running fore-to-aft, neatly notched around the aft-starboard trapdoor opening!
	var plank_w := 0.26
	var x := -CABIN_HW
	while x < CABIN_HW - 0.01:
		var x1 := minf(x + plank_w, CABIN_HW)
		var w := x1 - x
		var xm := (x + x1) * 0.5
		var tone := CEDAR_WARM.lerp(CEDAR_HONEY, rng.randf() * 0.65) * rng.randf_range(0.86, 1.12)
		s.colour = _lin(tone)
		var hits_hatch := x1 > HATCH_X0 + 0.01 and x < HATCH_X1 - 0.01
		if hits_hatch:
			var len1 := HATCH_Z0 - CABIN_FZ
			s.box(Vector3(xm, -0.04, CABIN_FZ + len1 * 0.5), Vector3(w - 0.008, 0.08, len1), Basis(), [RoomMesh.DOWN])
			var len2 := CABIN_BZ - HATCH_Z1
			s.box(Vector3(xm, -0.04, HATCH_Z1 + len2 * 0.5), Vector3(w - 0.008, 0.08, len2), Basis(), [RoomMesh.DOWN])
		else:
			var full_len := CABIN_BZ - CABIN_FZ
			s.box(Vector3(xm, -0.04, (CABIN_FZ + CABIN_BZ) * 0.5), Vector3(w - 0.008, 0.08, full_len), Basis(),
					[RoomMesh.DOWN])
		x = x1

	# Wrap-around slatted exterior cedar balcony deck (port, starboard, aft porch, front ledge) slightly lower (-0.015 m).
	var deck_strips: Array = [
		# Port side walkway
		[Vector3(-DECK_HW, -0.055, DECK_FZ), Vector3(-CABIN_HW, -0.055, DECK_BZ), true],
		# Starboard side walkway
		[Vector3(CABIN_HW, -0.055, DECK_FZ), Vector3(DECK_HW, -0.055, DECK_BZ), true],
		# Aft wrap-around balcony deck (leads out to rope suspension bridge)
		[Vector3(-CABIN_HW, -0.055, CABIN_BZ), Vector3(CABIN_HW, -0.055, DECK_BZ), false],
		# Front cantilevered lookout deck ledge below the screen
		[Vector3(-CABIN_HW, -0.055, DECK_FZ), Vector3(CABIN_HW, -0.055, CABIN_FZ), false],
	]
	for ds: Array in deck_strips:
		var lo: Vector3 = ds[0]
		var hi: Vector3 = ds[1]
		var along_z: bool = ds[2]
		if along_z:
			var z := lo.z
			while z < hi.z - 0.02:
				var z1 := minf(z + 0.24, hi.z)
				var shade := rng.randf_range(0.82, 1.10)
				s.colour = _lin(CEDAR_DECK.lerp(CEDAR_WEATHERED, rng.randf() * 0.5) * shade)
				s.box(Vector3((lo.x + hi.x) * 0.5, lo.y, (z + z1) * 0.5),
						Vector3(hi.x - lo.x - 0.02, 0.065, z1 - z - 0.024))
				z = z1
		else:
			var xp := lo.x
			while xp < hi.x - 0.02:
				var xp1 := minf(xp + 0.24, hi.x)
				var shade := rng.randf_range(0.82, 1.10)
				s.colour = _lin(CEDAR_DECK.lerp(CEDAR_WEATHERED, rng.randf() * 0.5) * shade)
				s.box(Vector3((xp + xp1) * 0.5, lo.y, (lo.z + hi.z) * 0.5),
						Vector3(xp1 - xp - 0.024, 0.065, hi.z - lo.z - 0.02))
				xp = xp1

	# Heavy dark-cedar structural perimeter rim joists & cross floor bearers under the deck!
	s.colour = _lin(CEDAR_DARK)
	for sx: float in [-DECK_HW + 0.08, -CABIN_HW, 0.0, CABIN_HW, DECK_HW - 0.08]:
		s.box(Vector3(sx, -0.18, (DECK_FZ + DECK_BZ) * 0.5), Vector3(0.16, 0.22, DECK_BZ - DECK_FZ))
	for sz: float in [DECK_FZ + 0.08, -3.5, -1.0, 1.5, CABIN_BZ, DECK_BZ - 0.08]:
		s.box(Vector3(0.0, -0.18, sz), Vector3(DECK_HW * 2.0, 0.22, 0.16))

	# Dramatic diagonal timber knee struts underneath the deck bracing back toward the oak trunk & lower limbs!
	var struts: Array = [
		[Vector3(-4.7, -0.25, -4.5), Vector3(-2.6, -2.55, -2.4)],
		[Vector3(-4.7, -0.25, 1.2), Vector3(-1.8, -2.85, 1.6)],
		[Vector3(-4.5, -0.25, 5.2), Vector3(-1.6, -2.45, 3.2)],
		[Vector3(4.7, -0.25, -4.2), Vector3(3.4, -2.65, -0.4)],
		[Vector3(4.6, -0.25, 5.2), Vector3(3.7, -2.40, 2.7)],
		[Vector3(0.0, -0.25, -5.8), Vector3(1.6, -2.60, -1.5)],
		[Vector3(0.2, -0.25, 5.2), Vector3(2.9, -2.35, 2.5)],
	]
	for st: Array in struts:
		Shapes.beam(s, st[0], st[1], Vector2(0.18, 0.18))

	# Wrap-around rustic split-cedar deck balustrades (open cleanly at x = -1.65..-0.35 on aft edge for rope bridge!).
	_deck_railing_run(s, Vector3(-DECK_HW + 0.08, 0.0, DECK_FZ + 0.10), Vector3(-DECK_HW + 0.08, 0.0, DECK_BZ - 0.08), 8)
	_deck_railing_run(s, Vector3(DECK_HW - 0.08, 0.0, DECK_FZ + 0.10), Vector3(DECK_HW - 0.08, 0.0, DECK_BZ - 0.08), 8)
	_deck_railing_run(s, Vector3(-DECK_HW + 0.10, 0.0, DECK_FZ + 0.08), Vector3(DECK_HW - 0.10, 0.0, DECK_FZ + 0.08), 7)
	# Aft railing split left and right of the rope bridge entrance (-1.65 .. -0.35).
	_deck_railing_run(s, Vector3(-DECK_HW + 0.08, 0.0, DECK_BZ - 0.08), Vector3(-1.65, 0.0, DECK_BZ - 0.08), 3)
	_deck_railing_run(s, Vector3(-0.35, 0.0, DECK_BZ - 0.08), Vector3(DECK_HW - 0.08, 0.0, DECK_BZ - 0.08), 4)


static func _deck_railing_run(s: RoomMesh, a: Vector3, b: Vector3, bays: int) -> void:
	var dir := (b - a).normalized()
	var span := a.distance_to(b)
	s.colour = _lin(CEDAR_WEATHERED)
	for i in bays + 1:
		var p := a.lerp(b, float(i) / float(bays))
		var post_h := 0.96 if (i == 0 or i == bays) else 0.90
		var w := 0.11 if (i == 0 or i == bays) else 0.075
		s.box(p + Vector3(0.0, post_h * 0.5, 0.0), Vector3(w, post_h, w))
	# Top cap handrail + mid rail + rustic diagonal X-braces every other bay.
	s.colour = _lin(CEDAR_WARM)
	Shapes.beam(s, a + Vector3(0, 0.90, 0), b + Vector3(0, 0.90, 0), Vector2(0.095, 0.055))
	s.colour = _lin(CEDAR_WEATHERED)
	Shapes.beam(s, a + Vector3(0, 0.50, 0), b + Vector3(0, 0.50, 0), Vector2(0.055, 0.045))
	Shapes.beam(s, a + Vector3(0, 0.18, 0), b + Vector3(0, 0.18, 0), Vector2(0.055, 0.045))
	for i in bays:
		var p0 := a + dir * (span * float(i) / float(bays))
		var p1 := a + dir * (span * float(i + 1) / float(bays))
		if i % 2 == 0:
			Shapes.beam(s, p0 + Vector3(0, 0.20, 0), p1 + Vector3(0, 0.86, 0), Vector2(0.04, 0.04))
		else:
			Shapes.beam(s, p0 + Vector3(0, 0.86, 0), p1 + Vector3(0, 0.20, 0), Vector2(0.04, 0.04))


static func _walls_and_propped_shutters(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var wood_m: Material = c.tinted("wood")
	var iron_m: Material = c.tinted("iron")
	s.surface(wood_m)

	# Major vertical corner & wall framing posts (0.16 x 0.16 m) + knee braces.
	var posts: Array = [
		Vector3(-CABIN_HW, 0.0, CABIN_FZ),
		Vector3(-CABIN_HW, 0.0, -0.80),
		Vector3(-CABIN_HW, 0.0, CABIN_BZ),
		Vector3(CABIN_HW, 0.0, CABIN_FZ),
		Vector3(CABIN_HW, 0.0, -0.75),
		Vector3(CABIN_HW, 0.0, 1.20),
		Vector3(CABIN_HW, 0.0, CABIN_BZ),
		Vector3(-2.48, 0.0, CABIN_FZ),
		Vector3(2.48, 0.0, CABIN_FZ),
		Vector3(-1.82, 0.0, CABIN_BZ),
		Vector3(-0.18, 0.0, CABIN_BZ),
	]
	for p: Vector3 in posts:
		var h := WALL_H if absf(p.x) > 4.0 else (_roof_y(p.x) - 0.06)
		s.colour = _lin(CEDAR_DARK.lerp(CEDAR_WEATHERED, 0.4))
		s.box(Vector3(p.x, h * 0.5, p.z), Vector3(0.16, h, 0.16), Basis(), [RoomMesh.DOWN])

	# Top wall plates along port & starboard eaves + diagonal timber knee braces.
	s.colour = _lin(CEDAR_DARK)
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(side * CABIN_HW, WALL_H - 0.08, (CABIN_FZ + CABIN_BZ) * 0.5),
				Vector3(0.18, 0.18, CABIN_BZ - CABIN_FZ + 0.4))
		for kz: float in [-5.65, -0.80, 4.05]:
			var in_x := -side * 0.56
			Shapes.beam(s, Vector3(side * CABIN_HW, WALL_H - 0.68, kz),
					Vector3(side * CABIN_HW + in_x, WALL_H - 0.10, kz), Vector2(0.09, 0.09))

	# PORT WALL (x = -CABIN_HW): wainscot (y = 0..0.88), header (y = 2.60..3.05), piers, and 2 HUGE propped shutters!
	s.colour = _lin(CEDAR_WARM)
	s.box(Vector3(-CABIN_HW, 0.44, (CABIN_FZ + CABIN_BZ) * 0.5), Vector3(0.11, 0.88, CABIN_BZ - CABIN_FZ),
			Basis(), [RoomMesh.DOWN])
	s.colour = _lin(CEDAR_WEATHERED)
	s.box(Vector3(-CABIN_HW, 2.82, (CABIN_FZ + CABIN_BZ) * 0.5), Vector3(0.11, 0.46, CABIN_BZ - CABIN_FZ))
	# Piers between port windows: [-5.75..-4.65], [-1.25..-0.35], [2.95..4.15]
	for seg: Array in [[-5.75, -4.65], [-1.25, -0.35], [2.95, 4.15]]:
		var zm := (float(seg[0]) + float(seg[1])) * 0.5
		var zw := float(seg[1]) - float(seg[0])
		s.colour = _lin(CEDAR_WARM.lerp(CEDAR_WEATHERED, 0.4))
		s.box(Vector3(-CABIN_HW, 1.74, zm), Vector3(0.11, 1.72, zw))
	_propped_shutter_side(s, wood_m, iron_m, -CABIN_HW, -4.65, -1.25, 0.90, 2.58, -1.0, rng)
	_propped_shutter_side(s, wood_m, iron_m, -CABIN_HW, -0.35, 2.95, 0.90, 2.58, -1.0, rng)

	# STARBOARD WALL (x = +CABIN_HW): wainscot (notched cleanly around oak trunk z = 1.45..3.25!), header & 2 shutters!
	s.surface(wood_m)
	s.colour = _lin(CEDAR_WARM)
	s.box(Vector3(CABIN_HW, 0.44, (-5.75 + 1.45) * 0.5), Vector3(0.11, 0.88, 1.45 - (-5.75)), Basis(), [RoomMesh.DOWN])
	s.box(Vector3(CABIN_HW, 0.44, (3.25 + CABIN_BZ) * 0.5), Vector3(0.11, 0.88, CABIN_BZ - 3.25), Basis(), [RoomMesh.DOWN])
	s.colour = _lin(CEDAR_WEATHERED)
	s.box(Vector3(CABIN_HW, 2.82, (-5.75 + 1.40) * 0.5), Vector3(0.11, 0.46, 1.40 - (-5.75)))
	s.box(Vector3(CABIN_HW, 2.82, (3.30 + CABIN_BZ) * 0.5), Vector3(0.11, 0.46, CABIN_BZ - 3.30))
	for seg: Array in [[-5.75, -4.65], [-1.05, -0.45], [0.95, 1.42], [3.28, 4.15]]:
		var zm := (float(seg[0]) + float(seg[1])) * 0.5
		var zw := float(seg[1]) - float(seg[0])
		s.colour = _lin(CEDAR_WARM.lerp(CEDAR_WEATHERED, 0.4))
		s.box(Vector3(CABIN_HW, 1.74, zm), Vector3(0.11, 1.72, zw))
	_propped_shutter_side(s, wood_m, iron_m, CABIN_HW, -4.65, -1.05, 0.90, 2.58, 1.0, rng)
	_propped_shutter_side(s, wood_m, iron_m, CABIN_HW, -0.45, 0.95, 0.90, 2.58, 1.0, rng)

	# FORWARD WALL (z = CABIN_FZ): low cedar wainscot below screen & windows + 2 flanking propped-open shutters!
	s.surface(wood_m)
	s.colour = _lin(CEDAR_WARM)
	s.box(Vector3(0.0, 0.41, CABIN_FZ), Vector3(CABIN_HW * 2.0, 0.82, 0.11), Basis(), [RoomMesh.DOWN])
	# Header lintels over the two forward flank windows (x = -4.15..-2.48 and +2.48..+4.15).
	for side: float in [-1.0, 1.0]:
		var x0 := 2.48 if side > 0.0 else -CABIN_HW
		var x1 := CABIN_HW if side > 0.0 else -2.48
		var xm := (x0 + x1) * 0.5
		s.colour = _lin(CEDAR_WEATHERED)
		s.box(Vector3(xm, 2.82, CABIN_FZ), Vector3(x1 - x0, 0.46, 0.11))
		# Sloping triangular gable cheek above the flank header up to roof pitch.
		var y_out := _roof_y(CABIN_HW)
		var y_in := _roof_y(2.48)
		var g_in := side * 2.48
		var g_out := side * CABIN_HW
		s.face([Vector3(g_out, 3.04, CABIN_FZ + 0.05), Vector3(g_in, 3.04, CABIN_FZ + 0.05),
				Vector3(g_in, y_in, CABIN_FZ + 0.05), Vector3(g_out, y_out, CABIN_FZ + 0.05)], Vector3.BACK)
		s.face([Vector3(g_in, 3.04, CABIN_FZ - 0.05), Vector3(g_out, 3.04, CABIN_FZ - 0.05),
				Vector3(g_out, y_out, CABIN_FZ - 0.05), Vector3(g_in, y_in, CABIN_FZ - 0.05)], Vector3.FORWARD)
	_propped_shutter_front(s, wood_m, iron_m, -3.96, -2.62, 0.88, 2.58, CABIN_FZ, rng)
	_propped_shutter_front(s, wood_m, iron_m, 2.62, 3.96, 0.88, 2.58, CABIN_FZ, rng)

	# AFT WALL (z = CABIN_BZ): solid rustic plank wall flanking the open balcony doorway (-1.75..-0.25, y = 0..2.30)!
	s.surface(wood_m)
	s.colour = _lin(CEDAR_WARM)
	# Left aft panel (-4.15 .. -1.75)
	s.box(Vector3((-CABIN_HW - 1.75) * 0.5, WALL_H * 0.5, CABIN_BZ), Vector3(CABIN_HW - 1.75, WALL_H, 0.12),
			Basis(), [RoomMesh.DOWN])
	# Right aft panel (-0.25 .. +4.15, meeting the host oak trunk cleanly with zero corner gap!)
	s.box(Vector3((-0.25 + CABIN_HW) * 0.5, WALL_H * 0.5, CABIN_BZ), Vector3(CABIN_HW - (-0.25), WALL_H, 0.12),
			Basis(), [RoomMesh.DOWN])
	# Transom lintel above the open aft balcony doorway (-1.75 .. -0.25, y = 2.30 .. 3.05)
	s.colour = _lin(CEDAR_WEATHERED)
	s.box(Vector3(-1.0, 2.68, CABIN_BZ), Vector3(1.62, 0.76, 0.12))
	# Aft rustic triangular timber gable end (with small diamond ventilation peek-hole near the ridge!)
	s.colour = _lin(CEDAR_WARM.lerp(CEDAR_DARK, 0.25))
	s.face([Vector3(-CABIN_HW, WALL_H, CABIN_BZ - 0.06), Vector3(CABIN_HW, WALL_H, CABIN_BZ - 0.06),
			Vector3(0.0, RIDGE_Y - 0.08, CABIN_BZ - 0.06)], Vector3.FORWARD)
	s.face([Vector3(CABIN_HW, WALL_H, CABIN_BZ + 0.06), Vector3(-CABIN_HW, WALL_H, CABIN_BZ + 0.06),
			Vector3(0.0, RIDGE_Y - 0.08, CABIN_BZ + 0.06)], Vector3.BACK)

	# Interior cedar wainscoting trim rail & skirting baseboards.
	s.colour = _lin(CEDAR_DARK)
	s.box(Vector3(-CABIN_HW + 0.08, 0.89, (CABIN_FZ + CABIN_BZ) * 0.5), Vector3(0.18, 0.055, CABIN_BZ - CABIN_FZ))
	s.box(Vector3(CABIN_HW - 0.08, 0.89, (-5.75 + 1.45) * 0.5), Vector3(0.18, 0.055, 1.45 - (-5.75)))
	s.box(Vector3(0.0, 0.84, CABIN_FZ + 0.07), Vector3(CABIN_HW * 2.0, 0.055, 0.16))

	# Wall physics boxes (all strictly at |x| = 4.15 or z = -5.75 / +4.15, well clear of (0, 0, 0)).
	_solid(c, Vector3(-CABIN_HW, 1.5, -0.8), Vector3(0.24, 3.1, 10.0))
	_solid(c, Vector3(CABIN_HW, 1.5, -2.2), Vector3(0.24, 3.1, 7.2))
	_solid(c, Vector3(0.0, 0.42, CABIN_FZ), Vector3(8.3, 0.84, 0.24))


## Wide planked timber shutter hinged at y_top on a side wall, propped wide open at 73 deg as a rain awning on wooden stays.
static func _propped_shutter_side(s: RoomMesh, wood_m: Material, iron_m: Material, wall_x: float, z0: float,
		z1: float, y0: float, y1: float, out_sign: float, rng: RandomNumberGenerator) -> void:
	var zm := (z0 + z1) * 0.5
	var w := z1 - z0
	var h := y1 - y0
	var panel_h := minf(h * 0.78, 1.32)
	# Cedar window casing trim & deep sill lip.
	s.surface(wood_m)
	s.colour = _lin(CEDAR_DARK)
	s.box(Vector3(wall_x, y0 - 0.02, zm), Vector3(0.22, 0.05, w + 0.16))
	s.box(Vector3(wall_x, y1 + 0.03, zm), Vector3(0.18, 0.06, w + 0.16))
	for ez: float in [z0, z1]:
		s.box(Vector3(wall_x, (y0 + y1) * 0.5, ez), Vector3(0.16, h + 0.06, 0.08))

	# Propped-open shutter panel pivoting wide outward from top hinge at 73 deg so the misty forest view is wide open!
	var tilt := deg_to_rad(73.0)
	var out_vec := Vector3(out_sign * sin(tilt), -cos(tilt), 0.0)
	var up_norm := Vector3(out_sign * cos(tilt), sin(tilt), 0.0)
	var bx := up_norm
	var by := -out_vec
	var bz := bx.cross(by).normalized()
	var basis := Basis(bx, by, bz)
	var hinge := Vector3(wall_x + out_sign * 0.06, y1 + 0.02, zm)
	var panel_c := hinge + out_vec * (panel_h * 0.52)

	# Built from horizontal weathered planks + twin rustic cross-battens underneath!
	var planks := 5
	for i in planks:
		var frac := (float(i) + 0.5) / float(planks)
		var pc := hinge + out_vec * (panel_h * frac * 0.96)
		s.colour = _lin(CEDAR_WEATHERED.lerp(CEDAR_WARM, rng.randf() * 0.55) * rng.randf_range(0.88, 1.08))
		s.box(pc, Vector3(0.042, panel_h / float(planks) - 0.014, w - 0.04), basis)
	s.colour = _lin(CEDAR_DARK)
	for b_off: float in [-w * 0.34, 0.0, w * 0.34]:
		s.box(panel_c - up_norm * 0.036 + Vector3(0, 0, b_off), Vector3(0.036, panel_h * 0.88, 0.085), basis)

	# Twin angled wooden stay rods propping the wide-open awning from the outer sill!
	s.colour = _lin(CEDAR_HONEY)
	for sz: float in [z0 + 0.24, z1 - 0.24]:
		var sill_p := Vector3(wall_x + out_sign * 0.08, y0 + 0.04, sz)
		var tip_p := Vector3(hinge.x, hinge.y, sz) + out_vec * (panel_h * 0.72) - up_norm * 0.03
		Shapes.beam(s, sill_p, tip_p, Vector2(0.038, 0.038))

	# Black wrought-iron strap hinges along the top shutter edge.
	s.surface(iron_m)
	s.colour = _lin(IRON_DARK)
	for hz: float in [z0 + 0.36, z1 - 0.36]:
		var hc := Vector3(hinge.x, hinge.y, hz) + out_vec * 0.16 + up_norm * 0.025
		s.box(hc, Vector3(0.02, 0.28, 0.055), basis)


static func _propped_shutter_front(s: RoomMesh, wood_m: Material, iron_m: Material, x0: float, x1: float, y0: float,
		y1: float, wall_z: float, rng: RandomNumberGenerator) -> void:
	var xm := (x0 + x1) * 0.5
	var w := x1 - x0
	var h := y1 - y0
	var panel_h := minf(h * 0.76, 1.28)
	s.surface(wood_m)
	s.colour = _lin(CEDAR_DARK)
	s.box(Vector3(xm, y0 - 0.02, wall_z), Vector3(w + 0.14, 0.05, 0.20))
	s.box(Vector3(xm, y1 + 0.03, wall_z), Vector3(w + 0.14, 0.06, 0.18))
	for ex: float in [x0, x1]:
		s.box(Vector3(ex, (y0 + y1) * 0.5, wall_z), Vector3(0.08, h + 0.06, 0.16))

	# Hinge wide outward toward -Z at 74 deg!
	var tilt := deg_to_rad(74.0)
	var out_vec := Vector3(0.0, -cos(tilt), -sin(tilt))
	var up_norm := Vector3(0.0, sin(tilt), -cos(tilt))
	var bx := Vector3.RIGHT
	var by := -out_vec
	var bz := bx.cross(by).normalized()
	var basis := Basis(bx, by, bz)
	var hinge := Vector3(xm, y1 + 0.02, wall_z - 0.06)
	var panel_c := hinge + out_vec * (panel_h * 0.52)

	for i in 5:
		var frac := (float(i) + 0.5) / 5.0
		var pc := hinge + out_vec * (panel_h * frac * 0.96)
		s.colour = _lin(CEDAR_WEATHERED.lerp(CEDAR_WARM, rng.randf() * 0.5) * rng.randf_range(0.88, 1.08))
		s.box(pc, Vector3(w - 0.04, panel_h / 5.0 - 0.014, 0.042), basis)
	s.colour = _lin(CEDAR_DARK)
	for bx_o: float in [-w * 0.30, w * 0.30]:
		s.box(panel_c - up_norm * 0.036 + Vector3(bx_o, 0, 0), Vector3(0.08, panel_h * 0.86, 0.036), basis)
	s.colour = _lin(CEDAR_HONEY)
	for sx: float in [x0 + 0.20, x1 - 0.20]:
		var sill_p := Vector3(sx, y0 + 0.04, wall_z - 0.07)
		var tip_p := Vector3(sx, hinge.y, hinge.z) + out_vec * (panel_h * 0.72) - up_norm * 0.03
		Shapes.beam(s, sill_p, tip_p, Vector2(0.036, 0.036))

	s.surface(iron_m)
	s.colour = _lin(IRON_DARK)
	for hx: float in [x0 + 0.28, x1 - 0.28]:
		var hc := Vector3(hx, hinge.y, hinge.z) + out_vec * 0.16 + up_norm * 0.025
		s.box(hc, Vector3(0.055, 0.26, 0.02), basis)


static func _pitched_tin_roof_and_rafters(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var wood_m: Material = c.tinted("wood")
	var tin_m: Material = c.tinted("tin", "corrugated")
	var iron_m: Material = c.tinted("iron")

	# 1. Pitched weathered corrugated-tin roof sheets (both underside visible from inside & top weather face!).
	s.surface(tin_m)
	var slope_ang := atan(ROOF_SLOPE)
	var slope_len := sqrt(EAVE_X * EAVE_X + (RIDGE_Y - _roof_y(EAVE_X)) * (RIDGE_Y - _roof_y(EAVE_X)))
	var roof_len := EAVE_BZ - EAVE_FZ
	var roof_cz := (EAVE_FZ + EAVE_BZ) * 0.5
	# Split into 7 overlapping corrugated panels fore-to-aft per side for rich authentic galvanized & patina variation!
	var panels := 7
	var panel_z := roof_len / float(panels)
	for side: float in [-1.0, 1.0]:
		var b := Basis(Vector3.FORWARD, side * slope_ang)
		var mid_x := side * EAVE_X * 0.5
		var mid_y := (RIDGE_Y + _roof_y(EAVE_X)) * 0.5 + 0.10
		for pi in panels:
			var pz := EAVE_FZ + (float(pi) + 0.5) * panel_z
			var col := TIN_BASE.lerp(TIN_PATINA, rng.randf() * 0.72) * rng.randf_range(0.86, 1.10)
			s.colour = _lin(col)
			s.box(Vector3(mid_x, mid_y, pz), Vector3(slope_len + 0.08, 0.045, panel_z + 0.04), b)

	# Dark galvanized ridge cap & deep rainwater eave gutters along both overhangs.
	s.surface(iron_m)
	s.colour = _lin(Color(0.24, 0.25, 0.25))
	s.box(Vector3(0.0, RIDGE_Y + 0.15, roof_cz), Vector3(0.28, 0.08, roof_len + 0.14))
	for side: float in [-1.0, 1.0]:
		var ey := _roof_y(EAVE_X) + 0.04
		s.box(Vector3(side * (EAVE_X + 0.06), ey, roof_cz), Vector3(0.11, 0.09, roof_len + 0.10))
	# Sculpted fitted octagonal cedar roof & floor collar rings snugly scribed around the living oak trunk!
	s.surface(wood_m)
	s.colour = _lin(CEDAR_DARK)
	Shapes.arch(s, Vector3(TRUNK_X, _roof_y(TRUNK_X) + 0.04, TRUNK_Z), 0.78, 1.16, 0.14, 10,
			Basis(Vector3.FORWARD, slope_ang) * Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU)
	Shapes.arch(s, Vector3(TRUNK_X, 0.03, TRUNK_Z), 0.86, 1.18, 0.07, 10, Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU)

	# 2. Exposed honey-cedar ridge beam, 9 pairs of pitched rafters, horizontal purlins & high king-post collar ties!
	s.surface(wood_m)
	s.colour = _lin(CEDAR_DARK)
	s.box(Vector3(0.0, RIDGE_Y - 0.06, roof_cz), Vector3(0.16, 0.24, roof_len - 0.12))

	var rafter_zs: Array[float] = [-6.35, -5.75, -4.45, -3.15, -1.85, -0.55, 0.75, 2.05, 3.35, 4.15, 4.95]
	for ri in rafter_zs.size():
		var rz := rafter_zs[ri]
		for side: float in [-1.0, 1.0]:
			var top_p := Vector3(0.0, RIDGE_Y - 0.02, rz)
			var eave_p := Vector3(side * EAVE_X, _roof_y(EAVE_X) - 0.02, rz)
			s.colour = _lin(CEDAR_WARM.lerp(CEDAR_DARK, 0.30))
			Shapes.beam(s, top_p, eave_p, Vector2(0.10, 0.16))
		# High king-post collar tie beam on interior trusses (y = 3.86 m — well above screen top 3.23 m & sightlines!).
		if ri in [1, 3, 5, 7, 9]:
			var tie_x := (RIDGE_Y - 3.88) / ROOF_SLOPE
			s.colour = _lin(CEDAR_HONEY.lerp(CEDAR_WARM, 0.5))
			Shapes.beam(s, Vector3(-tie_x, 3.88, rz), Vector3(tie_x, 3.88, rz), Vector2(0.11, 0.13))
			Shapes.beam(s, Vector3(0.0, 3.92, rz), Vector3(0.0, RIDGE_Y - 0.10, rz), Vector2(0.10, 0.10))
			# Cute angled king-post struts!
			for side: float in [-1.0, 1.0]:
				Shapes.beam(s, Vector3(0.0, 3.94, rz), Vector3(side * 0.92, _roof_y(0.92) - 0.06, rz), Vector2(0.075, 0.075))

	# Horizontal cedar purlins tying all rafters cleanly under the corrugated tin sheets!
	s.colour = _lin(CEDAR_HONEY)
	for side: float in [-1.0, 1.0]:
		for px: float in [1.35, 2.75, 4.15, 4.98]:
			var py := _roof_y(px) + 0.04
			s.box(Vector3(side * px, py, roof_cz), Vector3(0.08, 0.075, roof_len - 0.08),
					Basis(Vector3.FORWARD, side * slope_ang))


static func _screen_cedar_frame(c: Object) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 2.05, -5.40)))
	var sc_sz: Vector2 = scr.get("size", Vector2(4.2, 2.36))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var cz := sc_xf.origin.z
	var hw := sc_sz.x * 0.5
	var hh := sc_sz.y * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wood_m: Material = c.tinted("wood")
	var cloth_m: Material = c.tinted("cloth")
	var cloth_soft: Material = c.soft("cloth", true)
	var wood_soft: Material = c.soft("wood", true)
	var iron_m: Material = c.tinted("iron")

	# 1. Taut canvas cinema backing slab strictly behind screen plane (z = cz - 0.12 -> -5.52).
	s.surface(iron_m)
	s.colour = _lin(Color(0.07, 0.065, 0.06))
	s.box(Vector3(cx, cy, cz - 0.14), Vector3(sc_sz.x + 0.22, sc_sz.y + 0.22, 0.08))
	s.surface(cloth_m)
	s.colour = _lin(CANVAS_WEATHERED * 0.55)
	s.box(Vector3(cx, cy, cz - 0.19), Vector3(sc_sz.x + 0.34, sc_sz.y + 0.34, 0.04))

	# 2. Hand-lashed round weathered cedar poles framing all four edges strictly OUTSIDE screen bounds!
	u.surface(wood_soft)
	u.colour = _lin(CEDAR_HONEY.lerp(CEDAR_WARM, 0.5))
	var px_out := hw + 0.16 # 2.26 m
	var y_bot := cy - hh - 0.14 # 0.73 m
	var y_top := cy + hh + 0.14 # 3.37 m
	var pole_z := cz - 0.08 # -5.48 m
	# Left & right vertical cedar poles extending down into floor bench & up to rafters!
	for side: float in [-1.0, 1.0]:
		Shapes.cylinder(u, Vector3(cx + side * px_out, 0.0, pole_z), 0.075, _roof_y(px_out) - 0.05, 10)
	# Top & bottom horizontal cedar crossbars overhanging past the vertical poles!
	Shapes.cylinder(u, Vector3(cx - px_out - 0.32, y_top, pole_z), 0.068, (px_out + 0.32) * 2.0, 10,
			Basis(Vector3.BACK, -PI * 0.5))
	Shapes.cylinder(u, Vector3(cx - px_out - 0.28, y_bot, pole_z), 0.062, (px_out + 0.28) * 2.0, 10,
			Basis(Vector3.BACK, -PI * 0.5))

	# Cross-lashed hemp rope bindings at all four corners + side screen-tension cords!
	u.surface(cloth_soft)
	u.colour = _lin(ROPE_HEMP)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [y_bot, y_top]:
			var lc := Vector3(cx + sx * px_out, sy, pole_z)
			for diag: float in [-1.0, 1.0]:
				var rb := Basis(Vector3.BACK, diag * deg_to_rad(42.0))
				u.rounded_box(Vector3.ZERO, Vector3(0.22, 0.16, 0.19), 0.045, Transform3D(rb, lc), 1)
		# Tension lacing cords tying the canvas edge cleanly to the cedar side poles.
		for k in 7:
			var ly := lerpf(y_bot + 0.22, y_top - 0.22, float(k) / 6.0)
			Shapes.beam(u, Vector3(cx + sx * (hw + 0.05), ly, pole_z),
					Vector3(cx + sx * px_out, ly + 0.04, pole_z), Vector2(0.016, 0.016))

	# 3. Rolled weathered canvas weather flaps strapped above the top spar & tied back beside the cedar poles!
	u.surface(cloth_soft)
	u.colour = _lin(CANVAS_CREAM.lerp(CANVAS_WEATHERED, 0.35))
	# Top rolled weather awning flap (y = 3.49 m, strictly above screen top 3.23 m!).
	Shapes.cylinder(u, Vector3(cx - hw - 0.10, y_top + 0.11, pole_z + 0.02), 0.095, sc_sz.x + 0.20, 10,
			Basis(Vector3.BACK, -PI * 0.5))
	# Two rolled canvas side flaps tied neatly outside the vertical poles (|x| = 2.40 m).
	for side: float in [-1.0, 1.0]:
		Shapes.cylinder(u, Vector3(cx + side * (px_out + 0.12), y_bot + 0.05, pole_z + 0.02), 0.072,
				y_top - y_bot - 0.10, 10)
		# Hemp tie-straps cinching the rolled flaps.
		u.colour = _lin(ROPE_HEMP * 0.85)
		for ty: float in [1.35, 2.05, 2.75]:
			Shapes.cylinder(u, Vector3(cx + side * (px_out + 0.12), ty, pole_z + 0.02), 0.079, 0.032, 10)
		u.colour = _lin(CANVAS_CREAM.lerp(CANVAS_WEATHERED, 0.35))
	u.colour = _lin(ROPE_HEMP * 0.85)
	for tx: float in [-1.45, 0.0, 1.45]:
		Shapes.cylinder(u, Vector3(cx + tx, y_top + 0.11, pole_z + 0.02), 0.103, 0.036, 10,
				Basis(Vector3.BACK, -PI * 0.5))

	# 4. Built-in rustic cedar storage bench under the screen (y = 0.0..0.46, z = -5.66..-5.22) with coiled rope & blanket!
	s.surface(wood_m)
	s.colour = _lin(CEDAR_HONEY.lerp(CEDAR_WARM, 0.5))
	s.box(Vector3(0.0, 0.44, -5.45), Vector3(3.95, 0.055, 0.48))
	s.colour = _lin(CEDAR_DARK)
	for bx: float in [-1.80, -0.60, 0.60, 1.80]:
		s.box(Vector3(bx, 0.21, -5.45), Vector3(0.09, 0.42, 0.42), Basis(), [RoomMesh.DOWN])
	# Folded crimson-tartan wool blanket & coiled climbing rope resting cleanly on the under-screen bench!
	u.surface(cloth_soft)
	u.colour = _lin(BLANKET_PLAID)
	u.rounded_box(Vector3.ZERO, Vector3(0.62, 0.14, 0.38), 0.04,
			Transform3D(Basis(Vector3.UP, 0.12), Vector3(-1.15, 0.54, -5.44)), 1)
	u.colour = _lin(PILLOW_OCHRE * 0.9)
	u.rounded_box(Vector3.ZERO, Vector3(0.56, 0.04, 0.36), 0.015,
			Transform3D(Basis(Vector3.UP, 0.12), Vector3(-1.15, 0.61, -5.44)), 1)
	# Coiled hemp climbing rope on the right side of the bench.
	u.colour = _lin(ROPE_HEMP)
	for ring_i in 3:
		Shapes.arch(u, Vector3(1.22, 0.49 + float(ring_i) * 0.038, -5.44), 0.11, 0.175, 0.036, 14,
				Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU)


static func _rug_border_and_pillows(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cloth_m: Material = c.tinted("cloth")
	var cloth_soft: Material = c.soft("cloth", true)

	# Raised braided moss-terracotta rug hem & delicate fringe tassels framing NordicRug!
	s.surface(cloth_m)
	s.colour = _lin(PILLOW_MOSS * 0.82)
	var bw := 0.065
	var rx_len := RUG_X1 - RUG_X0
	var rz_len := RUG_Z1 - RUG_Z0
	s.box(Vector3(0.0, 0.006, RUG_Z0 - bw * 0.4), Vector3(rx_len + bw * 2.0, 0.012, bw), Basis(), [RoomMesh.DOWN])
	s.box(Vector3(0.0, 0.006, RUG_Z1 + bw * 0.4), Vector3(rx_len + bw * 2.0, 0.012, bw), Basis(), [RoomMesh.DOWN])
	s.box(Vector3(RUG_X0 - bw * 0.4, 0.006, (RUG_Z0 + RUG_Z1) * 0.5), Vector3(bw, 0.012, rz_len), Basis(), [RoomMesh.DOWN])
	s.box(Vector3(RUG_X1 + bw * 0.4, 0.006, (RUG_Z0 + RUG_Z1) * 0.5), Vector3(bw, 0.012, rz_len), Basis(), [RoomMesh.DOWN])
	# Cream braided fringe tassels at front & back rug edges.
	s.colour = _lin(CANVAS_CREAM * 0.92)
	for fz: float in [RUG_Z0 - bw - 0.035, RUG_Z1 + bw + 0.035]:
		for i in 16:
			var fx := lerpf(RUG_X0 + 0.12, RUG_X1 - 0.12, float(i) / 15.0)
			s.box(Vector3(fx, 0.004, fz), Vector3(0.04, 0.008, 0.08), Basis(), [RoomMesh.DOWN])

	# Four plump hand-stitched mossy-green, ochre & berry floor throw pillows tucked near the rug flanks!
	u.surface(cloth_soft)
	var pillows: Array = [
		[Vector3(-2.02, 0.09, -0.35), Vector3(0.50, 0.17, 0.48), 0.32, PILLOW_MOSS],
		[Vector3(2.04, 0.09, -0.25), Vector3(0.48, 0.17, 0.48), -0.42, PILLOW_OCHRE],
		[Vector3(-2.06, 0.09, 1.95), Vector3(0.52, 0.17, 0.46), -0.25, PILLOW_BERRY],
		[Vector3(2.02, 0.09, 1.72), Vector3(0.50, 0.17, 0.48), 0.55, PILLOW_MOSS],
	]
	for pl: Array in pillows:
		u.colour = _lin(pl[3])
		u.rounded_box(Vector3.ZERO, pl[1], 0.065, Transform3D(Basis(Vector3.UP, float(pl[2])), pl[0]), 2,
				Vector3i(1, 0, 1), 0.0, [RoomMesh.DOWN])


static func _coffee_table_and_props(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var glass: RoomMesh = c.glass
	var wood_m: Material = c.tinted("wood")
	var wood_soft: Material = c.soft("wood", true)
	var enamel_m: Material = c.shiny("iron", 0.0, 0.36, 0.18)
	var brass_m: Material = c.shiny("gilt", 1.0, 0.72, 0.18)
	var cloth_soft: Material = c.soft("cloth", true)
	var shade_m: Material = c.shade(LANTERN_AMBER)

	# Low rustic cedar-crate & tree-stump coffee table (strictly y_top = 0.36 m <= 0.40 m, clear of all sightlines!).
	var tz := -1.92
	var table_y := 0.36
	# Two organic bark-rimmed cedar stump legs supporting the tabletop!
	u.surface(wood_soft)
	for sx: float in [-0.42, 0.42]:
		u.colour = _lin(BARK_WARM)
		Shapes.lathe(u, [
			Vector2(0.18, 0.0),
			Vector2(0.155, 0.08),
			Vector2(0.145, 0.22),
			Vector2(0.16, 0.315),
		], Vector3(sx, 0.0, tz), 10)
	# Slatted warm cedar-plank tabletop + lower wooden crate magazine shelf + woven linen tea runner!
	s.surface(wood_m)
	for pi in 4:
		var pz := tz - 0.23 + float(pi) * 0.153
		s.colour = _lin(CEDAR_HONEY.lerp(CEDAR_WARM, float(pi % 2) * 0.45))
		s.box(Vector3(0.0, table_y - 0.022, pz), Vector3(1.24, 0.044, 0.142))
	s.colour = _lin(CEDAR_WEATHERED)
	s.box(Vector3(0.0, 0.14, tz), Vector3(0.76, 0.028, 0.42))
	_solid(c, Vector3(0.0, table_y * 0.5, tz), Vector3(1.24, table_y, 0.62))
	u.surface(cloth_soft)
	u.colour = _lin(PILLOW_MOSS * 0.85)
	u.box(Vector3(-0.20, table_y + 0.004, tz + 0.03), Vector3(0.66, 0.008, 0.44))

	# 1. Deep forest-pine camp enamel teapot with brass lid finial (center-left at x = -0.26, y = 0.36, z = tz - 0.04).
	var tp := Vector3(-0.26, table_y + 0.006, tz - 0.04)
	u.surface(enamel_m)
	u.colour = _lin(ENAMEL_FOREST)
	Shapes.lathe(u, [
		Vector2(0.082, 0.0),
		Vector2(0.095, 0.045),
		Vector2(0.090, 0.105),
		Vector2(0.068, 0.142),
		Vector2(0.062, 0.152),
		Vector2(0.022, 0.172),
		Vector2(0.0, 0.180),
	], tp, 12)
	u.surface(brass_m)
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [Vector2(0.014, 0.176), Vector2(0.019, 0.190), Vector2(0.0, 0.198)], tp, 8)
	u.surface(enamel_m)
	u.colour = _lin(ENAMEL_FOREST)
	# Curved spout & arched dark-enamel handle!
	Shapes.beam(u, tp + Vector3(0.075, 0.042, 0.0), tp + Vector3(0.142, 0.125, 0.0), Vector2(0.022, 0.022))
	u.colour = _lin(IRON_DARK)
	Shapes.beam(u, tp + Vector3(-0.078, 0.125, 0.0), tp + Vector3(-0.128, 0.112, 0.0), Vector2(0.014, 0.014))
	Shapes.beam(u, tp + Vector3(-0.128, 0.112, 0.0), tp + Vector3(-0.132, 0.045, 0.0), Vector2(0.014, 0.014))
	Shapes.beam(u, tp + Vector3(-0.132, 0.045, 0.0), tp + Vector3(-0.086, 0.032, 0.0), Vector2(0.014, 0.014))

	# 2. Two cozy enamel camp mugs beside the teapot (oat-cream & clay-terracotta with dark rim & warm tea meniscus!).
	var mugs: Array = [
		[Vector3(-0.02, table_y + 0.006, tz + 0.11), ENAMEL_CREAM, 0.45],
		[Vector3(-0.46, table_y + 0.006, tz + 0.13), ENAMEL_TERRA, -0.60],
	]
	for mg: Array in mugs:
		var mp: Vector3 = mg[0]
		var mc: Color = mg[1]
		var myaw: float = float(mg[2])
		u.surface(enamel_m)
		u.colour = _lin(mc)
		Shapes.lathe(u, [Vector2(0.042, 0.0), Vector2(0.044, 0.078), Vector2(0.046, 0.088)], mp, 10)
		u.colour = _lin(IRON_DARK)
		Shapes.lathe(u, [Vector2(0.045, 0.084), Vector2(0.047, 0.092), Vector2(0.038, 0.092)], mp, 10)
		# Warm dark steeped-tea surface inside each mug!
		u.colour = _lin(Color(0.22, 0.10, 0.04))
		Shapes.cylinder(u, mp + Vector3(0, 0.072, 0), 0.039, 0.008, 10)
		# Tiny mug handle
		u.colour = _lin(IRON_DARK)
		var hd := Vector3(cos(myaw), 0.0, sin(myaw))
		Shapes.beam(u, mp + hd * 0.044 + Vector3(0, 0.072, 0), mp + hd * 0.072 + Vector3(0, 0.066, 0), Vector2(0.010, 0.010))
		Shapes.beam(u, mp + hd * 0.072 + Vector3(0, 0.066, 0), mp + hd * 0.072 + Vector3(0, 0.024, 0), Vector2(0.010, 0.010))
		Shapes.beam(u, mp + hd * 0.072 + Vector3(0, 0.024, 0), mp + hd * 0.044 + Vector3(0, 0.018, 0), Vector2(0.010, 0.010))

	# 3. Gleaming brass oil hurricane lantern (x = +0.18, y = 0.36..0.62 m -> well below sightline y >= 1.04 m!).
	var lp := Vector3(0.18, table_y, tz - 0.06)
	u.surface(brass_m)
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [
		Vector2(0.078, 0.0),
		Vector2(0.082, 0.032),
		Vector2(0.066, 0.058),
		Vector2(0.048, 0.072),
	], lp, 12)
	Shapes.lathe(u, [
		Vector2(0.054, 0.185),
		Vector2(0.072, 0.205),
		Vector2(0.036, 0.232),
		Vector2(0.016, 0.250),
	], lp, 12)
	# Twin brass air-draft tubes flanking the glass chimney.
	for sx: float in [-1.0, 1.0]:
		Shapes.beam(u, lp + Vector3(sx * 0.072, 0.045, 0), lp + Vector3(sx * 0.072, 0.195, 0), Vector2(0.011, 0.011))
		Shapes.beam(u, lp + Vector3(sx * 0.072, 0.195, 0), lp + Vector3(sx * 0.032, 0.228, 0), Vector2(0.010, 0.010))
	# Clear glass hurricane globe (PieceGlass) + warm glowing flame core (PieceLamps)!
	glass.surface(c.mat("tin"))
	Shapes.lathe(glass, [
		Vector2(0.046, 0.072),
		Vector2(0.060, 0.125),
		Vector2(0.050, 0.186),
	], lp, 12)
	lit.surface(shade_m)
	lit.colour = Color.WHITE
	Shapes.lathe(lit, [
		Vector2(0.010, 0.095),
		Vector2(0.022, 0.120),
		Vector2(0.016, 0.150),
		Vector2(0.0, 0.166),
	], lp, 8)
	c.lamps.append([lp + Vector3(0.0, 0.18, 0.0), LANTERN_AMBER, 0.55])

	# 4. Neat stack of 3 hardcover woodland field guides (right side at x = +0.44, z = tz + 0.06).
	var books: Array = [
		[Vector3(0.44, table_y + 0.020, tz + 0.07), Vector3(0.24, 0.040, 0.18), 0.14, PILLOW_MOSS],
		[Vector3(0.43, table_y + 0.056, tz + 0.06), Vector3(0.22, 0.032, 0.165), -0.18, PILLOW_BERRY],
		[Vector3(0.45, table_y + 0.088, tz + 0.07), Vector3(0.20, 0.030, 0.155), 0.28, PILLOW_OCHRE],
	]
	for bk: Array in books:
		var bp: Vector3 = bk[0]
		var bs: Vector3 = bk[1]
		var byaw: float = float(bk[2])
		var bc: Color = bk[3]
		var bb := Basis(Vector3.UP, byaw)
		u.surface(cloth_soft)
		u.colour = _lin(bc)
		u.box(bp, bs, bb)
		u.colour = _lin(PAPER_CREAM)
		u.box(bp + bb * Vector3(0.008, 0.0, 0.006), Vector3(bs.x - 0.012, bs.y - 0.010, bs.z - 0.012), bb)


static func _port_windowsill_props(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var glass: RoomMesh = c.glass
	var wood_m: Material = c.tinted("wood")
	var brass_m: Material = c.shiny("gilt", 1.0, 0.72, 0.18)
	var enamel_m: Material = c.shiny("iron", 0.0, 0.36, 0.18)
	var cloth_soft: Material = c.soft("cloth", true)
	var leaf_m: Material = c.soft("leaves", true)
	var shade_m: Material = c.shade(LANTERN_AMBER)

	# Deep rustic cedar windowsill shelf running along the port windows (x = -3.96, y = 0.88 m)!
	var shelf_x := -3.96
	var shelf_y := 0.90
	s.surface(wood_m)
	s.colour = _lin(CEDAR_HONEY.lerp(CEDAR_WARM, 0.4))
	s.box(Vector3(shelf_x, shelf_y - 0.025, -2.95), Vector3(0.32, 0.05, 3.55))
	s.box(Vector3(shelf_x, shelf_y - 0.025, 1.30), Vector3(0.32, 0.05, 3.45))
	# Angled timber shelf corbel brackets underneath.
	s.colour = _lin(CEDAR_DARK)
	for bz: float in [-4.30, -2.95, -1.60, -0.05, 1.30, 2.65]:
		Shapes.beam(s, Vector3(-CABIN_HW + 0.06, 0.64, bz), Vector3(shelf_x + 0.12, shelf_y - 0.04, bz),
				Vector2(0.055, 0.055))

	# 1. Three warm glowing jam-jar candles spaced along the port windowsill!
	for jz: float in [-3.65, -1.75, 0.65]:
		var jp := Vector3(shelf_x + 0.02, shelf_y, jz)
		u.surface(cloth_soft)
		u.colour = _lin(CANDLE_WAX)
		Shapes.cylinder(u, jp + Vector3(0, 0.010, 0), 0.044, 0.080, 10)
		u.surface(brass_m)
		u.colour = _lin(BRASS_AGED)
		Shapes.lathe(u, [Vector2(0.054, 0.145), Vector2(0.060, 0.162), Vector2(0.048, 0.166)], jp, 10)
		glass.surface(c.mat("tin"))
		Shapes.lathe(glass, [
			Vector2(0.056, 0.0),
			Vector2(0.062, 0.026),
			Vector2(0.062, 0.132),
			Vector2(0.054, 0.155),
		], jp, 10)
		lit.surface(shade_m)
		lit.colour = Color.WHITE
		Shapes.lathe(lit, [Vector2(0.012, 0.088), Vector2(0.028, 0.115), Vector2(0.020, 0.145), Vector2(0.0, 0.162)],
				jp, 8)

	# 2. Hero gleaming telescoping brass spyglass on a carved cedar swivel stand aimed out through the port window!
	var sp := Vector3(shelf_x + 0.01, shelf_y, -2.68)
	s.surface(wood_m)
	s.colour = _lin(CEDAR_DARK)
	s.box(sp + Vector3(0.0, 0.020, 0.0), Vector3(0.18, 0.040, 0.30))
	for oz: float in [-0.10, 0.10]:
		s.box(sp + Vector3(0.0, 0.10, oz), Vector3(0.036, 0.16, 0.032))
	u.surface(brass_m)
	u.colour = _lin(BRASS_WARM)
	var spy_b := Basis(Vector3.UP, deg_to_rad(-22.0)) * Basis(Vector3.BACK, deg_to_rad(104.0))
	var spy_base := sp + Vector3(0.13, 0.15, 0.05)
	Shapes.cylinder(u, spy_base, 0.024, 0.22, 10, spy_b)
	Shapes.cylinder(u, spy_base + spy_b * Vector3(0, 0.21, 0), 0.033, 0.24, 10, spy_b)
	Shapes.cylinder(u, spy_base + spy_b * Vector3(0, 0.44, 0), 0.043, 0.26, 12, spy_b)
	u.surface(cloth_soft)
	u.colour = _lin(CEDAR_DARK)
	Shapes.cylinder(u, spy_base + spy_b * Vector3(0, 0.25, 0), 0.036, 0.16, 10, spy_b)

	# 3. Vintage painted spruce-teal tin biscuit box with oat-cream lid, gold stripe & brass latch at z = +1.72.
	var bp := Vector3(shelf_x + 0.02, shelf_y, 1.72)
	u.surface(enamel_m)
	u.colour = _lin(BISCUIT_TEAL)
	u.box(bp + Vector3(0.0, 0.080, 0.0), Vector3(0.22, 0.16, 0.30), Basis(Vector3.UP, 0.14))
	u.colour = _lin(ENAMEL_CREAM)
	u.box(bp + Vector3(0.0, 0.166, 0.0), Vector3(0.236, 0.034, 0.316), Basis(Vector3.UP, 0.14))
	u.surface(brass_m)
	u.colour = _lin(BRASS_WARM)
	u.box(bp + Vector3(0.0, 0.085, 0.0), Vector3(0.226, 0.028, 0.306), Basis(Vector3.UP, 0.14))
	u.box(bp + Vector3(0.118, 0.150, 0.014), Vector3(0.020, 0.040, 0.048), Basis(Vector3.UP, 0.14))

	# 4. Terracotta pot with lush feathery fern fronds at aft end of port sill (z = +2.55).
	var fp := Vector3(shelf_x + 0.02, shelf_y, 2.55)
	u.surface(enamel_m)
	u.colour = _lin(ENAMEL_TERRA)
	Shapes.lathe(u, [Vector2(0.072, 0.0), Vector2(0.098, 0.13), Vector2(0.110, 0.158), Vector2(0.095, 0.164)], fp, 10)
	u.surface(leaf_m)
	_fern_clump(u, fp + Vector3(0.0, 0.15, 0.0), 0.44, rng)


static func _aft_trapdoor_shelf_and_door(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var glass: RoomMesh = c.glass
	var wood_m: Material = c.tinted("wood")
	var iron_m: Material = c.tinted("iron")
	var brass_m: Material = c.shiny("gilt", 1.0, 0.72, 0.18)
	var cloth_soft: Material = c.soft("cloth", true)

	# 1. Open rustic Z-braced cedar balcony door swung open at the aft doorway (x = -1.75..-0.25, z = CABIN_BZ)!
	s.surface(wood_m)
	s.colour = _lin(CEDAR_DARK)
	# Doorway frame casing.
	s.box(Vector3(-1.78, 1.15, CABIN_BZ), Vector3(0.10, 2.32, 0.18))
	s.box(Vector3(-0.22, 1.15, CABIN_BZ), Vector3(0.10, 2.32, 0.18))
	s.box(Vector3(-1.00, 2.32, CABIN_BZ), Vector3(1.66, 0.12, 0.18))
	# Swung-open planked door leaf pivoting outward onto the aft balcony deck from hinge at x = -1.75!
	var door_yaw := deg_to_rad(-118.0)
	var door_b := Basis(Vector3.UP, door_yaw)
	var hinge_p := Vector3(-1.74, 0.0, CABIN_BZ + 0.06)
	var door_w := 1.44
	var door_h := 2.24
	var leaf_c := hinge_p + door_b * Vector3(door_w * 0.5, door_h * 0.5, 0.0)
	s.colour = _lin(CEDAR_HONEY.lerp(CEDAR_WARM, 0.45))
	s.box(leaf_c, Vector3(door_w, door_h, 0.055), door_b)
	s.colour = _lin(CEDAR_DARK)
	# Z-brace ledgers on the door face.
	for dy: float in [0.36, 1.88]:
		s.box(hinge_p + door_b * Vector3(door_w * 0.5, dy, 0.042), Vector3(door_w - 0.14, 0.12, 0.032), door_b)
	Shapes.beam(s, hinge_p + door_b * Vector3(0.14, 0.42, 0.045),
			hinge_p + door_b * Vector3(door_w - 0.14, 1.82, 0.045), Vector2(0.04, 0.11))
	s.surface(iron_m)
	s.colour = _lin(IRON_DARK)
	for hy: float in [0.45, 1.80]:
		s.box(hinge_p + door_b * Vector3(0.24, hy, -0.034), Vector3(0.46, 0.06, 0.018), door_b)

	# 2. Aft-port cozy naturalist's cedar bookshelf cabinet (x = -3.82..-2.18, z = 3.74..4.08)!
	var sx0 := -3.82
	var sx1 := -2.18
	var sxm := (sx0 + sx1) * 0.5
	var sw := sx1 - sx0
	var sz := 3.92
	s.surface(wood_m)
	s.colour = _lin(CEDAR_WEATHERED)
	s.box(Vector3(sx0, 0.96, sz), Vector3(0.06, 1.92, 0.34), Basis(), [RoomMesh.DOWN])
	s.box(Vector3(sx1, 0.96, sz), Vector3(0.06, 1.92, 0.34), Basis(), [RoomMesh.DOWN])
	s.colour = _lin(CEDAR_HONEY)
	for sy: float in [0.10, 0.60, 1.08, 1.54, 1.92]:
		s.box(Vector3(sxm, sy, sz), Vector3(sw, 0.045, 0.34))
	_solid(c, Vector3(sxm, 0.96, sz), Vector3(sw, 1.92, 0.36))
	# Rows of colorful nature journals & glass specimen jars on the shelves!
	var book_cols: Array[Color] = [PILLOW_MOSS, PILLOW_BERRY, PILLOW_OCHRE, CEDAR_DARK, BISCUIT_TEAL, CANVAS_WEATHERED]
	u.surface(cloth_soft)
	for row_y: float in [0.625, 1.105, 1.565]:
		var bx := sx0 + 0.12
		while bx < sx1 - 0.52:
			var bw := rng.randf_range(0.042, 0.068)
			var bh := rng.randf_range(0.22, 0.31)
			u.colour = _lin(book_cols[rng.randi() % book_cols.size()])
			u.box(Vector3(bx + bw * 0.5, row_y + bh * 0.5, sz - 0.02), Vector3(bw - 0.004, bh, 0.22))
			bx += bw
	# Glass specimen jars & brass compass on the right side of the shelf.
	for jy: float in [0.625, 1.105]:
		var jp := Vector3(sx1 - 0.28, jy, sz - 0.02)
		glass.surface(c.mat("tin"))
		Shapes.cylinder(glass, jp, 0.055, 0.16, 10)
		u.surface(brass_m)
		u.colour = _lin(BRASS_AGED)
		Shapes.cylinder(u, jp + Vector3(0, 0.155, 0), 0.058, 0.024, 10)

	# 3. Aft-starboard hinged open cedar TRAPDOOR HATCH & descending WOODEN-RUNG ROPE LADDER!
	var hx_m := (HATCH_X0 + HATCH_X1) * 0.5
	var hz_m := (HATCH_Z0 + HATCH_Z1) * 0.5
	var hw := HATCH_X1 - HATCH_X0
	var hd := HATCH_Z1 - HATCH_Z0
	# Coaming frame around the floor hatch opening & dark timber-lined shaft collar extending down.
	s.surface(wood_m)
	s.colour = _lin(CEDAR_DARK)
	s.box(Vector3(hx_m, 0.03, HATCH_Z0 - 0.04), Vector3(hw + 0.16, 0.07, 0.08))
	s.box(Vector3(hx_m, 0.03, HATCH_Z1 + 0.04), Vector3(hw + 0.16, 0.07, 0.08))
	s.box(Vector3(HATCH_X0 - 0.04, 0.03, hz_m), Vector3(0.08, 0.07, hd))
	s.box(Vector3(HATCH_X1 + 0.04, 0.03, hz_m), Vector3(0.08, 0.07, hd))
	# Shaft side-lining descending below deck joists (y = -0.30..0.0).
	s.box(Vector3(hx_m, -0.16, HATCH_Z0 - 0.02), Vector3(hw + 0.04, 0.30, 0.04))
	s.box(Vector3(hx_m, -0.16, HATCH_Z1 + 0.02), Vector3(hw + 0.04, 0.30, 0.04))
	s.box(Vector3(HATCH_X0 - 0.02, -0.16, hz_m), Vector3(0.04, 0.30, hd))
	s.box(Vector3(HATCH_X1 + 0.02, -0.16, hz_m), Vector3(0.04, 0.30, hd))

	# Hinged trapdoor lid propped open at 78 deg along its STARBOARD edge (x = HATCH_X1), swinging open toward the trunk
	# so looking aft clearly reveals the dark open floor hatch shaft & descending wooden-rung rope ladder!
	var open_ang := deg_to_rad(-78.0)
	var lid_b := Basis(Vector3.BACK, open_ang)
	var lid_hinge := Vector3(HATCH_X1, 0.04, hz_m)
	var lid_c := lid_hinge + lid_b * Vector3(-hw * 0.5, 0.025, 0.0)
	s.colour = _lin(CEDAR_HONEY.lerp(CEDAR_WARM, 0.4))
	s.box(lid_c, Vector3(hw - 0.02, 0.052, hd - 0.02), lid_b)
	s.colour = _lin(CEDAR_DARK)
	for bx_l: float in [-hw * 0.28, -hw * 0.72]:
		s.box(lid_hinge + lid_b * Vector3(bx_l, -0.018, 0.0), Vector3(0.09, 0.038, hd - 0.14), lid_b)
	# Black iron strap hinges & gleaming brass ring pull on the open trapdoor!
	s.surface(iron_m)
	s.colour = _lin(IRON_DARK)
	for sz_h: float in [-0.30, 0.30]:
		s.box(lid_hinge + lid_b * Vector3(-0.18, 0.056, sz_h), Vector3(0.36, 0.016, 0.055), lid_b)
	u.surface(brass_m)
	u.colour = _lin(BRASS_WARM)
	Shapes.arch(u, lid_hinge + lid_b * Vector3(-hw + 0.16, 0.068, 0.0), 0.032, 0.046, 0.014, 12,
			lid_b * Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU)

	# Framed vintage nocturnal star-map & compass chart hanging on the aft cedar wall above the trapdoor + doorway mat!
	s.surface(wood_m)
	s.colour = _lin(CEDAR_DARK)
	s.box(Vector3(1.18, 1.88, CABIN_BZ - 0.08), Vector3(0.92, 0.68, 0.04))
	u.surface(cloth_soft)
	u.colour = _lin(Color(0.11, 0.16, 0.24))
	u.box(Vector3(1.18, 1.88, CABIN_BZ - 0.105), Vector3(0.80, 0.56, 0.014))
	# Delicate gleaming brass celestial ring & compass-rose needle inlaid on the star chart!
	u.surface(brass_m)
	u.colour = _lin(BRASS_WARM)
	Shapes.arch(u, Vector3(1.18, 1.88, CABIN_BZ - 0.114), 0.18, 0.20, 0.008, 16, Basis(), 0.0, TAU)
	u.box(Vector3(1.18, 1.88, CABIN_BZ - 0.116), Vector3(0.46, 0.018, 0.008))
	u.box(Vector3(1.18, 1.88, CABIN_BZ - 0.116), Vector3(0.018, 0.44, 0.008))
	u.box(Vector3(1.18, 1.88, CABIN_BZ - 0.116), Vector3(0.28, 0.014, 0.008), Basis(Vector3.BACK, PI * 0.25))
	u.box(Vector3(1.18, 1.88, CABIN_BZ - 0.116), Vector3(0.28, 0.014, 0.008), Basis(Vector3.BACK, -PI * 0.25))
	# Cozy woven doormat inside the open balcony doorway.
	u.surface(cloth_soft)
	u.colour = _lin(ROPE_HEMP * 0.86)
	u.box(Vector3(-1.00, 0.010, CABIN_BZ - 0.42), Vector3(1.18, 0.018, 0.54))
	# Gleaming round brass wall barometer beside the map.
	u.surface(brass_m)
	u.colour = _lin(BRASS_WARM)
	Shapes.cylinder(u, Vector3(0.32, 1.82, CABIN_BZ - 0.08), 0.13, 0.04, 14, Basis(Vector3.RIGHT, PI * 0.5))
	u.surface(cloth_soft)
	u.colour = _lin(PAPER_CREAM)
	Shapes.cylinder(u, Vector3(0.32, 1.82, CABIN_BZ - 0.115), 0.105, 0.012, 14, Basis(Vector3.RIGHT, PI * 0.5))

	# Wooden-rung rope ladder anchored to the forward coaming edge & descending 5.2 m down into the misty oak boughs!
	var lad_z := HATCH_Z0 + 0.14
	u.surface(cloth_soft)
	u.colour = _lin(ROPE_HEMP)
	for side: float in [-1.0, 1.0]:
		var rx := hx_m + side * 0.24
		Shapes.beam(u, Vector3(rx, 0.05, lad_z), Vector3(rx, -5.2, lad_z + 0.25), Vector2(0.028, 0.028))
	s.surface(wood_m)
	s.colour = _lin(CEDAR_HONEY)
	for r in 14:
		var frac := float(r) / 13.0
		var ry := -0.18 - float(r) * 0.35
		var rz := lerpf(lad_z, lad_z + 0.25, frac)
		Shapes.cylinder(s, Vector3(hx_m - 0.29, ry, rz), 0.024, 0.58, 8, Basis(Vector3.BACK, -PI * 0.5))


static func _rope_suspension_bridge(c: Object, rng: RandomNumberGenerator) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var wood_m: Material = c.tinted("wood")
	var cloth_soft: Material = c.soft("cloth", true)
	var brass_m: Material = c.shiny("gilt", 1.0, 0.72, 0.18)
	var shade_m: Material = c.shade(LANTERN_AMBER)

	# Bridge curves gently aft-and-left from the open aft balcony (-1.0, 0.0, 5.65) to a distant mossy oak platform!
	var p_start := Vector3(-1.00, 0.0, DECK_BZ)
	var p_end := Vector3(-4.85, 0.32, 23.60)
	var bw := 1.18
	const SLATS := 34

	var bridge_pt := func(t: float) -> Vector3:
		var x := lerpf(p_start.x, p_end.x, t) - sin(t * PI) * 1.15
		var z := lerpf(p_start.z, p_end.z, t)
		var y := lerpf(p_start.y, p_end.y, t) - sin(t * PI) * 0.72
		return Vector3(x, y, z)

	var bridge_side := func(t: float) -> Vector3:
		var a: Vector3 = bridge_pt.call(maxf(t - 0.02, 0.0))
		var b: Vector3 = bridge_pt.call(minf(t + 0.02, 1.0))
		var fwd := (b - a).normalized()
		return fwd.cross(Vector3.UP).normalized()

	# Heavy carved cedar bridge anchor posts at BOTH ends!
	s.surface(wood_m)
	for end_t: float in [0.0, 1.0]:
		var ep: Vector3 = bridge_pt.call(end_t)
		var sv: Vector3 = bridge_side.call(end_t)
		for side: float in [-1.0, 1.0]:
			var pp := ep + sv * (side * (bw * 0.5 + 0.12))
			s.colour = _lin(CEDAR_DARK)
			s.box(pp + Vector3(0, 0.65, 0), Vector3(0.16, 1.55, 0.16))
			s.colour = _lin(CEDAR_WARM)
			s.box(pp + Vector3(0, 1.46, 0), Vector3(0.20, 0.08, 0.20))

	# Distant neighbouring oak wooden landing deck where the bridge terminates!
	s.colour = _lin(CEDAR_DECK)
	s.box(p_end + Vector3(-0.35, -0.06, 1.15), Vector3(3.2, 0.12, 2.5))
	s.colour = _lin(CEDAR_DARK)
	Shapes.beam(s, p_end + Vector3(-1.6, -0.10, 0.4), p_end + Vector3(-0.4, -2.2, 1.4), Vector2(0.18, 0.18))
	Shapes.beam(s, p_end + Vector3(0.9, -0.10, 0.4), p_end + Vector3(-0.3, -2.2, 1.4), Vector2(0.18, 0.18))

	# 34 weathered wooden walkway slats following the graceful curving catenary arc!
	for i in SLATS:
		var t := (float(i) + 0.5) / float(SLATS)
		var pt: Vector3 = bridge_pt.call(t)
		var sv: Vector3 = bridge_side.call(t)
		var fwd := Vector3.UP.cross(sv).normalized()
		var slat_b := Basis(sv, Vector3.UP, fwd) * Basis(Vector3.BACK, rng.randf_range(-0.025, 0.025))
		s.colour = _lin(CEDAR_DECK.lerp(CEDAR_WARM, rng.randf() * 0.5) * rng.randf_range(0.84, 1.12))
		s.box(pt, Vector3(bw + rng.randf_range(-0.04, 0.04), 0.048, 0.34), slat_b)

	# Twin thick braided hemp deck cables, upper handrail ropes & vertical dropper ties!
	u.surface(cloth_soft)
	u.colour = _lin(ROPE_HEMP)
	const SEGS := 18
	for side: float in [-1.0, 1.0]:
		var prev_bot := Vector3.ZERO
		var prev_top := Vector3.ZERO
		var prev_mid := Vector3.ZERO
		for k in SEGS + 1:
			var t := float(k) / float(SEGS)
			var pt: Vector3 = bridge_pt.call(t)
			var sv: Vector3 = bridge_side.call(t)
			var rail_h := 1.06 - sin(t * PI) * 0.14
			var pb := pt + sv * (side * (bw * 0.5 + 0.04)) + Vector3(0, -0.02, 0)
			var pm := pt + sv * (side * (bw * 0.5 + 0.07)) + Vector3(0, rail_h * 0.50, 0)
			var pt_hi := pt + sv * (side * (bw * 0.5 + 0.10)) + Vector3(0, rail_h, 0)
			if k > 0:
				Shapes.beam(u, prev_bot, pb, Vector2(0.042, 0.042))
				Shapes.beam(u, prev_mid, pm, Vector2(0.022, 0.022))
				Shapes.beam(u, prev_top, pt_hi, Vector2(0.036, 0.036))
			if k > 0 and k < SEGS:
				Shapes.beam(u, pb, pt_hi, Vector2(0.018, 0.018))
			prev_bot = pb
			prev_mid = pm
			prev_top = pt_hi

	# Warm beckoning brass post lanterns seated DEAD-CENTER on top of the carved anchor posts!
	var sv0: Vector3 = bridge_side.call(0.0)
	var sv1: Vector3 = bridge_side.call(1.0)
	var post_lamps: Array[Vector3] = [
		p_start + sv0 * (-bw * 0.5 - 0.12) + Vector3(0.0, 1.62, 0.0),
		p_start + sv0 * (bw * 0.5 + 0.12) + Vector3(0.0, 1.62, 0.0),
		p_end + sv1 * (bw * 0.5 + 0.12) + Vector3(0.0, 1.62, 0.0),
	]
	for pl: Vector3 in post_lamps:
		u.surface(brass_m)
		u.colour = _lin(BRASS_AGED)
		# Solid turned brass pedestal neck anchored down into the wooden post cap at y = 1.50!
		Shapes.lathe(u, [Vector2(0.055, -0.14), Vector2(0.032, -0.11), Vector2(0.078, -0.085)], pl, 8)
		Shapes.lathe(u, [Vector2(0.11, 0.09), Vector2(0.05, 0.15), Vector2(0.0, 0.18)], pl, 8)
		lit.surface(shade_m)
		lit.colour = Color.WHITE
		Shapes.cylinder(lit, pl + Vector3(0, -0.08, 0), 0.055, 0.17, 8)


static func _fairy_lanterns_and_lamps(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove
	var iron_m: Material = c.tinted("iron")
	var brass_m: Material = c.shiny("gilt", 1.0, 0.72, 0.18)
	var shade_m: Material = c.shade(LANTERN_AMBER)
	cove.surface(c.kit.cove_material())

	# 1. Four interior rafter festoon garlands (hugging the pitched roof profile cleanly above y >= 3.45 m across the
	#    centre corridor so ZERO lantern ever crosses a screen sightline, while bathing the rafters in warm magic!).
	var interior_zs: Array[float] = [-4.45, -1.85, 0.75, 3.35]
	for gi in interior_zs.size():
		var gz := interior_zs[gi]
		var pts: Array[Vector3] = []
		const STEPS := 10
		for k in STEPS + 1:
			var f := float(k) / float(STEPS)
			var x := lerpf(-CABIN_HW + 0.22, CABIN_HW - 0.22, f)
			# Scalloped double-swag arch following the pitched ceiling!
			var ceil_y := _roof_y(x) - 0.22
			var swag := 0.22 * absf(sin(f * PI * 2.0))
			pts.append(Vector3(x, ceil_y - swag, gz))
		s.surface(iron_m)
		s.colour = _lin(IRON_DARK)
		for k in STEPS:
			Shapes.beam(s, pts[k], pts[k + 1], Vector2(0.012, 0.012))
		# 7 warm glowing paper & brass fairy lanterns along each rafter garland!
		for k: int in [1, 2, 3, 5, 7, 8, 9]:
			var lp := pts[k]
			var big: bool = (k == 5 or k == 2 or k == 8)
			_fairy_globe(u, cove, brass_m, lp + Vector3(0, -0.09, 0), 0.105 if big else 0.072)

	# 2. Three exterior overhanging eave fairy-lantern garlands (port, starboard, forward gable) glowing warmly against
	#    the dark misty forest & rain!
	# Port & starboard eave runs:
	for side: float in [-1.0, 1.0]:
		var ex := side * (EAVE_X - 0.18)
		var ey := _roof_y(EAVE_X - 0.18) - 0.08
		var e_pts: Array[Vector3] = []
		for k in 9:
			var f := float(k) / 8.0
			var ez := lerpf(-5.65, 4.45, f)
			var sag := 0.16 * absf(sin(f * PI * 4.0))
			e_pts.append(Vector3(ex, ey - sag, ez))
		s.surface(iron_m)
		s.colour = _lin(IRON_DARK)
		for k in 8:
			Shapes.beam(s, e_pts[k], e_pts[k + 1], Vector2(0.012, 0.012))
		for k in [1, 3, 5, 7]:
			_fairy_globe(u, cove, brass_m, e_pts[k] + Vector3(0, -0.08, 0), 0.082)

	# Forward gable eave garland framing the upper gable high above the cinema screen (y = 3.65..4.42)!
	var fg_pts: Array[Vector3] = []
	for k in 9:
		var f := float(k) / 8.0
		var fx := lerpf(-4.25, 4.25, f)
		var fy := _roof_y(fx) - 0.16 - 0.14 * absf(sin(f * PI * 2.0))
		fg_pts.append(Vector3(fx, fy, -6.28))
	s.surface(iron_m)
	s.colour = _lin(IRON_DARK)
	for k in 8:
		Shapes.beam(s, fg_pts[k], fg_pts[k + 1], Vector2(0.012, 0.012))
	for k in [1, 2, 4, 6, 7]:
		_fairy_globe(u, cove, brass_m, fg_pts[k] + Vector3(0, -0.08, 0), 0.090)

	# 3. Four hero hanging brass & wrought-iron cabin storm lanterns (PieceLamps + hidden bake lamps)!
	var storm_specs: Array = [
		# Front-port & front-starboard cabin beams framing the viewing area
		[Vector3(-3.35, 2.52, -4.45), Vector3(-3.35, _roof_y(3.35) - 0.06, -4.45), 1.05],
		[Vector3(3.35, 2.52, -4.45), Vector3(3.35, _roof_y(3.35) - 0.06, -4.45), 1.05],
		# Aft-port beside the bookshelf & aft balcony doorway
		[Vector3(-2.65, 2.58, 3.35), Vector3(-2.65, _roof_y(2.65) - 0.06, 3.35), 0.95],
		# Aft-starboard warming the open trapdoor & gnarled oak trunk
		[Vector3(2.55, 2.58, 2.85), Vector3(2.55, _roof_y(2.55) - 0.06, 2.85), 0.95],
		# Mid-port cozy reading glow over the windowsill spyglass & candles
		[Vector3(-3.45, 2.48, -0.80), Vector3(-3.45, _roof_y(3.45) - 0.06, -0.80), 0.85],
	]
	for sp: Array in storm_specs:
		var ctr: Vector3 = sp[0]
		var top: Vector3 = sp[1]
		var strength: float = float(sp[2])
		s.surface(iron_m)
		s.colour = _lin(IRON_DARK)
		Shapes.beam(s, top, ctr + Vector3(0, 0.19, 0), Vector2(0.016, 0.016))
		for k in 4:
			var a := float(k) * PI * 0.5 + PI * 0.25
			var off := Vector3(cos(a) * 0.10, 0.0, sin(a) * 0.10)
			Shapes.beam(s, ctr + off + Vector3(0, -0.10, 0), ctr + off + Vector3(0, 0.10, 0), Vector2(0.011, 0.011))
		u.surface(brass_m)
		u.colour = _lin(BRASS_WARM)
		Shapes.lathe(u, [Vector2(0.018, 0.20), Vector2(0.065, 0.16), Vector2(0.15, 0.10), Vector2(0.12, 0.08)], ctr, 8)
		Shapes.lathe(u, [Vector2(0.018, -0.17), Vector2(0.11, -0.12), Vector2(0.12, -0.09)], ctr, 8)
		lit.surface(shade_m)
		lit.colour = Color.WHITE
		Shapes.lathe(lit, [Vector2(0.048, -0.09), Vector2(0.082, -0.04), Vector2(0.086, 0.04), Vector2(0.056, 0.09)],
				ctr, 8)
		c.lamps.append([ctr, LANTERN_AMBER, strength])

	# Two live-tinted cove footlights under the pitched rafters so changing `lanterns` (amber / forest_gold / dim)
	# shifts the warm glow cast across the honey-cedar rafters, rug and mossy oak trunk in real time!
	c.footlights.append([Vector3(0.0, 3.65, -1.85), -1.0, 0.72])
	c.footlights.append([Vector3(0.0, 3.65, 1.45), -1.0, 0.65])


## One glowing pleated paper & brass fairy lantern globe (PieceCove, live-bound to setting.lanterns).
static func _fairy_globe(u: RoomMesh, cove: RoomMesh, brass_m: Material, ctr: Vector3, rad: float) -> void:
	u.surface(brass_m)
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [Vector2(rad * 0.22, rad * 1.18), Vector2(rad * 0.56, rad * 0.88), Vector2(rad * 0.44, rad * 0.82)],
			ctr, 8)
	Shapes.lathe(u, [Vector2(rad * 0.16, -rad * 1.06), Vector2(rad * 0.44, -rad * 0.84)], ctr, 8)
	cove.colour = _lin(PAPER_CREAM, 0.96)
	Shapes.lathe(cove, [
		Vector2(rad * 0.42, -rad * 0.85),
		Vector2(rad * 0.90, -rad * 0.45),
		Vector2(rad * 1.02, 0.0),
		Vector2(rad * 0.90, rad * 0.48),
		Vector2(rad * 0.44, rad * 0.85),
	], ctr, 8)


# --- Piece 2: Ancient gnarled mossy host oak + surrounding dark misty woodland ----------------------------------------

static func _build_oak_and_woodland(c: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4219

	_ancient_host_oak(c, rng)
	_neighbouring_misty_woodland(c, rng)


static func _ancient_host_oak(c: Object, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	var bark_m: Material = c.soft("wood", true)
	var leaf_m: Material = c.soft("leaves", true)

	# 1. Monumental fluted gnarled oak trunk passing straight through the aft-starboard corner (3.95, y, 2.35),
	#    plunging down 15 m into the mossy forest depths and soaring 14.5 m up into the twilight canopy!
	u.surface(bark_m)
	const RINGS := 16
	const SEGS := 14
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for ri in RINGS + 1:
		var v := float(ri) / float(RINGS)
		var y := lerpf(-15.0, 14.5, v)
		# Natural gentle trunk twist and slight lean around the cabin.
		var cx := TRUNK_X + 0.34 * sin(v * PI * 1.35 + 0.4) - 0.55 * smoothstep(0.65, 1.0, v)
		var cz := TRUNK_Z + 0.28 * cos(v * PI * 1.15 - 0.3) - 0.45 * smoothstep(0.68, 1.0, v)
		# Flaring buttress roots near forest floor, sturdy 1.02 m trunk through the deck, tapering high in the crown.
		var root_flare := 1.45 * pow(maxf(1.0 - v * 2.8, 0.0), 1.8)
		var r_base := lerpf(1.22, 0.48, pow(v, 0.85)) + root_flare
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for si in SEGS + 1:
			var ang := TAU * float(si % SEGS) / float(SEGS)
			var twist := ang + v * 1.35
			var flute := 1.0 + (0.14 + 0.16 * maxf(1.0 - v * 2.2, 0.0)) * cos(twist * 5.0) + 0.06 * sin(twist * 8.0 + 1.1)
			var r := r_base * flute
			var radial := Vector3(cos(ang), 0.0, sin(ang))
			row.append(Vector3(cx + radial.x * r, y, cz + radial.z * r))
			nrow.append(radial)
			# Mossy velvet green tinting along the damp north/west bark ridges and upper boughs!
			var moss := clampf(0.45 + 0.40 * sin(ang - 0.6) + 0.20 * cos(v * 9.0), 0.0, 1.0)
			var col := BARK_DEEP.lerp(BARK_WARM, 0.42 + 0.30 * sin(twist * 5.0))
			col = col.lerp(BARK_MOSS, moss * 0.48)
			crow.append(_lin(col))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	u.grid(rows, norms, cols)
	# Trunk physics box strictly at (3.95, y, 2.35) (distance ~4.6 m from origin!).
	_solid(c, Vector3(TRUNK_X, 2.2, TRUNK_Z), Vector3(1.85, 7.5, 1.85))

	# Sculptural gnarled oak root buttresses anchored smoothly into the cedar deck + upper limbs passing cleanly up
	# through the pitched corrugated-tin roof slope (zero cut stumps floating inside the cabin!).
	var corner_roots: Array = [
		[[Vector3(3.75, 0.92, 2.08), Vector3(3.22, 0.34, 1.82), Vector3(2.92, -0.06, 1.72)], 0.34, 0.18],
		[[Vector3(3.70, 0.84, 2.66), Vector3(3.16, 0.28, 3.04), Vector3(2.86, -0.06, 3.22)], 0.32, 0.17],
		[[Vector3(3.80, 2.30, 2.12), Vector3(3.22, 2.98, 1.62), Vector3(2.45, _roof_y(2.45) + 0.16, 1.05)], 0.30, 0.18],
		[[Vector3(3.72, 2.40, 2.55), Vector3(3.05, 3.08, 2.95), Vector3(2.25, _roof_y(2.25) + 0.18, 3.45)], 0.28, 0.17],
	]
	for cr_b: Array in corner_roots:
		var cpts: Array[Vector3] = []
		for p: Vector3 in cr_b[0]:
			cpts.append(p)
		_branch_tube(u, cpts, float(cr_b[1]), float(cr_b[2]), 6)

	# 2. Massive twisting oak limbs: under-deck cradle boughs, flanking screen boughs, and soaring overhead crown boughs!
	#    Each entry: [points_array, r_start, r_end, foliage_at_tips]
	var boughs: Array = [
		# --- Under-deck cradle boughs holding the treehouse securely 14 m aloft (strictly below deck y <= -0.45!) ---
		[[Vector3(3.6, -2.5, 2.1), Vector3(1.4, -1.25, 0.4), Vector3(-1.8, -0.85, -1.2), Vector3(-5.2, -0.85, -2.4),
				Vector3(-7.8, 0.55, -3.5)], 0.56, 0.18, false],
		[[Vector3(3.7, -2.1, 1.8), Vector3(2.8, -1.05, -1.6), Vector3(2.8, -0.95, -5.2), Vector3(3.8, -0.45, -6.7),
				Vector3(5.2, 2.45, -8.8)], 0.52, 0.16, false],
		[[Vector3(3.5, -2.6, 2.6), Vector3(0.4, -1.35, 3.6), Vector3(-3.2, -0.95, 4.4), Vector3(-6.8, -0.25, 5.2),
				Vector3(-9.2, 1.45, 6.2)], 0.48, 0.15, false],
		# --- Left-side companion oak bough rising gracefully outside the port windows & cradling front-port corner! ---
		[[Vector3(-4.4, -1.3, -2.1), Vector3(-5.85, 0.35, -3.2), Vector3(-6.15, 2.25, -4.4), Vector3(-5.55, 4.15, -5.8),
				Vector3(-3.95, 5.45, -7.1), Vector3(-1.45, 6.45, -8.2)], 0.46, 0.14, true],
		[[Vector3(-6.05, 1.55, -3.6), Vector3(-7.8, 2.55, -2.0), Vector3(-9.8, 3.35, -0.2), Vector3(-11.4, 4.15, 1.6)],
				0.34, 0.10, true],
		[[Vector3(-6.05, 2.15, -4.2), Vector3(-8.2, 3.05, -6.2), Vector3(-10.5, 4.35, -8.0)], 0.30, 0.10, true],
		# --- Forward-starboard hero bough rising beside the starboard window & framing the right side of the screen! ---
		[[Vector3(4.1, 2.2, 1.9), Vector3(5.95, 2.95, -0.4), Vector3(6.15, 3.75, -3.2), Vector3(5.35, 4.55, -6.0),
				Vector3(3.55, 5.35, -7.7), Vector3(0.95, 6.35, -9.0)], 0.48, 0.14, true],
		[[Vector3(6.05, 3.05, -1.2), Vector3(8.0, 3.85, -2.5), Vector3(10.5, 4.55, -3.8)], 0.32, 0.10, true],
		# --- Six monumental overarching upper crown limbs soaring above the corrugated-tin roof ridge (y = 5.4..12.2)! ---
		[[Vector3(3.8, 4.8, 2.2), Vector3(1.5, 5.95, 0.6), Vector3(-1.8, 6.65, -1.2), Vector3(-6.2, 6.95, -2.6),
				Vector3(-9.8, 7.15, -3.5)], 0.50, 0.14, true],
		[[Vector3(3.8, 5.4, 2.0), Vector3(1.2, 6.65, -1.4), Vector3(-1.4, 7.55, -4.8), Vector3(-4.2, 8.15, -8.2),
				Vector3(-6.8, 8.35, -10.8)], 0.46, 0.12, true],
		[[Vector3(3.9, 5.8, 2.5), Vector3(1.8, 6.85, 4.8), Vector3(-1.2, 7.45, 7.4), Vector3(-4.6, 7.85, 9.6)],
				0.44, 0.12, true],
		[[Vector3(4.0, 5.2, 2.4), Vector3(6.6, 6.05, 3.2), Vector3(9.4, 6.75, 4.8), Vector3(11.8, 7.25, 6.4)],
				0.42, 0.12, true],
		[[Vector3(3.9, 6.6, 2.1), Vector3(5.8, 8.15, -0.6), Vector3(8.2, 9.45, -3.6), Vector3(10.5, 10.25, -6.4)],
				0.40, 0.11, true],
		[[Vector3(3.6, 8.4, 1.9), Vector3(0.4, 10.2, 0.2), Vector3(-3.6, 11.4, -1.8), Vector3(-7.4, 11.8, -3.4)],
				0.38, 0.10, true],
		[[Vector3(3.5, 9.8, 2.1), Vector3(3.2, 12.2, 4.8), Vector3(2.4, 13.4, 8.2)], 0.34, 0.10, true],
	]

	var canopy_tips: Array = []
	for bg: Array in boughs:
		var pts_raw: Array = bg[0]
		var pts: Array[Vector3] = []
		for p: Vector3 in pts_raw:
			pts.append(p)
		var r0: float = float(bg[1])
		var r1: float = float(bg[2])
		u.surface(bark_m)
		_branch_tube(u, pts, r0, r1, 7)

		# Forking secondary twigs & canopy anchor points strictly outside the dry cabin & eaves!
		if bool(bg[3]):
			for pi in range(1, pts.size()):
				var frac := float(pi) / float(pts.size() - 1)
				var pt := pts[pi]
				if _inside_cabin_or_sight(pt, 1.75):
					continue
				canopy_tips.append([pt, lerpf(1.45, 2.35, frac)])
				if pi < pts.size() - 1:
					var seg_dir := (pts[pi + 1] - pts[pi - 1]).normalized()
					var perp := seg_dir.cross(Vector3.UP)
					if perp.length() < 0.05:
						perp = Vector3.RIGHT
					perp = perp.normalized()
					var sgn := 1.0 if (pi % 2 == 0) else -1.0
					var fork_tip := pt + perp * (sgn * rng.randf_range(1.6, 2.8)) + Vector3(0, rng.randf_range(0.4, 1.3), 0)
					if not _inside_cabin_or_sight(fork_tip, 1.85):
						u.surface(bark_m)
						_branch_tube(u, [pt, pt.lerp(fork_tip, 0.5) + Vector3(0, 0.25, 0), fork_tip],
								lerpf(r0, r1, frac) * 0.65, 0.06, 5)
						canopy_tips.append([fork_tip, rng.randf_range(1.50, 2.25)])
		else:
			# Outer foliage strictly at the far tips of the under-deck cradle boughs!
			var tip := pts[pts.size() - 1]
			if not _inside_cabin_or_sight(tip, 2.0):
				canopy_tips.append([tip, 1.85])

	# 3. Lush billowing multi-lobe mossy-green oak canopy clusters clothing the host oak boughs!
	u.surface(leaf_m)
	for ct: Array in canopy_tips:
		var cp: Vector3 = ct[0]
		var rad: float = float(ct[1])
		_oak_leaf_cluster(u, cp, rad, rng, 0.0)

	# 4. Close-up organic oak bough foliage framing EVERY wide-open propped window (strictly >= 2.2 m outside cabin walls
	#    so ZERO leaf ever touches the cabin walls, floor, or rafters, while filling every window view with living forest!).
	var window_foliage: Array = [
		[Vector3(-7.45, 2.35, -3.80), 1.35],
		[Vector3(-7.65, 1.55, -1.65), 1.25],
		[Vector3(-7.50, 2.65, 1.05), 1.40],
		[Vector3(-7.35, 1.75, 2.85), 1.30],
		[Vector3(7.45, 2.25, -3.55), 1.35],
		[Vector3(7.55, 1.75, -0.55), 1.30],
		[Vector3(-5.15, 2.85, -8.55), 1.45],
		[Vector3(5.15, 2.95, -8.45), 1.45],
		[Vector3(-8.4, 0.65, -5.8), 1.55],
		[Vector3(8.4, 0.75, -5.6), 1.55],
	]
	for wf: Array in window_foliage:
		_oak_leaf_cluster(u, wf[0], float(wf[1]), rng, 0.05)


static func _neighbouring_misty_woodland(c: Object, rng: RandomNumberGenerator) -> void:
	var u: RoomMesh = c.u
	var bark_m: Material = c.soft("wood", true)
	var leaf_m: Material = c.soft("leaves", true)

	# 21 tall neighbouring ancient oak & cedar trunks (11..38 m out) encircling 360 deg around the treehouse,
	# framing every wide-open window and cradling the curving wooden-slat rope suspension bridge!
	# [x, z, trunk_r, top_y, crown_r, is_cedar]
	var trees: Array = [
		# Destination oak supporting the far end of the rope suspension bridge + close bridge-flanking oaks!
		[-5.25, 25.0, 1.05, 19.5, 5.8, false],
		[-10.2, 13.5, 0.84, 18.5, 4.8, false],
		[3.2, 14.8, 0.86, 19.2, 5.0, true],
		# Forward misty woodland right outside the wide-open front flank shutters (12..34 m)
		[-10.8, -12.8, 0.86, 19.5, 5.2, false],
		[-3.8, -16.8, 0.82, 21.5, 5.0, true],
		[4.8, -15.2, 0.88, 20.0, 5.4, false],
		[11.8, -12.2, 0.82, 20.5, 5.0, true],
		# Port side misty woodland right outside the wide-open port shutter awnings (11..28 m)
		[-12.2, -5.2, 0.90, 19.0, 5.4, false],
		[-12.6, 2.2, 0.88, 20.2, 5.2, false],
		[-14.5, 9.2, 0.86, 20.5, 5.4, true],
		[-22.5, -9.5, 1.02, 23.5, 6.4, true],
		[-21.5, 4.5, 0.96, 22.5, 6.2, false],
		# Starboard misty woodland beyond the host oak (12..28 m)
		[12.8, -4.6, 0.88, 19.6, 5.2, false],
		[13.4, 3.8, 0.90, 20.8, 5.4, true],
		[14.5, 12.0, 0.86, 21.0, 5.2, false],
		[23.5, -7.2, 1.04, 24.0, 6.6, true],
		# Aft & far twilight forest depth completing a seamless 360 deg forest canopy skyline!
		[7.8, 22.5, 0.92, 21.5, 5.8, false],
		[-15.8, 23.5, 0.96, 22.5, 6.2, true],
		[0.5, -29.5, 1.12, 25.5, 7.0, true],
		[-13.5, -28.0, 1.08, 25.0, 6.8, false],
		[14.8, -27.0, 1.06, 24.5, 6.8, true],
	]

	for tr: Array in trees:
		var tx: float = float(tr[0])
		var tz: float = float(tr[1])
		var rad: float = float(tr[2])
		var top_y: float = float(tr[3])
		var cr: float = float(tr[4])
		var cedar: bool = bool(tr[5])
		var dist := Vector2(tx, tz).length()
		var depth_mix := clampf((dist - 10.0) / 26.0, 0.0, 1.0)

		# Tapered tall trunk rising from deep forest floor (-15.0 m) up into the twilight canopy.
		u.surface(bark_m)
		var bcol := BARK_DEEP.lerp(Color(0.08, 0.12, 0.14), depth_mix * 0.72)
		u.colour = _lin(bcol)
		Shapes.lathe(u, [
			Vector2(rad * 1.48, -15.0),
			Vector2(rad * 1.12, -5.0),
			Vector2(rad * 0.95, 2.0),
			Vector2(rad * 0.72, top_y * 0.55),
			Vector2(rad * 0.32, top_y * 0.88),
			Vector2(0.08, top_y),
		], Vector3(tx, 0.0, tz), 6)

		# 4 sweeping silhouette boughs + lush multi-tiered billowing canopy clouds (low & mid tiers visible through windows!)
		for bi in 4:
			var ang := TAU * float(bi) / 4.0 + rng.randf_range(-0.32, 0.32)
			var by := lerpf(1.6, top_y * 0.72, float(bi) / 3.0)
			var reach := cr * rng.randf_range(0.55, 0.92)
			var b_end := Vector3(tx + cos(ang) * reach, by + (rng.randf_range(-0.5, 0.5) if cedar else rng.randf_range(0.8, 2.0)),
					tz + sin(ang) * reach)
			u.surface(bark_m)
			u.colour = _lin(bcol)
			Shapes.beam(u, Vector3(tx, by, tz), b_end, Vector2(rad * 0.32, rad * 0.32))
			u.surface(leaf_m)
			_canopy_lobe(u, b_end, cr * (0.40 if cedar else 0.48), rng, depth_mix)
			_canopy_lobe(u, b_end + Vector3(cos(ang + 1.1) * cr * 0.22, -0.35, sin(ang + 1.1) * cr * 0.22),
					cr * 0.32, rng, depth_mix)

		# Broad billowing upper crown cap silhouette against the starry twilight sky.
		u.surface(leaf_m)
		_canopy_lobe(u, Vector3(tx, top_y - 1.4, tz), cr * 0.60, rng, depth_mix)

	# Deep shadowed forest canopy carpet & misty rolling woodland treetop mounds far below (y = -11.5..-14.5 m)!
	u.surface(leaf_m)
	for mi in 14:
		var ma := TAU * float(mi) / 14.0 + rng.randf_range(-0.18, 0.18)
		var md := rng.randf_range(10.0, 32.0)
		_canopy_lobe(u, Vector3(cos(ma) * md, -11.2 + rng.randf_range(-1.2, 1.8), sin(ma) * md),
				rng.randf_range(4.2, 6.8), rng, 0.65)
	u.colour = _lin(FOREST_FLOOR)
	var floor_poly := PackedVector3Array()
	for k in 20:
		var a := TAU * float(k) / 20.0
		floor_poly.append(Vector3(cos(a) * 76.0, -14.5, sin(a) * 76.0))
	u.polygon(floor_poly, Vector3.UP)


## True if `p` falls inside or within `pad` metres of the dry cabin shell or screen viewing corridor.
static func _inside_cabin_or_sight(p: Vector3, pad := 1.65) -> bool:
	if absf(p.x) < CABIN_HW + pad and p.z > CABIN_FZ - pad and p.z < CABIN_BZ + pad and p.y > -1.90 and p.y < RIDGE_Y + 0.85:
		return true
	if absf(p.x) < 3.10 and p.z > -7.8 and p.z < 2.2 and p.y > 0.20 and p.y < 4.25:
		return true
	return false


## Smoothly tapered organic 3D branch tube along a polyline `pts` (zero gaps or hard miter corners).
static func _branch_tube(u: RoomMesh, pts: Array[Vector3], r_start: float, r_end: float, sides := 7) -> void:
	if pts.size() < 2:
		return
	var rings: Array = []
	var nrings: Array = []
	var crings: Array = []
	for i in pts.size():
		var f := float(i) / float(pts.size() - 1)
		var rad := lerpf(r_start, r_end, f)
		var tang: Vector3
		if i == 0:
			tang = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			tang = (pts[i] - pts[i - 1]).normalized()
		else:
			tang = (pts[i + 1] - pts[i - 1]).normalized()
		var ref := Vector3.UP if absf(tang.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
		var s1 := ref.cross(tang).normalized()
		var s2 := tang.cross(s1).normalized()
		var ring := PackedVector3Array()
		var nring := PackedVector3Array()
		var cring := PackedColorArray()
		for k in sides + 1:
			var a := TAU * float(k % sides) / float(sides)
			var nrm := (s1 * cos(a) + s2 * sin(a)).normalized()
			ring.append(pts[i] + nrm * rad)
			nring.append(nrm)
			# Mossy green tinting along the upper side of every oak limb!
			var moss := clampf(nrm.y * 0.75 + 0.25, 0.0, 1.0)
			cring.append(_lin(BARK_DEEP.lerp(BARK_WARM, 0.45).lerp(BARK_MOSS, moss * 0.55)))
		rings.append(ring)
		nrings.append(nring)
		crings.append(cring)
	u.grid(rings, nrings, crings)


## Sculpted irregular billowing organic canopy foliage dome (zero sparse geometric squares!).
static func _canopy_lobe(u: RoomMesh, ctr: Vector3, radius: float, rng: RandomNumberGenerator, depth_mix: float) -> void:
	const RINGS := 4
	const SEGS := 7
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for ri in RINGS + 1:
		var v := float(ri) / float(RINGS)
		var lat := lerpf(-PI * 0.44, PI * 0.46, v)
		var ring_r := cos(lat) * radius
		var y_off := sin(lat) * radius * 0.56
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for si in SEGS + 1:
			var a := TAU * float(si % SEGS) / float(SEGS)
			# Organic bumpy leafy silhouette modulation!
			var bump := 1.0 + 0.22 * sin(a * 3.0 + ph1 + v * 2.4) + 0.12 * cos(a * 5.0 + ph2)
			var rr := ring_r * bump
			var nrm := Vector3(cos(a) * cos(lat), sin(lat), sin(a) * cos(lat)).normalized()
			row.append(ctr + Vector3(cos(a) * rr, y_off * (0.92 + 0.14 * sin(a * 2.0 + ph2)), sin(a) * rr))
			nrow.append(nrm)
			var up_f := clampf(v, 0.0, 1.0)
			var col := LEAF_SHADOW.lerp(LEAF_MOSS, up_f * 0.82).lerp(LEAF_SAGE, smoothstep(0.58, 1.0, up_f) * 0.55)
			col = col.lerp(LEAF_DISTANT, depth_mix * 0.78) * (0.90 + 0.16 * sin(a * 3.0 + ph1))
			crow.append(_lin(col))
		rows.append(row)
		norms.append(nrow)
		cols.append(crow)
	u.grid(rows, norms, cols)


## Lush multi-lobe botanical oak foliage cluster: 3 overlapping organic leafy domes + ruffling edge leaf sprays!
static func _oak_leaf_cluster(u: RoomMesh, ctr: Vector3, radius: float, rng: RandomNumberGenerator,
		depth_mix: float) -> void:
	if _inside_cabin_or_sight(ctr, radius * 0.75 + 0.65):
		return
	_canopy_lobe(u, ctr, radius * 0.78, rng, depth_mix)
	for li in 2:
		var la := rng.randf() * TAU
		var sub := ctr + Vector3(cos(la) * radius * 0.52, rng.randf_range(-0.22, 0.34) * radius, sin(la) * radius * 0.52)
		if not _inside_cabin_or_sight(sub, radius * 0.55 + 0.55):
			_canopy_lobe(u, sub, radius * rng.randf_range(0.52, 0.66), rng, depth_mix)
	# Delicate outer oak leaf sprays ruffling the organic lobe silhouette!
	for i in 5:
		var ang := TAU * float(i) / 5.0 + rng.randf_range(-0.4, 0.4)
		var elev := rng.randf_range(-0.25, 0.55)
		var pos := ctr + Vector3(cos(ang) * cos(elev) * radius * 0.62, sin(elev) * radius * 0.42,
				sin(ang) * cos(elev) * radius * 0.62)
		var dir := Vector3(cos(ang), rng.randf_range(-0.18, 0.28), sin(ang)).normalized()
		var l_len := radius * rng.randf_range(0.42, 0.62)
		if _inside_cabin_or_sight(pos, 0.65) or _inside_cabin_or_sight(pos + dir * l_len, 0.65):
			continue
		var across := dir.cross(Vector3.UP)
		if across.length() < 0.05:
			across = Vector3.RIGHT
		across = across.normalized() * (l_len * 0.44)
		var nrm := dir.cross(across).normalized()
		var col := LEAF_SHADOW.lerp(LEAF_MOSS, clampf(elev + 0.45, 0.0, 1.0)).lerp(LEAF_DISTANT, depth_mix * 0.75)
		u.colour = _lin(col * rng.randf_range(0.88, 1.12))
		Shapes.leaf(u, pos, dir * l_len, across, nrm)


static func _fern_clump(u: RoomMesh, at: Vector3, scale: float, rng: RandomNumberGenerator) -> void:
	const FRONDS := 6
	for f in FRONDS:
		var a := TAU * float(f) / float(FRONDS) + rng.randf_range(-0.25, 0.25)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var side := dir.cross(Vector3.UP).normalized()
		var prev := at
		u.colour = _lin(LEAF_MOSS.lerp(LEAF_SAGE, rng.randf() * 0.55))
		for i in range(1, 5):
			var t := float(i) / 4.0
			var p := at + dir * (scale * t) + Vector3.UP * (scale * 0.48 * sin(t * PI * 0.82) - 0.14 * t * t)
			var along := (p - prev).normalized()
			var pinna := scale * 0.28 * sin(clampf(t, 0.1, 0.96) * PI)
			for sgn: float in [-1.0, 1.0]:
				var l_dir := (side * sgn + along * 0.36 + Vector3.DOWN * 0.14).normalized() * pinna
				var l_across := along * (pinna * 0.30)
				Shapes.leaf(u, p, l_dir, l_across, l_dir.cross(l_across).normalized())
			prev = p
