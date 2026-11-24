extends RefCounted

## Moon ferry (app/environments/moon_ferry.env.json; docs/environments/rooms/moon_ferry.md): a classic retro-futuristic
## cislunar passenger liner gliding silently through star-filled space from an orbital transfer dock to the Moon Crater
## base. Dressed over a `cabin` builder (`lean: 6.0`, `glazed_roof: true`) and `seats` (`recliner`) rows.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, arches and lathed shapes; no people,
## no real trademarks, no agency emblems or text.
##
##   moonferry_cabin    the cislunar liner's retro-future cabin architecture:
##                      - swept ivory-composite forward flight-deck brow canopy hugging the front arch, blocking screen
##                        glare and peripheral flow clearance with a brushed-titanium arch lip and recessed glowing
##                        orbital cove valance (`PieceCove`, Warm amber / Ice blue / Off, `cove_floor: 0.42`)
##                      - streamlined forward cinema bulkhead with matte-obsidian screen mask bezel, chamfered titanium
##                        trim frame, twin angled ivory composite cheek fairings, recessed spacecraft flight-status
##                        telemetry displays (`PieceWindows`, pure geometric orbital attitude bars & velocity pips), and
##                        lower life-support console with brushed-titanium zero-G handrail & acoustic louvres
##                      - leaning-wall continuous brushed-titanium viewport sill ledges, under-sill thermal diffusers,
##                        cornice orbital cove ribbons (`PieceCove`), titanium pier ring-ribs with recessed cabin sconce
##                        lenses (`PieceLamps`, `bake_lamps: 2`) and curved tubular zero-G handrail loops
##                      - aft circular spacecraft pressure airlock hatch (`Shapes.arch` collar with 8 radial clamp lugs,
##                        domed composite hatch leaf, inner locking wheel, glowing docking status ring & viewport in
##                        `PieceWindows`, flanking zero-G grab-handles) and working mission chronometer (`PieceClock`)
##   moonferry_console  the cislunar lounge seating hardware and aft orbital navigation & service consoles:
##                      - sculpted ivory-composite & brushed-titanium shared recliner armrests (`Seats.RECLINER_ARM`,
##                        both kept when the viewer's own seat folds away) with charcoal arm-caps, personal cabin
##                        control rocker pods, curved bullnose front fairings, and low aisle floor-guide strips
##                        (`PieceCove`)
##                      - crisp contoured ivory headrest shells hugging `seats.gd _recliner`'s exact curve
##                        (`bend = -0.35`, `radius = 0.062`) and tubular titanium zero-G seatback grab-handles
##                      - aft-port cislunar trajectory map console: angled ivory pedestal housing a glowing ice-cyan
##                        backlit display (`PieceWindows`) overlaid with a 3D sculpted Earth-to-Moon transfer loop
##                        (blue Earth disc, silver Moon disc, curved golden transit arcs and crimson ferry marker)
##                      - aft-starboard zero-G cabin service credenza with titanium magnetic tray rails and twin
##                        lathed titanium-and-crimson thermal beverage carafes

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")

const PIECES: Array[String] = ["moonferry_cabin", "moonferry_console"]

## Palette (sRGB): Space-Age ivory composite, brushed titanium, obsidian charcoal, vermilion crimson & orbital accents.
const IVORY_SHELL := Color(0.92, 0.91, 0.88)
const IVORY_WARM := Color(0.86, 0.85, 0.81)
const TITANIUM := Color(0.82, 0.85, 0.89)
const TITANIUM_DARK := Color(0.46, 0.50, 0.56)
const OBSIDIAN := Color(0.06, 0.065, 0.08)
const SLATE_PANEL := Color(0.16, 0.18, 0.22)
const GRIP_DARK := Color(0.11, 0.12, 0.145)
const CRIMSON := Color(0.68, 0.14, 0.13)
const EARTH_BLUE := Color(0.16, 0.44, 0.78)
const EARTH_LAND := Color(0.32, 0.64, 0.42)
const MOON_SILVER := Color(0.76, 0.77, 0.79)
const ORBIT_GOLD := Color(0.96, 0.76, 0.32)
const STATUS_CYAN := Color(0.36, 0.84, 0.98)
const STATUS_AMBER := Color(1.0, 0.66, 0.22)
const LAMP_GLOW := Color(1.0, 0.90, 0.74)

## Swept forward canopy brow depths from front_z (metres): shields the glazed dome roof cleanly over the forward screen
## flow-clearance cone (FLOW_CLEAR_DEG) while opening wide overhead above the passenger rows.
const BROW_CROWN := 1.78
const BROW_SIDE := 2.24


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"moonferry_cabin":
			_cabin(c)
		"moonferry_console":
			_console_and_rows(c)


# --- The cislunar spacecraft cabin ------------------------------------------------------------------------------------

static func _cabin(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_forward_brow_and_bulkhead(c, q)
	_viewport_ledges_and_rails(c, q)
	_aft_airlock_and_clock(c, q)


## Swept ivory-composite forward dome brow cowl, brushed-titanium arch rim, recessed orbital cove valance (`PieceCove`),
## streamlined cinema screen bulkhead, glowing flight-status telemetry displays (`PieceWindows`), and lower life-support
## console with zero-G handrail.
static func _forward_brow_and_bulkhead(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(1.84, 1.035))
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
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
	var lit: RoomMesh = c.lit
	var cove: RoomMesh = c.cove

	# 1. Swept ivory-composite forward dome brow cowl hugging the arched canopy from fz to BROW_CROWN / BROW_SIDE.
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
	s.colour = IVORY_SHELL.srgb_to_linear()
	var inner_f := PackedVector3Array()
	var inner_b := PackedVector3Array()
	var inner_n := PackedVector3Array()
	var lip_out := PackedVector3Array()
	var lip_in := PackedVector3Array()
	var lip_n := PackedVector3Array()
	var brow_t := 0.052
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

	# 2. Streamlined lower forward console & sculpted ivory composite screen cheek bulkheads.
	var console_h := sc_y - hsh - 0.16 # ~1.42 m below the screen mask
	var console_d := 0.26
	var console_z := fz + console_d * 0.5
	var foot_w := hw * 2.0 - 0.28
	s.colour = IVORY_WARM.srgb_to_linear()
	s.box(Vector3(cx, console_h * 0.5, console_z), Vector3(foot_w, console_h, console_d), Basis(),
			[RoomMesh.DOWN, RoomMesh.FRONT])
	# Recessed upper ivory bulkhead shell behind the screen + sculpted cheek pods flanking the picture.
	var back_d := maxf(sc_z - fz - 0.035, 0.08)
	var back_z := fz + back_d * 0.5
	s.colour = IVORY_SHELL.srgb_to_linear()
	s.box(Vector3(sc_x, sc_y, back_z), Vector3(sw + 0.34, sh + 0.22, back_d), Basis(), [RoomMesh.FRONT])
	var cheek_inner := hsw + 0.22
	var cheek_outer := th - 0.06
	var cheek_w := maxf(cheek_outer - cheek_inner, 0.36)
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (cheek_inner + cheek_w * 0.5)
		var ch := minf(_roof_y(q, cx + side * (cheek_inner + cheek_w * 0.85)) - console_h - 0.06, 1.18)
		s.box(Vector3(px, console_h + ch * 0.5, fz + 0.075), Vector3(cheek_w, ch, 0.15), Basis(), [RoomMesh.FRONT])

	# 3. Matte-obsidian cinema mask bezel, lower kick-plinth, recessed thermal louvres & telemetry display housings.
	s.surface(c.tinted("iron"))
	s.colour = OBSIDIAN.srgb_to_linear()
	var mask_z := sc_z - 0.028
	var bw := 0.068
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(sc_x + side * (hsw + bw * 0.5), sc_y, mask_z), Vector3(bw, sh + bw * 2.0, 0.056))
	s.box(Vector3(sc_x, sc_y + hsh + bw * 0.5, mask_z), Vector3(sw, bw, 0.056))
	s.box(Vector3(sc_x, sc_y - hsh - bw * 0.5, mask_z), Vector3(sw, bw, 0.056))
	# Recessed slate-obsidian plinth & twin environmental intake louvre bays below the screen.
	s.colour = SLATE_PANEL.srgb_to_linear()
	s.box(Vector3(cx, 0.065, fz + console_d + 0.01), Vector3(foot_w - 0.06, 0.13, 0.02), Basis(), [RoomMesh.DOWN])
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * 0.96, 0.56, fz + console_d + 0.01), Vector3(1.18, 0.42, 0.02), Basis(),
				[RoomMesh.FRONT])
	# Recessed dark-anodised flight-status instrument housings on both flanking cheeks and above the screen.
	s.colour = OBSIDIAN.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var dx := cx + side * (cheek_inner + cheek_w * 0.5)
		s.box(Vector3(dx, sc_y + 0.04, fz + 0.16), Vector3(cheek_w * 0.76, 0.48, 0.032), Basis(), [RoomMesh.FRONT])
	# Slim upper flight-status telemetry bar centered cleanly above the screen bezel.
	var bar_y := sc_y + hsh + bw + 0.072
	s.box(Vector3(sc_x, bar_y, fz + back_d + 0.014), Vector3(0.76, 0.068, 0.032), Basis(), [RoomMesh.FRONT])

	# 4. Brushed-titanium aerospace trim: swept brow arch rib, chamfered screen pin-frame, lower zero-G handrail,
	#    thermal grille slats and telemetry instrument bezels.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	var rib_a := PackedVector3Array()
	var rib_b := PackedVector3Array()
	var rib_n := PackedVector3Array()
	for i in rpts.size():
		var p := rpts[i] + rns[i] * (brow_t + 0.012)
		var bz_i := brow_zs[i]
		rib_a.append(Vector3(p.x, p.y, bz_i - 0.058))
		rib_b.append(Vector3(p.x, p.y, bz_i + 0.016))
		rib_n.append(Vector3(rns[i].x, rns[i].y, 0.0))
	u.strip(rib_a, rib_b, rib_n)
	# Outer titanium pin-frame hugging the obsidian picture mask (strictly clear of screen area).
	var fr_z := sc_z - 0.005
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(sc_x + side * (hsw + bw + 0.012), sc_y, fr_z), Vector3(0.024, sh + bw * 2.0 + 0.048, 0.022))
	u.box(Vector3(sc_x, sc_y + hsh + bw + 0.012, fr_z), Vector3(sw + bw * 2.0, 0.024, 0.022))
	u.box(Vector3(sc_x, sc_y - hsh - bw - 0.012, fr_z), Vector3(sw + bw * 2.0, 0.024, 0.022))
	# Sleek titanium deck counter lip + continuous tubular zero-G grab handrail across the lower bulkhead!
	u.box(Vector3(cx, console_h + 0.016, fz + console_d + 0.012), Vector3(foot_w + 0.04, 0.032, 0.042))
	var rail_y := 1.08
	var rail_z := fz + console_d + 0.072
	var rail_w := foot_w - 0.42
	var basis_x := Basis(Vector3.BACK, -PI * 0.5)
	Shapes.cylinder(u, Vector3(cx - rail_w * 0.5, rail_y, rail_z), 0.017, rail_w, 10, basis_x)
	for rx: float in [-1.45, -0.55, 0.55, 1.45]:
		u.box(Vector3(cx + rx, rail_y, fz + console_d + 0.036), Vector3(0.024, 0.026, 0.072))
	# Horizontal titanium thermal diffuser slats across both lower bulkhead intake bays.
	for side: float in [-1.0, 1.0]:
		var gx := cx + side * 0.96
		for k in 6:
			u.box(Vector3(gx, 0.40 + 0.064 * k, fz + console_d + 0.024), Vector3(1.12, 0.013, 0.014))
		# Chamfered titanium bezel frames around both cheek telemetry monitors.
		var dx := cx + side * (cheek_inner + cheek_w * 0.5)
		var mw := cheek_w * 0.76
		for v_s: float in [-1.0, 1.0]:
			u.box(Vector3(dx, sc_y + 0.04 + v_s * 0.246, fz + 0.176), Vector3(mw + 0.024, 0.016, 0.018))
		for h_s: float in [-1.0, 1.0]:
			u.box(Vector3(dx + h_s * (mw * 0.5 + 0.008), sc_y + 0.04, fz + 0.176), Vector3(0.016, 0.49, 0.018))
	# Vermilion-crimson space-age accent stripe inlaid neatly below the screen console counter.
	u.surface(c.soft("plastic", true))
	u.colour = CRIMSON.srgb_to_linear()
	u.box(Vector3(cx, console_h - 0.055, fz + console_d + 0.008), Vector3(foot_w - 0.16, 0.032, 0.016))

	# 5. Recessed glowing spacecraft flight-status telemetry displays (`PieceWindows`, crisp orbital ice-cyan):
	#    pure geometric orbital trajectory horizon bars, velocity ladder ticks, and status indicators (zero text!).
	var gw: Array = c.glows.get("window", [])
	var mon_z := fz + 0.179
	for side: float in [-1.0, 1.0]:
		var dx := cx + side * (cheek_inner + cheek_w * 0.5)
		var mw := cheek_w * 0.68
		# Backlit ice-cyan telemetry screen face inside the obsidian monitor housing.
		gw.append([Vector3(dx, sc_y + 0.04, mon_z), Vector3(mw * 0.5, 0.0, 0.0), Vector3(0.0, 0.195, 0.0), Vector3.BACK])
		# Crisp dark geometric telemetry grid dividers & orbital waveform bars floating cleanly 4 mm proud of glass.
		u.surface(c.soft("plastic", true))
		u.colour = OBSIDIAN.srgb_to_linear()
		u.box(Vector3(dx, sc_y + 0.04, mon_z + 0.004), Vector3(mw * 0.94, 0.012, 0.004))
		u.box(Vector3(dx, sc_y + 0.04, mon_z + 0.004), Vector3(0.010, 0.36, 0.004))
		# Geometric telemetry bar-graph & circular orbital attitude ring (pure shapes, zero text).
		if side < 0.0:
			Shapes.arch(u, Vector3(dx - mw * 0.22, sc_y + 0.135, mon_z + 0.004), 0.052, 0.064, 0.004, 16, Basis(),
					0.0, TAU, ["front"])
			for k in 4:
				var bw_k := mw * (0.14 + 0.06 * ((k * 3 + 1) % 4))
				u.box(Vector3(dx + mw * 0.05 + bw_k * 0.5, sc_y + 0.19 - 0.038 * k, mon_z + 0.004),
						Vector3(bw_k, 0.018, 0.004))
			for k in 5:
				var bh_k := 0.05 + 0.03 * ((k * 2 + 1) % 4)
				u.box(Vector3(dx - mw * 0.34 + 0.058 * k, sc_y - 0.13 + bh_k * 0.5, mon_z + 0.004),
						Vector3(0.032, bh_k, 0.004))
		else:
			# Starboard monitor: cislunar distance progress curve & concentric target rings.
			Shapes.arch(u, Vector3(dx + mw * 0.20, sc_y + 0.135, mon_z + 0.004), 0.034, 0.044, 0.004, 14, Basis(),
					0.0, TAU, ["front"])
			Shapes.arch(u, Vector3(dx + mw * 0.20, sc_y + 0.135, mon_z + 0.004), 0.066, 0.075, 0.004, 18, Basis(),
					0.0, TAU, ["front"])
			for k in 5:
				var tx := dx - mw * 0.36 + 0.075 * k
				var ty := sc_y - 0.09 + 0.045 * sin(float(k) * 0.85)
				u.box(Vector3(tx, ty, mon_z + 0.004), Vector3(0.048, 0.016, 0.004))
		# Small amber / crimson indicator pips tucked below each telemetry bezel.
		for k in 3:
			u.colour = (STATUS_AMBER if k == 0 else (STATUS_CYAN if k == 1 else CRIMSON)).srgb_to_linear()
			u.box(Vector3(dx - 0.10 + 0.10 * k, sc_y - 0.245, fz + 0.178), Vector3(0.036, 0.016, 0.008))
	# Upper center flight-status bar glowing slits (`PieceWindows`).
	for k in 4:
		var sx := sc_x - 0.24 + 0.16 * k
		gw.append([Vector3(sx, bar_y, fz + back_d + 0.032), Vector3(0.056, 0.0, 0.0), Vector3(0.0, 0.018, 0.0),
				Vector3.BACK])
	c.glows["window"] = gw

	# Warm recessed courtesy lenses along the forward console under-lip (`PieceLamps`, house group).
	lit.surface(c.shade(LAMP_GLOW))
	for side: float in [-1.0, 1.0]:
		var lx := cx + side * 0.96
		lit.face([Vector3(lx - 0.42, console_h - 0.11, fz + console_d + 0.004),
				Vector3(lx + 0.42, console_h - 0.11, fz + console_d + 0.004),
				Vector3(lx + 0.42, console_h - 0.08, fz + console_d + 0.004),
				Vector3(lx - 0.42, console_h - 0.08, fz + console_d + 0.004)], Vector3.BACK)

	# 6. Recessed live orbital cove lighting (`PieceCove`, Warm amber / Ice blue / Off, `cove_floor: 0.42`):
	#    swept dome brow wash, flanking vertical picture coves, console wash, and upper cornice cove ribbons!
	cove.surface(c.kit.cove_material())
	var cove_base := Color(0.95, 0.97, 0.99).srgb_to_linear()
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.82)
	var ca := PackedVector3Array()
	var cb := PackedVector3Array()
	var cn := PackedVector3Array()
	for i in range(1, rpts.size() - 1):
		var p := rpts[i] + rns[i] * (brow_t + 0.006)
		var bz_i := brow_zs[i]
		ca.append(Vector3(p.x, p.y, bz_i - 0.24))
		cb.append(Vector3(p.x, p.y, bz_i - 0.062))
		cn.append(Vector3(rns[i].x, rns[i].y, 0.0))
	cove.strip(ca, cb, cn)
	# Flanking vertical picture-surround cove washes & horizontal wash above the forward console deck.
	for side: float in [-1.0, 1.0]:
		var vx := sc_x + side * (hsw + bw + 0.072)
		cove.face([Vector3(vx - 0.028, sc_y - hsh - 0.04, fz + back_d + 0.006),
				Vector3(vx + 0.028, sc_y - hsh - 0.04, fz + back_d + 0.006),
				Vector3(vx + 0.028, sc_y + hsh + 0.04, fz + back_d + 0.006),
				Vector3(vx - 0.028, sc_y + hsh + 0.04, fz + back_d + 0.006)], Vector3.BACK)
	cove.face([Vector3(sc_x - hsw - 0.14, console_h + 0.04, fz + back_d + 0.006),
			Vector3(sc_x + hsw + 0.14, console_h + 0.04, fz + back_d + 0.006),
			Vector3(sc_x + hsw + 0.14, console_h + 0.105, fz + back_d + 0.006),
			Vector3(sc_x - hsw - 0.14, console_h + 0.105, fz + back_d + 0.006)], Vector3.BACK)
	# Continuous upper cornice cove ribbons along both leaning side walls just beneath the glazed canopy springing!
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.70)
	for side: float in [-1.0, 1.0]:
		var wy0 := wall_h - 0.088
		var wy1 := wall_h - 0.056
		var x0 := _wall_x(q, side, wy0) - side * 0.048
		var x1 := _wall_x(q, side, wy1) - side * 0.048
		var n := Cabin._n(q, side)
		var p0 := Vector3(x0, wy0, brow_side_z + 0.04)
		var p1 := Vector3(x0, wy0, bz - 0.18)
		var p2 := Vector3(x1, wy1, bz - 0.18)
		var p3 := Vector3(x1, wy1, brow_side_z + 0.04)
		if side < 0.0:
			cove.face([p0, p1, p2, p3], n)
		else:
			cove.face([p1, p0, p3, p2], n)
	cove.colour = Color.WHITE
	s.colour = Color.WHITE
	u.colour = Color.WHITE

	# Clean physics collision box for the forward console (strictly inside cabin, > 3.8 m from viewer's seat).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, console_h * 0.5, console_z),
			Vector3(foot_w, console_h, console_d), Basis()))


## Continuous leaning-wall brushed-titanium viewport sill ledges, recessed thermal diffusers, ribbed titanium pier
## collars, warm recessed bulkhead reading sconces (`PieceLamps`, `bake_lamps: 2`), and curved zero-G handrail loops!
static func _viewport_ledges_and_rails(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var sill := float(q["window_sill"])
	var marks: Array[float] = Cabin._bay_marks(q)
	var z0 := fz + 0.34
	var z1 := bz - 0.18
	var span := z1 - z0
	var mid_z := (z0 + z1) * 0.5
	var shelf_d := 0.125

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit

	# 1. Slate-obsidian rubberised viewport sill top decks & low cabin floor thermal diffuser plinths.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_PANEL.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var wx_sill := _wall_x(q, side, sill - 0.02)
		var wx_low := _wall_x(q, side, 0.16)
		s.box(Vector3(wx_sill - side * (shelf_d * 0.5), sill - 0.02, mid_z), Vector3(shelf_d - 0.012, 0.028, span))
		s.box(Vector3(wx_low - side * 0.036, 0.16, mid_z), Vector3(0.064, 0.24, span - 0.36), Basis(), [RoomMesh.DOWN])

	# 2. Gleaming brushed-titanium aerospace sill rails, structural rib gussets, thermal grille fins & zero-G loops.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
	for side: float in [-1.0, 1.0]:
		var wx_sill := _wall_x(q, side, sill - 0.024)
		var edge_x := wx_sill - side * shelf_d
		# Chamfered brushed-titanium sill bullnose rail + twin longitudinal spacecraft hull flutes.
		u.box(Vector3(edge_x, sill - 0.024, mid_z), Vector3(0.024, 0.038, span + 0.02))
		u.box(Vector3(edge_x + side * 0.01, sill - 0.062, mid_z), Vector3(0.016, 0.014, span))
		# Continuous brushed-titanium floor kick-rail & thermal grille fins along the lower hull curve.
		var wx_low := _wall_x(q, side, 0.16)
		u.box(Vector3(wx_low - side * 0.072, 0.052, mid_z), Vector3(0.012, 0.088, span - 0.32), Basis(), [RoomMesh.DOWN])
		for k in 3:
			u.box(Vector3(wx_low - side * 0.072, 0.13 + 0.052 * k, mid_z), Vector3(0.012, 0.012, span - 0.44))
		# Sculpted titanium rib brackets under every structural pier + recessed sconce housings & zero-G handrail loops!
		for mz: float in marks:
			if mz > z0 + 0.12 and mz < z1 - 0.12:
				u.box(Vector3(wx_sill - side * (shelf_d * 0.48), sill - 0.095, mz),
						Vector3(shelf_d * 0.88, 0.075, 0.048))
				# Sleek chamfered brushed-titanium cabin sconce pod at y = 1.98 on each interior pier between viewports.
				var wx_hi := _wall_x(q, side, 1.96)
				u.colour = TITANIUM.srgb_to_linear()
				u.rounded_box(Vector3(wx_hi - side * 0.042, 1.96, mz), Vector3(0.064, 0.21, 0.115), 0.018,
						Transform3D(), 1)
				u.colour = TITANIUM_DARK.srgb_to_linear()
				u.box(Vector3(wx_hi - side * 0.058, 2.045, mz), Vector3(0.056, 0.022, 0.122))
				u.box(Vector3(wx_hi - side * 0.058, 1.875, mz), Vector3(0.056, 0.022, 0.122))
				# Curved vertical zero-G tubular handrail loop mounted cleanly on the interior piers (y = 1.12..1.66)!
				if mz > fz + 1.5 and mz < bz - 0.6:
					var wx_mid := _wall_x(q, side, 1.38)
					var gx := wx_mid - side * 0.092
					u.colour = TITANIUM.srgb_to_linear()
					Shapes.cylinder(u, Vector3(gx, 1.14, mz), 0.014, 0.50, 8)
					for gy: float in [1.14, 1.64]:
						u.box(Vector3(_wall_x(q, side, gy) - side * 0.052, gy, mz), Vector3(0.096, 0.022, 0.024))
					# Tactile dark silicone zero-G grip sleeve wrapped around the middle of each pier grab-loop.
					u.surface(c.soft("plastic", true))
					u.colour = GRIP_DARK.srgb_to_linear()
					Shapes.cylinder(u, Vector3(gx, 1.24, mz), 0.017, 0.30, 8)
					u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
					u.colour = TITANIUM.srgb_to_linear()
		# Continuous sleek zero-G grab-bar along the upper sill edge of each bay (clear of windows).
		var wx_rail := _wall_x(q, side, sill + 0.035)
		Shapes.cylinder(u, Vector3(wx_rail - side * 0.095, sill + 0.035, z0 + 0.25), 0.013, span - 0.5, 8, basis_z)

		# Clean physics box enclosing each side sill ledge (strictly inside cabin, >= 1.15 m from viewer's seat).
		c.shapes.append(PhysicsShapes.box(Vector3(wx_sill - side * (shelf_d * 0.5), sill - 0.025, mid_z),
				Vector3(shelf_d, 0.075, span), Basis()))

	# 3. Recessed warm-ivory spacecraft sconce light diffusers tucked cleanly under the titanium pier hoods (`PieceLamps`).
	lit.surface(c.shade(LAMP_GLOW))
	for mz: float in marks:
		if mz > z0 + 0.12 and mz < z1 - 0.12:
			for side: float in [-1.0, 1.0]:
				var wx_l := _wall_x(q, side, 1.96)
				var lx := wx_l - side * 0.076
				var n := Cabin._n(q, side)
				var p0 := Vector3(lx, 1.895, mz - 0.038)
				var p1 := Vector3(lx, 1.895, mz + 0.038)
				var p2 := Vector3(lx, 2.025, mz + 0.038)
				var p3 := Vector3(lx, 2.025, mz - 0.038)
				if side < 0.0:
					lit.face([p0, p1, p2, p3], n)
				else:
					lit.face([p1, p0, p3, p2], n)
				# Register the two middle-cabin sconces for lightmap baking & soft cabin stand-in fill (`bake_lamps: 2`).
				if absf(mz - 0.06) < 0.2:
					c.lamps.append([Vector3(lx - side * 0.12, 1.92, mz), LAMP_GLOW, 0.78])
	# Also ensure cabin centerline x has clean reference for subtle floor-edge cove trim along the aft vestibule.
	var _unused_cx := cx
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Rear bulkhead: iconic circular spacecraft pressure airlock hatch with bolted titanium collar ring, 8 radial clamp
## lugs, recessed domed hatch door leaf, central manual locking wheel, glowing circular docking status ring & viewport
## (`PieceWindows`), flanking zero-G grab-handles, aft arch rib, and working mission chronometer (`PieceClock`).
static func _aft_airlock_and_clock(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var basis_aft := Basis(Vector3.UP, PI) # local +Z faces world -Z (into cabin)

	# 1. Circular spacecraft pressure airlock hatch centered on the aft bulkhead (radius 0.84 m, center y = 1.12 m).
	var air_y := 1.12
	var air_r := 0.84
	var air_z := bz - 0.042
	# Outer dark-slate recessed pressure frame backing plate & lower threshold step apron.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_PANEL.srgb_to_linear()
	s.box(Vector3(cx, 0.14, bz - 0.045), Vector3(1.56, 0.28, 0.09), Basis(), [RoomMesh.DOWN, RoomMesh.BACK])
	# Brushed-titanium heavy circular pressure bulkhead collar ring (`Shapes.arch`, full 360°!).
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, air_y, air_z), air_r - 0.12, air_r, 0.088, 28, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Inner dark-titanium chamfered seal ring & 8 radial pressure clamp lugs around the circumference.
	u.colour = TITANIUM_DARK.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, air_y, air_z - 0.012), air_r - 0.17, air_r - 0.115, 0.055, 24, basis_aft, 0.0, TAU,
			["front", "inner"])
	for k in 8:
		var ang := TAU * float(k) / 8.0 + PI / 8.0
		var lr := air_r - 0.055
		var pos := Vector3(cx + cos(ang) * lr, air_y + sin(ang) * lr, air_z - 0.048)
		u.box(pos, Vector3(0.088, 0.046, 0.042), Basis(Vector3.BACK, ang))
	# Vermilion-crimson retro-future safety alignment chevrons at 12, 3, 6 and 9 o'clock on the collar!
	u.surface(c.soft("plastic", true))
	u.colour = CRIMSON.srgb_to_linear()
	for k in 4:
		var ang := PI * 0.5 * float(k)
		var tr := air_r - 0.058
		u.box(Vector3(cx + cos(ang) * tr, air_y + sin(ang) * tr, air_z - 0.046),
				Vector3(0.072, 0.032, 0.014), Basis(Vector3.BACK, ang))
	# Recessed domed ivory composite airlock hatch door leaf (lathed smoothly toward the cabin along -Z!).
	u.colour = IVORY_WARM.srgb_to_linear()
	var hatch_basis := Basis(Vector3.RIGHT, -PI * 0.5) # lathe +Y -> world -Z!
	Shapes.lathe(u, [Vector2(0.67, 0.0), Vector2(0.67, 0.04), Vector2(0.54, 0.078), Vector2(0.28, 0.095),
			Vector2(0.22, 0.095)], Vector3(cx, air_y, bz - 0.025), 24, hatch_basis)
	# Central dark-obsidian recessed docking porthole bezel & circular brushed-titanium manual locking wheel!
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, air_y, bz - 0.132), 0.19, 0.24, 0.036, 20, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Three radial titanium locking spokes around a sleek offset locking hub below the central docking porthole.
	var wheel_y := air_y - 0.36
	var wheel_z := bz - 0.115
	Shapes.arch(u, Vector3(cx, wheel_y, wheel_z), 0.105, 0.135, 0.026, 18, basis_aft, 0.0, TAU,
			["front", "back", "inner", "outer"])
	for k in 3:
		var a := TAU * float(k) / 3.0 + PI / 6.0
		u.box(Vector3(cx + cos(a) * 0.06, wheel_y + sin(a) * 0.06, wheel_z), Vector3(0.11, 0.020, 0.018),
				Basis(Vector3.BACK, a))
	Shapes.lathe(u, [Vector2(0.038, 0.0), Vector2(0.038, 0.045), Vector2(0.022, 0.058), Vector2(0.0, 0.062)],
			Vector3(cx, wheel_y, bz - 0.095), 10, hatch_basis)

	# Glowing ice-cyan circular airlock docking status viewport & twin docking-lock indicator bars (`PieceWindows`).
	var gw: Array = c.glows.get("window", [])
	gw.append([Vector3(cx, air_y, bz - 0.135), Vector3(-0.17, 0.0, 0.0), Vector3(0.0, 0.17, 0.0), Vector3.FORWARD])
	for side: float in [-1.0, 1.0]:
		gw.append([Vector3(cx + side * 0.56, air_y + 0.54, bz - 0.044), Vector3(-0.068, 0.0, 0.0),
				Vector3(0.0, 0.022, 0.0), Vector3.FORWARD])
	c.glows["window"] = gw
	# Crosshair alignment reticle floating cleanly 4 mm proud of the airlock docking viewport (pure geometry).
	u.surface(c.soft("plastic", true))
	u.colour = OBSIDIAN.srgb_to_linear()
	u.box(Vector3(cx, air_y, bz - 0.139), Vector3(0.32, 0.012, 0.004))
	u.box(Vector3(cx, air_y, bz - 0.139), Vector3(0.012, 0.32, 0.004))
	Shapes.arch(u, Vector3(cx, air_y, bz - 0.139), 0.088, 0.102, 0.005, 16, basis_aft, 0.0, TAU, ["front"])

	# Twin brushed-titanium zero-G grab-handles flanking the circular airlock collar!
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var hx := cx + side * (air_r + 0.11)
		Shapes.cylinder(u, Vector3(hx, 0.88, bz - 0.092), 0.016, 0.54, 8)
		for hy: float in [0.88, 1.42]:
			u.box(Vector3(hx, hy, bz - 0.048), Vector3(0.026, 0.026, 0.09))
		u.surface(c.soft("plastic", true))
		u.colour = GRIP_DARK.srgb_to_linear()
		Shapes.cylinder(u, Vector3(hx, 0.99, bz - 0.092), 0.019, 0.32, 8)
		u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
		u.colour = TITANIUM.srgb_to_linear()

	# 2. Working Mission Chronometer (`PieceClock`, live wall time) centered high above the airlock hatch!
	var clk_y := 2.34
	var clk_r := 0.20
	var clk_z := bz - 0.048
	Shapes.arch(u, Vector3(cx, clk_y, clk_z), clk_r, clk_r + 0.042, 0.062, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Sleek horizontal brushed-titanium aerospace wing-bars flanking the mission chronometer.
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var wl := 0.42 - 0.09 * k
			u.box(Vector3(cx + side * (clk_r + 0.06 + wl * 0.5), clk_y + (k - 1) * 0.052, bz - 0.028),
					Vector3(wl, 0.018, 0.022))
	c.clocks.append([Vector3(cx, clk_y, bz - 0.072), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# 3. Curved brushed-titanium aft canopy crown rib + soft circular cove halo ringing the airlock bulkhead!
	var roof: Array = Cabin._roof(q)
	var rpts: PackedVector2Array = roof[0]
	var rns: PackedVector2Array = roof[1]
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	var rn := PackedVector3Array()
	for i in rpts.size():
		var p := rpts[i] + rns[i] * 0.032
		ra.append(Vector3(p.x, p.y, bz - 0.075))
		rb.append(Vector3(p.x, p.y, bz - 0.005))
		rn.append(Vector3(rns[i].x, rns[i].y, 0.0))
	u.strip(ra, rb, rn)

	cove.surface(c.kit.cove_material())
	var cove_base := Color(0.95, 0.97, 0.99).srgb_to_linear()
	cove.colour = Color(cove_base.r, cove_base.g, cove_base.b, 0.72)
	Shapes.arch(cove, Vector3(cx, air_y, bz - 0.018), air_r + 0.006, air_r + 0.056, 0.008, 28, basis_aft, 0.0, TAU,
			["front"])
	cove.colour = Color.WHITE
	s.colour = Color.WHITE
	u.colour = Color.WHITE

	# Clean physics collision box for the circular airlock collar (strictly inside cabin, > 3.2 m from viewer's seat).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, air_y, bz - 0.075), Vector3(1.84, 1.84, 0.14), Basis()))


# --- Space-age lounge recliner rows & aft cislunar trajectory/service consoles ----------------------------------------

static func _console_and_rows(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_recliner_rows(c, q)
	_trajectory_console(c, q)
	_service_credenza(c, q)


## Sculpted ivory-composite & brushed-titanium shared recliner armrests (`Seats.RECLINER_ARM`, keeping both around the
## viewer's folded seat), contoured ivory headrest shells hugging `seats.gd _recliner`'s exact curve, tubular titanium
## zero-G seatback grab-handles, and low aisle floor-guide strips (`PieceCove`).
static func _recliner_rows(c: Object, q: Dictionary) -> void:
	var slots: Array = Cabin.seat_slots_for(c.builder_params)
	if slots.is_empty():
		return
	var cx := float(q["cx"])
	var pitch := float(q["seat_pitch"])
	var arm_w := Seats.RECLINER_ARM
	var arm_h := 0.57
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
				if absf(ax - cx) < float(q["aisle"]) * 0.5 + 0.14:
					aisle_arms.append([Vector3(ax, o.y, o.z), -1.0 if ax > cx else 1.0])

	# 1. Moulded space-age ivory composite armrest pedestals with contoured obsidian-charcoal padded arm-caps.
	u.surface(c.soft("plastic", true))
	for at: Vector3 in arm_places.values():
		u.colour = IVORY_SHELL.srgb_to_linear()
		u.box(at + Vector3(0.0, arm_h * 0.5, arm_z), Vector3(arm_w, arm_h, arm_d), Basis(), [RoomMesh.DOWN])
		u.colour = GRIP_DARK.srgb_to_linear()
		u.rounded_box(Vector3.ZERO, Vector3(arm_w + 0.012, 0.044, arm_d + 0.024), 0.016,
				Transform3D(Basis(), at + Vector3(0.0, arm_h + 0.018, arm_z - 0.01)), 1, Vector3i.ZERO, 0.0,
				[RoomMesh.DOWN])
		# Tiny glowing amber/cyan cabin-control rocker pips inlaid on top of each armrest console.
		u.colour = STATUS_CYAN.srgb_to_linear()
		u.box(at + Vector3(-0.022, arm_h + 0.045, arm_z - arm_d * 0.30), Vector3(0.018, 0.008, 0.022))
		u.colour = STATUS_AMBER.srgb_to_linear()
		u.box(at + Vector3(0.022, arm_h + 0.045, arm_z - arm_d * 0.30), Vector3(0.018, 0.008, 0.022))

	# 2. Brushed-titanium armrest hardware: curved waterfall front nose bumper, recessed side trim bars & control plate.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	for at: Vector3 in arm_places.values():
		u.rounded_box(Vector3.ZERO, Vector3(arm_w + 0.008, arm_h * 0.82, 0.036), 0.014,
				Transform3D(Basis(), at + Vector3(0.0, arm_h * 0.52, arm_z - arm_d * 0.5 - 0.006)), 1)
		for sy: float in [0.24, 0.38]:
			u.box(at + Vector3(0.0, sy, arm_z), Vector3(arm_w + 0.012, 0.015, arm_d * 0.84))
		u.box(at + Vector3(0.0, arm_h + 0.042, arm_z - arm_d * 0.28), Vector3(0.088, 0.006, 0.095))

	# 3. Solid inner-shell cradle face closing off `seats.gd _recliner`'s open front shell lip (so no hollow wireframe
	#    rim shows from the front!), plus crisp contoured ivory woven headrest pads hugging `seats.gd _recliner`'s exact
	#    curve (`bend = -0.35`, `radius = 0.062`) cleanly proud of the crimson pillow envelope.
	var wi := pitch - arm_w - 0.01
	u.surface(c.soft("plastic", true))
	u.colour = Color(0.68, 0.71, 0.75).srgb_to_linear()
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		# Closed curved inner shell liner sitting strictly inside `seats.gd _recliner`'s outer shell silhouette.
		u.rounded_box(Vector3(0.0, 0.37, 0.062), Vector3(wi + 0.014, 0.90, 0.022), 0.01, t_world, 1,
				Vector3i(2, 1, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK, RoomMesh.UP, RoomMesh.LEFT, RoomMesh.RIGHT])
	u.surface(c.soft("cloth", true))
	u.colour = IVORY_SHELL.srgb_to_linear()
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.rounded_box(Vector3(0.0, 0.649, -0.011), Vector3(wi - 0.14, 0.256, 0.156), 0.062, t_world, 1,
				Vector3i(2, 0, 0), -0.35, [RoomMesh.DOWN, RoomMesh.BACK])

	# 4. Tubular brushed-titanium zero-G seatback grab-handles across the back of every recliner shell.
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	var grab_w := wi - 0.12
	for sl: Dictionary in slots:
		var xf: Transform3D = sl["transform"]
		if xf.origin.length() < 0.05:
			continue
		var t_world := xf * tilt
		u.box(t_world * Vector3(0.0, 0.58, 0.150), Vector3(grab_w, 0.022, 0.022), t_world.basis)
		for side: float in [-1.0, 1.0]:
			u.box(t_world * Vector3(side * (grab_w * 0.5 - 0.012), 0.58, 0.128), Vector3(0.022, 0.024, 0.038),
					t_world.basis)

	# 5. Low aisle floor-guide strips along the aisle-facing base of the aisle armrests (`PieceCove`, live colour).
	cove.surface(c.kit.cove_material())
	var strip_col := Color(0.95, 0.97, 0.99).srgb_to_linear()
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


## Aft-port cislunar free-return trajectory console: angled retro-future ivory composite navigation pedestal housing a
## glowing backlit display (`PieceWindows`) overlaid with a 3D sculpted Earth-to-Moon transit loop (Earth disc, Moon
## disc, golden orbital transfer arcs, and crimson ferry marker pip). Stands cleanly along the aft-port bulkhead flank!
static func _trajectory_console(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var con_x := cx - 1.54 # ~-2.36 m, cleanly clear of the circular airlock collar & inside the port wall!
	var con_z := bz - 0.52 # ~+2.88 m, nicely framed beneath Port Bay 3 and well behind row -1 (z = +1.42)!
	var con_w := 0.86
	var con_d := 0.58
	var desk_h := 0.78

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# 1. Sculpted ivory-composite angled console pedestal standing on a recessed dark slate plinth.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_PANEL.srgb_to_linear()
	s.box(Vector3(con_x, 0.06, con_z), Vector3(con_w - 0.08, 0.12, con_d - 0.08), Basis(), [RoomMesh.DOWN])
	s.surface(c.tinted("plastic"))
	s.colour = IVORY_SHELL.srgb_to_linear()
	s.box(Vector3(con_x, 0.44, con_z), Vector3(con_w, 0.66, con_d), Basis(), [RoomMesh.DOWN])
	# Raised sloped instrument hood facing forward-inward toward the passenger aisle (facing -Z, tilted 32° upward).
	var hood_y := desk_h + 0.17
	var tilt_rad := deg_to_rad(32.0)
	var screen_n := Vector3(0.0, sin(tilt_rad), -cos(tilt_rad)).normalized() # faces into cabin (-Z) & 32 deg upward
	var screen_u := Vector3.LEFT # rightward when facing the aft console (+Z)
	var screen_v := screen_n.cross(screen_u).normalized() # upward-and-aft along the sloped display face
	var disp_b := Basis(screen_u, screen_v, screen_n)
	# Rear enclosure block tucked cleanly behind the sloped display panel.
	s.box(Vector3(con_x, hood_y + 0.01, con_z + 0.14), Vector3(con_w, 0.36, 0.24), Basis(), [RoomMesh.DOWN])

	# Dark-obsidian recessed display housing & brushed-titanium perimeter bezel frame.
	s.surface(c.tinted("iron"))
	s.colour = OBSIDIAN.srgb_to_linear()
	var face_c := Vector3(con_x, hood_y + 0.04, con_z - 0.03)
	s.box(face_c - screen_n * 0.022, Vector3(con_w - 0.04, 0.40, 0.045), disp_b)
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	# Front counter bullnose & titanium display perimeter frame.
	u.box(Vector3(con_x, desk_h + 0.012, con_z - con_d * 0.5 - 0.01), Vector3(con_w + 0.02, 0.026, 0.032))
	for v_s: float in [-1.0, 1.0]:
		u.box(face_c + screen_v * (v_s * 0.195), Vector3(con_w - 0.02, 0.018, 0.024), disp_b)
	for h_s: float in [-1.0, 1.0]:
		u.box(face_c + screen_u * (h_s * (con_w * 0.5 - 0.02)), Vector3(0.018, 0.40, 0.024), disp_b)

	# 2. Glowing backlit ice-cyan orbital navigation chart (`PieceWindows`) + 3D Earth–Moon cislunar transit loop!
	var gw: Array = c.glows.get("window", [])
	var map_c := face_c + screen_n * 0.005
	gw.append([map_c, screen_u * (con_w * 0.5 - 0.055), screen_v * 0.165, screen_n])
	c.glows["window"] = gw

	# Sculpted Earth disc (left), Moon disc (right), golden cislunar transit curve & crimson ferry marker!
	var earth_p := map_c - screen_u * 0.22 - screen_v * 0.01 + screen_n * 0.004
	var moon_p := map_c + screen_u * 0.24 + screen_v * 0.02 + screen_n * 0.004
	var disc_b := Basis(screen_u, screen_n, -screen_v) # right-handed: lathe +Y along screen_n!
	u.surface(c.soft("plastic", true))
	u.colour = EARTH_BLUE.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.072, 0.0), Vector2(0.072, 0.008), Vector2(0.0, 0.012)], earth_p, 16, disc_b)
	u.colour = EARTH_LAND.srgb_to_linear()
	u.box(earth_p + screen_u * 0.015 + screen_v * 0.014 + screen_n * 0.009, Vector3(0.048, 0.032, 0.006), disp_b)
	u.box(earth_p - screen_u * 0.024 - screen_v * 0.016 + screen_n * 0.009, Vector3(0.038, 0.024, 0.006), disp_b)
	u.colour = MOON_SILVER.srgb_to_linear()
	Shapes.lathe(u, [Vector2(0.034, 0.0), Vector2(0.034, 0.008), Vector2(0.0, 0.011)], moon_p, 14, disc_b)
	# Sweeping golden free-return cislunar trajectory curve (outbound upper arc + return lower arc)!
	u.colour = ORBIT_GOLD.srgb_to_linear()
	var prev_hi := Vector3.ZERO
	var prev_lo := Vector3.ZERO
	var steps := 14
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x_arc := lerpf(-0.22, 0.24, t)
		# Smooth pinched loop crossing cleanly at the Earth-Moon gravity saddle (t ~ 0.66).
		var y_hi := 0.105 * sin(t * PI) * cos((t - 0.12) * PI * 0.85) + 0.022 * t
		var y_lo := -0.095 * sin(t * PI) * cos((t - 0.12) * PI * 0.85) + 0.018 * t
		var p_hi := map_c + screen_u * x_arc + screen_v * y_hi + screen_n * 0.007
		var p_lo := map_c + screen_u * x_arc + screen_v * y_lo + screen_n * 0.007
		if i > 0:
			Shapes.beam(u, prev_hi, p_hi, Vector2(0.008, 0.006), screen_n)
			Shapes.beam(u, prev_lo, p_lo, Vector2(0.006, 0.005), screen_n)
		prev_hi = p_hi
		prev_lo = p_lo
	# Glowing vermilion-crimson ferry position diamond right along the outbound cislunar arc!
	u.colour = CRIMSON.srgb_to_linear()
	var ship_p := map_c + screen_u * 0.02 + screen_v * 0.068 + screen_n * 0.012
	u.box(ship_p, Vector3(0.024, 0.024, 0.010), disp_b * Basis(Vector3.BACK, PI * 0.25))

	# Tactile row of space-age indicator keys beneath the display bezel.
	for k in 6:
		u.colour = (STATUS_AMBER if k % 3 == 0 else (STATUS_CYAN if k % 3 == 1 else IVORY_WARM)).srgb_to_linear()
		u.box(Vector3(con_x - 0.25 + 0.10 * k, desk_h + 0.024, con_z - con_d * 0.36), Vector3(0.056, 0.018, 0.044))

	# Clean physics collision box enclosing the aft-port trajectory console (strictly inside cabin, > 3.1 m from seat).
	c.shapes.append(PhysicsShapes.box(Vector3(con_x, 0.60, con_z), Vector3(con_w, 1.20, con_d + 0.04), Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Aft-starboard zero-G cabin service credenza: sculpted ivory cabinet, recessed magnetic tray deck with brushed-
## titanium zero-G retaining rails, and twin lathed brushed-titanium & crimson thermal beverage carafes.
static func _service_credenza(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var cr_x := cx + 1.54 # ~+0.72 m, cleanly clear of the airlock collar & inside the starboard wall!
	var cr_z := bz - 0.52 # ~+2.88 m, symmetric to the aft-port trajectory console!
	var cr_w := 0.86
	var cr_d := 0.58
	var top_y := 0.84

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# 1. Ivory-composite zero-G service cabinet on recessed dark-slate base plinth.
	s.surface(c.tinted("iron"))
	s.colour = SLATE_PANEL.srgb_to_linear()
	s.box(Vector3(cr_x, 0.06, cr_z), Vector3(cr_w - 0.08, 0.12, cr_d - 0.08), Basis(), [RoomMesh.DOWN])
	s.surface(c.tinted("plastic"))
	s.colour = IVORY_SHELL.srgb_to_linear()
	s.box(Vector3(cr_x, 0.48, cr_z), Vector3(cr_w, 0.72, cr_d), Basis(), [RoomMesh.DOWN])
	# Recessed dark magnetic countertop pad + cabinet drawer recess seams.
	s.surface(c.tinted("iron"))
	s.colour = OBSIDIAN.srgb_to_linear()
	s.box(Vector3(cr_x, top_y + 0.008, cr_z), Vector3(cr_w - 0.08, 0.016, cr_d - 0.08), Basis(), [RoomMesh.DOWN])
	for dy: float in [0.34, 0.58]:
		s.box(Vector3(cr_x, dy, cr_z - cr_d * 0.5 - 0.004), Vector3(cr_w - 0.12, 0.012, 0.010))

	# 2. Brushed-titanium zero-G countertop retaining gallery rail, recessed drawer pulls & twin thermal carafes!
	u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
	u.colour = TITANIUM.srgb_to_linear()
	var basis_x := Basis(Vector3.BACK, -PI * 0.5)
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
	var rail_y := top_y + 0.072
	Shapes.cylinder(u, Vector3(cr_x - cr_w * 0.44, rail_y, cr_z - cr_d * 0.44), 0.010, cr_w * 0.88, 8, basis_x)
	for side: float in [-1.0, 1.0]:
		Shapes.cylinder(u, Vector3(cr_x + side * cr_w * 0.44, rail_y, cr_z - cr_d * 0.44), 0.010, cr_d * 0.88, 8,
				basis_z)
		for pz: float in [cr_z - cr_d * 0.44, cr_z + cr_d * 0.44]:
			Shapes.cylinder(u, Vector3(cr_x + side * cr_w * 0.44, top_y, pz), 0.010, 0.074, 8)
	# Sleek flush titanium drawer handles on the credenza front.
	for dy: float in [0.44, 0.68]:
		u.box(Vector3(cr_x, dy, cr_z - cr_d * 0.5 - 0.014), Vector3(0.24, 0.020, 0.022))

	# Twin sleek lathed retro-future thermal beverage carafes docked magnetically on the credenza deck!
	for k in 2:
		var fx := cr_x - 0.18 + 0.36 * k
		var fz_c := cr_z + 0.04
		var base_at := Vector3(fx, top_y + 0.016, fz_c)
		u.surface(c.shiny("chrome", 0.94, 0.80, 0.12))
		u.colour = TITANIUM.srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.068, 0.0), Vector2(0.072, 0.025), Vector2(0.058, 0.19), Vector2(0.044, 0.25),
				Vector2(0.052, 0.27)], base_at, 12)
		# Vermilion-crimson / slate space-age thermal lid dome & magnetic docking ring!
		u.surface(c.soft("plastic", true))
		u.colour = (CRIMSON if k == 0 else SLATE_PANEL).srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.052, 0.268), Vector2(0.050, 0.295), Vector2(0.024, 0.312), Vector2(0.0, 0.316)],
				base_at, 10)
		u.colour = GRIP_DARK.srgb_to_linear()
		u.box(base_at + Vector3(0.0, 0.14, 0.072), Vector3(0.020, 0.14, 0.032))

	# Clean physics collision box enclosing the aft-starboard service credenza (strictly inside cabin, > 2.4 m from seat).
	c.shapes.append(PhysicsShapes.box(Vector3(cr_x, 0.54, cr_z), Vector3(cr_w, 1.08, cr_d + 0.04), Basis()))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


# --- Helpers ----------------------------------------------------------------------------------------------------------

## Inner X coordinate of side s's leaning wall (-1 port, +1 starboard) at world height y.
static func _wall_x(q: Dictionary, side: float, y: float) -> float:
	return float(q["cx"]) + side * (float(q["hw"]) - y * tan(float(q["L"])))


## Roof height of the cabin's arched glass canopy at world x.
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
