extends RefCounted

## Sky lift (app/environments/sky_lift.env.json; docs/environments/rooms/sky_lift.md): a near-future equatorial
## orbital elevator climber car ascending smoothly from an equatorial ocean tether platform through the cloud deck into
## black star-filled orbit, with Earth's glowing curved limb opening out beneath you. Dressed over a `cabin` builder
## (`glazed_roof: true`, outward-canted observation walls) and `seats` (`recliner`) rows.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, arches, cylinders and lathed shapes;
## no people, no real trademarks, no mission badges or text.
##
##   skylift_cabin    the orbital climber's aerospace cabin architecture and seating hardware:
##                    - swept brushed-titanium forward canopy brow cowl hugging the arched glass dome (shielding the
##                      canopy from screen spill and keeping forward peripheral flow clear) with a polished titanium
##                      trailing lip and recessed live status cove valance (`PieceCove`, `cove_floor: 0.45`)
##                    - exposed overhead curved brushed-titanium observation truss hoops with open structural diagonal
##                      struts and longitudinal roof tension rails curving cleanly beneath the glazed dome
##                    - floating dark-slate & titanium cinema screen chassis with slim vertical telemetry edge-status
##                      bars (`PieceWindows`), indirect bulkhead halo cove (`PieceCove`), and low cantilevered forward
##                      avionics deck with recessed thermal grilles and gold thermal-foil inspection trim
##                    - continuous outward-canted window-sill deck trim, tubular brushed-titanium perimeter safety
##                      hand-rails mounted strictly at the window piers, and indirect under-sill cabin sconces
##                      (`PieceLamps`, `bake_lamps: 2`)
##                    - two rows of sculpted deep-slate & pearl-white shared recliner armrests (`Seats.RECLINER_ARM`,
##                      both kept when the viewer's seat folds away), dark-slate contoured headrest collar cradles,
##                      tubular titanium rear seatback zero-g grab-bars, and continuous backlit aisle floor pathway
##                      guide strips (`PieceCove`)
##   skylift_console  the aft orbital docking bay, altitude/climb telemetry consoles and mission chronometer:
##                    - monumental circular pressurised docking airlock hatch with octagonal-bolted titanium ring
##                      collar, tri-spoke central mechanical dogging wheel, gold thermal-foil collar segments, upper
##                      pressurised circular viewport (`PieceGlass`), glowing vestibule status ring (`PieceLamps`),
##                      and vertical airlock-seal telemetry bars (`PieceWindows`)
##                    - port & starboard cantilevered orbital altitude and tether-tension telemetry consoles with
##                      tilted multi-segment geometric bar-graph display panels (`PieceWindows`, zero text)
##                    - working circular brushed-titanium mission chronometer (`PieceClock`, live wall time) with 12
##                      radial machined hour lugs and outer orbital bezel ring centered high above the docking hatch
##                    - aft tubular titanium observation deck guard-rails with tinted safety-glass panels (`PieceGlass`)

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")

const PIECES: Array[String] = ["skylift_cabin", "skylift_console"]

## Palette (sRGB): brushed aerospace titanium, polished titanium trim, pearl-white composite, deep orbital slate,
## dark anodized pressure-hull charcoal, thermal gold foil, and cool ice-white cabin sconces.
const TITANIUM_BRIGHT := Color(0.86, 0.90, 0.94)
const TITANIUM_SATIN := Color(0.68, 0.74, 0.80)
const PEARL_COMPOSITE := Color(0.88, 0.90, 0.93)
const SLATE_PANEL := Color(0.20, 0.24, 0.30)
const SLATE_DARK := Color(0.11, 0.135, 0.175)
const CHARCOAL_PAD := Color(0.085, 0.10, 0.13)
const GOLD_FOIL := Color(0.82, 0.64, 0.22)
const CABIN_LAMP := Color(0.86, 0.94, 1.0)
const HATCH_RING_GLOW := Color(0.46, 0.90, 1.0)

## Forward swept brushed-titanium canopy brow depths from the front bulkhead (metres): flows from crown to rib #1.
const BROW_CROWN := 1.42
const BROW_SIDE := 1.93


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"skylift_cabin":
			_cabin(c)
		"skylift_console":
			_console(c)


# --- The orbital elevator climber cabin -------------------------------------------------------------------------------

static func _cabin(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_forward_brow_and_trusses(c, q)
	_screen_chassis(c, q)
	_sill_rails_and_sconces(c, q)
	_aerospace_rows(c, q)


## Swept brushed-titanium forward canopy brow cowl, recessed curved status cove, side cornice coves, and overhead
## curved observation truss hoops curving beneath the glazed space dome.
static func _forward_brow_and_trusses(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var rd := float(q["rib_depth"])
	var roof: Array = Cabin._roof(q)
	var rpts: PackedVector2Array = roof[0]
	var rns: PackedVector2Array = roof[1]
	var th := maxf(float(q["top_half"]), 0.1)
	var brow_side_z := fz + BROW_SIDE

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# 1. Swept curved brushed-titanium forward dome brow cowl hugging the front arch cleanly to rib #1.
	var brow_zs := PackedFloat32Array()
	for i in rpts.size():
		var u_arch := clampf(absf((rpts[i].x - cx) / th), 0.0, 1.0)
		var frac := 0.5 - 0.5 * cos(PI * u_arch)
		brow_zs.append(fz + lerpf(BROW_CROWN, BROW_SIDE, frac))

	s.surface(c.tinted("plastic"))
	s.colour = SLATE_PANEL.srgb_to_linear()
	var inner_f := PackedVector3Array()
	var inner_b := PackedVector3Array()
	var inner_n := PackedVector3Array()
	var lip_in := PackedVector3Array()
	var lip_out := PackedVector3Array()
	var lip_n := PackedVector3Array()
	var brow_t := 0.05
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

	# 2. Gleaming brushed-titanium trailing arch lip on the forward brow, curved overhead aerospace observation truss
	#    hoops at each glazed bay rib, and slender aft crown arch rib.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	var ba := PackedVector3Array()
	var bb := PackedVector3Array()
	var bn := PackedVector3Array()
	for i in rpts.size():
		var p := rpts[i] + rns[i] * (brow_t + 0.014)
		var bz_i := brow_zs[i]
		ba.append(Vector3(p.x, p.y, bz_i - 0.06))
		bb.append(Vector3(p.x, p.y, bz_i + 0.016))
		bn.append(Vector3(rns[i].x, rns[i].y, 0.0))
	u.strip(ba, bb, bn)

	# Overhead curved aerospace observation truss hoops at every intermediate rib mark (`_bay_marks`): inner titanium
	# chord flange suspended cleanly 0.10 m beneath the outer cabin arch rib + bold diagonal truss lattice struts!
	var marks: Array[float] = Cabin._bay_marks(q)
	for mz: float in marks:
		if mz < fz + 1.4 or mz > bz - 0.2:
			continue
		var ta := PackedVector3Array()
		var tb := PackedVector3Array()
		var tn := PackedVector3Array()
		for i in rpts.size():
			var p := rpts[i] + rns[i] * (rd + 0.105)
			ta.append(Vector3(p.x, p.y, mz - 0.032))
			tb.append(Vector3(p.x, p.y, mz + 0.032))
			tn.append(Vector3(rns[i].x, rns[i].y, 0.0))
		u.strip(ta, tb, tn)
		# Crisp open diagonal aerospace truss lattice struts linking the outer rib to the inner curved flange chord.
		u.colour = TITANIUM_SATIN.srgb_to_linear()
		for i in rpts.size() - 1:
			var p_out0 := Vector3(rpts[i].x + rns[i].x * (rd + 0.008), rpts[i].y + rns[i].y * (rd + 0.008), mz)
			var p_out1 := Vector3(rpts[i + 1].x + rns[i + 1].x * (rd + 0.008),
					rpts[i + 1].y + rns[i + 1].y * (rd + 0.008), mz)
			var p_in0 := Vector3(rpts[i].x + rns[i].x * (rd + 0.10), rpts[i].y + rns[i].y * (rd + 0.10), mz)
			var p_in1 := Vector3(rpts[i + 1].x + rns[i + 1].x * (rd + 0.10),
					rpts[i + 1].y + rns[i + 1].y * (rd + 0.10), mz)
			if i % 2 == 0:
				Shapes.beam(u, p_out0, p_in1, Vector2(0.024, 0.024))
			else:
				Shapes.beam(u, p_in0, p_out1, Vector2(0.024, 0.024))
		u.colour = TITANIUM_BRIGHT.srgb_to_linear()

	# Twin sleek longitudinal titanium tension spine rails flanking the central overhead glass bay (from brow to aft).
	if rpts.size() >= 9:
		for idx: int in [2, rpts.size() - 3]:
			var p := rpts[idx] + rns[idx] * (rd + 0.068)
			var ang := atan2(-rns[idx].x, -rns[idx].y)
			var span := (bz - 0.08) - (brow_zs[idx] - 0.02)
			var mid_z := (brow_zs[idx] - 0.02 + bz - 0.08) * 0.5
			u.box(Vector3(p.x, p.y, mid_z), Vector3(0.036, 0.024, span), Basis(Vector3.BACK, ang))

	# 3. Recessed glowing aerospace status cove ribbons (`PieceCove`, live colour via Cabin light setting):
	#    curved light wash tucked under the swept forward brow lip + continuous upper eave cornice ribbons.
	cove.surface(c.kit.cove_material())
	var cove_base := Color(0.95, 0.98, 1.0).srgb_to_linear()
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.96)
	var ca := PackedVector3Array()
	var cb := PackedVector3Array()
	var cn := PackedVector3Array()
	for i in range(1, rpts.size() - 1):
		var p := rpts[i] + rns[i] * (brow_t + 0.008)
		var bz_i := brow_zs[i]
		ca.append(Vector3(p.x, p.y, bz_i - 0.21))
		cb.append(Vector3(p.x, p.y, bz_i - 0.065))
		cn.append(Vector3(rns[i].x, rns[i].y, 0.0))
	cove.strip(ca, cb, cn)

	# Upper side-wall cornice cove strips running along both outward-canted eaves just beneath the glass dome!
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.72)
	var wall_len := float(q["wall_len"])
	for side: float in [-1.0, 1.0]:
		var n := Cabin._n(q, side)
		var p0 := Cabin._pt(q, side, brow_side_z + 0.06, wall_len - 0.095) + n * 0.044
		var p1 := Cabin._pt(q, side, bz - 0.18, wall_len - 0.095) + n * 0.044
		var p2 := Cabin._pt(q, side, bz - 0.18, wall_len - 0.064) + n * 0.044
		var p3 := Cabin._pt(q, side, brow_side_z + 0.06, wall_len - 0.064) + n * 0.044
		if side < 0.0:
			cove.face([p0, p1, p2, p3], n)
		else:
			cove.face([p1, p0, p3, p2], n)

	cove.colour = Color.WHITE
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Floating aerospace cinema screen chassis with chamfered brushed-titanium halo frame, slim vertical cyan telemetry
## edge-status bars (`PieceWindows`), indirect bulkhead halo cove (`PieceCove`), and low cantilevered avionics deck.
static func _screen_chassis(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(2.24, 1.26))
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var sc_x := sc_xf.origin.x
	var sc_y := sc_xf.origin.y
	var sc_z := sc_xf.origin.z
	var sw := sc_sz.x
	var sh := sc_sz.y
	var hsw := sw * 0.5
	var hsh := sh * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# 1. Low cantilevered aerospace forward avionics console below the floating screen (`y = 0 .. console_h`).
	var console_h := sc_y - hsh - 0.28
	var console_d := 0.32
	var console_z := fz + console_d * 0.5
	s.surface(c.tinted("plastic"))
	s.colour = SLATE_PANEL.srgb_to_linear()
	s.box(Vector3(cx, console_h * 0.5, console_z), Vector3(hw * 2.0 - 0.12, console_h, console_d), Basis(),
			[RoomMesh.DOWN, RoomMesh.FRONT])
	# Recessed low-glare deep-slate acoustic bulkhead cheek bays flanking the floating screen chassis.
	s.colour = SLATE_DARK.srgb_to_linear()
	var cheek_w := maxf(hw - (hsw + 0.28), 0.35)
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (hsw + 0.28 + cheek_w * 0.5)
		s.box(Vector3(px, console_h + 0.62, fz + 0.035), Vector3(cheek_w - 0.06, 1.18, 0.06), Basis(),
				[RoomMesh.FRONT])

	# 2. Floating screen dark-slate standoff spine & crisp chamfered mask bezel (strictly behind sc_z!).
	s.surface(c.tinted("iron"))
	s.colour = SLATE_DARK.srgb_to_linear()
	var back_d := maxf(sc_z - fz - 0.035, 0.08)
	s.box(Vector3(sc_x, sc_y, fz + back_d * 0.5), Vector3(sw - 0.16, sh - 0.14, back_d), Basis(), [RoomMesh.FRONT])
	var bz := sc_z - 0.034
	var bw := 0.058
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(sc_x + side * (hsw + bw * 0.5), sc_y, bz), Vector3(bw, sh + bw * 2.0, 0.055))
	s.box(Vector3(sc_x, sc_y + hsh + bw * 0.5, bz), Vector3(sw, bw, 0.055))
	s.box(Vector3(sc_x, sc_y - hsh - bw * 0.5, bz), Vector3(sw, bw, 0.055))
	# Recessed dark lower kick-plinth and twin avionics thermal cooling grille bays.
	s.box(Vector3(cx, 0.06, fz + console_d + 0.012), Vector3(hw * 2.0 - 0.14, 0.12, 0.024), Basis(), [RoomMesh.DOWN])
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * 1.18
		s.box(Vector3(gx, 0.54, fz + console_d + 0.008), Vector3(1.24, 0.38, 0.02), Basis(), [RoomMesh.FRONT])

	# 3. Gleaming brushed-titanium outer floating screen halo rim, corner clamps, console bullnose & thermal slats!
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	var fr_z := sc_z - 0.012
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(sc_x + side * (hsw + bw + 0.014), sc_y, fr_z), Vector3(0.026, sh + bw * 2.0 + 0.052, 0.028))
		# Four machined titanium corner bracket collars framing the floating screen chassis.
		for sy: float in [-1.0, 1.0]:
			u.box(Vector3(sc_x + side * (hsw + bw + 0.042), sc_y + sy * (hsh + bw - 0.06), fr_z - 0.018),
					Vector3(0.052, 0.16, 0.042))
	u.box(Vector3(sc_x, sc_y + hsh + bw + 0.014, fr_z), Vector3(sw + bw * 2.0 + 0.052, 0.026, 0.028))
	u.box(Vector3(sc_x, sc_y - hsh - bw - 0.014, fr_z), Vector3(sw + bw * 2.0 + 0.052, 0.026, 0.028))
	# Continuous brushed-titanium console top bullnose rail & thermal louvre slats.
	u.box(Vector3(cx, console_h + 0.018, fz + console_d + 0.014), Vector3(hw * 2.0 - 0.08, 0.036, 0.048))
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * 1.18
		for k in 5:
			u.box(Vector3(gx, 0.41 + 0.065 * k, fz + console_d + 0.022), Vector3(1.16, 0.014, 0.014))
		# Subtle slim titanium telemetry housing bars + five architectural horizontal acoustic ribs across each flank!
		var tx := sc_x + side * (hsw + bw + 0.12)
		u.box(Vector3(tx, sc_y, fz + 0.085), Vector3(0.065, sh * 0.88, 0.034))
		var px := cx + side * (hsw + 0.28 + cheek_w * 0.5)
		var rib_w := maxf(cheek_w - 0.16, 0.2)
		u.colour = TITANIUM_SATIN.srgb_to_linear()
		for k in 5:
			var ry := console_h + 0.24 + 0.19 * k
			u.box(Vector3(px, ry, fz + 0.072), Vector3(rib_w, 0.02, 0.018))
		u.colour = TITANIUM_BRIGHT.srgb_to_linear()
		u.box(Vector3(px + side * (rib_w * 0.5 + 0.012), console_h + 0.62, fz + 0.072), Vector3(0.02, 1.14, 0.02))
	# Aerospace gold-foil thermal inspection trim strip nested along the centre avionics panel + flank alignment dashes.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.16))
	u.colour = GOLD_FOIL.srgb_to_linear()
	u.box(Vector3(cx, console_h - 0.09, fz + console_d + 0.012), Vector3(0.92, 0.028, 0.016))
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (hsw + 0.28 + cheek_w * 0.5)
		u.box(Vector3(px, console_h + 1.14, fz + 0.076), Vector3(maxf(cheek_w - 0.34, 0.14), 0.022, 0.018))

	# 4. Slim glowing orbital telemetry edge bars beside the floating screen & on the forward console (`PieceWindows`).
	var wins: Array = c.glows.get("window", [])
	for side: float in [-1.0, 1.0]:
		var tx := sc_x + side * (hsw + bw + 0.12)
		# Three crisp vertical segmented orbital climb-telemetry indicator bars flanking each side of the screen.
		for k in 3:
			var by := sc_y - 0.34 + 0.34 * k
			wins.append([Vector3(tx, by, fz + 0.106), Vector3(0.014, 0.0, 0.0), Vector3(0.0, 0.12, 0.0), Vector3.BACK])
		# Slim horizontal avionics telemetry strip along the upper lip of each console flank.
		var fx := cx + side * 1.18
		wins.append([Vector3(fx, console_h - 0.10, fz + console_d + 0.014), Vector3(0.36, 0.0, 0.0),
				Vector3(0.0, 0.016, 0.0), Vector3.BACK])
	c.glows["window"] = wins

	# 5. Indirect backlit bulkhead halo cove behind the floating screen frame (`PieceCove`).
	cove.surface(c.kit.cove_material())
	var col_lin := Color(0.94, 0.98, 1.0).srgb_to_linear()
	cove.colour = Color(col_lin.r, col_lin.g, col_lin.b, 0.88)
	for side: float in [-1.0, 1.0]:
		var vx := sc_x + side * (hsw + bw + 0.052)
		cove.face([Vector3(vx - 0.028, sc_y - hsh - 0.02, fz + 0.018),
				Vector3(vx + 0.028, sc_y - hsh - 0.02, fz + 0.018),
				Vector3(vx + 0.028, sc_y + hsh + 0.02, fz + 0.018),
				Vector3(vx - 0.028, sc_y + hsh + 0.02, fz + 0.018)], Vector3.BACK)
	cove.face([Vector3(sc_x - hsw - 0.06, console_h + 0.055, fz + 0.018),
			Vector3(sc_x + hsw + 0.06, console_h + 0.055, fz + 0.018),
			Vector3(sc_x + hsw + 0.06, console_h + 0.115, fz + 0.018),
			Vector3(sc_x - hsw - 0.06, console_h + 0.115, fz + 0.018)], Vector3.BACK)

	cove.colour = Color.WHITE
	s.colour = Color.WHITE
	u.colour = Color.WHITE

	# Clean physics collision box for the forward avionics console (strictly inside cabin, ~4.0 m from viewer's seat).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, console_h * 0.5, fz + console_d * 0.5),
			Vector3(hw * 2.0 - 0.14, console_h, console_d), Basis()))


## Continuous outward-canted window-sill deck bolsters, tubular brushed-titanium perimeter safety hand-rails along
## the low glazed sills, structural titanium pier flanges, and indirect under-sill cabin sconces (`PieceLamps`).
static func _sill_rails_and_sconces(c: Object, q: Dictionary) -> void:
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var sill := float(q["window_sill"])
	var lean := float(q["L"])
	var vs := sill / cos(lean)
	var wall_len := float(q["wall_len"])
	var wzs: Array = q["window_zs"]
	var marks: Array[float] = Cabin._bay_marks(q)
	if wzs.is_empty():
		return
	var z0 := fz + 0.36
	var z1 := bz - 0.14
	var span := z1 - z0
	var mid_z := (z0 + z1) * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)

	# 1. Low dark-slate aerodynamic sill bolster ledges hugging both outward-canted window walls cleanly below y = 0.62.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_DARK.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var n := Cabin._n(q, side)
		var wb := Cabin._wall_basis(q, side)
		var ledge_pt := Cabin._pt(q, side, mid_z, vs - 0.03) + n * 0.055
		s.box(ledge_pt, Vector3(span, 0.055, 0.11), wb)
		# Lower floor baseboard cable-conduit kick rail along each side wall.
		var base_pt := Cabin._pt(q, side, mid_z, 0.09) + n * 0.035
		s.box(base_pt, Vector3(span - 0.2, 0.18, 0.065), wb, [RoomMesh.DOWN])

	# 2. Gleaming tubular brushed-titanium perimeter safety hand-rails running along the low glazed sills (y = 0.78),
	#    with machined titanium stanchions placed ONLY at the window piers (`marks`) so the panoramic view stays 100%
	#    open, plus crisp brushed-titanium bullnose sill caps and structural pier ribs.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	var rail_v := (sill + 0.15) / cos(lean)
	for side: float in [-1.0, 1.0]:
		var n := Cabin._n(q, side)
		var wb := Cabin._wall_basis(q, side)
		# Brushed-titanium bullnose sill fascia trim along the full side deck.
		var lip_pt := Cabin._pt(q, side, mid_z, vs - 0.012) + n * 0.114
		u.box(lip_pt, Vector3(span + 0.02, 0.024, 0.026), wb)
		# Continuous tubular titanium safety hand-rail along the low panoramic window sills.
		var rail_start := Cabin._pt(q, side, z0 + 0.12, rail_v) + n * 0.105
		Shapes.cylinder(u, rail_start, 0.017, span - 0.24, 10, basis_z)
		# Stanchion brackets connecting the tubular hand-rail cleanly into the sill bolster at every pier mark.
		for mz: float in marks:
			if mz < z0 + 0.12 or mz > z1 - 0.12:
				continue
			var p_sill := Cabin._pt(q, side, mz, vs - 0.015) + n * 0.085
			var p_rail := Cabin._pt(q, side, mz, rail_v) + n * 0.105
			Shapes.beam(u, p_sill, p_rail, Vector2(0.024, 0.024))
			# Vertical brushed-titanium rib flange accent running up each canted window pier.
			var rib_mid := Cabin._pt(q, side, mz, (vs + wall_len) * 0.5) + n * 0.048
			u.box(rib_mid, Vector3(0.036, wall_len - vs - 0.04, 0.022), wb)
			# Floor-to-sill lower vertical dado structural strut at each pier.
			var low_mid := Cabin._pt(q, side, mz, vs * 0.5) + n * 0.032
			u.box(low_mid, Vector3(0.044, vs - 0.04, 0.026), wb)

		# Clean physics box enclosing each side sill bolster (strictly inside floor width AABB, > 1.4 m from origin).
		var px_floor := float(q["cx"]) + side * (float(q["hw"]) - 0.065)
		c.shapes.append(PhysicsShapes.box(Vector3(px_floor, sill * 0.5, mid_z), Vector3(0.11, sill, span), Basis()))

	# 3. Indirect linear under-sill cabin sconces tucked neatly beneath the sill lip at each window bay (`PieceLamps`,
	#    house group, dimming smoothly to 0.10 when the film starts) + 2 middle-bay lamps registered for baking!
	lit.surface(c.shade(CABIN_LAMP))
	for i in wzs.size():
		var wz := float(wzs[i])
		for side: float in [-1.0, 1.0]:
			var n := Cabin._n(q, side)
			var wb := Cabin._wall_basis(q, side)
			var lamp_pt := Cabin._pt(q, side, wz, vs - 0.068) + n * 0.082
			lit.box(lamp_pt, Vector3(0.74, 0.018, 0.026), wb)
			if i == 2:
				c.lamps.append([lamp_pt + n * 0.14 + Vector3(0.0, 0.12, 0.0), CABIN_LAMP, 0.78])

	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Two rows of sculpted aerospace recliner hardware round `seats` (`recliner`): deep-slate & pearl-white shared
## armrests (`Seats.RECLINER_ARM`, both kept around the viewer's folded seat), contoured dark-slate headrest collars,
## tubular titanium rear seatback grab-bars, and continuous backlit aisle floor pathway strips (`PieceCove`).
static func _aerospace_rows(c: Object, q: Dictionary) -> void:
	var slots: Array = Cabin.seat_slots_for(c.builder_params)
	if slots.is_empty():
		return
	var cx := float(q["cx"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var pitch := float(q["seat_pitch"])
	var aisle_half := float(q["aisle"]) * 0.5
	var arm_w := Seats.RECLINER_ARM
	var arm_h := 0.55
	var arm_d := 0.60
	var arm_z := -0.07
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15.0)), Vector3(0.0, 0.46, 0.12))

	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# Deduplicate shared armrests across each row block.
	var arm_places := {}
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		var o := xf.origin
		var row_key := roundi(o.z * 100.0)
		for side: float in [-1.0, 1.0]:
			var ax := o.x + side * pitch * 0.5
			var k := "%d:%d" % [row_key, roundi(ax * 100.0)]
			if not arm_places.has(k):
				arm_places[k] = Vector3(ax, o.y, o.z)

	# 1. Sculpted pearl-white & deep-slate aerospace armrest pedestals with soft charcoal ergonomic top rest caps.
	u.surface(c.soft("plastic", true))
	for at: Vector3 in arm_places.values():
		u.colour = SLATE_PANEL.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h * 0.5, arm_z), Vector3(arm_w, arm_h, arm_d), Basis(), [RoomMesh.DOWN])
		u.colour = PEARL_COMPOSITE.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h * 0.56, arm_z + 0.02), Vector3(arm_w + 0.01, arm_h * 0.52, arm_d * 0.72))
		u.colour = CHARCOAL_PAD.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(arm_w + 0.014, 0.044, arm_d + 0.026), 0.016,
				Transform3D(Basis(), at + Vector3(0.0, arm_h + 0.018, arm_z - 0.01)), 1, Vector3i.ZERO, 0.0,
				[RoomMesh.DOWN])

	# 2. Gleaming brushed-titanium waterfall armrest nose fascia, inlaid side rails & seat-recline touch-bar bezel.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	for at: Vector3 in arm_places.values():
		u.rounded_box(Vector3.ZERO, Vector3(arm_w + 0.01, arm_h * 0.80, 0.034), 0.014,
				Transform3D(Basis(), at + Vector3(0.0, arm_h * 0.50, arm_z - arm_d * 0.5 - 0.006)), 1)
		u.box(at + Vector3(0.0, 0.28, arm_z), Vector3(arm_w + 0.016, 0.018, arm_d * 0.88))
		u.box(at + Vector3(0.0, arm_h + 0.042, arm_z - arm_d * 0.24), Vector3(0.056, 0.008, 0.095))

	# 3. Sculpted aerospace slate-blue headrest bolster cradles hugging `seats.gd _recliner`'s exact headrest curve
	#    (`bend = -0.35`, `radius = 0.062`) cleanly proud of the pearl-white upholstery (zero z-fighting!).
	var wi := pitch - arm_w - 0.01
	u.surface(c.soft("cloth", true))
	u.colour = Color(0.24, 0.31, 0.40).srgb_to_linear()
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.rounded_box(Vector3(0.0, 0.649, -0.011), Vector3(wi - 0.18, 0.242, 0.156), 0.062, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])

	# 4. Tubular brushed-titanium rear seatback zero-g hand-rails + twin vertical titanium spine trim ribs.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	var grab_w := wi - 0.10
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.box(t_world * Vector3(0.0, 0.56, 0.148), Vector3(grab_w, 0.022, 0.022), t_world.basis)
		for side: float in [-1.0, 1.0]:
			u.box(t_world * Vector3(side * (grab_w * 0.5 - 0.012), 0.56, 0.128), Vector3(0.022, 0.024, 0.036),
					t_world.basis)
			u.box(t_world * Vector3(side * (wi * 0.28), 0.28, 0.124), Vector3(0.016, 0.42, 0.014), t_world.basis)

	# 5. Continuous backlit floor-level pathway strips (`PieceCove`) flanking the entire central aisle from the forward
	#    avionics deck right back to the aft pressurised docking airlock hatch!
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.95, 0.98, 1.0).srgb_to_linear()
	cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.98)
	var path_z0 := fz + 0.62
	var path_z1 := bz - 0.28
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * (aisle_half - 0.055)
		cove.face([Vector3(gx - 0.018, 0.008, path_z0), Vector3(gx + 0.018, 0.008, path_z0),
				Vector3(gx + 0.018, 0.008, path_z1), Vector3(gx - 0.018, 0.008, path_z1)], Vector3.UP)
		# Crisp slim anodized titanium bezel edging flanking each floor-level light strip.
		u.colour = TITANIUM_SATIN.srgb_to_linear()
		u.box(Vector3(gx + side * 0.024, 0.005, (path_z0 + path_z1) * 0.5),
				Vector3(0.012, 0.01, path_z1 - path_z0), Basis(), [RoomMesh.DOWN])

	cove.colour = Color.WHITE
	u.colour = Color.WHITE


# --- The aft pressurised orbital docking hatch, telemetry consoles & mission chronometer ------------------------------

static func _console(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_aft_docking_hatch(c, q)
	_aft_telemetry_desks_and_rails(c, q)
	_mission_chronometer(c, q)


## Monumental aft pressurised circular docking airlock hatch: bolted titanium ring collar, recessed pressure-hull
## door disc, central tri-spoke mechanical locking wheel, upper circular pressurised viewport (`PieceGlass`), glowing
## vestibule status ring (`PieceLamps`), gold thermal-foil collar accents, and vertical airlock-seal status bars.
static func _aft_docking_hatch(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var hatch_y := 1.04
	var r_in := 0.68
	var r_out := 0.89
	var basis_aft := Basis(Vector3.UP, PI)

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	# 1. Recessed dark pressure-hull hatch door plate & heavy lower threshold step ramp.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_DARK.srgb_to_linear()
	s.box(Vector3(cx, hatch_y, bz - 0.025), Vector3(r_in * 2.02, r_in * 2.02, 0.045), Basis(), [RoomMesh.BACK])
	s.box(Vector3(cx, 0.075, bz - 0.14), Vector3(1.16, 0.15, 0.24), Basis(), [RoomMesh.DOWN, RoomMesh.BACK])

	# 2. Thick brushed-titanium circular pressurised docking collar ring (`Shapes.arch`, 24 segments) + 8 radially
	#    bolted structural lock-dog lugs + tri-spoke mechanical central locking wheel + flanking grab-handles!
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, hatch_y, bz - 0.075), r_in, r_out, 0.12, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Inner stepped sealing flange ring.
	u.colour = TITANIUM_SATIN.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, hatch_y, bz - 0.065), r_in - 0.07, r_in + 0.01, 0.055, 20, basis_aft, 0.0, TAU,
			["front", "inner"])
	# 8 radially machined pressure-lock dog lugs round the hatch perimeter.
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	for k in 8:
		var ang := TAU * float(k) / 8.0 + PI / 8.0
		var lr := (r_in + r_out) * 0.5
		u.box(Vector3(cx + cos(ang) * lr, hatch_y + sin(ang) * lr, bz - 0.145),
				Vector3(0.085, 0.055, 0.042), Basis(Vector3.BACK, ang))
	# Central heavy mechanical tri-spoke airlock dogging wheel (centered at y = 0.94 on the hatch face).
	var wheel_y := hatch_y - 0.14
	var wheel_z := bz - 0.115
	Shapes.arch(u, Vector3(cx, wheel_y, wheel_z), 0.185, 0.225, 0.032, 18, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	Shapes.cylinder(u, Vector3(cx, wheel_y, bz - 0.045), 0.055, 0.085, 10, Basis(Vector3.RIGHT, -PI * 0.5))
	for k in 3:
		var ang := TAU * float(k) / 3.0 + PI / 6.0
		var p_spoke := Vector3(cx + cos(ang) * 0.105, wheel_y + sin(ang) * 0.105, wheel_z)
		u.box(p_spoke, Vector3(0.19, 0.026, 0.024), Basis(Vector3.BACK, ang))
	# Twin vertical brushed-titanium boarding grab-handles flanking the docking airlock collar.
	for side: float in [-1.0, 1.0]:
		var hx := cx + side * (r_out + 0.095)
		Shapes.cylinder(u, Vector3(hx, 0.72, bz - 0.11), 0.016, 0.72, 8)
		for hy: float in [0.74, 1.42]:
			u.box(Vector3(hx, hy, bz - 0.055), Vector3(0.032, 0.032, 0.11))

	# 3. Upper circular pressurised docking viewport (`y = 1.42`, radius `0.18 m`) with titanium bezel, tinted safety
	#    glass (`PieceGlass`), and glowing cyan vestibule lock-ring (`PieceLamps`).
	var vp_y := hatch_y + 0.36
	Shapes.arch(u, Vector3(cx, vp_y, bz - 0.072), 0.165, 0.21, 0.06, 18, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	c.glass.surface(c.mat("tin"))
	c.glass.box(Vector3(cx, vp_y, bz - 0.066), Vector3(0.32, 0.32, 0.012))
	lit.surface(c.shade(HATCH_RING_GLOW))
	Shapes.arch(lit, Vector3(cx, vp_y, bz - 0.052), 0.135, 0.162, 0.016, 18, basis_aft, 0.0, TAU, ["front"])

	# 4. Aerospace gold-foil thermal collar stripes flanking the airlock threshold + vertical airlock status bars.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.16))
	u.colour = GOLD_FOIL.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.42, 0.162, bz - 0.255), Vector3(0.28, 0.022, 0.022))

	var wins: Array = c.glows.get("window", [])
	for side: float in [-1.0, 1.0]:
		var sx := cx + side * (r_out + 0.19)
		wins.append([Vector3(sx, hatch_y + 0.18, bz - 0.032), Vector3(0.018, 0.0, 0.0), Vector3(0.0, 0.24, 0.0),
				Vector3.FORWARD])
		wins.append([Vector3(sx, hatch_y - 0.18, bz - 0.032), Vector3(0.018, 0.0, 0.0), Vector3(0.0, 0.08, 0.0),
				Vector3.FORWARD])
	c.glows["window"] = wins

	# Soft backlit cove halo tucked behind the circular docking hatch ring (`PieceCove`).
	cove.surface(c.kit.cove_material())
	var col_lin := Color(0.95, 0.98, 1.0).srgb_to_linear()
	cove.colour = Color(col_lin.r, col_lin.g, col_lin.b, 0.88)
	Shapes.arch(cove, Vector3(cx, hatch_y, bz - 0.016), r_out - 0.01, r_out + 0.055, 0.01, 24, basis_aft, 0.0, TAU,
			["front"])
	cove.colour = Color.WHITE
	s.colour = Color.WHITE
	u.colour = Color.WHITE

	# Clean physics collision box for the aft docking airlock collar (strictly inside cabin, > 3.1 m from viewer).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, hatch_y, bz - 0.09), Vector3(r_out * 2.0, r_out * 2.0, 0.18),
			Basis()))


## Flanking aft orbital altitude & tether-tension telemetry consoles with angled multi-segment glowing display panels
## (`PieceWindows`, pure geometry, zero text), plus aft tubular titanium observation deck guard-rails (`PieceGlass`).
static func _aft_telemetry_desks_and_rails(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var aisle_half := float(q["aisle"]) * 0.5
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var wins: Array = c.glows.get("window", [])
	var basis_x := Basis(Vector3.BACK, -PI * 0.5)

	# 1. Port & starboard cantilevered aerospace telemetry consoles tucked against the aft bulkhead flanks.
	var desk_w := 1.02
	var desk_h := 0.96
	var desk_d := 0.44
	var desk_z := bz - desk_d * 0.5 - 0.02
	var rail_z := bz - 1.02
	var rail_h := 0.90

	for side: float in [-1.0, 1.0]:
		var dx := cx + side * 1.56
		# Main dark-slate console pedestal + sloped upper instrument hood.
		s.surface(c.tinted("plastic"))
		s.colour = SLATE_PANEL.srgb_to_linear()
		s.box(Vector3(dx, desk_h * 0.5, desk_z), Vector3(desk_w, desk_h, desk_d), Basis(),
				[RoomMesh.DOWN, RoomMesh.BACK])
		s.surface(c.tinted("iron"))
		s.colour = SLATE_DARK.srgb_to_linear()
		var hood_basis := Basis(Vector3.RIGHT, deg_to_rad(28.0))
		s.box(Vector3(dx, desk_h + 0.16, bz - 0.20), Vector3(desk_w - 0.04, 0.36, 0.12), hood_basis)
		# Lower recessed telemetry deck cooling panel.
		s.box(Vector3(dx, 0.44, desk_z - desk_d * 0.5 - 0.008), Vector3(desk_w - 0.16, 0.46, 0.018))

		# Brushed-titanium console desktop bullnose, sloped instrument hood bezel, and gold-foil accent strip.
		u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
		u.colour = TITANIUM_BRIGHT.srgb_to_linear()
		u.box(Vector3(dx, desk_h + 0.016, desk_z - desk_d * 0.5 - 0.012), Vector3(desk_w + 0.04, 0.032, 0.044))
		for s2: float in [-1.0, 1.0]:
			u.box(Vector3(dx + s2 * (desk_w * 0.5 - 0.02), desk_h + 0.16, bz - 0.25), Vector3(0.032, 0.38, 0.04),
					hood_basis)
		u.box(Vector3(dx, desk_h + 0.33, bz - 0.14), Vector3(desk_w, 0.032, 0.045), hood_basis)
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.16))
		u.colour = GOLD_FOIL.srgb_to_linear()
		u.box(Vector3(dx, 0.76, desk_z - desk_d * 0.5 - 0.012), Vector3(desk_w - 0.18, 0.024, 0.016))

		# Glowing geometric orbital altitude & climb telemetry display panels (`PieceWindows`, tilted toward viewer!).
		var n_disp := (hood_basis * Vector3.FORWARD).normalized()
		var up_disp := (hood_basis * Vector3.UP).normalized()
		var disp_center := Vector3(dx, desk_h + 0.165, bz - 0.268)
		if side < 0.0:
			# Port console: 6-step orbital climb altitude ladder bar-graph (sea level -> cloud deck -> orbit!).
			for k in 6:
				var frac := float(k) / 5.0
				var bar_w := lerpf(0.08, 0.34, frac)
				var by := -0.105 + 0.042 * k
				var pos := disp_center + up_disp * by + Vector3(-0.34 + bar_w * 0.5 + 0.04, 0.0, 0.0)
				wins.append([pos, Vector3(bar_w * 0.5, 0.0, 0.0), up_disp * 0.012, n_disp])
			# Companion vertical climb-rate indicator column on the right side of the port display.
			wins.append([disp_center + Vector3(0.28, 0.0, 0.0), Vector3(0.022, 0.0, 0.0), up_disp * 0.11, n_disp])
		else:
			# Starboard console: 4 vertical tether-tension & thermal telemetry bar columns + horizon status line.
			for k in 4:
				var bx := -0.28 + 0.185 * k
				var bar_h := float([0.10, 0.16, 0.13, 0.18][k])
				var pos := disp_center + Vector3(bx, 0.0, 0.0) + up_disp * (-0.11 + bar_h * 0.5)
				wins.append([pos, Vector3(0.042, 0.0, 0.0), up_disp * (bar_h * 0.5), n_disp])
			wins.append([disp_center + up_disp * 0.115, Vector3(0.36, 0.0, 0.0), up_disp * 0.012, n_disp])

		# Clean physics box for each aft telemetry console (strictly inside cabin, > 2.9 m behind viewer's seat).
		c.shapes.append(PhysicsShapes.box(Vector3(dx, (desk_h + 0.30) * 0.5, desk_z),
				Vector3(desk_w, desk_h + 0.30, desk_d), Basis()))

		# 2. Sleek aft observation deck guard-rail protecting the telemetry bays while leaving the central aisle wide!
		var x_in := cx + side * (aisle_half + 0.24)
		var x_out := cx + side * (hw - 0.12)
		var span_x := absf(x_out - x_in)
		var x_lo := minf(x_in, x_out)
		var x_mid := (x_in + x_out) * 0.5
		u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
		u.colour = TITANIUM_BRIGHT.srgb_to_linear()
		Shapes.cylinder(u, Vector3(x_lo, rail_h, rail_z), 0.02, span_x, 10, basis_x)
		u.box(Vector3(x_mid, rail_h * 0.54, rail_z), Vector3(span_x, 0.018, 0.018))
		for px: float in [x_in, x_out]:
			Shapes.cylinder(u, Vector3(px, 0.0, rail_z), 0.02, rail_h, 10)
			Shapes.lathe(u, [Vector2(0.045, 0.0), Vector2(0.045, 0.015), Vector2(0.024, 0.028)],
					Vector3(px, 0.0, rail_z), 10)
		# Tinted aerospace safety-glass panel framed cleanly inside the aft guard-rail (behind viewer!).
		c.glass.surface(c.mat("tin"))
		c.glass.box(Vector3(x_mid, 0.44, rail_z), Vector3(span_x - 0.12, 0.62, 0.012))
		c.shapes.append(PhysicsShapes.box(Vector3(x_mid, rail_h * 0.5, rail_z), Vector3(span_x, rail_h, 0.08),
				Basis()))

	c.glows["window"] = wins
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Working machined brushed-titanium orbital mission chronometer (`PieceClock`, live wall time) centered high above the
## aft pressurised docking hatch, plus the aft curved brushed-titanium roof arch seam rib.
static func _mission_chronometer(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var clk_y := 2.40
	var clk_r := 0.21
	var clk_z := bz - 0.048
	var basis_aft := Basis(Vector3.UP, PI)
	var u: RoomMesh = c.u

	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	# Primary circular machined titanium chronometer bezel + thin outer orbital halo ring.
	Shapes.arch(u, Vector3(cx, clk_y, clk_z), clk_r, clk_r + 0.044, 0.062, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	u.colour = TITANIUM_SATIN.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, clk_y, clk_z + 0.01), clk_r + 0.075, clk_r + 0.095, 0.024, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# 12 radial machined titanium hour index lugs linking the inner bezel to the outer orbital ring.
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	for k in 12:
		var ang := TAU * float(k) / 12.0
		var cardinal := (k % 3 == 0)
		var r0 := clk_r + 0.040
		var rlen := 0.085 if cardinal else 0.045
		var mid_r := r0 + rlen * 0.5
		u.box(Vector3(cx + sin(ang) * mid_r, clk_y + cos(ang) * mid_r, clk_z + 0.004),
				Vector3(0.022 if cardinal else 0.012, rlen, 0.02), Basis(Vector3.BACK, -ang))
	# Gold thermal-foil accent pin at 12 o'clock on the mission chronometer collar.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.16))
	u.colour = GOLD_FOIL.srgb_to_linear()
	u.box(Vector3(cx, clk_y + clk_r + 0.115, clk_z), Vector3(0.036, 0.036, 0.026))

	# Live illuminated chronometer dial (`PieceClock`, updated every second to system wall time).
	c.clocks.append([Vector3(cx, clk_y, bz - 0.072), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# Curved brushed-titanium aft arch crown rib framing the rear glass-dome seam.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM_BRIGHT.srgb_to_linear()
	var roof: Array = Cabin._roof(q)
	var rpts: PackedVector2Array = roof[0]
	var rns: PackedVector2Array = roof[1]
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	var rn := PackedVector3Array()
	for i in rpts.size():
		var p := rpts[i] + rns[i] * 0.032
		ra.append(Vector3(p.x, p.y, bz - 0.072))
		rb.append(Vector3(p.x, p.y, bz - 0.005))
		rn.append(Vector3(rns[i].x, rns[i].y, 0.0))
	u.strip(ra, rb, rn)
	u.colour = Color.WHITE
