extends RefCounted

## Dome car 1955 (app/environments/dome_car_1955.env.json; docs/environments/rooms/dome_car_1955.md): a gleaming
## mid-century stainless-steel desert observation dome car crossing moonlit canyon country beneath the Milky Way and
## shooting stars. Dressed over a `cabin` builder (`glazed_roof: true`) and `seats` (`recliner`) rows.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, arches and lathed shapes; no
## people, no real trademarks, no railway liveries or badges.
##
##   dome_1955_lounge  the upper observation deck's 1955 streamliner craft:
##                     - curved brushed-stainless forward dome brow cowl & streamlined screen bulkhead housing with
##                       three horizontal chrome speed-bars, recessed ventilation louvre console, and recessed live
##                       cove valance (`PieceCove`, Turquoise / Desert coral / Warm chrome)
##                     - continuous brushed-chrome fluted window-sill shelf ledges with ribbed under-sill heater
##                       grilles and eight mid-century atomic saucer dome table lamps (`PieceLamps`, `bake_lamps: 2`)
##                       tucked cleanly on the window piers between the panoramic glass bays
##                     - aft stainless-steel perimeter handrail & illuminated step-well balustrade with glass modesty
##                       panels (`PieceGlass`) and glowing step-riser courtesy strips leading down to the lower car
##                     - mid-century lacquered turquoise-and-coral boomerang decorative wall emblems with chrome
##                       atomic starburst pins on the rear bulkhead (pure geometry, no text)
##                     - working chrome sunburst 1955 railway bulkhead clock (`PieceClock`) with 16 alternating radial
##                       sunburst spears tipped with desert-coral and turquoise atomic orbs
##   dome_1955_rows    the observation deck's recliner hardware round `seats` (`recliner`):
##                     - sleek curved charcoal & brushed-chrome shared armrests (`Seats.RECLINER_ARM`, both kept when
##                       the viewer's seat folds away) with inlaid side chrome speed-stripes, curved chrome front
##                       bullnose bumpers, chrome recline levers and flip-top ash-receivers
##                     - crisp mid-century cream woven headrest antimacassars hugging `seats.gd _recliner`'s exact
##                       curve (`bend = -0.35`, `radius = 0.06`), plus tubular chrome seatback grab-bars
##                     - low aisle carpet-edge guide strips (`PieceCove`) glowing gently along the aisle plinths

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")

const PIECES: Array[String] = ["dome_1955_lounge", "dome_1955_rows"]

## Palette (sRGB): 1955 brushed stainless steel, polished chrome, desert turquoise, desert coral, charcoal & warm cream.
const CHROME_BRIGHT := Color(0.88, 0.90, 0.93)
const STEEL_SATIN := Color(0.70, 0.75, 0.79)
const TURQUOISE := Color(0.14, 0.48, 0.50)
const TURQUOISE_DEEP := Color(0.10, 0.34, 0.38)
const CORAL := Color(0.78, 0.28, 0.21)
const CHARCOAL := Color(0.20, 0.23, 0.26)
const CHARCOAL_CAP := Color(0.11, 0.125, 0.145)
const CREAM_LINEN := Color(0.93, 0.90, 0.83)
const LAMP_GLOW := Color(1.0, 0.82, 0.56)
const STEP_GLOW := Color(1.0, 0.78, 0.48)

## Forward curved stainless dome brow canopy depths from the front bulkhead (metres): sweeps smoothly from the
## centre crown back to the first arched dome rib along the haunches, shielding the glass canopy from screen glare.
const BROW_CROWN := 1.54
const BROW_SIDE := 2.08


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"dome_1955_lounge":
			_lounge(c)
		"dome_1955_rows":
			_rows(c)


# --- The 1955 observation dome lounge ---------------------------------------------------------------------------------

static func _lounge(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_screen_bulkhead(c, q)
	_window_ledges_and_lamps(c, q)
	_aft_stepwell_and_rail(c, q)
	_aft_bulkhead(c, q)


## Streamlined 1955 brushed-stainless & chrome forward dome brow cowl, picture bulkhead housing with horizontal chrome
## speed-bars, lower louvred air-conditioning console, and recessed live cove valance (`PieceCove`).
static func _screen_bulkhead(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(1.88, 1.0575))
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var wall_h := float(q["wall_height"])
	var sc_x := sc_xf.origin.x
	var sc_y := sc_xf.origin.y
	var sc_z := sc_xf.origin.z
	var sw := sc_sz.x
	var sh := sc_sz.y
	var hsw := sw * 0.5
	var hsh := sh * 0.5
	var brow_side_z := fz + BROW_SIDE

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# 1. Swept curved brushed-stainless forward dome brow canopy hugging the front arch, flowing seamlessly from the
	#    centre crown (fz + BROW_CROWN) back along the arch shoulders into the first structural rib (fz + BROW_SIDE).
	var roof: Array = Cabin._roof(q)
	var rpts: PackedVector2Array = roof[0]
	var rns: PackedVector2Array = roof[1]
	var th := maxf(float(q["top_half"]), 0.1)
	var brow_zs := PackedFloat32Array()
	for i in rpts.size():
		var u_arch := clampf(absf((rpts[i].x - cx) / th), 0.0, 1.0)
		var frac := 0.5 - 0.5 * cos(PI * u_arch)
		brow_zs.append(fz + lerpf(BROW_CROWN, BROW_SIDE, frac))
	s.surface(c.tinted("plastic"))
	s.colour = STEEL_SATIN.srgb_to_linear()
	var inner_f := PackedVector3Array()
	var inner_b := PackedVector3Array()
	var inner_n := PackedVector3Array()
	var lip_in := PackedVector3Array()
	var lip_out := PackedVector3Array()
	var lip_n := PackedVector3Array()
	var brow_t := 0.045
	for i in rpts.size():
		var bz_i := brow_zs[i]
		var p_out := rpts[i] + rns[i] * 0.008
		var p_in := rpts[i] + rns[i] * brow_t
		inner_f.append(Vector3(p_in.x, p_in.y, fz + 0.01))
		inner_b.append(Vector3(p_in.x, p_in.y, bz_i))
		inner_n.append(Vector3(rns[i].x, rns[i].y, 0.0))
		lip_out.append(Vector3(p_out.x, p_out.y, bz_i))
		lip_in.append(Vector3(p_in.x, p_in.y, bz_i))
		lip_n.append(Vector3.BACK)
	s.strip(inner_f, inner_b, inner_n)
	s.strip(lip_out, lip_in, lip_n)

	# 2. Streamlined lower bulkhead console below the screen (turquoise lacquered enamel body + brushed-steel top deck
	#    and recessed charcoal ventilation louvre bay).
	var console_h := sc_y - hsh - 0.14
	var console_d := 0.28
	var console_z := fz + console_d * 0.5
	s.colour = TURQUOISE.srgb_to_linear()
	s.box(Vector3(cx, console_h * 0.5, console_z), Vector3(hw * 2.0 - 0.08, console_h, console_d), Basis(),
			[RoomMesh.DOWN, RoomMesh.FRONT])
	# Recessed upper screen bulkhead backing panel (deep desert turquoise framing the brushed-stainless flanks).
	var back_d := maxf(sc_z - fz - 0.03, 0.08)
	var back_z := fz + back_d * 0.5
	s.colour = TURQUOISE_DEEP.srgb_to_linear()
	s.box(Vector3(sc_x, sc_y, back_z), Vector3(sw + 0.36, sh + 0.22, back_d), Basis(), [RoomMesh.FRONT])
	# Stepped satin-stainless bulkhead cheek pilasters flanking the screen housing cleanly out to the curved walls.
	s.colour = STEEL_SATIN.srgb_to_linear()
	var cheek_w := maxf(hw - (hsw + 0.22), 0.3)
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (hsw + 0.22 + cheek_w * 0.5)
		var ch := minf(_roof_y(q, cx + side * (hsw + 0.22 + cheek_w * 0.8)) - console_h - 0.06, 1.38)
		s.box(Vector3(px, console_h + ch * 0.5, fz + 0.06), Vector3(cheek_w, ch, 0.12), Basis(), [RoomMesh.FRONT])

	# Dark charcoal recessed screen mask bezel and lower ventilation grille recess.
	s.surface(c.tinted("iron"))
	s.colour = CHARCOAL.srgb_to_linear()
	var bz := sc_z - 0.028
	var bw := 0.065
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(sc_x + side * (hsw + bw * 0.5), sc_y, bz), Vector3(bw, sh + bw * 2.0, 0.06))
	s.box(Vector3(sc_x, sc_y + hsh + bw * 0.5, bz), Vector3(sw, bw, 0.06))
	s.box(Vector3(sc_x, sc_y - hsh - bw * 0.5, bz), Vector3(sw, bw, 0.06))
	# Lower bulkhead recessed dark kick-plinth and twin air-conditioning louvre bays.
	s.box(Vector3(cx, 0.055, fz + console_d + 0.01), Vector3(hw * 2.0 - 0.1, 0.11, 0.02), Basis(), [RoomMesh.DOWN])
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * 0.92
		s.box(Vector3(gx, 0.62, fz + console_d + 0.008), Vector3(1.16, 0.38, 0.02), Basis(), [RoomMesh.FRONT])

	# 3. Gleaming polished-chrome streamlined trim: curved dome brow arch lip, screen surround rim, three horizontal
	#    speed-bars across both screen flanks, console counter lip, and ventilation grille chrome slats.
	u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	# Curved chrome moulding strip along the swept aft lip of the arched dome brow.
	var rib_a := PackedVector3Array()
	var rib_b := PackedVector3Array()
	var rib_n := PackedVector3Array()
	for i in rpts.size():
		var p := rpts[i] + rns[i] * (brow_t + 0.012)
		var bz_i := brow_zs[i]
		rib_a.append(Vector3(p.x, p.y, bz_i - 0.055))
		rib_b.append(Vector3(p.x, p.y, bz_i + 0.015))
		rib_n.append(Vector3(rns[i].x, rns[i].y, 0.0))
	u.strip(rib_a, rib_b, rib_n)
	# Crisp chrome outer pin-frame hugging the charcoal picture bezel (never intruding into picture bounds).
	var fr_z := sc_z - 0.004
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(sc_x + side * (hsw + bw + 0.012), sc_y, fr_z), Vector3(0.024, sh + bw * 2.0 + 0.048, 0.024))
	u.box(Vector3(sc_x, sc_y + hsh + bw + 0.012, fr_z), Vector3(sw + bw * 2.0, 0.024, 0.024))
	u.box(Vector3(sc_x, sc_y - hsh - bw - 0.012, fr_z), Vector3(sw + bw * 2.0, 0.024, 0.024))
	# Three horizontal streamlined chrome speed-bars sweeping outward on each flank beside the picture!
	var flank_x0 := hsw + bw + 0.06
	var flank_x1 := hw - 0.14
	var flank_w := maxf(flank_x1 - flank_x0, 0.25)
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var by := sc_y - 0.28 + 0.28 * k
			var len_k := flank_w * (0.94 - 0.1 * absf(float(k) - 1.0))
			var bx := cx + side * (flank_x0 + len_k * 0.5)
			u.box(Vector3(bx, by, fz + 0.135), Vector3(len_k, 0.024, 0.022))
			# Tapered chrome speed-bullet nose cap at the inner tip of each bar.
			u.box(Vector3(cx + side * (flank_x0 + 0.01), by, fz + 0.142), Vector3(0.036, 0.032, 0.024))
	# Continuous brushed-chrome console counter bullnose rail + twin speed-bars across the full bulkhead width.
	u.box(Vector3(cx, console_h + 0.016, fz + console_d + 0.012), Vector3(hw * 2.0 - 0.04, 0.034, 0.044))
	for dy: float in [0.98, 1.08, 1.18]:
		if dy < console_h - 0.08:
			u.box(Vector3(cx, dy, fz + console_d + 0.012), Vector3(hw * 2.0 - 0.12, 0.018, 0.018))
	# Chrome horizontal louvre slats across the twin lower ventilation bays.
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * 0.92
		for k in 6:
			u.box(Vector3(gx, 0.48 + 0.056 * k, fz + console_d + 0.022), Vector3(1.1, 0.014, 0.014))
	# Subtle desert-coral enamel accent strip nested beneath the screen bezel.
	u.surface(c.soft("plastic", true))
	u.colour = CORAL.srgb_to_linear()
	u.box(Vector3(sc_x, sc_y - hsh - bw - 0.048, fz + console_d + 0.008), Vector3(sw + 0.16, 0.036, 0.02))

	# 4. Recessed glowing mid-century cove valance (`PieceCove`, live colour via Dome coves setting, cove_floor 0.45):
	#    curved light wash under the forward dome brow, plus twin vertical picture coves and horizontal console wash.
	cove.surface(c.kit.cove_material())
	var cove_base := Color(0.95, 0.97, 0.98).srgb_to_linear()
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.95)
	# Curved cove ribbon tucked under the swept aft lip of the stainless dome brow.
	var ca := PackedVector3Array()
	var cb := PackedVector3Array()
	var cn := PackedVector3Array()
	for i in range(1, rpts.size() - 1):
		var p := rpts[i] + rns[i] * (brow_t + 0.006)
		var bz_i := brow_zs[i]
		ca.append(Vector3(p.x, p.y, bz_i - 0.24))
		cb.append(Vector3(p.x, p.y, bz_i - 0.06))
		cn.append(Vector3(rns[i].x, rns[i].y, 0.0))
	cove.strip(ca, cb, cn)
	# Vertical recessed cove strips flanking the screen surround and horizontal wash under the picture.
	for side: float in [-1.0, 1.0]:
		var vx := sc_x + side * (hsw + bw + 0.075)
		cove.face([Vector3(vx - 0.032, sc_y - hsh - 0.04, fz + back_d + 0.006),
				Vector3(vx + 0.032, sc_y - hsh - 0.04, fz + back_d + 0.006),
				Vector3(vx + 0.032, sc_y + hsh + 0.04, fz + back_d + 0.006),
				Vector3(vx - 0.032, sc_y + hsh + 0.04, fz + back_d + 0.006)], Vector3.BACK)
	cove.face([Vector3(sc_x - hsw - 0.1, console_h + 0.045, fz + back_d + 0.006),
			Vector3(sc_x + hsw + 0.1, console_h + 0.045, fz + back_d + 0.006),
			Vector3(sc_x + hsw + 0.1, console_h + 0.115, fz + back_d + 0.006),
			Vector3(sc_x - hsw - 0.1, console_h + 0.115, fz + back_d + 0.006)], Vector3.BACK)
	# Subtle cornice cove ribbons running along the upper side walls just under the glass dome springing!
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.72)
	var aft_z := float(q["back_z"])
	for side: float in [-1.0, 1.0]:
		var wx := cx + side * (hw - 0.052)
		var wy0 := wall_h - 0.072
		var wy1 := wall_h - 0.046
		var n := Vector3(-side, 0.0, 0.0)
		var p0 := Vector3(wx, wy0, brow_side_z + 0.06)
		var p1 := Vector3(wx, wy0, aft_z - 0.25)
		var p2 := Vector3(wx, wy1, aft_z - 0.25)
		var p3 := Vector3(wx, wy1, brow_side_z + 0.06)
		if side < 0.0:
			cove.face([p0, p1, p2, p3], n)
		else:
			cove.face([p1, p0, p3, p2], n)
	cove.colour = Color.WHITE
	s.colour = Color.WHITE
	u.colour = Color.WHITE

	# Clean physics collision box for the forward screen console (strictly inside cabin, > 3.8 m from viewer's seat).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, console_h * 0.5, fz + console_d * 0.5),
			Vector3(hw * 2.0 - 0.08, console_h, console_d), Basis()))


## Continuous brushed-chrome fluted window-sill shelf ledges, ribbed under-sill heater grilles, stainless kick-strips,
## and eight mid-century 1955 atomic saucer dome table lamps standing at the window piers (`PieceLamps`, `bake_lamps`).
static func _window_ledges_and_lamps(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var sill := float(q["window_sill"])
	var wzs: Array = q["window_zs"]
	var marks: Array[float] = Cabin._bay_marks(q)
	if wzs.is_empty():
		return
	var z0 := fz + 0.34
	var z1 := bz - 0.16
	var span := z1 - z0
	var mid_z := (z0 + z1) * 0.5
	var shelf_d := 0.115

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit

	# Continuous dark-charcoal rubber inlay top on the window-sill shelves and recessed floor baseboard grilles.
	s.surface(c.tinted("iron"))
	s.colour = CHARCOAL.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var wall_x := cx + side * hw
		var sx := wall_x - side * (shelf_d * 0.5)
		s.box(Vector3(sx, sill - 0.018, mid_z), Vector3(shelf_d - 0.015, 0.026, span))
		# Under-dado slim steam-heat convector box flush along each lower wall.
		s.box(Vector3(wall_x - side * 0.032, 0.18, mid_z), Vector3(0.06, 0.24, span - 0.4), Basis(), [RoomMesh.DOWN])

	# Gleaming brushed-chrome fluted shelf fascia (three crisp longitudinal speed-flutes + brackets + heater ribs).
	u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var wall_x := cx + side * hw
		var edge_x := wall_x - side * shelf_d
		# Three parallel chrome speed-flutes running the length of the shelf edge.
		for k in 3:
			var fy := sill - 0.044 + 0.02 * k
			var fx := edge_x - side * (0.008 if k == 1 else 0.002)
			u.box(Vector3(fx, fy, mid_z), Vector3(0.018, 0.013, span + 0.02))
		# Slim chrome dado baseboard strip and heater-grille fins.
		u.box(Vector3(wall_x - side * 0.066, 0.055, mid_z), Vector3(0.01, 0.085, span - 0.36), Basis(), [RoomMesh.DOWN])
		for k in 3:
			u.box(Vector3(wall_x - side * 0.066, 0.15 + 0.052 * k, mid_z), Vector3(0.012, 0.012, span - 0.46))
		# Cast-chrome shelf support corbels aligned beneath every structural rib.
		for mz: float in marks:
			if mz > z0 + 0.15 and mz < z1 - 0.15:
				u.box(Vector3(wall_x - side * (shelf_d * 0.45), sill - 0.08, mz), Vector3(shelf_d * 0.85, 0.06, 0.026))
		# Clean physics box enclosing each side window-sill shelf (inside cabin, > 1.1 m from viewer's seat).
		c.shapes.append(PhysicsShapes.box(Vector3(wall_x - side * (shelf_d * 0.5), sill - 0.025, mid_z),
				Vector3(shelf_d, 0.06, span), Basis()))

	# Mid-century 1955 atomic saucer dome table lamps standing on the window-sill shelves at the four interior ribs
	# between the panoramic windows (tucked cleanly against the piers so they never obstruct the desert view!).
	var lamp_zs: Array[float] = []
	for mz: float in marks:
		if mz > fz + 1.4 and mz < bz - 0.5:
			lamp_zs.append(mz)
	lit.surface(c.shade(LAMP_GLOW))
	var lamp_idx := 0
	for lz: float in lamp_zs:
		for side: float in [-1.0, 1.0]:
			var wall_x := cx + side * hw
			var lx := wall_x - side * 0.082
			var base_at := Vector3(lx, sill - 0.004, lz)
			# Brushed-chrome weighted saucer base, slender tapered stem, and finial crown tip.
			u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
			u.colour = CHROME_BRIGHT.srgb_to_linear()
			Shapes.lathe(u, [Vector2(0.044, 0.0), Vector2(0.044, 0.012), Vector2(0.032, 0.024),
					Vector2(0.012, 0.034), Vector2(0.009, 0.175), Vector2(0.02, 0.19)], base_at, 10)
			# Iconic 1955 flared atomic saucer dome shade (alternating desert coral & turquoise enamel!).
			u.surface(c.soft("plastic", true))
			var shade_col := CORAL if (lamp_idx % 2 == 0) else TURQUOISE
			u.colour = shade_col.srgb_to_linear()
			Shapes.lathe(u, [Vector2(0.088, 0.168), Vector2(0.092, 0.176), Vector2(0.072, 0.214),
					Vector2(0.036, 0.236), Vector2(0.0, 0.244)], base_at, 12)
			# Gleaming chrome finial button on top of the atomic dome shade.
			u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
			u.colour = CHROME_BRIGHT.srgb_to_linear()
			Shapes.lathe(u, [Vector2(0.014, 0.242), Vector2(0.016, 0.252), Vector2(0.0, 0.262)], base_at, 8)
			# Warm opal-glass dome diffuser tucked cleanly under the metal saucer shade (`PieceLamps`, house group).
			Shapes.lathe(lit, [Vector2(0.0, 0.114), Vector2(0.036, 0.122), Vector2(0.054, 0.146),
					Vector2(0.050, 0.172)], base_at, 10)
			# Register the two middle-bay lamps for the room's baked lightmap & warm stand-in fill (`bake_lamps: 2`).
			if absf(lz) < 1.2:
				c.lamps.append([base_at + Vector3(-side * 0.08, 0.14, 0.0), LAMP_GLOW, 0.72])
		lamp_idx += 1
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Aft stainless-steel perimeter handrail & illuminated step-well balustrade leading down to the lower car.
static func _aft_stepwell_and_rail(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var well_w := 0.96
	var hwell := well_w * 0.5
	var z_front := bz - 1.02
	var z_back := bz - 0.04
	var rail_h := 0.94
	var well_len := z_back - z_front
	var well_mid := (z_front + z_back) * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	# 1. Stepped turquoise-enamel knee walls flanking the aft stairwell opening, capped in polished chrome.
	s.surface(c.tinted("plastic"))
	s.colour = TURQUOISE_DEEP.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var kx := cx + side * (hwell + 0.045)
		s.box(Vector3(kx, 0.36, well_mid), Vector3(0.09, 0.72, well_len), Basis(), [RoomMesh.DOWN])
	# Recessed stairwell floor pad with descending dark rubber stair treads and stainless stair nosings!
	s.surface(c.tinted("iron"))
	s.colour = Color(0.045, 0.05, 0.06).srgb_to_linear()
	s.box(Vector3(cx, 0.008, well_mid), Vector3(well_w - 0.02, 0.016, well_len - 0.04), Basis(), [RoomMesh.DOWN])
	# Four descending ribbed stair-tread bars leading aft toward the lower-level vestibule portal.
	u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	for step in 4:
		var sz := z_front + 0.1 + 0.24 * step
		u.box(Vector3(cx, 0.019, sz), Vector3(well_w - 0.06, 0.01, 0.032))
	# Warm recessed step-well courtesy light lenses embedded inside both knee walls facing into the stair opening.
	lit.surface(c.shade(STEP_GLOW))
	for side: float in [-1.0, 1.0]:
		var lx := cx + side * (hwell - 0.002)
		for sz: float in [z_front + 0.26, z_front + 0.72]:
			var n := Vector3(-side, 0.0, 0.0)
			var p0 := Vector3(lx, 0.14, sz - 0.08)
			var p1 := Vector3(lx, 0.14, sz + 0.08)
			var p2 := Vector3(lx, 0.21, sz + 0.08)
			var p3 := Vector3(lx, 0.21, sz - 0.08)
			if side > 0.0:
				lit.face([p0, p1, p2, p3], n)
			else:
				lit.face([p1, p0, p3, p2], n)
	# Soft cove wash along the top inner lip of the step-well knee walls (`PieceCove`).
	cove.surface(c.kit.cove_material())
	var col_lin := Color(0.95, 0.97, 0.98).srgb_to_linear()
	cove.colour = Color(col_lin.r, col_lin.g, col_lin.b, 0.92)
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * (hwell + 0.004)
		var n := Vector3(-side, 0.0, 0.0)
		var q0 := Vector3(gx, 0.65, z_front + 0.04)
		var q1 := Vector3(gx, 0.65, z_back - 0.04)
		var q2 := Vector3(gx, 0.71, z_back - 0.04)
		var q3 := Vector3(gx, 0.71, z_front + 0.04)
		if side > 0.0:
			cove.face([q0, q1, q2, q3], n)
		else:
			cove.face([q1, q0, q3, q2], n)
	cove.colour = Color.WHITE

	# 2. Gleaming tubular stainless-steel perimeter handrail & balustrade framing the aft deck on both sides of the
	#    step-well opening (from side walls to stairwell corners, then returning aft to the rear bulkhead).
	#    Note: rotating +Y to +X about +Z is -PI/2 (right-hand rule).
	var basis_x := Basis(Vector3.BACK, -PI * 0.5)
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
	for side: float in [-1.0, 1.0]:
		var x_inner := cx + side * (hwell + 0.045)
		var x_outer := cx + side * (hw - 0.06)
		var span_x := absf(x_outer - x_inner)
		var x_lo := minf(x_inner, x_outer)
		var x_mid := (x_inner + x_outer) * 0.5
		# Polished tubular top handrail across the transverse balustrade and along the step-well cheek!
		Shapes.cylinder(u, Vector3(x_lo, rail_h, z_front), 0.022, span_x, 10, basis_x)
		Shapes.cylinder(u, Vector3(x_inner, rail_h, z_front), 0.022, well_len, 10, basis_z)
		# Angled chrome descending stair handrail inside the stairwell cheeks leading down toward the lower deck!
		Shapes.beam(u, Vector3(cx + side * (hwell - 0.045), 0.78, z_front + 0.08),
				Vector3(cx + side * (hwell - 0.045), 0.34, z_back - 0.06), Vector2(0.026, 0.026))
		# Three sleek lower horizontal chrome speed-bars spanning each balustrade wing.
		for frac: float in [0.34, 0.55, 0.76]:
			u.box(Vector3(x_mid, rail_h * frac, z_front), Vector3(span_x, 0.018, 0.018))
		# Vertical tubular chrome stanchion posts with stepped floor flanges.
		for px: float in [x_inner, (x_inner + x_outer) * 0.5, x_outer - side * 0.04]:
			Shapes.cylinder(u, Vector3(px, 0.0, z_front), 0.02, rail_h, 10)
			Shapes.lathe(u, [Vector2(0.046, 0.0), Vector2(0.046, 0.016), Vector2(0.026, 0.03)],
					Vector3(px, 0.0, z_front), 10)
		# Corner finial spheres crowning the stairwell newel posts + aft wall-anchor stanchions.
		Shapes.lathe(u, [Vector2(0.022, rail_h), Vector2(0.032, rail_h + 0.016), Vector2(0.022, rail_h + 0.034),
				Vector2(0.0, rail_h + 0.04)], Vector3(x_inner, 0.0, z_front), 10)
		Shapes.cylinder(u, Vector3(x_inner, 0.72, z_back - 0.04), 0.02, rail_h - 0.72, 8)
		# Frosted tinted safety glass modesty panel framed cleanly inside the aft balustrade (behind the viewer!).
		c.glass.surface(c.mat("tin"))
		c.glass.box(Vector3(x_mid, 0.48, z_front), Vector3(span_x - 0.14, 0.62, 0.012))
		# Clean physics collision box for each aft balustrade wing & step-well knee wall.
		c.shapes.append(PhysicsShapes.box(Vector3(x_mid, rail_h * 0.5, z_front), Vector3(span_x, rail_h, 0.08), Basis()))
		c.shapes.append(PhysicsShapes.box(Vector3(x_inner, rail_h * 0.5, well_mid), Vector3(0.11, rail_h, well_len),
				Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Rear bulkhead: recessed stainless lower-car stairwell portal arch, twin mid-century boomerang decorative wall
## emblems (pure geometry, no text), curved aft roof arch trim, and working chrome sunburst 1955 railway clock.
static func _aft_bulkhead(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis_aft := Basis(Vector3.UP, PI)

	# 1. Recessed lower-deck stairwell portal arch centered at the back of the step-well (warm recessed lower-deck
	#    vestibule transom strip + streamlined chrome portal framing — reads unmistakably as stairs to the lower car).
	var port_w := 0.88
	var port_h := 1.72
	s.surface(c.tinted("iron"))
	s.colour = Color(0.05, 0.06, 0.07).srgb_to_linear()
	s.box(Vector3(cx, port_h * 0.5, bz - 0.012), Vector3(port_w, port_h, 0.024), Basis(), [RoomMesh.DOWN, RoomMesh.BACK])
	# Warm lower-car stairwell transom light bar tucked just inside the portal lintel (`PieceLamps`, house group).
	var lit: RoomMesh = c.lit
	lit.surface(c.shade(STEP_GLOW))
	lit.face([Vector3(cx - port_w * 0.42, port_h - 0.14, bz - 0.028),
			Vector3(cx + port_w * 0.42, port_h - 0.14, bz - 0.028),
			Vector3(cx + port_w * 0.42, port_h - 0.05, bz - 0.028),
			Vector3(cx - port_w * 0.42, port_h - 0.05, bz - 0.028)], Vector3.FORWARD)
	u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * (port_w * 0.5 + 0.028), port_h * 0.5, bz - 0.025), Vector3(0.056, port_h, 0.04))
	u.box(Vector3(cx, port_h + 0.028, bz - 0.025), Vector3(port_w + 0.112, 0.056, 0.045))
	# Three crisp horizontal chrome vestibule speed-bars above the portal lintel.
	for k in 3:
		u.box(Vector3(cx, port_h + 0.095 + 0.036 * k, bz - 0.02), Vector3(port_w + 0.36 - 0.12 * k, 0.016, 0.018))

	# 2. Chrome sunburst 1955 railway bulkhead clock (`PieceClock`, live wall time) centered high on the aft bulkhead!
	var clk_y := 2.34
	var clk_r := 0.21
	var clk_z := bz - 0.045
	Shapes.arch(u, Vector3(cx, clk_y, clk_z), clk_r, clk_r + 0.038, 0.055, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# 16 alternating long and short sculpted 1955 atomic sunburst rays radiating around the chrome bezel.
	for k in 16:
		var ang := TAU * float(k) / 16.0
		var long_ray := (k % 2 == 0)
		var r0 := clk_r + 0.035
		var rlen := 0.19 if long_ray else 0.105
		var mid_r := r0 + rlen * 0.5
		var pos := Vector3(cx + sin(ang) * mid_r, clk_y + cos(ang) * mid_r, clk_z + 0.008)
		u.box(pos, Vector3(0.016 if long_ray else 0.011, rlen, 0.014), Basis(Vector3.BACK, -ang))
	# Alternating desert-coral and turquoise atomic orbs crowning the 8 long sunburst spears!
	u.surface(c.soft("plastic", true))
	for k in 8:
		var ang := TAU * float(k) / 8.0
		var tip_r := clk_r + 0.235
		u.colour = (CORAL if k % 2 == 0 else TURQUOISE).srgb_to_linear()
		u.rounded_box(Vector3(cx + sin(ang) * tip_r, clk_y + cos(ang) * tip_r, clk_z + 0.004),
				Vector3(0.042, 0.042, 0.034), 0.014, Transform3D(), 1)
	# Live illuminated clock dial (`PieceClock`, hands updated to real system time).
	c.clocks.append([Vector3(cx, clk_y, bz - 0.066), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# 3. Mid-century 1955 boomerang decorative wall emblems flanking the aft stairwell portal (pure geometry, no text!).
	for side: float in [-1.0, 1.0]:
		var ex := cx + side * (hw * 0.58)
		var ey := 1.48
		# Backing sleek brushed-chrome oval/lozenge shield plaque.
		u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
		u.colour = CHROME_BRIGHT.srgb_to_linear()
		u.box(Vector3(ex, ey, bz - 0.014), Vector3(0.68, 0.022, 0.018))
		u.box(Vector3(ex, ey - 0.055, bz - 0.014), Vector3(0.54, 0.016, 0.016))
		u.box(Vector3(ex, ey + 0.055, bz - 0.014), Vector3(0.54, 0.016, 0.016))
		# Sculpted sweeping boomerang chevrons in lacquered desert coral & turquoise!
		u.surface(c.soft("plastic", true))
		var tilt_hi := Basis(Vector3.BACK, side * 0.58)
		var tilt_lo := Basis(Vector3.BACK, -side * 0.42)
		# Upper boomerang wing (desert coral) + lower swept wing (desert turquoise), meeting at an atomic apex.
		u.colour = CORAL.srgb_to_linear()
		u.box(Vector3(ex - side * 0.05, ey + 0.11, bz - 0.03), Vector3(0.36, 0.068, 0.022), tilt_hi)
		u.box(Vector3(ex + side * 0.11, ey + 0.03, bz - 0.03), Vector3(0.24, 0.054, 0.022), tilt_lo)
		u.colour = TURQUOISE.srgb_to_linear()
		u.box(Vector3(ex - side * 0.02, ey - 0.06, bz - 0.026), Vector3(0.32, 0.058, 0.018), tilt_lo)
		u.box(Vector3(ex + side * 0.12, ey - 0.13, bz - 0.026), Vector3(0.22, 0.046, 0.018), tilt_hi)
		# Three gleaming four-point atomic chrome starburst diamond pins floating beside the boomerang.
		u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
		u.colour = CHROME_BRIGHT.srgb_to_linear()
		for star: Array in [[ex - side * 0.24, ey + 0.16, 0.068], [ex + side * 0.24, ey + 0.13, 0.048],
				[ex - side * 0.18, ey - 0.17, 0.052]]:
			var sx := float(star[0])
			var sy := float(star[1])
			var sl := float(star[2])
			u.box(Vector3(sx, sy, bz - 0.032), Vector3(sl, sl * 0.22, 0.014))
			u.box(Vector3(sx, sy, bz - 0.032), Vector3(sl * 0.22, sl, 0.014))

	# 4. Curved brushed-chrome aft arch crown rib framing the rear glass-dome seam.
	var roof: Array = Cabin._roof(q)
	var rpts: PackedVector2Array = roof[0]
	var rns: PackedVector2Array = roof[1]
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	var rn := PackedVector3Array()
	for i in rpts.size():
		var p := rpts[i] + rns[i] * 0.03
		ra.append(Vector3(p.x, p.y, bz - 0.07))
		rb.append(Vector3(p.x, p.y, bz - 0.005))
		rn.append(Vector3(rns[i].x, rns[i].y, 0.0))
	u.strip(ra, rb, rn)
	s.colour = Color.WHITE
	u.colour = Color.WHITE


# --- The 1955 observation recliner rows' hardware ---------------------------------------------------------------------

## Sleek curved brushed-chrome & charcoal shared armrests (`Seats.RECLINER_ARM`, keeping both around the viewer's own
## folded seat), crisp mid-century cream headrest antimacassars hugging the curved recliner profile, chrome rear
## seatback grab-bars, and low aisle floor-guide strips (`PieceCove`).
static func _rows(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var slots: Array = Cabin.seat_slots_for(c.builder_params)
	if slots.is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	var cx := float(q["cx"])
	var pitch := float(q["seat_pitch"])
	var arm_w := Seats.RECLINER_ARM
	var arm_h := 0.56
	var arm_d := 0.58
	var arm_z := -0.07
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15.0)), Vector3(0.0, 0.46, 0.12))

	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# Collect unique armrest positions across each row block (between seats and at both ends of each block).
	var arm_places := {}
	var aisle_arms: Array = []
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		var o := xf.origin
		var row_key := roundi(o.z * 100.0)
		for side: float in [-1.0, 1.0]:
			var ax := o.x + side * pitch * 0.5
			var k := "%d:%d" % [row_key, roundi(ax * 100.0)]
			if not arm_places.has(k):
				arm_places[k] = Vector3(ax, o.y, o.z)
				if absf(ax - cx) < float(q["aisle"]) * 0.5 + 0.12:
					aisle_arms.append([Vector3(ax, o.y, o.z), -1.0 if ax > cx else 1.0])

	# 1. Sculpted 1955 charcoal armrest pedestals with softly rounded padded caps.
	u.surface(c.soft("plastic", true))
	for at: Vector3 in arm_places.values():
		u.colour = CHARCOAL.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h * 0.5, arm_z), Vector3(arm_w, arm_h, arm_d), Basis(), [RoomMesh.DOWN])
		u.colour = CHARCOAL_CAP.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(arm_w + 0.012, 0.044, arm_d + 0.024), 0.016,
				Transform3D(Basis(), at + Vector3(0.0, arm_h + 0.018, arm_z - 0.01)), 1, Vector3i.ZERO, 0.0,
				[RoomMesh.DOWN])

	# 2. Gleaming brushed-chrome streamliner armrest hardware: curved waterfall front bullnose bumper, inlaid twin
	#    horizontal side speed-stripes, chrome recline paddle and flip-top ash-receiver lid.
	u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	for at: Vector3 in arm_places.values():
		# Vertical curved chrome waterfall bullnose wrapping the front of each armrest pedestal.
		u.rounded_box(Vector3.ZERO, Vector3(arm_w + 0.008, arm_h * 0.82, 0.036), 0.014,
				Transform3D(Basis(), at + Vector3(0.0, arm_h * 0.52, arm_z - arm_d * 0.5 - 0.006)), 1)
		# Twin horizontal inlaid chrome speed-stripes along both flanks of the armrest body.
		for sy: float in [0.24, 0.34]:
			u.box(at + Vector3(0.0, sy, arm_z), Vector3(arm_w + 0.014, 0.016, arm_d * 0.86))
		# Classic 1955 chrome flip-lid ash-receiver and slim recline button on top of the armrest.
		u.box(at + Vector3(0.0, arm_h + 0.042, arm_z - arm_d * 0.33), Vector3(0.062, 0.008, 0.076))
		u.box(at + Vector3(0.0, arm_h + 0.042, arm_z - arm_d * 0.11), Vector3(0.024, 0.012, 0.032))

	# 3. Crisp curved mid-century cream headrest antimacassars hugging `seats.gd _recliner`'s exact headrest curve
	#    (`bend = -0.35`, `radius = 0.062`) cleanly proud of the pillow envelope so zero upholstery z-fights through.
	var wi := pitch - arm_w - 0.01
	u.surface(c.soft("cloth", true))
	u.colour = CREAM_LINEN.srgb_to_linear()
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.rounded_box(Vector3(0.0, 0.649, -0.011), Vector3(wi - 0.14, 0.256, 0.156), 0.062, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])

	# 4. Tubular brushed-chrome rear seatback grab-bars across the back of every seat shell (for steady passage down
	#    the dome aisle while the train rolls across the desert!).
	u.surface(c.shiny("chrome", 0.96, 0.84, 0.10))
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	var grab_w := wi - 0.12
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.box(t_world * Vector3(0.0, 0.56, 0.148), Vector3(grab_w, 0.022, 0.022), t_world.basis)
		for side: float in [-1.0, 1.0]:
			u.box(t_world * Vector3(side * (grab_w * 0.5 - 0.012), 0.56, 0.128), Vector3(0.022, 0.024, 0.036),
					t_world.basis)

	# 5. Low aisle floor-guide light strips along the aisle-facing base of the aisle armrests (`PieceCove`, live colour).
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.95, 0.97, 0.98).srgb_to_linear()
	cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.96)
	for entry: Array in aisle_arms:
		var at: Vector3 = entry[0]
		var inward: float = float(entry[1])
		var x := at.x + inward * (arm_w * 0.5 + 0.005)
		var z0 := at.z + arm_z - arm_d * 0.43
		var z1 := at.z + arm_z + arm_d * 0.43
		var n := Vector3(inward, 0.0, 0.0)
		var p0 := Vector3(x, 0.04, z0)
		var p1 := Vector3(x, 0.04, z1)
		var p2 := Vector3(x, 0.09, z1)
		var p3 := Vector3(x, 0.09, z0)
		if inward > 0.0:
			cove.face([p0, p1, p2, p3], n)
		else:
			cove.face([p1, p0, p3, p2], n)
	cove.colour = Color.WHITE
	u.colour = Color.WHITE


## Roof height of the cabin's arched dome canopy at world x.
static func _roof_y(q: Dictionary, x: float) -> float:
	var cx := float(q["cx"])
	var th := float(q["top_half"])
	var wall_h := float(q["wall_height"])
	var rise := float(q["rise"])
	if rise < 0.001:
		return wall_h
	var r := (th * th + rise * rise) / (2.0 * rise)
	var dx := clampf(x - cx, -th, th)
	return wall_h + rise - r + sqrt(maxf(r * r - dx * dx, 0.0))
