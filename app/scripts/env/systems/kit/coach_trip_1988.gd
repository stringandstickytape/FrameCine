extends RefCounted

## Coach trip, 1988 overnight touring coach (docs/environments/rooms/coach_trip_1988.md): a narrow high-floor 1988
## British/European overnight express touring coach dressed over a `cabin` builder and `seats` (`recliner`) rows.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips and lathed shapes; no people, no
## real mark, no coach-operator livery or badge.
##
##   coach_1988_cabin   the 1988 overnight coach's interior craft:
##                      - ribbed dark-rubber central aisle runner with brushed-aluminium grip trims over the swirly
##                        moquette carpet, flanked by low night-driving floor guide strips (`PieceCove`)
##                      - forward driver's cab night curtain (pleated deep burgundy-brown drape hanging from brass
##                        rings on a chrome rail cleanly hiding the cab area; zero people), curved upper coach header
##                        valance, twin cream-and-walnut laminate front modesty screens with padded crash rails and
##                        curved brushed-chrome entry stairwell grab rails
##                      - ceiling-mounted 1988 4:3 CRT television suspended in a bolted dark-charcoal steel cradle
##                        with speaker grilles, channel buttons, rotary dial, chrome chin trim, green standby LED
##                        (`PieceWindows`), deep cathode-ray neck housing, and a bolted lower steel shelf holding a
##                        1988 video cassette deck flashing `12:00` (`PieceDisplay`) beside stacked retro plastic
##                        rental video tape cases
##                      - continuous overhead parcel racks along both window walls with warm cream soffits, padded
##                        brown luggage lips, chrome grab rails, per-row passenger service pods (twin round eyeball
##                        air vents and recessed reading-lamp lenses), recessed warm fluorescent ceiling diffuser
##                        troughs (`PieceLamps`, house group), and night-travel courtesy cove strips (`PieceCove`)
##                      - cream pleated window curtains tied back cleanly between bays on chrome tracks, under-sill
##                        convector heater ducts, and break-glass red emergency hammer boxes (`PieceGlass`)
##                      - aft WC/vestibule bulkhead with stainless kick-plate & push-bar, backlit green geometric
##                        EXIT pictogram box (`PieceWindows`), working 1988 quartz bulkhead clock (`PieceClock`),
##                        safety layout placard and chrome coat hooks
##   coach_1988_rows    the 1988 touring coach row hardware round `seats` (`recliner`):
##                      - sculpted dark-brown moulded shared armrests (the viewer's own recliner folds away while
##                        both armrests remain) with chestnut vinyl arm caps, brushed-chrome folding armrest ashtray
##                        lids and seat-recline buttons
##                      - sculpted woven cream-linen antimacassar headrest covers with subtle terracotta hem bands
##                        hugging every other headrest's exact curve
##                      - fold-down cream laminate seatback tray tables with twist latches, angled support arms and
##                        lower criss-cross magazine net pockets holding folded route leaflets

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Furniture := preload("res://scripts/env/systems/kit/furniture.gd")

const PIECES: Array[String] = ["coach_1988_cabin", "coach_1988_rows"]

## Palette (sRGB): 1988 British/European touring coach warm cream, chestnut/chocolate vinyl, walnut veneer, burgundy
## cab drape, charcoal ABS/steel, brushed chrome & brass, signal emergency red, retro rental-case colours.
const CRT_BODY := Color(0.11, 0.11, 0.12)
const CRT_BEZEL := Color(0.075, 0.078, 0.085)
const STEEL_DARK := Color(0.16, 0.17, 0.19)
const CHROME_BRUSH := Color(0.76, 0.78, 0.80)
const BRASS_WARM := Color(0.86, 0.68, 0.30)
const COACH_CREAM := Color(0.84, 0.79, 0.70)
const WALNUT_TRIM := Color(0.32, 0.19, 0.11)
const CAB_CURTAIN := Color(0.32, 0.10, 0.11)
const WIN_CURTAIN := Color(0.82, 0.76, 0.65)
const TIE_BROWN := Color(0.28, 0.16, 0.10)
const RUBBER_DARK := Color(0.12, 0.125, 0.135)
const FLUOR_WARM := Color(1.0, 0.92, 0.78)
const ARM_BROWN := Color(0.20, 0.13, 0.095)
const ARM_CAP := Color(0.30, 0.18, 0.12)
const LINEN_CREAM := Color(0.91, 0.88, 0.81)
const HEM_RUST := Color(0.56, 0.22, 0.13)
const TRAY_CREAM := Color(0.76, 0.71, 0.63)
const EMERG_RED := Color(0.76, 0.11, 0.10)
const RENTAL_TEAL := Color(0.13, 0.48, 0.50)
const RENTAL_ORANGE := Color(0.76, 0.32, 0.13)
const RENTAL_MUSTARD := Color(0.76, 0.58, 0.18)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"coach_1988_cabin":
			_cabin(c)
		"coach_1988_rows":
			_rows(c)


# --- The 1988 touring coach cabin -------------------------------------------------------------------------------------

static func _cabin(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_aisle_and_floor(c, q)
	_forward_cab(c, q)
	_crt_and_vcr(c, q)
	_parcel_racks_and_ceiling(c, q)
	_window_bays(c, q)
	_aft_bulkhead(c, q)


## Ribbed dark-rubber central aisle runner with brushed-aluminium carpet trim strips and continuous night-driving
## floor guide strips (`PieceCove`) down both aisle edges.
static func _aisle_and_floor(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var span := bz - fz - 0.22
	var mid_z := (fz + bz) * 0.5
	var runner_w := clampf(float(q["aisle"]) - 0.08, 0.28, 0.46)
	var half_w := runner_w * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	# Dark charcoal ribbed rubber floor matting down the central aisle.
	s.surface(c.tinted("iron"))
	s.colour = RUBBER_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.004, mid_z), Vector3(runner_w, 0.008, span), Basis(), [RoomMesh.DOWN])
	# Longitudinal raised anti-slip rubber ribs along the aisle tread.
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.08, 0.085, 0.092).srgb_to_linear()
	for k in 5:
		var rx := cx + lerpf(-half_w + 0.035, half_w - 0.035, float(k) / 4.0)
		u.box(Vector3(rx, 0.010, mid_z), Vector3(0.014, 0.004, span - 0.08), Basis(), [RoomMesh.DOWN])
	# Brushed-aluminium edge carpet-grip strips flanking the rubber aisle runner.
	u.surface(c.shiny("chrome", 0.9, 0.72, 0.16))
	u.colour = CHROME_BRUSH.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * (half_w + 0.011), 0.006, mid_z), Vector3(0.022, 0.011, span), Basis(),
				[RoomMesh.DOWN])
	# Low night-driving floor guide LED strips tucked along the aisle trim edges (PieceCove).
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.95, 0.96, 0.98).srgb_to_linear()
	cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.96)
	var z0 := fz + 0.85
	var z1 := bz - 0.35
	for side: float in [-1.0, 1.0]:
		var x_in := cx + side * (half_w + 0.004)
		var x_out := cx + side * (half_w + 0.022)
		var y_strip := 0.013
		var a := Vector3(x_in, y_strip, z0)
		var b := Vector3(x_out, y_strip, z0)
		var d := Vector3(x_out, y_strip, z1)
		var e := Vector3(x_in, y_strip, z1)
		if side > 0.0:
			cove.face([a, b, d, e], Vector3.UP)
		else:
			cove.face([b, a, e, d], Vector3.UP)
	s.colour = Color.WHITE
	u.colour = Color.WHITE
	cove.colour = Color.WHITE


## Forward driver's cab night curtain (pleated deep burgundy-brown drape with brass rings on a chrome rail hiding the
## cab cleanly — zero people), upper moulded header valance, twin cream-and-walnut laminate front-row modesty screens,
## and curved brushed-chrome entry stairwell grab rails.
static func _forward_cab(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var wall_h := float(q["wall_height"])
	var lean := float(q["L"])

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# Upper curved coach header valance panel above the driver's curtain rail (y 1.80..2.36).
	var rail_y := 1.78
	var top_hw := hw - rail_y * tan(lean) - 0.02
	s.surface(c.tinted("plastic"))
	s.colour = COACH_CREAM.srgb_to_linear()
	s.box(Vector3(cx, rail_y + 0.04, fz + 0.09), Vector3(top_hw * 2.0, 0.08, 0.14))
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_TRIM.srgb_to_linear()
	s.box(Vector3(cx, rail_y + 0.012, fz + 0.162), Vector3(top_hw * 2.0 - 0.04, 0.024, 0.012))

	# Brushed-chrome driver's curtain rail spanning across the forward bulkhead + 16 warm brass rings.
	var rail_z := fz + 0.145
	var rail_half := top_hw - 0.03
	u.surface(c.shiny("chrome", 0.9, 0.74, 0.14))
	u.colour = CHROME_BRUSH.srgb_to_linear()
	Shapes.cylinder(u, Vector3(cx - rail_half, rail_y, rail_z), 0.013, rail_half * 2.0, 8,
			Basis(Vector3.BACK, -PI * 0.5))
	# Brass curtain rings spaced evenly along the rail.
	u.colour = BRASS_WARM.srgb_to_linear()
	var n_rings := 16
	for i in n_rings:
		var rx := cx + lerpf(-rail_half + 0.06, rail_half - 0.06, float(i) / float(n_rings - 1))
		Shapes.arch(u, Vector3(rx, rail_y - 0.004, rail_z), 0.015, 0.024, 0.008, 10,
				Basis(Vector3.UP, PI * 0.5), 0.0, TAU, ["front", "back", "outer"])

	# Pleated deep burgundy-brown driver's night curtain hanging smoothly from y 0.05 to rail_y - 0.02 across the cab.
	u.surface(c.soft("cloth", true))
	var curt_y0 := 0.04
	var curt_y1 := rail_y - 0.02
	var folds := 28
	var segs := folds * 2
	var bot_pts := PackedVector3Array()
	var top_pts := PackedVector3Array()
	var ns := PackedVector3Array()
	var bot_cols := PackedColorArray()
	var top_cols := PackedColorArray()
	var curtain_hw := hw - 0.05
	for i in segs + 1:
		var t := float(i) / float(segs)
		var x_bot := cx + lerpf(-curtain_hw, curtain_hw, t)
		var x_top := cx + lerpf(-rail_half, rail_half, t)
		var wave := sin(t * float(folds) * PI)
		var dz := 0.032 * wave
		# Subtle centre parting tuck where the two drawn halves overlap.
		var seam := 1.0 - 0.45 * exp(-pow((t - 0.5) * 28.0, 2.0))
		var z_at := rail_z + dz * seam
		bot_pts.append(Vector3(x_bot, curt_y0, z_at + 0.008))
		top_pts.append(Vector3(x_top, curt_y1, z_at))
		var slope_x := cos(t * float(folds) * PI) * 0.55
		ns.append(Vector3(-slope_x, 0.0, 1.0).normalized())
		var shade_v := 0.72 + 0.28 * (0.5 + 0.5 * wave)
		var col_top := (CAB_CURTAIN * (shade_v * 1.06)).srgb_to_linear()
		var col_bot := (CAB_CURTAIN * (shade_v * 0.78)).srgb_to_linear()
		top_cols.append(col_top)
		bot_cols.append(col_bot)
	u.grid([bot_pts, top_pts], [ns, ns], [bot_cols, top_cols])

	# Classic 1988 coach front-row modesty screens (cream laminate + walnut woodgrain inlay + padded brown crash top)
	# and curved brushed-chrome entry stairwell grab rails ahead of row +2 (z = -3.62).
	var mod_z := fz + 1.18
	var mod_h := 0.94
	var half_aisle := float(q["aisle"]) * 0.5 + 0.05
	for side: float in [-1.0, 1.0]:
		var wall_x := cx + side * (hw - mod_h * 0.5 * tan(lean) - 0.03)
		var aisle_x := cx + side * half_aisle
		var mw := absf(wall_x - aisle_x)
		var mx := (wall_x + aisle_x) * 0.5
		# Cream laminate structural modesty screen.
		s.surface(c.tinted("plastic"))
		s.colour = COACH_CREAM.srgb_to_linear()
		s.box(Vector3(mx, mod_h * 0.5, mod_z), Vector3(mw, mod_h, 0.042), Basis(), [RoomMesh.DOWN])
		# Walnut woodgrain recessed decorative panel on the passenger-facing side.
		s.surface(c.tinted("wood"))
		s.colour = WALNUT_TRIM.srgb_to_linear()
		s.box(Vector3(mx, mod_h * 0.54, mod_z + 0.024), Vector3(mw - 0.10, mod_h * 0.62, 0.012), Basis(),
				[RoomMesh.FRONT])
		# Padded chocolate-brown vinyl crash lip along the top of the modesty panel.
		u.surface(c.soft("plastic", true))
		u.colour = ARM_CAP.srgb_to_linear()
		u.rounded_box(Vector3(mx, mod_h + 0.025, mod_z), Vector3(mw + 0.01, 0.055, 0.068), 0.02, Transform3D(), 1)
		# Curved brushed-chrome coach entry stairwell grab rail rising from the aisle corner and sweeping forward
		# toward the kerbside entry bay.
		u.surface(c.shiny("chrome", 0.9, 0.74, 0.14))
		u.colour = CHROME_BRUSH.srgb_to_linear()
		var gx := aisle_x + side * 0.02
		# Vertical floor-to-top stanchion post at the aisle edge of the modesty panel.
		Shapes.cylinder(u, Vector3(gx, 0.0, mod_z + 0.025), 0.016, mod_h + 0.09, 8)
		# Horizontal chrome handhold bar across the top of the modesty screen.
		Shapes.cylinder(u, Vector3(minf(gx, wall_x), mod_h + 0.09, mod_z + 0.025), 0.015, absf(wall_x - gx), 8,
				Basis(Vector3.BACK, -PI * 0.5))
		# Forward stairwell balustrade rail sweeping toward the cab doorway on the kerbside (-1) and parcel bay (+1).
		var rail_end_z := fz + 0.42
		Shapes.cylinder(u, Vector3(gx, mod_h + 0.09, rail_end_z), 0.015, mod_z + 0.025 - rail_end_z, 8,
				Basis(Vector3.RIGHT, PI * 0.5))
		Shapes.cylinder(u, Vector3(gx, 0.0, rail_end_z), 0.016, mod_h + 0.09, 8)
		# Neat rounded elbow joints at the top stanchion corners.
		u.rounded_box(Vector3(gx, mod_h + 0.09, mod_z + 0.025), Vector3(0.036, 0.036, 0.036), 0.014, Transform3D(), 1)
		u.rounded_box(Vector3(gx, mod_h + 0.09, rail_end_z), Vector3(0.036, 0.036, 0.036), 0.014, Transform3D(), 1)
		# Mid-height safety rail along the entry stairwell drop.
		Shapes.cylinder(u, Vector3(gx, mod_h * 0.52, rail_end_z), 0.012, mod_z + 0.025 - rail_end_z, 8,
				Basis(Vector3.RIGHT, PI * 0.5))
		# Clean physics box enclosing the modesty panel and stairwell rail (min y = 0.0, strictly inside cabin box).
		var box_h := mod_h + 0.08
		c.shapes.append(PhysicsShapes.box(Vector3(mx, box_h * 0.5, mod_z), Vector3(mw, box_h, 0.08), Basis()))

	# Subtle wall corner vertical trim posts framing the forward curtain opening on both sides.
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_TRIM.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var wx := cx + side * (hw - wall_h * 0.45 * tan(lean) - 0.03)
		s.box(Vector3(wx, rail_y * 0.5, rail_z + 0.03), Vector3(0.05, rail_y, 0.06),
				Basis(Vector3.BACK, side * lean), [RoomMesh.DOWN])

	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Ceiling-mounted 1988 4:3 CRT television in a bolted steel coach cradle + lower steel equipment shelf holding a
## flashing `12:00` video cassette deck (`PieceDisplay`) and a stack of colourful 1988 plastic rental tape cases.
static func _crt_and_vcr(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(0.80, 0.60))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var sz := sc_xf.origin.z
	var w := sc_sz.x
	var h := sc_sz.y
	var hw := w * 0.5
	var hh := h * 0.5
	var fz := float(q["front_z"])

	var bezel_side := 0.060
	var bezel_top := 0.048
	var chin_h := 0.095
	var outer_w := w + bezel_side * 2.0
	var top_y := cy + hh + bezel_top
	var bot_y := cy - hh - chin_h
	var total_h := top_y - bot_y
	var mid_y := (top_y + bot_y) * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# 1988 dark charcoal ABS CRT television bezel & deep cathode-ray cabinet housing (cleanly clear of picture face).
	s.surface(c.tinted("iron"))
	s.colour = CRT_BEZEL.srgb_to_linear()
	var bz := sz - 0.038
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * (hw + bezel_side * 0.5), mid_y, bz), Vector3(bezel_side, total_h, 0.072))
	s.box(Vector3(cx, cy + hh + bezel_top * 0.5, bz), Vector3(w, bezel_top, 0.072))
	s.box(Vector3(cx, cy - hh - chin_h * 0.5, bz), Vector3(w, chin_h, 0.072))
	# Deep main CRT cabinet behind the tube face, tapering to the cathode-ray neck housing clear of the cab curtain.
	s.colour = CRT_BODY.srgb_to_linear()
	var body_d := minf(0.28, maxf(sz - fz - 0.30, 0.16))
	s.box(Vector3(cx, mid_y, sz - 0.074 - body_d * 0.5), Vector3(outer_w - 0.016, total_h - 0.016, body_d))
	var neck_d := minf(0.22, maxf(sz - fz - 0.074 - body_d - 0.16, 0.08))
	s.box(Vector3(cx, cy + 0.02, sz - 0.074 - body_d - neck_d * 0.5), Vector3(w * 0.62, h * 0.66, neck_d))

	# Front chin hardware: recessed speaker grille slats on the left, 6 square channel push-buttons + rotary volume dial
	# on the right, chrome accent strip, and glowing green standby LED (`PieceWindows`).
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.045, 0.048, 0.055).srgb_to_linear()
	for slat in 4:
		var sy := cy - hh - 0.026 - 0.016 * slat
		u.box(Vector3(cx - hw + 0.14, sy, sz - 0.002), Vector3(0.24, 0.008, 0.008))
	# Tactile 1988 channel preset buttons in mid-right chin.
	u.colour = Color(0.22, 0.23, 0.25).srgb_to_linear()
	for k in 6:
		u.box(Vector3(cx + 0.03 + k * 0.032, cy - hh - 0.052, sz - 0.001), Vector3(0.022, 0.024, 0.010))
	# Brushed-chrome chin divider bar & small rotary control knob.
	u.surface(c.shiny("chrome", 0.9, 0.74, 0.14))
	u.colour = CHROME_BRUSH.srgb_to_linear()
	u.box(Vector3(cx, cy - hh - 0.010, sz - 0.002), Vector3(outer_w - 0.04, 0.009, 0.008))
	Shapes.cylinder(u, Vector3(cx + hw - 0.095, cy - hh - 0.052, sz - 0.004), 0.016, 0.014, 10,
			Basis(Vector3.RIGHT, PI * 0.5))
	# Green standby power LED on the lower-right bezel corner (`PieceWindows`).
	var gw: Array = c.glows.get("window", [])
	gw.append([Vector3(cx + hw - 0.028, cy - hh - 0.052, sz + 0.004), Vector3(0.010, 0.0, 0.0),
			Vector3(0.0, 0.010, 0.0), Vector3.BACK])
	c.glows["window"] = gw

	# Heavy bolted steel coach ceiling cradle suspending the CRT cleanly from the arched roof crown.
	u.surface(c.soft("plastic", true))
	u.colour = STEEL_DARK.srgb_to_linear()
	var mount_z := sz - 0.16
	# Bottom & top steel cradle yoke beams + clamping side straps.
	u.box(Vector3(cx, bot_y - 0.018, mount_z), Vector3(outer_w + 0.06, 0.036, 0.095))
	u.box(Vector3(cx, top_y + 0.016, mount_z), Vector3(outer_w + 0.06, 0.032, 0.095))
	for side: float in [-1.0, 1.0]:
		var sx := cx + side * (outer_w * 0.5 + 0.018)
		u.box(Vector3(sx, mid_y, mount_z), Vector3(0.036, total_h + 0.068, 0.072))
		# Twin steel drop struts anchored up into the arched ceiling.
		var bx := cx + side * (hw * 0.65)
		var roof_here := _roof_y(q, bx)
		var strut_h := maxf(roof_here - top_y + 0.02, 0.06)
		u.box(Vector3(bx, top_y + strut_h * 0.5, mount_z), Vector3(0.048, strut_h, 0.052))
		u.box(Vector3(bx, roof_here - 0.014, mount_z), Vector3(0.15, 0.024, 0.15))
		# Rear anti-sway tie bars bolted back to the upper front header bulkhead.
		var brace_len := maxf(mount_z - fz - 0.04, 0.14)
		u.box(Vector3(bx, top_y + 0.014, fz + 0.04 + brace_len * 0.5), Vector3(0.036, 0.036, brace_len))

	# Bolted steel video-deck shelf hanging cleanly below the CRT chin (y 1.37; well below the 1.61 m screen bottom).
	var shelf_y := bot_y - 0.145
	var shelf_z := sz - 0.07
	var shelf_w := 0.76
	var shelf_d := 0.30
	u.box(Vector3(cx, shelf_y - 0.010, shelf_z), Vector3(shelf_w, 0.020, shelf_d))
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (shelf_w * 0.5 - 0.012)
		var hanger_h := bot_y - 0.018 - shelf_y
		u.box(Vector3(px, shelf_y + hanger_h * 0.5, shelf_z + shelf_d * 0.34), Vector3(0.020, hanger_h, 0.020))
		u.box(Vector3(px, shelf_y + hanger_h * 0.5, shelf_z - shelf_d * 0.34), Vector3(0.020, hanger_h, 0.020))
	# Slim chrome retaining rail across the shelf front so the video deck & tape cases stay put on motorway bends.
	u.surface(c.shiny("chrome", 0.9, 0.74, 0.14))
	u.colour = CHROME_BRUSH.srgb_to_linear()
	Shapes.cylinder(u, Vector3(cx - shelf_w * 0.5, shelf_y + 0.024, shelf_z + shelf_d * 0.45), 0.007, shelf_w, 6,
			Basis(Vector3.BACK, -PI * 0.5))

	# 1988 video cassette recorder on the left of the shelf with flashing cyan-green `12:00` clock (`PieceDisplay`).
	var vcr_x := cx - 0.135
	var vcr_xf := Transform3D(Basis(), Vector3(vcr_x, shelf_y, shelf_z))
	s.colour = Color(0.075, 0.078, 0.088).srgb_to_linear()
	var vcr_mat: Material = c.tinted("iron")
	var win: Array = Furniture.video_recorder(s, vcr_xf, Vector3(0.41, 0.088, 0.26),
			{"body": vcr_mat, "detail": vcr_mat})
	var gd: Array = c.glows.get("display", [])
	gd.append_array(Furniture.seven_segments("12:00", win[0], win[1], win[2], win[3], win[4]))
	c.glows["display"] = gd

	# Stack of three chunky 1988 plastic rental video tape library cases sitting beside the deck (zero text/marks).
	u.surface(c.soft("plastic", true))
	var tape_x := cx + 0.225
	var tape_cols: Array[Color] = [RENTAL_TEAL, RENTAL_ORANGE, RENTAL_MUSTARD]
	var tape_yaws: Array[float] = [0.06, -0.09, 0.11]
	for k in 3:
		var ty := shelf_y + 0.015 + k * 0.030
		var b_tape := Basis(Vector3.UP, tape_yaws[k])
		u.colour = tape_cols[k].srgb_to_linear()
		u.box(Vector3(tape_x, ty, shelf_z + 0.01), Vector3(0.20, 0.028, 0.125), b_tape)
		# Pale cream library-sleeve spine stripe facing down the coach aisle.
		u.colour = LINEN_CREAM.srgb_to_linear()
		u.box(Vector3(tape_x, ty, shelf_z + 0.01) + b_tape * Vector3(0.0, 0.0, 0.064),
				Vector3(0.15, 0.014, 0.004), b_tape)

	# Single clean physics collision box enclosing the overhead CRT & VCR shelf assembly.
	var rig_lo := Vector3(cx - outer_w * 0.5 - 0.02, shelf_y - 0.02, fz + 0.04)
	var rig_hi := Vector3(cx + outer_w * 0.5 + 0.02, top_y + 0.04, sz + 0.02)
	c.shapes.append(PhysicsShapes.box((rig_lo + rig_hi) * 0.5, rig_hi - rig_lo, Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Continuous overhead parcel racks along both sides (clear of all seat sight lines), per-row passenger service pods
## with round eyeball air vents & reading lamps, recessed warm fluorescent ceiling troughs (`PieceLamps`), and live
## night-travel courtesy cove strips (`PieceCove`).
static func _parcel_racks_and_ceiling(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var wall_h := float(q["wall_height"])
	var rise := float(q["rise"])
	var lean := float(q["L"])

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	# Overhead parcel racks run along both side walls from just behind the forward cab header to the rear bulkhead.
	# Inner edge stays at x_rel = 0.64 m so back window seats have completely clear sight lines to the overhead CRT.
	var rack_z0 := fz + 0.92
	var rack_z1 := bz - 0.12
	var rack_len := rack_z1 - rack_z0
	var rack_mid := (rack_z0 + rack_z1) * 0.5
	var rack_y := 1.92
	var inner_rel := 0.64
	var wall_rel := hw - rack_y * tan(lean) - 0.015
	var rack_w := maxf(wall_rel - inner_rel, 0.36)
	var rack_mid_rel := (inner_rel + wall_rel) * 0.5

	for side: float in [-1.0, 1.0]:
		var rx := cx + side * rack_mid_rel
		var lip_x := cx + side * (inner_rel + 0.022)
		# Cream moulded luggage rack shelf deck.
		s.surface(c.tinted("plastic"))
		s.colour = COACH_CREAM.srgb_to_linear()
		s.box(Vector3(rx, rack_y + 0.022, rack_mid), Vector3(rack_w, 0.038, rack_len))
		# Soft luggage cove fascia turning up along the inner edge of the shelf.
		s.surface(c.tinted("wood"))
		s.colour = WALNUT_TRIM.srgb_to_linear()
		s.box(Vector3(cx + side * (inner_rel + 0.008), rack_y + 0.048, rack_mid), Vector3(0.024, 0.055, rack_len))
		# Padded brown-vinyl rounded overhead luggage bumper lip along the aisle edge.
		u.surface(c.soft("plastic", true))
		u.colour = ARM_CAP.srgb_to_linear()
		u.rounded_box(Vector3(lip_x, rack_y + 0.058, rack_mid), Vector3(0.056, 0.072, rack_len + 0.02), 0.022,
				Transform3D(), 1)
		# End caps closing the forward and aft ends of each parcel rack cleanly.
		s.surface(c.tinted("plastic"))
		s.colour = COACH_CREAM.srgb_to_linear()
		for ez: float in [rack_z0, rack_z1]:
			var cap_h := maxf(_roof_y(q, rx) - rack_y, 0.22)
			s.box(Vector3(rx, rack_y + cap_h * 0.5, ez), Vector3(rack_w, cap_h, 0.032))
		# Brushed-chrome continuous overhead luggage retaining rail / aisle grab bar running along the rack lip.
		u.surface(c.shiny("chrome", 0.9, 0.74, 0.14))
		u.colour = CHROME_BRUSH.srgb_to_linear()
		Shapes.cylinder(u, Vector3(cx + side * (inner_rel + 0.015), rack_y + 0.118, rack_z0), 0.012, rack_len, 8,
				Basis(Vector3.RIGHT, PI * 0.5))
		# Sleek dark-steel rack hanger struts aligned cleanly with the ceiling's interior bay ribs.
		u.surface(c.soft("plastic", true))
		u.colour = STEEL_DARK.srgb_to_linear()
		for mz: float in Cabin._bay_marks(q):
			if mz < rack_z0 + 0.35 or mz > rack_z1 - 0.35:
				continue
			var hx := cx + side * (inner_rel + 0.04)
			var top_here := _roof_y(q, hx)
			var sh := maxf(top_here - (rack_y + 0.08), 0.10)
			Shapes.cylinder(u, Vector3(hx, rack_y + 0.08, mz), 0.010, sh, 6)
		# Night-travel overhead courtesy cove strip tucked cleanly beneath the inner lip of each parcel rack.
		cove.surface(c.kit.cove_material())
		var strip_col := Color(0.95, 0.96, 0.98).srgb_to_linear()
		cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.94)
		var x_a := cx + side * (inner_rel + 0.02)
		var x_b := cx + side * (inner_rel + 0.08)
		var y_c := rack_y + 0.001
		var p0 := Vector3(x_a, y_c, rack_z0 + 0.18)
		var p1 := Vector3(x_b, y_c, rack_z0 + 0.18)
		var p2 := Vector3(x_b, y_c, rack_z1 - 0.18)
		var p3 := Vector3(x_a, y_c, rack_z1 - 0.18)
		if side < 0.0:
			cove.face([p0, p1, p2, p3], Vector3.DOWN)
		else:
			cove.face([p1, p0, p3, p2], Vector3.DOWN)

	# Per-row Passenger Service Units (PSUs) underneath both parcel racks: dark moulded console pod, twin round
	# eyeball air-jet vents, twin recessed reading-lamp rings and a tiny attendant call dot.
	var pitch := float(q["row_pitch"])
	for row in range(-int(q["rows_back"]), int(q["rows_front"]) + 1):
		var rz := -row * pitch - 0.05
		if rz < rack_z0 + 0.2 or rz > rack_z1 - 0.2:
			continue
		for side: float in [-1.0, 1.0]:
			var px := cx + side * (inner_rel + 0.22)
			u.surface(c.soft("plastic", true))
			u.colour = ARM_BROWN.srgb_to_linear()
			u.box(Vector3(px, rack_y - 0.004, rz), Vector3(0.24, 0.016, 0.14))
			# Twin eyeball jet-vents & reading-lamp surrounds (inner seat + window seat).
			for seat_off: float in [-0.055, 0.055]:
				var vx := px + seat_off
				u.colour = STEEL_DARK.srgb_to_linear()
				Shapes.cylinder(u, Vector3(vx, rack_y - 0.022, rz - 0.025), 0.024, 0.016, 8)
				u.colour = COACH_CREAM.srgb_to_linear()
				Shapes.cylinder(u, Vector3(vx, rack_y - 0.018, rz + 0.032), 0.017, 0.012, 8)
			u.surface(c.shiny("chrome", 0.9, 0.72, 0.16))
			u.colour = CHROME_BRUSH.srgb_to_linear()
			for seat_off: float in [-0.055, 0.055]:
				Shapes.cylinder(u, Vector3(px + seat_off, rack_y - 0.024, rz - 0.025), 0.011, 0.006, 6)

	# Recessed warm-white fluorescent ceiling diffuser troughs down the arched roof centreline (`PieceLamps`, house).
	var crown_y := wall_h + rise - 0.022
	lit.surface(c.shade(FLUOR_WARM))
	s.surface(c.tinted("plastic"))
	s.colour = COACH_CREAM.srgb_to_linear()
	# Longitudinal ceiling trim rails flanking the central light channel.
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * 0.165, crown_y + 0.004, rack_mid), Vector3(0.035, 0.026, rack_len))
	var n_panels := 4
	for i in n_panels:
		var pz := lerpf(fz + 1.55, bz - 0.80, float(i) / maxf(n_panels - 1, 1))
		# Crisp transverse diffuser clips along each fluorescent luminaire.
		for k in 3:
			var lz := pz - 0.36 + 0.36 * k
			s.box(Vector3(cx, crown_y - 0.008, lz), Vector3(0.28, 0.010, 0.018))
		# Glowing warm-white acrylic diffuser face pointing down into the coach aisle.
		lit.face([Vector3(cx - 0.135, crown_y - 0.006, pz - 0.50), Vector3(cx + 0.135, crown_y - 0.006, pz - 0.50),
				Vector3(cx + 0.135, crown_y - 0.006, pz + 0.50), Vector3(cx - 0.135, crown_y - 0.006, pz + 0.50)],
				Vector3.DOWN)
		if i == 0 or i == 1 or i == 2:
			c.lamps.append([Vector3(cx, crown_y - 0.16, pz), FLUOR_WARM, 0.72])

	s.colour = Color.WHITE
	u.colour = Color.WHITE
	cove.colour = Color.WHITE


## Cream pleated window curtains tied back cleanly between bays on chrome tracks, under-sill heater convector ducts,
## and signal-red break-glass emergency hammer boxes (`PieceGlass`) mounted on mid-cabin window pillars.
static func _window_bays(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var lean := float(q["L"])
	var sill := float(q["window_sill"])
	var wh := float(q["window_height"])
	var wzs: Array = q["window_zs"]
	if wzs.is_empty():
		return
	var marks: Array[float] = Cabin._bay_marks(q)
	var track_z0 := float(wzs[0]) - float(q["window_width"]) * 0.52
	var track_z1 := float(wzs[-1]) + float(q["window_width"]) * 0.52
	var track_len := track_z1 - track_z0
	var track_y := sill + wh + 0.025
	var v_bot := (sill + 0.022) / cos(lean)
	var v_top := track_y / cos(lean)
	var v_mid := lerpf(v_bot, v_top, 0.44)

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# Continuous brushed-chrome window curtain tracks above the windows on both sides.
	u.surface(c.shiny("chrome", 0.9, 0.74, 0.14))
	u.colour = CHROME_BRUSH.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var p_start := Cabin._pt(q, side, track_z0, v_top) + Cabin._n(q, side) * 0.025
		Shapes.cylinder(u, p_start, 0.008, track_len, 6, Basis(Vector3.RIGHT, PI * 0.5))

	# Signal-red break-glass emergency hammer boxes mounted cleanly on two mid-cabin window pillars (`PieceGlass`).
	var hammer_places: Array = []
	if marks.size() >= 4:
		hammer_places = [[1.0, marks[2]], [-1.0, marks[3]]]
	elif not marks.is_empty():
		hammer_places = [[1.0, marks[0]]]

	# Cream pleated side-window curtains gathered neatly with chocolate-brown tiebacks at every bay pillar (skipped
	# at the two emergency-hammer pillar centres so the red break-glass hammer boxes read crisply unobstructed).
	u.surface(c.soft("cloth", true))
	for side: float in [-1.0, 1.0]:
		var n := Cabin._n(q, side)
		var wb := Cabin._wall_basis(q, side)
		for mz: float in marks:
			var has_hammer := false
			for hp: Array in hammer_places:
				if is_equal_approx(float(hp[0]), side) and absf(float(hp[1]) - mz) < 0.05:
					has_hammer = true
			if has_hammer:
				continue
			# Gathered curtain tucked closely against the pillar (total width ~0.22 m, keeping the panoramic
			# night-motorway windows wide open!).
			var rows_v: Array[float] = [v_bot, lerpf(v_bot, v_mid, 0.5), v_mid, lerpf(v_mid, v_top, 0.55), v_top]
			var widths: Array[float] = [0.105, 0.088, 0.056, 0.085, 0.115]
			var grid_pts: Array = []
			var grid_ns: Array = []
			var grid_cols: Array = []
			var n_pleats := 6
			for r in rows_v.size():
				var row_p := PackedVector3Array()
				var row_n := PackedVector3Array()
				var row_c := PackedColorArray()
				var half_span := widths[r]
				for j in n_pleats + 1:
					var frac := float(j) / float(n_pleats)
					var dz := lerpf(-half_span, half_span, frac)
					var pleat := sin(frac * 3.0 * PI)
					var depth := 0.044 + 0.014 * (0.5 + 0.5 * pleat)
					var pt := Cabin._pt(q, side, mz + dz, rows_v[r]) + n * depth
					row_p.append(pt)
					var pnorm := (n + Vector3(0.0, 0.0, cos(frac * 3.0 * PI) * 0.35)).normalized()
					row_n.append(pnorm)
					var sh := 0.80 + 0.20 * (0.5 + 0.5 * pleat)
					row_c.append((WIN_CURTAIN * sh).srgb_to_linear())
				grid_pts.append(row_p)
				grid_ns.append(row_n)
				grid_cols.append(row_c)
			u.grid(grid_pts, grid_ns, grid_cols)
			# Chocolate-brown woven curtain tieback strap cinching the waist.
			var waist := Cabin._pt(q, side, mz, v_mid) + n * 0.048
			u.colour = TIE_BROWN.srgb_to_linear()
			u.box(waist, Vector3(0.135, 0.036, 0.034), wb)
			u.colour = Color.WHITE

	for hp: Array in hammer_places:
		var side := float(hp[0])
		var hz := float(hp[1])
		var n := Cabin._n(q, side)
		var wb := Cabin._wall_basis(q, side)
		var box_at := Cabin._pt(q, side, hz, 1.50 / cos(lean)) + n * 0.032
		# Recessed signal-red metal frame box.
		s.surface(c.tinted("iron"))
		s.colour = EMERG_RED.srgb_to_linear()
		s.box(box_at - n * 0.018, Vector3(0.125, 0.225, 0.014), wb)
		for es: float in [-1.0, 1.0]:
			s.box(box_at + wb.x * (es * 0.056), Vector3(0.014, 0.225, 0.052), wb)
			s.box(box_at + wb.y * (es * 0.106), Vector3(0.125, 0.014, 0.052), wb)
		# Bright white inner backing panel so the red emergency hammer silhouette reads crisply behind the glass.
		u.surface(c.soft("plastic", true))
		u.colour = LINEN_CREAM.srgb_to_linear()
		u.box(box_at - n * 0.008, Vector3(0.098, 0.195, 0.006), wb)
		# Red emergency hammer grip + chrome dual-point steel glass-breaker head mounted inside.
		u.colour = EMERG_RED.srgb_to_linear()
		u.box(box_at - wb.y * 0.022 + n * 0.006, Vector3(0.026, 0.130, 0.018), wb)
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = CHROME_BRUSH.srgb_to_linear()
		u.box(box_at + wb.y * 0.054 + n * 0.006, Vector3(0.084, 0.026, 0.020), wb)
		# Single-surface break-glass front pane (`PieceGlass`, no double-layer milky box overdraw).
		c.glass.surface(c.mat("tin"))
		Shapes.quad(c.glass, box_at + n * 0.026, wb.x * 0.050, wb.y * 0.098, n)

	# Low under-dado perimeter coach heater convector ducts tucked flush along both floor walls.
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.24, 0.20, 0.17).srgb_to_linear()
	var duct_len := bz - fz - 1.4
	var duct_mid := (fz + 1.15 + bz - 0.25) * 0.5
	for side: float in [-1.0, 1.0]:
		var dx := cx + side * (hw - 0.036)
		u.box(Vector3(dx, 0.09, duct_mid), Vector3(0.058, 0.16, duct_len), Basis(), [RoomMesh.DOWN])

	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Aft WC / stairwell vestibule bulkhead: stainless door kick-plate & push-bar, backlit green geometric EXIT placard
## (`PieceWindows`), working 1988 quartz bulkhead clock (`PieceClock`), framed coach emergency safety diagram, and
## chrome coat hooks.
static func _aft_bulkhead(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis_aft := Basis(Vector3.UP, PI)

	# Walnut frame & stainless kick-plate + horizontal crash push-bar on the aft WC/exit vestibule door.
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_TRIM.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * 0.33, 0.94, bz - 0.016), Vector3(0.04, 1.88, 0.024), Basis(), [RoomMesh.BACK])
	s.box(Vector3(cx, 1.88, bz - 0.016), Vector3(0.70, 0.04, 0.024), Basis(), [RoomMesh.BACK])

	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = CHROME_BRUSH.srgb_to_linear()
	u.box(Vector3(cx, 0.15, bz - 0.024), Vector3(0.56, 0.28, 0.008))
	u.box(Vector3(cx, 0.96, bz - 0.052), Vector3(0.48, 0.038, 0.022))
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.21, 0.96, bz - 0.034), Vector3(0.030, 0.050, 0.030))

	# Backlit green geometric EXIT placard above the aft door (`PieceWindows`, pure geometric doorway + arrow, no text).
	s.surface(c.tinted("iron"))
	s.colour = STEEL_DARK.srgb_to_linear()
	var ex_y := 2.02
	s.box(Vector3(cx, ex_y, bz - 0.046), Vector3(0.44, 0.18, 0.085))
	var gw: Array = c.glows.get("window", [])
	gw.append([Vector3(cx, ex_y, bz - 0.092), Vector3(-0.19, 0.0, 0.0), Vector3(0.0, 0.068, 0.0), Vector3.FORWARD])
	c.glows["window"] = gw
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.95, 0.98, 0.96).srgb_to_linear()
	u.box(Vector3(cx + 0.10, ex_y, bz - 0.096), Vector3(0.065, 0.095, 0.005))
	u.box(Vector3(cx - 0.065, ex_y, bz - 0.096), Vector3(0.115, 0.020, 0.005))
	u.box(Vector3(cx - 0.115, ex_y + 0.020, bz - 0.096), Vector3(0.050, 0.015, 0.005), Basis(Vector3.BACK, 0.65))
	u.box(Vector3(cx - 0.115, ex_y - 0.020, bz - 0.096), Vector3(0.050, 0.015, 0.005), Basis(Vector3.BACK, -0.65))

	# Working 1988 quartz bulkhead clock mounted on the port aft bulkhead panel (`PieceClock`, live wall time).
	var clk_x := cx - hw * 0.58
	var clk_y := 1.62
	var clk_r := 0.145
	s.surface(c.tinted("iron"))
	s.colour = ARM_BROWN.srgb_to_linear()
	s.box(Vector3(clk_x, clk_y, bz - 0.025), Vector3(clk_r * 2.45, clk_r * 2.45, 0.045), Basis(), [RoomMesh.BACK])
	u.surface(c.shiny("chrome", 0.92, 0.76, 0.14))
	u.colour = BRASS_WARM.srgb_to_linear()
	Shapes.arch(u, Vector3(clk_x, clk_y, bz - 0.048), clk_r, clk_r + 0.022, 0.036, 20, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	c.clocks.append([Vector3(clk_x, clk_y, bz - 0.056), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# Starboard aft bulkhead: framed geometric coach safety & WC pictogram placard (zero text/marks).
	var px := cx + hw * 0.58
	s.surface(c.tinted("plastic"))
	s.colour = COACH_CREAM.srgb_to_linear()
	s.box(Vector3(px, 1.56, bz - 0.014), Vector3(0.38, 0.44, 0.022), Basis(), [RoomMesh.BACK])
	u.surface(c.soft("plastic", true))
	u.colour = RENTAL_TEAL.srgb_to_linear()
	u.box(Vector3(px, 1.70, bz - 0.027), Vector3(0.33, 0.075, 0.006))
	u.colour = EMERG_RED.srgb_to_linear()
	u.box(Vector3(px - 0.07, 1.56, bz - 0.027), Vector3(0.12, 0.09, 0.006))
	u.colour = Color(0.22, 0.24, 0.28).srgb_to_linear()
	for bar in 4:
		u.box(Vector3(px + 0.06, 1.60 - 0.045 * bar, bz - 0.027), Vector3(0.11, 0.014, 0.005))
	# Pair of small chrome coat hooks on the aft bulkhead pillars.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = CHROME_BRUSH.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var hx := cx + side * (hw - 0.24)
		u.box(Vector3(hx, 1.38, bz - 0.020), Vector3(0.024, 0.065, 0.016))
		u.box(Vector3(hx, 1.36, bz - 0.042), Vector3(0.014, 0.016, 0.036))

	s.colour = Color.WHITE
	u.colour = Color.WHITE


# --- The 1988 touring coach rows' hardware ----------------------------------------------------------------------------

## Moulded brown coach armrests (with folding chrome ashtray caps and recline buttons), woven cream-linen antimacassar
## headrest covers with terracotta hem bands, fold-down cream laminate seatback tray tables, and lower magazine net
## pockets holding folded route leaflets.
static func _rows(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var slots: Array = Cabin.seat_slots_for(c.builder_params)
	if slots.is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	var pitch := float(q["seat_pitch"])
	# seats.gd _recliner width is `w - RECLINER_ARM (0.14) - 0.01`; a 0.105 m contoured coach armrest fits crisply
	# between adjacent seats and clears the leaning side walls cleanly.
	var wi := pitch - 0.15
	var arm_w := 0.102
	var arm_h := 0.56
	var arm_d := 0.56
	var arm_z := -0.075
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15.0)), Vector3(0.0, 0.46, 0.12))

	var u: RoomMesh = c.u

	# Collect unique armrest positions across each row block (between paired seats and at both aisle & window ends).
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

	# Draw moulded brown coach armrests with padded chestnut vinyl caps.
	u.surface(c.soft("plastic", true))
	for at: Vector3 in arm_places.values():
		u.colour = ARM_BROWN.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h * 0.5, arm_z), Vector3(arm_w, arm_h, arm_d), Basis(), [RoomMesh.DOWN])
		u.colour = ARM_CAP.srgb_to_linear()
		u.rounded_box(at + Vector3(0.0, arm_h + 0.018, arm_z - 0.01), Vector3(arm_w + 0.010, 0.036, arm_d + 0.018),
				0.012, Transform3D(), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])

	# Classic 1988 chrome flip-lid armrest ashtrays + round seat-recline push buttons.
	u.surface(c.shiny("chrome", 0.9, 0.72, 0.16))
	u.colour = CHROME_BRUSH.srgb_to_linear()
	for at: Vector3 in arm_places.values():
		u.box(at + Vector3(0.0, arm_h + 0.038, arm_z - arm_d * 0.34), Vector3(0.056, 0.008, 0.070))
		u.box(at + Vector3(0.0, arm_h + 0.038, arm_z - arm_d * 0.12), Vector3(0.022, 0.009, 0.022))

	# Sculpted woven cream-linen antimacassar headrest covers slipping concentrically over every headrest (except viewer's).
	u.surface(c.soft("cloth", true))
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		var anti_w := maxf(wi - 0.036, 0.20)
		u.colour = LINEN_CREAM.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.650, -0.008), Vector3(anti_w, 0.258, 0.148), 0.062, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])
		# Stitched woven terracotta-rust hem band inset cleanly across the lower front face (zero overhang).
		u.colour = HEM_RUST.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.592, -0.080), Vector3(maxf(anti_w - 0.086, 0.12), 0.018, 0.008), 0.004, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.BACK])

	# Full-height inner shell front-closure panel behind each recliner (closing `seats.gd _recliner`'s taller rear
	# shell cleanly from front & side angles with zero floating bar), plus fold-down cream laminate seatback tray
	# tables, dark-brown turn latches, lower magazine net pockets & leaflets.
	u.surface(c.soft("plastic", true))
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.colour = Color(0.28, 0.17, 0.11).srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.41, 0.070), Vector3(wi + 0.008, 0.82, 0.034), 0.016, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])
		var tray_w := maxf(wi - 0.04, 0.22)
		# Folded-up cream laminate seatback tray table hugging the rear shell curvature (`bend -0.35`).
		u.colour = TRAY_CREAM.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.435, 0.127), Vector3(tray_w, 0.23, 0.016), 0.006, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.FRONT])
		# Twist catch latch at top + lower hinge bar.
		u.colour = ARM_BROWN.srgb_to_linear()
		u.box(t_world * Vector3(0.0, 0.564, 0.128), Vector3(0.044, 0.022, 0.016), t_world.basis)
		u.box(t_world * Vector3(0.0, 0.308, 0.125), Vector3(tray_w - 0.01, 0.018, 0.016), t_world.basis)
		# Lower woven magazine net pocket: elastic upper bar, lower clamp bar, criss-cross cords & tucked leaflet.
		var net_w := tray_w - 0.02
		u.colour = STEEL_DARK.srgb_to_linear()
		u.box(t_world * Vector3(0.0, 0.255, 0.136), Vector3(net_w, 0.014, 0.014), t_world.basis)
		u.box(t_world * Vector3(0.0, 0.075, 0.129), Vector3(net_w, 0.014, 0.012), t_world.basis)
		# Crisscross net cord struts giving a tactile 1988 seatback mesh pocket silhouette.
		for k in 3:
			var nx := lerpf(-net_w * 0.34, net_w * 0.34, float(k) / 2.0)
			u.box(t_world * Vector3(nx, 0.165, 0.135), Vector3(0.009, 0.185, 0.008),
					t_world.basis * Basis(Vector3.BACK, 0.34))
			u.box(t_world * Vector3(nx, 0.165, 0.135), Vector3(0.009, 0.185, 0.008),
					t_world.basis * Basis(Vector3.BACK, -0.34))
		# Corner of a folded retro teal-and-cream coach route leaflet peeking out of the magazine pocket.
		u.colour = RENTAL_TEAL.srgb_to_linear()
		u.box(t_world * Vector3(0.035, 0.205, 0.128), Vector3(0.088, 0.145, 0.006),
				t_world.basis * Basis(Vector3.BACK, -0.08))
		u.colour = LINEN_CREAM.srgb_to_linear()
		u.box(t_world * Vector3(0.032, 0.235, 0.131), Vector3(0.068, 0.036, 0.003),
				t_world.basis * Basis(Vector3.BACK, -0.08))

	u.colour = Color.WHITE


## Roof height of the cabin's arched ceiling at world x.
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
