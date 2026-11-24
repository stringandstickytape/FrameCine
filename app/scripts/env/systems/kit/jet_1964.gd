extends RefCounted

## The Jet 1964 transpolar first-class cabin (docs/environments/rooms/jet_1964.md): a glamorous mid-century narrow-body
## first-class jetliner cabin dressed over a leaning-wall `cabin` builder and `seats` (`recliner`) rows.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, arches and lathed shapes; no people,
## no real airline or aircraft mark, no text.
##
##   jet_1964_cabin   the cabin's 1964 inflight-cinema craft:
##                    - ceiling-mounted 16 mm twin-reel movie projector bolted cleanly to the central arched ceiling
##                      spine above the aisle (streamlined brushed-aluminium housing, cooling louvres, twin spoked
##                      vertical 16 mm reels with wound dark film packs, film-path rollers, canted dark telephoto lens
##                      barrel, and glowing lens aperture in `PiecePort`)
##                    - pull-down bulkhead cinema screen assembly (`screen_standoff` 0.08, `screen_frame` false):
##                      sleek brushed-aluminium top roller cassette on bulkhead brackets, matte-black velvet masking
##                      edges, weighted chrome bottom dowel bar with turned finials and central chrome pull ring, plus
##                      walnut-framed forward bulkhead trim and low pocket rails with colourful geometric flight folders
##                    - glowing backlit amber FASTEN SEATBELT / NO SMOKING geometric icon placard centered high above
##                      the screen roller cassette (`PieceWindows`, pure geometric buckle and circle-slash symbols)
##                    - 1960s open cantilevered overhead hat-racks curving along both leaning walls above the six oval
##                      fuselage windows per side, with continuous brushed-aluminium guardrails, recessed passenger
##                      service units above each row, continuous indirect mood cove strips (`PieceCove`), and five
##                      recessed overhead fluorescent ceiling valance panels (`PieceLamps`, house group)
##                    - aft galley bulkhead: brushed-steel door kick-plate and tubular pull handle, pleated mid-century
##                      champagne-gold galley curtain valance and terracotta tie-backs, working brushed-aluminium cabin
##                      clock (`PieceClock`), tiered walnut magazine pocket with colourful geometric folders, and a
##                      geometric polar great-circle route plaque
##   jet_1964_rows    the first-class recliner rows' hardware round `seats` (`recliner`):
##                    - chunky 1964 moulded charcoal & brushed-chrome armrests (keeping both armrests round the
##                      viewer's folded seat; slimmed outboard armrests tucked cleanly inside the 8 deg leaning fuselage
##                      wall), each topped with a brushed-chrome dual-hole pneumatic air-tube headset jack plate,
##                      audio channel selector dial, and recline button
##                    - crisp woven ivory linen antimacassar headrest covers hugging the exact `recliner` curve
##                      (`bend` -0.35, `radius` 0.06) with a subtle burnt-terracotta woven border band
##                    - flush curved flip-up warm-almond laminate seatback tray tables with chrome turn-latches
##                    - soft aisle carpet-edge guide light strips (`PieceCove`) along the aisle-facing armrest bases

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")

const PIECES: Array[String] = ["jet_1964_cabin", "jet_1964_rows"]

## Palette (sRGB): 1964 Jet Age cream-ivory liner, warm walnut, brushed aluminium, charcoal ABS, terracotta & gold.
const ALU_BRUSH := Color(0.80, 0.82, 0.84)
const ALU_DARK := Color(0.46, 0.49, 0.53)
const GOLD_TRIM := Color(0.88, 0.72, 0.36)
const IVORY_LINER := Color(0.90, 0.87, 0.80)
const RACK_SHELL := Color(0.86, 0.83, 0.76)
const WALNUT := Color(0.32, 0.18, 0.10)
const VELVET_BLACK := Color(0.04, 0.042, 0.048)
const CHARCOAL := Color(0.14, 0.145, 0.165)
const ARM_CAP := Color(0.095, 0.10, 0.115)
const SHELL_TAUPE := Color(0.46, 0.41, 0.36)
const TRAY_ALMOND := Color(0.86, 0.83, 0.76)
const LINEN_IVORY := Color(0.93, 0.91, 0.85)
const TERRACOTTA := Color(0.68, 0.25, 0.11)
const CURTAIN_GOLD := Color(0.86, 0.68, 0.34)
const TEAL_FOLDER := Color(0.14, 0.46, 0.50)
const MUSTARD_FOLDER := Color(0.84, 0.62, 0.18)
const NAVY_PLAQUE := Color(0.07, 0.13, 0.24)
const FILM_PACK := Color(0.11, 0.085, 0.07)
const CABIN_LAMP := Color(1.0, 0.92, 0.78)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"jet_1964_cabin":
			_cabin(c)
		"jet_1964_rows":
			_rows(c)


# --- The 1964 first-class jet cabin -----------------------------------------------------------------------------------

static func _cabin(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_screen_assembly(c, q)
	_seatbelt_placard(c, q)
	_ceiling_projector(c, q)
	_hat_racks_and_lighting(c, q)
	_window_accents(c, q)
	_aft_bulkhead(c, q)


## Pull-down bulkhead cinema screen assembly: brushed-aluminium top roller cassette, black velvet masking borders,
## weighted chrome bottom dowel bar with turned end finials and central chrome pull ring, plus forward bulkhead
## walnut trim & low flight-folder pockets flanking the aisle.
static func _screen_assembly(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(1.36, 0.765))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var sz := sc_xf.origin.z
	var w := sc_sz.x
	var h := sc_sz.y
	var hw := w * 0.5
	var hh := h * 0.5
	var fz := float(q["front_z"])
	var top_y := cy + hh
	var bot_y := cy - hh

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# Matte-black velvet masking backing & side borders sitting cleanly 8 mm behind the screen face (zero obstruction).
	s.surface(c.tinted("iron"))
	s.colour = VELVET_BLACK.srgb_to_linear()
	var mask_w := 0.045
	var mask_z := sz - 0.012
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * (hw + mask_w * 0.5), cy, mask_z), Vector3(mask_w, h + 0.06, 0.014))
	s.box(Vector3(cx, top_y + 0.015, mask_z), Vector3(w, 0.03, 0.014))
	s.box(Vector3(cx, bot_y - 0.015, mask_z), Vector3(w, 0.03, 0.014))
	# Slim matte-black sheet backing behind the pull-down canvas so no bulkhead light bleeds round edges.
	s.box(Vector3(cx, cy, sz - 0.022), Vector3(w + mask_w * 2.0, h + 0.06, 0.008))

	# Sleek brushed-aluminium top roller cassette bolted to the forward bulkhead, with chamfered end caps & brackets.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	var cas_w := w + 0.20
	var cas_y := top_y + 0.042
	var cas_z := sz - 0.014
	var basis_x := Basis(Vector3.BACK, PI * 0.5)
	Shapes.cylinder(u, Vector3(cx - cas_w * 0.5, cas_y, cas_z), 0.028, cas_w, 12, basis_x)
	# Upper hood lip and twin brushed-steel wall mounting brackets back into the bulkhead.
	u.box(Vector3(cx, cas_y + 0.018, (cas_z + fz) * 0.5), Vector3(cas_w + 0.02, 0.018, maxf(cas_z - fz + 0.02, 0.06)))
	for side: float in [-1.0, 1.0]:
		var ex := cx + side * (cas_w * 0.5 + 0.012)
		u.colour = ALU_DARK.srgb_to_linear()
		Shapes.cylinder(u, Vector3(ex - side * 0.012, cas_y, cas_z), 0.033, 0.022, 12, basis_x)
		u.box(Vector3(cx + side * (hw + 0.055), cas_y, (cas_z + fz) * 0.5),
				Vector3(0.032, 0.062, maxf(cas_z - fz, 0.06)))
		u.colour = ALU_BRUSH.srgb_to_linear()

	# Weighted brushed-chrome bottom tension dowel bar, turned finials, central clasp and pull ring.
	var bar_w := w + 0.14
	var bar_y := bot_y - 0.036
	Shapes.cylinder(u, Vector3(cx - bar_w * 0.5, bar_y, sz - 0.006), 0.014, bar_w, 10, basis_x)
	for side: float in [-1.0, 1.0]:
		u.colour = GOLD_TRIM.srgb_to_linear()
		Shapes.cylinder(u, Vector3(cx + side * (bar_w * 0.5), bar_y, sz - 0.006), 0.018, 0.024 * side, 10, basis_x)
	u.colour = ALU_BRUSH.srgb_to_linear()
	u.box(Vector3(cx, bar_y - 0.016, sz - 0.006), Vector3(0.026, 0.02, 0.016))
	Shapes.arch(u, Vector3(cx, bar_y - 0.046, sz - 0.006), 0.018, 0.028, 0.012, 16, Basis(), 0.0, TAU,
			["front", "back", "inner", "outer"])

	# Vertical brushed-aluminium mid-century bulkhead accent strips framing the screen cleanly down to the dado rail.
	var half_bulk := float(q["hw"])
	for side: float in [-1.0, 1.0]:
		var tx := cx + side * (hw + 0.24)
		u.box(Vector3(tx, 1.54, fz + 0.014), Vector3(0.022, 1.16, 0.018))
		# Continuous horizontal brushed-steel dado trim rail across the forward bulkhead under the screen.
		var px := cx + side * (half_bulk * 0.52)
		u.box(Vector3(px, 0.96, fz + 0.016), Vector3(half_bulk * 0.80, 0.026, 0.022))

	# Forward bulkhead cream-ivory & brushed-aluminium flight-folder literature pockets (crisp contrast against walnut).
	s.surface(c.tinted("plastic"))
	s.colour = RACK_SHELL.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var px := cx + side * 0.96
		var py := 0.62
		# Back panel, bottom shelf, front retaining wall & end caps of each bulkhead literature pocket.
		s.box(Vector3(px, py + 0.02, fz + 0.014), Vector3(0.56, 0.30, 0.016))
		s.box(Vector3(px, py - 0.12, fz + 0.044), Vector3(0.56, 0.024, 0.064))
		s.box(Vector3(px, py - 0.03, fz + 0.072), Vector3(0.56, 0.18, 0.016))
		for es: float in [-1.0, 1.0]:
			s.box(Vector3(px + es * 0.272, py - 0.03, fz + 0.044), Vector3(0.018, 0.18, 0.062))
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = ALU_BRUSH.srgb_to_linear()
		u.box(Vector3(px, py + 0.062, fz + 0.078), Vector3(0.57, 0.018, 0.018))
		u.box(Vector3(px, py + 0.168, fz + 0.024), Vector3(0.57, 0.014, 0.014))
		# Colourful 1960s geometric flight folders & safety leaflets tucked neatly inside each pocket.
		u.surface(c.soft("plastic", true))
		var folders := [[-0.16, 0.15, 0.24, TERRACOTTA], [0.01, 0.145, 0.27, TEAL_FOLDER],
				[0.16, 0.135, 0.22, MUSTARD_FOLDER]]
		for f: Array in folders:
			u.colour = (f[3] as Color).srgb_to_linear()
			u.box(Vector3(px + float(f[0]), py + 0.05, fz + 0.045), Vector3(float(f[1]), float(f[2]), 0.012))
			u.colour = IVORY_LINER.srgb_to_linear()
			u.box(Vector3(px + float(f[0]), py + 0.10, fz + 0.052), Vector3(float(f[1]) * 0.72, 0.036, 0.004))

	# Clean physics collision box enclosing the overhead screen roller cassette & bulkhead pockets (strictly inside cabin).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, cas_y, fz + 0.055), Vector3(cas_w + 0.04, 0.10, 0.09), Basis()))
	for side: float in [-1.0, 1.0]:
		c.shapes.append(PhysicsShapes.box(Vector3(cx + side * 0.96, 0.64, fz + 0.05),
				Vector3(0.58, 0.34, 0.085), Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Glowing backlit amber FASTEN SEATBELT / NO SMOKING icon placard centered high on the forward bulkhead above the
## screen roller cassette (pure geometric buckle & circle-slash icons, zero text, zero people).
static func _seatbelt_placard(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var fz := float(q["front_z"])
	var py := 2.33
	var pz := fz + 0.068
	var pw := 0.44
	var ph := 0.076

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	# Dark anodised placard housing with slim brushed-aluminium surround cleanly proud of the roller cassette.
	s.surface(c.tinted("iron"))
	s.colour = CHARCOAL.srgb_to_linear()
	s.box(Vector3(cx, py, pz), Vector3(pw, ph, 0.088))
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	u.box(Vector3(cx, py + ph * 0.5, pz + 0.012), Vector3(pw + 0.016, 0.011, 0.072))
	u.box(Vector3(cx, py - ph * 0.5, pz + 0.012), Vector3(pw + 0.016, 0.011, 0.072))
	u.box(Vector3(cx, py, pz + 0.045), Vector3(0.016, ph, 0.012))

	# Twin backlit amber translucent glass panels (`PieceWindows`, warm amber `window_colour`).
	var face_z := pz + 0.046
	var gw: Array = c.glows.get("window", [])
	for side: float in [-1.0, 1.0]:
		gw.append([Vector3(cx + side * 0.105, py, face_z), Vector3(0.088, 0.0, 0.0), Vector3(0.0, 0.026, 0.0),
				Vector3.BACK])
	c.glows["window"] = gw

	# Left panel: crisp dark geometric seatbelt buckle clasp silhouette (two horizontal straps + central rectangular buckle).
	u.surface(c.soft("plastic", true))
	u.colour = VELVET_BLACK.srgb_to_linear()
	var lx := cx - 0.105
	var iz := face_z + 0.004
	u.box(Vector3(lx - 0.046, py, iz), Vector3(0.052, 0.014, 0.004))
	u.box(Vector3(lx + 0.046, py, iz), Vector3(0.052, 0.014, 0.004))
	u.box(Vector3(lx, py, iz), Vector3(0.030, 0.028, 0.005))
	u.colour = Color(0.98, 0.74, 0.28).srgb_to_linear()
	u.box(Vector3(lx - 0.003, py, iz + 0.002), Vector3(0.010, 0.014, 0.003))

	# Right panel: crisp dark geometric no-smoking ring + diagonal slash over a tiny horizontal cylinder bar.
	var rx := cx + 0.105
	u.colour = VELVET_BLACK.srgb_to_linear()
	Shapes.arch(u, Vector3(rx, py, iz), 0.018, 0.024, 0.005, 16, Basis(), 0.0, TAU, ["front"])
	u.box(Vector3(rx, py, iz + 0.001), Vector3(0.040, 0.006, 0.004), Basis(Vector3.BACK, -0.78))
	u.box(Vector3(rx - 0.002, py - 0.002, iz), Vector3(0.026, 0.006, 0.004))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Ceiling-mounted 16 mm twin-reel inflight cinema projector bolted cleanly to the central arched ceiling spine above
## the aisle, centered inside Bay 2 (`x = cx`, `z = -0.96`, clear of all ceiling ribs): brushed-aluminium streamlined
## pod, cooling louvres, twin spoked 16 mm vertical film reels with wound dark film packs, film-gate guide rollers,
## canted dark lens barrel, and glowing lens aperture.
static func _ceiling_projector(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var crown_y := float(q["headroom"])
	var pz := -0.96
	var pod_y := crown_y - 0.185 # 2.245 m center; bottom ~2.14 m, well above every seat's sight line!

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# Streamlined brushed-aluminium ceiling mount plate, suspension collar and main 16 mm projector pod body.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	# Curved ceiling anchor fairing bolted flush into the crown spine.
	u.box(Vector3(cx, crown_y - 0.015, pz), Vector3(0.28, 0.032, 0.50))
	u.colour = ALU_DARK.srgb_to_linear()
	u.box(Vector3(cx, crown_y - 0.056, pz), Vector3(0.16, 0.055, 0.34))
	# Main 1964 brushed-aluminium cast projector body + sculpted mid-century upper lamphouse cowl.
	u.colour = ALU_BRUSH.srgb_to_linear()
	u.rounded_box(Vector3(cx, pod_y, pz), Vector3(0.23, 0.175, 0.44), 0.028, Transform3D(), 1)
	u.rounded_box(Vector3(cx, pod_y + 0.085, pz + 0.04), Vector3(0.17, 0.055, 0.24), 0.016, Transform3D(), 1)
	# Twin chrome mid-century speed-trim side strips along the projector body.
	u.colour = GOLD_TRIM.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.118, pod_y + 0.01, pz), Vector3(0.008, 0.016, 0.38))

	# Recessed dark-anodised cooling vent louvres on the port side and aft lamphouse end.
	s.surface(c.tinted("iron"))
	s.colour = CHARCOAL.srgb_to_linear()
	for k in 5:
		var vz := pz - 0.10 + 0.05 * k
		s.box(Vector3(cx - 0.118, pod_y - 0.02, vz), Vector3(0.01, 0.075, 0.018))
	s.box(Vector3(cx, pod_y, pz + 0.222), Vector3(0.15, 0.10, 0.012))

	# Twin 16 mm spoked metal film reels mounted in tandem on the starboard (+X, aisle/viewer-facing) side of the pod!
	# Forward feed reel at z = -0.77 and aft take-up reel at z = -0.33, radius 0.108 m (bottom y = 2.14, top y = 2.36).
	var reel_x := cx + 0.148
	var reel_y := pod_y + 0.01
	var reel_r := 0.108
	var reel_basis := Basis(Vector3.UP, PI * 0.5) # arch in local XY -> world ZY plane; depth along X!
	var spindle_basis := Basis(Vector3.BACK, PI * 0.5) # cylinder axis along X!
	for rz: float in [pz - 0.21, pz + 0.21]:
		# Brushed-aluminium reel support arm & central spindle hub.
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = ALU_DARK.srgb_to_linear()
		u.box(Vector3(cx + 0.115, reel_y, (rz + pz) * 0.5), Vector3(0.032, 0.038, absf(rz - pz) + 0.04))
		Shapes.cylinder(u, Vector3(cx + 0.11, reel_y, rz), 0.018, 0.068, 10, spindle_basis)
		# Inner and outer brushed-aluminium 16 mm spoked reel flanges (outer rim + 4 radial spokes + hub ring).
		u.colour = ALU_BRUSH.srgb_to_linear()
		for dx: float in [-0.016, 0.016]:
			Shapes.arch(u, Vector3(reel_x + dx, reel_y, rz), reel_r - 0.014, reel_r, 0.005, 18, reel_basis, 0.0, TAU,
					["front", "back", "inner", "outer"])
			Shapes.arch(u, Vector3(reel_x + dx, reel_y, rz), 0.018, 0.032, 0.005, 12, reel_basis, 0.0, TAU,
					["front", "back"])
			for sp in 4:
				var ang := PI * 0.25 + PI * 0.5 * sp
				u.box(Vector3(reel_x + dx, reel_y, rz), Vector3(0.004, 0.014, reel_r * 1.88),
						Basis(Vector3.RIGHT, ang))
		# Dark wound 16 mm celluloid film pack nested neatly between the two metallic reel flanges.
		u.surface(c.soft("plastic", true))
		u.colour = FILM_PACK.srgb_to_linear()
		Shapes.cylinder(u, Vector3(reel_x - 0.013, reel_y, rz), reel_r * 0.78, 0.026, 16, spindle_basis)

	# Chrome 16 mm gate rollers and dark film strip threading between the two reels.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	for gz: float in [pz - 0.075, pz + 0.075]:
		Shapes.cylinder(u, Vector3(cx + 0.115, pod_y - 0.045, gz), 0.012, 0.045, 8, spindle_basis)
	u.surface(c.soft("plastic", true))
	u.colour = FILM_PACK.srgb_to_linear()
	u.box(Vector3(reel_x, pod_y - 0.056, pz), Vector3(0.016, 0.004, 0.34))

	# Forward-projecting dark-anodised telephoto lens barrel aimed cleanly at the pull-down bulkhead screen (-7 deg).
	var lens_pitch := deg_to_rad(-6.8)
	var lens_basis := Basis(Vector3.RIGHT, lens_pitch) * Basis(Vector3.RIGHT, -PI * 0.5)
	var lens_base := Vector3(cx, pod_y - 0.025, pz - 0.21)
	u.surface(c.soft("plastic", true))
	u.colour = CHARCOAL.srgb_to_linear()
	Shapes.cylinder(u, lens_base, 0.044, 0.065, 14, lens_basis)
	Shapes.cylinder(u, lens_base + Vector3(0.0, -0.008, -0.06), 0.036, 0.072, 14, lens_basis)
	# Brushed-chrome focus knurling ring around the lens front.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	Shapes.cylinder(u, lens_base + Vector3(0.0, -0.014, -0.105), 0.039, 0.018, 14, lens_basis)

	# Glowing 16 mm projector lens aperture (`PiecePort`, warm radial booth-lens glow texture, aimed straight forward!).
	var lens_tip := Vector3(cx, pod_y - 0.043, pz - 0.345)
	var gp: Array = c.glows.get("port", [])
	gp.append([lens_tip, Vector3(0.030, 0.0, 0.0), Vector3(0.0, 0.030, 0.0), Vector3.FORWARD])
	c.glows["port"] = gp

	# Single clean physics collision box enclosing the ceiling projector pod & reels (x in [-0.90, -0.455] -> > 0.45 m
	# horizontally from viewer at origin, strictly inside cabin AABB).
	c.shapes.append(PhysicsShapes.box(Vector3(cx + 0.02, crown_y - 0.155, pz), Vector3(0.38, 0.29, 0.72), Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## 1960s open cantilevered overhead hat-racks curving along both leaning walls above the six oval windows, continuous
## brushed-aluminium guardrails, recessed passenger service units, continuous indirect mood cove strips (`PieceCove`),
## and four recessed overhead fluorescent cabin ceiling valance panels (`PieceLamps`, house group).
static func _hat_racks_and_lighting(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var lean := float(q["L"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var crown_y := float(q["headroom"])
	var rack_z0 := fz + 0.42
	var rack_z1 := bz - 0.38
	var rack_len := rack_z1 - rack_z0
	var rack_mid := (rack_z0 + rack_z1) * 0.5
	var rack_y := 1.66 # 12 cm cleanly above window tops (1.12 + 0.42 = 1.54)

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	var wall_at_rack := hw - rack_y * tan(lean) # ~1.617 m from cx
	var shelf_w := 0.42
	var inner_off := wall_at_rack - shelf_w # ~1.197 m from cx

	# Open cantilevered cream-ivory overhead hat-rack shelves with upturned aisle lips & walnut underside accent trim.
	s.surface(c.tinted("plastic"))
	s.colour = RACK_SHELL.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var sx := cx + side * (wall_at_rack - shelf_w * 0.5)
		var lip_x := cx + side * (inner_off + 0.02)
		# Main horizontal shelf slab + sculpted angled outer fascia & upturned luggage-retaining lip.
		s.box(Vector3(sx, rack_y, rack_mid), Vector3(shelf_w, 0.036, rack_len))
		s.box(Vector3(lip_x, rack_y + 0.048, rack_mid), Vector3(0.042, 0.095, rack_len))
		# Streamlined tapered end bulkheads closing each hat-rack cleanly at fore & aft ends.
		for ez: float in [rack_z0, rack_z1]:
			s.box(Vector3(sx, rack_y + 0.055, ez), Vector3(shelf_w, 0.14, 0.03))
		# Recessed underside passenger service unit (PSU) panels above each seat row (z = -1.35, 0.0, +1.35).
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = ALU_BRUSH.srgb_to_linear()
		# Continuous brushed-aluminium luggage guardrail tube running above the hat-rack lip.
		var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
		Shapes.cylinder(u, Vector3(lip_x - side * 0.008, rack_y + 0.135, rack_z0 + 0.04), 0.011, rack_len - 0.08, 8,
				basis_z)
		for k in 7:
			var post_z := lerpf(rack_z0 + 0.2, rack_z1 - 0.2, float(k) / 6.0)
			u.box(Vector3(lip_x - side * 0.008, rack_y + 0.105, post_z), Vector3(0.014, 0.06, 0.014))
		# Brushed-aluminium trim bead along the bottom-inner hat-rack edge.
		u.box(Vector3(lip_x - side * 0.012, rack_y - 0.016, rack_mid), Vector3(0.02, 0.016, rack_len))
		# PSU panels + individual dark air-nozzle & reading-lamp eyeball vents over each row.
		for rz: float in [-1.35, 0.0, 1.35]:
			var psu_x := cx + side * (inner_off + 0.14)
			u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
			u.colour = ALU_BRUSH.srgb_to_linear()
			u.box(Vector3(psu_x, rack_y - 0.022, rz), Vector3(0.18, 0.012, 0.28))
			u.surface(c.soft("plastic", true))
			u.colour = CHARCOAL.srgb_to_linear()
			for dz: float in [-0.07, 0.07]:
				Shapes.cylinder(u, Vector3(psu_x, rack_y - 0.036, rz + dz), 0.018, 0.016, 8)
		# Physics box for each hat-rack (well above eye height and > 1.19 m from cx, far clear of viewer origin).
		c.shapes.append(PhysicsShapes.box(Vector3(sx, rack_y + 0.04, rack_mid),
				Vector3(shelf_w, 0.14, rack_len), Basis()))

	# Continuous indirect cabin cove light strips tucked along BOTH overhead hat-racks (upper indirect ceiling-wash
	# cove + soft under-rack window-valance graze strip, live-controlled by `Cabin mood` setting, `cove_floor` 0.45).
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.98, 0.96, 0.92).srgb_to_linear()
	cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.96)
	for side: float in [-1.0, 1.0]:
		# Upper cove light strip nested inside the upturned hat-rack lip washing the cream arched ceiling.
		var ux_in := cx + side * (inner_off + 0.05)
		var ux_out := cx + side * (inner_off + 0.15)
		var uy := rack_y + 0.024
		var p0 := Vector3(ux_in, uy, rack_z0 + 0.12)
		var p1 := Vector3(ux_out, uy, rack_z0 + 0.12)
		var p2 := Vector3(ux_out, uy, rack_z1 - 0.12)
		var p3 := Vector3(ux_in, uy, rack_z1 - 0.12)
		if side > 0.0:
			cove.face([p0, p1, p2, p3], Vector3.UP)
		else:
			cove.face([p1, p0, p3, p2], Vector3.UP)
		# Lower downward-facing subtle strip tucked beneath the outer wall join of the hat-rack above the windows.
		var lx_in := cx + side * (wall_at_rack - 0.11)
		var lx_out := cx + side * (wall_at_rack - 0.02)
		var ly := rack_y - 0.022
		var q0 := Vector3(lx_in, ly, rack_z0 + 0.12)
		var q1 := Vector3(lx_out, ly, rack_z0 + 0.12)
		var q2 := Vector3(lx_out, ly, rack_z1 - 0.12)
		var q3 := Vector3(lx_in, ly, rack_z1 - 0.12)
		if side < 0.0:
			cove.face([q0, q1, q2, q3], Vector3.DOWN)
		else:
			cove.face([q1, q0, q3, q2], Vector3.DOWN)
	cove.colour = Color.WHITE

	# Longitudinal cream-ivory ceiling spine strips & four recessed overhead fluorescent cabin valance diffuser panels
	# (`PieceLamps`, house group) cleanly split fore and aft of the 16 mm ceiling projector at z = -0.55.
	s.surface(c.tinted("plastic"))
	s.colour = IVORY_LINER.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var rx := cx + side * 0.24
		var ry := _roof_y(q, rx) - 0.015
		s.box(Vector3(rx, ry, (fz + bz) * 0.5), Vector3(0.036, 0.024, bz - fz - 0.12))

	lit.surface(c.shade(CABIN_LAMP))
	# Five ceiling valance panels aligned dead center in Bays 0, 1, 3, 4 and 5 (clear of every ceiling rib and of the
	# 16 mm projector centered in Bay 2 at z = -0.96).
	var panel_zs := [-2.88, -1.92, 0.0, 0.96, 1.92]
	var panel_y := crown_y - 0.018
	for i in panel_zs.size():
		var pz: float = panel_zs[i]
		# Brushed-aluminium recessed ceiling valance frame & fine transverse acrylic diffuser ribs.
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = ALU_BRUSH.srgb_to_linear()
		u.box(Vector3(cx, panel_y + 0.008, pz), Vector3(0.30, 0.018, 0.72))
		for k in 5:
			var lz := pz - 0.24 + 0.12 * k
			u.box(Vector3(cx, panel_y - 0.006, lz), Vector3(0.25, 0.009, 0.011))
		# Warm frosted acrylic glowing face pointing straight down along the aisle.
		lit.face([Vector3(cx - 0.125, panel_y - 0.004, pz - 0.32), Vector3(cx + 0.125, panel_y - 0.004, pz - 0.32),
				Vector3(cx + 0.125, panel_y - 0.004, pz + 0.32), Vector3(cx - 0.125, panel_y - 0.004, pz + 0.32)],
				Vector3.DOWN)
		if i == 1 or i == 3:
			c.lamps.append([Vector3(cx, panel_y - 0.18, pz), CABIN_LAMP, 0.92])
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Subtle brushed-chrome window-shade pull tabs tucked into the upper reveals of the 12 oval fuselage windows, plus
## slim horizontal dado brightwork rails cleanly hugging the leaning fuselage walls.
static func _window_accents(c: Object, q: Dictionary) -> void:
	var lean := float(q["L"])
	var sill := float(q["window_sill"])
	var wh := float(q["window_height"])
	var vt := (sill + wh - 0.025) / cos(lean)
	var wzs: Array = q["window_zs"]
	if wzs.is_empty():
		return
	var u: RoomMesh = c.u
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	for side: float in q["window_sides_s"]:
		var basis := Cabin._wall_basis(q, side)
		var n := Cabin._n(q, side)
		for wz: float in wzs:
			# Crisp tucked shade-rail bar & pull tab at the top of each oval window reveal (never blocks view).
			var p := Cabin._pt(q, side, wz, vt) - n * 0.025
			u.box(p, Vector3(0.14, 0.016, 0.018), basis)
			u.box(p + n * 0.012 - Cabin._up(q, side) * 0.008, Vector3(0.042, 0.01, 0.01), basis)
	u.colour = Color.WHITE


## Aft galley bulkhead (`back_z`): brushed-steel door furniture & vertical trim, pleated mid-century burnt-orange
## galley curtain valance & tie-backs framing the aft doorway, working sleek 1964 cabin clock (`PieceClock`), tiered
## walnut magazine pocket with colourful flight folders, and a geometric polar great-circle route plaque.
static func _aft_bulkhead(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis_aft := Basis(Vector3.UP, PI)

	# Brushed-steel galley door kick-plate, tubular pull handle and vertical bulkhead architectural strips.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	u.box(Vector3(cx, 0.15, bz - 0.026), Vector3(0.58, 0.28, 0.01))
	Shapes.cylinder(u, Vector3(cx - 0.22, 0.88, bz - 0.056), 0.011, 0.24, 8)
	for dy: float in [0.90, 1.10]:
		u.box(Vector3(cx - 0.22, dy, bz - 0.038), Vector3(0.02, 0.02, 0.036))
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.50, 1.0, bz - 0.014), Vector3(0.022, 1.96, 0.018))
		u.box(Vector3(cx + side * 1.12, 0.96, bz - 0.014), Vector3(1.06, 0.024, 0.018))

	# Pleated mid-century burnt-orange galley curtain valance & draped side tie-backs framing the aft doorway.
	s.surface(c.tinted("wood"))
	s.colour = WALNUT.srgb_to_linear()
	s.box(Vector3(cx, 1.94, bz - 0.055), Vector3(0.92, 0.10, 0.09))
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = GOLD_TRIM.srgb_to_linear()
	u.box(Vector3(cx, 1.895, bz - 0.102), Vector3(0.93, 0.014, 0.012))

	u.surface(c.soft("cloth", true))
	u.colour = CURTAIN_GOLD.srgb_to_linear()
	# Pleated top curtain valance header strip in glamorous 1964 champagne-gold weave.
	for k in 9:
		var vx := cx - 0.40 + 0.10 * k
		var dz := 0.016 if k % 2 == 0 else 0.0
		u.rounded_box(Vector3(vx, 1.835, bz - 0.062 - dz), Vector3(0.095, 0.15, 0.036), 0.012, Transform3D(), 1)
	# Twin gathered pleated side curtain panels flanking the aft doorway (clear of the glowing door pane!).
	for side: float in [-1.0, 1.0]:
		for fold in 3:
			var fx := cx + side * (0.34 + 0.056 * fold)
			var fz_off := 0.018 if fold % 2 == 0 else 0.0
			u.rounded_box(Vector3(fx, 0.98, bz - 0.052 - fz_off), Vector3(0.058, 1.72, 0.040), 0.015, Transform3D(), 1)
		# Burnt-terracotta woven tie-back sash cinching each champagne-gold side drape at waist height.
		u.colour = TERRACOTTA.srgb_to_linear()
		u.box(Vector3(cx + side * 0.39, 0.96, bz - 0.075), Vector3(0.18, 0.038, 0.026))
		u.colour = CURTAIN_GOLD.srgb_to_linear()

	# Working sleek 1964 brushed-aluminium & gold starburst cabin clock centered above the galley valance (`PieceClock`).
	var clk_y := 2.21
	var clk_r := 0.145
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, clk_y, bz - 0.038), clk_r, clk_r + 0.026, 0.045, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Twelve delicate 1960s mid-century gold sunburst rays radiating round the clock bezel.
	u.colour = GOLD_TRIM.srgb_to_linear()
	for k in 12:
		var a := TAU * float(k) / 12.0
		var ray_len := 0.048 if k % 3 == 0 else 0.030
		var rc := Vector3(cx + cos(a) * (clk_r + 0.026 + ray_len * 0.5),
				clk_y + sin(a) * (clk_r + 0.026 + ray_len * 0.5), bz - 0.025)
		u.box(rc, Vector3(ray_len, 0.009, 0.012), Basis(Vector3.BACK, a))
	c.clocks.append([Vector3(cx, clk_y, bz - 0.052), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# Port aft bulkhead: tiered walnut & brushed-steel magazine pocket stocked with colourful mid-century flight folders.
	var mx := cx - 1.04
	var my := 1.18
	s.surface(c.tinted("wood"))
	s.colour = WALNUT.srgb_to_linear()
	s.box(Vector3(mx, my, bz - 0.022), Vector3(0.64, 0.56, 0.028))
	s.box(Vector3(mx, my - 0.14, bz - 0.052), Vector3(0.60, 0.22, 0.054))
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	u.box(Vector3(mx, my - 0.028, bz - 0.082), Vector3(0.62, 0.016, 0.016))
	u.box(Vector3(mx, my + 0.12, bz - 0.068), Vector3(0.62, 0.014, 0.014))
	u.surface(c.soft("plastic", true))
	var aft_folders := [[-0.19, 0.16, 0.25, TERRACOTTA, -0.06], [0.0, 0.17, 0.27, TEAL_FOLDER, -0.05],
			[0.19, 0.15, 0.24, MUSTARD_FOLDER, -0.06], [-0.11, 0.16, 0.24, IVORY_LINER, 0.12],
			[0.11, 0.16, 0.25, TERRACOTTA, 0.12]]
	for f: Array in aft_folders:
		u.colour = (f[3] as Color).srgb_to_linear()
		u.box(Vector3(mx + float(f[0]), my + float(f[4]), bz - 0.048), Vector3(float(f[1]), float(f[2]), 0.012))
	c.shapes.append(PhysicsShapes.box(Vector3(mx, my, bz - 0.055), Vector3(0.64, 0.58, 0.09), Basis()))

	# Starboard aft bulkhead: mid-century framed geometric polar great-circle route plaque (pure geometry, zero text).
	var px := cx + 1.04
	var py := 1.34
	s.surface(c.tinted("wood"))
	s.colour = WALNUT.srgb_to_linear()
	s.box(Vector3(px, py, bz - 0.02), Vector3(0.62, 0.44, 0.03))
	u.surface(c.soft("plastic", true))
	u.colour = NAVY_PLAQUE.srgb_to_linear()
	u.box(Vector3(px, py, bz - 0.036), Vector3(0.54, 0.36, 0.008))
	# Concentric brushed-aluminium polar latitude rings + gleaming gold transpolar great-circle arc.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	Shapes.arch(u, Vector3(px, py, bz - 0.042), 0.065, 0.072, 0.006, 20, basis_aft, 0.0, TAU, ["front"])
	Shapes.arch(u, Vector3(px, py, bz - 0.042), 0.125, 0.132, 0.006, 24, basis_aft, 0.0, TAU, ["front"])
	u.colour = GOLD_TRIM.srgb_to_linear()
	Shapes.arch(u, Vector3(px, py - 0.08, bz - 0.044), 0.145, 0.156, 0.007, 16, basis_aft, 0.45, PI - 0.45, ["front"])
	u.box(Vector3(px, py, bz - 0.044), Vector3(0.018, 0.018, 0.007))
	c.shapes.append(PhysicsShapes.box(Vector3(px, py, bz - 0.036), Vector3(0.62, 0.44, 0.05), Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


# --- The 1964 first-class recliner rows' hardware ---------------------------------------------------------------------

## Chunky 1964 moulded charcoal & brushed-chrome armrests (retaining both armrests round the viewer's folded seat, with
## slimmed outboard armrests tucked cleanly inside the 8 deg leaning fuselage wall) featuring dual-hole pneumatic
## air-tube headset jacks and channel dials, crisp woven ivory headrest antimacassars hugging the curved `recliner`
## profile, flush curved flip-up laminate tray tables, and soft aisle carpet-edge guide strips (`PieceCove`).
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

	# Collect unique armrest placements per row block; identify aisle-side and outboard window-side armrests.
	var arm_entries := {}
	var aisle_arms: Array = []
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		var o := xf.origin
		var row_key := roundi(o.z * 100.0)
		for side: float in [-1.0, 1.0]:
			var raw_x := o.x + side * pitch * 0.5
			var k := "%d:%d" % [row_key, roundi(raw_x * 100.0)]
			if not arm_entries.has(k):
				var from_cx := raw_x - cx
				var outboard := absf(from_cx) > 1.50
				# Outboard window armrests narrow cleanly to 9.5 cm and tuck 2.4 cm inward to clear the 8 deg wall!
				var w := 0.095 if outboard else arm_w
				var ax := (cx + signf(from_cx) * 1.696) if outboard else raw_x
				arm_entries[k] = [Vector3(ax, o.y, o.z), w, outboard]
				if absf(ax - cx) < float(q["aisle"]) * 0.5 + 0.12:
					aisle_arms.append([Vector3(ax, o.y, o.z), -1.0 if ax > cx else 1.0, w])

	# Moulded 1964 charcoal armrest bodies, contoured dark caps, and recessed dual acoustic headset port holes.
	u.surface(c.soft("plastic", true))
	for entry: Array in arm_entries.values():
		var at: Vector3 = entry[0]
		var w := float(entry[1])
		u.colour = CHARCOAL.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h * 0.5, arm_z), Vector3(w, arm_h, arm_d), Basis(), [RoomMesh.DOWN])
		u.colour = ARM_CAP.srgb_to_linear()
		u.rounded_box(at + Vector3(0.0, arm_h + 0.018, arm_z - 0.008), Vector3(w + 0.01, 0.036, arm_d + 0.016),
				0.012, Transform3D(), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		# Two tiny dark pneumatic air-tube headset acoustic jack holes sitting proud of the chrome jack plate.
		u.colour = VELVET_BLACK.srgb_to_linear()
		var jz := at.z + arm_z - arm_d * 0.30
		for hx: float in [-0.014, 0.014]:
			Shapes.cylinder(u, Vector3(at.x + hx, arm_h + 0.038, jz), 0.0065, 0.005, 8)

	# Brushed-chrome armrest front trim bars, dual-hole pneumatic headset jack plates, channel dials & recline buttons.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	for entry: Array in arm_entries.values():
		var at: Vector3 = entry[0]
		var w := float(entry[1])
		var jz := at.z + arm_z - arm_d * 0.30
		u.colour = ALU_BRUSH.srgb_to_linear()
		# Sleek brushed-aluminium front nose strip & side reveal accents.
		u.box(at + Vector3(0.0, arm_h * 0.52, arm_z - arm_d * 0.5 - 0.004), Vector3(w - 0.014, arm_h * 0.78, 0.008))
		# Classic 1964 dual-hole pneumatic air-tube headset jack plate recessed on top of each armrest.
		u.box(Vector3(at.x, arm_h + 0.037, jz), Vector3(minf(w - 0.022, 0.064), 0.005, 0.044))
		# Knurled chrome inflight audio channel selector dial + small round silver recline button behind the jack.
		Shapes.cylinder(u, Vector3(at.x, arm_h + 0.036, jz + 0.056), 0.015, 0.012, 10)
		u.colour = GOLD_TRIM.srgb_to_linear()
		Shapes.cylinder(u, Vector3(at.x, arm_h + 0.046, jz + 0.056), 0.009, 0.004, 10)
		u.colour = ALU_BRUSH.srgb_to_linear()
		u.box(Vector3(at.x, arm_h + 0.038, jz + 0.105), Vector3(0.024, 0.009, 0.024))

	# Crisp woven ivory linen antimacassars hugging every recliner's curved headrest (`bend -0.35`, `radius 0.06`),
	# skipping the viewer's own folded seat at the origin.
	var wi := pitch - arm_w - 0.01
	u.surface(c.soft("cloth", true))
	u.colour = LINEN_IVORY.srgb_to_linear()
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.rounded_box(Vector3(0.0, 0.655, -0.008), Vector3(wi - 0.13, 0.235, 0.148), 0.06, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])

	# Flush curved flip-up warm-almond laminate seatback tray tables (`bend -0.35`) + solid warm sandstone-taupe inner
	# shell front-closure panel behind each recliner headrest (closing the open front of `seats.gd _recliner`'s taller
	# outer shell cleanly from every front & side angle) with chrome latches & pivot bars.
	u.surface(c.soft("plastic", true))
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.colour = SHELL_TAUPE.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.41, 0.070), Vector3(wi + 0.008, 0.82, 0.034), 0.016, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])
		u.colour = TRAY_ALMOND.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.34, 0.126), Vector3(wi - 0.085, 0.28, 0.018), 0.008, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.FRONT])
		u.colour = ARM_CAP.srgb_to_linear()
		u.box(t_world * Vector3(0.0, 0.19, 0.124), Vector3(wi - 0.095, 0.02, 0.018), t_world.basis)
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = ALU_BRUSH.srgb_to_linear()
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.box(t_world * Vector3(0.0, 0.498, 0.129), Vector3(0.048, 0.022, 0.016), t_world.basis)

	# Soft aisle carpet-edge guide light strips along the aisle-facing base of the aisle armrests (`PieceCove`).
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.98, 0.96, 0.92).srgb_to_linear()
	cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.96)
	for entry: Array in aisle_arms:
		var at: Vector3 = entry[0]
		var inward := float(entry[1])
		var w := float(entry[2])
		var x := at.x + inward * (w * 0.5 + 0.005)
		var z0 := at.z + arm_z - arm_d * 0.44
		var z1 := at.z + arm_z + arm_d * 0.44
		var n := Vector3(inward, 0.0, 0.0)
		var p0 := Vector3(x, 0.036, z0)
		var p1 := Vector3(x, 0.036, z1)
		var p2 := Vector3(x, 0.082, z1)
		var p3 := Vector3(x, 0.082, z0)
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
