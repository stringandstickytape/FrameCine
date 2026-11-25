extends RefCounted

## Bookshop loft (app/environments/bookshop_loft.env.json; docs/environments/rooms/bookshop_loft.md):
## a Cozy retreats room built by Gemini 4 Neon Extra High. A warm walnut-and-oak timber mezzanine loft perched
## overlooking a winding two-storey antique bookshop after closing on a rainy night. Everything is built from
## procedural boxes, lathes, arches, cylinders and strips; zero people, zero real marks, 100% procedural/CC0.
##
## Pieces (dispatched from kit/pieces.gd):
##   bookshop_mezzanine   two-storey timber hall (x = +/-5.60 m, z = -8.40..+5.40 m, lower shop floor y = -3.40 m,
##                        mezzanine deck y = 0.0 m, eaves y = 3.60 m, timber ridge y = 5.90 m), open central atrium
##                        well (x = -3.65..+3.65 m, z = -7.30..-2.05 m) framed by turned walnut columns and carved
##                        corbels, turned-oak & gleaming brass balustrade (handrail cleanly at y = 0.86 m — zero screen
##                        clipping from any seat), slanted timber rafters, collar tie-beams, king-posts and four tall
##                        rain-beaded dormer skylights with exterior rain-wet dark slate chimney roofs, grand central
##                        mahogany arched bookcase bay framing the cinema screen with fluted pilasters, carved pediment
##                        cornice and indirect cornice uplight (PieceCove), port & starboard mahogany reading tables
##                        holding glowing emerald-glass banker's lamps (PieceCove + PieceLamps), vintage brass
##                        terrestrial globe, glazed porcelain teacup & saucer, brass magnifying glass and stacked
##                        hardcovers, warm amber glass pendant lamps flanking the atrium well, aft-port descending
##                        wooden mezzanine staircase with handrail, and a tall carved oak-case grandfather clock
##                        against the aft wall with a working live dial (PieceClock) and glazed brass pendulum door.
##   bookshop_shelves     towering two-storey floor-to-ceiling mahogany bookshelves lining both the lower bookshop
##                        atrium (y = -3.40..-0.32 m) and the upper mezzanine gallery walls (port, starboard, front
##                        flanks and aft wall flanking the grandfather clock), packed with nearly two thousand richly
##                        varied jewel-toned leather & cloth book spines (varied heights, depths, leaning volumes,
##                        horizontal folio stacks and gilt spine highlights batched into two shared soft materials),
##                        three slender oak-and-brass rolling library ladders hooked onto horizontal brass rail bars,
##                        plus the lower bookshop atrium well's oak shopkeeper's reading table piled with open folios,
##                        hardcover stacks and glowing reading lamp, slatted wooden book crates, brass floor lamp, and
##                        a warm cast-iron bookshop parlor stove.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")

const PIECES: Array[String] = ["bookshop_mezzanine", "bookshop_shelves"]

## Two-storey bookshop hall extents (metres).
const HALF_W := 5.60
const FRONT_Z := -8.40
const BACK_Z := 5.40
const LOWER_Y := -3.40
const MEZZ_Y := 0.00
const MEZZ_THICK := 0.28
const EAVE_Y := 3.60
const RIDGE_Y := 5.90

## Open central bookshop atrium well footprint.
const WELL_HW := 3.65
const WELL_Z0 := -7.30
const WELL_Z1 := -2.05

## Balustrade top rail height: strictly 0.86 m so seated eyes at y = 1.20 m clear the screen bottom (y = 0.955 m at
## z = -7.60 m) by 24 cm even from the back row (z = +1.75 m).
const RAIL_H := 0.86

## Aft-port descending stairwell opening.
const STAIR_X0 := -5.50
const STAIR_X1 := -3.90
const STAIR_Z0 := 1.70
const STAIR_Z1 := 4.80

## Tall dormer skylight openings on port & starboard roof slopes (matching weather.panes in bookshop_loft.env.json).
const DORMER_TOP_Y := 5.26
const DORMER_Z0_A := -4.55
const DORMER_Z1_A := -2.65
const DORMER_Z0_B := -0.25
const DORMER_Z1_B := 1.65

## Palette (sRGB; converted to linear on vertex colours).
const MAHOGANY := Color(0.32, 0.14, 0.075)
const MAHOGANY_DARK := Color(0.18, 0.08, 0.045)
const MAHOGANY_WARM := Color(0.42, 0.20, 0.105)
const WALNUT_BEAM := Color(0.24, 0.13, 0.075)
const OAK_HONEY := Color(0.48, 0.30, 0.16)
const OAK_WARM := Color(0.40, 0.24, 0.125)
const OAK_FLOOR := Color(0.44, 0.27, 0.145)
const LOWER_FLOOR := Color(0.28, 0.17, 0.095)
const ROOF_PLANK := Color(0.26, 0.15, 0.085)
const PLASTER_WARM := Color(0.56, 0.47, 0.36)
const PLASTER_DORMER := Color(0.46, 0.37, 0.28)
const CREAM_PAGE := Color(0.88, 0.82, 0.69)
const PORCELAIN_CREAM := Color(0.93, 0.90, 0.82)
const COBALT_GLAZE := Color(0.14, 0.28, 0.58)
const TEA_DARK := Color(0.11, 0.045, 0.018)
const GLOBE_PARCHMENT := Color(0.76, 0.67, 0.50)
const GLOBE_OCEAN := Color(0.24, 0.36, 0.38)
const BRASS := Color(0.86, 0.68, 0.34)
const BRASS_WARM := Color(0.94, 0.76, 0.40)
const BRASS_DARK := Color(0.56, 0.42, 0.19)
const IRON_DARK := Color(0.08, 0.08, 0.09)
const SLATE_WET := Color(0.11, 0.13, 0.17)
const BRICK_CHIMNEY := Color(0.26, 0.15, 0.12)
const TERRACOTTA_POT := Color(0.42, 0.21, 0.14)
const LAMP_AMBER := Color(1.0, 0.78, 0.44)
const LAMP_BULB := Color(1.0, 0.88, 0.64)
const STOVE_EMBER := Color(1.0, 0.46, 0.14)

## Rich jewel-toned antique book spine palette (12 distinct cloth & leather hues).
const BOOK_PALETTE: Array[Color] = [
	Color(0.46, 0.10, 0.11), # Deep oxblood
	Color(0.34, 0.09, 0.14), # Burgundy wine
	Color(0.11, 0.29, 0.17), # Forest hunter green
	Color(0.09, 0.21, 0.16), # Bottle pine
	Color(0.10, 0.18, 0.34), # Midnight navy
	Color(0.16, 0.25, 0.36), # Prussian slate
	Color(0.76, 0.68, 0.54), # Aged parchment cream
	Color(0.64, 0.46, 0.16), # Antique ochre gold
	Color(0.38, 0.21, 0.11), # Burnt umber leather
	Color(0.50, 0.27, 0.13), # Chestnut cognac
	Color(0.30, 0.12, 0.24), # Plum aubergine
	Color(0.30, 0.33, 0.17), # Warm olive cloth
]


## Custom Hall for Bookshop loft: builds the baked static woven Nordic wool rugs (`MezzanineRug`, using
## `Procedural.apply(..., "nordic_rug", ...)`, tinted deep burgundy/warm ochre/cream) beneath the mezzanine club
## armchairs and across the lower bookshop atrium floor, and tunes `PieceGlass` transparency.
class Hall:
	var kit: Node
	var has_mezzanine := false
	var rug_node: MeshInstance3D

	func finish(k: Node) -> void:
		if not has_mezzanine:
			return
		_build_woven_rugs(k)
		# Crisp clear glazing for the grandfather clock pendulum door, dormer glass and magnifying lens.
		for n: Node in k.owned():
			if n is MeshInstance3D and str(n.name).begins_with("PieceGlass"):
				var gm := (n as MeshInstance3D).material_override as ShaderMaterial
				if gm != null:
					gm.set_shader_parameter("alpha", 0.12)
					gm.set_shader_parameter("rim", 0.36)

	func tick(_delta: float) -> void:
		pass

	## Baked static mesh carrying both the upper mezzanine reading rug (`4.50 x 3.50 m` under all 6 Chesterfield
	## armchairs) and the lower bookshop atrium runner (`3.10 x 3.60 m` under the shopkeeper's reading table) on a
	## single shared `nordic_rug` procedural shader material (1 draw call total, zero Z-fighting).
	func _build_woven_rugs(k: Node) -> void:
		var m: ShaderMaterial = k._light.from_param({"library": "woven_upholstery", "color": [1.0, 1.0, 1.0]}, false)
		Procedural.apply(m, "nordic_rug", Color(0.54, 0.31, 0.22))
		m.set_shader_parameter("use_mesh_uv", true)
		m.set_shader_parameter("uv_repeat", Vector2(1.0, 1.0))
		m.set_shader_parameter("normal_strength", 1.15)
		m.set_shader_parameter("specular", 0.25)

		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedFloat32Array()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var idx := PackedInt32Array()

		# [x0, x1, z0, z1, y_top, y_base, uv_scale_x, uv_scale_z, uv2_rect]
		var rugs: Array = [
			[-2.25, 2.25, -0.95, 2.55, MEZZ_Y + 0.012, MEZZ_Y + 0.002, 2.0, 2.0, Rect2(0.04, 0.04, 0.42, 0.92)],
			[-1.55, 1.55, -6.35, -2.75, LOWER_Y + 0.014, LOWER_Y + 0.002, 1.5, 2.0, Rect2(0.54, 0.04, 0.42, 0.92)],
		]
		for rg: Array in rugs:
			var x0: float = rg[0]
			var x1: float = rg[1]
			var z0: float = rg[2]
			var z1: float = rg[3]
			var yt: float = rg[4]
			var yb: float = rg[5]
			var us: float = rg[6]
			var vs: float = rg[7]
			var r2: Rect2 = rg[8]
			var bev := 0.055
			# Top woven face (inset by bevel).
			var b := v.size()
			var top_pts := [
				Vector3(x0 + bev, yt, z0 + bev),
				Vector3(x1 - bev, yt, z0 + bev),
				Vector3(x1 - bev, yt, z1 - bev),
				Vector3(x0 + bev, yt, z1 - bev),
			]
			var top_uvs := [Vector2(0.0, 0.0), Vector2(us, 0.0), Vector2(us, vs), Vector2(0.0, vs)]
			var top_uv2s := [
				Vector2(r2.position.x, r2.position.y),
				Vector2(r2.end.x, r2.position.y),
				Vector2(r2.end.x, r2.end.y),
				Vector2(r2.position.x, r2.end.y),
			]
			for i in 4:
				v.append(top_pts[i])
				n.append(Vector3.UP)
				t.append_array([1.0, 0.0, 0.0, 1.0])
				uv.append(top_uvs[i])
				uv2.append(top_uv2s[i])
			idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])

			# Four gentle bevelled wool skirt strips around the rug perimeter (thick handcrafted textile edge).
			var out_pts := [
				Vector3(x0, yb, z0),
				Vector3(x1, yb, z0),
				Vector3(x1, yb, z1),
				Vector3(x0, yb, z1),
			]
			var sk_norms := [
				Vector3(0.0, 0.4, -0.92).normalized(),
				Vector3(0.92, 0.4, 0.0).normalized(),
				Vector3(0.0, 0.4, 0.92).normalized(),
				Vector3(-0.92, 0.4, 0.0).normalized(),
			]
			for side in 4:
				var nxt := (side + 1) % 4
				var sb := v.size()
				var spts := [out_pts[side], out_pts[nxt], top_pts[nxt], top_pts[side]]
				var suvs := [top_uvs[side], top_uvs[nxt], top_uvs[nxt], top_uvs[side]]
				var suv2s := [top_uv2s[side], top_uv2s[nxt], top_uv2s[nxt], top_uv2s[side]]
				for i in 4:
					v.append(spts[i])
					n.append(sk_norms[side])
					t.append_array([1.0, 0.0, 0.0, 1.0])
					uv.append(suvs[i])
					uv2.append(suv2s[i])
				idx.append_array([sb, sb + 1, sb + 2, sb, sb + 2, sb + 3])

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
		rug_node = k._add_mesh("MezzanineRug", mesh)
		rug_node.gi_mode = GeometryInstance3D.GI_MODE_STATIC


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	# Keep PieceStatic's lightmap atlas crisp and strictly <= 1024 x 1024 across the two-storey hall.
	c.s.texel = maxf(float(c.s.texel), 0.24)
	var h := _hall(c)
	match piece:
		"bookshop_mezzanine":
			h.has_mezzanine = true
			_bookshop_mezzanine(c)
		"bookshop_shelves":
			_bookshop_shelves(c)
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


static func _brass(c: Object) -> Material:
	return c.shiny("gilt", 1.0, 0.72, 0.22)


static func _ceramic(c: Object) -> Material:
	return c.shiny("china", 0.0, 0.42, 0.12)


static func _lacquer(c: Object) -> Material:
	return c.shiny("iron", 0.0, 0.44, 0.12)


static func _solid(c: Object, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, basis))


static func _roof_y(abs_x: float) -> float:
	return RIDGE_Y - (RIDGE_Y - EAVE_Y) * clampf(abs_x / HALF_W, 0.0, 1.0)


# ======================================================================================================================
# Piece 1: bookshop_mezzanine — hall, mezzanine gallery, balustrade, roof & dormers, screen bay, tables, clock & stairs
# ======================================================================================================================

static func _bookshop_mezzanine(c: Object) -> void:
	_hall_shell_and_floors(c)
	_roof_rafters_and_dormers(c)
	_neighbour_chimney_roofs(c)
	_mezzanine_columns_and_balustrade(c)
	_screen_bookcase_bay(c)
	_mezzanine_reading_tables(c)
	_amber_pendant_lamps(c)
	_grandfather_clock(c)
	_aft_port_staircase(c)
	_room_lamps(c)


## Two-storey timber bookshop enclosure: lower shop floor (y = -3.40 m), mezzanine timber gallery decks (y = 0.0 m)
## framing the dramatic open central atrium well and aft-port stairwell, outer panelled & plastered walls, and gables.
static func _hall_shell_and_floors(c: Object) -> void:
	var s: RoomMesh = c.s
	var w := HALF_W * 2.0
	var d := BACK_Z - FRONT_Z
	var cz := (FRONT_Z + BACK_Z) * 0.5

	# --- 1. Lower Bookshop Ground Floor (`y = -3.40 m`, wide aged rustic oak planks) ---
	s.surface(c.tinted("roof"))
	s.colour = _lin(LOWER_FLOOR)
	s.face([
		Vector3(-HALF_W, LOWER_Y, FRONT_Z), Vector3(HALF_W, LOWER_Y, FRONT_Z),
		Vector3(HALF_W, LOWER_Y, BACK_Z), Vector3(-HALF_W, LOWER_Y, BACK_Z),
	], Vector3.UP)

	# --- 2. Mezzanine Timber Gallery Decks (`y = 0.0 m`, slab thickness `0.28 m`, honey-walnut wide planks) ---
	# Six cleanly non-overlapping slabs leaving the central atrium well (x = -3.65..+3.65, z = -7.30..-2.05) and
	# the aft-port stairwell cutout (x = -5.50..-3.90, z = +1.70..+4.80) open!
	var deck_rects: Array = [
		[STAIR_X1, HALF_W, WELL_Z1, BACK_Z],        # Main aft seating platform (all 6 armchairs sit here!)
		[-HALF_W, STAIR_X1, WELL_Z1, STAIR_Z0],     # Aft-port forward landing
		[-HALF_W, STAIR_X1, STAIR_Z1, BACK_Z],      # Aft-port strip behind stairwell
		[-HALF_W, -WELL_HW, WELL_Z0, WELL_Z1],      # Port upper gallery walkway
		[WELL_HW, HALF_W, WELL_Z0, WELL_Z1],        # Starboard upper gallery walkway
		[-HALF_W, HALF_W, FRONT_Z, WELL_Z0],        # Front gallery bridge beneath the screen bookcase bay
	]
	for rc: Array in deck_rects:
		var x0: float = rc[0]
		var x1: float = rc[1]
		var z0: float = rc[2]
		var z1: float = rc[3]
		# Top wide honey-walnut floorboards.
		s.surface(c.tinted("roof"))
		s.colour = _lin(OAK_FLOOR)
		s.face([
			Vector3(x0, MEZZ_Y, z0), Vector3(x1, MEZZ_Y, z0),
			Vector3(x1, MEZZ_Y, z1), Vector3(x0, MEZZ_Y, z1),
		], Vector3.UP)
		# Dark walnut timber ceiling soffit underneath the mezzanine gallery.
		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY_DARK)
		s.face([
			Vector3(x0, MEZZ_Y - MEZZ_THICK, z0), Vector3(x0, MEZZ_Y - MEZZ_THICK, z1),
			Vector3(x1, MEZZ_Y - MEZZ_THICK, z1), Vector3(x1, MEZZ_Y - MEZZ_THICK, z0),
		], Vector3.DOWN)

	# Heavy moulded mahogany mezzanine fascia beam wrapping all four edges of the open central atrium well!
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY)
	var well_w := WELL_HW * 2.0
	var well_d := WELL_Z1 - WELL_Z0
	var well_zc := (WELL_Z0 + WELL_Z1) * 0.5
	var beam_y := MEZZ_Y - MEZZ_THICK * 0.5
	# Front-of-seating fascia (`z = WELL_Z1`), far-front bridge fascia (`z = WELL_Z0`), and port/starboard side fascias.
	s.box(Vector3(0.0, beam_y, WELL_Z1 + 0.05), Vector3(well_w + 0.24, MEZZ_THICK + 0.06, 0.14))
	s.box(Vector3(0.0, beam_y, WELL_Z0 - 0.05), Vector3(well_w + 0.24, MEZZ_THICK + 0.06, 0.14))
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(sd * (WELL_HW + 0.05), beam_y, well_zc), Vector3(0.14, MEZZ_THICK + 0.06, well_d))
	# Warm moulding lip & dentil trim accent along the mezzanine fascia rim.
	s.colour = _lin(MAHOGANY_WARM)
	s.box(Vector3(0.0, MEZZ_Y - 0.02, WELL_Z1 - 0.03), Vector3(well_w + 0.12, 0.055, 0.07))
	s.box(Vector3(0.0, MEZZ_Y - MEZZ_THICK - 0.02, WELL_Z1 - 0.02), Vector3(well_w + 0.12, 0.05, 0.08))
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(sd * (WELL_HW - 0.03), MEZZ_Y - 0.02, well_zc), Vector3(0.07, 0.055, well_d))

	# Underside exposed walnut floor joists beneath the aft mezzanine overhang (visible from lower bookshop!).
	s.colour = _lin(WALNUT_BEAM)
	for jx: float in [-3.6, -1.8, 0.0, 1.8, 3.6]:
		s.box(Vector3(jx, MEZZ_Y - MEZZ_THICK - 0.09, 1.65), Vector3(0.16, 0.18, 7.2), Basis(), [RoomMesh.UP])

	# --- 3. Outer Enclosure Walls (Lower Mahogany Panelling + Upper Aged Plaster + Front/Aft Attic Gables) ---
	# Lower storey walls (`y = -3.40..0.0`) in rich dark mahogany wainscot.
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	s.face([Vector3(-HALF_W, LOWER_Y, FRONT_Z), Vector3(-HALF_W, LOWER_Y, BACK_Z),
			Vector3(-HALF_W, MEZZ_Y, BACK_Z), Vector3(-HALF_W, MEZZ_Y, FRONT_Z)], Vector3.RIGHT)
	s.face([Vector3(HALF_W, LOWER_Y, BACK_Z), Vector3(HALF_W, LOWER_Y, FRONT_Z),
			Vector3(HALF_W, MEZZ_Y, FRONT_Z), Vector3(HALF_W, MEZZ_Y, BACK_Z)], Vector3.LEFT)
	s.face([Vector3(-HALF_W, LOWER_Y, FRONT_Z), Vector3(HALF_W, LOWER_Y, FRONT_Z),
			Vector3(HALF_W, MEZZ_Y, FRONT_Z), Vector3(-HALF_W, MEZZ_Y, FRONT_Z)], Vector3.BACK)
	s.face([Vector3(HALF_W, LOWER_Y, BACK_Z), Vector3(-HALF_W, LOWER_Y, BACK_Z),
			Vector3(-HALF_W, MEZZ_Y, BACK_Z), Vector3(HALF_W, MEZZ_Y, BACK_Z)], Vector3.FORWARD)

	# Upper storey walls (`y = 0.0..EAVE_Y`) & triangular front/aft attic gables (`EAVE_Y..RIDGE_Y`) in warm library plaster.
	s.surface(c.tinted("plaster"))
	s.colour = _lin(PLASTER_WARM)
	s.face([Vector3(-HALF_W, MEZZ_Y, FRONT_Z), Vector3(-HALF_W, MEZZ_Y, BACK_Z),
			Vector3(-HALF_W, EAVE_Y, BACK_Z), Vector3(-HALF_W, EAVE_Y, FRONT_Z)], Vector3.RIGHT)
	s.face([Vector3(HALF_W, MEZZ_Y, BACK_Z), Vector3(HALF_W, MEZZ_Y, FRONT_Z),
			Vector3(HALF_W, EAVE_Y, FRONT_Z), Vector3(HALF_W, EAVE_Y, BACK_Z)], Vector3.LEFT)
	s.face([Vector3(-HALF_W, MEZZ_Y, FRONT_Z), Vector3(HALF_W, MEZZ_Y, FRONT_Z),
			Vector3(HALF_W, EAVE_Y, FRONT_Z), Vector3(-HALF_W, EAVE_Y, FRONT_Z)], Vector3.BACK)
	s.face([Vector3(HALF_W, MEZZ_Y, BACK_Z), Vector3(-HALF_W, MEZZ_Y, BACK_Z),
			Vector3(-HALF_W, EAVE_Y, BACK_Z), Vector3(HALF_W, EAVE_Y, BACK_Z)], Vector3.FORWARD)
	# Front & aft triangular gable end walls closing the pitched attic roof cleanly!
	s.face([Vector3(-HALF_W, EAVE_Y, FRONT_Z), Vector3(HALF_W, EAVE_Y, FRONT_Z), Vector3(0.0, RIDGE_Y, FRONT_Z)],
			Vector3.BACK)
	s.face([Vector3(HALF_W, EAVE_Y, BACK_Z), Vector3(-HALF_W, EAVE_Y, BACK_Z), Vector3(0.0, RIDGE_Y, BACK_Z)],
			Vector3.FORWARD)

	# Heavy horizontal walnut wall-plate beams along port & starboard eaves + gable tie-beams & timber wall framing.
	s.surface(c.tinted("wood"))
	s.colour = _lin(WALNUT_BEAM)
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(sd * (HALF_W - 0.11), EAVE_Y - 0.10, cz), Vector3(0.22, 0.22, d), Basis(),
				[RoomMesh.LEFT if sd < 0.0 else RoomMesh.RIGHT])
		# Skirting baseboards on mezzanine & lower shop walls.
		s.box(Vector3(sd * (HALF_W - 0.03), MEZZ_Y + 0.09, cz), Vector3(0.06, 0.18, d), Basis(),
				[RoomMesh.DOWN, RoomMesh.LEFT if sd < 0.0 else RoomMesh.RIGHT])
	# Front & aft gable collar beams & vertical king-posts framing the attic ends.
	for gz: float in [FRONT_Z + 0.10, BACK_Z - 0.10]:
		s.box(Vector3(0.0, EAVE_Y - 0.08, gz), Vector3(w, 0.20, 0.20))
		s.box(Vector3(0.0, (EAVE_Y + RIDGE_Y) * 0.5, gz), Vector3(0.20, RIDGE_Y - EAVE_Y, 0.18))
		for sd: float in [-1.0, 1.0]:
			Shapes.beam(s, Vector3(sd * HALF_W, EAVE_Y, gz), Vector3(0.0, RIDGE_Y, gz), Vector2(0.18, 0.20))


## Slanted cozy attic timber roof with exposed walnut rafters, collar tie-beams, king-posts, purlins, and four tall
## rain-beaded dormer skylights cutting cleanly through both roof slopes (zero sky leaks, zero blocking of glass!).
static func _roof_rafters_and_dormers(c: Object) -> void:
	var s: RoomMesh = c.s
	var g: RoomMesh = c.glass
	var d := BACK_Z - FRONT_Z
	var cz := (FRONT_Z + BACK_Z) * 0.5
	var rise := RIDGE_Y - EAVE_Y
	# Where the horizontal dormer ceiling (y = 5.26 m) intersects the pitched roof slope.
	var x_join := HALF_W * (RIDGE_Y - DORMER_TOP_Y) / rise

	var solid_spans: Array = [
		Vector2(FRONT_Z, DORMER_Z0_A),
		Vector2(DORMER_Z1_A, DORMER_Z0_B),
		Vector2(DORMER_Z1_B, BACK_Z),
	]
	var dormer_bands: Array = [
		Vector2(DORMER_Z0_A, DORMER_Z1_A),
		Vector2(DORMER_Z0_B, DORMER_Z1_B),
	]

	for sd: float in [-1.0, 1.0]:
		var n_slope := Vector3(-sd * rise, -HALF_W, 0.0).normalized()

		# Solid sloped timber roof planking between dormers.
		s.surface(c.tinted("roof"))
		s.colour = _lin(ROOF_PLANK)
		for sp: Vector2 in solid_spans:
			s.face([
				Vector3(sd * HALF_W, EAVE_Y, sp.x),
				Vector3(sd * HALF_W, EAVE_Y, sp.y),
				Vector3(0.0, RIDGE_Y, sp.y),
				Vector3(0.0, RIDGE_Y, sp.x),
			], n_slope)

		# Dormer skylight bays: upper slope above dormer ceiling + horizontal soffit + cheek walls + mullioned glass!
		for db: Vector2 in dormer_bands:
			var z0 := db.x
			var z1 := db.y
			var zc := (z0 + z1) * 0.5
			var dw := z1 - z0

			# Upper roof plank strip from ridge down to dormer ceiling junction (`abs_x = 0 .. x_join`).
			s.surface(c.tinted("roof"))
			s.colour = _lin(ROOF_PLANK)
			s.face([
				Vector3(sd * x_join, DORMER_TOP_Y, z0),
				Vector3(sd * x_join, DORMER_TOP_Y, z1),
				Vector3(0.0, RIDGE_Y, z1),
				Vector3(0.0, RIDGE_Y, z0),
			], n_slope)

			# Horizontal timber-planked dormer alcove ceiling (`y = DORMER_TOP_Y`, `abs_x = x_join .. HALF_W`).
			s.colour = _lin(ROOF_PLANK * 1.15)
			s.face([
				Vector3(sd * x_join, DORMER_TOP_Y, z0),
				Vector3(sd * HALF_W, DORMER_TOP_Y, z0),
				Vector3(sd * HALF_W, DORMER_TOP_Y, z1),
				Vector3(sd * x_join, DORMER_TOP_Y, z1),
			], Vector3.DOWN)

			# Triangular dormer cheek walls sealing front & back faces of the dormer cavity cleanly to the roof plane!
			s.surface(c.tinted("plaster"))
			s.colour = _lin(PLASTER_DORMER)
			s.face([
				Vector3(sd * x_join, DORMER_TOP_Y, z0),
				Vector3(sd * HALF_W, DORMER_TOP_Y, z0),
				Vector3(sd * HALF_W, EAVE_Y, z0),
			], Vector3.BACK)
			s.face([
				Vector3(sd * HALF_W, EAVE_Y, z1),
				Vector3(sd * HALF_W, DORMER_TOP_Y, z1),
				Vector3(sd * x_join, DORMER_TOP_Y, z1),
			], Vector3.FORWARD)
			# Horizontal walnut header moulding framing the dormer cheek soffit edge.
			s.surface(c.tinted("wood"))
			s.colour = _lin(WALNUT_BEAM)
			for wz_c: float in [z0 + 0.04, z1 - 0.04]:
				Shapes.beam(s, Vector3(sd * x_join, DORMER_TOP_Y - 0.03, wz_c),
						Vector3(sd * HALF_W, DORMER_TOP_Y - 0.03, wz_c), Vector2(0.09, 0.09))

			# Deep moulded mahogany dormer window casing (sill, header, jambs & sloped cheek rafters).
			var win_x := sd * (HALF_W - 0.05)
			var win_h := DORMER_TOP_Y - EAVE_Y
			var win_yc := (EAVE_Y + DORMER_TOP_Y) * 0.5
			s.surface(c.tinted("wood"))
			s.colour = _lin(MAHOGANY)
			s.box(Vector3(win_x - sd * 0.06, EAVE_Y + 0.03, zc), Vector3(0.28, 0.09, dw + 0.14))
			s.box(Vector3(win_x - sd * 0.04, DORMER_TOP_Y - 0.03, zc), Vector3(0.22, 0.09, dw + 0.14))
			for wz: float in [z0 + 0.04, z1 - 0.04]:
				s.box(Vector3(win_x - sd * 0.04, win_yc, wz), Vector3(0.22, win_h, 0.09))
				# Sloped walnut cheek-trim rafter bordering each dormer cutout.
				Shapes.beam(s, Vector3(sd * HALF_W, EAVE_Y, wz), Vector3(sd * x_join, DORMER_TOP_Y, wz),
						Vector2(0.11, 0.14))
			# Exterior overhanging dark slate dormer hood cap (`abs_x = 5.55..6.05`) framing the rain outside.
			s.surface(c.tinted("iron"))
			s.colour = _lin(SLATE_WET)
			s.box(Vector3(sd * (HALF_W + 0.22), DORMER_TOP_Y + 0.06, zc), Vector3(0.56, 0.10, dw + 0.28))

			# Dark wrought-iron mullioned glazing bars dividing each tall dormer window into 3 x 3 rain-beaded panes!
			s.colour = _lin(IRON_DARK)
			var mull_x := sd * (HALF_W - 0.08)
			for col in [1, 2]:
				var mz := lerpf(z0 + 0.06, z1 - 0.06, float(col) / 3.0)
				s.box(Vector3(mull_x, win_yc, mz), Vector3(0.04, win_h - 0.10, 0.036))
			for row in [1, 2]:
				var my := lerpf(EAVE_Y + 0.06, DORMER_TOP_Y - 0.06, float(row) / 3.0)
				s.box(Vector3(mull_x, my, zc), Vector3(0.04, 0.036, dw - 0.12))

			# Crisp glazing pane in `PieceGlass` sitting behind the `weather.panes` rain-beaded layer.
			g.surface(c.kit.GLASS)
			var gx := sd * (HALF_W - 0.10)
			g.face([
				Vector3(gx, EAVE_Y + 0.06, z0 + 0.06),
				Vector3(gx, EAVE_Y + 0.06, z1 - 0.06),
				Vector3(gx, DORMER_TOP_Y - 0.06, z1 - 0.06),
				Vector3(gx, DORMER_TOP_Y - 0.06, z0 + 0.06),
			], Vector3(-sd, 0.0, 0.0))

	# --- Exposed Heavy Walnut Attic Roof Trusses, Rafters, Collar Tie-Beams, King-Posts & Ridge Beam ---
	s.surface(c.tinted("wood"))
	s.colour = _lin(WALNUT_BEAM)
	# Heavy central ridge beam running the entire length of the bookshop loft.
	s.box(Vector3(0.0, RIDGE_Y - 0.13, cz), Vector3(0.22, 0.26, d - 0.10), Basis(), [RoomMesh.UP])

	# Seven pairs of sloped main roof rafters spaced cleanly around the four dormer skylight bays.
	var rafter_zs: Array[float] = [-7.85, -5.05, -2.20, -0.55, 1.95, 3.65, 5.05]
	var collar_zs: Array[float] = [-5.05, -2.20, 1.95, 3.65]
	for rz: float in rafter_zs:
		for sd: float in [-1.0, 1.0]:
			Shapes.beam(s, Vector3(sd * (HALF_W - 0.08), EAVE_Y - 0.04, rz), Vector3(0.0, RIDGE_Y - 0.10, rz),
					Vector2(0.15, 0.22))
		if rz in collar_zs:
			# Horizontal collar tie-beam spanning at y = 4.86 m (`abs_x = 2.53 m` at slope intersection!).
			var col_y := 4.86
			var col_hw := HALF_W * (RIDGE_Y - col_y) / rise
			s.box(Vector3(0.0, col_y, rz), Vector3(col_hw * 2.0 + 0.12, 0.18, 0.16))
			# Short central timber king-post rising from collar beam to ridge + twin diagonal struts.
			s.box(Vector3(0.0, (col_y + RIDGE_Y - 0.14) * 0.5, rz), Vector3(0.16, RIDGE_Y - 0.14 - col_y, 0.16))
			for sd: float in [-1.0, 1.0]:
				Shapes.beam(s, Vector3(0.0, col_y + 0.14, rz), Vector3(sd * 1.15, _roof_y(1.15) - 0.08, rz),
						Vector2(0.10, 0.12))
				# Curved-feel diagonal knee-braces linking eave wall posts to rafters (strictly above y = 3.10 m).
				Shapes.beam(s, Vector3(sd * (HALF_W - 0.14), EAVE_Y - 0.55, rz),
						Vector3(sd * (HALF_W - 0.92), _roof_y(HALF_W - 0.92) - 0.08, rz), Vector2(0.11, 0.13))

	# Longitudinal mid-slope purlin beams running along solid roof spans between dormers.
	var purlin_x := 2.95
	var purlin_y := _roof_y(purlin_x) - 0.10
	for sd: float in [-1.0, 1.0]:
		for sp: Vector2 in solid_spans:
			var slen := sp.y - sp.x
			s.box(Vector3(sd * purlin_x, purlin_y, (sp.x + sp.y) * 0.5), Vector3(0.14, 0.16, slen))


## Picturesque neighbouring rain-wet dark slate mansard rooftops & brick chimney stacks outside both dormer slopes
## (`|x| = 9.5..13.5 m`, strictly outside the rain particle boxes; elevated cleanly into the lower dormer views while
## keeping the port-forward crescent Moon at altitude 30 deg framed gleaming right above the chimneys!).
static func _neighbour_chimney_roofs(c: Object) -> void:
	var s: RoomMesh = c.s
	var gw: Array = c.glows.get("window", [])

	for sd: float in [-1.0, 1.0]:
		# Neighbouring wet-slate pitched gable roof silhouette outside the dormers (`|x| = 9.8..13.4 m`).
		var rx := sd * 11.6
		s.surface(c.tinted("iron"))
		s.colour = _lin(SLATE_WET)
		# Lower brick-and-slate building mass beneath the eaves (`y = 0.0..4.35 m`).
		s.box(Vector3(rx, 2.18, -1.5), Vector3(3.6, 4.35, 16.0), Basis(), [RoomMesh.DOWN])
		# Sloped wet-slate roof pitch facing our dormers (`y = 4.35..5.65 m` — clearly visible through the lower
		# panes of both port and starboard dormers!).
		var roof_in := sd * 9.8
		var roof_ridge := sd * 11.6
		s.face([
			Vector3(roof_in, 4.35, -9.5), Vector3(roof_in, 4.35, 6.5),
			Vector3(roof_ridge, 5.65, 6.5), Vector3(roof_ridge, 5.65, -9.5),
		], Vector3(-sd * 1.30, 1.80, 0.0).normalized())
		# Dark roof ridge tiles running along the wet-slate crest.
		s.colour = _lin(SLATE_WET * 1.35)
		s.box(Vector3(roof_ridge, 5.70, -1.5), Vector3(0.26, 0.14, 16.0))

		# Brick chimney stacks topped with terracotta chimney pots (flanking the Moon sightline on port so the
		# silver crescent hangs dramatically between the rain-wet chimney silhouettes!).
		var chim_zs: Array = [-5.8, -1.8, 1.6] if sd < 0.0 else [-4.4, -0.6, 2.6]
		for k in chim_zs.size():
			var cz := float(chim_zs[k])
			var ch_h := 6.65 if k == 1 else 6.35
			var cx := sd * (10.55 if k % 2 == 0 else 11.35)
			s.surface(c.tinted("wood"))
			s.colour = _lin(BRICK_CHIMNEY)
			s.box(Vector3(cx, (4.3 + ch_h) * 0.5, cz), Vector3(0.84, ch_h - 4.3, 1.18), Basis(), [RoomMesh.DOWN])
			# Stepped stone chimney crown.
			s.surface(c.tinted("iron"))
			s.colour = _lin(SLATE_WET * 1.35)
			s.box(Vector3(cx, ch_h + 0.07, cz), Vector3(0.98, 0.14, 1.32))
			# Three terracotta chimney pots rising proudly into the rainy night sky!
			s.surface(c.tinted("wood"))
			s.colour = _lin(TERRACOTTA_POT)
			for dz: float in [-0.34, 0.0, 0.34]:
				Shapes.cylinder(s, Vector3(cx, ch_h + 0.14, cz + dz), 0.11, 0.52, 8)

		# Distant warm amber garret windows glowing across the rainy rooftops (`y = 4.6..5.2 m`!).
		for wz: float in [-4.0, 0.8]:
			gw.append([
				Vector3(sd * 9.76, 4.10, wz),
				Vector3(0.0, 0.0, 0.30),
				Vector3(0.0, 0.38, 0.0),
				Vector3(-sd, 0.0, 0.0),
			])

	c.glows["window"] = gw


## Turned walnut-and-oak gallery columns supporting the mezzanine well from the lower shop floor (`y = -3.40..0.0 m`)
## plus the turned-oak & gleaming brass mezzanine balustrade wrapping all three sides of the atrium well cleanly at
## `RAIL_H = 0.86 m` (100% below every seat's sight line to the cinema screen!).
static func _mezzanine_columns_and_balustrade(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var brass := _brass(c)
	var wood_soft: Material = c.soft("wood", true)

	# --- 1. Six Turned Walnut Gallery Columns & Carved Corbel Knee-Braces Supporting the Mezzanine Well ---
	var col_zs: Array[float] = [WELL_Z1 + 0.04, (WELL_Z0 + WELL_Z1) * 0.5, WELL_Z0 - 0.04]
	for sd: float in [-1.0, 1.0]:
		var cx := sd * (WELL_HW + 0.04)
		for cz: float in col_zs:
			# Square chamfered plinth pedestal on the lower bookshop floor.
			s.surface(c.tinted("wood"))
			s.colour = _lin(MAHOGANY_DARK)
			s.box(Vector3(cx, LOWER_Y + 0.26, cz), Vector3(0.32, 0.52, 0.32), Basis(), [RoomMesh.DOWN])
			s.colour = _lin(MAHOGANY)
			s.box(Vector3(cx, MEZZ_Y - MEZZ_THICK - 0.10, cz), Vector3(0.34, 0.16, 0.34))
			# Turned walnut column shaft rising from plinth to mezzanine fascia beam.
			u.surface(wood_soft)
			u.colour = _lin(WALNUT_BEAM * 1.15)
			Shapes.lathe(u, [
				Vector2(0.135, LOWER_Y + 0.52),
				Vector2(0.115, LOWER_Y + 0.62),
				Vector2(0.105, LOWER_Y + 1.80),
				Vector2(0.095, MEZZ_Y - MEZZ_THICK - 0.24),
				Vector2(0.135, MEZZ_Y - MEZZ_THICK - 0.16),
			], Vector3(cx, 0.0, cz), 12)
			# Gleaming brass base & capital collar rings on each gallery column.
			u.surface(brass)
			u.colour = _lin(BRASS)
			Shapes.cylinder(u, Vector3(cx, LOWER_Y + 0.52, cz), 0.142, 0.04, 12)
			Shapes.cylinder(u, Vector3(cx, MEZZ_Y - MEZZ_THICK - 0.22, cz), 0.132, 0.04, 12)
			# Carved diagonal timber corbel knee-braces supporting the mezzanine rim.
			s.surface(c.tinted("wood"))
			s.colour = _lin(MAHOGANY_WARM)
			Shapes.beam(s, Vector3(cx, MEZZ_Y - MEZZ_THICK - 0.62, cz),
					Vector3(cx - sd * 0.44, MEZZ_Y - MEZZ_THICK - 0.06, cz), Vector2(0.09, 0.11))

	# --- 2. Turned-Oak & Gleaming Brass Mezzanine Balustrade (`y = 0.0 .. RAIL_H = 0.86 m`) ---
	# Three open runs overlooking the central atrium well:
	#   Front seating edge: z = WELL_Z1 + 0.06 (-1.99), x = -WELL_HW .. +WELL_HW
	#   Port gallery edge:  x = -WELL_HW - 0.06 (-3.71), z = WELL_Z0 .. WELL_Z1
	#   Starboard edge:     x = +WELL_HW + 0.06 (+3.71), z = WELL_Z0 .. WELL_Z1
	var rail_runs: Array = [
		[Vector3(-WELL_HW - 0.06, MEZZ_Y, WELL_Z1 + 0.06), Vector3(WELL_HW + 0.06, MEZZ_Y, WELL_Z1 + 0.06), true],
		[Vector3(-WELL_HW - 0.06, MEZZ_Y, WELL_Z0 - 0.06), Vector3(-WELL_HW - 0.06, MEZZ_Y, WELL_Z1 + 0.06), false],
		[Vector3(WELL_HW + 0.06, MEZZ_Y, WELL_Z0 - 0.06), Vector3(WELL_HW + 0.06, MEZZ_Y, WELL_Z1 + 0.06), false],
	]
	for run: Array in rail_runs:
		var p0: Vector3 = run[0]
		var p1: Vector3 = run[1]
		var is_front: bool = run[2]
		var dir := (p1 - p0).normalized()
		var rlen := p0.distance_to(p1)
		var mid := (p0 + p1) * 0.5
		var rbasis := Basis(dir, Vector3.UP, Vector3.UP.cross(dir))

		# Moulded honey-oak bottom shoe rail (`y = 0.035`) and sculpted top handrail (`top at y = 0.86 m`!).
		s.surface(c.tinted("wood"))
		s.colour = _lin(OAK_WARM)
		s.box(mid + Vector3(0.0, 0.035, 0.0), Vector3(rlen, 0.07, 0.11), rbasis, [RoomMesh.DOWN])
		s.colour = _lin(MAHOGANY_WARM)
		s.box(mid + Vector3(0.0, RAIL_H - 0.03, 0.0), Vector3(rlen + 0.08, 0.06, 0.12), rbasis)
		# Gleaming slim horizontal upper brass gallery bar just below the oak handrail (`y = 0.755 m`).
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		Shapes.beam(u, p0 + Vector3(0.0, RAIL_H - 0.105, 0.0), p1 + Vector3(0.0, RAIL_H - 0.105, 0.0),
				Vector2(0.022, 0.022))

		# Alternating turned honey-oak balusters and gleaming slim brass spindle rods along the entire rail!
		var count := int(floor(rlen / 0.24))
		for k in range(1, count):
			var bp := p0.lerp(p1, float(k) / float(count))
			# Leave clean gaps right where intermediate newel posts stand.
			if is_front and (absf(bp.x - (-1.85)) < 0.12 or absf(bp.x - 1.85) < 0.12):
				continue
			if not is_front and absf(bp.z - (WELL_Z0 + WELL_Z1) * 0.5) < 0.12:
				continue
			if k % 2 == 0:
				u.surface(wood_soft)
				u.colour = _lin(OAK_HONEY)
				Shapes.lathe(u, [
					Vector2(0.026, 0.07),
					Vector2(0.022, 0.16),
					Vector2(0.030, 0.34),
					Vector2(0.017, 0.58),
					Vector2(0.024, 0.72),
					Vector2(0.024, RAIL_H - 0.06),
				], bp, 8)
			else:
				u.surface(brass)
				u.colour = _lin(BRASS)
				Shapes.cylinder(u, bp + Vector3(0.0, 0.07, 0.0), 0.011, RAIL_H - 0.13, 8, Basis(), false)
				# Decorative turned brass centre knop bead on each brass spindle.
				Shapes.lathe(u, [Vector2(0.011, 0.40), Vector2(0.022, 0.44), Vector2(0.011, 0.48)], bp, 8)

		# Clean physics box enclosing each balustrade run (strictly >= 1.99 m from origin!).
		_solid(c, mid + Vector3(0.0, RAIL_H * 0.5, 0.0), Vector3(rlen, RAIL_H, 0.14), rbasis)

	# Carved square oak newel posts at corners and bay junctions (front posts strictly capped <= 0.92 m so ZERO
	# screen clipping even from back row!).
	var newels: Array = [
		[Vector3(-WELL_HW - 0.06, MEZZ_Y, WELL_Z1 + 0.06), 0.98],
		[Vector3(WELL_HW + 0.06, MEZZ_Y, WELL_Z1 + 0.06), 0.98],
		[Vector3(-WELL_HW - 0.06, MEZZ_Y, WELL_Z0 - 0.06), 0.98],
		[Vector3(WELL_HW + 0.06, MEZZ_Y, WELL_Z0 - 0.06), 0.98],
		[Vector3(-WELL_HW - 0.06, MEZZ_Y, (WELL_Z0 + WELL_Z1) * 0.5), 0.94],
		[Vector3(WELL_HW + 0.06, MEZZ_Y, (WELL_Z0 + WELL_Z1) * 0.5), 0.94],
		[Vector3(-1.85, MEZZ_Y, WELL_Z1 + 0.06), 0.89],
		[Vector3(1.85, MEZZ_Y, WELL_Z1 + 0.06), 0.89],
	]
	for nw: Array in newels:
		var np: Vector3 = nw[0]
		var nh: float = nw[1]
		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY)
		s.box(np + Vector3(0.0, nh * 0.5, 0.0), Vector3(0.14, nh, 0.14), Basis(), [RoomMesh.DOWN])
		s.colour = _lin(MAHOGANY_WARM)
		s.box(np + Vector3(0.0, nh + 0.015, 0.0), Vector3(0.17, 0.035, 0.17))
		# Small turned brass acorn finial cap (only +0.055 m tall -> front posts top out at 0.945 m, 15.5 cm below
		# the back-row sight line!).
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		Shapes.lathe(u, [
			Vector2(0.042, nh + 0.032),
			Vector2(0.032, nh + 0.045),
			Vector2(0.038, nh + 0.065),
			Vector2(0.000, nh + 0.088),
		], np, 10)


## Grand central mahogany arched bookcase bay directly across the upper atrium well framing the cinema screen
## (`center: [0.0, 2.25, -7.60]`, `size: [4.60, 2.59]`), with fluted pilasters, stepped library sill, carved pediment
## cornice, semicircular mahogany arch crown, and warm indirect cornice uplight cove (`PieceCove`).
static func _screen_bookcase_bay(c: Object) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 2.25, -7.60)))
	var sc_sz: Vector2 = scr.get("size", Vector2(4.60, 2.59))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var sz := sc_xf.origin.z
	var w := sc_sz.x
	var h := sc_sz.y
	var hw := w * 0.5
	var hh := h * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var brass := _brass(c)

	# Matte-black recessed acoustic backing strictly behind the picture plane (`z = sz - 0.055`).
	s.surface(c.tinted("iron"))
	s.colour = _lin(IRON_DARK)
	s.box(Vector3(cx, cy, sz - 0.065), Vector3(w + 0.12, h + 0.12, 0.04))

	# Deep stepped dark mahogany picture surround & architectural enclosure back to `FRONT_Z = -8.40` (strictly
	# outside `|x| <= hw` and `y in [cy - hh, cy + hh]` so zero geometry ever touches the screen sight line!).
	var frame_w := 0.16
	var pil_x := hw + frame_w + 0.18
	var cab_d := sz - FRONT_Z - 0.04
	var cab_zc := FRONT_Z + cab_d * 0.5

	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	# Left & right deep bookcase cheek piers flanking the screen.
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(cx + sd * (hw + frame_w * 0.5 + 0.18), cy + 0.05, cab_zc),
				Vector3(frame_w + 0.36, h + 0.65, cab_d))
	# Recessed upper frieze & lower dado bay below the screen sill (`y = MEZZ_Y .. cy - hh`).
	var bot_y := cy - hh
	var top_y := cy + hh
	s.box(Vector3(cx, (MEZZ_Y + bot_y - 0.02) * 0.5, cab_zc), Vector3(pil_x * 2.0 + 0.40, bot_y - MEZZ_Y - 0.02, cab_d))
	s.box(Vector3(cx, top_y + 0.24, cab_zc), Vector3(pil_x * 2.0 + 0.40, 0.48, cab_d))

	# Moulded mahogany inner picture bezel trim (`z = sz - 0.03`, strictly outside screen rectangle!).
	s.colour = _lin(MAHOGANY_WARM)
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(cx + sd * (hw + 0.075), cy, sz - 0.035), Vector3(0.15, h + 0.26, 0.06))
	s.box(Vector3(cx, top_y + 0.075, sz - 0.035), Vector3(w + 0.30, 0.15, 0.06))
	s.box(Vector3(cx, bot_y - 0.075, sz - 0.035), Vector3(w + 0.30, 0.15, 0.06))
	# Fine gleaming brass fillet inlay framing the inner picture recess!
	u.surface(brass)
	u.colour = _lin(BRASS)
	for sd: float in [-1.0, 1.0]:
		u.box(Vector3(cx + sd * (hw + 0.018), cy, sz - 0.018), Vector3(0.024, h + 0.05, 0.024))
	u.box(Vector3(cx, top_y + 0.018, sz - 0.018), Vector3(w + 0.06, 0.024, 0.024))
	u.box(Vector3(cx, bot_y - 0.018, sz - 0.018), Vector3(w + 0.06, 0.024, 0.024))

	# Broad stepped mahogany library sill ledge under the screen (`y = 0.72..0.88`, supported by carved brackets).
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY)
	s.box(Vector3(cx, bot_y - 0.18, sz + 0.06), Vector3(pil_x * 2.0 + 0.62, 0.10, 0.34))
	s.colour = _lin(MAHOGANY_DARK)
	for bx: float in [-2.35, -1.15, 0.0, 1.15, 2.35]:
		s.box(Vector3(cx + bx, bot_y - 0.44, sz + 0.02), Vector3(0.14, 0.44, 0.22))

	# Twin Grand Fluted Mahogany Pilasters (`x = +/- 2.64 m`, `y = 0.0..3.88 m`) with carved plinths & brass capitals!
	var pil_top := top_y + 0.30
	for sd: float in [-1.0, 1.0]:
		var px := cx + sd * pil_x
		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY_DARK)
		s.box(Vector3(px, 0.32, sz + 0.04), Vector3(0.42, 0.64, 0.30), Basis(), [RoomMesh.DOWN])
		s.colour = _lin(MAHOGANY)
		s.box(Vector3(px, (0.64 + pil_top) * 0.5, sz + 0.02), Vector3(0.34, pil_top - 0.64, 0.24))
		# Three vertical projecting fluted mahogany ribs down each pilaster face.
		s.colour = _lin(MAHOGANY_WARM)
		for fl: float in [-0.10, 0.0, 0.10]:
			s.box(Vector3(px + fl, (0.74 + pil_top - 0.18) * 0.5, sz + 0.145),
					Vector3(0.036, pil_top - 0.92, 0.03))
		# Stepped classical mahogany capital & gleaming brass necking collar!
		s.colour = _lin(MAHOGANY_WARM)
		s.box(Vector3(px, pil_top - 0.05, sz + 0.06), Vector3(0.46, 0.14, 0.34))
		u.surface(brass)
		u.colour = _lin(BRASS)
		u.box(Vector3(px, pil_top - 0.16, sz + 0.05), Vector3(0.39, 0.036, 0.28))

	# Carved Classical Pediment Entablature Cornice (`y = 3.84..4.18 m`) with dentil blocks & arched crown!
	var corn_y := pil_top + 0.12
	var corn_w := pil_x * 2.0 + 0.88
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY)
	s.box(Vector3(cx, corn_y, sz + 0.10), Vector3(corn_w, 0.16, 0.44))
	s.colour = _lin(MAHOGANY_WARM)
	s.box(Vector3(cx, corn_y + 0.14, sz + 0.18), Vector3(corn_w + 0.26, 0.11, 0.58))
	# Crisp frieze dentil blocks lining the underside of the projecting mahogany cornice.
	for k in 17:
		var dx := lerpf(-corn_w * 0.46, corn_w * 0.46, float(k) / 16.0)
		s.box(Vector3(cx + dx, corn_y - 0.09, sz + 0.28), Vector3(0.11, 0.075, 0.10))

	# Graceful Semicircular Mahogany Pediment Arch Crowning the Screen Bay (`y = 4.18..5.16 m`)!
	var arch_r_in := 1.48
	var arch_r_out := 1.72
	var arch_ctr := Vector3(cx, corn_y + 0.18, sz + 0.02)
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_WARM)
	Shapes.arch(s, arch_ctr, arch_r_in, arch_r_out, 0.30, 18, Basis(), 0.08, PI - 0.08)
	# Gleaming brass sunburst keystone finial & arched cornice inlay bead crowning the bookcase arch!
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.arch(u, arch_ctr + Vector3(0.0, 0.0, 0.15), arch_r_in + 0.02, arch_r_in + 0.055, 0.03, 18, Basis(),
			0.10, PI - 0.10, ["front", "inner", "outer"])
	Shapes.lathe(u, [
		Vector2(0.00, 0.00), Vector2(0.075, 0.06), Vector2(0.105, 0.14),
		Vector2(0.060, 0.23), Vector2(0.00, 0.30),
	], Vector3(cx, corn_y + 0.18 + arch_r_out - 0.02, sz + 0.06), 12)

	# --- Warm Indirect Cornice Uplight (`PieceCove`, live bound to `setting.lamps` + `cove_floor: 0.42`) ---
	# Curved recessed warm plaster tympanum inside the crowning mahogany arch washing softly upward from the cornice!
	cove.surface(c.kit.cove_material())
	var segs := 16
	var tymp_rows: Array = []
	var tymp_norms: Array = []
	var tymp_cols: Array = []
	for ring in 2:
		var r_pts := PackedVector3Array()
		var r_nrms := PackedVector3Array()
		var r_cols := PackedColorArray()
		var rad := 0.08 if ring == 0 else arch_r_in
		for k in segs + 1:
			var ang := lerpf(0.08, PI - 0.08, float(k) / float(segs))
			var px := cx + cos(ang) * rad
			var py := corn_y + 0.18 + sin(ang) * rad * 0.88
			var pz := sz - 0.10 + (0.04 if ring == 0 else 0.0)
			r_pts.append(Vector3(px, py, pz))
			r_nrms.append(Vector3.BACK)
			# Smooth soft wash strongest along the lower cornice trough, tapering gracefully upward into the arch!
			var h_frac := clampf((py - (corn_y + 0.18)) / arch_r_in, 0.0, 1.0)
			var w_glow := lerpf(0.66, 0.16, pow(h_frac, 0.72))
			r_cols.append(Color(0.84, 0.78, 0.68, w_glow))
		tymp_rows.append(r_pts)
		tymp_norms.append(r_nrms)
		tymp_cols.append(r_cols)
	cove.sheet(tymp_rows, tymp_norms, tymp_cols, Vector3.RIGHT, Vector3.UP)
	# Carved mahogany scroll volute brackets flanking the arched pediment cleanly atop the cornice!
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_WARM)
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(cx + sd * (arch_r_out + 0.34), corn_y + 0.30, sz + 0.06), Vector3(0.68, 0.16, 0.24))
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		Shapes.lathe(u, [Vector2(0.055, 0.0), Vector2(0.04, 0.06), Vector2(0.058, 0.12), Vector2(0.0, 0.19)],
				Vector3(cx + sd * (corn_w * 0.45), corn_y + 0.20, sz + 0.16), 10)

	_solid(c, Vector3(cx, 2.2, FRONT_Z + 0.42), Vector3(pil_x * 2.0 + 0.70, 4.4, 0.84))


## Cozy mezzanine side mahogany reading tables flanking the Chesterfield armchairs (`x = +/-2.46, z = -0.35`, strictly
## clear of every seat and screen sight line!) holding glowing emerald-glass banker's lamps (`PieceCove` + `PieceLamps`),
## stacked cloth hardcovers, brass magnifying glass, glazed porcelain teacup & saucer, and vintage brass terrestrial globe!
static func _mezzanine_reading_tables(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var g: RoomMesh = c.glass
	var brass := _brass(c)
	var wood_soft: Material = c.soft("wood", true)
	var ceramic := _ceramic(c)

	var table_h := 0.66
	var tw := 0.70
	var td := 0.70

	# Build twin matching mahogany reading tables at port (`x = -2.46`) and starboard (`x = +2.46`).
	for sd: float in [-1.0, 1.0]:
		var tx := sd * 2.46
		var tz := -0.35
		var ctr := Vector3(tx, MEZZ_Y, tz)

		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY_WARM)
		# Moulded square tabletop (`y = 0.64..0.66 m`).
		s.box(ctr + Vector3(0.0, table_h - 0.022, 0.0), Vector3(tw, 0.044, td))
		# Recessed drawer apron + lower shelf (`y = 0.22 m`).
		s.colour = _lin(MAHOGANY)
		s.box(ctr + Vector3(0.0, table_h - 0.095, 0.0), Vector3(tw - 0.10, 0.11, td - 0.10))
		s.box(ctr + Vector3(0.0, 0.22, 0.0), Vector3(tw - 0.12, 0.032, td - 0.12))

		# Four slender turned mahogany table legs with gleaming brass caster ferrules!
		for lx: float in [-0.27, 0.27]:
			for lz: float in [-0.27, 0.27]:
				u.surface(wood_soft)
				u.colour = _lin(MAHOGANY_DARK)
				Shapes.lathe(u, [
					Vector2(0.018, 0.05), Vector2(0.022, 0.22), Vector2(0.028, 0.42),
					Vector2(0.030, table_h - 0.04),
				], ctr + Vector3(lx, 0.0, lz), 8)
				u.surface(brass)
				u.colour = _lin(BRASS)
				Shapes.cylinder(u, ctr + Vector3(lx, 0.0, lz), 0.019, 0.055, 8)
		# Brass drawer knob facing inward toward the reading armchairs.
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		Shapes.cylinder(u, ctr + Vector3(-sd * (tw * 0.5 - 0.03), table_h - 0.095, 0.0), 0.016, 0.028, 8,
				Basis(Vector3.BACK, sd * PI * 0.5))

		# Horizontal stack of oversized antique atlases resting on the lower shelf (`y = 0.236 m`).
		_table_book_stack(c, ctr + Vector3(0.0, 0.236, 0.0), [
			[0.34, 0.042, 0.26, 6.0, BOOK_PALETTE[0]],
			[0.31, 0.038, 0.24, -4.0, BOOK_PALETTE[2]],
			[0.28, 0.036, 0.22, 9.0, BOOK_PALETTE[4]],
		])

		# Iconic Glowing Emerald-Glass Banker's Lamp on BOTH tables (angled warmly inward toward the reader!).
		_bankers_lamp(c, Vector3(tx + sd * 0.08, table_h, tz - 0.12), deg_to_rad(-sd * 32.0), 1.0)

		_solid(c, ctr + Vector3(0.0, table_h * 0.5, 0.0), Vector3(tw, table_h, td))

	# --- Starboard Table Hero Props (`x = +2.46, z = -0.35`, hero close-up!) ---
	# 1. Stacked cloth hardcovers with crimson bookmark ribbon (`+2.28, 0.66, -0.18`).
	_table_book_stack(c, Vector3(2.29, table_h, -0.19), [
		[0.25, 0.036, 0.18, 18.0, BOOK_PALETTE[2]],
		[0.23, 0.032, 0.16, 7.0, BOOK_PALETTE[0]],
		[0.21, 0.028, 0.15, 24.0, BOOK_PALETTE[7]],
	])
	# 2. Glazed Cream-and-Cobalt Ceramic Teacup & Saucer with dark tea (`+2.26, 0.66, -0.49`).
	var cup_at := Vector3(2.26, table_h, -0.49)
	u.surface(ceramic)
	u.colour = _lin(PORCELAIN_CREAM)
	Shapes.lathe(u, [
		Vector2(0.042, 0.000), Vector2(0.072, 0.012), Vector2(0.078, 0.020),
		Vector2(0.056, 0.015), Vector2(0.000, 0.010),
	], cup_at, 16)
	Shapes.lathe(u, [
		Vector2(0.030, 0.012), Vector2(0.044, 0.040), Vector2(0.050, 0.074),
		Vector2(0.052, 0.082), Vector2(0.046, 0.082), Vector2(0.038, 0.042),
	], cup_at, 16)
	# Cobalt glaze stripe & brass rim lip on the teacup.
	u.colour = _lin(COBALT_GLAZE)
	Shapes.lathe(u, [Vector2(0.049, 0.062), Vector2(0.051, 0.073)], cup_at, 16)
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [Vector2(0.052, 0.080), Vector2(0.050, 0.084), Vector2(0.046, 0.081)], cup_at, 16)
	# Tiny curved porcelain ear handle.
	u.surface(ceramic)
	u.colour = _lin(PORCELAIN_CREAM)
	Shapes.arch(u, cup_at + Vector3(-0.046, 0.050, 0.0), 0.016, 0.024, 0.010, 10, Basis(), PI * 0.5, PI * 1.5)
	# Glossy dark tea disc inside the cup.
	u.surface(_lacquer(c))
	u.colour = _lin(TEA_DARK)
	var tea_pts: Array = []
	for k in 12:
		var a := -TAU * float(k) / 12.0
		tea_pts.append(cup_at + Vector3(cos(a) * 0.044, 0.068, sin(a) * 0.044))
	u.face(tea_pts, Vector3.UP)

	# 3. Brass-Handled Magnifying Glass resting beside the stacked books (`+2.54, 0.66, -0.14`).
	var mag_c := Vector3(2.55, table_h + 0.012, -0.13)
	var mag_rot := Basis(Vector3.UP, deg_to_rad(-42.0))
	var mag_r := 0.056
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.arch(u, mag_c, mag_r - 0.008, mag_r + 0.008, 0.016, 16, mag_rot * Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU)
	var mh_basis := mag_rot * Basis(Vector3.BACK, -PI * 0.5)
	var mh_start := mag_c + mag_rot * Vector3(mag_r + 0.006, 0.0, 0.0)
	Shapes.lathe(u, [Vector2(0.008, 0.0), Vector2(0.011, 0.022)], mh_start, 10, mh_basis)
	u.surface(wood_soft)
	u.colour = _lin(MAHOGANY_DARK)
	Shapes.lathe(u, [Vector2(0.010, 0.022), Vector2(0.014, 0.085), Vector2(0.011, 0.135), Vector2(0.0, 0.142)],
			mh_start, 10, mh_basis)
	g.surface(c.kit.GLASS)
	var mpts: Array = []
	for k in 12:
		var ma := TAU * float(k) / 12.0
		mpts.append(mag_c + Vector3(cos(ma) * (mag_r - 0.007), 0.002, sin(ma) * (mag_r - 0.007)))
	g.face(mpts, Vector3.UP)

	# --- Port Table Hero Props (`x = -2.46, z = -0.35`) ---
	# 1. Vintage Brass Terrestrial Globe (`-2.32, 0.66, -0.16`, 0.43 m tall)!
	var gl_base := Vector3(-2.31, table_h, -0.16)
	var gl_ctr := gl_base + Vector3(0.0, 0.275, 0.0)
	var gl_r := 0.125
	var gl_tilt := Basis(Vector3.UP, deg_to_rad(26.0)) * Basis(Vector3.BACK, deg_to_rad(23.5))
	# Turned mahogany pedestal foot & gleaming brass finial spindle.
	u.surface(wood_soft)
	u.colour = _lin(MAHOGANY)
	Shapes.lathe(u, [
		Vector2(0.095, 0.000), Vector2(0.092, 0.022), Vector2(0.056, 0.042),
		Vector2(0.028, 0.095), Vector2(0.036, 0.115), Vector2(0.022, 0.132),
	], gl_base, 16)
	# Gleaming angled brass meridian half-ring & axis pin embracing the tilted antique globe!
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.arch(u, gl_ctr, gl_r + 0.010, gl_r + 0.024, 0.014, 18, gl_tilt, -PI * 0.5, PI * 0.5)
	Shapes.cylinder(u, gl_ctr - gl_tilt * Vector3(0.0, gl_r + 0.024, 0.0), 0.007, (gl_r + 0.024) * 2.0, 8, gl_tilt)
	# Horizontal brass equatorial horizon band around the globe.
	Shapes.arch(u, gl_ctr, gl_r + 0.001, gl_r + 0.007, 0.012, 20, gl_tilt * Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU)
	# Antique parchment-and-slate terrestrial globe sphere (banded latitude zones so continents & oceans read richly!).
	u.surface(ceramic)
	var gl_rings := 10
	for r in gl_rings:
		var lat0 := lerpf(-PI * 0.5, PI * 0.5, float(r) / float(gl_rings))
		var lat1 := lerpf(-PI * 0.5, PI * 0.5, float(r + 1) / float(gl_rings))
		u.colour = _lin(GLOBE_PARCHMENT if (r == 2 or r == 5 or r == 6 or r == 7) else GLOBE_OCEAN)
		Shapes.lathe(u, [
			Vector2(cos(lat0) * gl_r, sin(lat0) * gl_r),
			Vector2(cos(lat1) * gl_r, sin(lat1) * gl_r),
		], gl_ctr, 18, gl_tilt)

	# 2. Small stack of leather-bound novels beside the globe (`-2.55, 0.66, -0.14`).
	_table_book_stack(c, Vector3(-2.55, table_h, -0.14), [
		[0.22, 0.034, 0.16, -15.0, BOOK_PALETTE[1]],
		[0.20, 0.030, 0.15, -6.0, BOOK_PALETTE[8]],
	])

	# --- Compact Back-Row Side Reading Stands (`x = +/-2.42, z = +1.72`, height 0.56 m) ---
	for sd: float in [-1.0, 1.0]:
		var st_at := Vector3(sd * 2.42, MEZZ_Y, 1.72)
		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY)
		s.box(st_at + Vector3(0.0, 0.54, 0.0), Vector3(0.46, 0.04, 0.46))
		u.surface(wood_soft)
		u.colour = _lin(MAHOGANY_DARK)
		Shapes.lathe(u, [
			Vector2(0.16, 0.00), Vector2(0.14, 0.04), Vector2(0.045, 0.09),
			Vector2(0.036, 0.46), Vector2(0.08, 0.52),
		], st_at, 12)
		_table_book_stack(c, st_at + Vector3(0.0, 0.56, 0.0), [
			[0.24, 0.036, 0.17, sd * 14.0, BOOK_PALETTE[3 if sd < 0.0 else 4]],
			[0.22, 0.032, 0.16, -sd * 8.0, BOOK_PALETTE[6]],
			[0.19, 0.028, 0.14, sd * 20.0, BOOK_PALETTE[0]],
		])
		_solid(c, st_at + Vector3(0.0, 0.28, 0.0), Vector3(0.46, 0.56, 0.46))


## Reusable emerald-glass / warm-amber brass banker's lamp (`PieceCove` cowl shifts live with `setting.lamps`:
## `warm_amber` / `emerald_banker` / `dim`, plus warm glowing inner bulb in `PieceLamps` and dainty brass pull chain!).
static func _bankers_lamp(c: Object, base_at: Vector3, yaw: float, k: float) -> void:
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var lit: RoomMesh = c.lit
	var brass := _brass(c)
	var rot := Basis(Vector3.UP, yaw)

	# Stepped circular brass pedestal base + gracefully curved swan-neck stem.
	u.surface(brass)
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [
		Vector2(0.095 * k, 0.000), Vector2(0.095 * k, 0.018 * k), Vector2(0.072 * k, 0.034 * k),
		Vector2(0.036 * k, 0.056 * k), Vector2(0.018 * k, 0.075 * k),
	], base_at, 14)
	var p0 := base_at + Vector3(0.0, 0.072 * k, 0.0)
	var p1 := base_at + rot * Vector3(0.0, 0.24 * k, -0.02 * k)
	var p2 := base_at + rot * Vector3(0.0, 0.38 * k, -0.04 * k)
	var p3 := base_at + rot * Vector3(0.0, 0.42 * k, 0.02 * k)
	var shade_ctr := base_at + rot * Vector3(0.0, 0.345 * k, 0.045 * k)
	Shapes.beam(u, p0, p1, Vector2(0.016 * k, 0.016 * k))
	Shapes.beam(u, p1, p2, Vector2(0.016 * k, 0.016 * k))
	Shapes.beam(u, p2, p3, Vector2(0.015 * k, 0.015 * k))
	# Forked swivel yoke holding the curved glass cowl ends.
	var half_l := 0.125 * k
	var shade_r := 0.068 * k
	var tilt := rot * Basis(Vector3.RIGHT, deg_to_rad(18.0))
	for sd: float in [-1.0, 1.0]:
		var ep := shade_ctr + tilt * Vector3(sd * (half_l + 0.008 * k), 0.0, 0.0)
		Shapes.beam(u, p3, ep, Vector2(0.010 * k, 0.010 * k))
		Shapes.cylinder(u, ep - tilt * Vector3(sd * 0.008 * k, 0.0, 0.0), 0.016 * k, 0.016 * k, 8,
				tilt * Basis(Vector3.BACK, -sd * PI * 0.5))
	# Dainty hanging beaded brass pull chain beneath the shade.
	u.colour = _lin(BRASS_WARM)
	Shapes.cylinder(u, shade_ctr + rot * Vector3(0.03 * k, -0.11 * k, -0.015 * k), 0.003 * k, 0.11 * k, 6)
	Shapes.lathe(u, [Vector2(0.0, 0.0), Vector2(0.009 * k, 0.012 * k), Vector2(0.0, 0.022 * k)],
			shade_ctr + rot * Vector3(0.03 * k, -0.13 * k, -0.015 * k), 8)

	# Curved translucent emerald/amber glass cowl shade in `PieceCove` (shifts live with `setting.lamps`!).
	cove.surface(c.kit.cove_material())
	var segs := 12
	var rows: Array = []
	var norms: Array = []
	var cols: Array = []
	for j in 2:
		var x_loc := -half_l if j == 0 else half_l
		var r_pts := PackedVector3Array()
		var r_nrms := PackedVector3Array()
		var r_cols := PackedColorArray()
		for i in segs + 1:
			var t := float(i) / float(segs)
			var ang := lerpf(-0.12, PI + 0.12, t)
			var lp := Vector3(x_loc, sin(ang) * shade_r * 0.90, cos(ang) * shade_r)
			var ln := Vector3(0.0, sin(ang) * 1.10, cos(ang)).normalized()
			r_pts.append(shade_ctr + tilt * lp)
			r_nrms.append((tilt * ln).normalized())
			var crown := sin(clampf(t * PI, 0.0, PI))
			r_cols.append(Color(0.74, 0.78, 0.74, lerpf(0.40, 0.64, crown)))
		rows.append(r_pts)
		norms.append(r_nrms)
		cols.append(r_cols)
	cove.sheet(rows, norms, cols, Vector3.RIGHT, Vector3.FORWARD)
	for sd: float in [-1.0, 1.0]:
		var pts: Array = []
		for i in segs + 1:
			var ang := lerpf(-0.12, PI + 0.12, float(i) / float(segs))
			pts.append(shade_ctr + tilt * Vector3(sd * half_l, sin(ang) * shade_r * 0.90, cos(ang) * shade_r))
		cove.colour = Color(0.68, 0.72, 0.68, 0.48)
		cove.face(pts, (tilt * Vector3(sd, 0.0, 0.0)).normalized())

	# Warm opal-cream inner glowing bulb & reflector liner (`PieceLamps`, house group).
	lit.surface(c.shade(LAMP_BULB))
	Shapes.lathe(lit, [
		Vector2(0.00, -0.055 * k), Vector2(0.022 * k, -0.035 * k),
		Vector2(0.026 * k, 0.00), Vector2(0.022 * k, 0.035 * k), Vector2(0.00, 0.055 * k),
	], shade_ctr + tilt * Vector3(0.0, 0.015 * k, 0.0), 10, tilt * Basis(Vector3.BACK, -PI * 0.5))


## Crisp miniature real-scale stack of hardcover books on a reading table (leather/cloth boards + recessed cream pages).
static func _table_book_stack(c: Object, base_at: Vector3, specs: Array) -> void:
	var u: RoomMesh = c.u
	var y := base_at.y
	for i in specs.size():
		var sp: Array = specs[i]
		var bw: float = sp[0]
		var bh: float = sp[1]
		var bd: float = sp[2]
		var yaw := deg_to_rad(float(sp[3]))
		var col: Color = sp[4]
		var rot := Basis(Vector3.UP, yaw)
		var ctr := Vector3(base_at.x, y + bh * 0.5, base_at.z)
		# Hardcover cloth/leather boards & spine.
		u.surface(c.soft("cloth" if i % 2 == 0 else "fabric", true))
		u.colour = _lin(col)
		u.box(ctr + Vector3(0.0, -bh * 0.5 + 0.003, 0.0), Vector3(bw, 0.006, bd), rot)
		u.box(ctr + Vector3(0.0, bh * 0.5 - 0.003, 0.0), Vector3(bw, 0.006, bd), rot)
		u.box(ctr + rot * Vector3(-bw * 0.5 + 0.005, 0.0, 0.0), Vector3(0.010, bh, bd), rot)
		# Recessed cream page block.
		u.surface(c.soft("plaster", true))
		u.colour = _lin(CREAM_PAGE)
		u.box(ctr + rot * Vector3(0.004, 0.0, 0.0), Vector3(bw - 0.016, bh - 0.012, bd - 0.012), rot)
		y += bh


## Six warm amber-glass vintage library pendant lamps hanging from the attic timber roof rafters: four flanking the
## open central bookshop well (strictly >= 1.0 m outside the screen sight-line cone!) and two over the aft seating loft.
static func _amber_pendant_lamps(c: Object) -> void:
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var brass := _brass(c)

	# [x, shade_bottom_y, z]
	var pendants: Array = [
		[-2.78, 3.15, -3.85],
		[ 2.78, 3.15, -3.85],
		[-2.78, 3.22, -6.05],
		[ 2.78, 3.22, -6.05],
		[-2.60, 2.95,  2.25],
		[ 2.60, 2.95,  2.25],
	]
	for pd: Array in pendants:
		var px: float = pd[0]
		var py: float = pd[1]
		var pz: float = pd[2]
		var ceil_y := _roof_y(absf(px)) - 0.06
		var rod_bot := py + 0.24

		# Brass ceiling canopy rose, slender drop stem, fluted gallery cup & decorative trim band.
		u.surface(brass)
		u.colour = _lin(BRASS)
		Shapes.lathe(u, [Vector2(0.075, 0.0), Vector2(0.055, -0.04), Vector2(0.014, -0.065)],
				Vector3(px, ceil_y, pz), 10)
		Shapes.cylinder(u, Vector3(px, rod_bot, pz), 0.011, maxf(ceil_y - rod_bot - 0.05, 0.2), 8, Basis(), false)
		u.colour = _lin(BRASS_WARM)
		Shapes.lathe(u, [
			Vector2(0.018, 0.06), Vector2(0.048, 0.04), Vector2(0.066, 0.00),
			Vector2(0.060, -0.015),
		], Vector3(px, rod_bot, pz), 12)

		# Glowing ribbed warm-amber vintage glass bell shade (`PieceLamps`, house group).
		lit.surface(c.shade(LAMP_AMBER))
		Shapes.lathe(lit, [
			Vector2(0.058, 0.24),
			Vector2(0.095, 0.19),
			Vector2(0.145, 0.11),
			Vector2(0.175, 0.03),
			Vector2(0.165, 0.00),
			Vector2(0.140, 0.02),
			Vector2(0.095, 0.11),
			Vector2(0.045, 0.20),
		], Vector3(px, py, pz), 16)
		# Inner glowing vintage filament bulb tucked inside the amber bell.
		lit.surface(c.shade(LAMP_BULB))
		Shapes.lathe(lit, [
			Vector2(0.00, 0.06), Vector2(0.038, 0.08), Vector2(0.042, 0.12),
			Vector2(0.022, 0.17), Vector2(0.00, 0.19),
		], Vector3(px, py, pz), 10)


## Tall carved oak-case grandfather clock standing proudly against the aft mezzanine wall (`x = 0.0, z = +4.84`,
## facing `-Z` straight toward the mezzanine & viewer), with a working live dial (`PieceClock`), glazed waist pendulum
## door (`PieceGlass`), gleaming brass pendulum bob, twin brass weights, turned hood colonnettes and brass finials!
static func _grandfather_clock(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var g: RoomMesh = c.glass
	var brass := _brass(c)
	var wood_soft: Material = c.soft("wood", true)

	var cx := 0.0
	var cz := 4.86 # Back touches aft wall near z = +5.10, front projects cleanly to z = +4.64!

	# --- 1. Stepped Carved Oak Base Plinth (`y = 0.0 .. 0.50 m`) ---
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	s.box(Vector3(cx, 0.05, cz), Vector3(0.66, 0.10, 0.46), Basis(), [RoomMesh.DOWN])
	s.colour = _lin(OAK_WARM)
	s.box(Vector3(cx, 0.28, cz), Vector3(0.58, 0.36, 0.40))
	s.colour = _lin(MAHOGANY_WARM)
	s.box(Vector3(cx, 0.48, cz), Vector3(0.64, 0.06, 0.44))
	# Recessed decorative bevelled base panel facing `-Z`.
	s.colour = _lin(MAHOGANY_DARK)
	s.box(Vector3(cx, 0.28, cz - 0.205), Vector3(0.42, 0.22, 0.02))

	# --- 2. Tall Slender Glazed Oak Waist Trunk (`y = 0.51 .. 1.66 m`) with Recessed Pendulum Cavity ---
	var tr_y0 := 0.51
	var tr_y1 := 1.66
	var tr_ym := (tr_y0 + tr_y1) * 0.5
	var tr_h := tr_y1 - tr_y0
	# Solid back wall and left/right waist stiles forming a genuine hollow shadowed pendulum recess!
	s.colour = _lin(MAHOGANY_DARK)
	s.box(Vector3(cx, tr_ym, cz + 0.12), Vector3(0.48, tr_h, 0.08)) # Back board of trunk
	s.colour = _lin(OAK_WARM)
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(cx + sd * 0.205, tr_ym, cz), Vector3(0.09, tr_h, 0.32))
	# Top & bottom moulded oak door rails framing the tall vertical pendulum window (`x = -0.15..+0.15, y = 0.62..1.55`).
	s.colour = _lin(MAHOGANY)
	s.box(Vector3(cx, tr_y0 + 0.055, cz - 0.14), Vector3(0.44, 0.11, 0.04))
	s.box(Vector3(cx, tr_y1 - 0.055, cz - 0.14), Vector3(0.44, 0.11, 0.04))
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(cx + sd * 0.18, tr_ym, cz - 0.14), Vector3(0.055, tr_h - 0.20, 0.04))

	# Gleaming Brass Pendulum Rod, Lenticular Pendulum Bob & Twin Brass Weights inside the Waist Cavity!
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	var pend_z := cz + 0.02
	# Slender brass pendulum rod hanging from y = 1.62 down to the lenticular bob at y = 0.84.
	Shapes.cylinder(u, Vector3(cx, 0.84, pend_z), 0.007, 0.78, 8, Basis(), false)
	# Polished convex brass lenticular pendulum bob (`r = 0.092 m`, facing `-Z`!).
	Shapes.lathe(u, [
		Vector2(0.000, -0.022), Vector2(0.068, -0.016), Vector2(0.092, 0.000),
		Vector2(0.068,  0.016), Vector2(0.000,  0.022),
	], Vector3(cx, 0.84, pend_z), 18, Basis(Vector3.RIGHT, PI * 0.5))
	# Twin cylindrical brass weights suspended on slender brass chains flanking the pendulum!
	u.colour = _lin(BRASS)
	for wt: Array in [[-0.095, 1.12], [0.095, 1.24]]:
		var wx: float = wt[0]
		var wy: float = wt[1]
		Shapes.cylinder(u, Vector3(cx + wx, wy + 0.16, pend_z + 0.03), 0.004, 1.62 - (wy + 0.16), 6, Basis(), false)
		Shapes.cylinder(u, Vector3(cx + wx, wy, pend_z + 0.03), 0.026, 0.18, 10)
	# Tiny brass keyhole escutcheon on the waist door frame.
	u.box(Vector3(cx + 0.18, 1.10, cz - 0.165), Vector3(0.018, 0.05, 0.012))

	# Crystal-clear glazed waist pendulum door pane (`PieceGlass`).
	g.surface(c.kit.GLASS)
	g.face([
		Vector3(cx + 0.155, tr_y0 + 0.10, cz - 0.145),
		Vector3(cx - 0.155, tr_y0 + 0.10, cz - 0.145),
		Vector3(cx - 0.155, tr_y1 - 0.10, cz - 0.145),
		Vector3(cx + 0.155, tr_y1 - 0.10, cz - 0.145),
	], Vector3.FORWARD)

	# --- 3. Carved Oak Clock Hood (`y = 1.66 .. 2.42 m`), Live Dial (`PieceClock`), Colonnettes & Finials ---
	var hood_y0 := 1.66
	var dial_y := 1.98
	var dial_z := cz - 0.215
	var dial_r := 0.185
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_WARM)
	s.box(Vector3(cx, hood_y0 + 0.035, cz - 0.01), Vector3(0.62, 0.07, 0.44))
	s.colour = _lin(OAK_WARM)
	# Hood cabinet housing behind the dial.
	s.box(Vector3(cx, dial_y, cz + 0.01), Vector3(0.54, 0.56, 0.40))
	# Moulded cornice & swan-neck arched hood pediment crowning the clock!
	s.colour = _lin(MAHOGANY)
	s.box(Vector3(cx, 2.28, cz - 0.02), Vector3(0.66, 0.07, 0.46))
	Shapes.arch(s, Vector3(cx, 2.26, cz - 0.02), 0.14, 0.26, 0.36, 14, Basis(), 0.0, PI)

	# Twin turned oak-and-brass flanking hood colonnettes (`x = +/-0.24`).
	for sd: float in [-1.0, 1.0]:
		var px := cx + sd * 0.245
		u.surface(wood_soft)
		u.colour = _lin(MAHOGANY_WARM)
		Shapes.cylinder(u, Vector3(px, hood_y0 + 0.07, cz - 0.18), 0.026, 0.54, 10)
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		Shapes.cylinder(u, Vector3(px, hood_y0 + 0.07, cz - 0.18), 0.033, 0.035, 10)
		Shapes.cylinder(u, Vector3(px, 2.21, cz - 0.18), 0.033, 0.035, 10)

	# Three gleaming turned brass urn finials crowning the grandfather clock hood (`y = 2.31..2.58 m`)!
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	for fn: Array in [[-0.25, 2.31], [0.0, 2.50], [0.25, 2.31]]:
		Shapes.lathe(u, [
			Vector2(0.030, 0.00), Vector2(0.018, 0.03), Vector2(0.038, 0.075),
			Vector2(0.022, 0.12), Vector2(0.008, 0.155), Vector2(0.000, 0.18),
		], Vector3(cx + float(fn[0]), float(fn[1]), cz - 0.02), 10)

	# Gleaming spun-brass bezel ring framing the working live grandfather clock dial!
	Shapes.arch(u, Vector3(cx, dial_y, dial_z), dial_r - 0.004, dial_r + 0.022, 0.034, 24, Basis(), 0.0, TAU)

	# Working live clock dial (`PieceClock`, `env_clock.gdshader` keeping real wall time!):
	# Facing `-Z` (Vector3.FORWARD): when viewed from `(0, 1.2, 0)` looking aft toward `+Z`, viewer's right (3 o'clock)
	# is `-X` (`Vector3.LEFT`), 12 o'clock is `+Y` (`Vector3.UP`), and `LEFT.cross(UP) = FORWARD` (right-handed!).
	c.clocks.append([Vector3(cx, dial_y, dial_z - 0.012), Vector3.LEFT * dial_r, Vector3.UP * dial_r, Vector3.FORWARD])

	_solid(c, Vector3(cx, 1.28, cz), Vector3(0.68, 2.56, 0.50))


## Wooden mezzanine staircase descending cleanly along the aft-port wall from the loft (`z = +1.85, y = 0.0`) down to
## the lower antique bookshop floor (`z = +4.95, y = -3.40`), complete with oak treads, stringers, stairwell safety
## balustrade and descending walnut handrail!
static func _aft_port_staircase(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var brass := _brass(c)
	var wood_soft: Material = c.soft("wood", true)

	var sx0 := STAIR_X0 + 0.06
	var sx1 := STAIR_X1 - 0.06
	var sw := sx1 - sx0
	var sxc := (sx0 + sx1) * 0.5
	var steps := 14
	var z_start := STAIR_Z0 + 0.12
	var z_end := STAIR_Z1 + 0.25
	var dz := (z_end - z_start) / float(steps)
	var dy := (MEZZ_Y - LOWER_Y) / float(steps)

	# Solid oak treads & recessed dark mahogany risers descending cleanly into the lower bookshop!
	for k in steps:
		var ty := MEZZ_Y - float(k + 1) * dy
		var tz := z_start + (float(k) + 0.5) * dz
		s.surface(c.tinted("wood"))
		s.colour = _lin(OAK_HONEY)
		s.box(Vector3(sxc, ty + dy - 0.022, tz), Vector3(sw, 0.044, dz + 0.04))
		s.colour = _lin(MAHOGANY_DARK)
		s.box(Vector3(sxc, ty + dy * 0.5, tz - dz * 0.5), Vector3(sw - 0.04, dy, 0.03))

	# Slanted walnut side stringer beams embracing the staircase.
	s.surface(c.tinted("wood"))
	s.colour = _lin(WALNUT_BEAM)
	for edge_x: float in [sx0 - 0.03, sx1 + 0.03]:
		Shapes.beam(s, Vector3(edge_x, MEZZ_Y - 0.08, z_start), Vector3(edge_x, LOWER_Y + 0.08, z_end),
				Vector2(0.065, 0.26))

	# Slanted walnut stair handrail & gleaming brass brackets descending along the inner staircase edge!
	s.colour = _lin(MAHOGANY_WARM)
	Shapes.beam(s, Vector3(sx1 + 0.03, MEZZ_Y + RAIL_H, z_start),
			Vector3(sx1 + 0.03, LOWER_Y + RAIL_H + 0.08, z_end), Vector2(0.075, 0.065))
	u.surface(brass)
	u.colour = _lin(BRASS)
	for k in [2, 5, 8, 11]:
		var f := float(k) / float(steps)
		var pz := lerpf(z_start, z_end, f)
		var py := lerpf(MEZZ_Y, LOWER_Y, f)
		Shapes.cylinder(u, Vector3(sx1 + 0.03, py, pz), 0.012, RAIL_H, 6, Basis(), false)

	# Upper stairwell guard balustrade running along the mezzanine edge (`x = STAIR_X1`, `z = STAIR_Z0..STAIR_Z1`,
	# plus aft return rail along `z = STAIR_Z1`) so nobody could ever step into the stairwell!
	var guard_runs: Array = [
		[Vector3(STAIR_X1 + 0.04, MEZZ_Y, STAIR_Z0), Vector3(STAIR_X1 + 0.04, MEZZ_Y, STAIR_Z1 + 0.04)],
		[Vector3(STAIR_X0, MEZZ_Y, STAIR_Z1 + 0.04), Vector3(STAIR_X1 + 0.04, MEZZ_Y, STAIR_Z1 + 0.04)],
	]
	for gr: Array in guard_runs:
		var p0: Vector3 = gr[0]
		var p1: Vector3 = gr[1]
		var rlen := p0.distance_to(p1)
		var mid := (p0 + p1) * 0.5
		var dir := (p1 - p0).normalized()
		var rbasis := Basis(dir, Vector3.UP, Vector3.UP.cross(dir))
		s.surface(c.tinted("wood"))
		s.colour = _lin(OAK_WARM)
		s.box(mid + Vector3(0.0, 0.035, 0.0), Vector3(rlen, 0.07, 0.09), rbasis, [RoomMesh.DOWN])
		s.colour = _lin(MAHOGANY_WARM)
		s.box(mid + Vector3(0.0, RAIL_H - 0.03, 0.0), Vector3(rlen + 0.06, 0.06, 0.11), rbasis)
		var n_sp := maxi(int(floor(rlen / 0.24)), 3)
		for k in range(1, n_sp):
			var bp := p0.lerp(p1, float(k) / float(n_sp))
			if k % 2 == 0:
				u.surface(wood_soft)
				u.colour = _lin(OAK_HONEY)
				Shapes.cylinder(u, bp + Vector3(0.0, 0.07, 0.0), 0.020, RAIL_H - 0.13, 8, Basis(), false)
			else:
				u.surface(brass)
				u.colour = _lin(BRASS)
				Shapes.cylinder(u, bp + Vector3(0.0, 0.07, 0.0), 0.010, RAIL_H - 0.13, 6, Basis(), false)
		_solid(c, mid + Vector3(0.0, RAIL_H * 0.5, 0.0), Vector3(rlen, RAIL_H, 0.14), rbasis)

	# Corner newel posts framing the stairwell opening.
	for np: Vector3 in [Vector3(STAIR_X1 + 0.04, MEZZ_Y, STAIR_Z0), Vector3(STAIR_X1 + 0.04, MEZZ_Y, STAIR_Z1 + 0.04)]:
		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY)
		s.box(np + Vector3(0.0, 0.48, 0.0), Vector3(0.13, 0.96, 0.13), Basis(), [RoomMesh.DOWN])
		u.surface(brass)
		u.colour = _lin(BRASS_WARM)
		Shapes.lathe(u, [Vector2(0.04, 0.96), Vector2(0.035, 1.00), Vector2(0.0, 1.04)], np, 10)

	# --- Aft-Port Stairwell Wall Dressing (`x = -5.56, z = +1.70..+5.30`) ---
	# Rich mahogany dado wainscoting, three framed antique celestial/botanical prints (zero people!), and a glowing
	# warm amber-glass brass stairwell wall sconce so the stairwell gallery feels warm and hand-curated!
	var wx := -HALF_W + 0.04
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	s.box(Vector3(wx + 0.02, 0.56, 3.50), Vector3(0.05, 1.12, 3.65), Basis(), [RoomMesh.LEFT, RoomMesh.DOWN])
	s.colour = _lin(MAHOGANY_WARM)
	s.box(Vector3(wx + 0.04, 1.14, 3.50), Vector3(0.09, 0.07, 3.68), Basis(), [RoomMesh.LEFT])
	# Three carved mahogany & gilt framed antique bookshop plates along the stairwell wall!
	var prints: Array = [
		[2.35, 2.08, 0.62, 0.78, Color(0.18, 0.30, 0.24)], # Pressed fern botanical study
		[3.42, 2.18, 0.74, 0.92, Color(0.14, 0.22, 0.36)], # Antique celestial star-chart folio
		[4.48, 2.04, 0.60, 0.76, Color(0.42, 0.20, 0.14)], # Architectural arch elevation plate
	]
	for pr: Array in prints:
		var pz: float = pr[0]
		var py: float = pr[1]
		var pw: float = pr[2]
		var ph: float = pr[3]
		var plate_col: Color = pr[4]
		# Carved dark mahogany outer frame + warm cream mat + geometric tinted plate centre.
		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY)
		s.box(Vector3(wx + 0.025, py, pz), Vector3(0.04, ph, pw), Basis(), [RoomMesh.LEFT])
		s.surface(c.tinted("plaster"))
		s.colour = _lin(CREAM_PAGE)
		s.box(Vector3(wx + 0.042, py, pz), Vector3(0.014, ph - 0.12, pw - 0.12), Basis(), [RoomMesh.LEFT])
		u.surface(c.soft("fabric", true))
		u.colour = _lin(plate_col)
		u.box(Vector3(wx + 0.049, py, pz), Vector3(0.010, ph - 0.24, pw - 0.22), Basis(), [RoomMesh.LEFT])
		u.surface(brass)
		u.colour = _lin(BRASS)
		u.box(Vector3(wx + 0.052, py + ph * 0.5 - 0.055, pz), Vector3(0.008, 0.014, pw - 0.10))
		u.box(Vector3(wx + 0.052, py - ph * 0.5 + 0.055, pz), Vector3(0.008, 0.014, pw - 0.10))
	# Warm glowing amber-glass brass stairwell wall sconce between the framed prints (`z = 2.88, y = 2.68`).
	var sc_at := Vector3(wx + 0.02, 2.72, 3.42)
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.cylinder(u, sc_at, 0.065, 0.024, 10, Basis(Vector3.BACK, -PI * 0.5))
	Shapes.beam(u, sc_at + Vector3(0.02, 0.0, 0.0), sc_at + Vector3(0.18, 0.04, 0.0), Vector2(0.018, 0.018))
	var lit: RoomMesh = c.lit
	lit.surface(c.shade(LAMP_AMBER))
	Shapes.lathe(lit, [
		Vector2(0.042, 0.00), Vector2(0.088, 0.06), Vector2(0.095, 0.14), Vector2(0.058, 0.20),
	], sc_at + Vector3(0.18, -0.02, 0.0), 12)


## Eight warm stand-in shader + hidden bake omni lamps (`bake_lamps: 8`) plus two hidden bake moonlight spotlights
## slanting softly down through the rain-beaded dormer skylights onto the exposed walnut attic rafters. Zero live lights!
static func _room_lamps(c: Object) -> void:
	# 1. Port reading table banker's lamp golden pool.
	c.lamps.append([Vector3(-2.35, 1.25, -0.45), Color(1.0, 0.78, 0.44), 1.15])
	# 2. Starboard reading table banker's lamp golden pool.
	c.lamps.append([Vector3( 2.35, 1.25, -0.45), Color(1.0, 0.78, 0.44), 1.15])
	# 3. Port amber pendant lantern washing the port upper bookshelves & brass library ladder.
	c.lamps.append([Vector3(-2.75, 2.95, -4.40), Color(1.0, 0.75, 0.42), 1.15])
	# 4. Starboard amber pendant lantern washing the starboard upper bookshelves & gallery.
	c.lamps.append([Vector3( 2.75, 2.95, -4.40), Color(1.0, 0.75, 0.42), 1.15])
	# 5. Warm pediment cornice uplight grazing the grand mahogany arched screen bay & upper gable.
	c.lamps.append([Vector3( 0.00, 3.85, -6.55), Color(1.0, 0.76, 0.45), 1.00])
	# 6. Lower bookshop atrium golden table lamp illuminating open folios, runner rug & lower shelves.
	c.lamps.append([Vector3( 0.00, -1.45, -4.85), Color(1.0, 0.74, 0.40), 1.85])
	# 7. Cozy aft reading fill illuminating back armchairs, aft bookshelves, grandfather clock & stairwell.
	c.lamps.append([Vector3(-0.35, 2.40,  2.75), Color(1.0, 0.76, 0.46), 1.35])
	# 8. Cool silvery indigo night skylight grazing in through the port rain-beaded dormers.
	c.lamps.append([Vector3(-3.85, 4.30, -3.55), Color(0.52, 0.68, 0.96), 0.72])

	# Two hidden bake-only moonlight spotlights slanting through port & starboard forward dormers.
	c.spots.append([Vector3(-6.2, 4.7, -3.6), Vector3(-1.2, 1.0, -3.2), Color(0.54, 0.70, 0.96), 1.9, 14.0, 40.0])
	c.spots.append([Vector3( 6.2, 4.7, -3.6), Vector3( 1.2, 1.0, -3.2), Color(0.54, 0.70, 0.96), 1.5, 14.0, 40.0])


# ======================================================================================================================
# Piece 2: bookshop_shelves — two-storey mahogany bookshelves, jewel-toned book spines, 3 rolling ladders & lower atrium
# ======================================================================================================================

static func _bookshop_shelves(c: Object) -> void:
	_two_storey_bookcases(c)
	_rolling_brass_ladders(c)
	_lower_bookshop_atrium_props(c)


## Towering two-storey floor-to-ceiling mahogany bookshelves lining BOTH the lower bookshop atrium (`y = -3.40..-0.32`)
## AND the upper mezzanine walls (port, starboard, front flanks and aft wall flanking the grandfather clock), packed
## with ~1,900 richly varied jewel-toned leather & cloth book spines (batched in 2 soft surfaces, zero atlas bloat!).
static func _two_storey_bookcases(c: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1894

	# Each bookcase run: [origin, along_axis, into_room_normal, length, height, depth, bays, shelves, hero_gilt]
	var runs: Array = [
		# --- UPPER MEZZANINE BOOKSHELVES ---
		# Port upper wall (`x = -5.56`, running from front to stairwell edge `z = -7.65 .. +1.55`, 8 bays).
		[Vector3(-HALF_W + 0.04, MEZZ_Y, -7.65), Vector3.BACK, Vector3.RIGHT, 9.20, 3.44, 0.44, 8, 7, true],
		# Starboard upper wall (`x = +5.56`, full run `z = +4.85 .. -7.65`, 11 bays).
		[Vector3(HALF_W - 0.04, MEZZ_Y, 4.85), Vector3.FORWARD, Vector3.LEFT, 12.50, 3.44, 0.44, 11, 7, true],
		# Front-flank upper left & right bays (`z = -8.36`, flanking the grand mahogany screen bay, rising to 3.82 m!).
		[Vector3(-5.08, MEZZ_Y, FRONT_Z + 0.04), Vector3.RIGHT, Vector3.BACK, 2.15, 3.74, 0.44, 2, 7, true],
		[Vector3( 2.93, MEZZ_Y, FRONT_Z + 0.04), Vector3.RIGHT, Vector3.BACK, 2.15, 3.74, 0.44, 2, 7, true],
		# Aft mezzanine wall (`z = +5.36`, towering to 4.18 m flanking BOTH sides of the central grandfather clock!).
		[Vector3(-0.56, MEZZ_Y, BACK_Z - 0.04), Vector3.LEFT, Vector3.FORWARD, 3.12, 4.12, 0.44, 3, 8, true],
		[Vector3( 4.98, MEZZ_Y, BACK_Z - 0.04), Vector3.LEFT, Vector3.FORWARD, 4.42, 4.12, 0.44, 4, 8, true],

		# --- LOWER BOOKSHOP ATRIUM BOOKSHELVES (`y = -3.40 .. -0.34 m`) ---
		# Lower port wall (`x = -5.56`, visible peering down & left over the balustrade).
		[Vector3(-HALF_W + 0.04, LOWER_Y, -7.65), Vector3.BACK, Vector3.RIGHT, 6.40, 3.04, 0.48, 5, 6, false],
		# Lower starboard wall (`x = +5.56`, visible peering down & right over the balustrade).
		[Vector3(HALF_W - 0.04, LOWER_Y, -1.25), Vector3.FORWARD, Vector3.LEFT, 6.40, 3.04, 0.48, 5, 6, false],
		# Lower front wall beneath the cinema screen (`z = -8.36`, spanning full lower width!).
		[Vector3(-5.05, LOWER_Y, FRONT_Z + 0.04), Vector3.RIGHT, Vector3.BACK, 10.10, 3.04, 0.48, 8, 6, false],
		# Lower aft-well wall beneath the mezzanine seating overhang (`z = -2.18`, facing `-Z`).
		[Vector3(3.35, LOWER_Y, WELL_Z1 - 0.08), Vector3.LEFT, Vector3.FORWARD, 6.70, 3.02, 0.42, 5, 6, false],
	]

	for run: Array in runs:
		_build_bookcase_run(c, rng, run[0], run[1], run[2], float(run[3]), float(run[4]), float(run[5]),
				int(run[6]), int(run[7]), bool(run[8]))


static func _build_bookcase_run(c: Object, rng: RandomNumberGenerator, orig: Vector3, along: Vector3, normal: Vector3,
		length: float, height: float, depth: float, bays: int, shelves: int, hero_gilt: bool) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis := Basis(along, Vector3.UP, normal)
	var bay_w := length / float(bays)
	var plinth_h := 0.34
	var crown_h := 0.14
	var usable_h := height - plinth_h - crown_h
	var shelf_step := usable_h / float(shelves)
	var brass := _brass(c)

	# --- Mahogany Carcass (Baked Static `c.s`) ---
	s.surface(c.tinted("wood"))
	# Deep dark mahogany back-panel board inside every bookcase so zero pale wall plaster peeks behind the books!
	s.colour = _lin(MAHOGANY_DARK * 0.78)
	s.face([
		orig + normal * 0.035,
		orig + along * length + normal * 0.035,
		orig + along * length + Vector3.UP * height + normal * 0.035,
		orig + Vector3.UP * height + normal * 0.035,
	], normal)
	# Lower recessed plinth cabinet base + projecting crown cornice.
	s.colour = _lin(MAHOGANY_DARK)
	s.box(orig + along * (length * 0.5) + Vector3.UP * (plinth_h * 0.5) + normal * (depth * 0.52),
			Vector3(length, plinth_h, depth * 1.04), basis, [RoomMesh.FRONT, RoomMesh.DOWN])
	s.colour = _lin(MAHOGANY_WARM)
	s.box(orig + along * (length * 0.5) + Vector3.UP * (height - crown_h * 0.5) + normal * (depth * 0.58),
			Vector3(length + 0.10, crown_h, depth * 1.16), basis, [RoomMesh.FRONT])
	# Vertical mahogany pilaster dividers separating each bookcase bay.
	s.colour = _lin(MAHOGANY)
	for b in bays + 1:
		var bx := float(b) * bay_w
		s.box(orig + along * bx + Vector3.UP * (height * 0.5) + normal * (depth * 0.5),
				Vector3(0.085, height, depth), basis, [RoomMesh.FRONT, RoomMesh.DOWN])
	# Horizontal mahogany shelf boards spanning across the bookcase.
	s.colour = _lin(MAHOGANY * 0.92)
	for sh in shelves:
		var sy := plinth_h + float(sh) * shelf_step
		s.box(orig + along * (length * 0.5) + Vector3.UP * sy + normal * (depth * 0.5),
				Vector3(length - 0.04, 0.034, depth - 0.02), basis, [RoomMesh.FRONT])

	# Clean physics box enclosing the bookcase run (strictly at the walls, >= 4.7 m from origin!).
	_solid(c, orig + along * (length * 0.5) + Vector3.UP * (height * 0.5) + normal * (depth * 0.5),
			Vector3(length, height, depth), basis)

	# --- Jewel-Toned Leather & Cloth Book Spines (Batched Efficiently in `c.u` — 2 Shared Soft Surfaces!) ---
	var cloth_m: Material = c.soft("cloth", true)
	var fabric_m: Material = c.soft("fabric", true)
	var page_m: Material = c.soft("plaster", true)
	var skip_faces := [RoomMesh.DOWN, RoomMesh.FRONT]
	var skip_tight := [RoomMesh.DOWN, RoomMesh.FRONT, RoomMesh.LEFT, RoomMesh.RIGHT]

	for sh in shelves:
		var sy := plinth_h + float(sh) * shelf_step + 0.017
		# Subtle shelf-elevation ambient occlusion shading (brighter in mid eye-level shelves, deeper up top/bottom).
		var shelf_ao := 0.88 + 0.14 * sin(clampf(float(sh + 1) / float(shelves + 1), 0.0, 1.0) * PI)
		for b in bays:
			var x0 := float(b) * bay_w + 0.055
			var x1 := float(b + 1) * bay_w - 0.055
			var bay_clear := x1 - x0
			var x := x0
			var roll_style := rng.randf()
			# Occasional horizontal stack of oversized antique folios (~12% of bays) for authentic bookshop charm!
			var has_flat_stack := (roll_style < 0.12 and bay_clear > 0.72)
			var run_end := x1 - (0.30 if has_flat_stack else 0.02)
			var lean_end := (not has_flat_stack and roll_style > 0.74 and bay_clear > 0.55)
			if lean_end:
				run_end -= 0.16

			var idx_in_bay := 0
			var min_bw := 0.078 if hero_gilt else 0.115
			var max_bw := 0.155 if hero_gilt else 0.210
			while x < run_end - min_bw * 0.9:
				var rem := run_end - x
				var bw := minf(rng.randf_range(min_bw, max_bw), rem)
				var bh := clampf(shelf_step * rng.randf_range(0.58, 0.86), 0.18, shelf_step - 0.045)
				var bd := depth * rng.randf_range(0.64, 0.88)
				var base_col: Color = BOOK_PALETTE[rng.randi() % BOOK_PALETTE.size()]
				var shade := rng.randf_range(0.84, 1.15) * shelf_ao
				var is_leather := (rng.randi() % 2 == 0)
				u.surface(cloth_m if is_leather else fabric_m)
				u.colour = _lin(base_col * shade)
				var book_ctr := orig + along * (x + bw * 0.5) + Vector3.UP * (sy + bh * 0.5) + normal * (0.04 + bd * 0.5)
				# Use tight skip (spine + top only = 4 tris) on interior volumes, full exposed sides at bay edges!
				var use_skip := skip_faces if (idx_in_bay == 0 or x + bw >= run_end - min_bw * 0.9 or idx_in_bay % 4 == 0) else skip_tight
				u.box(book_ctr, Vector3(bw - 0.005, bh, bd), basis, use_skip)

				# Subtle gleaming gold-tooled spine band on select leather volumes along upper hero shelves!
				if hero_gilt and is_leather and (idx_in_bay % 5 == 1) and (sh % 2 == 1):
					u.surface(brass)
					u.colour = _lin(BRASS_DARK * 1.15)
					u.box(orig + along * (x + bw * 0.5) + Vector3.UP * (sy + bh * 0.72) + normal * (0.04 + bd + 0.003),
							Vector3(bw - 0.014, 0.014, 0.006), basis, skip_tight)
				x += bw
				idx_in_bay += 1

			# Jaunty leaning volume resting at 16-22 deg against the last upright book in the bay!
			if lean_end and x < x1 - 0.09:
				var lbw := rng.randf_range(0.042, 0.062)
				var lbh := clampf(shelf_step * rng.randf_range(0.62, 0.78), 0.19, shelf_step - 0.06)
				var lbd := depth * 0.76
				var lean_ang := deg_to_rad(rng.randf_range(15.0, 22.0))
				var lean_basis := basis * Basis(Vector3.BACK, lean_ang)
				var lcol: Color = BOOK_PALETTE[rng.randi() % BOOK_PALETTE.size()] * shelf_ao
				u.surface(cloth_m)
				u.colour = _lin(lcol)
				var lpos := orig + along * (x + lbh * sin(lean_ang) * 0.5 + 0.015) \
						+ Vector3.UP * (sy + lbh * cos(lean_ang) * 0.5) + normal * (0.04 + lbd * 0.5)
				u.box(lpos, Vector3(lbw, lbh, lbd), lean_basis, [RoomMesh.DOWN, RoomMesh.FRONT])

			# Occasional neat horizontal stack of 3 flat folios at the bay's right end!
			if has_flat_stack:
				var fy := sy
				var fx := x1 - 0.15
				for k in 3:
					var fh := rng.randf_range(0.036, 0.048)
					var fw := rng.randf_range(0.22, 0.27)
					var fd := depth * rng.randf_range(0.68, 0.80)
					var fcol: Color = BOOK_PALETTE[rng.randi() % BOOK_PALETTE.size()] * shelf_ao
					u.surface(cloth_m if k % 2 == 0 else fabric_m)
					u.colour = _lin(fcol)
					u.box(orig + along * fx + Vector3.UP * (fy + fh * 0.5) + normal * (0.04 + fd * 0.5),
							Vector3(fw, fh - 0.003, fd), basis, [RoomMesh.DOWN, RoomMesh.FRONT])
					if k == 2:
						# Cream page fore-edge hint on the topmost folio.
						u.surface(page_m)
						u.colour = _lin(CREAM_PAGE * 0.88)
						u.box(orig + along * (fx - fw * 0.5 - 0.002) + Vector3.UP * (fy + fh * 0.5)
								+ normal * (0.04 + fd * 0.5), Vector3(0.006, fh * 0.65, fd * 0.90), basis,
								[RoomMesh.DOWN, RoomMesh.FRONT])
					fy += fh


## Horizontal gleaming brass ladder rails running along the upper & lower bookcase galleries plus THREE slender
## oak-and-brass rolling library ladders hooked onto the rails and angled jauntily against the shelves!
static func _rolling_brass_ladders(c: Object) -> void:
	var u: RoomMesh = c.u
	var brass := _brass(c)

	# --- Horizontal Gleaming Brass Guide Rails + Standoff Brackets ---
	var rails: Array = [
		# Upper port gallery rail (`x = -5.06, y = 2.86, z = -7.55 .. +1.45`)
		[Vector3(-HALF_W + 0.54, 2.86, -7.55), Vector3(-HALF_W + 0.54, 2.86, 1.45), Vector3.RIGHT],
		# Upper starboard gallery rail (`x = +5.06, y = 2.86, z = -7.55 .. +4.75`)
		[Vector3(HALF_W - 0.54, 2.86, -7.55), Vector3(HALF_W - 0.54, 2.86, 4.75), Vector3.LEFT],
		# Lower port atrium rail (`x = -5.02, y = -0.80, z = -7.50 .. -1.35`)
		[Vector3(-HALF_W + 0.58, -0.80, -7.50), Vector3(-HALF_W + 0.58, -0.80, -1.35), Vector3.RIGHT],
		# Lower starboard atrium rail (`x = +5.02, y = -0.80, z = -7.50 .. -1.35`)
		[Vector3(HALF_W - 0.58, -0.80, -7.50), Vector3(HALF_W - 0.58, -0.80, -1.35), Vector3.LEFT],
	]
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	for rl: Array in rails:
		var a: Vector3 = rl[0]
		var b: Vector3 = rl[1]
		var out_n: Vector3 = rl[2]
		var rlen := a.distance_to(b)
		var dir := (b - a).normalized()
		# Cylindrical gleaming brass bar.
		var rbasis := Basis(out_n, dir, out_n.cross(dir))
		Shapes.cylinder(u, a, 0.017, rlen, 10, rbasis)
		# Brass end-cap finials & wall standoff brackets every ~1.8 m.
		var br_count := maxi(int(round(rlen / 1.8)), 2)
		for k in br_count + 1:
			var bp := a.lerp(b, float(k) / float(br_count))
			Shapes.beam(u, bp, bp - out_n * 0.14, Vector2(0.022, 0.022))
			Shapes.cylinder(u, bp - out_n * 0.13, 0.028, 0.016, 8, Basis(Vector3.BACK, -out_n.x * PI * 0.5))

	# --- Three Slender Oak-and-Brass Rolling Library Ladders Hooked Cleanly Onto the Rails! ---
	# 1. Port upper gallery ladder (forward-left over the atrium well, immediately visible from every seat!)
	_rolling_ladder(c, Vector3(-HALF_W + 0.54, 2.86, -3.90), MEZZ_Y, Vector3.RIGHT, 0.66)
	# 2. Starboard upper gallery ladder (angled jauntily beside the seating loft!)
	_rolling_ladder(c, Vector3(HALF_W - 0.54, 2.86, -1.55), MEZZ_Y, Vector3.LEFT, 0.66)
	# 3. Lower atrium bookshop ladder (visible down in the bookshop well when peering over the balustrade!)
	_rolling_ladder(c, Vector3(-HALF_W + 0.58, -0.80, -5.05), LOWER_Y, Vector3.RIGHT, 0.62)


static func _rolling_ladder(c: Object, rail_pt: Vector3, floor_y: float, into_room: Vector3, foot_out: float) -> void:
	var u: RoomMesh = c.u
	var brass := _brass(c)
	var wood_soft: Material = c.soft("wood", true)

	var along_wall := Vector3.UP.cross(into_room).normalized()
	var lad_hw := 0.22 # Total ladder width 0.44 m
	var top_pt := rail_pt
	var bot_pt := Vector3(rail_pt.x, floor_y + 0.03, rail_pt.z) + into_room * foot_out
	var spine := top_pt - bot_pt
	var lad_len := spine.length()
	var lad_up := spine.normalized()
	var lad_out := along_wall.cross(lad_up).normalized()
	var lad_basis := Basis(along_wall, lad_up, lad_out)

	# Twin slender honey-oak ladder side stiles (`0.032 x 0.068 m`).
	u.surface(wood_soft)
	u.colour = _lin(OAK_HONEY)
	for sd: float in [-1.0, 1.0]:
		var s_bot := bot_pt + along_wall * (sd * lad_hw)
		var s_top := top_pt + along_wall * (sd * lad_hw) + lad_up * 0.04
		Shapes.beam(u, s_bot, s_top, Vector2(0.030, 0.068), lad_out)

	# Nine flat horizontal honey-oak ladder steps with gleaming slim brass tie-rods underneath each step!
	var rungs := 9
	for k in range(1, rungs + 1):
		var f := float(k) / float(rungs + 1)
		var rp := bot_pt.lerp(top_pt, f)
		u.surface(wood_soft)
		u.colour = _lin(OAK_WARM)
		u.box(rp, Vector3(lad_hw * 2.0 - 0.02, 0.024, 0.082), Basis(along_wall, Vector3.UP, into_room))
		u.surface(brass)
		u.colour = _lin(BRASS)
		Shapes.beam(u, rp - along_wall * lad_hw - Vector3(0.0, 0.022, 0.0),
				rp + along_wall * lad_hw - Vector3(0.0, 0.022, 0.0), Vector2(0.010, 0.010))

	# Curved gleaming brass top-hook carriages & twin roller wheels gripping the brass rail bar, plus brass foot boots!
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	var hook_basis := Basis(into_room, Vector3.UP, along_wall)
	for sd: float in [-1.0, 1.0]:
		var hp := top_pt + along_wall * (sd * lad_hw)
		# Curved brass carriage hook arching neatly over the rail bar!
		Shapes.arch(u, hp + Vector3(0.0, 0.008, 0.0), 0.022, 0.038, 0.022, 12, hook_basis, -0.35, PI + 0.35)
		# Brass roller wheel riding atop the rail.
		Shapes.cylinder(u, hp + Vector3(0.0, 0.028, 0.0) - along_wall * 0.010, 0.024, 0.020, 10,
				Basis(Vector3.UP, along_wall, into_room))
		# Brass caster wheel boots resting squarely on the timber floorboards!
		var fp := bot_pt + along_wall * (sd * lad_hw)
		u.box(fp + Vector3(0.0, 0.02, 0.0), Vector3(0.040, 0.07, 0.080), lad_basis)
		Shapes.cylinder(u, fp + Vector3(0.0, -0.008, 0.0) - along_wall * 0.012, 0.022, 0.024, 8,
				Basis(Vector3.UP, along_wall, into_room))

	# Ladder collision box (strictly along outer walkways, >= 4.2 m from origin!).
	_solid(c, (bot_pt + top_pt) * 0.5, Vector3(lad_hw * 2.0 + 0.08, lad_len, 0.18), lad_basis)


## Down in the lower bookshop atrium well (`y = -3.40 m`, visible whenever you peer over the balustrade!):
## warm-lit oak shopkeeper's reading & display table piled with open folios, stacked books & glowing reading lamp,
## slatted wooden book crates stuffed with angled volumes, tall brass floor lamp, and a cozy cast-iron bookshop stove!
static func _lower_bookshop_atrium_props(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var brass := _brass(c)
	var wood_soft: Material = c.soft("wood", true)

	# --- 1. Warm-Lit Oak Shopkeeper's Reading & Display Table (`center = (0.0, -3.40, -4.85)`, 2.50 x 0.80 x 1.24 m) ---
	var tbl := Vector3(0.0, LOWER_Y, -4.85)
	var tw := 2.50
	var th := 0.80
	var td := 1.24
	s.surface(c.tinted("wood"))
	s.colour = _lin(OAK_HONEY)
	s.box(tbl + Vector3(0.0, th - 0.035, 0.0), Vector3(tw, 0.07, td))
	s.colour = _lin(OAK_WARM)
	s.box(tbl + Vector3(0.0, th - 0.12, 0.0), Vector3(tw - 0.20, 0.11, td - 0.20))
	# Heavy turned oak legs + central lower stretcher beam.
	for lx: float in [-0.94, 0.94]:
		for lz: float in [-0.42, 0.42]:
			u.surface(wood_soft)
			u.colour = _lin(MAHOGANY)
			Shapes.lathe(u, [
				Vector2(0.044, 0.00), Vector2(0.036, 0.14), Vector2(0.052, 0.36),
				Vector2(0.038, 0.60), Vector2(0.048, th - 0.06),
			], tbl + Vector3(lx, 0.0, lz), 10)
		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY_DARK)
		s.box(tbl + Vector3(lx, 0.18, 0.0), Vector3(0.065, 0.065, 0.84))
	s.box(tbl + Vector3(0.0, 0.18, 0.0), Vector3(1.88, 0.075, 0.085))

	# Open leather antique folios (splayed boards + upward-curving ivory cream spreads catching the table lamp!).
	for fl: Array in [[Vector3(-0.48, th, 0.12), 14.0, BOOK_PALETTE[0]],
			[Vector3(0.52, th, -0.16), -22.0, BOOK_PALETTE[4]]]:
		var fp: Vector3 = tbl + (fl[0] as Vector3)
		var frot := Basis(Vector3.UP, deg_to_rad(float(fl[1])))
		var fcol: Color = fl[2]
		u.surface(c.soft("cloth", true))
		u.colour = _lin(fcol)
		u.box(fp + Vector3(0.0, 0.008, 0.0), Vector3(0.52, 0.016, 0.34), frot)
		# Twin gently angled open ivory cream page wings meeting at the central spine gutter!
		u.surface(c.soft("plaster", true))
		u.colour = _lin(CREAM_PAGE)
		for sd: float in [-1.0, 1.0]:
			var wing := frot * Basis(Vector3.BACK, sd * deg_to_rad(8.0))
			u.box(fp + frot * Vector3(sd * 0.12, 0.026, 0.0), Vector3(0.23, 0.022, 0.31), wing)

	# Four colourful stacks of antique hardcover volumes piled across the shopkeeper's reading table!
	_table_book_stack(c, tbl + Vector3(-0.84, th, -0.26), [
		[0.32, 0.048, 0.24, 10.0, BOOK_PALETTE[2]],
		[0.29, 0.044, 0.22, -6.0, BOOK_PALETTE[7]],
		[0.27, 0.040, 0.20, 18.0, BOOK_PALETTE[1]],
		[0.24, 0.036, 0.18, 4.0, BOOK_PALETTE[9]],
	])
	_table_book_stack(c, tbl + Vector3(0.84, th, 0.24), [
		[0.30, 0.045, 0.23, -12.0, BOOK_PALETTE[5]],
		[0.28, 0.042, 0.21, 5.0, BOOK_PALETTE[0]],
		[0.25, 0.038, 0.19, -18.0, BOOK_PALETTE[6]],
	])
	_table_book_stack(c, tbl + Vector3(0.04, th, 0.30), [
		[0.26, 0.040, 0.20, 26.0, BOOK_PALETTE[10]],
		[0.23, 0.036, 0.18, 12.0, BOOK_PALETTE[3]],
	])

	# Glowing Shopkeeper's Emerald-Glass Banker's Lamp perched cleanly at the centre-back of the lower reading table!
	_bankers_lamp(c, tbl + Vector3(0.0, th, -0.22), 0.0, 1.25)

	# --- 2. Stacked Wooden Antiquarian Book Crates Stuffed With Angled Colourful Volumes ---
	var crates: Array = [
		[Vector3(-2.35, LOWER_Y, -3.55), 18.0, false],
		[Vector3(-2.22, LOWER_Y + 0.36, -3.62), -11.0, true],
		[Vector3( 2.25, LOWER_Y, -5.65), -24.0, false],
	]
	for cr: Array in crates:
		var cp: Vector3 = cr[0]
		var crot := Basis(Vector3.UP, deg_to_rad(float(cr[1])))
		var top_cr: bool = cr[2]
		var cw := 0.62 if not top_cr else 0.54
		var ch := 0.36
		var cd := 0.44 if not top_cr else 0.38
		s.surface(c.tinted("wood"))
		s.colour = _lin(OAK_WARM)
		# Bottom plank + four slatted walls of the open wooden book crate.
		s.box(cp + Vector3(0.0, 0.015, 0.0), Vector3(cw, 0.03, cd), crot, [RoomMesh.DOWN])
		for sd: float in [-1.0, 1.0]:
			s.box(cp + crot * Vector3(0.0, ch * 0.5, sd * (cd * 0.5 - 0.015)), Vector3(cw, ch, 0.03), crot)
			s.box(cp + crot * Vector3(sd * (cw * 0.5 - 0.015), ch * 0.5, 0.0), Vector3(0.03, ch, cd - 0.06), crot)
		# Packed colourful spines peeking out of the open wooden crate!
		for k in 6:
			var bx := lerpf(-cw * 0.36, cw * 0.36, float(k) / 5.0)
			var bcol: Color = BOOK_PALETTE[(k * 3 + (2 if top_cr else 0)) % BOOK_PALETTE.size()]
			u.surface(c.soft("cloth" if k % 2 == 0 else "fabric", true))
			u.colour = _lin(bcol)
			var tilt := crot * Basis(Vector3.BACK, deg_to_rad(-8.0 if k == 5 else 2.0))
			u.box(cp + crot * Vector3(bx, 0.24, 0.0), Vector3(0.062, 0.32 + 0.03 * float(k % 3), cd * 0.72), tilt)

	# --- 3. Tall Gleaming Brass Library Floor Lamp Down in the Atrium (`x = +2.55, z = -3.65`) ---
	var fl_at := Vector3(2.55, LOWER_Y, -3.65)
	u.surface(brass)
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [
		Vector2(0.22, 0.00), Vector2(0.20, 0.05), Vector2(0.11, 0.11),
		Vector2(0.025, 0.18), Vector2(0.020, 1.48),
	], fl_at, 14)
	# Warm glowing pleated amber floor-lamp shade (`PieceLamps`, house group).
	lit.surface(c.shade(LAMP_AMBER))
	Shapes.lathe(lit, [
		Vector2(0.28, 1.38), Vector2(0.22, 1.62), Vector2(0.14, 1.78),
		Vector2(0.13, 1.78), Vector2(0.20, 1.62), Vector2(0.26, 1.38),
	], fl_at, 16)

	# --- 4. Cozy Cast-Iron Bookshop Parlor Stove (`x = -2.85, z = -6.55`, y = -3.40) ---
	# Provides gentle visual anchor for the very soft distant `fire` sound bed down in the bookshop!
	var stv := Vector3(-2.85, LOWER_Y, -6.55)
	s.surface(c.tinted("iron"))
	s.colour = _lin(IRON_DARK)
	# Stone hearth pad beneath the cast-iron stove.
	s.box(stv + Vector3(0.0, 0.03, 0.0), Vector3(1.10, 0.06, 1.10), Basis(), [RoomMesh.DOWN])
	# Cylindrical cast-iron stove drum, scrolled feet, domed cap & slender flue pipe rising into the front-port wall.
	Shapes.lathe(s, [
		Vector2(0.32, 0.16), Vector2(0.36, 0.22), Vector2(0.31, 0.28),
		Vector2(0.31, 1.12), Vector2(0.35, 1.18), Vector2(0.24, 1.34), Vector2(0.10, 1.42),
	], stv, 14)
	for a_idx in 4:
		var ang := TAU * float(a_idx) / 4.0 + PI * 0.25
		s.box(stv + Vector3(cos(ang) * 0.26, 0.11, sin(ang) * 0.26), Vector3(0.07, 0.16, 0.07))
	Shapes.cylinder(s, stv + Vector3(0.0, 1.40, 0.0), 0.085, 1.72, 10)
	Shapes.beam(s, stv + Vector3(0.0, 3.06, 0.0), Vector3(-2.85, LOWER_Y + 3.06, FRONT_Z + 0.05), Vector2(0.17, 0.17))
	# Gleaming brass stove rail trim & warm recessed firebox ember glow (`PieceWindows` + flickering `PieceLamps`!).
	u.surface(brass)
	u.colour = _lin(BRASS_DARK)
	Shapes.arch(u, stv + Vector3(0.0, 0.24, 0.0), 0.36, 0.39, 0.025, 16, Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU)
	var stove_n := Vector3(0.45, 0.0, 0.89).normalized()
	var stove_r := Vector3.UP.cross(stove_n).normalized()
	var ember_at := stv + Vector3(0.0, 0.64, 0.0) + stove_n * 0.318
	var gw: Array = c.glows.get("window", [])
	gw.append([ember_at, stove_r * 0.11, Vector3.UP * 0.13, stove_n])
	c.glows["window"] = gw
	lit.surface(c.kit._lamp(STOVE_EMBER, 1.45, 0.24, "accent", true))
	lit.face([
		ember_at - stove_r * 0.08 - Vector3.UP * 0.09 + stove_n * 0.004,
		ember_at + stove_r * 0.08 - Vector3.UP * 0.09 + stove_n * 0.004,
		ember_at + stove_r * 0.05 + Vector3.UP * 0.09 + stove_n * 0.004,
		ember_at - stove_r * 0.05 + Vector3.UP * 0.09 + stove_n * 0.004,
	], stove_n)
	# Tiny cast-iron grate bars across the glowing stove ember door.
	s.surface(c.tinted("iron"))
	s.colour = _lin(IRON_DARK)
	for g_off: float in [-0.055, 0.0, 0.055]:
		s.box(ember_at + stove_r * g_off + stove_n * 0.012, Vector3(0.014, 0.26, 0.014),
				Basis(stove_r, Vector3.UP, stove_n))

	_solid(c, tbl + Vector3(0.0, th * 0.5, 0.0), Vector3(tw, th, td))
	_solid(c, stv + Vector3(0.0, 0.72, 0.0), Vector3(0.80, 1.44, 0.80))
