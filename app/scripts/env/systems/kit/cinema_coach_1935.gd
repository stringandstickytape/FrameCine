extends RefCounted

## Cinema coach 1935 (docs/environments/rooms/cinema_coach_1935.md): a 1935 express newsreel railway cinema carriage
## dressed over a narrow `cabin` builder (`carriage`, arched elliptical roof, five rounded-corner windows a side,
## twenty plush tip-up velvet cinema seats across a central aisle). Built by Gemini 4 Neon Extra High. Everything is
## ours, drawn from boxes, strips, arches and lathed profiles; no people, no real railway or film trademarks.
##
##   coach_1935_interior   the carriage's 1935 wood-and-brass craft:
##                         - Art Deco streamlined mahogany & brass rear-projection screen surround with curved glowing
##                           brass-hooded cove valance (`PieceCove`, live Lighting setting, `cove_floor` 0.55 so it
##                           glows warmly even inside the dark railway tunnel), pleated claret velvet proscenium tabs,
##                           slotted brass loudspeaker apron and sunburst brass crest
##                         - ornate continuous polished-brass and woven-cord netting overhead luggage racks along both
##                           window walls with Art Deco cantilever brackets and cornice uplight coves (`PieceCove`)
##                         - partly drawn holland-cloth carriage window blinds in mahogany top boxes with gleaming brass
##                           bottom battens and crimson tassel pulls in every window
##                         - turned brass coat hooks on mahogany wall plaques and continuous brass emergency
##                           communication cord chain with signal-red pull tags above the windows
##                         - under-sill cast-iron steam heater pipe guards and crown ceiling Art Deco brass ventilators
##                         - wood-panelled aft vestibule door dressed with a frosted-glass brass security grille,
##                           kick-plate and push-bar, framed geometric route-map plaques, and a working 1935 railway
##                           brass bulkhead clock (`PieceClock`)
##   coach_1935_lamps      hanging brass-and-opal-glass carriage lamps suspended cleanly along the luggage racks (built
##                         per side via `at.x` < -0.5 or > 0.5 so each side's `motion` `sway` group pivots right at its
##                         own brass rack rail with zero detachment as the express sways gently under way).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")

const PIECES: Array[String] = ["coach_1935_interior", "coach_1935_lamps"]

## Palette (sRGB): 1935 express mahogany, polished railway brass, holland blind cloth, claret velvet, signal enamel.
const MAHOGANY := Color(0.28, 0.12, 0.07)
const MAHOGANY_DARK := Color(0.18, 0.075, 0.045)
const MAHOGANY_TRIM := Color(0.35, 0.16, 0.09)
const BRASS := Color(0.92, 0.73, 0.34)
const IRON_DARK := Color(0.12, 0.115, 0.11)
const CLARET_VELVET := Color(0.42, 0.075, 0.1)
const BLIND_CLOTH := Color(0.76, 0.68, 0.52)
const NET_CORD := Color(0.78, 0.69, 0.5)
const SIGNAL_RED := Color(0.76, 0.1, 0.09)
const PARCHMENT := Color(0.84, 0.78, 0.64)
const COVE_PLASTER := Color(0.92, 0.87, 0.78)
const LAMP_GLOW := Color(1.0, 0.84, 0.56)

## Exact horizontal offset from cabin centreline and height of the luggage rack lower lamp-suspension brass rod.
const RACK_RAIL_DX := 1.38
const RACK_RAIL_Y := 2.02


static func build(piece: String, c: Object, xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"coach_1935_interior":
			_interior(c)
		"coach_1935_lamps":
			_lamps(c, xf)


# --- The 1935 cinema coach interior -----------------------------------------------------------------------------------

static func _interior(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_proscenium(c, q)
	_luggage_racks(c, q)
	_window_blinds_and_hardware(c, q)
	_ceiling_and_heaters(c, q)
	_aft_vestibule(c, q)


## 1930s Art Deco streamlined mahogany & brass rear-projection screen surround with curved glowing brass-hooded cove
## valance (PieceCove), pleated claret velvet proscenium tabs, recessed brass speaker apron and sunburst crest.
static func _proscenium(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(2.24, 1.26))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var sz := sc_xf.origin.z
	var hw_s := sc_sz.x * 0.5
	var hh_s := sc_sz.y * 0.5
	var bot_y := cy - hh_s
	var top_y := cy + hh_s
	var fz := float(q["front_z"])
	var hw := float(q["hw"])
	var wall_h := float(q["wall_height"])

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# --- Stepped streamlined mahogany surround casing & lower speaker console ---
	s.surface(c.tinted("wood"))
	var casing_d := maxf(sz - fz - 0.006, 0.1)
	var casing_z := fz + casing_d * 0.5
	# Lower rear-projection console & horn-speaker wainscot below the screen (y 0..bot_y), stepping forward gracefully.
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.06, fz + 0.13), Vector3(hw * 2.0 - 0.04, 0.12, 0.26), Basis(), [RoomMesh.DOWN, RoomMesh.FRONT])
	s.colour = MAHOGANY.srgb_to_linear()
	s.box(Vector3(cx, (0.12 + bot_y) * 0.5, fz + 0.115), Vector3(hw * 2.0 - 0.08, bot_y - 0.12, 0.23),
			Basis(), [RoomMesh.FRONT])
	# Streamlined stepped top sill shelf directly beneath the picture.
	s.colour = MAHOGANY_TRIM.srgb_to_linear()
	s.box(Vector3(cx, bot_y - 0.025, fz + 0.135), Vector3(sc_sz.x + 0.28, 0.05, 0.27), Basis(), [RoomMesh.FRONT])

	# Stepped mahogany flanking piers either side of the screen (inner setback + outer streamlined wing pier).
	for side: float in [-1.0, 1.0]:
		var inner_x := cx + side * (hw_s + 0.09)
		var inner_top := minf(_roof_y(q, cx + side * (hw_s + 0.16)) - 0.04, wall_h + 0.22)
		s.colour = MAHOGANY_DARK.srgb_to_linear()
		s.box(Vector3(inner_x, (bot_y + inner_top) * 0.5, casing_z),
				Vector3(0.18, inner_top - bot_y, casing_d), Basis(), [RoomMesh.FRONT])
		# Outer stepped wing pier protruding slightly forward, creating a recessed vertical cove pocket between piers.
		var outer_x := cx + side * (hw - 0.125)
		var outer_top := wall_h - 0.02
		s.colour = MAHOGANY.srgb_to_linear()
		s.box(Vector3(outer_x, (bot_y + outer_top) * 0.5, fz + 0.135),
				Vector3(0.25, outer_top - bot_y, 0.27), Basis(), [RoomMesh.FRONT])
		# Curved chamfered wood cornice return linking outer pier to wall dado.
		s.colour = MAHOGANY_TRIM.srgb_to_linear()
		s.box(Vector3(cx + side * (hw - 0.04), bot_y, fz + 0.15), Vector3(0.08, 0.05, 0.3), Basis(), [RoomMesh.FRONT])

	# Overhead stepped mahogany proscenium header hugging the elliptical arch cleanly above the picture.
	var hdr_segs := 10
	var hdr_span := hw_s + 0.18
	s.colour = MAHOGANY.srgb_to_linear()
	for i in hdr_segs:
		var x0 := cx - hdr_span + 2.0 * hdr_span * float(i) / hdr_segs
		var x1 := cx - hdr_span + 2.0 * hdr_span * float(i + 1) / hdr_segs
		var xm := (x0 + x1) * 0.5
		var ry := _roof_y(q, xm) - 0.015
		var h_seg := maxf(ry - top_y, 0.06)
		s.box(Vector3(xm, top_y + h_seg * 0.5, casing_z), Vector3(x1 - x0 + 0.004, h_seg, casing_d),
				Basis(), [RoomMesh.FRONT])

	# Dark recessed acoustic cloth backing behind the brass loudspeaker grille under the screen.
	s.surface(c.tinted("iron"))
	s.colour = IRON_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.56, fz + 0.232), Vector3(1.22, 0.56, 0.014), Basis(), [RoomMesh.FRONT])
	# Shadow reveal framing the rear-projection screen edge tightly without protruding into the picture.
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * (hw_s + 0.016), cy, sz - 0.006), Vector3(0.032, sc_sz.y + 0.064, 0.022))
	s.box(Vector3(cx, top_y + 0.016, sz - 0.006), Vector3(sc_sz.x + 0.064, 0.032, 0.022))
	s.box(Vector3(cx, bot_y - 0.016, sz - 0.006), Vector3(sc_sz.x + 0.064, 0.032, 0.022))
	s.colour = Color.WHITE

	# --- Pleated claret velvet side masking tabs flanking the screen (outside picture width) ---
	u.surface(c.soft("cloth", true))
	var tab_col := CLARET_VELVET.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var x_inner := cx + side * (hw_s + 0.035)
		var tab_w := 0.135
		var folds := 4
		for j in folds:
			var f0 := float(j) / folds
			var f1 := float(j + 1) / folds
			var xm := x_inner + side * tab_w * ((f0 + f1) * 0.5)
			var xa := x_inner + side * tab_w * f0
			var xb := x_inner + side * tab_w * f1
			var zb := sz + 0.005
			var zf := sz + 0.042
			var n_a := Vector3(-side * 0.5, 0.0, 0.86).normalized()
			var n_b := Vector3(side * 0.5, 0.0, 0.86).normalized()
			u.colour = tab_col * 0.72
			if side > 0.0:
				u.face([Vector3(xa, bot_y + 0.01, zb), Vector3(xm, bot_y + 0.01, zf),
						Vector3(xm, top_y - 0.01, zf), Vector3(xa, top_y - 0.01, zb)], n_a)
				u.colour = tab_col
				u.face([Vector3(xm, bot_y + 0.01, zf), Vector3(xb, bot_y + 0.01, zb),
						Vector3(xb, top_y - 0.01, zb), Vector3(xm, top_y - 0.01, zf)], n_b)
			else:
				u.face([Vector3(xm, bot_y + 0.01, zf), Vector3(xa, bot_y + 0.01, zb),
						Vector3(xa, top_y - 0.01, zb), Vector3(xm, top_y - 0.01, zf)], n_a)
				u.colour = tab_col
				u.face([Vector3(xb, bot_y + 0.01, zb), Vector3(xm, bot_y + 0.01, zf),
						Vector3(xm, top_y - 0.01, zf), Vector3(xb, top_y - 0.01, zb)], n_b)

	# --- Curved glowing brass-hooded cove valance above and flanking the screen (PieceCove) ---
	cove.surface(c.kit.cove_material())
	var plaster := COVE_PLASTER.srgb_to_linear()
	# Arched glowing header cove crescent above the screen (parallels the elliptical roof arch, framed top & bottom in brass).
	var arch_lo := PackedVector3Array()
	var arch_hi := PackedVector3Array()
	var arch_n := PackedVector3Array()
	var cove_span := hw_s + 0.14
	var arch_steps := 14
	for i in arch_steps + 1:
		var t := float(i) / arch_steps
		var x := cx + lerpf(-cove_span, cove_span, t)
		var arch_rise := 1.0 - pow((x - cx) / cove_span, 2.0)
		var ry := _roof_y(q, x) - 0.04
		var y_bot := top_y + 0.045 + 0.048 * arch_rise
		var y_top := minf(ry, top_y + 0.145 + 0.135 * arch_rise)
		arch_lo.append(Vector3(x, y_bot, sz + 0.01))
		arch_hi.append(Vector3(x, y_top, sz + 0.01))
		arch_n.append(Vector3.BACK)
	cove.colour = Color(plaster.r, plaster.g, plaster.b, 0.98)
	cove.strip(arch_lo, arch_hi, arch_n)
	# Twin vertical recessed glowing cove strips tucked between inner and outer mahogany piers.
	for side: float in [-1.0, 1.0]:
		var x0 := cx + side * (hw_s + 0.185)
		var x1 := cx + side * (hw_s + 0.275)
		var x_l := minf(x0, x1)
		var x_r := maxf(x0, x1)
		var top_c := wall_h - 0.06
		cove.face([Vector3(x_l, bot_y + 0.06, fz + 0.165), Vector3(x_r, bot_y + 0.06, fz + 0.165),
				Vector3(x_r, top_c, fz + 0.165), Vector3(x_l, top_c, fz + 0.165)], Vector3.BACK)
	cove.colour = Color.WHITE

	# --- Gleaming 1935 polished brass trim: curved cove hood, sunburst crest, speaker louvres & speed-lines ---
	u.surface(c.shiny("gilt", 0.88, 0.72, 0.14))
	u.colour = BRASS.srgb_to_linear()
	# Curved streamlined double brass cove-hood valance framing the arched header cove cleanly along lower & upper curves.
	for i in arch_steps:
		var x0 := cx + lerpf(-cove_span, cove_span, float(i) / arch_steps)
		var x1 := cx + lerpf(-cove_span, cove_span, float(i + 1) / arch_steps)
		var xm := (x0 + x1) * 0.5
		var seg_w := x1 - x0 + 0.008
		var arch_rise := 1.0 - pow((xm - cx) / cove_span, 2.0)
		var y_hood := top_y + 0.042 + 0.048 * arch_rise
		var y_crown := minf(_roof_y(q, xm) - 0.038, top_y + 0.148 + 0.135 * arch_rise)
		u.box(Vector3(xm, y_hood, sz + 0.044), Vector3(seg_w, 0.03, 0.058))
		u.box(Vector3(xm, y_crown, sz + 0.03), Vector3(seg_w, 0.022, 0.034))
	# Central Art Deco brass sunburst fan crest crowning the rear-projection surround.
	var crest_y := top_y + 0.105
	u.box(Vector3(cx, crest_y - 0.012, sz + 0.056), Vector3(0.28, 0.042, 0.03))
	u.box(Vector3(cx, crest_y + 0.015, sz + 0.056), Vector3(0.18, 0.032, 0.028))
	for k in 7:
		var ang := deg_to_rad(-54.0 + 18.0 * k)
		var rlen := 0.185 if k % 2 == 0 else 0.13
		var mid := Vector3(cx + sin(ang) * rlen * 0.5, crest_y + 0.01 + cos(ang) * rlen * 0.5, sz + 0.05)
		u.box(mid, Vector3(0.02, rlen, 0.02), Basis(Vector3.BACK, -ang))
	# Vertical brass cove-hood baffle lips along both flanking mahogany piers.
	for side: float in [-1.0, 1.0]:
		var lip_x := cx + side * (hw - 0.25)
		u.box(Vector3(lip_x, (bot_y + wall_h - 0.04) * 0.5, fz + 0.275),
				Vector3(0.024, wall_h - 0.04 - bot_y, 0.026))
		u.box(Vector3(cx + side * (hw - 0.125), bot_y + 0.03, fz + 0.276), Vector3(0.24, 0.022, 0.018))
		u.box(Vector3(cx + side * (hw - 0.125), wall_h - 0.06, fz + 0.276), Vector3(0.24, 0.022, 0.018))
	# Horizontal brass speed-lines across the lower console & recessed slotted Art Deco horn-speaker grille.
	u.box(Vector3(cx, bot_y - 0.016, fz + 0.275), Vector3(sc_sz.x + 0.28, 0.022, 0.018))
	u.box(Vector3(cx, bot_y - 0.075, fz + 0.236), Vector3(hw * 2.0 - 0.14, 0.016, 0.016))
	u.box(Vector3(cx, 0.14, fz + 0.264), Vector3(hw * 2.0 - 0.08, 0.02, 0.018))
	# Framed brass speaker grille surround + 7 sleek horizontal Art Deco brass louvre bars + 3 vertical ribs.
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.61, 0.56, fz + 0.244), Vector3(0.028, 0.58, 0.022))
	u.box(Vector3(cx, 0.85, fz + 0.244), Vector3(1.24, 0.022, 0.022))
	u.box(Vector3(cx, 0.27, fz + 0.244), Vector3(1.24, 0.022, 0.022))
	for row in 7:
		var ly := 0.32 + 0.08 * row
		u.box(Vector3(cx, ly, fz + 0.246), Vector3(1.2, 0.015, 0.018))
	for rx: float in [-0.25, 0.0, 0.25]:
		u.box(Vector3(cx + rx, 0.56, fz + 0.248), Vector3(0.018, 0.56, 0.016))
	u.colour = Color.WHITE

	# Clean physics collision boxes for the front rear-projection console & piers (strictly inside cabin box).
	c.shapes.append(PhysicsShapes.box(Vector3(cx, bot_y * 0.5, fz + 0.135),
			Vector3(hw * 2.0 - 0.06, bot_y, 0.27), Basis()))
	for side: float in [-1.0, 1.0]:
		c.shapes.append(PhysicsShapes.box(Vector3(cx + side * (hw - 0.26), (bot_y + wall_h) * 0.5, fz + 0.135),
				Vector3(0.5, wall_h - bot_y, 0.27), Basis()))

	# Four warm tungsten carriage bake/stand-in lights evenly distributed down the arched ceiling aisle.
	for pz: float in [-2.4, -0.5, 1.4, 3.2]:
		c.lamps.append([Vector3(cx, float(q["headroom"]) - 0.26, pz), LAMP_GLOW, 0.72])


## Ornate continuous polished-brass and woven-cord netting overhead luggage racks along both window walls, plus subtle
## cornice uplight coves (PieceCove) washing the curved cream carriage ceiling.
static func _luggage_racks(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var wall_h := float(q["wall_height"])
	var marks: Array[float] = Cabin._bay_marks(q)
	if marks.size() < 2:
		return
	var z0 := marks[0] - 0.08
	var z1 := marks[-1] + 0.08
	var span := z1 - z0
	var mid_z := (z0 + z1) * 0.5
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)

	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	u.surface(c.shiny("gilt", 0.88, 0.72, 0.14))
	u.colour = BRASS.srgb_to_linear()

	for side: float in [-1.0, 1.0]:
		var wx := cx + side * hw
		var rail_x := cx + side * RACK_RAIL_DX
		var front_x := cx + side * (RACK_RAIL_DX - 0.025)
		var wall_bar_x := wx - side * 0.022
		# Heavy upper polished-brass guard rail, lower carrier/lamp-pivot rail, and wall ledger bar.
		Shapes.cylinder(u, Vector3(front_x, RACK_RAIL_Y + 0.105, z0), 0.015, span, 8, basis_z)
		Shapes.cylinder(u, Vector3(rail_x, RACK_RAIL_Y, z0), 0.011, span, 8, basis_z)
		u.box(Vector3(wall_bar_x, RACK_RAIL_Y + 0.02, mid_z), Vector3(0.02, 0.026, span))
		# Decorative turned brass end finials capping the front guard rail.
		for ez: float in [z0, z1]:
			u.box(Vector3(front_x, RACK_RAIL_Y + 0.105, ez), Vector3(0.04, 0.04, 0.036))
			u.box(Vector3(rail_x, RACK_RAIL_Y, ez), Vector3(0.03, 0.03, 0.028))
		# Ornate Art Deco stepped brass cantilever brackets at every window pier mark.
		for mz: float in marks:
			var arm_w := absf(wx - front_x)
			# Vertical wall mounting plate.
			u.box(Vector3(wx - side * 0.012, RACK_RAIL_Y + 0.01, mz), Vector3(0.018, 0.24, 0.046))
			# Horizontal main bracket arm supporting both rails.
			u.box(Vector3((wx + front_x) * 0.5, RACK_RAIL_Y + 0.005, mz), Vector3(arm_w, 0.022, 0.024))
			# Upward curved/stepped front lip rising from lower rail to upper guard rail.
			u.box(Vector3(front_x + side * 0.012, RACK_RAIL_Y + 0.055, mz), Vector3(0.024, 0.115, 0.024))
			# Diagonal Art Deco underside strut brace down to the pier rib.
			Shapes.beam(u, Vector3(wx - side * 0.018, RACK_RAIL_Y - 0.085, mz), Vector3(rail_x + side * 0.06, RACK_RAIL_Y, mz),
					Vector2(0.018, 0.02))

	# Woven cream-gold luggage-rack netting: crisp criss-crossing cord grid suspended neatly inside the brass rails.
	u.surface(c.soft("cloth", true))
	u.colour = NET_CORD.srgb_to_linear()
	var pitch_z := 0.26
	var n_steps := maxi(int(span / pitch_z), 8)
	var dz := span / n_steps
	for side: float in [-1.0, 1.0]:
		var x_wall := cx + side * (hw - 0.025)
		var x_rail := cx + side * RACK_RAIL_DX
		# Three longitudinal cord stringers running the rack length.
		for frac: float in [0.25, 0.5, 0.75]:
			var sx := lerpf(x_wall, x_rail, frac)
			var sy := lerpf(RACK_RAIL_Y + 0.02, RACK_RAIL_Y, frac) - 0.012 * sin(PI * frac)
			u.box(Vector3(sx, sy, mid_z), Vector3(0.008, 0.006, span - 0.04))
		# Diagonal crisscrossing netting cords creating authentic diamond railway luggage netting.
		for i in n_steps:
			var za := z0 + dz * i
			var zb := za + dz
			Shapes.beam(u, Vector3(x_wall, RACK_RAIL_Y + 0.02, za), Vector3(x_rail, RACK_RAIL_Y, zb), Vector2(0.007, 0.006))
			Shapes.beam(u, Vector3(x_wall, RACK_RAIL_Y + 0.02, zb), Vector3(x_rail, RACK_RAIL_Y, za), Vector2(0.007, 0.006))
	u.colour = Color.WHITE

	# Continuous subtle brass-hooded cornice cove uplight strips running above the luggage racks (PieceCove).
	u.surface(c.shiny("gilt", 0.88, 0.72, 0.14))
	u.colour = BRASS.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * (hw - 0.042), wall_h - 0.078, mid_z), Vector3(0.024, 0.016, span))
	u.colour = Color.WHITE
	cove.surface(c.kit.cove_material())
	var plaster := COVE_PLASTER.srgb_to_linear()
	cove.colour = Color(plaster.r, plaster.g, plaster.b, 0.92)
	for side: float in [-1.0, 1.0]:
		var x_c := cx + side * (hw - 0.03)
		var n_in := Vector3(-side, -0.25, 0.0).normalized()
		var y0 := wall_h - 0.072
		var y1 := wall_h - 0.012
		if side < 0.0:
			cove.face([Vector3(x_c, y0, z0), Vector3(x_c, y0, z1), Vector3(x_c, y1, z1), Vector3(x_c, y1, z0)], n_in)
		else:
			cove.face([Vector3(x_c, y0, z1), Vector3(x_c, y0, z0), Vector3(x_c, y1, z0), Vector3(x_c, y1, z1)], n_in)
	cove.colour = Color.WHITE


## Partly drawn holland-cloth carriage window blinds in mahogany top boxes with gleaming brass bottom battens and
## crimson tassel pulls, brass coat hooks on the mahogany piers, and the emergency communication cord chain.
static func _window_blinds_and_hardware(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var wt := float(q["wall_thickness"])
	var sill := float(q["window_sill"])
	var wh := float(q["window_height"])
	var ww := float(q["window_width"])
	var wzs: Array = q["window_zs"]
	var marks: Array[float] = Cabin._bay_marks(q)
	var win_top := sill + wh
	var blind_bot := win_top - 0.21

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	# Mahogany top blind roller pelmet boxes tucked neatly inside every window's upper reveal, plus coat-hook plaques.
	s.surface(c.tinted("wood"))
	for side: float in [-1.0, 1.0]:
		var wx := cx + side * hw
		s.colour = MAHOGANY_DARK.srgb_to_linear()
		for wz: float in wzs:
			s.box(Vector3(wx + side * (wt * 0.38), win_top - 0.032, wz), Vector3(wt * 0.65, 0.062, ww - 0.02))
		# Bevelled mahogany coat-hook plaques mounted on each interior window pier.
		s.colour = MAHOGANY_TRIM.srgb_to_linear()
		for i in range(1, marks.size() - 1):
			s.box(Vector3(wx - side * 0.012, 1.56, marks[i]), Vector3(0.022, 0.16, 0.075))
	s.colour = Color.WHITE

	# Warm holland-cloth roller blinds partly drawn at the top of each window + crimson pull tassels + red cord tags.
	u.surface(c.soft("cloth", true))
	for side: float in [-1.0, 1.0]:
		var wx := cx + side * hw
		var bx := wx + side * (wt * 0.5)
		u.colour = BLIND_CLOTH.srgb_to_linear()
		for wz: float in wzs:
			# Blind cloth sheet inside the upper reveal (leaves generous 0.75 m tall clear glass window below).
			u.box(Vector3(bx, (blind_bot + win_top - 0.055) * 0.5, wz),
					Vector3(0.012, win_top - 0.055 - blind_bot, ww - 0.04))
		# Crimson decorative blind pull tassels suspended centrally from each brass bottom batten.
		u.colour = CLARET_VELVET.srgb_to_linear()
		for wz: float in wzs:
			u.box(Vector3(bx - side * 0.012, blind_bot - 0.048, wz), Vector3(0.016, 0.042, 0.016))
		# Classic signal-red enamel emergency communication-cord pull tags on two piers per side.
		u.colour = SIGNAL_RED.srgb_to_linear()
		for idx: int in [2, 4]:
			if idx < marks.size():
				u.box(Vector3(wx - side * 0.036, RACK_RAIL_Y + 0.145, marks[idx]), Vector3(0.012, 0.075, 0.048))

	# Polished brass blind bottom battens, pull rings, curved coat hooks, and continuous emergency communication cord.
	u.surface(c.shiny("gilt", 0.88, 0.72, 0.14))
	u.colour = BRASS.srgb_to_linear()
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)
	for side: float in [-1.0, 1.0]:
		var wx := cx + side * hw
		var bx := wx + side * (wt * 0.5)
		for wz: float in wzs:
			# Gleaming horizontal brass bottom batten + centered pull ring.
			u.box(Vector3(bx - side * 0.008, blind_bot, wz), Vector3(0.022, 0.018, ww - 0.03))
			Shapes.arch(u, Vector3(bx - side * 0.012, blind_bot - 0.02, wz), 0.01, 0.017, 0.008, 10,
					Basis(Vector3.UP, PI * 0.5), 0.0, TAU, ["front", "back", "inner", "outer"])
		# Turned brass double coat hooks on interior window piers.
		for i in range(1, marks.size() - 1):
			var mz := marks[i]
			u.box(Vector3(wx - side * 0.032, 1.56, mz), Vector3(0.03, 0.016, 0.02))
			u.box(Vector3(wx - side * 0.058, 1.59, mz), Vector3(0.018, 0.072, 0.018))
			u.box(Vector3(wx - side * 0.05, 1.52, mz), Vector3(0.014, 0.032, 0.014))
		# Continuous brass emergency communication cord chain just below the upper cornice, threaded through eyelets.
		if marks.size() >= 2:
			var cz0 := marks[0] - 0.15
			var cz1 := marks[-1] + 0.15
			var cord_x := wx - side * 0.034
			var cord_y := RACK_RAIL_Y + 0.205
			Shapes.cylinder(u, Vector3(cord_x, cord_y, cz0), 0.006, cz1 - cz0, 6, basis_z)
			for mz: float in marks:
				u.box(Vector3(wx - side * 0.018, cord_y, mz), Vector3(0.032, 0.014, 0.014))
	u.colour = Color.WHITE


## Under-sill cast-iron steam heater pipe guards along both lower walls and Art Deco ceiling brass ventilators along
## the elliptical carriage crown.
static func _ceiling_and_heaters(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var crown_y := float(q["headroom"])
	var marks: Array[float] = Cabin._bay_marks(q)

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	# Cast-iron floor-edge steam heater pipe shrouds tucked cleanly beneath the dado (clear of outer seats).
	s.surface(c.tinted("iron"))
	s.colour = IRON_DARK.srgb_to_linear()
	var hz0 := fz + 0.45
	var hz1 := bz - 0.4
	var h_span := hz1 - hz0
	var h_mid := (hz0 + hz1) * 0.5
	for side: float in [-1.0, 1.0]:
		var hx := cx + side * (hw - 0.03)
		s.box(Vector3(hx, 0.14, h_mid), Vector3(0.052, 0.18, h_span), Basis(), [RoomMesh.DOWN])
	# Recessed mahogany crown clerestory batten running cleanly along the elliptical roof spine.
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY_TRIM.srgb_to_linear()
	s.box(Vector3(cx, crown_y - 0.014, (fz + bz) * 0.5), Vector3(0.24, 0.024, bz - fz - 0.16), Basis(), [RoomMesh.UP])
	s.colour = Color.WHITE

	# Four turned brass Art Deco circular roof-ventilator grilles mounted along the ceiling crown spine.
	u.surface(c.shiny("gilt", 0.88, 0.72, 0.14))
	u.colour = BRASS.srgb_to_linear()
	var vent_zs: Array[float] = [-2.4, -0.45, 1.5, 3.35]
	for vz: float in vent_zs:
		Shapes.lathe(u, [Vector2(0.135, 0.0), Vector2(0.135, -0.018), Vector2(0.105, -0.03),
				Vector2(0.08, -0.032), Vector2(0.0, -0.026)], Vector3(cx, crown_y - 0.024, vz), 14)
	# Brass ceiling rib rosette clasps where each arched carriage rib crosses the crown spine.
	for mz: float in marks:
		u.box(Vector3(cx, crown_y - 0.032, mz), Vector3(0.26, 0.018, 0.09))
	u.colour = Color.WHITE


## Wood-panelled aft vestibule door with frosted-glass Art Deco brass security grille, heavy brass push-bar & kick-plate,
## framed geometric railway route-map plaques, and working 1935 railway brass bulkhead clock (PieceClock).
static func _aft_vestibule(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis_aft := Basis(Vector3.UP, PI)

	# --- Wood-panelled vestibule door moulding, flanking bulkhead wainscot frames & clock backing plaque ---
	s.surface(c.tinted("wood"))
	# Recessed raised mahogany moulding on the lower door leaf (door is 0.62 x 1.85 m, face at bz - 0.02).
	s.colour = MAHOGANY_TRIM.srgb_to_linear()
	s.box(Vector3(cx, 0.72, bz - 0.024), Vector3(0.46, 0.84, 0.014), Basis(), [RoomMesh.BACK])
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.72, bz - 0.03), Vector3(0.38, 0.76, 0.01), Basis(), [RoomMesh.BACK])
	# Moulded mahogany door architrave framing the entire vestibule doorway cleanly.
	s.colour = MAHOGANY_TRIM.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * 0.345, 0.94, bz - 0.022), Vector3(0.07, 1.88, 0.044), Basis(), [RoomMesh.BACK])
	s.box(Vector3(cx, 1.885, bz - 0.026), Vector3(0.76, 0.07, 0.052), Basis(), [RoomMesh.BACK])
	# Stepped mahogany backing plaque for the working 1935 railway brass bulkhead clock above the vestibule door.
	var clk_y := 2.3
	var clk_r := 0.185
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	s.box(Vector3(cx, clk_y, bz - 0.02), Vector3(0.96, 0.22, 0.04), Basis(), [RoomMesh.BACK])
	s.box(Vector3(cx, clk_y, bz - 0.026), Vector3(0.48, 0.44, 0.052), Basis(), [RoomMesh.BACK])
	# Two framed mahogany route-map / compartment diagram plaques flanking the vestibule door.
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (hw * 0.62)
		s.colour = MAHOGANY_TRIM.srgb_to_linear()
		s.box(Vector3(px, 1.46, bz - 0.018), Vector3(0.56, 0.42, 0.032), Basis(), [RoomMesh.BACK])
	s.colour = Color.WHITE

	# Cream parchment backing inside the two flanking aft bulkhead frames (pure geometric Deco track-line motifs).
	u.surface(c.soft("cloth", true))
	u.colour = PARCHMENT.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (hw * 0.62)
		u.box(Vector3(px, 1.46, bz - 0.036), Vector3(0.48, 0.34, 0.008))

	# --- Gleaming brass vestibule hardware: frosted-window Art Deco grille, push-bar, kick-plate & bulkhead clock ---
	u.surface(c.shiny("gilt", 0.88, 0.72, 0.14))
	u.colour = BRASS.srgb_to_linear()
	# Brass kick-plate, horizontal carriage vestibule push-bar & curved door latch.
	u.box(Vector3(cx, 0.11, bz - 0.028), Vector3(0.56, 0.22, 0.01))
	u.box(Vector3(cx, 1.02, bz - 0.058), Vector3(0.48, 0.03, 0.02))
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.21, 1.02, bz - 0.04), Vector3(0.028, 0.044, 0.036))
	# Ornate Art Deco brass security grille standing cleanly proud of the backlit frosted vestibule door glass
	# (DoorGlow lies at bz - 0.032, x = cx +- 0.15, y = 1.30..1.70).
	var gz := bz - 0.042
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.155, 1.5, gz), Vector3(0.018, 0.42, 0.012))
		u.box(Vector3(cx + side * 0.065, 1.5, gz), Vector3(0.01, 0.4, 0.01))
	u.box(Vector3(cx, 1.705, gz), Vector3(0.328, 0.018, 0.012))
	u.box(Vector3(cx, 1.295, gz), Vector3(0.328, 0.018, 0.012))
	u.box(Vector3(cx, 1.5, gz), Vector3(0.31, 0.012, 0.01))
	# Central Art Deco diamond lozenge inside the frosted vestibule window grille.
	for k in 4:
		var ang := PI * 0.25 + PI * 0.5 * k
		var dx := cos(ang) * 0.065
		var dy := sin(ang) * 0.085
		u.box(Vector3(cx + dx * 0.5, 1.5 + dy * 0.5, gz - 0.004), Vector3(0.095, 0.011, 0.01),
				Basis(Vector3.BACK, PI * 0.25 * (1.0 if k % 2 == 0 else -1.0)))

	# Stylized brass Art Deco route-line & compass-star reliefs inside the flanking bulkhead map plaques (zero text).
	for side: float in [-1.0, 1.0]:
		var px := cx + side * (hw * 0.62)
		var pz := bz - 0.043
		u.box(Vector3(px, 1.46, pz), Vector3(0.4, 0.012, 0.006))
		u.box(Vector3(px - 0.12, 1.52, pz), Vector3(0.16, 0.01, 0.006), Basis(Vector3.BACK, 0.45))
		u.box(Vector3(px + 0.1, 1.4, pz), Vector3(0.18, 0.01, 0.006), Basis(Vector3.BACK, -0.35))
		for station_x: float in [-0.17, -0.05, 0.06, 0.17]:
			u.box(Vector3(px + station_x, 1.46, pz - 0.003), Vector3(0.022, 0.022, 0.008),
					Basis(Vector3.BACK, PI * 0.25))

	# Spun gleaming brass bezel, Art Deco horizontal wing speed-bars & crown finial around the working railway clock.
	Shapes.arch(u, Vector3(cx, clk_y, bz - 0.052), clk_r, clk_r + 0.036, 0.052, 24, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * 0.35, clk_y + 0.048, bz - 0.044), Vector3(0.24, 0.016, 0.016))
		u.box(Vector3(cx + side * 0.33, clk_y, bz - 0.046), Vector3(0.2, 0.02, 0.018))
		u.box(Vector3(cx + side * 0.31, clk_y - 0.048, bz - 0.044), Vector3(0.16, 0.016, 0.016))
	u.box(Vector3(cx, clk_y + clk_r + 0.048, bz - 0.052), Vector3(0.052, 0.032, 0.028))
	u.colour = Color.WHITE

	# Live working 1935 railway bulkhead clock dial (PieceClock, facing -Z into the carriage).
	c.clocks.append([Vector3(cx, clk_y, bz - 0.066), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# Clean physics collision box for the aft vestibule door architrave & bulkhead trim.
	c.shapes.append(PhysicsShapes.box(Vector3(cx, 1.15, bz - 0.035), Vector3(0.76, 2.3, 0.07), Basis()))


# --- Swaying hanging brass-and-opal-glass carriage lamps --------------------------------------------------------------

## Hanging 1935 brass-and-opal-glass carriage lamps suspended cleanly from the luggage rack lower brass rail
## (x = cx +- RACK_RAIL_DX, y = RACK_RAIL_Y). Called per side (at.x < -0.5 for left, > 0.5 for right; or both when 0)
## so each side's `motion` `sway` group pivots right along its own rack rail with zero vertical detachment.
static func _lamps(c: Object, xf: Transform3D) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	var cx := float(q["cx"])
	var marks: Array[float] = Cabin._bay_marks(q)
	if marks.size() < 3:
		return
	var sides: Array[float] = [-1.0, 1.0]
	if xf.origin.x < -0.5:
		sides = [-1.0]
	elif xf.origin.x > 0.5:
		sides = [1.0]

	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	u.surface(c.shiny("gilt", 0.88, 0.72, 0.14))
	u.colour = BRASS.srgb_to_linear()
	lit.surface(c.shade(LAMP_GLOW))

	# Hang a glowing brass-and-opal tulip carriage lamp at each of the four inner window pier bays.
	for side: float in sides:
		var lx := cx + side * RACK_RAIL_DX
		for i in range(1, marks.size() - 1):
			var lz := marks[i]
			var pivot := Vector3(lx, RACK_RAIL_Y, lz)
			# Brass saddle collar hugging the luggage rack rod + turned pendant stem, ornamental bead & shade gallery.
			Shapes.lathe(u, [
				Vector2(0.017, 0.014), Vector2(0.017, -0.016),
				Vector2(0.008, -0.022), Vector2(0.007, -0.072),
				Vector2(0.016, -0.082), Vector2(0.016, -0.094),
				Vector2(0.008, -0.104), Vector2(0.022, -0.118),
				Vector2(0.052, -0.132), Vector2(0.056, -0.148),
				Vector2(0.048, -0.156)], pivot, 10)
			# Stepped Art Deco fluted opal-glass carriage lamp globe (house group: bright in station, warm dim in film).
			Shapes.lathe(lit, [
				Vector2(0.046, -0.154), Vector2(0.062, -0.184),
				Vector2(0.064, -0.222), Vector2(0.052, -0.258),
				Vector2(0.024, -0.278), Vector2(0.0, -0.284)], pivot, 12)
			# Decorative bottom brass acorn finial tip beneath the opal globe.
			Shapes.lathe(u, [
				Vector2(0.02, -0.278), Vector2(0.015, -0.292),
				Vector2(0.008, -0.304), Vector2(0.0, -0.312)], pivot, 8)
	u.colour = Color.WHITE


## Roof height of the carriage's arched elliptical ceiling at world x.
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
