extends RefCounted

## Night sleeper, 1929 (app/environments/night_sleeper_1929.env.json; docs/environments/rooms/night_sleeper_1929.md):
## an intimate Art Deco marquetry sleeping compartment crossing a moonlit winter alpine night into rosy dawn.
## Built by Gemini 4 Neon Extra High. Everything is drawn from boxes, strips and lathed shapes; an empty private
## compartment with no real railway or projector mark.
##
##   sleeper_1929_cabin   the compartment's 1929 Art Deco joinery and fittings:
##                        - right corridor wall: book-matched walnut/mahogany marquetry panels with inlaid brass
##                          diamond medallions and trim lines, recessed sliding wood-and-frosted-glass corridor door
##                          with brass track, latch handle and frosted transom pane (PieceWindows), overhead brass
##                          luggage rack with strapped leather valise, and a working brass railway compartment clock
##                          above the corridor door (PieceClock)
##                        - rear bulkhead: claret velvet lower sleeper berth sofa with rolled bolsters, folded ivory
##                          linen and wool travel blanket; folded-up walnut, brass and ivory-linen upper sleeping berth
##                          stowed high on the rear bulkhead with brass strap brackets, latch handles, ladder hooks and
##                          a stowed slim brass bunk ladder
##                        - left panoramic window: walnut-and-brass Art Deco curtain pelmet box, deeply pleated
##                          drawn-back claret velvet curtains with brass tie-back clasps, flanking marquetry piers with
##                          brass diamond inlays, and a brass-slatted under-sill steam radiator grille
##                        - arched roof & lighting: walnut-and-brass ceiling ribs, glowing sapphire-blue night lamp
##                          glass globe framed by a stepped walnut-and-brass ceiling medallion (PieceCove, live Night
##                          lamp setting, cove_floor 0.65), plus four warm Art Deco brass-and-opal-glass sconces
##   sleeper_1929_props   the portable 16 mm projection setup and travel props:
##                        - front bulkhead: custom walnut-and-brass spring-roller portable linen projection screen
##                          casing with turned brass end-caps, hanging hooks, slim side trim, weighted lower dowel bar
##                          and brass pull ring, above a low marquetry bulkhead console cabinet
##                        - folding walnut window-side table tucked neatly left-front (> 0.9 m clear of the seat) with
##                          brass edge banding and hinged diagonal folding leg, holding a vintage 1929 16 mm home film
##                          projector (black enamel body, vented lamphouse, twin spoked brass reels, optical lens barrel
##                          and subtle glowing lens aperture aimed at the screen), a bone-china porcelain teacup & saucer
##                          with brass teaspoon, and a burgundy leatherbound travel timetable with brass corner clasps

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")

const PIECES: Array[String] = ["sleeper_1929_cabin", "sleeper_1929_props"]

## World-space coordinates of the tabletop 1929 16 mm projector's lens (matches atmosphere.lens in the document).
const PROJECTOR_AT := Vector3(-0.98, 0.72, -1.08)
const PROJECTOR_LENS := Vector3(-0.885, 0.915, -1.202)

## Palette (sRGB): 1929 burled walnut, reddish mahogany marquetry, warm antique brass, claret velvet, ivory linen.
const WALNUT_DARK := Color(0.2, 0.11, 0.065)
const WALNUT_MID := Color(0.3, 0.17, 0.095)
const MAHOGANY_INLAY := Color(0.42, 0.21, 0.11)
const BURL_HONEY := Color(0.52, 0.31, 0.16)
const BRASS_GOLD := Color(0.95, 0.68, 0.24)
const BRASS_WARM := Color(0.84, 0.56, 0.20)
const CLARET_VELVET := Color(0.42, 0.08, 0.12)
const CLARET_DEEP := Color(0.24, 0.04, 0.07)
const LINEN_IVORY := Color(0.92, 0.89, 0.82)
const BLANKET_NAVY := Color(0.11, 0.17, 0.29)
const ENAMEL_BLACK := Color(0.08, 0.08, 0.09)
const ENAMEL_CHARCOAL := Color(0.15, 0.15, 0.17)
const LEATHER_TAN := Color(0.48, 0.27, 0.14)
const LEATHER_OXBLOOD := Color(0.34, 0.08, 0.1)
const CHINA_CREAM := Color(0.95, 0.93, 0.88)
const TEA_AMBER := Color(0.38, 0.18, 0.07)
const WARM_LAMP := Color(1.0, 0.82, 0.54)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"sleeper_1929_cabin":
			_cabin(c)
		"sleeper_1929_props":
			_props(c)


# --- Piece 1: 1929 sleeping compartment architecture, marquetry, corridor door, berths & lighting ---------------------

static func _cabin(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_corridor_wall(c, q)
	_berths_and_rear(c, q)
	_left_window_and_drapes(c, q)
	_ceiling_and_lighting(c, q)
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE
	c.cove.colour = Color.WHITE


## Right corridor wall (solid): Art Deco walnut & mahogany marquetry panels with brass diamond medallions, recessed
## sliding wood-and-frosted-glass corridor door with brass latch & transom pane, overhead brass luggage rack with
## strapped leather valise, and working brass railway compartment clock above the door.
static func _corridor_wall(c: Object, q: Dictionary) -> void:
	var rx := float(q["cx"]) + float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var wall_h := float(q["wall_height"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# Door spans z = -1.18..-0.32 (centred at z = -0.75, width 0.86 m), height 1.70 m, transom 1.74..1.86 m.
	var dz := -0.75
	var dw := 0.86
	var d_lo := dz - dw * 0.5
	var d_hi := dz + dw * 0.5
	var dh := 1.70

	# Walnut vertical pilasters framing the three bays on the right wall + continuous upper frieze rail.
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_DARK.srgb_to_linear()
	for pz: float in [fz + 0.06, d_lo - 0.05, d_hi + 0.05, 0.78, bz - 0.06]:
		s.box(Vector3(rx - 0.018, wall_h * 0.5, pz), Vector3(0.036, wall_h - 0.04, 0.085), Basis(), [RoomMesh.RIGHT])
	# Continuous Art Deco cornice frieze and upper door header beam along the corridor wall.
	s.box(Vector3(rx - 0.02, wall_h - 0.055, (fz + bz) * 0.5), Vector3(0.04, 0.09, bz - fz - 0.06), Basis(),
			[RoomMesh.RIGHT])
	s.box(Vector3(rx - 0.024, dh + 0.025, dz), Vector3(0.048, 0.05, dw + 0.14), Basis(), [RoomMesh.RIGHT])
	s.box(Vector3(rx - 0.024, 1.88, dz), Vector3(0.048, 0.04, dw + 0.14), Basis(), [RoomMesh.RIGHT])

	# Marquetry inset wood panels on the forward bay (sconce bay: clean border + lower diamond so sconce never clips
	# the central medallion!) and aft bays (full tall brass diamond medallions).
	var bays := [
		[-2.28, -1.28, false],
		[-0.22, 0.72, true],
		[0.84, 1.66, true],
	]
	for bay: Array in bays:
		var z0: float = bay[0]
		var z1: float = bay[1]
		var has_medallion: bool = bay[2]
		var zm := (z0 + z1) * 0.5
		var span := z1 - z0
		# Lower dado marquetry panel (y = 0.14..0.80) and upper tall marquetry panel (y = 0.96..2.20).
		s.colour = MAHOGANY_INLAY.srgb_to_linear()
		s.box(Vector3(rx - 0.008, 0.47, zm), Vector3(0.016, 0.64, span - 0.12), Basis(), [RoomMesh.RIGHT])
		s.box(Vector3(rx - 0.008, 1.58, zm), Vector3(0.016, 1.22, span - 0.12), Basis(), [RoomMesh.RIGHT])
		s.colour = BURL_HONEY.srgb_to_linear()
		s.box(Vector3(rx - 0.012, 1.58, zm), Vector3(0.01, 0.96, span - 0.28), Basis(), [RoomMesh.RIGHT])
		# Gleaming inlaid brass trim border lines and Art Deco diamond medallion (sconce bay keeps diamond below sconce).
		_brass_marquetry_panel(c, u, rx - 0.018, 1.58, zm, span - 0.24, 1.08, -1.0, has_medallion)
		_brass_marquetry_panel(c, u, rx - 0.017, 0.47, zm, span - 0.18, 0.52, -1.0, true)

	# Recessed sliding wood-and-frosted-glass corridor door leaf (slightly recessed behind its walnut jambs).
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_MID.srgb_to_linear()
	# Left & right vertical door stiles, bottom rail, lock rail and top rail.
	s.box(Vector3(rx - 0.014, dh * 0.5, d_lo + 0.065), Vector3(0.024, dh, 0.11), Basis(), [RoomMesh.RIGHT])
	s.box(Vector3(rx - 0.014, dh * 0.5, d_hi - 0.065), Vector3(0.024, dh, 0.11), Basis(), [RoomMesh.RIGHT])
	s.box(Vector3(rx - 0.014, 0.09, dz), Vector3(0.024, 0.18, dw - 0.20), Basis(), [RoomMesh.RIGHT])
	s.box(Vector3(rx - 0.014, 0.88, dz), Vector3(0.024, 0.14, dw - 0.20), Basis(), [RoomMesh.RIGHT])
	s.box(Vector3(rx - 0.014, dh - 0.06, dz), Vector3(0.024, 0.12, dw - 0.20), Basis(), [RoomMesh.RIGHT])
	# Lower marquetry door panel.
	s.colour = MAHOGANY_INLAY.srgb_to_linear()
	s.box(Vector3(rx - 0.01, 0.49, dz), Vector3(0.016, 0.64, dw - 0.22), Basis(), [RoomMesh.RIGHT])
	_brass_marquetry_panel(c, u, rx - 0.019, 0.49, dz, dw - 0.28, 0.52, -1.0)

	# Warm frosted-glass upper corridor door pane & frosted transom pane (PieceWindows, glowing from corridor outside).
	var gw: Array = c.glows.get("window", [])
	gw.append([Vector3(rx - 0.012, 1.29, dz), Vector3(0.0, 0.0, (dw - 0.24) * 0.5), Vector3(0.0, 0.33, 0.0),
			Vector3.LEFT])
	gw.append([Vector3(rx - 0.014, 1.795, dz), Vector3(0.0, 0.0, (dw - 0.16) * 0.5), Vector3(0.0, 0.062, 0.0),
			Vector3.LEFT])
	c.glows["window"] = gw

	# Gleaming brass hardware on the sliding corridor door: decorative muntin grille, curved latch handle, finger pull,
	# brass kick-plate and overhead sliding door track rail.
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	# Art Deco brass muntin bars across the frosted corridor door glass.
	u.box(Vector3(rx - 0.02, 1.29, dz), Vector3(0.012, 0.66, 0.016))
	u.box(Vector3(rx - 0.02, 1.44, dz), Vector3(0.012, 0.016, dw - 0.24))
	u.box(Vector3(rx - 0.02, 1.14, dz), Vector3(0.012, 0.016, dw - 0.24))
	# Diamond brass centre medallion over the frosted door pane.
	u.box(Vector3(rx - 0.022, 1.29, dz), Vector3(0.014, 0.13, 0.13), Basis(Vector3.RIGHT, PI * 0.25))
	# Transom vertical muntin bars.
	for tz: float in [dz - 0.16, dz + 0.16]:
		u.box(Vector3(rx - 0.02, 1.795, tz), Vector3(0.012, 0.125, 0.014))
	# Sliding door brass track rail & twin roller hangers.
	u.box(Vector3(rx - 0.036, dh + 0.026, dz), Vector3(0.02, 0.022, dw + 0.24))
	for hz: float in [d_lo + 0.12, d_hi - 0.12]:
		u.box(Vector3(rx - 0.036, dh - 0.005, hz), Vector3(0.022, 0.055, 0.04))
	# Curved brass latch handle, backplate escutcheon, privacy turn-bolt & brass kick-plate.
	var hx := rx - 0.028
	var h_z := d_hi - 0.075
	u.box(Vector3(hx, 0.92, h_z), Vector3(0.012, 0.22, 0.048))
	u.box(Vector3(hx - 0.032, 0.92, h_z), Vector3(0.018, 0.14, 0.018))
	for dy: float in [-0.06, 0.06]:
		u.box(Vector3(hx - 0.016, 0.92 + dy, h_z), Vector3(0.034, 0.018, 0.018))
	# Privacy thumb-turn bolt just below the handle.
	u.box(Vector3(hx - 0.014, 0.835, h_z), Vector3(0.022, 0.014, 0.038))
	# Polished brass kick-plate along the door bottom.
	u.box(Vector3(rx - 0.024, 0.08, dz), Vector3(0.008, 0.14, dw - 0.06))

	# Overhead brass luggage rack cleanly over the corridor door (y = 1.90 m, projecting 0.23 m into room).
	var rack_y := 1.90
	var rack_z0 := -1.34
	var rack_z1 := -0.16
	var rack_zm := (rack_z0 + rack_z1) * 0.5
	var rack_len := rack_z1 - rack_z0
	var rack_out := 0.23
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
	# Longitudinal brass slats & slightly raised front retaining rail with decorative ball finials.
	for k in 4:
		var sx := rx - 0.05 - float(k) * ((rack_out - 0.06) / 3.0)
		Shapes.cylinder(u, Vector3(sx, rack_y, rack_z0), 0.007, rack_len, 6, basis_z)
	Shapes.cylinder(u, Vector3(rx - rack_out, rack_y + 0.045, rack_z0 - 0.02), 0.011, rack_len + 0.04, 8, basis_z)
	for ez: float in [rack_z0 - 0.022, rack_z1 + 0.022]:
		u.rounded_box(Vector3(rx - rack_out, rack_y + 0.045, ez), Vector3(0.03, 0.03, 0.03), 0.012, Transform3D(), 1)
	# Three sculpted stepped Art Deco brass wall brackets supporting the rack.
	for bz_k: float in [rack_z0 + 0.04, rack_zm, rack_z1 - 0.04]:
		u.box(Vector3(rx - 0.012, rack_y - 0.03, bz_k), Vector3(0.022, 0.14, 0.026))
		u.box(Vector3(rx - rack_out * 0.5, rack_y - 0.004, bz_k), Vector3(rack_out, 0.018, 0.022))
		u.box(Vector3(rx - rack_out, rack_y + 0.024, bz_k), Vector3(0.018, 0.052, 0.022))
		Shapes.beam(u, Vector3(rx - 0.015, rack_y - 0.09, bz_k), Vector3(rx - rack_out + 0.02, rack_y - 0.006, bz_k),
				Vector2(0.016, 0.016))

	# Small strapped tan leather weekend valise resting neatly on the forward end of the luggage rack (clear of clock!).
	u.surface(c.soft("china", true))
	u.colour = LEATHER_TAN.srgb_to_linear()
	var val_at := Vector3(rx - 0.125, rack_y + 0.075, -1.16)
	u.rounded_box(val_at, Vector3(0.18, 0.13, 0.30), 0.016, Transform3D(), 1)
	u.surface(_brass_mat(c))
	u.colour = BRASS_WARM.srgb_to_linear()
	for sz: float in [-0.085, 0.085]:
		u.box(val_at + Vector3(0.0, 0.0, sz), Vector3(0.188, 0.136, 0.018))
	u.box(val_at + Vector3(-0.094, 0.015, 0.0), Vector3(0.014, 0.028, 0.075))

	# Working brass railway compartment clock centered cleanly ABOVE the corridor door & luggage rack (y = 2.16 m).
	var clk_y := 2.165
	var clk_r := 0.106
	var basis_left := Basis(Vector3.UP, -PI * 0.5)
	# Stepped walnut Art Deco clock backing plaque.
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(Vector3(rx - 0.018, clk_y, dz), Vector3(0.036, 0.14, 0.62), Basis(), [RoomMesh.RIGHT])
	s.box(Vector3(rx - 0.024, clk_y, dz), Vector3(0.044, 0.25, 0.27), Basis(), [RoomMesh.RIGHT])
	# Gleaming brass circular bezel, speed-wings and live PieceClock dial facing -X into the compartment!
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	Shapes.arch(u, Vector3(rx - 0.052, clk_y, dz), clk_r, clk_r + 0.026, 0.04, 24, basis_left, 0.0, TAU,
			["front", "inner", "outer"])
	for side_z: float in [-1.0, 1.0]:
		var wz := dz + side_z * 0.215
		u.box(Vector3(rx - 0.04, clk_y + 0.034, wz), Vector3(0.014, 0.014, 0.15))
		u.box(Vector3(rx - 0.042, clk_y, wz - side_z * 0.012), Vector3(0.016, 0.018, 0.125))
		u.box(Vector3(rx - 0.04, clk_y - 0.034, wz - side_z * 0.025), Vector3(0.014, 0.014, 0.10))
	c.clocks.append([Vector3(rx - 0.064, clk_y, dz), Vector3(0.0, 0.0, clk_r), Vector3(0.0, clk_r, 0.0),
			Vector3.LEFT])


## Rear bulkhead: sumptuous claret velvet lower sleeper berth sofa with rolled bolsters and folded ivory linen/blanket,
## plus the folded-up walnut, brass & linen upper sleeping berth stowed neatly high on the rear bulkhead with brass
## folding strap brackets, latch handles, ladder hooks and a stowed slim brass bunk ladder.
static func _berths_and_rear(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# Lower sleeper berth plinth (z = 1.06..1.79, x = -1.25..+1.25, y = 0.0..0.30).
	var berth_w := hw * 2.0 - 0.10
	var berth_d := 0.72
	var berth_z := bz - berth_d * 0.5 - 0.01
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.15, berth_z), Vector3(berth_w, 0.30, berth_d), Basis(), [RoomMesh.DOWN, RoomMesh.BACK])
	# Recessed walnut under-berth luggage drawers with brass pulls.
	s.colour = WALNUT_MID.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * 0.56, 0.155, berth_z - berth_d * 0.5 - 0.006), Vector3(0.96, 0.21, 0.014))
	# Claret velvet berth mattress cushion, angled tufted backrest & twin cylindrical corner bolsters.
	u.surface(c.soft("drapes", true))
	u.colour = CLARET_VELVET.srgb_to_linear()
	u.rounded_box(Vector3(cx, 0.385, berth_z - 0.015), Vector3(berth_w + 0.02, 0.17, berth_d + 0.02), 0.055,
			Transform3D(), 1, Vector3i(2, 0, 1), 0.0, [RoomMesh.DOWN])
	var back_xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-11.0)), Vector3(cx, 0.74, bz - 0.12))
	u.rounded_box(Vector3.ZERO, Vector3(berth_w, 0.56, 0.16), 0.06, back_xf, 1, Vector3i(3, 1, 0), 0.0, [RoomMesh.BACK])
	u.colour = CLARET_DEEP.srgb_to_linear()
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
	for side: float in [-1.0, 1.0]:
		Shapes.cylinder(u, Vector3(cx + side * (berth_w * 0.5 - 0.11), 0.555, berth_z - 0.24), 0.095, 0.48, 12, basis_z)
	# Crisp folded ivory linen sheet and neatly folded deep-navy wool travel blanket resting cleanly on the berth seat.
	u.surface(c.soft("cloth", true))
	u.colour = LINEN_IVORY.srgb_to_linear()
	u.rounded_box(Vector3.ZERO, Vector3(0.56, 0.065, 0.46), 0.022,
			Transform3D(Basis(Vector3.UP, 0.08), Vector3(cx + 0.58, 0.50, berth_z + 0.02)), 1)
	u.colour = BLANKET_NAVY.srgb_to_linear()
	u.rounded_box(Vector3.ZERO, Vector3(0.50, 0.06, 0.42), 0.024,
			Transform3D(Basis(Vector3.UP, -0.05), Vector3(cx + 0.59, 0.558, berth_z + 0.01)), 1)
	# Plush cream sleeping pillow nestled snugly against the left backrest & seat cushion.
	u.colour = LINEN_IVORY.srgb_to_linear()
	u.rounded_box(Vector3.ZERO, Vector3(0.48, 0.22, 0.16), 0.065,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-24.0)) * Basis(Vector3.UP, 0.12),
			Vector3(cx - 0.54, 0.575, bz - 0.28)), 1)

	# Folded-up upper sleeping berth stowed neatly high on the rear bulkhead (y = 1.44..2.12, z = 1.54..1.79).
	var up_y := 1.78
	var up_w := hw * 2.0 - 0.24
	var up_h := 0.66
	var up_d := 0.22
	var up_z := bz - up_d * 0.5 - 0.01
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(Vector3(cx, up_y, up_z), Vector3(up_w, up_h, up_d), Basis(), [RoomMesh.BACK])
	s.colour = MAHOGANY_INLAY.srgb_to_linear()
	s.box(Vector3(cx, up_y, up_z - up_d * 0.5 - 0.008), Vector3(up_w - 0.14, up_h - 0.12, 0.016))
	s.colour = BURL_HONEY.srgb_to_linear()
	s.box(Vector3(cx, up_y, up_z - up_d * 0.5 - 0.014), Vector3(up_w - 0.34, up_h - 0.24, 0.01))
	# Crisp ivory folded upper-berth mattress & linen peeking neatly above the stowed mahogany frame.
	u.surface(c.soft("cloth", true))
	u.colour = LINEN_IVORY.srgb_to_linear()
	u.rounded_box(Vector3(cx, up_y + up_h * 0.5 + 0.045, up_z + 0.02), Vector3(up_w - 0.08, 0.11, up_d - 0.04), 0.035,
			Transform3D(), 1)

	# Gleaming brass berth hardware: marquetry trim & central diamond on the stowed berth underside, top linen guard
	# rail, twin side strap brackets, twin release-latch handles, drawer pulls, ladder hooks and stowed slim bunk ladder.
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	# Brass kick-plate & drawer handles on the lower berth plinth.
	u.box(Vector3(cx, 0.025, berth_z - berth_d * 0.5 - 0.005), Vector3(berth_w, 0.05, 0.008))
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.56, 0.165, berth_z - berth_d * 0.5 - 0.022), Vector3(0.14, 0.018, 0.02))
		# Brass bolster end buttons.
		u.rounded_box(Vector3(cx + side * (berth_w * 0.5 - 0.11), 0.555, berth_z - 0.245), Vector3(0.034, 0.034, 0.018),
				0.01, Transform3D(), 1)
	# Inlaid brass border & Art Deco diamond medallion across the underside of the stowed upper berth.
	var front_b := up_z - up_d * 0.5 - 0.022
	u.box(Vector3(cx, up_y + up_h * 0.5 - 0.075, front_b), Vector3(up_w - 0.22, 0.014, 0.012))
	u.box(Vector3(cx, up_y - up_h * 0.5 + 0.075, front_b), Vector3(up_w - 0.22, 0.014, 0.012))
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * (up_w * 0.5 - 0.11), up_y, front_b), Vector3(0.014, up_h - 0.15, 0.012))
		# Twin brass stowage release-latch handles & curved brass folding strap brackets at both ends.
		u.box(Vector3(cx + side * 0.55, up_y - up_h * 0.5 - 0.016, front_b + 0.04), Vector3(0.16, 0.022, 0.026))
		u.box(Vector3(cx + side * (hw - 0.04), up_y + 0.08, bz - 0.14), Vector3(0.06, 0.035, 0.24))
		u.box(Vector3(cx + side * (hw - 0.02), up_y + 0.16, bz - 0.20), Vector3(0.025, 0.24, 0.045))
		Shapes.beam(u, Vector3(cx + side * (hw - 0.05), up_y - 0.18, bz - 0.06),
				Vector3(cx + side * (hw - 0.05), up_y + 0.24, bz - 0.24), Vector2(0.02, 0.024))
	# Central brass diamond medallion on stowed upper berth face.
	u.box(Vector3(cx, up_y, front_b - 0.004), Vector3(0.24, 0.24, 0.012), Basis(Vector3.BACK, PI * 0.25))
	u.colour = WALNUT_DARK.srgb_to_linear()
	u.box(Vector3(cx, up_y, front_b - 0.008), Vector3(0.16, 0.16, 0.012), Basis(Vector3.BACK, PI * 0.25))
	u.colour = BRASS_GOLD.srgb_to_linear()
	u.box(Vector3(cx, up_y, front_b - 0.012), Vector3(0.08, 0.08, 0.012), Basis(Vector3.BACK, PI * 0.25))
	# Top brass retaining rail holding the stowed upper linen mattress.
	Shapes.cylinder(u, Vector3(cx - up_w * 0.46, up_y + up_h * 0.5 + 0.09, front_b + 0.03), 0.011, up_w * 0.92, 8,
			Basis(Vector3.BACK, -PI * 0.5))
	for kx: float in [-up_w * 0.44, 0.0, up_w * 0.44]:
		u.box(Vector3(cx + kx, up_y + up_h * 0.5 + 0.045, front_b + 0.03), Vector3(0.018, 0.095, 0.018))
	# Twin gleaming brass ladder hooks on the upper berth bottom edge + slim stowed brass bunk ladder in rear-right.
	for lx: float in [0.42, 0.74]:
		u.box(Vector3(lx, up_y - up_h * 0.5 - 0.025, front_b + 0.015), Vector3(0.028, 0.055, 0.032))
		u.box(Vector3(lx, up_y - up_h * 0.5 - 0.048, front_b - 0.012), Vector3(0.028, 0.018, 0.038))
	# Slim stowed brass bunk ladder latched flat against the rear-right corridor wall (z = 1.06..1.42, y = 0.08..1.48).
	var lad_x := cx + hw - 0.05
	for lz: float in [1.08, 1.40]:
		Shapes.cylinder(u, Vector3(lad_x, 0.08, lz), 0.012, 1.40, 8)
		u.box(Vector3(lad_x + 0.02, 1.47, lz), Vector3(0.04, 0.02, 0.024))
	for step in 5:
		var sy := 0.28 + 0.25 * step
		u.box(Vector3(lad_x, sy, 1.24), Vector3(0.028, 0.016, 0.31))

	# Clean physics boxes enclosing the lower berth sofa & stowed upper berth (strictly inside cabin, > 1.0 m from seat).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, 0.48, berth_z), Vector3(berth_w, 0.96, berth_d), Basis()))
	c.shapes.append(PhysicsShapes.box(Vector3(cx, up_y, up_z), Vector3(up_w, up_h + 0.12, up_d), Basis()))


## Left panoramic window wall: walnut-and-brass Art Deco pelmet box, deeply pleated drawn-back claret velvet curtains
## with gleaming brass tie-back clasps, flanking marquetry piers with brass diamond inlays, and a brass-slatted
## under-sill steam radiator grille.
static func _left_window_and_drapes(c: Object, q: Dictionary) -> void:
	var lx := float(q["cx"]) - float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var sill := float(q["window_sill"])
	var wh := float(q["window_height"])
	var ww := float(q["window_width"])
	var wzs: Array = q["window_zs"]
	var wz := float(wzs[0]) if not wzs.is_empty() else -0.25
	var w_lo := wz - ww * 0.5
	var w_hi := wz + ww * 0.5
	var w_top := sill + wh

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	# Walnut-and-brass Art Deco curtain pelmet box crowning the panoramic picture window.
	var pel_z0 := w_lo - 0.36
	var pel_z1 := w_hi + 0.36
	var pel_zm := (pel_z0 + pel_z1) * 0.5
	var pel_len := pel_z1 - pel_z0
	var pel_y := w_top + 0.10
	var pel_d := 0.14
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(Vector3(lx + pel_d - 0.016, pel_y, pel_zm), Vector3(0.032, 0.15, pel_len))
	s.box(Vector3(lx + pel_d * 0.5, pel_y + 0.065, pel_zm), Vector3(pel_d, 0.025, pel_len))
	for ez: float in [pel_z0 + 0.016, pel_z1 - 0.016]:
		s.box(Vector3(lx + pel_d * 0.5, pel_y, ez), Vector3(pel_d, 0.15, 0.032))
	# Deep walnut window sill shelf lip projecting cleanly over the dado.
	s.colour = WALNUT_MID.srgb_to_linear()
	s.box(Vector3(lx + 0.035, sill - 0.018, wz), Vector3(0.07, 0.036, ww + 0.18), Basis(), [RoomMesh.LEFT])
	# Left wall forward & aft marquetry piers (forward pier frames the reading sconce; rear pier has brass diamond).
	for pier: Array in [[fz + 0.12, pel_z0 - 0.08, false], [pel_z1 + 0.08, bz - 0.12, true]]:
		var p0: float = pier[0]
		var p1: float = pier[1]
		var has_medallion: bool = pier[2]
		if p1 - p0 < 0.38:
			continue
		var pm := (p0 + p1) * 0.5
		var pw := p1 - p0
		s.colour = MAHOGANY_INLAY.srgb_to_linear()
		s.box(Vector3(lx + 0.008, 1.56, pm), Vector3(0.016, 1.18, pw - 0.10), Basis(), [RoomMesh.LEFT])
		_brass_marquetry_panel(c, u, lx + 0.018, 1.56, pm, pw - 0.18, 1.02, 1.0, has_medallion)

	# Drawn-back deeply pleated claret velvet window curtains flanking both sides of the panoramic window: built as
	# continuous inward-facing pleated grids (zero culling gaps from any angle!) cinched by gleaming brass tie-backs.
	var hem_y := sill - 0.06
	var top_y := pel_y - 0.03
	var tie_y := lerpf(hem_y, top_y, 0.36)
	u.surface(c.soft("drapes", true))
	var c_lo := CLARET_DEEP.srgb_to_linear()
	var c_hi := CLARET_VELVET.srgb_to_linear()
	var c_hem := BRASS_WARM.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		# Front curtain (side -1) runs from z_min = pel_z0 + 0.03 to z_max = inner; rear curtain (side +1) from inner to
		# pel_z1 - 0.03. Keeping columns ordered strictly along +Z guarantees outward normal strictly toward +X!
		var outer_z := (pel_z0 + 0.03) if side < 0.0 else (pel_z1 - 0.03)
		var inner_top := (w_lo + 0.08) if side < 0.0 else (w_hi - 0.08)
		var inner_tie := (w_lo - 0.09) if side < 0.0 else (w_hi + 0.09)
		var inner_hem := (w_lo - 0.02) if side < 0.0 else (w_hi + 0.02)
		var cols := 13
		var v_steps := 10
		var rows_p: Array = []
		var rows_n: Array = []
		var rows_c: Array = []
		for r in v_steps + 1:
			var v := float(r) / v_steps
			var y := lerpf(hem_y, top_y, v)
			var in_z := _curtain_edge(v, inner_hem, inner_tie, inner_top)
			var z_min := minf(outer_z, in_z)
			var z_max := maxf(outer_z, in_z)
			var pinch := 1.0 - 0.42 * exp(-pow((v - 0.36) / 0.16, 2.0))
			var rp := PackedVector3Array()
			var rn := PackedVector3Array()
			var rc := PackedColorArray()
			for j in cols:
				var t := float(j) / (cols - 1)
				var z := lerpf(z_min, z_max, t)
				var wave := 0.5 - 0.5 * cos(t * TAU * 3.0)
				var dwave := sin(t * TAU * 3.0)
				# Return edges at j == 0 and j == cols - 1 tuck back cleanly to the wall so the curtain reads solid!
				var depth := 0.0 if (j == 0 or j == cols - 1) else (0.024 + 0.058 * wave * pinch)
				rp.append(Vector3(lx + 0.024 + depth, y, z))
				var n := Vector3(1.0, 0.0, -0.58 * dwave * pinch).normalized()
				if j == 0:
					n = Vector3(0.3, 0.0, -0.95).normalized()
				elif j == cols - 1:
					n = Vector3(0.3, 0.0, 0.95).normalized()
				rn.append(n)
				var shade := c_lo.lerp(c_hi, wave)
				if v <= 0.08:
					shade = c_hem * (0.65 + 0.35 * wave)
				rc.append(shade)
			rows_p.append(rp)
			rows_n.append(rn)
			rows_c.append(rc)
		u.grid(rows_p, rows_n, rows_c)

	# Gleaming brass pelmet speed lines, exposed brass curtain pole, tie-back clasps and refined radiator grille.
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	u.box(Vector3(lx + pel_d + 0.005, pel_y - 0.048, pel_zm), Vector3(0.012, 0.016, pel_len + 0.01))
	u.box(Vector3(lx + pel_d + 0.004, pel_y - 0.014, pel_zm), Vector3(0.01, 0.01, pel_len + 0.01))
	Shapes.cylinder(u, Vector3(lx + 0.082, top_y - 0.005, pel_z0 + 0.02), 0.01, pel_len - 0.04, 8,
			Basis(Vector3.RIGHT, PI * 0.5))
	# Brass Art Deco tie-back bands cinching each curtain waist cleanly.
	for side: float in [-1.0, 1.0]:
		var outer_z := (pel_z0 + 0.03) if side < 0.0 else (pel_z1 - 0.03)
		var inner_tie := (w_lo - 0.09) if side < 0.0 else (w_hi + 0.09)
		var cz := (outer_z + inner_tie) * 0.5
		var cw := absf(inner_tie - outer_z) + 0.04
		u.box(Vector3(lx + 0.072, tie_y, cz), Vector3(0.02, 0.026, cw))
		u.box(Vector3(lx + 0.04, tie_y, outer_z), Vector3(0.075, 0.024, 0.02))
	# Refined walnut-framed brass steam radiator grille tucked cleanly under the aft half of the window.
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(Vector3(lx + 0.032, 0.34, 0.14), Vector3(0.064, 0.40, 0.72), Basis(), [RoomMesh.LEFT])
	s.surface(c.tinted("iron"))
	s.colour = ENAMEL_BLACK.srgb_to_linear()
	s.box(Vector3(lx + 0.056, 0.34, 0.14), Vector3(0.024, 0.32, 0.64), Basis(), [RoomMesh.LEFT])
	u.colour = BRASS_WARM.srgb_to_linear()
	for slat in 6:
		var sy := 0.215 + 0.05 * slat
		u.box(Vector3(lx + 0.07, sy, 0.14), Vector3(0.01, 0.012, 0.62))
	for post_z: float in [-0.17, 0.14, 0.45]:
		u.box(Vector3(lx + 0.07, 0.34, post_z), Vector3(0.012, 0.34, 0.018))


## Arched roof walnut-and-brass ribs, the signature glowing sapphire-blue night lamp glass globe + soft arched ceiling
## wash halo (PieceCove, live Night lamp setting, cove_floor 0.65), and four warm Art Deco brass reading sconces.
static func _ceiling_and_lighting(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	# Two curved walnut-and-brass Art Deco ribs sweeping cleanly across the arched ceiling.
	var steps := 14
	for rz: float in [-1.42, 0.68]:
		s.surface(c.tinted("wood"))
		s.colour = WALNUT_DARK.srgb_to_linear()
		u.surface(_brass_mat(c))
		u.colour = BRASS_GOLD.srgb_to_linear()
		for i in steps:
			var x0 := lerpf(cx - hw + 0.02, cx + hw - 0.02, float(i) / steps)
			var x1 := lerpf(cx - hw + 0.02, cx + hw - 0.02, float(i + 1) / steps)
			var p0 := Vector3(x0, _roof_y(q, x0) - 0.016, rz)
			var p1 := Vector3(x1, _roof_y(q, x1) - 0.016, rz)
			Shapes.beam(s, p0, p1, Vector2(0.036, 0.065))
			Shapes.beam(u, p0 + Vector3(0.0, -0.022, 0.0), p1 + Vector3(0.0, -0.022, 0.0), Vector2(0.012, 0.022))

	# --- Signature glowing sapphire-blue night lamp (PieceCove: live Night lamp setting, cove_floor 0.65) ---
	# Framed inside an authentic stepped Art Deco walnut-and-brass circular ceiling medallion ring so the softly
	# washed plaster dish (PieceCove) sits cleanly inside real architectural moulding with zero hard shader seam!
	var nl_z := -0.35
	var crown_y := _roof_y(q, cx)
	var ring_r := 0.40
	var ring_segs := 24
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_DARK.srgb_to_linear()
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	for k in ring_segs:
		var a0 := TAU * float(k) / ring_segs
		var a1 := TAU * float(k + 1) / ring_segs
		var p0 := Vector3(cx + cos(a0) * ring_r, _roof_y(q, cx + cos(a0) * ring_r) - 0.022, nl_z + sin(a0) * ring_r)
		var p1 := Vector3(cx + cos(a1) * ring_r, _roof_y(q, cx + cos(a1) * ring_r) - 0.022, nl_z + sin(a1) * ring_r)
		Shapes.beam(s, p0, p1, Vector2(0.044, 0.036))
		var b0 := Vector3(cx + cos(a0) * (ring_r - 0.024), _roof_y(q, cx + cos(a0) * (ring_r - 0.024)) - 0.034,
				nl_z + sin(a0) * (ring_r - 0.024))
		var b1 := Vector3(cx + cos(a1) * (ring_r - 0.024), _roof_y(q, cx + cos(a1) * (ring_r - 0.024)) - 0.034,
				nl_z + sin(a1) * (ring_r - 0.024))
		Shapes.beam(u, b0, b1, Vector2(0.016, 0.016))
	# Stepped walnut & gleaming brass central collar housing cradling the night-lamp glass globe.
	Shapes.cylinder(s, Vector3(cx, crown_y - 0.045, nl_z), 0.165, 0.045, 16)
	Shapes.lathe(u, [Vector2(0.145, 0.0), Vector2(0.145, 0.018), Vector2(0.112, 0.022), Vector2(0.096, 0.050),
			Vector2(0.078, 0.054)], Vector3(cx, crown_y - 0.088, nl_z), 16)
	# Four slender Art Deco brass rib fins hugging the glass globe.
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var fx := cx + cos(a) * 0.080
		var fz_fin := nl_z + sin(a) * 0.080
		u.box(Vector3(fx, crown_y - 0.118, fz_fin), Vector3(0.012, 0.072, 0.020), Basis(Vector3.UP, -a))
	# Lathed milk-glass night-lamp globe in PieceCove (glows jewel sapphire blue or warm amber via Night lamp setting!).
	cove.surface(c.kit.cove_material())
	var globe_col := Color(0.96, 0.98, 1.0).srgb_to_linear()
	cove.colour = Color(globe_col.r, globe_col.g, globe_col.b, 0.98)
	var g_prof: Array = []
	var g_rings := 8
	for i in g_rings + 1:
		var lat := lerpf(-PI * 0.5, PI * 0.35, float(i) / g_rings)
		g_prof.append(Vector2(cos(lat) * 0.076, sin(lat) * 0.070))
	Shapes.lathe(cove, g_prof, Vector3(cx, crown_y - 0.142, nl_z), 16)
	# Recessed plaster ceiling cove dish neatly bounded inside the walnut-and-brass ring (r = 0.14..ring_r - 0.01).
	var halo_radii: Array[float] = [0.14, 0.24, ring_r - 0.01]
	var halo_alphas: Array[float] = [0.82, 0.48, 0.22]
	var plaster_col := Color(0.92, 0.90, 0.84).srgb_to_linear()
	for r_idx in halo_radii.size() - 1:
		var r0 := halo_radii[r_idx]
		var r1 := halo_radii[r_idx + 1]
		var a0 := halo_alphas[r_idx]
		var a1 := halo_alphas[r_idx + 1]
		var row0 := PackedVector3Array()
		var row1 := PackedVector3Array()
		var n0 := PackedVector3Array()
		var n1 := PackedVector3Array()
		var c0 := PackedColorArray()
		var c1 := PackedColorArray()
		for k in ring_segs + 1:
			var ang := TAU * float(k) / ring_segs
			var dx0 := cos(ang) * r0
			var dz0 := sin(ang) * r0
			var dx1 := cos(ang) * r1
			var dz1 := sin(ang) * r1
			row0.append(Vector3(cx + dx0, _roof_y(q, cx + dx0) - 0.012, nl_z + dz0))
			row1.append(Vector3(cx + dx1, _roof_y(q, cx + dx1) - 0.012, nl_z + dz1))
			n0.append(Vector3.DOWN)
			n1.append(Vector3.DOWN)
			c0.append(Color(plaster_col.r, plaster_col.g, plaster_col.b, a0))
			c1.append(Color(plaster_col.r, plaster_col.g, plaster_col.b, a1))
		cove.grid([row0, row1], [n0, n1], [c0, c1])

	# Secondary jewel-sized recessed night-light globe & brass hood over the rear berth (also live via PieceCove).
	var rear_nl := Vector3(cx, 2.29, bz - 0.075)
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	u.box(Vector3(cx, 2.315, bz - 0.04), Vector3(0.18, 0.07, 0.08))
	cove.colour = Color(globe_col.r, globe_col.g, globe_col.b, 0.94)
	var mini_prof: Array = []
	for i in 7:
		var lat := lerpf(-PI * 0.5, PI * 0.4, float(i) / 6.0)
		mini_prof.append(Vector2(cos(lat) * 0.036, sin(lat) * 0.032))
	Shapes.lathe(cove, mini_prof, rear_nl, 12)
	cove.colour = Color.WHITE

	# --- Four warm Art Deco brass-and-opal-glass reading sconces (PieceLamps, house group) ---
	lit.surface(c.shade(WARM_LAMP))
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	# Forward left & right wall reading sconces (x = ±1.29, y = 1.62, z = -1.78).
	for side: float in [-1.0, 1.0]:
		var wx := cx + side * hw
		var inward := -side
		_art_deco_sconce(u, lit, Vector3(wx, 1.62, -1.78), Vector3(inward, 0.0, 0.0))
	# Rear berth bedside reading sconces flanking the lower berth (z = bz, x = ±1.06, y = 1.18).
	for side: float in [-1.0, 1.0]:
		_art_deco_sconce(u, lit, Vector3(cx + side * 1.04, 1.18, bz), Vector3.FORWARD)
	# Two gentle warm house bake lights illuminating the entire walnut compartment cleanly.
	c.lamps.append([Vector3(cx, crown_y - 0.34, -1.05), WARM_LAMP, 0.75])
	c.lamps.append([Vector3(cx, crown_y - 0.34, 0.78), WARM_LAMP, 0.7])
	var _unused_fz := fz


# --- Piece 2: portable 16 mm linen screen, folding walnut window table, 1929 projector, teacup & timetable ------------

static func _props(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_portable_screen(c, q)
	_window_table_and_projector(c, q)
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE


## Custom portable 1929 linen roller projection screen mounted cleanly on the front walnut bulkhead, above a low
## inlaid marquetry bulkhead console cabinet with brass gallery rail.
static func _portable_screen(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 1.4125, -2.34)))
	var sc_sz: Vector2 = scr.get("size", Vector2(1.68, 0.945))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var sz := sc_xf.origin.z
	var w := sc_sz.x
	var h := sc_sz.y
	var hw := w * 0.5
	var hh := h * 0.5
	var fz := float(q["front_z"])
	var cab_hw := float(q["hw"])

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis_x := Basis(Vector3.BACK, -PI * 0.5)

	# Walnut-and-brass spring-roller housing directly above the portable linen screen (y = cy + hh + 0.05).
	var top_y := cy + hh
	var bot_y := cy - hh
	var roll_y := top_y + 0.052
	var roll_w := w + 0.14
	s.surface(c.tinted("wood"))
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(Vector3(cx, roll_y, fz + 0.048), Vector3(roll_w, 0.092, 0.096), Basis(), [RoomMesh.FRONT])
	# Slim dark-walnut side masking borders hugging outside the picture face (never obstructing sight lines!).
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * (hw + 0.022), cy, sz - 0.016), Vector3(0.044, h + 0.02, 0.022))
	# Weighted lower walnut tension bar directly beneath the portable linen screen.
	s.box(Vector3(cx, bot_y - 0.022, sz - 0.008), Vector3(w + 0.09, 0.036, 0.032))

	# Front bulkhead flanking marquetry panels & low inlaid console cabinet below the screen (y = 0.0..0.72).
	var con_h := 0.72
	var con_d := 0.21
	var con_w := cab_hw * 2.0 - 0.28
	var con_z := fz + con_d * 0.5
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(Vector3(cx, con_h * 0.5, con_z), Vector3(con_w, con_h, con_d), Basis(), [RoomMesh.DOWN, RoomMesh.FRONT])
	s.colour = WALNUT_MID.srgb_to_linear()
	s.box(Vector3(cx, con_h + 0.014, con_z + 0.008), Vector3(con_w + 0.04, 0.028, con_d + 0.02))
	s.colour = MAHOGANY_INLAY.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * 0.76, 0.36, con_z + con_d * 0.5 + 0.006), Vector3(0.56, 0.52, 0.012))
	# Central recessed steam heater louver panel under the console.
	s.surface(c.tinted("iron"))
	s.colour = ENAMEL_BLACK.srgb_to_linear()
	s.box(Vector3(cx, 0.35, con_z + con_d * 0.5 + 0.004), Vector3(0.76, 0.48, 0.01))

	# Gleaming brass fittings on the portable screen: turned end-caps on the roller box, hanging wall hooks, trim strips,
	# weighted bottom dowel finials, delicate central pull ring, and brass radiator/gallery rails on the console.
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	# Turned cylindrical brass end-caps flanking the screen roller box + top brass trim line.
	for side: float in [-1.0, 1.0]:
		var ex := cx + side * (roll_w * 0.5)
		Shapes.cylinder(u, Vector3(ex - (0.045 if side < 0.0 else 0.0), roll_y, fz + 0.048), 0.052, 0.045, 12, basis_x)
		# Brass hanging eye-brackets & bulkhead hooks above the roller box.
		u.box(Vector3(cx + side * (hw - 0.14), roll_y + 0.085, fz + 0.036), Vector3(0.024, 0.095, 0.024))
		u.rounded_box(Vector3(cx + side * (hw - 0.14), roll_y + 0.135, fz + 0.038), Vector3(0.048, 0.048, 0.026), 0.015,
				Transform3D(), 1)
		# Thin gleaming brass side fillet strips outside the screen edges.
		u.box(Vector3(cx + side * (hw + 0.044), cy, sz - 0.012), Vector3(0.01, h + 0.02, 0.014))
		# Brass end finials on the weighted lower tension bar.
		Shapes.cylinder(u, Vector3(cx + side * (hw + 0.045) - (0.03 if side < 0.0 else 0.0), bot_y - 0.022, sz - 0.008),
				0.02, 0.03, 10, basis_x)
	u.box(Vector3(cx, roll_y - 0.038, fz + 0.098), Vector3(roll_w + 0.01, 0.014, 0.01))
	u.box(Vector3(cx, roll_y + 0.038, fz + 0.098), Vector3(roll_w + 0.01, 0.014, 0.01))
	# Central brass pull ring hanging cleanly below the screen's weighted dowel bar.
	Shapes.arch(u, Vector3(cx, bot_y - 0.068, sz - 0.008), 0.018, 0.028, 0.012, 14, Basis(), 0.0, TAU,
			["front", "back", "inner", "outer"])
	# Art Deco brass crest medallion & gallery rail on the low front console cabinet.
	u.box(Vector3(cx, con_h + 0.068, con_z + con_d * 0.5 - 0.015), Vector3(con_w - 0.04, 0.012, 0.012))
	for kx: float in [-con_w * 0.46, -0.42, 0.42, con_w * 0.46]:
		u.box(Vector3(cx + kx, con_h + 0.046, con_z + con_d * 0.5 - 0.015), Vector3(0.014, 0.045, 0.014))
	u.colour = BRASS_WARM.srgb_to_linear()
	for slat in 6:
		u.box(Vector3(cx, 0.17 + 0.068 * slat, con_z + con_d * 0.5 + 0.012), Vector3(0.70, 0.014, 0.01))
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.76, 0.36, con_z + con_d * 0.5 + 0.014), Vector3(0.14, 0.14, 0.01),
				Basis(Vector3.BACK, PI * 0.25))
		# Vertical Art Deco brass trim flutes on the front bulkhead corners flanking the screen.
		u.box(Vector3(cx + side * (cab_hw - 0.12), 1.44, fz + 0.014), Vector3(0.016, 1.38, 0.016))
		u.box(Vector3(cx + side * (cab_hw - 0.17), 1.44, fz + 0.012), Vector3(0.01, 1.24, 0.012))

	# Clean physics collision box for the front bulkhead console cabinet.
	c.shapes.append(PhysicsShapes.box(Vector3(cx, con_h * 0.5, con_z), Vector3(con_w, con_h, con_d), Basis()))


## Folding walnut window-side table tucked neatly left-front (> 0.9 m clear of the seat), holding the vintage 1929
## 16 mm home film projector aimed cleanly at the portable linen screen, a porcelain teacup & saucer, and a burgundy
## leatherbound travel timetable.
static func _window_table_and_projector(c: Object, q: Dictionary) -> void:
	var lx := float(q["cx"]) - float(q["hw"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# Folding walnut window-side table: x = -1.29..-0.75 (width 0.54 m), z = -1.34..-0.54 (depth 0.80 m), top y = 0.72 m.
	var tw := 0.54
	var td := 0.80
	var th := 0.72
	var tx := lx + tw * 0.5 + 0.01
	var tz := -0.94

	s.surface(c.tinted("wood"))
	s.colour = WALNUT_MID.srgb_to_linear()
	s.box(Vector3(tx, th - 0.016, tz), Vector3(tw, 0.032, td))
	s.colour = BURL_HONEY.srgb_to_linear()
	s.box(Vector3(tx, th - 0.001, tz), Vector3(tw - 0.10, 0.004, td - 0.12))
	# Walnut wall ledger strip & hinged folding leaf rail underneath.
	s.colour = WALNUT_DARK.srgb_to_linear()
	s.box(Vector3(lx + 0.025, th - 0.055, tz), Vector3(0.045, 0.065, td - 0.08), Basis(), [RoomMesh.LEFT])
	s.box(Vector3(tx, th - 0.05, tz), Vector3(tw - 0.08, 0.04, 0.06))
	# Diagonal folding walnut-and-brass strut leg down to a wall bracket on the left dado.
	Shapes.beam(s, Vector3(lx + 0.04, 0.24, tz), Vector3(tx + 0.14, th - 0.045, tz), Vector2(0.042, 0.048))

	# Brass edge banding around the folding table, wall hinge plates and diagonal folding strut collar.
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	u.box(Vector3(tx + tw * 0.5 + 0.004, th - 0.016, tz), Vector3(0.01, 0.034, td + 0.008))
	for dz: float in [-1.0, 1.0]:
		u.box(Vector3(tx, th - 0.016, tz + dz * (td * 0.5 + 0.004)), Vector3(tw + 0.008, 0.034, 0.01))
	u.box(Vector3(lx + 0.032, 0.24, tz), Vector3(0.06, 0.09, 0.09))
	u.box(Vector3(tx + 0.14, th - 0.045, tz), Vector3(0.07, 0.036, 0.08))

	# --- Vintage 1929 16 mm home film projector aimed at the screen center (0.0, 1.4125, -2.34) ---
	var sc_origin: Vector3 = (c.screen.get("xf", Transform3D(Basis(), Vector3(0.0, 1.4125, -2.34))) as Transform3D).origin
	var to_scr := sc_origin - PROJECTOR_AT
	var proj_yaw := -atan2(to_scr.x, -to_scr.z)
	var pxf := Transform3D(Basis(Vector3.UP, proj_yaw), PROJECTOR_AT)
	var pb := pxf.basis

	# Black-enamel Art Deco pedestal base, upright mechanical column & vented horizontal lamphouse.
	s.surface(c.tinted("iron"))
	s.colour = ENAMEL_BLACK.srgb_to_linear()
	s.box(pxf * Vector3(0.0, 0.022, 0.0), Vector3(0.155, 0.034, 0.245), pb)
	# Upright mechanical film-gate standard & drive gearbox housing.
	s.box(pxf * Vector3(0.0, 0.125, -0.02), Vector3(0.078, 0.175, 0.125), pb)
	# Vented 1929 cylindrical/octagonal lamphouse mounted behind the film gate.
	s.colour = ENAMEL_CHARCOAL.srgb_to_linear()
	s.box(pxf * Vector3(0.0, 0.165, 0.072), Vector3(0.102, 0.145, 0.118), pb)
	# Domed black-enamel lamphouse top chimney cap.
	Shapes.cylinder(s, pxf * Vector3(0.0, 0.235, 0.072), 0.042, 0.035, 10, pb)

	# Gleaming brass projector craftsmanship: leveling feet, tilt thumbscrew, lamphouse cooling louvers,
	# optical lens barrel tilted up toward screen, twin reel arms & twin spoked 16 mm brass reels with dark film coils!
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	for sx: float in [-0.06, 0.06]:
		for sz_f: float in [-0.095, 0.095]:
			u.box(pxf * Vector3(sx, 0.005, sz_f), Vector3(0.02, 0.01, 0.02), pb)
	# Front elevation tilt screw & right-side brass framing knob + hand-crank wheel.
	u.box(pxf * Vector3(0.0, 0.048, -0.105), Vector3(0.024, 0.028, 0.024), pb)
	var basis_right := pb * Basis(Vector3.BACK, -PI * 0.5)
	Shapes.cylinder(u, pxf * Vector3(0.038, 0.135, -0.015), 0.026, 0.022, 10, basis_right)
	Shapes.cylinder(u, pxf * Vector3(0.042, 0.085, 0.035), 0.016, 0.018, 8, basis_right)
	# Brass cooling louver rings on the lamphouse sides.
	for lv in 4:
		u.box(pxf * Vector3(0.0, 0.125 + 0.024 * lv, 0.072), Vector3(0.108, 0.008, 0.09), pb)
	# Projecting brass optical lens barrel aimed up (+14 deg) directly toward the linen screen!
	var lens_pitch := deg_to_rad(14.0)
	var lens_basis := pb * Basis(Vector3.RIGHT, lens_pitch)
	var lens_cyl_basis := lens_basis * Basis(Vector3.RIGHT, -PI * 0.5)
	Shapes.cylinder(u, pxf * Vector3(0.0, 0.175, -0.078), 0.025, 0.076, 12, lens_cyl_basis)
	Shapes.cylinder(u, pxf * Vector3(0.0, 0.186, -0.122), 0.030, 0.024, 12, lens_cyl_basis)
	# Subtle warm glowing projector lens face right at the tip of the barrel (PiecePort: stays lit while film plays!).
	var lens_tip := pxf * Vector3(0.0, 0.195, -0.155)
	var lens_fwd := (lens_basis * Vector3.FORWARD).normalized()
	var gp: Array = c.glows.get("port", [])
	gp.append([lens_tip, lens_basis.x * 0.023, lens_basis.y * 0.023, lens_fwd])
	c.glows["port"] = gp

	# Twin 1929 16 mm film reel arms and classic spoked brass reels (upper feed reel + aft take-up reel).
	var upper_hub := Vector3(0.015, 0.345, -0.045)
	var lower_hub := Vector3(0.015, 0.155, 0.185)
	Shapes.beam(u, pxf * Vector3(0.005, 0.21, -0.025), pxf * upper_hub, Vector2(0.014, 0.018))
	Shapes.beam(u, pxf * Vector3(0.005, 0.12, 0.06), pxf * lower_hub, Vector2(0.014, 0.018))
	_film_reel(c, u, s, pxf, upper_hub, 0.088)
	_film_reel(c, u, s, pxf, lower_hub, 0.082)

	# --- Vintage porcelain teacup & saucer with brass teaspoon (z = -0.68, right beside the snowy window!) ---
	var cup_at := Vector3(tx + 0.08, th, -0.68)
	u.surface(c.soft("china", true))
	u.colour = CHINA_CREAM.srgb_to_linear()
	# Scalloped porcelain saucer.
	Shapes.lathe(u, [Vector2(0.0, 0.0), Vector2(0.042, 0.002), Vector2(0.068, 0.013), Vector2(0.072, 0.015)],
			cup_at, 14)
	# Delicately flared porcelain teacup body & curved ear-handle.
	Shapes.lathe(u, [Vector2(0.022, 0.008), Vector2(0.036, 0.026), Vector2(0.044, 0.056), Vector2(0.046, 0.062)],
			cup_at, 14)
	for seg: Array in [
		[Vector3(0.040, 0.052, 0.0), Vector3(0.062, 0.050, 0.0)],
		[Vector3(0.062, 0.050, 0.0), Vector3(0.060, 0.028, 0.0)],
		[Vector3(0.060, 0.028, 0.0), Vector3(0.034, 0.022, 0.0)],
	]:
		Shapes.beam(u, cup_at + (seg[0] as Vector3), cup_at + (seg[1] as Vector3), Vector2(0.007, 0.007))
	# Rich amber tea surface inside the cup.
	u.colour = TEA_AMBER.srgb_to_linear()
	var tea_pts: Array = []
	for k in 12:
		var a := TAU * float(k) / 12.0
		tea_pts.append(cup_at + Vector3(cos(a) * 0.041, 0.052, sin(a) * 0.041))
	u.face(tea_pts, Vector3.UP)
	# Gilt cup rim band & gleaming brass teaspoon resting across the saucer.
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.045, 0.058), Vector2(0.047, 0.063)], cup_at, 14)
	Shapes.beam(u, cup_at + Vector3(-0.045, 0.016, 0.048), cup_at + Vector3(0.058, 0.017, 0.036), Vector2(0.006, 0.004))

	# --- Burgundy leatherbound 1929 travel timetable with brass corner clasps & cream pages ---
	var book_at := Vector3(tx - 0.09, th, -0.69)
	var book_b := Basis(Vector3.UP, 0.24)
	u.surface(c.soft("china", true))
	u.colour = LEATHER_OXBLOOD.srgb_to_linear()
	u.box(book_at + Vector3(0.0, 0.010, 0.0), Vector3(0.135, 0.019, 0.195), book_b)
	u.surface(c.soft("cloth", true))
	u.colour = LINEN_IVORY.srgb_to_linear()
	u.box(book_at + book_b * Vector3(0.004, 0.010, 0.0), Vector3(0.125, 0.013, 0.185), book_b)
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	# Brass corner clasps & gilt spine bars on the timetable cover.
	for cx_b: float in [-0.058, 0.058]:
		for cz_b: float in [-0.088, 0.088]:
			u.box(book_at + book_b * Vector3(cx_b, 0.011, cz_b), Vector3(0.02, 0.021, 0.02), book_b)
	u.box(book_at + book_b * Vector3(-0.066, 0.011, 0.0), Vector3(0.008, 0.02, 0.14), book_b)

	# Physics collision box for the folding window table & tabletop 16 mm projector (> 0.9 m clear of origin!).
	c.shapes.append(PhysicsShapes.box(Vector3(tx, 0.58, tz), Vector3(tw, 1.16, td), Basis()))


# --- Shared sculptural helpers ----------------------------------------------------------------------------------------

## Shared warm antique 1929 brass material (keeps all brass in one reflecting draw call).
static func _brass_mat(c: Object) -> Material:
	return c.shiny("gilt", 0.82, 0.56, 0.18)


## Inlaid Art Deco brass border frame & diamond medallion on a side wall (x = wall plane, inward_x = +1 or -1).
static func _brass_marquetry_panel(c: Object, u: RoomMesh, x: float, cy: float, cz: float, w: float, h: float,
		inward_x: float, medallion := true) -> void:
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	var bx := x + inward_x * 0.004
	var t := 0.011
	# Outer fine brass inlay border rectangle.
	u.box(Vector3(bx, cy + h * 0.5, cz), Vector3(0.008, t, w))
	u.box(Vector3(bx, cy - h * 0.5, cz), Vector3(0.008, t, w))
	u.box(Vector3(bx, cy, cz - w * 0.5), Vector3(0.008, h, t))
	u.box(Vector3(bx, cy, cz + w * 0.5), Vector3(0.008, h, t))
	if not medallion:
		# Sconce bay: clean twin stepped Art Deco brass corner accents leaving the centre unobstructed for the sconce.
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				u.box(Vector3(bx + inward_x * 0.001, cy + sy * (h * 0.5 - 0.055), cz + sz * (w * 0.5 - 0.055)),
						Vector3(0.007, 0.06, 0.06))
		return
	# Central Art Deco stepped brass diamond medallion & vertical speed line.
	var dm := minf(w, h) * 0.28
	if dm > 0.07:
		var d_basis := Basis(Vector3.RIGHT, PI * 0.25)
		u.box(Vector3(bx + inward_x * 0.002, cy, cz), Vector3(0.008, dm, dm), d_basis)
		u.box(Vector3(bx + inward_x * 0.001, cy, cz), Vector3(0.006, h * 0.78, 0.009))
		u.colour = WALNUT_DARK.srgb_to_linear()
		u.box(Vector3(bx + inward_x * 0.004, cy, cz), Vector3(0.008, dm * 0.62, dm * 0.62), d_basis)
		u.colour = BRASS_GOLD.srgb_to_linear()
		u.box(Vector3(bx + inward_x * 0.006, cy, cz), Vector3(0.008, dm * 0.3, dm * 0.3), d_basis)


## Sculpted 1929 Art Deco brass wall reading sconce with stepped brass backplate, curved stem and lathed frosted
## warm-opal glass tulip shade (`c.lit`, house group).
static func _art_deco_sconce(u: RoomMesh, lit: RoomMesh, wall_at: Vector3, normal: Vector3) -> void:
	var n := normal.normalized()
	var right := Vector3.UP.cross(n).normalized()
	var basis := Basis(right, Vector3.UP, n)
	# Stepped octagonal/vertical Art Deco brass wall backplate + curved support arm.
	u.box(wall_at + n * 0.012, Vector3(0.082, 0.22, 0.022), basis)
	u.box(wall_at + n * 0.024, Vector3(0.048, 0.26, 0.016), basis)
	u.box(wall_at + n * 0.068 + Vector3(0.0, -0.02, 0.0), Vector3(0.02, 0.02, 0.09), basis)
	var cup_at := wall_at + n * 0.108 + Vector3(0.0, -0.01, 0.0)
	Shapes.lathe(u, [Vector2(0.02, 0.0), Vector2(0.044, 0.028), Vector2(0.048, 0.042)], cup_at, 10)
	# Glowing frosted-opal Art Deco stepped tulip glass shade (`PieceLamps`).
	Shapes.lathe(lit, [Vector2(0.044, 0.040), Vector2(0.062, 0.088), Vector2(0.056, 0.145), Vector2(0.038, 0.185),
			Vector2(0.0, 0.195)], cup_at, 12)


## A spoked 1929 16 mm brass film reel with twin outer rim flanges, four radial spokes and a wound dark celluloid core.
static func _film_reel(c: Object, u: RoomMesh, s: RoomMesh, pxf: Transform3D, hub: Vector3, radius: float) -> void:
	var pb := pxf.basis
	var side_b := pb * Basis(Vector3.UP, PI * 0.5)
	var cyl_b := pb * Basis(Vector3.BACK, -PI * 0.5)
	# Dark wound 16 mm celluloid film roll inside the reel.
	s.surface(c.tinted("iron"))
	s.colour = ENAMEL_BLACK.srgb_to_linear()
	Shapes.cylinder(s, pxf * (hub + Vector3(-0.01, 0.0, 0.0)), radius * 0.72, 0.02, 14, cyl_b)
	# Twin gleaming brass outer rim rings, central hub boss and four radial spokes on each face.
	u.surface(_brass_mat(c))
	u.colour = BRASS_GOLD.srgb_to_linear()
	for dx: float in [-0.013, 0.013]:
		Shapes.arch(u, pxf * (hub + Vector3(dx, 0.0, 0.0)), radius * 0.82, radius, 0.005, 18, side_b, 0.0, TAU,
				["front", "back", "inner", "outer"])
		for k in 4:
			var a := PI * 0.25 + PI * 0.5 * k
			var spoke_b := side_b * Basis(Vector3.BACK, a)
			u.box(pxf * (hub + Vector3(dx, 0.0, 0.0)), Vector3(radius * 1.72, 0.011, 0.005), spoke_b)
	Shapes.cylinder(u, pxf * (hub + Vector3(-0.019, 0.0, 0.0)), 0.02, 0.038, 10, cyl_b)


## Smooth drawn-back curtain inner edge profile along height v in 0..1 (hem -> pinched waist -> pelmet top).
static func _curtain_edge(v: float, z_hem: float, z_tie: float, z_top: float) -> float:
	if v < 0.36:
		return lerpf(z_hem, z_tie, smoothstep(0.0, 0.36, v))
	return lerpf(z_tie, z_top, smoothstep(0.36, 1.0, v))


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
