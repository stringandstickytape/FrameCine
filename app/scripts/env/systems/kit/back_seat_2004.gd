extends RefCounted

## Back seat, 2004 (app/environments/back_seat_2004.env.json; docs/environments/rooms/back_seat_2004.md):
## the twelfth of the Journeys (Road). Built by Gemini 4 Neon Extra High. The cozy, rain-streaked back seat of a 2004
## family estate cruising down a late-night wet motorway. Everything is drawn from boxes, strips, grids and lathed
## shapes; strictly empty front seats, no real car or electronics mark.
##
##   car_2004_cabin   the 2004 family estate's interior architecture and glowing cockpit:
##                    - roof-mounted brushed-silver clamshell flip-down portable LCD housing suspended cleanly over the
##                      centre corridor with twin barrel hinges, sculpted ceiling console pod, recessed side disc slot,
##                      tactile lower transport buttons, speaker pinhole strips, glowing standby LED (`PieceWindows`),
##                      and twin angled courtesy map lights plus rear dome lamp (`PieceLamps`, house group)
##                    - two empty sculpted slate-grey velour front bucket seats flanking the centre gap (`x = +/-0.52`),
##                      with contoured bolsters, twin chrome headrest stalks, tall headrests, dark plastic rear shells,
##                      and seatback map pockets holding a paperback book and a folded motorway road atlas
##                    - curved dark soft-touch 2004 dashboard with open-fronted hooded driver instrument binnacle,
##                      twin chrome-ringed backlit speedometer and rev-counter dials (`PieceCove`, live Dash glow
##                      setting, `cove_floor` 0.88) with glowing amber-orange needles (`PieceWindows`), 3-spoke leather
##                      steering wheel & stalks, brushed-silver centre-console stack with open-fronted hooded upper LCD
##                      clock (`PieceDisplay` `"23:14"`), twin air vents, backlit CD/radio head unit, glowing amber
##                      hazard triangle, three illuminated circular HVAC climate knobs, transmission tunnel with
##                      leather-booted gearstick, handbrake, twin cupholders with an insulated travel mug, raked glossy
##                      dark night windscreen with silhouetted wipers, hanging interior rear-view mirror & sun visors
##                    - moulded two-tone door cards, armrests with glowing amber electric-window switches
##                      (`PieceWindows`), brushed-silver door pull handles, lower door pockets with stowed water
##                      bottles, slim headliner-matched upper pillar trims with retractable seatbelt straps, and
##                      recessed ceiling grab handles
##   car_2004_props   the cozy rear bench seat and late-night motorway travel comforts:
##                    - plush contoured rear bench cushion and reclined backrest with three headrests (no physics box
##                      within 0.45 m of the seat at the origin)
##                    - softly draped undulating wool tartan blanket (`tartan_blanket` procedural texture) tucked cleanly
##                      over the left rear seat and cascading gently over the bench front, with a folded lap corner and
##                      warm fringed edge, nestled beside a plump reclined oatmeal travel cushion
##                    - right rear seat cushion with a soft reclined navy corner pillow, zipped black-and-silver
##                      portable disc carry-case, and classic 2004 silver-and-black over-ear wired headphones
##                    - rear carpeted parcel shelf behind the rear bench holding a folded forest-green rain umbrella
##                      with curved wood handle and a folded spare tartan wool throw under dark rear tailgate glass with
##                      fine heated defroster lines

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Furniture := preload("res://scripts/env/systems/kit/furniture.gd")

const PIECES: Array[String] = ["car_2004_cabin", "car_2004_props"]

## Palette (sRGB): 2004 automotive charcoal soft-touch plastic, brushed metallic silver trim, slate-grey velour seats,
## warm halogen dome light, rich tartan wool and nostalgic travel props.
const DASH_DARK := Color(0.095, 0.10, 0.115)
const DASH_MID := Color(0.155, 0.165, 0.185)
const TRIM_BLACK := Color(0.055, 0.06, 0.07)
const HEADLINER_GREY := Color(0.62, 0.63, 0.64)
const PILLAR_LIGHT := Color(0.56, 0.57, 0.58)
const SILVER_TRIM := Color(0.76, 0.79, 0.82)
const CHROME_BRIGHT := Color(0.86, 0.89, 0.92)
const VELOUR_BASE := Color(0.24, 0.26, 0.30)
const VELOUR_BOLSTER := Color(0.175, 0.195, 0.235)
const VELOUR_INSERT := Color(0.30, 0.325, 0.375)
const WINDSCREEN_DARK := Color(0.022, 0.028, 0.044)
const DOME_WARM := Color(1.0, 0.86, 0.62)
const CUSHION_OATMEAL := Color(0.76, 0.70, 0.60)
const CUSHION_NAVY := Color(0.15, 0.22, 0.35)
const BOOK_TERRACOTTA := Color(0.66, 0.24, 0.16)
const BOOK_PAGES := Color(0.88, 0.84, 0.74)
const ATLAS_BLUE := Color(0.16, 0.34, 0.56)
const MUG_BURGUNDY := Color(0.46, 0.12, 0.16)
const UMBRELLA_GREEN := Color(0.12, 0.28, 0.18)
const WOOD_HANDLE := Color(0.42, 0.24, 0.12)
const FRINGE_GOLD := Color(0.76, 0.64, 0.36)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"car_2004_cabin":
			_cabin(c)
		"car_2004_props":
			_props(c)


# --- Piece 1: 2004 family estate interior, roof flip-down LCD, front bucket seats & glowing dashboard ----------------

static func _cabin(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_flipdown_screen_and_roof(c, q)
	_front_bucket_seats(c, q)
	_dashboard_and_console(c, q)
	_doors_and_pillars(c, q)
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE
	c.cove.colour = Color.WHITE


## Roof-mounted brushed-silver clamshell flip-down 2004 portable LCD housing, sleek sculpted ceiling console pod with
## twin barrel hinges, angled overhead courtesy map lights, rear dome lamp, and recessed ceiling grab handles.
static func _flipdown_screen_and_roof(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 1.2675, -0.98)))
	var sc_sz: Vector2 = scr.get("size", Vector2(0.72, 0.405))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var sz := sc_xf.origin.z
	var w := sc_sz.x
	var h := sc_sz.y
	var hw := w * 0.5
	var hh := h * 0.5

	var bezel_side := 0.030
	var bezel_top := 0.026
	var chin_h := 0.044
	var outer_w := w + bezel_side * 2.0
	var top_y := cy + hh + bezel_top
	var bot_y := cy - hh - chin_h
	var total_h := top_y - bot_y
	var mid_y := (top_y + bot_y) * 0.5
	var roof_y := _roof_y(q, cx)

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var chrome: Material = _silver_mat(c)
	var basis_x := Basis(Vector3.BACK, -PI * 0.5)

	# Solid matte-charcoal inner screen backing & crisp dark frame behind the picture plane (never blocks sight_line,
	# and forms a solid flow_clear shield behind the flip-down screen!).
	s.surface(c.tinted("iron"))
	s.colour = TRIM_BLACK.srgb_to_linear()
	s.box(Vector3(cx, mid_y, sz - 0.022), Vector3(outer_w - 0.010, total_h - 0.010, 0.020))

	# Sleek brushed-silver 2004 flip-down clamshell outer bezel framing the screen cleanly (recessed behind sz).
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	var bz := sz - 0.014
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * (hw + bezel_side * 0.5), mid_y, bz), Vector3(bezel_side, total_h, 0.022))
	u.box(Vector3(cx, cy + hh + bezel_top * 0.5, bz), Vector3(w, bezel_top, 0.022))
	u.box(Vector3(cx, cy - hh - chin_h * 0.5, bz), Vector3(w, chin_h, 0.022))
	# Rounded clamshell rear shell cap behind the LCD lid.
	u.rounded_box(Vector3(cx, mid_y, sz - 0.034), Vector3(outer_w, total_h, 0.024), 0.009, Transform3D(), 1)

	# Row of 5 tactile brushed-chrome transport buttons across the lower chin + recessed dark speaker pin-grilles.
	u.surface(c.soft("plastic", true))
	u.colour = TRIM_BLACK.srgb_to_linear()
	u.box(Vector3(cx, bot_y + chin_h * 0.5, sz - 0.003), Vector3(0.22, 0.020, 0.004))
	for side: float in [-1.0, 1.0]:
		for row in 2:
			u.box(Vector3(cx + side * (hw - 0.095), bot_y + 0.016 + 0.011 * row, sz - 0.002),
					Vector3(0.105, 0.0045, 0.004))
	u.surface(chrome)
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	for k in 5:
		var bx := cx - 0.084 + 0.042 * k
		u.box(Vector3(bx, bot_y + chin_h * 0.5, sz - 0.001), Vector3(0.024, 0.012, 0.007))

	# Tiny warm glowing standby power LED on the lower-right silver chin bezel (`PieceWindows`).
	var gw: Array = c.glows.get("window", [])
	gw.append([Vector3(cx + hw - 0.015, bot_y + chin_h * 0.5, sz + 0.001), Vector3(0.0055, 0.0, 0.0),
			Vector3(0.0, 0.0055, 0.0), Vector3.BACK])
	c.glows["window"] = gw

	# Sleek contoured ceiling console pod hugging the arched headliner above the flip-down screen.
	var pod_z := sz - 0.055
	var pod_y := (top_y + roof_y) * 0.5 + 0.018
	var pod_h := maxf(roof_y - top_y, 0.075)
	u.surface(c.soft("plastic", true))
	u.colour = HEADLINER_GREY.srgb_to_linear()
	u.rounded_box(Vector3(cx, pod_y, pod_z), Vector3(0.54, pod_h + 0.02, 0.30), 0.022, Transform3D(), 1)
	u.colour = DASH_MID.srgb_to_linear()
	u.rounded_box(Vector3(cx, top_y + 0.022, pod_z + 0.02), Vector3(0.46, 0.030, 0.22), 0.010, Transform3D(), 1)
	# Brushed-silver trim accent bar & twin barrel hinges linking the flip-down screen cleanly to the ceiling pod.
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	u.box(Vector3(cx, top_y + 0.048, pod_z + 0.148), Vector3(0.32, 0.012, 0.008))
	for side: float in [-1.0, 1.0]:
		var hx := cx + side * 0.165
		Shapes.cylinder(u, Vector3(hx - 0.042, top_y + 0.006, sz - 0.015), 0.014, 0.084, 10, basis_x)
		u.box(Vector3(hx, top_y + 0.022, sz - 0.017), Vector3(0.052, 0.030, 0.024))
	# Recessed side-loading disc slot on the console pod's left flank.
	s.surface(c.tinted("iron"))
	s.colour = TRIM_BLACK.srgb_to_linear()
	s.box(Vector3(cx - 0.272, top_y + 0.045, pod_z), Vector3(0.008, 0.008, 0.14))

	# Overhead courtesy map lights on the ceiling pod's aft edge (angled visibly toward the back seat!) + rear dome lamp.
	lit.surface(c.shade(DOME_WARM))
	var map_tilt := Basis(Vector3.RIGHT, deg_to_rad(-28.0))
	for side: float in [-1.0, 1.0]:
		var lx := cx + side * 0.165
		var lz := pod_z + 0.135
		var ly := top_y + 0.068
		u.surface(c.soft("plastic", true))
		u.colour = DASH_MID.srgb_to_linear()
		u.box(Vector3(lx, ly, lz - 0.006), Vector3(0.095, 0.036, 0.024), map_tilt)
		lit.box(Vector3(lx, ly - 0.002, lz + 0.004), Vector3(0.074, 0.022, 0.014), map_tilt)
	# Rear courtesy dome lamp above the back seat (`z = +0.28`).
	var rear_dome_z := 0.28
	var rear_dome_y := roof_y - 0.018
	s.surface(c.tinted("plastic"))
	s.colour = HEADLINER_GREY.srgb_to_linear()
	s.box(Vector3(cx, rear_dome_y + 0.008, rear_dome_z), Vector3(0.20, 0.022, 0.13), Basis(), [RoomMesh.UP])
	lit.box(Vector3(cx, rear_dome_y - 0.006, rear_dome_z), Vector3(0.14, 0.014, 0.085), Basis(), [RoomMesh.UP])

	# Two gentle warm interior halogen bake lights (forward over console & aft over rear bench).
	c.lamps.append([Vector3(cx, roof_y - 0.18, -0.78), DOME_WARM, 0.65])
	c.lamps.append([Vector3(cx, roof_y - 0.18, 0.26), DOME_WARM, 0.60])

	# Sleek moulded pale-grey ceiling grab handles tucked high above the windows.
	u.surface(c.soft("plastic", true))
	u.colour = HEADLINER_GREY.srgb_to_linear()
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
	for entry: Array in [[-1.0, 0.10], [1.0, 0.10], [-1.0, -1.10]]:
		var side: float = entry[0]
		var gz: float = entry[1]
		var gx := _wall_x(q, side, 1.40) - side * 0.020
		var gy := 1.405
		Shapes.cylinder(u, Vector3(gx - side * 0.018, gy - 0.022, gz - 0.080), 0.009, 0.16, 8, basis_z)
		for dz: float in [-0.080, 0.080]:
			u.box(Vector3(gx, gy - 0.006, gz + dz), Vector3(0.028, 0.018, 0.020))
			u.box(Vector3(gx - side * 0.012, gy - 0.015, gz + dz), Vector3(0.014, 0.018, 0.015))

	# Clean physics box enclosing the roof flip-down LCD & ceiling console pod (strictly inside cabin, > 0.85 m ahead).
	var pod_lo := Vector3(cx - outer_w * 0.5, bot_y, sz - 0.16)
	var pod_hi := Vector3(cx + outer_w * 0.5, minf(roof_y - 0.01, pod_y + pod_h * 0.5), sz + 0.01)
	c.shapes.append(PhysicsShapes.box((pod_lo + pod_hi) * 0.5, pod_hi - pod_lo, Basis()))


## Two empty sculpted 2004 slate-grey velour front bucket seats flanking the centre gap (`x = +/-0.52`), with side
## bolsters, dark plastic rear shells, chrome headrest stalks, tall headrests, and seatback map pockets holding a
## paperback book and folded motorway road atlas.
static func _front_bucket_seats(c: Object, _q: Dictionary) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var chrome: Material = _silver_mat(c)
	var cloth: Material = c.soft("fabric", true)
	var plastic: Material = c.soft("plastic", true)
	var back_tilt := Basis(Vector3.RIGHT, deg_to_rad(13.0))

	for side: float in [-1.0, 1.0]:
		var sx := side * 0.52
		# Under-seat dark-metal runner rails & pedestal frame.
		s.surface(c.tinted("iron"))
		s.colour = TRIM_BLACK.srgb_to_linear()
		for rx: float in [-0.15, 0.15]:
			s.box(Vector3(sx + rx, 0.022, -1.30), Vector3(0.036, 0.044, 0.44), Basis(), [RoomMesh.DOWN])
			s.box(Vector3(sx + rx, 0.13, -1.28), Vector3(0.038, 0.18, 0.26))
		s.box(Vector3(sx, 0.21, -1.30), Vector3(0.40, 0.04, 0.42))

		# Sculpted velour lower seat cushion + raised side thigh bolsters.
		u.surface(cloth)
		u.colour = VELOUR_BASE.srgb_to_linear()
		u.rounded_box(Vector3(sx, 0.30, -1.33), Vector3(0.44, 0.15, 0.46), 0.048,
				Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3.ZERO), 1)
		u.colour = VELOUR_BOLSTER.srgb_to_linear()
		for bside: float in [-1.0, 1.0]:
			u.rounded_box(Vector3(sx + bside * 0.19, 0.34, -1.33), Vector3(0.09, 0.13, 0.44), 0.035,
					Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3.ZERO), 1)

		# Reclined sculpted bucket backrest (`y = 0.36..1.08`).
		var back_xf := Transform3D(back_tilt, Vector3(sx, 0.72, -1.13))
		u.colour = VELOUR_BASE.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(0.45, 0.72, 0.14), 0.048, back_xf, 1)
		u.colour = VELOUR_INSERT.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.01, -0.022), Vector3(0.26, 0.60, 0.115), 0.032, back_xf, 1)
		u.colour = VELOUR_BOLSTER.srgb_to_linear()
		for bside: float in [-1.0, 1.0]:
			u.rounded_box(Vector3(bside * 0.195, -0.02, -0.015), Vector3(0.095, 0.66, 0.145), 0.038, back_xf, 1)

		# Dark charcoal moulded plastic rear seatback trim shell + seatback map pocket!
		u.surface(plastic)
		u.colour = DASH_MID.srgb_to_linear()
		u.rounded_box(Vector3(0.0, -0.02, 0.056), Vector3(0.39, 0.60, 0.036), 0.014, back_xf, 1)
		u.colour = VELOUR_BOLSTER.srgb_to_linear()
		u.rounded_box(Vector3(0.0, -0.15, 0.082), Vector3(0.33, 0.24, 0.028), 0.010, back_xf, 1)
		u.colour = TRIM_BLACK.srgb_to_linear()
		u.box(back_xf * Vector3(0.0, -0.032, 0.086), Vector3(0.335, 0.016, 0.026), back_xf.basis)

		# Twin chrome headrest stalks + sculpted headrest collars + tall contoured 2004 headrest (`y = 1.08..1.35`).
		var hr_x := side * 0.50
		var hr_z := -1.045
		u.surface(plastic)
		u.colour = TRIM_BLACK.srgb_to_linear()
		for stalk: float in [-0.065, 0.065]:
			u.box(Vector3(hr_x + stalk, 1.078, hr_z), Vector3(0.030, 0.016, 0.030))
		u.surface(chrome)
		u.colour = CHROME_BRIGHT.srgb_to_linear()
		for stalk: float in [-0.065, 0.065]:
			Shapes.cylinder(u, Vector3(hr_x + stalk, 1.07, hr_z), 0.0085, 0.075, 8)
		u.surface(cloth)
		u.colour = VELOUR_BASE.srgb_to_linear()
		var hr_xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), Vector3(hr_x, 1.215, hr_z))
		u.rounded_box(Vector3.ZERO, Vector3(0.27, 0.255, 0.12), 0.054, hr_xf, 1)
		u.colour = VELOUR_BOLSTER.srgb_to_linear()
		u.rounded_box(Vector3(0.0, -0.02, 0.022), Vector3(0.23, 0.19, 0.088), 0.035, hr_xf, 1)

		# Nostalgic items tucked into the front seatback map pockets!
		u.surface(plastic)
		if side < 0.0:
			var book_xf := back_xf * Transform3D(Basis(Vector3.BACK, deg_to_rad(8.0)), Vector3(-0.04, -0.01, 0.082))
			u.colour = BOOK_TERRACOTTA.srgb_to_linear()
			u.box(book_xf.origin, Vector3(0.135, 0.185, 0.022), book_xf.basis)
			u.colour = BOOK_PAGES.srgb_to_linear()
			u.box(book_xf * Vector3(0.005, 0.004, 0.0), Vector3(0.125, 0.178, 0.016), book_xf.basis)
			u.colour = Color(0.92, 0.85, 0.66).srgb_to_linear()
			u.box(book_xf * Vector3(0.0, 0.048, 0.012), Vector3(0.095, 0.026, 0.003), book_xf.basis)
		else:
			var atlas_xf := back_xf * Transform3D(Basis(Vector3.BACK, deg_to_rad(-6.0)), Vector3(0.03, 0.00, 0.082))
			u.colour = ATLAS_BLUE.srgb_to_linear()
			u.box(atlas_xf.origin, Vector3(0.185, 0.21, 0.014), atlas_xf.basis)
			u.colour = Color(0.92, 0.72, 0.22).srgb_to_linear()
			u.box(atlas_xf * Vector3(0.0, 0.055, 0.008), Vector3(0.165, 0.032, 0.003), atlas_xf.basis)
			u.colour = Color(0.88, 0.90, 0.92).srgb_to_linear()
			u.box(atlas_xf * Vector3(-0.03, -0.01, 0.008), Vector3(0.09, 0.05, 0.003), atlas_xf.basis)

		# Clean physics box for each front bucket seat (strictly inside cabin, > 0.98 m from origin).
		c.shapes.append(PhysicsShapes.box(Vector3(sx, 0.68, -1.24), Vector3(0.46, 1.32, 0.52), Basis()))


## Curved dark soft-touch 2004 dashboard, open-fronted glowing driver instrument binnacle (speedometer & rev-counter
## rings in `PieceCove`, amber needles in `PieceWindows`), 3-spoke leather steering wheel, brushed-silver centre
## console stack with open-fronted hooded LCD digital clock (`PieceDisplay` `"23:14"`), CD/radio stereo, illuminated
## HVAC knobs, centre tunnel with leather-booted gearstick, handbrake & travel mug, dark raked night windscreen,
## hanging rear-view mirror & folded sun visors.
static func _dashboard_and_console(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var chrome: Material = _silver_mat(c)
	var plastic: Material = c.soft("plastic", true)
	var gw: Array = c.glows.get("window", [])
	var cove_white := Color(0.92, 0.96, 1.0).srgb_to_linear()

	# --- Curved dark soft-touch 2004 dashboard main body (`z = -2.14..-1.66`, `y = 0.44..0.82`) ---
	var dash_w := (hw - 0.84 * tan(float(q["L"]))) * 2.0 + 0.06
	s.surface(c.tinted("plastic"))
	s.colour = DASH_DARK.srgb_to_linear()
	# Upper dash pad deck stopping cleanly at z = -1.66 and y = 0.82 so the instrument & clock pods sit proudly above!
	s.box(Vector3(cx, 0.77, -1.90), Vector3(dash_w, 0.10, 0.48), Basis(), [RoomMesh.FRONT])
	s.box(Vector3(cx, 0.58, -1.94), Vector3(dash_w, 0.30, 0.36), Basis(), [RoomMesh.FRONT])
	# Passenger glovebox recess & brushed-silver glovebox latch on left (`x = -0.45`).
	s.colour = DASH_MID.srgb_to_linear()
	s.box(Vector3(cx - 0.44, 0.58, -1.755), Vector3(0.46, 0.22, 0.025))
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	u.box(Vector3(cx - 0.34, 0.65, -1.738), Vector3(0.085, 0.018, 0.014))
	# Left & right outer circular dash air vents.
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var vx := cx + side * 0.64
		Shapes.cylinder(u, Vector3(vx, 0.74, -1.68), 0.042, 0.028, 12, Basis(Vector3.RIGHT, PI * 0.5))

	# --- Open-fronted Driver Instrument Binnacle & Backlit 2004 Gauges (`x = +0.39, y = 0.87, z = -1.64`, RHD) ---
	# Sits cleanly ABOVE the dash deck (`y = 0.82`) and IN FRONT of the backing plate (`z = -1.66`) so both glowing
	# circular dials and amber needles read vividly from the back seat right past the inner shoulder of the right seat!
	var binn_x := cx + 0.38
	var dial_y := 0.872
	var dial_z := -1.645
	u.surface(plastic)
	u.colour = DASH_DARK.srgb_to_linear()
	# Open-fronted hood canopy: arched top visor + left & right cheeks (open to +Z toward the driver & viewer!).
	u.rounded_box(Vector3(binn_x, dial_y + 0.068, -1.68), Vector3(0.36, 0.028, 0.16), 0.012, Transform3D(), 1)
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(binn_x + side * 0.165, dial_y + 0.008, -1.68), Vector3(0.028, 0.125, 0.15))
	# Matte-black recessed instrument backing face strictly behind the glowing dials (`z = -1.668`).
	s.surface(c.tinted("iron"))
	s.colour = TRIM_BLACK.srgb_to_linear()
	s.box(Vector3(binn_x, dial_y, -1.672), Vector3(0.31, 0.125, 0.016))

	# Twin circular backlit gauges (left: rev counter at x = +0.322; right: speedometer at x = +0.438).
	cove.surface(c.kit.cove_material())
	for d_info: Array in [[binn_x - 0.058, 0.048, 0.52], [binn_x + 0.058, 0.050, -0.32]]:
		var dx: float = d_info[0]
		var dr: float = d_info[1]
		var needle_ang: float = d_info[2]
		# Brushed-chrome gauge bezel ring framing each dial.
		u.surface(chrome)
		u.colour = CHROME_BRIGHT.srgb_to_linear()
		Shapes.arch(u, Vector3(dx, dial_y, dial_z + 0.004), dr, dr + 0.006, 0.012, 20, Basis(), 0.0, TAU,
				["front", "inner", "outer"])
		# Deep saturated backlit dial face + crisp bright outer tick arc in `PieceCove` (live Dash glow setting!).
		cove.colour = Color(cove_white.r, cove_white.g, cove_white.b, 0.36)
		Shapes.arch(cove, Vector3(dx, dial_y, dial_z - 0.002), 0.006, dr - 0.008, 0.003, 18, Basis(), 0.0, TAU,
				["front"])
		cove.colour = Color(cove_white.r, cove_white.g, cove_white.b, 0.72)
		Shapes.arch(cove, Vector3(dx, dial_y, dial_z), dr - 0.011, dr - 0.001, 0.003, 18, Basis(),
				deg_to_rad(-40.0), deg_to_rad(220.0), ["front"])
		# Glowing amber-orange cruising gauge needle (`PieceWindows`) + hub dot!
		var ndir := Vector3(sin(needle_ang), cos(needle_ang), 0.0)
		var nperp := Vector3(cos(needle_ang), -sin(needle_ang), 0.0)
		var nlen := dr * 0.80
		var nctr := Vector3(dx, dial_y, dial_z + 0.005) + ndir * (nlen * 0.40)
		gw.append([nctr, ndir * (nlen * 0.5), nperp * 0.0038, Vector3.BACK])
		gw.append([Vector3(dx, dial_y, dial_z + 0.006), Vector3(0.006, 0.0, 0.0), Vector3(0.0, 0.006, 0.0),
				Vector3.BACK])
	# Glowing centre trip-odometer LCD bar between the two gauges (`PieceCove`).
	cove.colour = Color(cove_white.r, cove_white.g, cove_white.b, 0.68)
	cove.face([Vector3(binn_x - 0.022, dial_y - 0.036, dial_z + 0.001),
			Vector3(binn_x + 0.022, dial_y - 0.036, dial_z + 0.001),
			Vector3(binn_x + 0.022, dial_y - 0.018, dial_z + 0.001),
			Vector3(binn_x - 0.022, dial_y - 0.018, dial_z + 0.001)], Vector3.BACK)

	# --- 3-spoke 2004 leather steering wheel & steering column (`x = +0.41, y = 0.77, z = -1.53`) ---
	var sw_at := Vector3(binn_x + 0.03, 0.765, -1.525)
	var sw_basis := Basis(Vector3.RIGHT, deg_to_rad(-22.0))
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	Shapes.beam(u, Vector3(sw_at.x, 0.71, -1.72), sw_at - sw_basis * Vector3(0.0, 0.0, 0.04), Vector2(0.09, 0.08))
	for s_side: float in [-1.0, 1.0]:
		Shapes.beam(u, sw_at + sw_basis * Vector3(s_side * 0.04, 0.01, -0.05),
				sw_at + sw_basis * Vector3(s_side * 0.14, 0.03, -0.04), Vector2(0.012, 0.012))
	Shapes.arch(u, sw_at, 0.142, 0.172, 0.030, 24, sw_basis, 0.0, TAU, ["front", "back", "inner", "outer"])
	u.rounded_box(Vector3.ZERO, Vector3(0.122, 0.102, 0.044), 0.024, Transform3D(sw_basis, sw_at), 1)
	for s_side: float in [-1.0, 1.0]:
		u.box(sw_at + sw_basis * Vector3(s_side * 0.105, -0.01, -0.004), Vector3(0.10, 0.028, 0.022), sw_basis)
	u.box(sw_at + sw_basis * Vector3(0.0, -0.10, -0.004), Vector3(0.036, 0.10, 0.022), sw_basis)
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	u.box(sw_at + sw_basis * Vector3(0.0, -0.092, 0.010), Vector3(0.022, 0.068, 0.008), sw_basis)
	Shapes.arch(u, sw_at + sw_basis * Vector3(0.0, 0.004, 0.024), 0.016, 0.022, 0.006, 14, sw_basis, 0.0, TAU, ["front"])

	# --- Glowing 2004 Centre Console Stack (`x = 0.0, y = 0.44..0.92, z = -1.615`) ---
	var cs_z := -1.615
	s.surface(c.tinted("plastic"))
	s.colour = DASH_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.65, cs_z - 0.07), Vector3(0.36, 0.44, 0.14))

	# Open-fronted hooded upper centre-dash digital clock & trip-computer pod (`y = 0.845..0.925`)!
	# Canopy visor & cheeks frame a recessed LCD window open cleanly toward +Z so `"23:14"` glows crystal clear!
	u.surface(plastic)
	u.colour = DASH_DARK.srgb_to_linear()
	u.rounded_box(Vector3(cx, 0.916, cs_z - 0.04), Vector3(0.28, 0.024, 0.15), 0.010, Transform3D(), 1)
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.126, 0.876, cs_z - 0.04), Vector3(0.026, 0.080, 0.14))
	s.surface(c.tinted("iron"))
	s.colour = TRIM_BLACK.srgb_to_linear()
	s.box(Vector3(cx, 0.876, cs_z - 0.016), Vector3(0.23, 0.072, 0.014))
	# Soft backlit LCD bed (`PieceCove`) + crisp 7-segment `"23:14"` (`PieceDisplay`) standing cleanly proud at cs_z!
	cove.colour = Color(cove_white.r, cove_white.g, cove_white.b, 0.28)
	cove.face([Vector3(cx - 0.098, 0.854, cs_z - 0.005), Vector3(cx + 0.098, 0.854, cs_z - 0.005),
			Vector3(cx + 0.098, 0.898, cs_z - 0.005), Vector3(cx - 0.098, 0.898, cs_z - 0.005)], Vector3.BACK)
	var gd: Array = c.glows.get("display", [])
	gd.append_array(Furniture.seven_segments("23:14", Vector3(cx, 0.876, cs_z + 0.001),
			Vector3.RIGHT, Vector3.UP, Vector3.BACK, 0.030))
	c.glows["display"] = gd

	# Brushed-silver metallic centre fascia plate framing vents, CD stereo & climate dials.
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	u.box(Vector3(cx, 0.648, cs_z + 0.006), Vector3(0.30, 0.38, 0.018))

	# Twin central rectangular air vents (`y = 0.785`) with horizontal louvres.
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var vx := cx + side * 0.072
		u.box(Vector3(vx, 0.785, cs_z + 0.016), Vector3(0.115, 0.054, 0.012))
		u.colour = DASH_MID.srgb_to_linear()
		for slat in 3:
			u.box(Vector3(vx, 0.770 + 0.015 * slat, cs_z + 0.023), Vector3(0.105, 0.005, 0.006))
		u.colour = TRIM_BLACK.srgb_to_linear()

	# 2004 Single-DIN CD/Radio Stereo Head Unit (`y = 0.692`) with backlit LCD bar, CD slot, silver knob & preset keys.
	u.box(Vector3(cx, 0.694, cs_z + 0.018), Vector3(0.245, 0.082, 0.016))
	u.colour = Color(0.02, 0.02, 0.025).srgb_to_linear()
	u.box(Vector3(cx + 0.01, 0.722, cs_z + 0.027), Vector3(0.155, 0.006, 0.004))
	u.surface(chrome)
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	Shapes.cylinder(u, Vector3(cx - 0.092, 0.692, cs_z + 0.022), 0.018, 0.016, 12, Basis(Vector3.RIGHT, PI * 0.5))
	Shapes.cylinder(u, Vector3(cx + 0.096, 0.692, cs_z + 0.022), 0.013, 0.014, 10, Basis(Vector3.RIGHT, PI * 0.5))
	# Saturated glowing stereo LCD tuner bar + 6 illuminated preset buttons in `PieceCove`!
	cove.colour = Color(cove_white.r, cove_white.g, cove_white.b, 0.70)
	cove.face([Vector3(cx - 0.056, 0.686, cs_z + 0.028), Vector3(cx + 0.068, 0.686, cs_z + 0.028),
			Vector3(cx + 0.068, 0.710, cs_z + 0.028), Vector3(cx - 0.056, 0.710, cs_z + 0.028)], Vector3.BACK)
	for k in 6:
		var px := cx - 0.054 + 0.022 * k
		cove.face([Vector3(px - 0.007, 0.664, cs_z + 0.028), Vector3(px + 0.007, 0.664, cs_z + 0.028),
				Vector3(px + 0.007, 0.674, cs_z + 0.028), Vector3(px - 0.007, 0.674, cs_z + 0.028)], Vector3.BACK)
	# Warm amber power indicator beside volume knob + central glowing amber hazard button (`PieceWindows`)!
	gw.append([Vector3(cx - 0.092, 0.664, cs_z + 0.028), Vector3(0.007, 0.0, 0.0), Vector3(0.0, 0.005, 0.0), Vector3.BACK])
	gw.append([Vector3(cx, 0.631, cs_z + 0.024), Vector3(0.015, 0.0, 0.0), Vector3(0.0, 0.010, 0.0), Vector3.BACK])

	# Three circular HVAC climate control dials (`y = 0.558`, `x = -0.078, 0.0, +0.078`) with rich glowing rings!
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	for kx: float in [-0.078, 0.0, 0.078]:
		Shapes.cylinder(u, Vector3(cx + kx, 0.558, cs_z + 0.018), 0.021, 0.022, 12, Basis(Vector3.RIGHT, PI * 0.5))
		cove.colour = Color(cove_white.r, cove_white.g, cove_white.b, 0.74)
		Shapes.arch(cove, Vector3(cx + kx, 0.558, cs_z + 0.020), 0.024, 0.032, 0.004, 16, Basis(), 0.0, TAU, ["front"])
	for ax: float in [-0.042, 0.042]:
		gw.append([Vector3(cx + ax, 0.504, cs_z + 0.022), Vector3(0.010, 0.0, 0.0), Vector3(0.0, 0.0055, 0.0),
				Vector3.BACK])

	# --- Centre Transmission Tunnel, Leather-Booted Gearstick, Handbrake & Twin Cupholders (`z = -1.60..-0.68`) ---
	s.surface(c.tinted("plastic"))
	s.colour = DASH_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.21, -1.16), Vector3(0.24, 0.42, 0.90), Basis(), [RoomMesh.DOWN])
	s.box(Vector3(cx, 0.38, -1.54), Vector3(0.26, 0.24, 0.20), Basis(Vector3.RIGHT, deg_to_rad(-24.0)))
	s.surface(c.tinted("iron"))
	s.colour = TRIM_BLACK.srgb_to_linear()
	s.box(Vector3(cx, 0.26, -0.706), Vector3(0.16, 0.12, 0.016))
	cove.colour = Color(cove_white.r, cove_white.g, cove_white.b, 0.68)
	Shapes.arch(cove, Vector3(cx + 0.055, 0.365, -0.705), 0.012, 0.017, 0.004, 14, Basis(), 0.0, TAU, ["front"])

	# Brushed-silver shift gate surround + pleated leather gearstick gaiter + chrome shaft + ergonomic shift knob.
	var gs_z := -1.33
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	u.box(Vector3(cx, 0.425, gs_z), Vector3(0.155, 0.012, 0.165))
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.058, 0.0), Vector2(0.048, 0.035), Vector2(0.052, 0.055), Vector2(0.036, 0.095),
			Vector2(0.020, 0.135)], Vector3(cx, 0.43, gs_z), 10)
	u.surface(chrome)
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	Shapes.cylinder(u, Vector3(cx, 0.555, gs_z), 0.009, 0.05, 8)
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	u.rounded_box(Vector3(cx, 0.615, gs_z), Vector3(0.048, 0.056, 0.052), 0.022, Transform3D(), 1)
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	Shapes.cylinder(u, Vector3(cx, 0.640, gs_z), 0.016, 0.006, 10)

	# Handbrake lever & chrome thumb release button (`x = -0.06, z = -1.04`).
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	var hb_basis := Basis(Vector3.RIGHT, deg_to_rad(14.0))
	u.rounded_box(Vector3(cx - 0.058, 0.465, -1.03), Vector3(0.034, 0.036, 0.24), 0.012,
			Transform3D(hb_basis, Vector3.ZERO), 1)
	u.surface(chrome)
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx - 0.058, 0.495, -1.15), Vector3(0.018, 0.018, 0.016), hb_basis)

	# Twin recessed cupholders (`x = +0.04, z = -1.08 & -0.94`) with a warm burgundy travel mug in the front holder!
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	for cz: float in [-1.08, -0.94]:
		Shapes.arch(u, Vector3(cx + 0.045, 0.426, cz), 0.038, 0.045, 0.014, 14, Basis(Vector3.RIGHT, PI * 0.5),
				0.0, TAU, ["front", "inner", "outer"])
	var mug_at := Vector3(cx + 0.045, 0.415, -1.08)
	u.colour = MUG_BURGUNDY.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.031, 0.0), Vector2(0.038, 0.118)], mug_at, 12)
	u.colour = TRIM_BLACK.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.040, 0.118), Vector2(0.041, 0.136), Vector2(0.032, 0.142), Vector2(0.0, 0.142)],
			mug_at, 12)
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.0385, 0.102), Vector2(0.0392, 0.118)], mug_at, 12)

	# --- Raked Dark Rain-Night Windscreen, Wiper Silhouettes, Hanging Rear-View Mirror & Folded Sun Visors ---
	var ws_y0 := 0.82
	var ws_y1 := float(q["wall_height"])
	var ws_z0 := fz + 0.06
	var ws_z1 := fz + 0.34
	var ws_hw0 := hw - ws_y0 * tan(float(q["L"]))
	var ws_hw1 := hw - ws_y1 * tan(float(q["L"]))
	var ws_n := Vector3(0.0, -(ws_z1 - ws_z0), ws_y1 - ws_y0).normalized()
	u.surface(c.shiny("iron", 0.08, 0.55, 0.06))
	u.colour = WINDSCREEN_DARK.srgb_to_linear()
	u.face([Vector3(cx - ws_hw0, ws_y0, ws_z0), Vector3(cx + ws_hw0, ws_y0, ws_z0),
			Vector3(cx + ws_hw1, ws_y1, ws_z1), Vector3(cx - ws_hw1, ws_y1, ws_z1)], ws_n)
	s.surface(c.tinted("plastic"))
	s.colour = HEADLINER_GREY.srgb_to_linear()
	s.box(Vector3(cx, ws_y1 + 0.02, ws_z1 - 0.02), Vector3(ws_hw1 * 2.0 + 0.02, 0.07, 0.09))
	for side: float in [-1.0, 1.0]:
		Shapes.beam(s, Vector3(cx + side * (ws_hw0 - 0.02), ws_y0, ws_z0 + 0.02),
				Vector3(cx + side * (ws_hw1 - 0.02), ws_y1, ws_z1 + 0.01), Vector2(0.070, 0.070))
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	for wx: float in [-0.32, 0.24]:
		u.box(Vector3(cx + wx, ws_y0 + 0.055, ws_z0 + 0.03), Vector3(0.42, 0.014, 0.016),
				Basis(Vector3.BACK, deg_to_rad(5.0)))
	var mir_at := Vector3(cx, 1.335, ws_z1 + 0.055)
	Shapes.beam(u, Vector3(cx, ws_y1 - 0.01, ws_z1 + 0.01), mir_at + Vector3(0.0, 0.02, -0.02), Vector2(0.014, 0.014))
	u.rounded_box(mir_at, Vector3(0.22, 0.058, 0.026), 0.012, Transform3D(), 1)
	u.surface(chrome)
	u.colour = CHROME_BRIGHT.srgb_to_linear()
	u.box(mir_at + Vector3(0.0, 0.0, 0.014), Vector3(0.20, 0.046, 0.004))
	u.surface(plastic)
	u.colour = HEADLINER_GREY.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		u.rounded_box(Vector3(cx + side * 0.33, ws_y1 + 0.005, ws_z1 + 0.09), Vector3(0.36, 0.022, 0.14), 0.008,
				Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), Vector3.ZERO), 1)

	c.glows["window"] = gw

	# Clean physics boxes enclosing the dashboard and centre transmission tunnel (strictly inside cabin, >= 0.68 m).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, 0.50, -1.86), Vector3(1.66, 0.92, 0.54), Basis()))
	c.shapes.append(PhysicsShapes.box(Vector3(cx, 0.23, -1.14), Vector3(0.24, 0.44, 0.90), Basis()))


## Moulded two-tone door trim panels, ergonomic door armrests with glowing amber electric-window switches
## (`PieceWindows`), brushed-silver interior door levers, lower map pockets, recessed speaker grilles, and sleek
## headliner-matched upper B-/C-pillar covers with retractable front seatbelt straps.
static func _doors_and_pillars(c: Object, q: Dictionary) -> void:
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var sill := float(q["window_sill"])
	var wall_h := float(q["wall_height"])
	var lean := float(q["L"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var chrome: Material = _silver_mat(c)
	var plastic: Material = c.soft("plastic", true)
	var cloth: Material = c.soft("fabric", true)
	var gw: Array = c.glows.get("window", [])

	for side: float in [-1.0, 1.0]:
		var inward := -side
		# Continuous sculpted upper door waist bolster rail right below the window sills.
		s.surface(c.tinted("plastic"))
		s.colour = DASH_DARK.srgb_to_linear()
		var rail_x := _wall_x(q, side, sill - 0.040) + inward * 0.022
		s.box(Vector3(rail_x, sill - 0.040, (fz + bz) * 0.5 + 0.10), Vector3(0.044, 0.075, bz - fz - 0.25))

		# Front & rear door upholstered elbow inserts, moulded armrests, silver levers, glowing amber window switches!
		for door_z: float in [-1.10, 0.08]:
			var is_rear := door_z > -0.4
			u.surface(cloth)
			u.colour = VELOUR_BASE.srgb_to_linear()
			var ins_x := _wall_x(q, side, 0.63) + inward * 0.014
			u.box(Vector3(ins_x, 0.63, door_z), Vector3(0.020, 0.20, 0.72), Basis(Vector3.BACK, side * lean))

			u.surface(plastic)
			u.colour = DASH_MID.srgb_to_linear()
			var arm_x := _wall_x(q, side, 0.54) + inward * 0.038
			u.rounded_box(Vector3(arm_x, 0.54, door_z + 0.02), Vector3(0.072, 0.066, 0.52), 0.018, Transform3D(), 1)
			u.colour = TRIM_BLACK.srgb_to_linear()
			u.box(Vector3(arm_x + inward * 0.004, 0.575, door_z - 0.14), Vector3(0.036, 0.012, 0.068))
			gw.append([Vector3(arm_x + inward * 0.005, 0.583, door_z - 0.14),
					Vector3(0.0, 0.0, 0.010), Vector3(0.007, 0.0, 0.0), Vector3.UP])

			var lev_x := _wall_x(q, side, 0.66) + inward * 0.020
			u.colour = TRIM_BLACK.srgb_to_linear()
			u.box(Vector3(lev_x, 0.66, door_z - 0.26), Vector3(0.018, 0.054, 0.112))
			u.surface(chrome)
			u.colour = SILVER_TRIM.srgb_to_linear()
			u.box(Vector3(lev_x + inward * 0.010, 0.66, door_z - 0.255), Vector3(0.012, 0.018, 0.074))

			u.surface(plastic)
			u.colour = DASH_DARK.srgb_to_linear()
			var pkt_x := _wall_x(q, side, 0.22) + inward * 0.036
			u.box(Vector3(pkt_x, 0.22, door_z + 0.05), Vector3(0.066, 0.16, 0.56))
			u.colour = TRIM_BLACK.srgb_to_linear()
			var spk_x := _wall_x(q, side, 0.24) + inward * 0.022
			Shapes.cylinder(u, Vector3(spk_x, 0.24, door_z - 0.26), 0.066, 0.016, 12,
					Basis(Vector3.BACK, -side * PI * 0.5))
			if is_rear:
				u.colour = Color(0.24, 0.44, 0.62).srgb_to_linear()
				var bot_at := Vector3(pkt_x - inward * 0.005, 0.19, door_z - 0.12)
				Shapes.lathe(u, [Vector2(0.028, 0.0), Vector2(0.029, 0.13), Vector2(0.015, 0.165), Vector2(0.015, 0.18)],
						bot_at, 10)
				u.colour = Color(0.88, 0.90, 0.94).srgb_to_linear()
				Shapes.cylinder(u, bot_at + Vector3(0.0, 0.178, 0.0), 0.016, 0.018, 10)

		# Sleek flush headliner-matched upper B-pillar (`z = -0.50`) & C-pillar (`z = +0.64`) trim covers (zero box
		# protrusion!), with charcoal lower B-pillar & refined slim seatbelt D-ring anchor + black webbing strap.
		u.surface(plastic)
		var up_h := (wall_h - sill - 0.02) / cos(lean)
		var pil_y := sill + (wall_h - sill - 0.02) * 0.5
		for pz: float in [-0.50, 0.64]:
			var pil_x := _wall_x(q, side, pil_y) + inward * 0.009
			u.colour = PILLAR_LIGHT.srgb_to_linear()
			u.rounded_box(Vector3.ZERO, Vector3(0.018, up_h, 0.125), 0.007,
					Transform3D(Basis(Vector3.BACK, side * lean), Vector3(pil_x, pil_y, pz)), 1)
		# Lower dark charcoal B-pillar trim below window sill (`y = 0.06..0.78`).
		var lo_y := 0.42
		u.colour = DASH_DARK.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(0.020, 0.72 / cos(lean), 0.135), 0.007,
				Transform3D(Basis(Vector3.BACK, side * lean), Vector3(_wall_x(q, side, lo_y) + inward * 0.010, lo_y,
				-0.50)), 1)
		# Vertical black front seatbelt webbing strap & slim recessed dark-plastic / chrome D-ring height slider!
		u.colour = TRIM_BLACK.srgb_to_linear()
		Shapes.beam(u, Vector3(_wall_x(q, side, 0.34) + inward * 0.022, 0.34, -0.50),
				Vector3(_wall_x(q, side, 1.24) + inward * 0.023, 1.24, -0.50), Vector2(0.006, 0.042))
		u.rounded_box(Vector3.ZERO, Vector3(0.016, 0.042, 0.056), 0.006,
				Transform3D(Basis(Vector3.BACK, side * lean), Vector3(_wall_x(q, side, 1.25) + inward * 0.020, 1.25,
				-0.50)), 1)
		u.surface(chrome)
		u.colour = SILVER_TRIM.srgb_to_linear()
		u.box(Vector3(_wall_x(q, side, 1.23) + inward * 0.028, 1.23, -0.50), Vector3(0.010, 0.012, 0.044),
				Basis(Vector3.BACK, side * lean))

	c.glows["window"] = gw


# --- Piece 2: Cozy rear bench seat, draped tartan wool blanket, cushions, disc case, headphones & parcel shelf -------

static func _props(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_rear_bench_and_blanket(c, q)
	_rear_parcel_shelf(c, q)
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


## Plush contoured rear bench seat (no physics box within 0.45 m of origin), softly draped undulating tartan wool
## blanket (`tartan_blanket` procedural texture!), plump reclined oatmeal & navy travel cushions, zipped 2004 disc
## carry-case, and classic 2004 silver-and-black over-ear wired headphones.
static func _rear_bench_and_blanket(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var u: RoomMesh = c.u
	var cloth: Material = c.soft("fabric", true)
	var plastic: Material = c.soft("plastic", true)
	var chrome: Material = _silver_mat(c)
	var bench_w := hw * 2.0 - 0.14

	# --- Contoured plush rear bench seat (`z = -0.24..+0.44`) ---
	u.surface(cloth)
	u.colour = VELOUR_BOLSTER.srgb_to_linear()
	u.box(Vector3(cx, 0.15, 0.06), Vector3(bench_w, 0.30, 0.56), Basis(), [RoomMesh.DOWN])
	u.colour = VELOUR_BASE.srgb_to_linear()
	u.rounded_box(Vector3(cx, 0.365, 0.02), Vector3(bench_w + 0.02, 0.165, 0.58), 0.055,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-4.0)), Vector3.ZERO), 1, Vector3i(2, 0, 1), 0.0,
			[RoomMesh.DOWN])
	var back_xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(14.0)), Vector3(cx, 0.72, 0.36))
	u.rounded_box(Vector3.ZERO, Vector3(bench_w - 0.06, 0.62, 0.15), 0.052, back_xf, 1, Vector3i(2, 0, 0))
	u.colour = VELOUR_INSERT.srgb_to_linear()
	for sx: float in [-0.50, 0.0, 0.50]:
		var pw := 0.34 if absf(sx) < 0.1 else 0.42
		u.rounded_box(Vector3(sx, 0.0, -0.025), Vector3(pw, 0.50, 0.12), 0.032, back_xf, 1)
	u.colour = VELOUR_BASE.srgb_to_linear()
	for h_info: Array in [[-0.50, 1.12, 0.24, 0.19], [0.0, 1.07, 0.21, 0.13], [0.50, 1.12, 0.24, 0.19]]:
		var hx: float = h_info[0]
		var hy: float = h_info[1]
		var hwid: float = h_info[2]
		var hhgt: float = h_info[3]
		u.rounded_box(Vector3(cx + hx, hy, 0.44), Vector3(hwid, hhgt, 0.11), 0.042,
				Transform3D(Basis(Vector3.RIGHT, deg_to_rad(10.0)), Vector3.ZERO), 1)
	# Recessed seat-belt buckle sockets tucked cleanly between the seat cushions.
	u.surface(plastic)
	u.colour = TRIM_BLACK.srgb_to_linear()
	for bx: float in [-0.26, 0.26]:
		u.box(Vector3(cx + bx, 0.46, 0.24), Vector3(0.042, 0.048, 0.028))
		u.colour = Color(0.76, 0.12, 0.12).srgb_to_linear()
		u.box(Vector3(cx + bx, 0.486, 0.24), Vector3(0.026, 0.010, 0.020))
		u.colour = TRIM_BLACK.srgb_to_linear()

	# --- Cozy Draped Woven Tartan Wool Blanket (`tartan_blanket` procedural texture!) ---
	var tartan_mat: Material = c.soft("cloth", false, "tartan_blanket")
	u.surface(tartan_mat)
	u.colour = Color.WHITE
	_draped_tartan_blanket(u, cx - 0.52)

	# Warm cream-gold wool fringe border tucked neatly along the lower cascading hem of the tartan blanket.
	u.surface(cloth)
	u.colour = FRINGE_GOLD.srgb_to_linear()
	for k in 14:
		var fx := cx - 0.77 + 0.038 * k
		var fz_w := -0.312 - 0.006 * sin(float(k) * 1.1)
		u.box(Vector3(fx, 0.205, fz_w), Vector3(0.013, 0.044, 0.008), Basis(Vector3.RIGHT, deg_to_rad(4.0)))

	# Plump oatmeal-cream corduroy/velour travel cushion leaning naturally BACK against the left rear backrest!
	u.colour = CUSHION_OATMEAL.srgb_to_linear()
	var pil_l_xf := Transform3D(Basis(Vector3.UP, deg_to_rad(22.0)) * Basis(Vector3.RIGHT, deg_to_rad(-28.0)),
			Vector3(cx - 0.55, 0.61, 0.19))
	u.rounded_box(Vector3.ZERO, Vector3(0.36, 0.28, 0.12), 0.054, pil_l_xf, 1)

	# Soft navy travel pillow leaning naturally BACK into the right rear corner beside the viewer (`x = +0.58`).
	u.colour = CUSHION_NAVY.srgb_to_linear()
	var pil_r_xf := Transform3D(Basis(Vector3.UP, deg_to_rad(-20.0)) * Basis(Vector3.RIGHT, deg_to_rad(-28.0)),
			Vector3(cx + 0.58, 0.60, 0.20))
	u.rounded_box(Vector3.ZERO, Vector3(0.34, 0.26, 0.115), 0.052, pil_r_xf, 1)

	# --- 2004 Portable Disc Carry-Case & Silver-and-Black Over-Ear Wired Headphones on the Right Bench Cushion ---
	var case_at := Vector3(cx + 0.42, 0.474, -0.04)
	var case_xf := Transform3D(Basis(Vector3.UP, deg_to_rad(-18.0)), case_at)
	u.surface(plastic)
	u.colour = Color(0.11, 0.12, 0.14).srgb_to_linear()
	u.rounded_box(Vector3.ZERO, Vector3(0.175, 0.042, 0.175), 0.015, case_xf, 1)
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	u.box(case_xf.origin, Vector3(0.180, 0.008, 0.180), case_xf.basis)
	u.box(case_xf * Vector3(0.0, 0.022, 0.0), Vector3(0.085, 0.004, 0.032), case_xf.basis)

	# Classic 2004 silver-and-black over-ear headphones resting cleanly on the right seat cushion (`y = 0.482`)!
	var hp_at := Vector3(cx + 0.58, 0.482, -0.14)
	var hp_yaw := Basis(Vector3.UP, deg_to_rad(30.0))
	var hp_arch_basis := hp_yaw * Basis(Vector3.RIGHT, PI * 0.5)
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	Shapes.arch(u, hp_at, 0.068, 0.082, 0.020, 14, hp_arch_basis, 0.0, PI, ["front", "back", "inner", "outer"])
	for s_cup: float in [-1.0, 1.0]:
		var cup_at := hp_at + hp_yaw * Vector3(s_cup * 0.070, 0.008, 0.016)
		u.surface(plastic)
		u.colour = TRIM_BLACK.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(0.044, 0.046, 0.068), 0.016, Transform3D(hp_yaw, cup_at), 1)
		u.surface(chrome)
		u.colour = SILVER_TRIM.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(0.014, 0.034, 0.052), 0.006,
				Transform3D(hp_yaw, cup_at + hp_yaw * Vector3(s_cup * 0.020, 0.0, 0.0)), 1)


## Undulating draped wool tartan blanket mesh (`tartan_blanket` procedural texture): flows cleanly above the left rear
## backrest, across the bench cushion with gentle organic folds and zero seat poke-through, and cascades warmly down
## over the front cushion nose, plus a casually folded lap layer tucked on top.
static func _draped_tartan_blanket(u: RoomMesh, mid_x: float) -> void:
	var path: Array[Vector2] = [
		Vector2(0.295, 0.72),
		Vector2(0.255, 0.57),
		Vector2(0.205, 0.486),
		Vector2(0.095, 0.474),
		Vector2(-0.025, 0.468),
		Vector2(-0.145, 0.465),
		Vector2(-0.255, 0.456),
		Vector2(-0.305, 0.408),
		Vector2(-0.312, 0.320),
		Vector2(-0.310, 0.228),
	]
	var cols := 11
	var half_w := 0.28
	var rows_p: Array = []
	var rows_n: Array = []
	for r in path.size():
		var pt := path[r]
		var prev := path[maxi(r - 1, 0)]
		var next := path[mini(r + 1, path.size() - 1)]
		var tang := (next - prev).normalized()
		var nyz := Vector2(tang.y, -tang.x).normalized()
		var rp := PackedVector3Array()
		var rn := PackedVector3Array()
		for j in cols:
			var t := float(j) / float(cols - 1)
			var lx := lerpf(-half_w, half_w, t)
			# Soft positive cloth ripples (always strictly above cushion surface!).
			var fold := 0.009 * (0.5 + 0.5 * sin(t * TAU * 2.2 + float(r) * 0.42)) \
					+ 0.004 * (0.5 + 0.5 * cos(t * TAU * 4.0 - float(r) * 0.28))
			var edge_tuck := -0.008 if (j == 0 or j == cols - 1) else 0.0
			var p := Vector3(mid_x + lx, pt.y, pt.x) + Vector3(0.0, nyz.y, nyz.x) * (fold + edge_tuck)
			var n := Vector3(0.0, nyz.y, nyz.x)
			if j == 0:
				n = (n + Vector3(-0.6, 0.0, 0.0)).normalized()
			elif j == cols - 1:
				n = (n + Vector3(0.6, 0.0, 0.0)).normalized()
			rp.append(p)
			rn.append(n)
		rows_p.append(rp)
		rows_n.append(rn)
	u.grid(rows_p, rows_n)
	# Softly folded second wool tartan layer angled casually across the rear-left cushion (clear of the pillow!).
	var fold_xf := Transform3D(Basis(Vector3.UP, deg_to_rad(12.0)), Vector3(mid_x + 0.04, 0.494, -0.05))
	u.rounded_box(Vector3.ZERO, Vector3(0.38, 0.048, 0.30), 0.022, fold_xf, 1)


## Rear carpeted parcel shelf (`z = +0.48..+0.94`, `y = 0.86`), folded forest-green rain umbrella with wooden handle,
## neatly folded spare tartan wool throw, and dark tinted rear tailgate glass with fine horizontal defroster lines
## and high-mount brake light pod.
static func _rear_parcel_shelf(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var wall_h := float(q["wall_height"])
	var lean := float(q["L"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var plastic: Material = c.soft("plastic", true)
	var chrome: Material = _silver_mat(c)
	var shelf_y := 0.86
	var shelf_w := (hw - shelf_y * tan(lean)) * 2.0 - 0.04

	s.surface(c.tinted("plastic"))
	s.colour = DASH_MID.srgb_to_linear()
	s.box(Vector3(cx, shelf_y - 0.02, bz - 0.23), Vector3(shelf_w, 0.04, 0.45), Basis(), [RoomMesh.BACK])
	s.colour = DASH_DARK.srgb_to_linear()
	s.box(Vector3(cx, shelf_y * 0.5, bz - 0.44), Vector3(shelf_w, shelf_y, 0.04), Basis(), [RoomMesh.DOWN])

	# Folded dark forest-green rain umbrella with curved wooden J-handle resting across the left parcel shelf!
	var umb_at := Vector3(cx - 0.32, shelf_y + 0.032, bz - 0.22)
	var umb_basis := Basis(Vector3.UP, deg_to_rad(10.0)) * Basis(Vector3.BACK, -PI * 0.5)
	u.surface(plastic)
	u.colour = UMBRELLA_GREEN.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.012, 0.0), Vector2(0.030, 0.06), Vector2(0.034, 0.38), Vector2(0.024, 0.46),
			Vector2(0.008, 0.50)], umb_at - Vector3(0.24, 0.0, 0.0), 10, umb_basis)
	u.colour = WOOD_HANDLE.srgb_to_linear()
	Shapes.cylinder(u, umb_at + Vector3(0.25, 0.0, -0.045), 0.011, 0.09, 8, umb_basis)
	Shapes.arch(u, umb_at + Vector3(0.34, 0.0, -0.022), 0.020, 0.036, 0.018, 10,
			Basis(Vector3.UP, deg_to_rad(10.0)) * Basis(Vector3.RIGHT, PI * 0.5), -PI * 0.5, PI * 0.5,
			["front", "back", "inner", "outer"])
	u.surface(chrome)
	u.colour = SILVER_TRIM.srgb_to_linear()
	Shapes.cylinder(u, umb_at - Vector3(0.28, 0.0, -0.05), 0.007, 0.045, 8, umb_basis)

	# Folded spare tartan wool throw tucked neatly on the right side of the rear parcel shelf!
	u.surface(c.soft("cloth", false, "tartan_blanket"))
	u.colour = Color.WHITE
	u.rounded_box(Vector3.ZERO, Vector3(0.42, 0.11, 0.28), 0.032,
			Transform3D(Basis(Vector3.UP, deg_to_rad(-8.0)), Vector3(cx + 0.34, shelf_y + 0.055, bz - 0.22)), 1)

	# Dark tinted rear tailgate window panel with fine heated-glass copper-amber defroster lines & third brake pod.
	var rw_y0 := shelf_y + 0.04
	var rw_y1 := wall_h - 0.04
	var rw_hw0 := hw - rw_y0 * tan(lean) - 0.06
	var rw_hw1 := hw - rw_y1 * tan(lean) - 0.06
	u.surface(c.shiny("iron", 0.08, 0.55, 0.06))
	u.colour = WINDSCREEN_DARK.srgb_to_linear()
	u.face([Vector3(cx - rw_hw0, rw_y0, bz - 0.02), Vector3(cx + rw_hw0, rw_y0, bz - 0.02),
			Vector3(cx + rw_hw1, rw_y1, bz - 0.08), Vector3(cx - rw_hw1, rw_y1, bz - 0.08)],
			Vector3(0.0, -0.10, -0.995).normalized())
	u.surface(plastic)
	u.colour = Color(0.32, 0.20, 0.12).srgb_to_linear()
	for k in 6:
		var ly := lerpf(rw_y0 + 0.06, rw_y1 - 0.08, float(k) / 5.0)
		var lz := lerpf(bz - 0.024, bz - 0.078, float(k) / 5.0)
		var lw := lerpf(rw_hw0, rw_hw1, float(k) / 5.0) * 1.84
		u.box(Vector3(cx, ly, lz), Vector3(lw, 0.004, 0.004))
	u.colour = TRIM_BLACK.srgb_to_linear()
	u.box(Vector3(cx, rw_y1 - 0.02, bz - 0.09), Vector3(0.24, 0.044, 0.055))

	# Clean physics box enclosing the rear parcel shelf & boot divider (z = 0.51..0.93, strictly >= 0.51 m from origin!).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, 0.45, bz - 0.23), Vector3(shelf_w, 0.86, 0.42), Basis()))


# --- Helpers ----------------------------------------------------------------------------------------------------------

static func _silver_mat(c: Object) -> Material:
	return c.shiny("chrome", 0.85, 0.70, 0.16)


## World X of the leaning side wall (`side = -1` left, `+1` right) at height `y`.
static func _wall_x(q: Dictionary, side: float, y: float) -> float:
	return float(q["cx"]) + side * (float(q["hw"]) - y * tan(float(q["L"])))


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
