extends RefCounted

## Mars train (app/environments/mars_train.env.json; docs/environments/rooms/mars_train.md): a rugged, warm-lit
## pressurised Martian rover-train rolling across a rust-ochre plain under the real haunting blue Martian sunset, past
## distant whirling dust devils and basalt mesas, arriving at a glowing domed Martian night colony. Dressed over an
## inward-leaning `cabin` pressure hull and `seats` (`recliner`) rows.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, arches and lathed shapes; no
## people, no real trademarks, no agency insignia or text.
##
##   marstrain_cabin  the pressurised rover-train cabin's aerospace expedition craft:
##                    - heavy chamfered aerospace-aluminium ring-frames with machined webs, bolted shoulder gusset
##                      flanges, and hex bolt bosses reinforcing every leaning hull bay and arched roof hoop
##                    - thick triple-glazed pressure-window inner bezel collars, chamfered sill trays, recessed
##                      under-sill thermal radiator louvres, and brushed-aluminium pier grab-bars
##                    - overhead pressurised oxygen (teal-banded) and thermal-coolant (terracotta-banded) conduit
##                      pipes clamped across the ring-frames, flanking recessed warm expedition LED ceiling light
##                      troughs (`PieceLamps`, `bake_lamps: 2`) and live indirect architectural cove strips
##                      (`PieceCove`, `cove_floor: 0.45`, Habitat amber / Telemetry teal / Off)
##                    - rugged forward cinema bulkhead framing the screen with chamfered titanium surround, recessed
##                      charcoal mask bezel, lower instrumentation console, twin backlit telemetry status displays
##                      (`PieceWindows`), and overhead pressure-seal indicator header bar
##                    - aft side expedition lockers tucked cleanly behind the rear windows: starboard geological
##                      sample rack holding four glass-sleeved Martian regolith core canisters (`PieceGlass`), and
##                      port pressure-manifold cabinet crowned by a framed topographic Martian geology & traverse map
##                      plaque (pure geometry, zero text)
##                    - iconic aft circular pressure airlock hatch framed by bold yellow-and-charcoal hazard striping,
##                      heavy bolted coaming ring, 4-spoke brushed-aluminium dogging wheel, glowing airlock
##                      pressure-green viewport & seal status bars (`PieceWindows`), vertical entry grab-bars, and a
##                      working Martian Sol chronometer (`PieceClock`) centered above the hatch
##   marstrain_rows   the technical expedition recliner rows' hardware round `seats` (`recliner`):
##                    - faceted slate & brushed-aluminium shared armrests (`Seats.RECLINER_ARM`, both kept around the
##                      viewer's folded seat; outboard window armrests slimmed and tucked cleanly inside the 8.5 deg
##                      leaning pressure hull) with forearm control pods, indicator pips and titanium recline levers
##                    - tailored warm-sand woven technical headrest wraps hugging `seats.gd _recliner`'s exact curve
##                      (`bend = -0.35`, `radius = 0.062`) cleanly proud of the upholstery
##                    - solid slate rear seatback shell closures, tubular brushed-aluminium overhead seatback grab-bar
##                      handles for steady passage over Martian regolith, and rear cargo stowage straps
##                    - recessed low aisle deck-guide light strips (`PieceCove`) along the aisle-facing armrest bases

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")

const PIECES: Array[String] = ["marstrain_cabin", "marstrain_rows"]

## Palette (sRGB): machined aerospace aluminium, dark pressure-hull slate, Martian terracotta, hazard yellow, sand.
const ALU_BRIGHT := Color(0.80, 0.82, 0.85)
const ALU_MID := Color(0.56, 0.59, 0.63)
const ALU_DARK := Color(0.32, 0.35, 0.39)
const SLATE_HULL := Color(0.20, 0.22, 0.25)
const SLATE_DARK := Color(0.11, 0.125, 0.145)
const MASK_BLACK := Color(0.045, 0.048, 0.055)
const TITANIUM_SAND := Color(0.76, 0.72, 0.66)
const HEADREST_SAND := Color(0.84, 0.79, 0.72)
const TERRACOTTA := Color(0.72, 0.30, 0.16)
const RUST_CORE := Color(0.58, 0.24, 0.14)
const BASALT_CORE := Color(0.24, 0.19, 0.17)
const O2_TEAL := Color(0.16, 0.56, 0.60)
const HAZARD_YELLOW := Color(0.90, 0.66, 0.12)
const LED_WARM := Color(1.0, 0.86, 0.64)
const TELEM_AMBER := Color(1.0, 0.62, 0.20)
const MAP_OCHRE := Color(0.68, 0.34, 0.18)
const MAP_DARK := Color(0.14, 0.11, 0.10)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"marstrain_cabin":
			_cabin(c)
		"marstrain_rows":
			_rows(c)


# --- The pressurised Mars rover-train cabin ---------------------------------------------------------------------------

static func _cabin(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_pressure_frames(c, q)
	_window_sills_and_grabs(c, q)
	_overhead_conduits_and_lighting(c, q)
	_forward_bulkhead(c, q)
	_side_lockers_and_geology(c, q)
	_aft_airlock_bulkhead(c, q)


## Heavy chamfered aerospace-aluminium ring-frames with machined inner flange caps, bolted shoulder gusset brackets
## and hex bolt bosses at every structural bay mark along both leaning side walls and across the arched roof.
static func _pressure_frames(c: Object, q: Dictionary) -> void:
	var marks: Array[float] = Cabin._bay_marks(q)
	if marks.is_empty():
		return
	var lean := float(q["L"])
	var wall_len := float(q["wall_len"])
	var dado_v := float(q["dado"]) / cos(lean)
	var roof: Array = Cabin._roof(q)
	var rpts: PackedVector2Array = roof[0]
	var rns: PackedVector2Array = roof[1]
	var rd := float(q["rib_depth"])
	var rw := float(q["rib_width"])

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# 1. Lower dado structural stanchion webs anchoring every pressure ring-frame right down to the hex-paver floor.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_HULL.srgb_to_linear()
	for mz: float in marks:
		for side: float in [-1.0, 1.0]:
			var basis := Cabin._wall_basis(q, side)
			var n := Cabin._n(q, side)
			s.box(Cabin._pt(q, side, mz, dado_v * 0.5) + n * (rd * 0.65),
					Vector3(rw + 0.04, dado_v, rd * 1.3), basis, [RoomMesh.FRONT])

	# 2. Chamfered brushed-aluminium inner ring-frame flange caps, angled shoulder gusset brackets & hex bolt bosses.
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	for mz: float in marks:
		u.colour = ALU_BRIGHT.srgb_to_linear()
		# Continuous inner flange cap strip sweeping smoothly across the arched roof rib (cleanly > 2.55 m at crown).
		var fa := PackedVector3Array()
		var fb := PackedVector3Array()
		var fn := PackedVector3Array()
		for i in rpts.size():
			var p := rpts[i] + rns[i] * (rd + 0.022)
			fa.append(Vector3(p.x, p.y, mz - rw * 0.68))
			fb.append(Vector3(p.x, p.y, mz + rw * 0.68))
			fn.append(Vector3(rns[i].x, rns[i].y, 0.0))
		u.strip(fa, fb, fn)
		# Bolted wall-rib flange face strips, shoulder knee gussets and industrial bolt-heads up both leaning walls.
		for side: float in [-1.0, 1.0]:
			var basis := Cabin._wall_basis(q, side)
			var n := Cabin._n(q, side)
			var up := Cabin._up(q, side)
			# Proud machined inner flange bar running floor-to-shoulder on each structural rib.
			u.colour = ALU_BRIGHT.srgb_to_linear()
			u.box(Cabin._pt(q, side, mz, wall_len * 0.5) + n * (rd + 0.016),
					Vector3(rw + 0.028, wall_len - 0.04, 0.024), basis, [RoomMesh.FRONT])
			# Heavy chamfered shoulder gusset bracket where the leaning wall meets the arched roof hoop.
			var sh_p := Cabin._pt(q, side, mz, wall_len - 0.11) + n * (rd + 0.052)
			u.colour = ALU_MID.srgb_to_linear()
			u.box(sh_p, Vector3(rw + 0.045, 0.22, 0.095), basis)
			# Four machined bolt bosses along each shoulder gusset and base anchor plate.
			u.colour = ALU_DARK.srgb_to_linear()
			for dv: float in [0.16, dado_v - 0.08, wall_len - 0.18, wall_len - 0.06]:
				var bp := Cabin._pt(q, side, mz, dv) + n * (rd + 0.032)
				for dz: float in [-0.028, 0.028]:
					u.box(bp + Vector3(0.0, 0.0, dz), Vector3(0.016, 0.016, 0.012), basis)
			# Heavy base floor-anchor gusset shoe tying each ring-frame into the hex-paver floor deck.
			u.colour = ALU_MID.srgb_to_linear()
			var foot := Cabin._pt(q, side, mz, 0.06) + n * 0.065
			u.box(foot, Vector3(rw + 0.08, 0.12, 0.12), basis, [RoomMesh.DOWN, RoomMesh.FRONT])
			# Subtle diagonal chamfered knee strut under the roof shoulder.
			var k0 := Cabin._pt(q, side, mz, wall_len - 0.24) + n * (rd + 0.02)
			var k1 := rpts[1 if side < 0.0 else rpts.size() - 2] + rns[1 if side < 0.0 else rns.size() - 2] * (rd + 0.02)
			Shapes.beam(u, k0, Vector3(k1.x, k1.y, mz), Vector2(0.042, 0.034), up)
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Continuous brushed-aluminium pressure-window sill ledges, heavy under-sill thermal radiator vents, inner viewport
## clamp lugs around the thick 0.18 m triple-glazed reveals, and vertical brushed-steel pier grab-bars.
static func _window_sills_and_grabs(c: Object, q: Dictionary) -> void:
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var lean := float(q["L"])
	var sill := float(q["window_sill"])
	var wh := float(q["window_height"])
	var ww := float(q["window_width"])
	var wzs: Array = q["window_zs"]
	var marks: Array[float] = Cabin._bay_marks(q)
	if wzs.is_empty():
		return

	var z0 := fz + 0.34
	var z1 := bz - 1.06 # stops cleanly ahead of the aft side locker bay!
	var span := z1 - z0
	var mid_z := (z0 + z1) * 0.5
	var vs := sill / cos(lean)
	var vt := (sill + wh) / cos(lean)
	var ledge_d := 0.105

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# 1. Under-sill charcoal thermal radiator convector ducts + recessed floor baseboard cable channels.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_DARK.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var basis := Cabin._wall_basis(q, side)
		var n := Cabin._n(q, side)
		# Slim dado cable trunking & floor thermal convector housing flush along the lower leaning wall.
		s.box(Cabin._pt(q, side, mid_z, 0.22 / cos(lean)) + n * 0.035,
				Vector3(span, 0.24, 0.068), basis, [RoomMesh.FRONT])
		# Dark recessed rubber mat tray inlay on top of the pressure-window sill ledge.
		s.box(Cabin._pt(q, side, mid_z, vs - 0.025) + n * (ledge_d * 0.48),
				Vector3(span, 0.028, ledge_d - 0.015), basis, [RoomMesh.FRONT])
		# Clean physics box enclosing each side sill ledge (strictly inside Cabin._box, > 0.98 m from viewer).
		var cx := float(q["cx"])
		var hw := float(q["hw"])
		var wall_x_sill := hw - sill * tan(lean)
		c.shapes.append(PhysicsShapes.box(
				Vector3(cx + side * (wall_x_sill - ledge_d * 0.5), sill - 0.03, mid_z),
				Vector3(ledge_d, 0.06, span), Basis()))

	# 2. Machined brushed-aluminium sill bullnose, radiator louvre slats, viewport pressure clamp lugs & pier grab-bars.
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	for side: float in [-1.0, 1.0]:
		var basis := Cabin._wall_basis(q, side)
		var n := Cabin._n(q, side)
		var up := Cabin._up(q, side)
		# Continuous chamfered aerospace-aluminium sill bullnose rail & twin lower thermal-duct louvre rails.
		u.colour = ALU_BRIGHT.srgb_to_linear()
		u.box(Cabin._pt(q, side, mid_z, vs - 0.028) + n * (ledge_d + 0.004),
				Vector3(span + 0.02, 0.038, 0.022), basis)
		for k in 3:
			u.box(Cabin._pt(q, side, mid_z, (0.16 + 0.055 * k) / cos(lean)) + n * 0.072,
					Vector3(span - 0.16, 0.014, 0.012), basis)
		# Machined pressure-window perimeter clamp lugs & top shade-visor rail around every triple-glazed viewport.
		for wz: float in wzs:
			u.colour = ALU_MID.srgb_to_linear()
			# Top & bottom machined triple-glaze pressure seal retainer bars proud of the frame.
			u.box(Cabin._pt(q, side, wz, vt + 0.038) + n * 0.034, Vector3(ww * 0.72, 0.024, 0.026), basis)
			u.box(Cabin._pt(q, side, wz, vs - 0.018) + n * 0.034, Vector3(ww * 0.72, 0.020, 0.026), basis)
			# Four corner pressure-clamp bosses around each rounded viewport frame.
			u.colour = ALU_DARK.srgb_to_linear()
			for dz: float in [-ww * 0.34, ww * 0.34]:
				for dv: float in [vs + 0.015, vt - 0.015]:
					u.box(Cabin._pt(q, side, wz + dz, dv) + n * 0.032, Vector3(0.038, 0.024, 0.022), basis)
		# Vertical tubular brushed-aluminium expedition grab-handles mounted on the interior window piers (M1, M2, M3).
		u.colour = ALU_BRIGHT.srgb_to_linear()
		for mz: float in marks:
			if mz > fz + 1.2 and mz < bz - 1.2:
				var g0 := Cabin._pt(q, side, mz, (sill + 0.22) / cos(lean)) + n * 0.095
				var g1 := Cabin._pt(q, side, mz, (sill + 0.76) / cos(lean)) + n * 0.095
				Shapes.beam(u, g0, g1, Vector2(0.022, 0.022), n)
				for gp: Vector3 in [g0, g1]:
					Shapes.beam(u, gp, gp - n * 0.055, Vector2(0.020, 0.024), up)
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Overhead pressurised oxygen & thermal-coolant conduits running longitudinally beneath the arched roof shoulders,
## four recessed warm expedition LED ceiling lighting troughs (`PieceLamps`, `bake_lamps: 2`), and continuous live
## architectural cove lighting troughs (`PieceCove`, `cove_floor: 0.45`).
static func _overhead_conduits_and_lighting(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var crown_y := float(q["headroom"])
	var marks: Array[float] = Cabin._bay_marks(q)
	var z0 := fz + 0.20
	var z1 := bz - 0.16
	var span := z1 - z0
	var mid_z := (z0 + z1) * 0.5
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	# 1. Twin chamfered longitudinal overhead service raceway housings flanking the central arched ceiling spine.
	s.surface(c.tinted("plastic"))
	s.colour = TITANIUM_SAND.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var rx := cx + side * 0.62
		var ry := _roof_y(q, rx) - 0.042
		s.box(Vector3(rx, ry, mid_z), Vector3(0.24, 0.058, span), Basis(Vector3.BACK, -side * 0.18))

	# 2. Pressurised oxygen (O2) and thermal-coolant pipes along both upper ceiling haunches, clamped at every bay mark!
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	for side: float in [-1.0, 1.0]:
		var px_hi := cx + side * 1.04
		var py_hi := _roof_y(q, px_hi) - 0.055
		var px_lo := cx + side * 1.18
		var py_lo := _roof_y(q, px_lo) - 0.062
		# Main pressurised brushed-aluminium O2 supply pipe & secondary thermal-coolant return pipe.
		u.colour = ALU_BRIGHT.srgb_to_linear()
		Shapes.cylinder(u, Vector3(px_hi, py_hi, z0), 0.026, span, 10, basis_z)
		u.colour = ALU_MID.srgb_to_linear()
		Shapes.cylinder(u, Vector3(px_lo, py_lo, z0), 0.019, span, 8, basis_z)
		# Machined pipe clamp brackets & colour-coded pressure identification bands at every bay ring-frame!
		for mz: float in marks:
			u.colour = ALU_DARK.srgb_to_linear()
			u.box(Vector3((px_hi + px_lo) * 0.5, (py_hi + py_lo) * 0.5 + 0.016, mz),
					Vector3(0.24, 0.068, 0.048), Basis(Vector3.BACK, -side * 0.34))
			# Crisp colour-coded pressure rings (O2 teal on upper conduit, thermal terracotta on lower conduit).
			u.surface(c.soft("plastic", true))
			u.colour = O2_TEAL.srgb_to_linear()
			Shapes.cylinder(u, Vector3(px_hi, py_hi, mz - 0.10), 0.030, 0.055, 10, basis_z)
			u.colour = TERRACOTTA.srgb_to_linear()
			Shapes.cylinder(u, Vector3(px_lo, py_lo, mz - 0.10), 0.023, 0.055, 8, basis_z)
			u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
		# Slim brushed-aluminium inner lip rail along each overhead lighting raceway.
		u.colour = ALU_BRIGHT.srgb_to_linear()
		var lip_x := cx + side * 0.49
		var lip_y := _roof_y(q, lip_x) - 0.058
		u.box(Vector3(lip_x, lip_y, mid_z), Vector3(0.026, 0.032, span))

	# 3. Four recessed warm expedition LED ceiling lighting troughs centered cleanly inside the 4 window bays!
	#    (`PieceLamps`, house group — dims softly when the film starts; 2 middle troughs baked via `bake_lamps: 2`).
	var wzs: Array = q["window_zs"]
	var lamp_y := crown_y - 0.032
	lit.surface(c.shade(LED_WARM))
	for i in wzs.size():
		var lz := float(wzs[i])
		# Recessed brushed-aluminium LED housing frame & transverse anti-glare baffle fins.
		u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
		u.colour = ALU_MID.srgb_to_linear()
		u.box(Vector3(cx, lamp_y + 0.012, lz), Vector3(0.36, 0.026, 0.96))
		u.colour = ALU_DARK.srgb_to_linear()
		for k in 5:
			var bz_fin := lz - 0.36 + 0.18 * k
			u.box(Vector3(cx, lamp_y - 0.008, bz_fin), Vector3(0.28, 0.012, 0.014))
		# Warm frosted expedition LED diffuser face pointing straight down the aisle.
		lit.face([Vector3(cx - 0.145, lamp_y - 0.004, lz - 0.43), Vector3(cx + 0.145, lamp_y - 0.004, lz - 0.43),
				Vector3(cx + 0.145, lamp_y - 0.004, lz + 0.43), Vector3(cx - 0.145, lamp_y - 0.004, lz + 0.43)],
				Vector3.DOWN)
		if i == 1 or i == 2:
			c.lamps.append([Vector3(cx, lamp_y - 0.16, lz), LED_WARM, 0.95])

	# 4. Continuous live indirect architectural cove strips tucked along BOTH overhead raceways (`PieceCove`,
	#    live colour via `Cabin lighting` setting: Habitat amber / Telemetry teal / Off; `cove_floor: 0.45`).
	cove.surface(c.kit.cove_material())
	var cove_base := Color(0.96, 0.97, 0.98).srgb_to_linear()
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.96)
	for side: float in [-1.0, 1.0]:
		# Inward-facing cove strip tucked on the ceiling-facing inner shoulder of each raceway washing the arched spine.
		var cx_strip := cx + side * 0.475
		var cy0 := _roof_y(q, cx_strip) - 0.056
		var cy1 := _roof_y(q, cx_strip) - 0.022
		var n := Vector3(-side, 0.0, 0.0)
		var p0 := Vector3(cx_strip, cy0, z0 + 0.14)
		var p1 := Vector3(cx_strip, cy0, z1 - 0.14)
		var p2 := Vector3(cx_strip, cy1, z1 - 0.14)
		var p3 := Vector3(cx_strip, cy1, z0 + 0.14)
		if side > 0.0:
			cove.face([p0, p1, p2, p3], n)
		else:
			cove.face([p1, p0, p3, p2], n)
		# Subtle downward-grazing expedition strip split cleanly into per-bay segments between structural ring-frames,
		# tucked under a slim machined brushed-aluminium valance hood above each triple-glazed viewport!
		var wx_hi := cx + side * (float(q["hw"]) - 2.02 * tan(float(q["L"])) - 0.032)
		var wzs_cove: Array = q["window_zs"]
		var bay_half := float(q["bay_pitch"]) * 0.5 - 0.085
		for wz_c: float in wzs_cove:
			var cz0 := wz_c - bay_half
			var cz1 := wz_c + bay_half
			var q0 := Vector3(wx_hi, 1.995, cz0)
			var q1 := Vector3(wx_hi, 1.995, cz1)
			var q2 := Vector3(wx_hi, 2.030, cz1)
			var q3 := Vector3(wx_hi, 2.030, cz0)
			if side > 0.0:
				cove.face([q0, q1, q2, q3], Vector3(-side, 0.0, 0.0))
			else:
				cove.face([q1, q0, q3, q2], Vector3(-side, 0.0, 0.0))
			u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
			u.colour = ALU_MID.srgb_to_linear()
			u.box(Vector3(wx_hi - side * 0.008, 2.042, wz_c), Vector3(0.036, 0.016, bay_half * 2.0 + 0.01))
	cove.colour = Color.WHITE
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Rugged aerospace forward cinema bulkhead: deep charcoal picture mask bezel, chamfered brushed-aluminium outer
## housing with corner bolt gussets, lower instrumentation console, twin backlit amber/teal telemetry status displays
## (`PieceWindows` + `PieceLamps`), overhead pressure-seal status header bar, and indirect screen-surround cove wash.
static func _forward_bulkhead(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(1.68, 0.945))
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
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	# 1. Rugged lower bulkhead instrumentation console (slate chassis + chamfered titanium upper deck + grille bays).
	var con_h := 1.24
	var con_d := 0.24
	var con_w := (hw - con_h * tan(float(q["L"]))) * 2.0 - 0.06
	s.surface(c.tinted("iron"))
	s.colour = SLATE_HULL.srgb_to_linear()
	s.box(Vector3(cx, con_h * 0.5, fz + con_d * 0.5), Vector3(con_w, con_h, con_d), Basis(),
			[RoomMesh.DOWN, RoomMesh.FRONT])
	# Recessed dark kick-plinth and recessed matte-black screen backing housing behind the floating picture.
	s.colour = MASK_BLACK.srgb_to_linear()
	s.box(Vector3(cx, 0.055, fz + con_d + 0.008), Vector3(con_w - 0.08, 0.11, 0.018), Basis(), [RoomMesh.DOWN])
	var bz := sc_z - 0.028
	var bw := 0.058
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(sc_x + side * (hsw + bw * 0.5), sc_y, bz), Vector3(bw, sh + bw * 2.0, 0.056))
	s.box(Vector3(sc_x, sc_y + hsh + bw * 0.5, bz), Vector3(sw, bw, 0.056))
	s.box(Vector3(sc_x, sc_y - hsh - bw * 0.5, bz), Vector3(sw, bw, 0.056))
	# Matte backing behind screen so zero light bleeds around edges.
	s.box(Vector3(sc_x, sc_y, fz + 0.045), Vector3(sw + 0.28, sh + 0.20, 0.09), Basis(), [RoomMesh.FRONT])

	# Flanking chamfered warm-sand composite equipment cheek panels on the forward bulkhead beside the screen.
	s.surface(c.tinted("plastic"))
	s.colour = TITANIUM_SAND.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var wall_mid := hw - 1.90 * tan(float(q["L"])) # ~1.616 m
		var cheek_x0 := hsw + bw + 0.10
		var cheek_w := maxf(wall_mid - cheek_x0 - 0.06, 0.24)
		var px := cx + side * (cheek_x0 + cheek_w * 0.5)
		s.box(Vector3(px, 1.88, fz + 0.055), Vector3(cheek_w, 0.96, 0.11), Basis(), [RoomMesh.FRONT])

	# 2. Machined brushed-aluminium outer screen frame, corner bolt gussets, console bullnose rail & cooling slats.
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_BRIGHT.srgb_to_linear()
	var fr_z := sc_z - 0.008
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(sc_x + side * (hsw + bw + 0.016), sc_y, fr_z), Vector3(0.032, sh + bw * 2.0 + 0.064, 0.032))
	u.box(Vector3(sc_x, sc_y + hsh + bw + 0.016, fr_z), Vector3(sw + bw * 2.0, 0.032, 0.032))
	u.box(Vector3(sc_x, sc_y - hsh - bw - 0.016, fr_z), Vector3(sw + bw * 2.0, 0.032, 0.032))
	# Corner machined reinforcement gusset plates on all four corners of the cinema screen frame.
	u.colour = ALU_MID.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			u.box(Vector3(sc_x + sx * (hsw + bw + 0.02), sc_y + sy * (hsh + bw + 0.02), fr_z + 0.008),
					Vector3(0.085, 0.085, 0.020))
	# Heavy horizontal brushed-aluminium console counter rail + recessed thermal intake louvre fins.
	u.colour = ALU_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx, con_h + 0.018, fz + con_d + 0.014), Vector3(con_w + 0.04, 0.038, 0.046))
	# Tubular aluminium hand-hold rail running across the lower bulkhead console (bracing bar).
	var basis_x := Basis(Vector3.BACK, -PI * 0.5)
	Shapes.cylinder(u, Vector3(cx - 0.92, con_h - 0.12, fz + con_d + 0.068), 0.015, 1.84, 10, basis_x)
	for hx: float in [-0.88, 0.0, 0.88]:
		u.box(Vector3(cx + hx, con_h - 0.12, fz + con_d + 0.034), Vector3(0.024, 0.028, 0.064))
	# Twin lower bulkhead thermal intake grille bays with horizontal machined fins.
	u.colour = ALU_MID.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * 0.86
		s.surface(c.tinted("iron"))
		s.colour = MASK_BLACK.srgb_to_linear()
		s.box(Vector3(gx, 0.44, fz + con_d + 0.006), Vector3(1.06, 0.42, 0.016), Basis(), [RoomMesh.FRONT])
		for k in 6:
			u.box(Vector3(gx, 0.28 + 0.062 * k, fz + con_d + 0.018), Vector3(1.00, 0.014, 0.014))

	# 3. Slim Amber & Cyan/Teal Telemetry Status Displays on the forward bulkhead (clean, never intruding on screen!).
	#    a) Twin glowing teal-cyan telemetry monitors nested on the upper lower-console fascia (`y = 0.90`, `PieceWindows`),
	#       with crisp dark geometric bar-graph/terrain-profile overlay lines (zero text!).
	var gw: Array = c.glows.get("window", [])
	for side: float in [-1.0, 1.0]:
		var tx := cx + side * 0.84
		var ty := 0.88
		var tz := fz + con_d + 0.014
		# Dark anodised monitor bezel frame.
		s.surface(c.tinted("iron"))
		s.colour = SLATE_DARK.srgb_to_linear()
		s.box(Vector3(tx, ty, tz), Vector3(0.62, 0.24, 0.024))
		# Glowing steady cyan/green telemetry screen face (`PieceWindows`, accent group).
		gw.append([Vector3(tx - side * 0.06, ty, tz + 0.014), Vector3(0.21, 0.0, 0.0), Vector3(0.0, 0.088, 0.0),
				Vector3.BACK])
		# Crisp dark geometric telemetry grid / bar-chart dividers over the glowing display face.
		u.surface(c.soft("plastic", true))
		u.colour = SLATE_DARK.srgb_to_linear()
		var disp_x := tx - side * 0.06
		u.box(Vector3(disp_x, ty, tz + 0.017), Vector3(0.41, 0.008, 0.004))
		for k in 5:
			var bx := disp_x - 0.16 + 0.08 * k
			var bh := 0.032 + 0.028 * float((k * 3 + (1 if side > 0.0 else 0)) % 4)
			u.box(Vector3(bx, ty - 0.082 + bh * 0.5, tz + 0.017), Vector3(0.026, bh, 0.004))
		# Warm amber status bar-column next to each cyan telemetry monitor (`PieceLamps`, dims gracefully during film!).
		lit.surface(c.shade(TELEM_AMBER))
		var ax := tx + side * 0.22
		for k in 3:
			var ay := ty - 0.055 + 0.055 * k
			lit.face([Vector3(ax - 0.048, ay - 0.016, tz + 0.014), Vector3(ax + 0.048, ay - 0.016, tz + 0.014),
					Vector3(ax + 0.048, ay + 0.016, tz + 0.014), Vector3(ax - 0.048, ay + 0.016, tz + 0.014)],
					Vector3.BACK)

	#    b) Slim horizontal telemetry & hull-seal status bar centered cleanly ABOVE the screen (`y = 2.615`, > 10 cm
	#       clear of screen top `2.505`!), with three glowing steady green seal pips (`PieceWindows`) and amber framing!
	var hdr_y := 2.615
	var hdr_z := fz + 0.075
	s.surface(c.tinted("iron"))
	s.colour = SLATE_DARK.srgb_to_linear()
	s.box(Vector3(cx, hdr_y, hdr_z), Vector3(0.76, 0.072, 0.075))
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_MID.srgb_to_linear()
	u.box(Vector3(cx, hdr_y + 0.038, hdr_z + 0.006), Vector3(0.78, 0.012, 0.068))
	u.box(Vector3(cx, hdr_y - 0.038, hdr_z + 0.006), Vector3(0.78, 0.012, 0.068))
	for px: float in [-0.22, 0.0, 0.22]:
		gw.append([Vector3(cx + px, hdr_y, hdr_z + 0.040), Vector3(0.068, 0.0, 0.0), Vector3(0.0, 0.018, 0.0),
				Vector3.BACK])
	#    c) Slim vertical telemetry accent strips tucked on the flanking bulkhead cheek panels (`y = 1.92`).
	for side: float in [-1.0, 1.0]:
		var sx_bar := cx + side * (hsw + bw + 0.25)
		s.surface(c.tinted("iron"))
		s.colour = SLATE_DARK.srgb_to_linear()
		s.box(Vector3(sx_bar, 1.92, fz + 0.118), Vector3(0.095, 0.68, 0.022))
		gw.append([Vector3(sx_bar, 2.08, fz + 0.132), Vector3(0.028, 0.0, 0.0), Vector3(0.0, 0.12, 0.0), Vector3.BACK])
		lit.surface(c.shade(TELEM_AMBER))
		lit.face([Vector3(sx_bar - 0.028, 1.66, fz + 0.132), Vector3(sx_bar + 0.028, 1.66, fz + 0.132),
				Vector3(sx_bar + 0.028, 1.90, fz + 0.132), Vector3(sx_bar - 0.028, 1.90, fz + 0.132)], Vector3.BACK)
	c.glows["window"] = gw

	# 4. Recessed indirect cove wash behind the floating cinema screen housing (`PieceCove`, live colour).
	cove.surface(c.kit.cove_material())
	var cove_base := Color(0.96, 0.97, 0.98).srgb_to_linear()
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.88)
	for side: float in [-1.0, 1.0]:
		var vx := sc_x + side * (hsw + bw + 0.058)
		cove.face([Vector3(vx - 0.022, sc_y - hsh - 0.02, fz + 0.095),
				Vector3(vx + 0.022, sc_y - hsh - 0.02, fz + 0.095),
				Vector3(vx + 0.022, sc_y + hsh + 0.02, fz + 0.095),
				Vector3(vx - 0.022, sc_y + hsh + 0.02, fz + 0.095)], Vector3.BACK)
	cove.face([Vector3(sc_x - hsw - 0.06, con_h + 0.05, fz + 0.095),
			Vector3(sc_x + hsw + 0.06, con_h + 0.05, fz + 0.095),
			Vector3(sc_x + hsw + 0.06, con_h + 0.11, fz + 0.095),
			Vector3(sc_x - hsw - 0.06, con_h + 0.11, fz + 0.095)], Vector3.BACK)
	cove.colour = Color.WHITE
	s.colour = Color.WHITE
	u.colour = Color.WHITE

	# Clean physics collision box for the forward instrumentation console (strictly inside Cabin._box).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, con_h * 0.5, fz + con_d * 0.5 + 0.01),
			Vector3(con_w - 0.04, con_h, con_d), Basis()))


## Aft side expedition bays (`z = +2.48..+3.28`, aft of the last windows):
## - Starboard (`+1`): geological sample locker with cargo drawers and four glass-sleeved Martian red-dust sample
##   canisters (`PieceGlass`) sealed with titanium caps and hazard-yellow collar rings.
## - Port (`-1`): lower pressure-manifold equipment cabinet crowned by a framed topographic Martian geology & traverse
##   map plaque (concentric crater contours and plotted rover route — pure geometry, zero text).
static func _side_lockers_and_geology(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var lean := float(q["L"])
	var bz := float(q["back_z"])
	var bay_z := bz - 0.48 # +2.92 m, centered cleanly in the solid aft bay [+2.40..+3.40]
	var bay_w := 0.78

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var gl: RoomMesh = c.glass

	# --- Starboard (+1): Geological Sample Locker & Red-Dust Sample Canisters ---
	var sb_basis := Cabin._wall_basis(q, 1.0)
	var sb_n := Cabin._n(q, 1.0)
	var sb_up := Cabin._up(q, 1.0)
	# Lower latched cargo cabinet (`v = 0.0..0.90`, depth 0.24 m) + recessed upper sample showcase niche (`0.90..1.68`).
	s.surface(c.tinted("iron"))
	s.colour = SLATE_HULL.srgb_to_linear()
	s.box(Cabin._pt(q, 1.0, bay_z, 0.45) + sb_n * 0.12, Vector3(bay_w, 0.90, 0.24), sb_basis,
			[RoomMesh.DOWN, RoomMesh.FRONT])
	s.box(Cabin._pt(q, 1.0, bay_z, 1.66) + sb_n * 0.11, Vector3(bay_w, 0.06, 0.22), sb_basis, [RoomMesh.FRONT])
	for dz: float in [-bay_w * 0.5 + 0.03, bay_w * 0.5 - 0.03]:
		s.box(Cabin._pt(q, 1.0, bay_z + dz, 1.28) + sb_n * 0.11, Vector3(0.06, 0.76, 0.22), sb_basis, [RoomMesh.FRONT])
	# Warm-sand locker back panel behind the four Martian red-dust sample canisters so they silhouette crisply!
	s.surface(c.tinted("plastic"))
	s.colour = TITANIUM_SAND.srgb_to_linear()
	s.box(Cabin._pt(q, 1.0, bay_z, 1.28) + sb_n * 0.025, Vector3(bay_w - 0.10, 0.72, 0.04), sb_basis, [RoomMesh.FRONT])
	# Two lower equipment drawer faces with terracotta pull bars & machined aluminium rack trim.
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_BRIGHT.srgb_to_linear()
	u.box(Cabin._pt(q, 1.0, bay_z, 0.905) + sb_n * 0.125, Vector3(bay_w + 0.02, 0.028, 0.25), sb_basis)
	for dy: float in [0.24, 0.64]:
		u.colour = ALU_MID.srgb_to_linear()
		u.box(Cabin._pt(q, 1.0, bay_z, dy) + sb_n * 0.245, Vector3(bay_w - 0.10, 0.30, 0.018), sb_basis)
		u.surface(c.soft("plastic", true))
		u.colour = TERRACOTTA.srgb_to_linear()
		u.box(Cabin._pt(q, 1.0, bay_z, dy + 0.08) + sb_n * 0.262, Vector3(0.28, 0.026, 0.024), sb_basis)
		u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	# Four sealed vertical Martian regolith sample canisters standing on the sampling shelf (`v = 0.92..1.44`)!
	# Each canister has machined aluminium base/cap, yellow pressure collar, layered rust-ochre & basalt core sample,
	# and a see-through protective glass cylinder sleeve (`PieceGlass`)!
	var can_shelf_v := 0.92
	for k in 4:
		var cz := bay_z - 0.24 + 0.16 * k
		var base_p := Cabin._pt(q, 1.0, cz, can_shelf_v) + sb_n * 0.125
		var core_h := 0.26 + 0.04 * float(k % 2)
		# Machined aluminium bottom foot & upper pressure seal cap.
		u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
		u.colour = ALU_BRIGHT.srgb_to_linear()
		Shapes.cylinder(u, base_p, 0.044, 0.042, 10, sb_basis)
		Shapes.cylinder(u, base_p + sb_up * (core_h + 0.055), 0.045, 0.055, 10, sb_basis)
		# Yellow hazard/sample-seal locking collar + inner layered Martian rust-ochre & dark basalt regolith cores!
		u.surface(c.soft("plastic", true))
		u.colour = HAZARD_YELLOW.srgb_to_linear()
		Shapes.cylinder(u, base_p + sb_up * (core_h + 0.036), 0.047, 0.022, 10, sb_basis)
		u.colour = (RUST_CORE if k % 2 == 0 else TERRACOTTA).srgb_to_linear()
		Shapes.cylinder(u, base_p + sb_up * 0.042, 0.030, core_h * 0.62, 10, sb_basis)
		u.colour = BASALT_CORE.srgb_to_linear()
		Shapes.cylinder(u, base_p + sb_up * (0.042 + core_h * 0.62), 0.029, core_h * 0.34, 10, sb_basis)
		# Protective see-through containment glass sleeve (`PieceGlass`).
		gl.surface(c.mat("tin"))
		Shapes.cylinder(gl, base_p + sb_up * 0.042, 0.041, core_h, 10, sb_basis, false)
	# Brushed-aluminium retaining bar across the front of the four sample canisters (so nothing shifts under way!),
	# plus a recessed warm showcase LED light strip tucked beneath the upper locker shelf illuminating the cores!
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_BRIGHT.srgb_to_linear()
	u.box(Cabin._pt(q, 1.0, bay_z, can_shelf_v + 0.20) + sb_n * 0.195, Vector3(bay_w - 0.08, 0.018, 0.018), sb_basis)
	var lit_sb: RoomMesh = c.lit
	lit_sb.surface(c.shade(LED_WARM))
	var sc_mid := Cabin._pt(q, 1.0, bay_z, 1.622) + sb_n * 0.12
	var sc_u := sb_basis.x * 0.29
	var sc_v := sb_n * 0.025
	lit_sb.face([sc_mid - sc_u - sc_v, sc_mid + sc_u - sc_v, sc_mid + sc_u + sc_v, sc_mid - sc_u + sc_v], -sb_up)
	# Clean physics box enclosing starboard sample locker (strictly inside Cabin._box, > 2.9 m from origin).
	var sb_x := cx + (hw - 1.65 * tan(lean) - 0.14)
	c.shapes.append(PhysicsShapes.box(Vector3(sb_x, 0.86, bay_z), Vector3(0.24, 1.68, bay_w), Basis()))

	# --- Port (-1): Lower Pressure-Manifold Cabinet + Framed Topographic Martian Geology Map Plaque ---
	var pt_basis := Cabin._wall_basis(q, -1.0)
	var pt_n := Cabin._n(q, -1.0)
	var pt_up := Cabin._up(q, -1.0)
	# Lower equipment cabinet housing environmental pressure valves & gauges (`v = 0.0..0.90`).
	s.surface(c.tinted("iron"))
	s.colour = SLATE_HULL.srgb_to_linear()
	s.box(Cabin._pt(q, -1.0, bay_z, 0.45) + pt_n * 0.11, Vector3(bay_w, 0.90, 0.22), pt_basis,
			[RoomMesh.DOWN, RoomMesh.FRONT])
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_BRIGHT.srgb_to_linear()
	u.box(Cabin._pt(q, -1.0, bay_z, 0.905) + pt_n * 0.115, Vector3(bay_w + 0.02, 0.028, 0.23), pt_basis)
	# Pressure manifold vertical pipes & twin rotary valve handwheels on the cabinet face.
	for dz: float in [-0.20, 0.20]:
		var vp := Cabin._pt(q, -1.0, bay_z + dz, 0.52) + pt_n * 0.235
		Shapes.arch(u, vp, 0.055, 0.072, 0.016, 14, pt_basis, 0.0, TAU, ["front", "inner", "outer"])
		u.box(vp, Vector3(0.12, 0.016, 0.012), pt_basis)
		u.box(vp, Vector3(0.016, 0.12, 0.012), pt_basis)
	# Framed Topographic Martian Geology & Rover Traverse Map Plaque (`v = 1.06..1.68`, pure geometry, zero text!).
	var map_c := Cabin._pt(q, -1.0, bay_z, 1.38) + pt_n * 0.032
	u.colour = ALU_BRIGHT.srgb_to_linear()
	u.box(map_c, Vector3(0.72, 0.52, 0.032), pt_basis)
	# Slim brushed-aluminium map-reading hood visor along the top edge of the geology plaque.
	u.colour = ALU_MID.srgb_to_linear()
	u.box(map_c + pt_up * 0.265 + pt_n * 0.032, Vector3(0.68, 0.022, 0.075), pt_basis)
	u.surface(c.soft("plastic", true))
	u.colour = MAP_DARK.srgb_to_linear()
	u.box(map_c + pt_n * 0.014, Vector3(0.66, 0.46, 0.010), pt_basis)
	# Topographic Martian rust-ochre elevation strata bands, canyon rift trace & concentric impact-crater rings!
	var map_z := pt_n * 0.022
	u.colour = MAP_OCHRE.srgb_to_linear()
	Shapes.arch(u, map_c + map_z + pt_basis.x * (-0.14) + pt_up * 0.06, 0.09, 0.115, 0.008, 18, pt_basis, 0.0, TAU,
			["front"])
	Shapes.arch(u, map_c + map_z + pt_basis.x * 0.16 - pt_up * 0.05, 0.06, 0.082, 0.008, 16, pt_basis, 0.0, TAU,
			["front"])
	u.colour = RUST_CORE.srgb_to_linear()
	Shapes.beam(u, map_c + map_z - pt_basis.x * 0.28 + pt_up * 0.16, map_c + map_z + pt_basis.x * 0.26 - pt_up * 0.17,
			Vector2(0.016, 0.006), pt_n)
	u.colour = TERRACOTTA.srgb_to_linear()
	Shapes.arch(u, map_c + map_z + pt_basis.x * (-0.14) + pt_up * 0.06, 0.042, 0.056, 0.008, 16, pt_basis, 0.0, TAU,
			["front"])
	# Plotted rover-train traverse route arc connecting departure & arrival domed colony markers (hazard yellow + teal)!
	u.colour = HAZARD_YELLOW.srgb_to_linear()
	Shapes.beam(u, map_c + map_z - pt_basis.x * 0.24 - pt_up * 0.12, map_c + map_z + pt_basis.x * 0.02 + pt_up * 0.01,
			Vector2(0.014, 0.008), pt_n)
	Shapes.beam(u, map_c + map_z + pt_basis.x * 0.02 + pt_up * 0.01, map_c + map_z + pt_basis.x * 0.24 + pt_up * 0.11,
			Vector2(0.014, 0.008), pt_n)
	u.colour = O2_TEAL.srgb_to_linear()
	for end_pt: Vector3 in [map_c + map_z - pt_basis.x * 0.24 - pt_up * 0.12,
			map_c + map_z + pt_basis.x * 0.24 + pt_up * 0.11]:
		u.box(end_pt + pt_n * 0.004, Vector3(0.044, 0.044, 0.010), pt_basis)
	# Clean physics box enclosing port manifold cabinet & geology map plaque (strictly inside Cabin._box).
	var pt_x := cx - (hw - 1.65 * tan(lean) - 0.13)
	c.shapes.append(PhysicsShapes.box(Vector3(pt_x, 0.86, bay_z), Vector3(0.22, 1.68, bay_w), Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Iconic aft circular pressure airlock hatch (`back_z = +3.40`): heavy bolted aerospace-aluminium coaming ring,
## recessed pressure door dish, central 4-spoke brushed-aluminium dogging wheel, bold yellow-and-charcoal hazard
## striping on threshold & flanking chevron collars, glowing airlock pressure-green viewport & seal status bars
## (`PieceWindows`), vertical entry grab-bars, and working Martian Sol chronometer (`PieceClock`) centered above!
static func _aft_airlock_bulkhead(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var basis_aft := Basis(Vector3.UP, PI) # local +Z faces world -Z (into cabin)

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# 1. Heavy structural aft airlock bulkhead frame & bold yellow-and-charcoal hazard-striped threshold kick-plate!
	var hatch_y := 1.08
	var r_in := 0.60
	var r_out := 0.74
	var hatch_z := bz - 0.055

	# Dark recessed pressure bulkhead backing pad & hazard-striped floor threshold step across the airlock doorway.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.06, bz - 0.075), Vector3(1.76, 0.12, 0.13), Basis(), [RoomMesh.DOWN, RoomMesh.BACK])
	# Recessed circular pressure hatch door dish (dark slate steel).
	Shapes.cylinder(s, Vector3(cx, hatch_y, bz - 0.015), r_in + 0.02, 0.036, 24, Basis(Vector3.RIGHT, -PI * 0.5))

	# Bold framed yellow-and-charcoal hazard striping along the airlock floor threshold & flanking vertical caution bars!
	# Floor threshold hazard channel (crisp diagonal yellow parallelogram bars set cleanly on charcoal steel base).
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_MID.srgb_to_linear()
	u.box(Vector3(cx, 0.122, bz - 0.140), Vector3(1.78, 0.014, 0.024))
	u.box(Vector3(cx, 0.008, bz - 0.140), Vector3(1.78, 0.016, 0.024))
	u.surface(c.soft("plastic", true))
	u.colour = HAZARD_YELLOW.srgb_to_linear()
	for k in 9:
		var sx := cx - 0.74 + 0.185 * k
		var zf := bz - 0.146
		u.face([Vector3(sx - 0.042, 0.018, zf), Vector3(sx + 0.048, 0.018, zf),
				Vector3(sx + 0.004, 0.112, zf), Vector3(sx - 0.086, 0.112, zf)], Vector3.FORWARD)
	# Twin crisp vertical yellow-and-charcoal aerospace caution bars flanking the circular pressure airlock ring!
	for side: float in [-1.0, 1.0]:
		var hx := cx + side * 0.88
		var bar_w := 0.105
		var bar_h := 1.24
		var bar_y0 := 0.42
		var bar_yc := bar_y0 + bar_h * 0.5
		s.surface(c.tinted("iron"))
		s.colour = SLATE_DARK.srgb_to_linear()
		s.box(Vector3(hx, bar_yc, bz - 0.016), Vector3(bar_w + 0.022, bar_h + 0.022, 0.022))
		u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
		u.colour = ALU_MID.srgb_to_linear()
		for es: float in [-1.0, 1.0]:
			u.box(Vector3(hx + es * (bar_w * 0.5 + 0.012), bar_yc, bz - 0.020), Vector3(0.012, bar_h + 0.028, 0.022))
		u.box(Vector3(hx, bar_y0 - 0.012, bz - 0.020), Vector3(bar_w + 0.036, 0.014, 0.022))
		u.box(Vector3(hx, bar_y0 + bar_h + 0.012, bz - 0.020), Vector3(bar_w + 0.036, 0.014, 0.022))
		u.surface(c.soft("plastic", true))
		u.colour = HAZARD_YELLOW.srgb_to_linear()
		var hw_b := bar_w * 0.48
		var zf := bz - 0.030
		for k in 8:
			var y0 := bar_y0 + 0.02 + 0.148 * k
			var y1 := y0 + 0.072
			var dy := 0.042 * side
			u.face([Vector3(hx - hw_b, y0, zf), Vector3(hx + hw_b, y0 + dy, zf),
					Vector3(hx + hw_b, y1 + dy, zf), Vector3(hx - hw_b, y1, zf)], Vector3.FORWARD)

	# 2. Heavy chamfered aerospace-aluminium circular pressure airlock coaming ring, 12 radial locking bolt lugs,
	#    hinge knuckles, and central 4-spoke brushed-aluminium dogging wheel!
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_BRIGHT.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, hatch_y, hatch_z), r_in, r_out, 0.095, 28, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Inner pressure-gasket chamfer ring & 12 machined radial perimeter clamping lugs around the circular ring!
	u.colour = ALU_MID.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, hatch_y, hatch_z - 0.038), r_in - 0.03, r_in + 0.015, 0.028, 24, basis_aft, 0.0, TAU,
			["front", "inner"])
	for k in 12:
		var ang := TAU * float(k) / 12.0
		var lx := cx + cos(ang) * (r_out - 0.045)
		var ly := hatch_y + sin(ang) * (r_out - 0.045)
		u.colour = (ALU_DARK if k % 2 == 0 else ALU_BRIGHT).srgb_to_linear()
		u.box(Vector3(lx, ly, hatch_z - 0.056), Vector3(0.048, 0.032, 0.024), Basis(Vector3.BACK, ang))
	# Heavy structural airlock hinge knuckles on the left (-X as seen facing +Z = right side of hatch) and latch dogs.
	u.colour = ALU_MID.srgb_to_linear()
	for dy: float in [-0.26, 0.26]:
		u.box(Vector3(cx - r_out + 0.02, hatch_y + dy, hatch_z - 0.048), Vector3(0.11, 0.085, 0.068))
	# Central 4-spoke brushed-aluminium pressure dogging wheel + recessed hub boss!
	var wheel_z := hatch_z - 0.075
	u.colour = ALU_BRIGHT.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, hatch_y - 0.08, wheel_z), 0.165, 0.205, 0.028, 20, basis_aft, 0.0, TAU,
			["front", "back", "inner", "outer"])
	for sp in 4:
		var a := PI * 0.25 + PI * 0.5 * sp
		u.box(Vector3(cx, hatch_y - 0.08, wheel_z + 0.008), Vector3(0.36, 0.026, 0.022), Basis(Vector3.BACK, a))
	Shapes.cylinder(u, Vector3(cx, hatch_y - 0.08, bz - 0.032), 0.055, 0.11, 12, Basis(Vector3.RIGHT, -PI * 0.5))
	# Twin heavy vertical brushed-aluminium entry grab-bars bolted on either side of the circular airlock ring!
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * 1.04
		Shapes.cylinder(u, Vector3(gx, 0.72, bz - 0.095), 0.017, 0.86, 10)
		for gy: float in [0.76, 1.54]:
			u.box(Vector3(gx, gy, bz - 0.05), Vector3(0.032, 0.034, 0.09))

	# 3. Glowing Airlock Pressure-Green Viewport & Flanking Seal-Status Bars (`PieceWindows`, steady accent group!).
	var gw: Array = c.glows.get("window", [])
	# Upper recessed airlock pressure viewport inside the circular hatch door (`y = hatch_y + 0.28`).
	var vp_y := hatch_y + 0.28
	u.colour = ALU_DARK.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, vp_y, bz - 0.055), 0.115, 0.15, 0.036, 18, basis_aft, 0.0, TAU, ["front", "inner", "outer"])
	gw.append([Vector3(cx, vp_y, bz - 0.062), Vector3(-0.105, 0.0, 0.0), Vector3(0.0, 0.105, 0.0), Vector3.FORWARD])
	# Twin vertical glowing airlock pressure-green status strips mounted beside the upper airlock coaming!
	for side: float in [-1.0, 1.0]:
		var sx := cx + side * 0.72
		s.surface(c.tinted("iron"))
		s.colour = SLATE_DARK.srgb_to_linear()
		s.box(Vector3(sx, 1.88, bz - 0.025), Vector3(0.11, 0.28, 0.032))
		gw.append([Vector3(sx, 1.88, bz - 0.044), Vector3(-0.034, 0.0, 0.0), Vector3(0.0, 0.11, 0.0), Vector3.FORWARD])
	c.glows["window"] = gw

	# 4. Working Martian Sol Chronometer (`PieceClock`, live wall time) centered high above the circular airlock!
	var clk_y := 2.22
	var clk_r := 0.175
	var clk_z := bz - 0.046
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_BRIGHT.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, clk_y, clk_z), clk_r, clk_r + 0.042, 0.056, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Heavy aerospace mounting flange lugs & terracotta 12-3-6-9 Sol cardinal index markers around the bezel.
	u.colour = ALU_DARK.srgb_to_linear()
	for k in 4:
		var ang := PI * 0.25 + PI * 0.5 * k
		u.box(Vector3(cx + cos(ang) * (clk_r + 0.048), clk_y + sin(ang) * (clk_r + 0.048), clk_z + 0.008),
				Vector3(0.042, 0.042, 0.024), Basis(Vector3.BACK, ang))
	u.surface(c.soft("plastic", true))
	u.colour = TERRACOTTA.srgb_to_linear()
	for k in 4:
		var ang := PI * 0.5 * k
		u.box(Vector3(cx + cos(ang) * (clk_r + 0.022), clk_y + sin(ang) * (clk_r + 0.022), clk_z - 0.030),
				Vector3(0.034, 0.012, 0.008), Basis(Vector3.BACK, ang))
	c.clocks.append([Vector3(cx, clk_y, bz - 0.068), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# Clean physics collision box enclosing the aft circular airlock bulkhead assembly (strictly inside Cabin._box).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, 1.08, bz - 0.085), Vector3(1.88, 2.08, 0.14), Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


# --- The technical expedition recliner rows' hardware -----------------------------------------------------------------

## Faceted slate & brushed-aluminium shared armrests (`Seats.RECLINER_ARM`, both kept round the viewer's folded seat;
## outboard armrests slimmed & tucked cleanly inside the 8.5 deg leaning pressure hull), tailored warm-sand technical
## headrest wraps, solid rear seatback shell closures, tubular brushed-aluminium seatback grab-bar handles, and low
## aisle deck-guide strips (`PieceCove`).
static func _rows(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var slots: Array = Cabin.seat_slots_for(c.builder_params)
	if slots.is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var lean := float(q["L"])
	var pitch := float(q["seat_pitch"])
	var arm_w := Seats.RECLINER_ARM
	var arm_h := 0.56
	var arm_d := 0.58
	var arm_z := -0.07
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15.0)), Vector3(0.0, 0.46, 0.12))

	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# Collect unique armrest positions per row block; slim and tuck outboard armrests cleanly inside the 8.5 deg wall!
	var wall_at_arm := hw - (arm_h + 0.04) * tan(lean) # ~1.810 m
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
				var outboard := absf(from_cx) > 1.55
				var w := 0.095 if outboard else arm_w
				var ax := (cx + signf(from_cx) * minf(absf(from_cx), wall_at_arm - w * 0.5 - 0.032)) if outboard \
						else raw_x
				arm_entries[k] = [Vector3(ax, o.y, o.z), w, outboard]
				if absf(ax - cx) < float(q["aisle"]) * 0.5 + 0.12:
					aisle_arms.append([Vector3(ax, o.y, o.z), -1.0 if ax > cx else 1.0, w])

	# 1. Faceted dark-slate expedition armrest pedestals, contoured graphite caps & tactile control-pod accents.
	u.surface(c.soft("plastic", true))
	for entry: Array in arm_entries.values():
		var at: Vector3 = entry[0]
		var w := float(entry[1])
		u.colour = SLATE_HULL.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h * 0.5, arm_z), Vector3(w, arm_h, arm_d), Basis(), [RoomMesh.DOWN])
		u.colour = SLATE_DARK.srgb_to_linear()
		u.rounded_box(at + Vector3(0.0, arm_h + 0.018, arm_z - 0.008), Vector3(w + 0.01, 0.036, arm_d + 0.018),
				0.012, Transform3D(), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		# Tiny tactile terracotta & teal suit-comms indicator buttons on the forward armrest control bezel.
		u.colour = TERRACOTTA.srgb_to_linear()
		u.box(Vector3(at.x - 0.016, arm_h + 0.039, at.z + arm_z - arm_d * 0.30), Vector3(0.014, 0.006, 0.018))
		u.colour = O2_TEAL.srgb_to_linear()
		u.box(Vector3(at.x + 0.016, arm_h + 0.039, at.z + arm_z - arm_d * 0.30), Vector3(0.014, 0.006, 0.018))

	# 2. Brushed-aluminium aerospace armrest structural side rails, bullnose front bumpers & titanium control bezels.
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	for entry: Array in arm_entries.values():
		var at: Vector3 = entry[0]
		var w := float(entry[1])
		u.colour = ALU_BRIGHT.srgb_to_linear()
		# Chamfered aerospace-aluminium front nose guard & structural side stiffener ribs.
		u.box(at + Vector3(0.0, arm_h * 0.52, arm_z - arm_d * 0.5 - 0.005), Vector3(w - 0.012, arm_h * 0.82, 0.012))
		u.colour = ALU_MID.srgb_to_linear()
		u.box(at + Vector3(0.0, 0.30, arm_z), Vector3(w + 0.014, 0.022, arm_d * 0.88))
		# Forearm titanium control plate & tactile recline toggle switch behind the comms buttons.
		u.colour = ALU_BRIGHT.srgb_to_linear()
		u.box(Vector3(at.x, arm_h + 0.037, at.z + arm_z - arm_d * 0.30), Vector3(minf(w - 0.018, 0.068), 0.004, 0.054))
		u.box(Vector3(at.x, arm_h + 0.039, at.z + arm_z - arm_d * 0.12), Vector3(0.026, 0.010, 0.028))

	# 3. Tailored warm-sand technical headrest wraps hugging `seats.gd _recliner`'s exact headrest curve
	#    (`bend = -0.35`, `radius = 0.062`) cleanly proud of the pillow envelope so zero upholstery z-fights through.
	var wi := pitch - arm_w - 0.01
	u.surface(c.soft("cloth", true))
	u.colour = HEADREST_SAND.srgb_to_linear()
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.rounded_box(Vector3(0.0, 0.652, -0.011), Vector3(wi - 0.13, 0.245, 0.154), 0.062, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])

	# 4. Solid slate rear seatback inner shell closure + elastic-strap technical rear cargo stowage pockets.
	u.surface(c.soft("plastic", true))
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		# Closes the open front of `seats.gd _recliner`'s taller outer shell cleanly from every angle.
		u.colour = SLATE_HULL.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.41, 0.070), Vector3(wi + 0.008, 0.82, 0.034), 0.016, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])
		# Rugged rear expedition stowage pouch & terracotta retention webbing strap.
		u.colour = SLATE_DARK.srgb_to_linear()
		u.rounded_box(Vector3(0.0, 0.28, 0.126), Vector3(wi - 0.10, 0.24, 0.018), 0.008, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.FRONT])
		u.colour = TERRACOTTA.srgb_to_linear()
		u.box(t_world * Vector3(0.0, 0.36, 0.136), Vector3(wi - 0.11, 0.022, 0.008), t_world.basis)

	# 5. Heavy tubular brushed-aluminium seatback grab-bar handles across the top back of every seat shell!
	u.surface(c.shiny("chrome", 0.88, 0.68, 0.18))
	u.colour = ALU_BRIGHT.srgb_to_linear()
	var grab_w := wi - 0.10
	var basis_x := Basis(Vector3.BACK, -PI * 0.5)
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		Shapes.cylinder(u, t_world * Vector3(-grab_w * 0.5, 0.57, 0.154), 0.014, grab_w, 8, t_world.basis * basis_x)
		for side: float in [-1.0, 1.0]:
			u.box(t_world * Vector3(side * (grab_w * 0.5 - 0.014), 0.57, 0.132), Vector3(0.024, 0.028, 0.044),
					t_world.basis)

	# 6. Recessed low aisle deck-guide light strips along the aisle-facing base of the aisle armrests (`PieceCove`).
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.96, 0.97, 0.98).srgb_to_linear()
	cove.colour = Color(strip_col.r, strip_col.g, strip_col.b, 0.96)
	for entry: Array in aisle_arms:
		var at: Vector3 = entry[0]
		var inward := float(entry[1])
		var w := float(entry[2])
		var x := at.x + inward * (w * 0.5 + 0.005)
		var z0 := at.z + arm_z - arm_d * 0.44
		var z1 := at.z + arm_z + arm_d * 0.44
		var n := Vector3(inward, 0.0, 0.0)
		var p0 := Vector3(x, 0.038, z0)
		var p1 := Vector3(x, 0.038, z1)
		var p2 := Vector3(x, 0.086, z1)
		var p3 := Vector3(x, 0.086, z0)
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
