extends RefCounted

## The Night Ferry 1994 video lounge (docs/environments/rooms/night_ferry_1994.md): a 1994 North Sea / cross-Channel
## passenger ferry's Pullman video lounge dressed over a `cabin` builder and `seats` (`recliner`) rows.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips and lathed shapes; no people, no
## real mark, no ferry-company livery or badge.
##
##   ferry_lounge   the lounge's 1994 marine craft:
##                  - ceiling-bracketed 1994 big-screen 4:3 CRT television on twin bolted steel marine drop-struts
##                    with speaker grilles, recessed control flap, green standby LED, deep cathode-ray casing,
##                    armoured umbilical conduit, and a locked steel VCR shelf cage underneath holding a VHS deck
##                    with a glowing 12:00 clock (`PieceDisplay`)
##                  - recessed overhead acoustic ceiling grid with four glowing fluorescent diffuser panels
##                    (`PieceLamps`, house group) and live night-crossing cove strips (`PieceCove`)
##                  - bolted brushed-steel marine storm grab-rails beneath every window sill
##                  - two laminate window-bay side tables with anti-roll fiddle lips, takeaway coffee cups and folded
##                    crossing timetables
##                  - aft steel bulkhead with a glass-fronted red fire-hose reel cabinet (`PieceGlass`), backlit
##                    green geometric EXIT pictogram box (`PieceWindows`), lifebuoy safety placard, stainless door
##                    push-bar & kick-plate, and a working brushed-steel ship's bulkhead clock (`PieceClock`)
##                  - wet exterior promenade deck white steel bulwark rails, bolted international-orange marine
##                    lifebuoy rings outside the middle windows, and exterior deck bulkhead lamps
##   ferry_rows     the Pullman recliner rows' hardware round `seats` (`recliner`):
##                  - chunky 1994 moulded dark-grey shared armrests between seats and at row ends (the viewer's own
##                    recliner folds away while both its armrests remain), with brushed-steel recline buttons and
##                    recessed flip-lid armrest ashtrays
##                  - crisp white linen antimacassar headrest covers draped neatly over every other seat's headrest
##                  - flip-up pale-grey laminate seatback tray tables with raised cup rings and latches
##                  - subtle night-crossing aisle step strips (`PieceCove`) along the aisle-facing armrest bases

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")
const Furniture := preload("res://scripts/env/systems/kit/furniture.gd")

const PIECES: Array[String] = ["ferry_lounge", "ferry_rows"]

## Palette (sRGB): utilitarian 1994 maritime grey, dark ABS plastic, signal safety red/orange, warm takeaway paper.
const CRT_BODY := Color(0.11, 0.12, 0.135)
const CRT_BEZEL := Color(0.08, 0.085, 0.095)
const STEEL_DARK := Color(0.18, 0.21, 0.24)
const STEEL_BRUSH := Color(0.74, 0.78, 0.81)
const CEILING_TILE := Color(0.76, 0.79, 0.81)
const FLUOR_LIGHT := Color(0.92, 0.96, 1.0)
const ARM_BODY := Color(0.16, 0.18, 0.21)
const ARM_CAP := Color(0.1, 0.11, 0.13)
const TRAY_GREY := Color(0.62, 0.65, 0.68)
const LINEN_WHITE := Color(0.9, 0.91, 0.88)
const FIRE_RED := Color(0.72, 0.1, 0.1)
const LIFE_ORANGE := Color(0.92, 0.34, 0.06)
const RAIL_WHITE := Color(0.82, 0.85, 0.87)
const LAMINATE := Color(0.68, 0.72, 0.74)
const TEAL_TIMETABLE := Color(0.12, 0.48, 0.54)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"ferry_lounge":
			_lounge(c)
		"ferry_rows":
			_rows(c)


# --- The 1994 ferry video lounge --------------------------------------------------------------------------------------

static func _lounge(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_crt_rig(c, q)
	_ceiling_and_lights(c, q)
	_window_bays(c, q)
	_side_tables(c, q)
	_aft_bulkhead(c, q)
	_exterior_deck(c, q)


## Ceiling-bracketed 1994 big-screen 4:3 CRT television, bolted twin-strut marine mount, armoured umbilical conduit
## and locked steel VCR shelf cage underneath holding a glowing VHS deck.
static func _crt_rig(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(1.56, 1.17))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var sz := sc_xf.origin.z
	var w := sc_sz.x
	var h := sc_sz.y
	var hw := w * 0.5
	var hh := h * 0.5
	var fz := float(q["front_z"])
	var roof_y := float(q["headroom"])

	var bezel_side := 0.085
	var bezel_top := 0.09
	var chin_h := 0.16
	var outer_w := w + bezel_side * 2.0
	var top_y := cy + hh + bezel_top
	var bot_y := cy - hh - chin_h
	var total_h := top_y - bot_y
	var mid_y := (top_y + bot_y) * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	# Dark charcoal ABS bezel framing the screen face cleanly without obstructing the picture (one vertex-tinted baked
	# iron material shared by the CRT cabinet, VCR deck, steel mounts and fire-hose cabinet to keep draws lean).
	s.surface(c.tinted("iron"))
	s.colour = CRT_BEZEL.srgb_to_linear()
	var bz := sz - 0.035
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * (hw + bezel_side * 0.5), mid_y, bz), Vector3(bezel_side, total_h, 0.09))
	s.box(Vector3(cx, cy + hh + bezel_top * 0.5, bz), Vector3(w, bezel_top, 0.09))
	s.box(Vector3(cx, cy - hh - chin_h * 0.5, bz), Vector3(w, chin_h, 0.09))
	# Deep main CRT cabinet casing behind the tube face, tapering into the cathode-ray neck housing.
	s.colour = CRT_BODY.srgb_to_linear()
	var body_d := minf(0.32, maxf(sz - fz - 0.24, 0.16))
	s.box(Vector3(cx, mid_y, sz - 0.08 - body_d * 0.5), Vector3(outer_w - 0.02, total_h - 0.02, body_d))
	var neck_d := maxf(sz - fz - 0.08 - body_d - 0.04, 0.12)
	s.box(Vector3(cx, cy + 0.04, sz - 0.08 - body_d - neck_d * 0.5), Vector3(w * 0.62, h * 0.68, neck_d))
	# Recessed dark-metal chin speaker grilles flanking the front control flap.
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.05, 0.055, 0.065).srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		for slat in 4:
			var sy := cy - hh - 0.04 - 0.026 * slat
			u.box(Vector3(cx + side * (hw - 0.2), sy, sz + 0.012), Vector3(0.36, 0.012, 0.01))
	# Subtle brushed-chrome trim line across the lower chin and control door recess.
	u.surface(c.shiny("chrome", 0.9, 0.75, 0.14))
	u.colour = STEEL_BRUSH.srgb_to_linear()
	u.box(Vector3(cx, cy - hh - 0.012, sz + 0.012), Vector3(outer_w - 0.06, 0.012, 0.01))
	u.box(Vector3(cx, cy - hh - 0.095, sz + 0.012), Vector3(0.28, 0.065, 0.012))
	# Tiny green standby power LED on the right of the lower bezel (steady accent glow).
	var gw: Array = c.glows.get("window", [])
	gw.append([Vector3(cx + hw - 0.04, cy - hh - 0.09, sz + 0.018), Vector3(0.014, 0.0, 0.0),
			Vector3(0.0, 0.014, 0.0), Vector3.BACK])
	c.glows["window"] = gw

	# Heavy bolted marine steel ceiling gantry bracket: twin vertical C-channels, cradle yoke, rear wall sway struts,
	# ceiling anchor plates, and armoured power/coax umbilical rising into the deckhead.
	u.surface(c.soft("plastic", true))
	u.colour = STEEL_DARK.srgb_to_linear()
	var mount_z := sz - 0.22
	var strut_h := maxf(roof_y - top_y + 0.06, 0.14)
	# Cradle yoke beam under the CRT and clamping side straps.
	u.box(Vector3(cx, bot_y - 0.025, mount_z), Vector3(outer_w + 0.08, 0.05, 0.12))
	u.box(Vector3(cx, top_y + 0.025, mount_z), Vector3(outer_w + 0.08, 0.045, 0.12))
	for side: float in [-1.0, 1.0]:
		var sx := cx + side * (outer_w * 0.5 + 0.025)
		u.box(Vector3(sx, mid_y, mount_z), Vector3(0.045, total_h + 0.09, 0.09))
		# Ceiling drop-struts up to bolted ceiling plates.
		var bx := cx + side * (hw * 0.62)
		u.box(Vector3(bx, top_y + strut_h * 0.5, mount_z), Vector3(0.065, strut_h, 0.065))
		u.box(Vector3(bx, roof_y - 0.02, mount_z), Vector3(0.22, 0.03, 0.22))
		# Rear anti-sway tie beams bolted into the forward steel bulkhead.
		var brace_len := maxf(mount_z - fz, 0.15)
		u.box(Vector3(bx, top_y + 0.02, fz + brace_len * 0.5), Vector3(0.05, 0.05, brace_len))
		u.box(Vector3(bx, bot_y - 0.025, fz + brace_len * 0.5), Vector3(0.045, 0.045, brace_len))
	# Armoured steel cable umbilical behind the TV up into a bulkhead junction box.
	var cable_z := fz + 0.08
	Shapes.cylinder(u, Vector3(cx + 0.22, mid_y, cable_z), 0.022, maxf(roof_y - mid_y, 0.4), 8)
	u.box(Vector3(cx + 0.22, mid_y, cable_z), Vector3(0.14, 0.16, 0.08))

	# Locked marine steel VCR shelf cage suspended beneath the CRT chin (clear of all seat sight lines).
	var vcr_y := bot_y - 0.165
	var vcr_z := sz - 0.2
	var shelf_w := 0.56
	var shelf_d := 0.36
	u.box(Vector3(cx, vcr_y - 0.012, vcr_z), Vector3(shelf_w, 0.022, shelf_d))
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (shelf_w * 0.5 - 0.012)
		u.box(Vector3(px, (vcr_y + bot_y - 0.025) * 0.5, vcr_z + shelf_d * 0.35),
				Vector3(0.022, bot_y - 0.025 - vcr_y, 0.022))
		u.box(Vector3(px, (vcr_y + bot_y - 0.025) * 0.5, vcr_z - shelf_d * 0.35),
				Vector3(0.022, bot_y - 0.025 - vcr_y, 0.022))
	# Front retaining security bar across the VCR cage.
	u.box(Vector3(cx, vcr_y + 0.115, vcr_z + shelf_d * 0.44), Vector3(shelf_w, 0.018, 0.018))
	# 1994 video cassette deck inside the cage with flashing cyan-green 12:00 seven-segment clock (`PieceDisplay`).
	var vcr_xf := Transform3D(Basis(), Vector3(cx, vcr_y, vcr_z))
	s.colour = Color(0.07, 0.075, 0.085).srgb_to_linear()
	var vcr_mat: Material = c.tinted("iron")
	var win: Array = Furniture.video_recorder(s, vcr_xf, Vector3(0.44, 0.095, 0.3),
			{"body": vcr_mat, "detail": vcr_mat})
	var gd: Array = c.glows.get("display", [])
	gd.append_array(Furniture.seven_segments("12:00", win[0], win[1], win[2], win[3], win[4]))
	c.glows["display"] = gd

	# Single clean physics collision box enclosing the overhead CRT & VCR rig (strictly inside cabin, > 3 m from seat).
	var rig_lo := Vector3(cx - outer_w * 0.5, vcr_y - 0.02, fz + 0.02)
	var rig_hi := Vector3(cx + outer_w * 0.5, top_y + 0.05, sz + 0.02)
	c.shapes.append(PhysicsShapes.box((rig_lo + rig_hi) * 0.5, rig_hi - rig_lo, Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Utilitarian marine ceiling dividers, recessed overhead fluorescent diffuser panels (house lamps), and live
## night-crossing cove strips along the upper window soffits.
static func _ceiling_and_lights(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var wall_h := float(q["wall_height"])
	var rise := float(q["rise"])
	var length := bz - fz
	var mid_z := (fz + bz) * 0.5

	var s: RoomMesh = c.s
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove
	# Longitudinal marine acoustic ceiling rail dividers flanking the central fluorescent light trough.
	s.surface(c.tinted("plastic"))
	s.colour = CEILING_TILE.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var rx := cx + side * 0.85
		var ry := _roof_y(q, rx) - 0.03
		s.box(Vector3(rx, ry, mid_z), Vector3(0.06, 0.05, length - 0.1))
		# Recessed upper window pelmet soffit fascia along each side wall (hides the night-crossing cove strip).
		var px := cx + side * (hw - 0.1)
		s.box(Vector3(px, wall_h - 0.09, mid_z), Vector3(0.2, 0.14, length - 0.12))

	# Four overhead recessed fluorescent light diffuser panels running down the lounge centreline.
	lit.surface(c.shade(FLUOR_LIGHT))
	var crown_y := wall_h + rise - 0.025
	var n_panels := 4
	for i in n_panels:
		var pz := lerpf(fz + 1.15, bz - 0.85, float(i) / maxf(n_panels - 1, 1))
		# Panel housing rim and crisp transverse marine diffuser louvre ribs (reads cleanly both lit and switched off).
		s.box(Vector3(cx, crown_y + 0.01, pz), Vector3(0.46, 0.03, 1.08))
		for k in 5:
			var lz := pz - 0.4 + 0.2 * k
			s.box(Vector3(cx, crown_y - 0.011, lz), Vector3(0.4, 0.014, 0.018))
		# Glowing white acrylic diffuser face pointing down into the lounge.
		lit.face([Vector3(cx - 0.2, crown_y - 0.008, pz - 0.5), Vector3(cx + 0.2, crown_y - 0.008, pz - 0.5),
				Vector3(cx + 0.2, crown_y - 0.008, pz + 0.5), Vector3(cx - 0.2, crown_y - 0.008, pz + 0.5)],
				Vector3.DOWN)
		if i == 1 or i == 2:
			c.lamps.append([Vector3(cx, crown_y - 0.18, pz), FLUOR_LIGHT, 0.85])

	# Night-crossing cove strips tucked beneath the side pelmet soffits (live colour via Night strips setting).
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.95, 0.96, 0.98).srgb_to_linear()
	cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.95)
	for side: float in [-1.0, 1.0]:
		var x_in := cx + side * (hw - 0.18)
		var x_out := cx + side * (hw - 0.04)
		var y_strip := wall_h - 0.165
		var a := Vector3(x_in, y_strip, fz + 0.35)
		var b := Vector3(x_out, y_strip, fz + 0.35)
		var d := Vector3(x_out, y_strip, bz - 0.35)
		var e := Vector3(x_in, y_strip, bz - 0.35)
		if side < 0.0:
			cove.face([a, b, d, e], Vector3.DOWN)
		else:
			cove.face([b, a, e, d], Vector3.DOWN)
	cove.colour = Color.WHITE


## Bolted brushed-steel storm grab-rails running beneath the rounded marine windows on both sides, plus subtle
## under-sill cabin heater convector grilles.
static func _window_bays(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var sill := float(q["window_sill"])
	var ww := float(q["window_width"])
	var wzs: Array = q["window_zs"]
	if wzs.is_empty():
		return
	var z0 := float(wzs[0]) - ww * 0.55
	var z1 := float(wzs[-1]) + ww * 0.55
	var rail_len := z1 - z0
	var rail_mid := (z0 + z1) * 0.5
	var rail_y := sill - 0.09

	var u: RoomMesh = c.u
	u.surface(c.shiny("chrome", 0.9, 0.72, 0.16))
	u.colour = STEEL_BRUSH.srgb_to_linear()
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
	for side: float in [-1.0, 1.0]:
		var wall_x := cx + side * hw
		var rx := wall_x - side * 0.065
		# Continuous brushed-steel storm handrail along the window bays.
		Shapes.cylinder(u, Vector3(rx, rail_y, z0), 0.018, rail_len, 8, basis_z)
		# Bolted wall standoff brackets between and at the ends of the windows.
		for k in wzs.size() + 1:
			var bz := z0 + rail_len * float(k) / float(wzs.size())
			u.box(Vector3(wall_x - side * 0.032, rail_y, bz), Vector3(0.065, 0.022, 0.022))
			u.box(Vector3(wall_x - side * 0.008, rail_y, bz), Vector3(0.014, 0.06, 0.06))
	# Under-dado marine bulkhead convector heater boxes tucked flush to each wall.
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.56, 0.6, 0.64).srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var hx := cx + side * (hw - 0.045)
		u.box(Vector3(hx, 0.24, rail_mid), Vector3(0.08, 0.34, rail_len * 0.82))
	u.colour = Color.WHITE


## Two bolted 1994 laminate window-bay corner tables with raised anti-roll fiddle lips, takeaway paper coffee cups
## with plastic lids, and folded teal-and-white ferry crossing timetables.
static func _side_tables(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var table_h := 0.62
	var tw := 0.44
	var td := 0.76
	for side: float in [-1.0, 1.0]:
		var tx := cx + side * (hw - tw * 0.5 - 0.06)
		var tz := 0.02
		# Bolted marine steel pedestal leg + floor flange.
		s.surface(c.tinted("iron"))
		s.colour = STEEL_DARK.srgb_to_linear()
		s.box(Vector3(tx, 0.015, tz), Vector3(0.26, 0.03, 0.36))
		s.box(Vector3(tx, table_h * 0.5, tz), Vector3(0.08, table_h - 0.04, 0.1))
		# Laminate tabletop with raised white anti-roll storm lip around its perimeter.
		s.surface(c.tinted("plastic"))
		s.colour = LAMINATE.srgb_to_linear()
		s.box(Vector3(tx, table_h - 0.018, tz), Vector3(tw, 0.036, td))
		s.box(Vector3(tx - side * (tw * 0.5 - 0.01), table_h + 0.008, tz), Vector3(0.018, 0.024, td))
		for dz: float in [-1.0, 1.0]:
			s.box(Vector3(tx, table_h + 0.008, tz + dz * (td * 0.5 - 0.01)), Vector3(tw, 0.024, 0.018))
		# Takeaway paper coffee cup + white moulded plastic sip lid.
		u.surface(c.soft("plastic", true))
		var cup_at := Vector3(tx - side * 0.06, table_h, tz - 0.14 * side)
		u.colour = Color(0.88, 0.85, 0.78).srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.028, 0.0), Vector2(0.038, 0.105)], cup_at, 10)
		u.colour = TEAL_TIMETABLE.srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.033, 0.04), Vector2(0.036, 0.072)], cup_at, 10)
		u.colour = Color(0.95, 0.96, 0.97).srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.042, 0.104), Vector2(0.042, 0.116), Vector2(0.032, 0.122), Vector2(0.0, 0.122)],
				cup_at, 10)
		# Folded 1994 ferry crossing timetable brochure resting beside the cup.
		var brochure_at := Vector3(tx + side * 0.04, table_h + 0.004, tz + 0.14 * side)
		var yaw := 0.24 * side
		u.colour = TEAL_TIMETABLE.srgb_to_linear()
		u.box(brochure_at, Vector3(0.11, 0.007, 0.21), Basis(Vector3.UP, yaw))
		u.colour = Color(0.92, 0.93, 0.91).srgb_to_linear()
		u.box(brochure_at + Vector3(0.0, 0.004, 0.0), Vector3(0.085, 0.002, 0.07), Basis(Vector3.UP, yaw))
		c.shapes.append(PhysicsShapes.box(Vector3(tx, table_h * 0.5, tz), Vector3(tw, table_h, td), Basis()))
	u.colour = Color.WHITE


## Aft steel bulkhead: glass-fronted red marine fire-hose reel cabinet, backlit green EXIT pictogram box above the
## companionway door, stainless door push-bar & kick-plate, lifebuoy safety placard, and working ship's bulkhead clock.
static func _aft_bulkhead(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis_aft := Basis(Vector3.UP, PI)

	# Stainless steel kick-plate and horizontal crash push-bar on the rear companionway door (door is 0.62 x 1.85 m).
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = STEEL_BRUSH.srgb_to_linear()
	u.box(Vector3(cx, 0.16, bz - 0.026), Vector3(0.58, 0.3, 0.01))
	u.box(Vector3(cx, 0.96, bz - 0.055), Vector3(0.52, 0.045, 0.025))
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.23, 0.96, bz - 0.036), Vector3(0.035, 0.06, 0.035))

	# Backlit emergency green EXIT sign housing above the companionway door (geometric doorway & arrow symbol, no text).
	s.surface(c.tinted("iron"))
	s.colour = STEEL_DARK.srgb_to_linear()
	var ex_y := 2.04
	s.box(Vector3(cx, ex_y, bz - 0.055), Vector3(0.52, 0.22, 0.11))
	var gw: Array = c.glows.get("window", [])
	gw.append([Vector3(cx, ex_y, bz - 0.114), Vector3(-0.23, 0.0, 0.0), Vector3(0.0, 0.085, 0.0), Vector3.FORWARD])
	c.glows["window"] = gw
	# Crisp white geometric doorway rectangle + arrow bars standing 2 mm proud of the green backlit panel.
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.95, 0.98, 0.96).srgb_to_linear()
	u.box(Vector3(cx + 0.12, ex_y, bz - 0.118), Vector3(0.08, 0.12, 0.006))
	u.box(Vector3(cx - 0.08, ex_y, bz - 0.118), Vector3(0.14, 0.024, 0.006))
	u.box(Vector3(cx - 0.14, ex_y + 0.024, bz - 0.118), Vector3(0.06, 0.018, 0.006), Basis(Vector3.BACK, 0.65))
	u.box(Vector3(cx - 0.14, ex_y - 0.024, bz - 0.118), Vector3(0.06, 0.018, 0.006), Basis(Vector3.BACK, -0.65))

	# Working brushed-steel maritime bulkhead clock centered above the EXIT sign (PieceClock, live wall time).
	var clk_y := 2.46
	var clk_r := 0.21
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = STEEL_BRUSH.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, clk_y, bz - 0.045), clk_r, clk_r + 0.035, 0.055, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	c.clocks.append([Vector3(cx, clk_y, bz - 0.062), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# Glass-fronted signal-red marine fire-hose reel cabinet on the port aft bulkhead.
	var fx := cx - hw * 0.6
	var fy := 1.42
	var fz_box := bz - 0.1
	s.surface(c.tinted("iron"))
	s.colour = FIRE_RED.srgb_to_linear()
	# Back, top, bottom and sides of the recessed cabinet; front glazed so the coiled hose reel shows inside.
	s.box(Vector3(fx, fy, bz - 0.02), Vector3(0.58, 0.68, 0.04))
	s.box(Vector3(fx, fy + 0.32, fz_box), Vector3(0.58, 0.04, 0.18))
	s.box(Vector3(fx, fy - 0.32, fz_box), Vector3(0.58, 0.04, 0.18))
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(fx + side * 0.27, fy, fz_box), Vector3(0.04, 0.6, 0.18))
	# Coiled red/cream fire hose drum & brass nozzle inside the cabinet (shares shiny chrome tinted brass).
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.84, 0.78, 0.66).srgb_to_linear()
	Shapes.cylinder(u, Vector3(fx, fy, bz - 0.05), 0.2, 0.07, 14, Basis(Vector3.RIGHT, -PI * 0.5))
	u.colour = FIRE_RED.srgb_to_linear()
	Shapes.cylinder(u, Vector3(fx, fy, bz - 0.045), 0.11, 0.085, 12, Basis(Vector3.RIGHT, -PI * 0.5))
	u.surface(c.shiny("chrome", 0.9, 0.75, 0.14))
	u.colour = Color(0.92, 0.72, 0.3).srgb_to_linear()
	Shapes.cylinder(u, Vector3(fx + 0.16, fy - 0.2, bz - 0.11), 0.022, 0.16, 8)
	# Cabinet front glass pane.
	c.glass.surface(c.mat("tin"))
	c.glass.box(Vector3(fx, fy, bz - 0.185), Vector3(0.5, 0.6, 0.01))
	c.shapes.append(PhysicsShapes.box(Vector3(fx, fy, fz_box), Vector3(0.58, 0.68, 0.18), Basis()))

	# Starboard aft bulkhead: framed marine lifebuoy safety placard (pure geometric ring + chevrons, no text).
	var sx := cx + hw * 0.6
	s.surface(c.tinted("plastic"))
	s.colour = Color(0.9, 0.92, 0.93).srgb_to_linear()
	s.box(Vector3(sx, 1.56, bz - 0.015), Vector3(0.54, 0.4, 0.025))
	s.colour = Color.WHITE
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.09, 0.32, 0.48).srgb_to_linear()
	u.box(Vector3(sx, 1.69, bz - 0.03), Vector3(0.48, 0.09, 0.008))
	u.colour = LIFE_ORANGE.srgb_to_linear()
	Shapes.arch(u, Vector3(sx - 0.11, 1.5, bz - 0.032), 0.05, 0.095, 0.012, 14, basis_aft, 0.0, TAU, ["front"])
	u.colour = Color(0.18, 0.22, 0.26).srgb_to_linear()
	for bar in 3:
		u.box(Vector3(sx + 0.09, 1.55 - 0.045 * bar, bz - 0.03), Vector3(0.18, 0.018, 0.006))
	u.colour = Color.WHITE


## Wet exterior promenade deck rails, bolted bright international-orange marine lifebuoy rings outside the middle
## storm windows, and exterior deck bulkhead lamps (unbaked, no interior collision boxes).
static func _exterior_deck(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var wt := float(q["wall_thickness"])
	var ledge := float(q["ledge"])
	if ledge < 0.3:
		return
	var ly := float(q["ledge_y"])
	var fz := float(q["front_z"]) - 1.2
	var bz := float(q["back_z"]) + 1.2
	var span := bz - fz
	var mid_z := (fz + bz) * 0.5
	var rail_h := 1.08

	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var bays := maxi(roundi(span / 1.4), 4)
	for side: float in [-1.0, 1.0]:
		var rx := cx + side * (hw + wt + ledge - 0.08)
		# Painted white marine steel bulwark stanchions, kick-board and four horizontal guard rails.
		u.surface(c.soft("plastic", true))
		u.colour = RAIL_WHITE.srgb_to_linear()
		u.box(Vector3(rx, ly + 0.09, mid_z), Vector3(0.05, 0.18, span))
		for frac: float in [0.34, 0.56, 0.78, 1.0]:
			var h_bar := 0.055 if frac > 0.95 else 0.03
			u.box(Vector3(rx, ly + rail_h * frac, mid_z), Vector3(0.06 if frac > 0.95 else 0.032, h_bar, span))
		for k in bays + 1:
			var sz := fz + span * float(k) / bays
			u.box(Vector3(rx, ly + rail_h * 0.5, sz), Vector3(0.045, rail_h, 0.045))
		# Bolted international-orange marine lifebuoy ring hung visibly on the promenade rail outside mid-lounge!
		var ring_at := Vector3(rx - side * 0.06, ly + 0.72, -0.75)
		var ring_basis := Basis(Vector3.UP, PI * 0.5 * (-side))
		u.colour = LIFE_ORANGE.srgb_to_linear()
		Shapes.arch(u, ring_at, 0.2, 0.34, 0.085, 16, ring_basis, 0.0, TAU, ["front", "back", "inner", "outer"])
		# Four reflective white SOLAS tape bands around the lifebuoy ring.
		u.colour = Color(0.95, 0.96, 0.97).srgb_to_linear()
		for k in 4:
			var a := PI * 0.25 + PI * 0.5 * k
			u.box(ring_at + ring_basis * Vector3(cos(a) * 0.27, sin(a) * 0.27, 0.0), Vector3(0.095, 0.05, 0.15),
					ring_basis * Basis(Vector3.BACK, a))
		# Subtle exterior watertight vapour-proof bulkhead deck lamps mounted outside between windows.
		lit.surface(c.shade(FLUOR_LIGHT))
		var wall_out := cx + side * (hw + wt + 0.03)
		for dz: float in [-1.55, 1.55]:
			u.surface(c.soft("plastic", true))
			u.colour = STEEL_DARK.srgb_to_linear()
			u.box(Vector3(wall_out, 2.24, dz), Vector3(0.07, 0.14, 0.22))
			lit.box(Vector3(wall_out + side * 0.03, 2.22, dz), Vector3(0.03, 0.08, 0.16))
	u.colour = Color.WHITE


# --- The Pullman recliner rows' hardware ------------------------------------------------------------------------------

## Moulded 1994 ferry armrests (with recline buttons and ashtrays), white linen antimacassars on every headrest but
## the viewer's own, flip-up seatback tray tables, and low night-crossing aisle strips (PieceCove).
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
	var arm_h := 0.58
	var arm_d := 0.60
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

	# Draw the chunky dark-grey moulded armrests with padded caps, recline buttons and flip-lid ashtrays.
	u.surface(c.soft("plastic", true))
	for at: Vector3 in arm_places.values():
		u.colour = ARM_BODY.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h * 0.5, arm_z), Vector3(arm_w, arm_h, arm_d), Basis(), [RoomMesh.DOWN])
		u.colour = ARM_CAP.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h + 0.018, arm_z - 0.01), Vector3(arm_w + 0.012, 0.036, arm_d + 0.02))
	u.surface(c.shiny("chrome", 0.9, 0.72, 0.16))
	u.colour = STEEL_BRUSH.srgb_to_linear()
	for at: Vector3 in arm_places.values():
		# Classic 1994 recessed metal armrest ashtray lid at front top + small round recline button beside it.
		u.box(at + Vector3(0.0, arm_h + 0.038, arm_z - arm_d * 0.34), Vector3(0.068, 0.008, 0.082))
		u.box(at + Vector3(0.0, arm_h + 0.038, arm_z - arm_d * 0.12), Vector3(0.026, 0.01, 0.026))

	# Draw crisp woven white linen antimacassars hugging the curved recliner headrests (`seats.gd _recliner` curve -0.35),
	# plus flush curved flip-up laminate seatback tray tables on every seat except the viewer's own.
	var wi := pitch - arm_w - 0.01
	u.surface(c.soft("cloth", true))
	u.colour = LINEN_WHITE.srgb_to_linear()
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		# Woven linen antimacassar matching the recliner headrest's exact curve and 6 cm rounded crown, tucked neatly
		# behind the pillow seam with teal bolsters showing on both sides.
		u.rounded_box(Vector3(0.0, 0.655, -0.008), Vector3(wi - 0.14, 0.24, 0.148), 0.06, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])
	u.surface(c.soft("plastic", true))
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		# Folded-up pale-grey laminate seatback tray table curving flush with the rear moulded shell (`bend -0.35`).
		u.colour = TRAY_GREY.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.34, 0.126), Vector3(wi - 0.09, 0.28, 0.018), 0.008, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.FRONT])
		u.colour = ARM_CAP.srgb_to_linear()
		u.box(t_world * Vector3(0.0, 0.498, 0.128), Vector3(0.048, 0.024, 0.016), t_world.basis)
		u.box(t_world * Vector3(0.0, 0.19, 0.124), Vector3(wi - 0.1, 0.02, 0.018), t_world.basis)

	# Low night-crossing aisle step strips along the aisle-facing base of the aisle armrests (PieceCove).
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.95, 0.96, 0.98).srgb_to_linear()
	cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.96)
	for entry: Array in aisle_arms:
		var at: Vector3 = entry[0]
		var inward: float = float(entry[1])
		var x := at.x + inward * (arm_w * 0.5 + 0.005)
		var z0 := at.z + arm_z - arm_d * 0.42
		var z1 := at.z + arm_z + arm_d * 0.42
		var n := Vector3(inward, 0.0, 0.0)
		var p0 := Vector3(x, 0.045, z0)
		var p1 := Vector3(x, 0.045, z1)
		var p2 := Vector3(x, 0.095, z1)
		var p3 := Vector3(x, 0.095, z0)
		if inward > 0.0:
			cove.face([p0, p1, p2, p3], n)
		else:
			cove.face([p1, p0, p3, p2], n)
	cove.colour = Color.WHITE
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
