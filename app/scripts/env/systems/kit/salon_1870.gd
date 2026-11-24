extends RefCounted

## The Salon, 1870 Victorian submarine salon (docs/environments/rooms/salon_1870.md): an opulent 1870 underwater
## observation salon dressed over a gently inward-leaning `cabin` pressure hull and crimson tufted `seats` (`club_chair`).
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, beams and lathed shapes; no people,
## no trademarks, CC0 library materials only.
##
##   salon_1870_interior  the 1870 Victorian submarine salon architecture and nautical furnishings:
##                        - five heavy riveted wrought-iron and burnished-brass arched pressure-hull ribs rising up both
##                          leaning walls and across the vaulted ceiling, tied fore-and-aft by longitudinal hull stringers,
##                          a crown spine beam, floor knee-gussets and rows of domed brass rivets
##                        - two monumental 32-segment circular bolted cast-brass & dark-iron observation viewport rings
##                          (port and starboard, 1.56 m clear aperture) studded with 20 domed brass pressure bolts each,
##                          paired with spoked brass iris hand-crank actuators and low mahogany viewing sills
##                        - Victorian mahogany, crimson-velvet and gilded-brass screen proscenium on a stepped dais with
##                          fluted pilasters, draped velvet side curtains, brass compass-rose tympanum crest and warm
##                          indirect cove lighting (`PieceCove`) along the proscenium and vaulted eaves
##                        - four flank mahogany cabinets: two tall forward library bookcases filled with leather-bound
##                          atlases behind diamond brass sea-grilles (plus a brass-mounted terrestrial globe), and two aft
##                          naturalist's specimen credenzas with a brass armillary sphere, spiral shell sculpture and
##                          mounted brass spyglass
##                        - six gooseneck marine brass wall sconces and two overhead brass-caged ceiling dome lanterns
##                          (`PieceLamps`, `bake_lamps: 4`)
##                        - aft bulkhead centerpiece: a 21-pipe Victorian mahogany-and-brass salon pipe organ with twin
##                          ivory/ebony manuals, draw-stop knobs, illuminated music rack, pedalboard and crimson velvet
##                          bench; a working bolted-brass marine chronometer (`PieceClock`) crowning the organ arch; a
##                          starboard brass navigation binnacle with quadrantal corrector spheres, engine-room order
##                          telegraph dial & lever, and port/starboard riveted ballast manifolds with spoked brass
##                          handwheels and six illuminated pressure/depth gauges (`PieceWindows`)
##   salon_1870_iris      animated 10-blade riveted mechanical brass iris shutters on BOTH circular observation viewports
##                        (20 curved bevelled crescent brass blades in ONE `MultiMeshInstance3D` = 1 draw, 0 lights)
##                        driven live via `c.halls` from `host.timeline.state`, `setting.shutters` (`Open for the film`,
##                        `Always open`, `Half open`) and `setting.motion` (snapping cleanly below 0.25)

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")

const PIECES: Array[String] = ["salon_1870_interior", "salon_1870_iris"]

## Palette (sRGB): Victorian mahogany, deep walnut, crimson velvet, wrought hull iron, burnished brass, warm ivory.
const MAHOGANY := Color(0.38, 0.17, 0.11)
const MAHOGANY_DARK := Color(0.24, 0.11, 0.07)
const WALNUT_WARM := Color(0.46, 0.25, 0.14)
const VELVET_CRIMSON := Color(0.46, 0.08, 0.12)
const VELVET_DEEP := Color(0.32, 0.05, 0.08)
const IRON_HULL := Color(0.18, 0.22, 0.26)
const IRON_DARK := Color(0.11, 0.13, 0.16)
const BRASS_BRIGHT := Color(0.92, 0.74, 0.36)
const BRASS_WARM := Color(0.78, 0.58, 0.25)
const BRASS_BRONZE := Color(0.66, 0.46, 0.20)
const COPPER_PIPE := Color(0.74, 0.41, 0.24)
const IVORY := Color(0.94, 0.90, 0.80)
const PARCHMENT := Color(0.90, 0.84, 0.68)
const EBONY := Color(0.06, 0.06, 0.07)
const OCEAN_GLOBE := Color(0.18, 0.42, 0.48)
const PORT_RED := Color(0.76, 0.14, 0.12)
const STBD_GREEN := Color(0.12, 0.56, 0.26)
const LAMP_AMBER := Color(1.0, 0.78, 0.44)

## Circular viewport & 10-blade mechanical brass iris geometry (metres, verified leak-free for phi = 0..46 deg).
const IRIS_BLADES := 10
const IRIS_R_OPEN := 0.78
const IRIS_R_PIV := 0.95
const IRIS_R_HOUSE := 1.18
const IRIS_A0_DEG := -6.0
const IRIS_A1_DEG := 112.0
const IRIS_PHI_CLOSED_DEG := 32.5
const IRIS_PHI_HALF_DEG := 16.5
const IRIS_PHI_OPEN_DEG := 0.0
const IRIS_TRAVEL_SECONDS := 5.0
const MOTION_FLOOR := 0.25


## Animated 10-blade riveted mechanical brass iris shutters on port & starboard viewports (20 blades = 1 draw).
class SalonIrisHall:
	var q: Dictionary
	var kit: Node
	var iris_mm: MultiMesh
	var iris_node: MultiMeshInstance3D
	## Per-viewport base transform (origin at viewport centre on inner wall plane, +Z pointing into salon).
	var _vp_xfs: Array[Transform3D] = []
	## Current openness 0.0 (pre-show glowing turquoise oculus) .. 1.0 (wide open circular ocean vista).
	var _open := 0.0
	var _last_phi := -999.0

	func _init(p_q: Dictionary) -> void:
		q = p_q

	func finish(k: Node) -> void:
		kit = k
		_vp_xfs.clear()
		var lean := float(q["L"])
		var wzs: Array = q["window_zs"]
		var sides: Array = q["window_sides_s"]
		var yc := (float(q["window_sill"]) + float(q["window_height"]) * 0.5) / cos(lean)
		var wz := float(wzs[0]) if not wzs.is_empty() else -0.5
		for s: float in sides:
			var origin := Cabin._pt(q, s, wz, yc)
			var basis := Cabin._wall_basis(q, s)
			_vp_xfs.append(Transform3D(basis, origin))
		var total := _vp_xfs.size() * IRIS_BLADES
		if total <= 0:
			return
		var blade_mesh := _build_blade_mesh(k._ctx.shiny("gilt", 0.88, 0.56, 0.18))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = blade_mesh
		mm.instance_count = total
		for vi in _vp_xfs.size():
			for bi in IRIS_BLADES:
				var idx := vi * IRIS_BLADES + bi
				# MultiMesh instance colors go straight to shader COLOR in linear space: convert sRGB->linear so
				# the 10 spiralling blades glow rich burnished Victorian gold-brass matching the bolted bezel!
				var col := (Color(0.94, 0.74, 0.34) if (bi % 2 == 0) else Color(0.76, 0.55, 0.22)).srgb_to_linear()
				mm.set_instance_color(idx, col)
		var mi := MultiMeshInstance3D.new()
		mi.name = "SalonIrisShutters"
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.set_meta("instances", total)
		iris_mm = mm
		iris_node = mi
		_open = _target_open()
		_apply(_open, true)
		# Record open-state transforms for headless sight_line checks (strictly in the side wall pockets).
		var placed: Array[Transform3D] = []
		for vi in _vp_xfs.size():
			for bi in IRIS_BLADES:
				placed.append(_blade_xf(_vp_xfs[vi], bi, deg_to_rad(IRIS_PHI_OPEN_DEG)))
		mi.set_meta("env_placed", placed)
		k.own(mi)

	func tick(delta: float) -> void:
		if iris_mm == null or kit == null or kit.host == null:
			return
		var want := _target_open()
		var motion := 1.0
		var m_val: Variant = kit.host.setting("motion")
		if m_val != null:
			motion = clampf(float(m_val), 0.0, 1.0)
		if motion < MOTION_FLOOR or delta <= 0.0:
			_open = want
		else:
			_open = move_toward(_open, want, delta / IRIS_TRAVEL_SECONDS * motion)
		_apply(_open, false)

	func _target_open() -> float:
		var mode := "film"
		if kit != null and kit.host != null:
			var s_val: Variant = kit.host.setting("shutters")
			if s_val != null:
				mode = str(s_val)
		match mode:
			"open":
				return 1.0
			"half":
				return 0.52
		var state := ""
		if kit != null and kit.host != null and kit.host.get("timeline") != null:
			state = str(kit.host.timeline.state)
		if state in ["starting", "playing", "credits"]:
			return 1.0
		if state in ["paused", "intermission"]:
			return 0.72
		return 0.0

	func _apply(open_t: float, force: bool) -> void:
		var t := clampf(open_t, 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t)
		var phi_deg := lerpf(IRIS_PHI_CLOSED_DEG, IRIS_PHI_OPEN_DEG, eased)
		var phi := deg_to_rad(phi_deg)
		if not force and absf(phi - _last_phi) < 1e-5:
			return
		_last_phi = phi
		for vi in _vp_xfs.size():
			var vp_xf := _vp_xfs[vi]
			for bi in IRIS_BLADES:
				iris_mm.set_instance_transform(vi * IRIS_BLADES + bi, _blade_xf(vp_xf, bi, phi))
		if iris_node != null and is_instance_valid(iris_node):
			iris_node.set_meta("iris_open", t)
			iris_node.set_meta("iris_angle_deg", phi_deg)

	static func _blade_xf(vp_xf: Transform3D, blade_index: int, phi: float) -> Transform3D:
		var theta := float(blade_index) * TAU / float(IRIS_BLADES)
		var ring_rot := Basis(Vector3.BACK, theta)
		var piv_local := ring_rot * Vector3(IRIS_R_PIV, 0.0, 0.0)
		var blade_rot := ring_rot * Basis(Vector3.BACK, phi)
		return vp_xf * Transform3D(blade_rot, piv_local)

	## Builds ONE 3D curved bevelled crescent brass iris blade in its pivot-local frame: pivot at (0, 0, 0),
	## inner concave lip at r = IRIS_R_OPEN - 0.015 (peeking subtly inside the bolted ring when open), outer convex arc
	## staying strictly inside r <= 1.16 m at every pivot angle, helically ramped in Z so overlapping blades shingle
	## cleanly with zero z-fighting, plus a sculpted brass stiffener rib and 4 rivet bosses on the cabin-facing side.
	static func _build_blade_mesh(mat: Material) -> ArrayMesh:
		var b := RoomMesh.new()
		b.surface(mat)
		b.colour = Color.WHITE
		var segs := 10
		var a0 := deg_to_rad(IRIS_A0_DEG)
		var a1 := deg_to_rad(IRIS_A1_DEG)
		var r_in := IRIS_R_OPEN - 0.014
		var ro_b := 1.13
		var ro_m := 1.15
		var ro_t := 1.10
		var thick := 0.009
		var z_base := -0.024
		var z_tip := 0.034

		var in_f := PackedVector3Array()
		var out_f := PackedVector3Array()
		var in_b := PackedVector3Array()
		var out_b := PackedVector3Array()
		var n_f := PackedVector3Array()
		var n_b := PackedVector3Array()
		var n_in := PackedVector3Array()
		var n_out := PackedVector3Array()

		for i in segs + 1:
			var t := float(i) / float(segs)
			var a := lerpf(a0, a1, t)
			var ca := cos(a)
			var sa := sin(a)
			var ro := ro_b * (1.0 - t) * (1.0 - t) + 2.0 * ro_m * t * (1.0 - t) + ro_t * t * t
			var zc := lerpf(z_base, z_tip, t)
			var zf := zc + thick * 0.5
			var zb := zc - thick * 0.5
			var pi_xy := Vector2(r_in * ca - IRIS_R_PIV, r_in * sa)
			var po_xy := Vector2(ro * ca - IRIS_R_PIV, ro * sa)
			in_f.append(Vector3(pi_xy.x, pi_xy.y, zf))
			out_f.append(Vector3(po_xy.x, po_xy.y, zf))
			in_b.append(Vector3(pi_xy.x, pi_xy.y, zb))
			out_b.append(Vector3(po_xy.x, po_xy.y, zb))
			n_f.append(Vector3.BACK)
			n_b.append(Vector3.FORWARD)
			n_in.append(Vector3(-ca, -sa, 0.0).normalized())
			n_out.append(Vector3(ca, sa, 0.0).normalized())

		# Front (cabin-facing) and back (ocean-facing) blade faces + curved inner/outer bevel edges + end caps.
		b.strip(in_f, out_f, n_f)
		b.strip(out_b, in_b, n_b)
		b.strip(in_b, in_f, n_in)
		b.strip(out_f, out_b, n_out)
		b.face([in_b[0], out_b[0], out_f[0], in_f[0]], Vector3(sin(a0), -cos(a0), 0.0).normalized())
		b.face([out_b[segs], in_b[segs], in_f[segs], out_f[segs]], Vector3(-sin(a1), cos(a1), 0.0).normalized())

		# Sculpted central brass stiffener rib curving along the exposed leading arc + 4 raised brass rivet bosses.
		for i in range(1, segs - 1):
			var p0 := in_f[i].lerp(out_f[i], 0.22) + Vector3(0.0, 0.0, 0.003)
			var p1 := in_f[i + 1].lerp(out_f[i + 1], 0.22) + Vector3(0.0, 0.0, 0.003)
			Shapes.beam(b, p0, p1, Vector2(0.016, 0.006), Vector3.BACK)
			if i in [2, 4, 6, 8]:
				var rv := in_f[i].lerp(out_f[i], 0.11) + Vector3(0.0, 0.0, 0.004)
				b.box(rv, Vector3(0.020, 0.020, 0.007))
		return b.commit()


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"salon_1870_interior":
			_interior(c)
		"salon_1870_iris":
			_iris(c)


static func _iris(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	c.halls.append(SalonIrisHall.new(q))


# --- The 1870 Victorian submarine salon interior ----------------------------------------------------------------------

static func _interior(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_hull_ribs_and_stringers(c, q)
	_viewport_rings(c, q)
	_proscenium_and_coves(c, q)
	_bookcases_and_vitrines(c, q)
	_marine_lamps(c, q)
	_aft_organ_and_instruments(c, q)
	_reset_colours(c)


static func _reset_colours(c: Object) -> void:
	c.s.colour = Color.WHITE
	c.u.colour = Color.WHITE
	c.cove.colour = Color.WHITE


## Five heavy riveted wrought-iron and burnished-brass arched pressure-hull ribs, longitudinal ceiling stringers,
## central vaulted hull crown spine, floor knee-gussets and studded brass rivets.
static func _hull_ribs_and_stringers(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var wall_len := float(q["wall_len"])
	var headroom := float(q["headroom"])
	var roof: Array = Cabin._roof(q)
	var rpts: PackedVector2Array = roof[0]
	var rns: PackedVector2Array = roof[1]

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var rib_zs: Array[float] = [fz + 0.12, -1.86, 0.86, 2.32, bz - 0.12]

	for z: float in rib_zs:
		# Wrought-iron I-section wall pillars & vaulted ceiling arch ribs.
		s.surface(c.tinted("iron"))
		s.colour = IRON_HULL.srgb_to_linear()
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
		u.colour = BRASS_WARM.srgb_to_linear()

		for side: float in [-1.0, 1.0]:
			var wb := Cabin._wall_basis(q, side)
			var n := Cabin._n(q, side)
			# Heavy wrought-iron web + wider base mounting flange hugging the leaning hull wall.
			s.box(Cabin._pt(q, side, z, wall_len * 0.5) + n * 0.06, Vector3(0.08, wall_len, 0.12), wb)
			s.box(Cabin._pt(q, side, z, wall_len * 0.5) + n * 0.015, Vector3(0.16, wall_len, 0.03), wb)
			# Sculpted lower floor knee-gusset bracket anchoring each rib into the deck.
			s.box(Cabin._pt(q, side, z, 0.24) + n * 0.12, Vector3(0.09, 0.44, 0.14), wb)
			s.box(Cabin._pt(q, side, z, 0.10) + n * 0.18, Vector3(0.11, 0.18, 0.14), wb)
			# Gleaming brass inner flange cap bead running smoothly up the rib spine.
			u.box(Cabin._pt(q, side, z, wall_len * 0.5) + n * 0.126, Vector3(0.095, wall_len, 0.018), wb)
			# Paired domed brass hull rivets studded up both flanges of the iron rib.
			for k in 8:
				var rv := 0.28 + float(k) * (wall_len - 0.52) / 7.0
				for dz: float in [-0.058, 0.058]:
					u.box(Cabin._pt(q, side, z + dz, rv) + n * 0.036, Vector3(0.018, 0.018, 0.014), wb)

		# Continuous riveted iron-and-brass arch spanning the vaulted pressure-hull ceiling.
		for i in rpts.size() - 1:
			var p0 := Vector3(rpts[i].x, rpts[i].y, z)
			var p1 := Vector3(rpts[i + 1].x, rpts[i + 1].y, z)
			var n0 := Vector3(rns[i].x, rns[i].y, 0.0)
			var n1 := Vector3(rns[i + 1].x, rns[i + 1].y, 0.0)
			var nm := (n0 + n1).normalized()
			var seg_len := p0.distance_to(p1) + 0.02
			var mid := (p0 + p1) * 0.5
			var tangent := (p1 - p0).normalized()
			var b_arch := Basis(tangent, nm, tangent.cross(nm).normalized())
			s.box(mid + nm * 0.055, Vector3(seg_len, 0.11, 0.085), b_arch)
			s.box(mid + nm * 0.014, Vector3(seg_len, 0.028, 0.16), b_arch)
			u.box(mid + nm * 0.116, Vector3(seg_len, 0.016, 0.096), b_arch)
			# Brass ceiling rivet pairs along the iron flange plates.
			for dz: float in [-0.058, 0.058]:
				u.box(mid + nm * 0.032 + Vector3(0.0, 0.0, dz), Vector3(0.018, 0.014, 0.018), b_arch)

	# Longitudinal vaulted hull stringers + central riveted iron-and-brass ceiling crown spine beam.
	var span := bz - fz - 0.14
	var mid_z := (fz + bz) * 0.5
	s.surface(c.tinted("iron"))
	s.colour = IRON_HULL.srgb_to_linear()
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_WARM.srgb_to_linear()
	for idx: int in [3, rpts.size() - 4]:
		var p := rpts[idx]
		var nr := rns[idx]
		var ang := atan2(-nr.x, -nr.y)
		var b_str := Basis(Vector3.BACK, ang)
		s.box(Vector3(p.x, p.y, mid_z) + Vector3(nr.x, nr.y, 0.0) * 0.04, Vector3(0.07, 0.08, span), b_str)
		u.box(Vector3(p.x, p.y, mid_z) + Vector3(nr.x, nr.y, 0.0) * 0.084, Vector3(0.078, 0.014, span), b_str)
	# Central crown pressure spine beam.
	s.box(Vector3(cx, headroom - 0.045, mid_z), Vector3(0.16, 0.09, span))
	u.box(Vector3(cx, headroom - 0.095, mid_z), Vector3(0.175, 0.016, span))
	# Mahogany skirting board + brass dado bead running cleanly along both side walls.
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var wb := Cabin._wall_basis(q, side)
		var n := Cabin._n(q, side)
		s.box(Cabin._pt(q, side, mid_z, 0.09) + n * 0.022, Vector3(span, 0.18, 0.044), wb)
		u.box(Cabin._pt(q, side, mid_z, 0.185) + n * 0.036, Vector3(span, 0.018, 0.018), wb)


## Monumental bolted cast-brass & iron circular observation viewport rings on both walls, studded with 20 domed brass
## hex bolts each, paired with spoked brass iris actuator handwheels and low mahogany viewing sills.
static func _viewport_rings(c: Object, q: Dictionary) -> void:
	var wzs: Array = q["window_zs"]
	var sides: Array = q["window_sides_s"]
	if wzs.is_empty() or sides.is_empty():
		return
	var lean := float(q["L"])
	var wz := float(wzs[0])
	var yc := (float(q["window_sill"]) + float(q["window_height"]) * 0.5) / cos(lean)
	var wall_t := float(q["wall_thickness"])

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u

	for side: float in sides:
		var wb := Cabin._wall_basis(q, side)
		var n := Cabin._n(q, side)
		var ctr := Cabin._pt(q, side, wz, yc)

		# 1. Recessed circular cast-iron pressure throat lining (masks the cabin's 16-gon cutout into a razor-smooth
		#    32-segment circular tunnel of clear radius IRIS_R_OPEN = 0.78 m).
		s.surface(c.tinted("iron"))
		s.colour = IRON_DARK.srgb_to_linear()
		Shapes.arch(s, ctr - n * (wall_t * 0.52), IRIS_R_OPEN, IRIS_R_OPEN + 0.15, wall_t + 0.04, 32, wb, 0.0, TAU,
				["front", "inner"])
		# Outer iron mounting collar bolted against the crimson velvet wall (r = 1.09..1.20).
		s.colour = IRON_HULL.srgb_to_linear()
		Shapes.arch(s, ctr + n * 0.028, 1.08, IRIS_R_HOUSE + 0.02, 0.056, 32, wb, 0.0, TAU, ["front", "outer"])

		# 2. Heavy stepped cast-brass pressure housing ring concealing the iris pivot chamber (r = 0.78..1.14).
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
		u.colour = BRASS_WARM.srgb_to_linear()
		# Main wide bolted middle flange (front face at +0.088 m, safely in front of the +0.036 m iris blades!).
		Shapes.arch(u, ctr + n * 0.068, 0.92, 1.14, 0.040, 32, wb, 0.0, TAU, ["front", "outer"])
		# Inner raised lip framing the 1.56 m clear aperture and hiding the iris blade tips cleanly inside.
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.arch(u, ctr + n * 0.080, IRIS_R_OPEN, 0.935, 0.052, 32, wb, 0.0, TAU, ["front", "inner", "outer"])
		# Outer raised brass rim bead.
		Shapes.arch(u, ctr + n * 0.072, 1.11, 1.165, 0.048, 32, wb, 0.0, TAU, ["front", "outer"])

		# 3. Twenty domed brass hex-head pressure bolts evenly spaced around the heavy flange ring (r = 1.025).
		var bolt_n := 20
		var bolt_basis := wb * Basis(Vector3.RIGHT, PI * 0.5)
		for k in bolt_n:
			var ang := float(k) * TAU / float(bolt_n)
			var bp := ctr + wb * Vector3(cos(ang) * 1.025, sin(ang) * 1.025, 0.088)
			Shapes.cylinder(u, bp, 0.026, 0.022, 6, bolt_basis)
			Shapes.cylinder(u, bp + n * 0.022, 0.014, 0.008, 6, bolt_basis)

		# 4. Ornate mechanical brass iris hand-crank actuator wheel & vertical pinion shaft tucked at lower-aft flank.
		var crank_dir := -side # aft along local wall X (starboard wall +X is +Z aft; port wall +X is -Z forward)
		var wheel_c := ctr + wb * Vector3(crank_dir * 1.04, -0.76, 0.135)
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.arch(u, wheel_c, 0.125, 0.155, 0.024, 16, wb, 0.0, TAU, ["front", "back", "inner", "outer"])
		Shapes.cylinder(u, wheel_c - n * 0.08, 0.028, 0.10, 10, bolt_basis)
		for sp in 5:
			var sa := float(sp) * TAU / 5.0
			var tip := wheel_c + wb * Vector3(cos(sa) * 0.135, sin(sa) * 0.135, 0.0)
			Shapes.beam(u, wheel_c, tip, Vector2(0.014, 0.014), n)
		# Brass worm-gear housing rod linking wheel hub up into the outer viewport ring gear.
		var gear_top := ctr + wb * Vector3(crank_dir * 0.94, -0.62, 0.085)
		Shapes.beam(u, wheel_c - n * 0.04, gear_top, Vector2(0.024, 0.024), n)

		# 5. Low sculpted mahogany & brass curved sill console neatly below the viewport ring.
		var sill_p := Cabin._pt(q, side, wz, 0.30) + n * 0.09
		s.surface(c.tinted("wood"))
		s.colour = MAHOGANY.srgb_to_linear()
		s.box(sill_p, Vector3(1.86, 0.055, 0.18), wb)
		s.colour = MAHOGANY_DARK.srgb_to_linear()
		for dz: float in [-0.74, 0.0, 0.74]:
			s.box(Cabin._pt(q, side, wz + dz, 0.15) + n * 0.075, Vector3(0.08, 0.25, 0.14), wb)
		u.colour = BRASS_WARM.srgb_to_linear()
		u.box(sill_p + wb * Vector3(0.0, 0.036, 0.072), Vector3(1.82, 0.016, 0.016), wb)


## Victorian mahogany, crimson-velvet and gilded-brass screen proscenium on a stepped dais, ornate brass compass-rose
## tympanum crest, and indirect architectural cove washes (PieceCove) along the proscenium and vaulted ceiling eaves.
static func _proscenium_and_coves(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(3.2, 1.8))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var hw := sc_sz.x * 0.5
	var hh := sc_sz.y * 0.5
	var sc_bot := cy - hh
	var sc_top := cy + hh
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var floor_hw := float(q["hw"])
	var wall_h := float(q["wall_height"])
	var top_half := float(q["top_half"])

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove

	# 1. Low stepped mahogany & brass dais beneath the forward screen bulkhead.
	var dais_w := floor_hw * 2.0 - 0.12
	var dais_h := 0.22
	var dais_d := 0.52
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.05, fz + dais_d * 0.5), Vector3(dais_w, 0.10, dais_d), Basis(), [RoomMesh.DOWN])
	s.colour = MAHOGANY.srgb_to_linear()
	s.box(Vector3(cx, 0.16, fz + dais_d * 0.44), Vector3(dais_w - 0.14, 0.12, dais_d * 0.88), Basis(), [RoomMesh.DOWN])
	c.shapes.append(PhysicsShapes.box(Vector3(cx, dais_h * 0.5, fz + dais_d * 0.5), Vector3(dais_w, dais_h, dais_d),
			Basis()))

	# Gleaming brass step nosing rails along the dais.
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx, 0.215, fz + dais_d * 0.88 + 0.008), Vector3(dais_w - 0.12, 0.022, 0.020))
	u.box(Vector3(cx, 0.098, fz + dais_d + 0.008), Vector3(dais_w, 0.020, 0.018))

	# 2. Panelled mahogany dado under the screen + fluted Victorian pilasters flanking the picture.
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY.srgb_to_linear()
	var under_h := sc_bot - 0.04 - dais_h
	s.box(Vector3(cx, dais_h + under_h * 0.5, fz + 0.05), Vector3(sc_sz.x + 0.16, under_h, 0.10))
	# Recessed decorative mahogany wainscot panels under the screen framed by slim hollow brass bead mouldings!
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	u.colour = BRASS_WARM.srgb_to_linear()
	var pan_w := 0.56
	var pan_h := under_h - 0.22
	var pan_y := dais_h + under_h * 0.5
	for k in 4:
		var px := cx - hw + 0.42 + float(k) * (sc_sz.x - 0.84) / 3.0
		s.box(Vector3(px, pan_y, fz + 0.106), Vector3(pan_w, pan_h, 0.018))
		# Slim 4-bar hollow brass picture-frame bead moulding around each sunken mahogany panel.
		for sy: float in [-pan_h * 0.5, pan_h * 0.5]:
			u.box(Vector3(px, pan_y + sy, fz + 0.118), Vector3(pan_w + 0.02, 0.018, 0.014))
		for sx: float in [-pan_w * 0.5, pan_w * 0.5]:
			u.box(Vector3(px + sx, pan_y, fz + 0.118), Vector3(0.018, pan_h + 0.02, 0.014))

	# Flanking fluted mahogany & gilded-brass proscenium columns (outside hw + 0.08 so strictly clear of the picture).
	for side: float in [-1.0, 1.0]:
		var col_x := cx + side * (hw + 0.24)
		var col_top := minf(_roof_y(q, col_x + side * 0.14) - 0.06, sc_top + 0.16)
		var col_h := col_top - dais_h
		s.surface(c.tinted("wood"))
		s.colour = MAHOGANY.srgb_to_linear()
		s.box(Vector3(col_x, dais_h + col_h * 0.5, fz + 0.14), Vector3(0.28, col_h, 0.28), Basis(), [RoomMesh.DOWN])
		# Stepped base plinth and carved capital cornice.
		s.colour = MAHOGANY_DARK.srgb_to_linear()
		s.box(Vector3(col_x, dais_h + 0.18, fz + 0.16), Vector3(0.34, 0.36, 0.32), Basis(), [RoomMesh.DOWN])
		s.box(Vector3(col_x, col_top - 0.08, fz + 0.16), Vector3(0.36, 0.16, 0.34))
		# Vertical gilded brass inlay flutes & capital collars.
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		for df: float in [-0.07, 0.0, 0.07]:
			u.box(Vector3(col_x + df, dais_h + col_h * 0.5 + 0.08, fz + 0.284), Vector3(0.016, col_h - 0.56, 0.014))
		u.box(Vector3(col_x, dais_h + 0.365, fz + 0.165), Vector3(0.36, 0.024, 0.34))
		u.box(Vector3(col_x, col_top - 0.165, fz + 0.165), Vector3(0.36, 0.024, 0.34))

		# Sumptuous deep crimson-velvet side drapery folds flanking the outer pilasters (x = cx +- 1.98..2.26).
		s.surface(c.tinted("fabric"))
		s.colour = VELVET_CRIMSON.srgb_to_linear()
		var drp_x := cx + side * (hw + 0.54)
		var drp_top := _roof_y(q, drp_x + side * 0.16) - 0.06
		var drp_h := drp_top - dais_h
		for pf in 3:
			var fx := drp_x + side * (float(pf) - 1.0) * 0.115
			var fd := 0.22 + (0.045 if pf % 2 == 0 else -0.02)
			s.colour = (VELVET_CRIMSON if pf % 2 == 0 else VELVET_DEEP).srgb_to_linear()
			s.box(Vector3(fx, dais_h + drp_h * 0.5, fz + fd * 0.5), Vector3(0.11, drp_h, fd), Basis(), [RoomMesh.DOWN])
		# Gilded brass tieback band cinching the velvet side drape gracefully at waist height!
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		u.box(Vector3(drp_x, 1.24, fz + 0.16), Vector3(0.36, 0.055, 0.24))
		c.shapes.append(PhysicsShapes.box(Vector3(cx + side * (hw + 0.42), dais_h + drp_h * 0.5, fz + 0.15),
				Vector3(0.64, drp_h, 0.30), Basis()))

	# 3. Heavy burnished-brass screen surround frame & scalloped crimson-velvet header pelmet above the picture.
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	var f_t := 0.065
	for side: float in [-1.0, 1.0]:
		u.box(Vector3(cx + side * (hw + f_t * 0.5), cy, fz + 0.055), Vector3(f_t, sc_sz.y + f_t * 2.0, 0.075))
	u.box(Vector3(cx, sc_bot - f_t * 0.5, fz + 0.055), Vector3(sc_sz.x + f_t * 2.0, f_t, 0.075))
	u.box(Vector3(cx, sc_top + f_t * 0.5, fz + 0.055), Vector3(sc_sz.x + f_t * 2.0, f_t, 0.075))
	# Crimson-velvet & gold-braid header pelmet valance spanning cleanly above the screen frame.
	s.surface(c.tinted("fabric"))
	s.colour = VELVET_CRIMSON.srgb_to_linear()
	s.box(Vector3(cx, sc_top + 0.145, fz + 0.15), Vector3(sc_sz.x + 0.72, 0.15, 0.22))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx, sc_top + 0.068, fz + 0.262), Vector3(sc_sz.x + 0.74, 0.022, 0.020))
	u.box(Vector3(cx, sc_top + 0.222, fz + 0.262), Vector3(sc_sz.x + 0.74, 0.022, 0.020))

	# Ornate Victorian brass astrolabe & compass-rose crest medallion crowning the proscenium arch!
	var crest := Vector3(cx, sc_top + 0.16, fz + 0.275)
	Shapes.arch(u, crest, 0.085, 0.125, 0.026, 20, Basis(), 0.0, TAU, ["front", "inner", "outer"])
	for k in 8:
		var ang := float(k) * PI * 0.25
		var sp_len := 0.21 if (k % 2 == 0) else 0.145
		u.box(crest + Vector3(0.0, 0.0, 0.01), Vector3(0.018, sp_len * 2.0, 0.014), Basis(Vector3.BACK, ang))
	u.surface(c.soft("plastic", true))
	u.colour = VELVET_CRIMSON.srgb_to_linear()
	Shapes.cylinder(u, crest + Vector3(0.0, 0.0, 0.008), 0.052, 0.024, 14, Basis(Vector3.RIGHT, PI * 0.5))

	# 4. Warm indirect architectural cove lighting (PieceCove): vertical proscenium pilasters, header soffit, and
	#    tucked upper-eave mahogany cornice troughs washing warm amber / sea-turquoise light onto the vaulted ceiling!
	cove.surface(c.kit.cove_material())
	var cove_lin := Color(0.95, 0.88, 0.74).srgb_to_linear()
	cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.92)
	for side: float in [-1.0, 1.0]:
		var vx := cx + side * (hw + 0.10)
		cove.face([Vector3(vx - 0.032, dais_h + 0.08, fz + 0.145), Vector3(vx + 0.032, dais_h + 0.08, fz + 0.145),
				Vector3(vx + 0.032, sc_top + 0.02, fz + 0.145), Vector3(vx - 0.032, sc_top + 0.02, fz + 0.145)],
				Vector3.BACK)
	# Under-pelmet warm cove strip above the screen.
	cove.face([Vector3(cx - hw - 0.08, sc_top + 0.04, fz + 0.20), Vector3(cx + hw + 0.08, sc_top + 0.04, fz + 0.20),
			Vector3(cx + hw + 0.08, sc_top + 0.04, fz + 0.10), Vector3(cx - hw - 0.08, sc_top + 0.04, fz + 0.10)],
			Vector3.DOWN)
	# Tucked mahogany eave cornice ledges + upward indirect vaulted hull cove wash along both sides!
	var cove_span := bz - fz - 0.24
	var cove_mid := (fz + bz) * 0.5
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_WARM.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var x_wall := cx + side * (top_half - 0.02)
		var x_lip := cx + side * (top_half - 0.13)
		var y_val := wall_h - 0.05
		s.box(Vector3(x_lip, y_val, cove_mid), Vector3(0.028, 0.056, cove_span))
		s.box(Vector3((x_wall + x_lip) * 0.5, y_val - 0.022, cove_mid), Vector3(absf(x_wall - x_lip), 0.020, cove_span))
		u.box(Vector3(x_lip - side * 0.016, y_val - 0.014, cove_mid), Vector3(0.014, 0.016, cove_span))
		# Soft architectural cove wash fading smoothly from warm glow at the cornice lip to 0 across the curved vault!
		var x_c0 := cx + side * (top_half - 0.03)
		var x_c1 := cx + side * (top_half - 0.14)
		var x_c2 := cx + side * (top_half - 0.34)
		var y_c0 := wall_h + 0.008
		var y_c1 := _roof_y(q, x_c1) - 0.006
		var y_c2 := _roof_y(q, x_c2) - 0.006
		var n_c0 := Vector3(-side * 0.34, -0.94, 0.0).normalized()
		var n_c1 := Vector3(-side * 0.28, -0.96, 0.0).normalized()
		var n_c2 := Vector3(-side * 0.22, -0.975, 0.0).normalized()
		var col0 := Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.78)
		var col1 := Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.26)
		var col2 := Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.0)
		var za := fz + 0.20
		var zb := bz - 0.20
		var rows_c := [
			PackedVector3Array([Vector3(x_c0, y_c0, za), Vector3(x_c0, y_c0, zb)]),
			PackedVector3Array([Vector3(x_c1, y_c1, za), Vector3(x_c1, y_c1, zb)]),
			PackedVector3Array([Vector3(x_c2, y_c2, za), Vector3(x_c2, y_c2, zb)]),
		]
		var norms_c := [
			PackedVector3Array([n_c0, n_c0]),
			PackedVector3Array([n_c1, n_c1]),
			PackedVector3Array([n_c2, n_c2]),
		]
		var cols_c := [
			PackedColorArray([col0, col0]),
			PackedColorArray([col1, col1]),
			PackedColorArray([col2, col2]),
		]
		if side > 0.0:
			rows_c.reverse()
			norms_c.reverse()
			cols_c.reverse()
		cove.grid(rows_c, norms_c, cols_c)


## Four custom Victorian flank mahogany cabinets: two tall forward brass-grilled library bookcases packed with
## leather-bound maritime atlases (plus an antique brass-mounted globe), and two aft naturalist's specimen credenzas
## holding an armillary sphere, spiral nautilus shell curiosity, brass marine spyglass and bound logs.
static func _bookcases_and_vitrines(c: Object, q: Dictionary) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var rng := RandomNumberGenerator.new()
	rng.seed = 1870
	var book_palette: Array[Color] = [
		Color(0.52, 0.11, 0.13), # crimson morocco
		Color(0.14, 0.24, 0.34), # admiralty navy
		Color(0.15, 0.30, 0.20), # bottle green
		Color(0.46, 0.26, 0.12), # chestnut calfskin
		Color(0.62, 0.44, 0.16), # ochre vellum
		Color(0.28, 0.16, 0.24), # plum leather
	]

	# --- 1. Two tall forward library bookcases (port & starboard, z = -3.60 .. -2.10, length = 1.50 m) ---
	for side: float in [-1.0, 1.0]:
		var z_mid := -2.85
		var len_z := 1.48
		var depth := 0.33
		var height := 2.34
		var wb := Cabin._wall_basis(q, side)
		var n := Cabin._n(q, side)
		var base_c := Cabin._pt(q, side, z_mid, 0.0)
		var x_in := base_c + n * (depth * 0.5)

		# Mahogany carcass: solid lower panelled cupboard, side uprights, back panel, top crown cornice & 4 shelves.
		s.surface(c.tinted("wood"))
		s.colour = MAHOGANY_DARK.srgb_to_linear()
		# Lower cupboard body (y = 0 .. 0.74).
		s.box(x_in + wb.y * 0.37, Vector3(len_z, 0.74, depth), wb, [RoomMesh.DOWN])
		# Backboard & upper side uprights.
		s.box(base_c + n * 0.02 + wb.y * (0.74 + (height - 0.74) * 0.5), Vector3(len_z - 0.04, height - 0.74, 0.03), wb)
		s.colour = MAHOGANY.srgb_to_linear()
		for sz: float in [-len_z * 0.5 + 0.035, 0.0, len_z * 0.5 - 0.035]:
			s.box(x_in + wb.x * sz + wb.y * (0.74 + (height - 0.74) * 0.5), Vector3(0.06, height - 0.74, depth), wb)
		# Lower cupboard raised door panels + waist ledge + moulded top crown cornice.
		for dz: float in [-len_z * 0.24, len_z * 0.24]:
			s.box(x_in + wb.x * dz + wb.y * 0.38 + n * (depth * 0.5 + 0.008), Vector3(len_z * 0.40, 0.48, 0.022), wb)
		s.box(x_in + wb.y * 0.75 + n * 0.015, Vector3(len_z + 0.06, 0.042, depth + 0.035), wb)
		s.box(x_in + wb.y * (height - 0.04) + n * 0.02, Vector3(len_z + 0.08, 0.085, depth + 0.05), wb)

		# Four shelf boards inside the upper library case.
		var shelf_ys: Array[float] = [0.77, 1.16, 1.54, 1.92]
		for sy: float in shelf_ys:
			if sy > 0.78:
				s.box(x_in + wb.y * sy, Vector3(len_z - 0.08, 0.028, depth - 0.04), wb)

		# Leather-bound atlases & volumes packed along the shelves (leaving lower-right starboard niche for a globe!).
		s.surface(c.tinted("fabric"))
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		for si in shelf_ys.size():
			var sy := shelf_ys[si] + 0.016
			for bay in 2:
				# Leave starboard bay 1 on the lowest shelf open for a brass-mounted terrestrial specimen globe!
				if side > 0.0 and si == 0 and bay == 1:
					continue
				var u0 := -len_z * 0.5 + 0.085 + float(bay) * (len_z * 0.5 - 0.035)
				var u1 := u0 + len_z * 0.5 - 0.145
				var cur := u0
				while cur < u1 - 0.055:
					var bw := rng.randf_range(0.036, 0.062)
					var bh := rng.randf_range(0.24, 0.32)
					var bd := rng.randf_range(0.18, 0.24)
					var col: Color = book_palette[rng.randi() % book_palette.size()]
					s.colour = col.srgb_to_linear()
					var bp := base_c + wb.x * (cur + bw * 0.5) + wb.y * (sy + bh * 0.5) + n * (0.05 + bd * 0.5)
					s.box(bp, Vector3(bw - 0.004, bh, bd), wb)
					# Tiny gilded brass spine band on every second folio!
					if rng.randf() < 0.55:
						u.box(bp + n * (bd * 0.5 + 0.003) + wb.y * (bh * 0.24), Vector3(bw - 0.008, 0.014, 0.006), wb)
					cur += bw

		# Brass cupboard handles + criss-cross diamond brass protective sea-grille bars over the bookcase bays!
		u.colour = BRASS_WARM.srgb_to_linear()
		for dz: float in [-0.14, 0.14]:
			u.box(x_in + wb.x * dz + wb.y * 0.44 + n * (depth * 0.5 + 0.025), Vector3(0.022, 0.07, 0.022), wb)
		# Horizontal brass sea-fiddle rails + fine diagonal brass lattice rods across each upper door frame.
		for sy: float in shelf_ys:
			u.box(x_in + wb.y * (sy + 0.08) + n * (depth * 0.5 - 0.01), Vector3(len_z - 0.08, 0.012, 0.012), wb)
		for bay in 2:
			if side > 0.0 and bay == 1:
				# Leave bottom niche open in front of the terrestrial globe; grille the upper three shelves only.
				_brass_grille(u, base_c, wb, n, 0.04, len_z * 0.5 - 0.06, 1.18, height - 0.10, depth - 0.012)
			else:
				_brass_grille(u, base_c, wb, n, -len_z * 0.5 + 0.06 if bay == 0 else 0.04,
						-0.04 if bay == 0 else len_z * 0.5 - 0.06, 0.79, height - 0.10, depth - 0.012)

		# Starboard forward open niche: antique ocean-teal & brass-meridian terrestrial specimen globe!
		if side > 0.0:
			var g_base := base_c + wb.x * (len_z * 0.25) + wb.y * 0.785 + n * (depth * 0.52)
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			Shapes.lathe(u, [Vector2(0.09, 0.0), Vector2(0.09, 0.018), Vector2(0.032, 0.035),
					Vector2(0.022, 0.10)], g_base, 12, wb)
			var g_ctr := g_base + wb.y * 0.215
			Shapes.arch(u, g_ctr, 0.118, 0.132, 0.016, 18, wb, -PI * 0.5, PI * 0.5, ["front", "back", "inner", "outer"])
			u.surface(c.soft("plastic", true))
			u.colour = OCEAN_GLOBE.srgb_to_linear()
			Shapes.dome(u, g_ctr, 0.106, 6, 14, false, -PI * 0.5, PI * 0.5)
			u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			# Equator brass band.
			Shapes.cylinder(u, g_ctr - wb.y * 0.008, 0.109, 0.016, 14, wb)

		# Physics box strictly inside the cabin (keep foot flush at y = 0 regardless of the 3-deg wall lean).
		var box_p := Cabin._pt(q, side, z_mid, height * 0.5) + n * (depth * 0.5)
		box_p.y = height * 0.5
		c.shapes.append(PhysicsShapes.box(box_p, Vector3(depth, height, len_z), Basis()))

	# --- 2. Two aft naturalist's specimen credenzas & vitrines (port & starboard, z = +1.10 .. +2.14, len = 1.04 m) ---
	for side: float in [-1.0, 1.0]:
		var z_mid := 1.62
		var len_z := 1.04
		var depth := 0.34
		var height := 2.24
		var wb := Cabin._wall_basis(q, side)
		var n := Cabin._n(q, side)
		var base_c := Cabin._pt(q, side, z_mid, 0.0)
		var x_in := base_c + n * (depth * 0.5)

		s.surface(c.tinted("wood"))
		s.colour = MAHOGANY_DARK.srgb_to_linear()
		# Lower chart-drawer chest (y = 0 .. 0.84).
		s.box(x_in + wb.y * 0.42, Vector3(len_z, 0.84, depth), wb, [RoomMesh.DOWN])
		# Backboard & upper vitrine uprights.
		s.box(base_c + n * 0.02 + wb.y * (0.84 + (height - 0.84) * 0.5), Vector3(len_z - 0.04, height - 0.84, 0.03), wb)
		s.colour = MAHOGANY.srgb_to_linear()
		for sz: float in [-len_z * 0.5 + 0.035, len_z * 0.5 - 0.035]:
			s.box(x_in + wb.x * sz + wb.y * (0.84 + (height - 0.84) * 0.5), Vector3(0.06, height - 0.84, depth), wb)
		# Three horizontal map-drawer fronts with gleaming brass cup pulls.
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		for k in 3:
			var dy := 0.18 + float(k) * 0.22
			s.box(x_in + wb.y * dy + n * (depth * 0.5 + 0.008), Vector3(len_z - 0.12, 0.17, 0.02), wb)
			for px: float in [-0.24, 0.24]:
				u.box(x_in + wb.x * px + wb.y * dy + n * (depth * 0.5 + 0.024), Vector3(0.075, 0.022, 0.020), wb)
		# Credenza top shelf, upper display shelf, and carved crown cornice.
		s.box(x_in + wb.y * 0.855 + n * 0.016, Vector3(len_z + 0.06, 0.042, depth + 0.04), wb)
		s.box(x_in + wb.y * 1.54, Vector3(len_z - 0.08, 0.030, depth - 0.04), wb)
		s.box(x_in + wb.y * (height - 0.04) + n * 0.02, Vector3(len_z + 0.08, 0.08, depth + 0.05), wb)
		# Brass anti-roll sea rail along the vitrine ledge.
		u.box(x_in + wb.y * 0.92 + n * (depth * 0.5 + 0.01), Vector3(len_z - 0.06, 0.012, 0.012), wb)
		u.box(x_in + wb.y * 1.62 + n * (depth * 0.5 - 0.01), Vector3(len_z - 0.08, 0.012, 0.012), wb)

		# Upper shelf: bound oceanographic expedition journals.
		s.surface(c.tinted("fabric"))
		var cur := -len_z * 0.5 + 0.09
		while cur < len_z * 0.5 - 0.14:
			var bw := rng.randf_range(0.040, 0.064)
			var bh := rng.randf_range(0.26, 0.35)
			s.colour = book_palette[rng.randi() % book_palette.size()].srgb_to_linear()
			s.box(base_c + wb.x * (cur + bw * 0.5) + wb.y * (1.56 + bh * 0.5) + n * 0.16,
					Vector3(bw - 0.004, bh, 0.22), wb)
			cur += bw

		# Centerpiece Victorian curiosities in the open waist niche (y = 0.88 .. 1.50)!
		var niche_y := 0.88
		if side < 0.0:
			# Port vitrine: polished brass armillary sphere + cream spiral nautilus shell sculpture on ebony plinth!
			var arm_p := base_c + wb.x * (-0.20) + wb.y * niche_y + n * 0.18
			u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			Shapes.lathe(u, [Vector2(0.085, 0.0), Vector2(0.085, 0.02), Vector2(0.024, 0.04),
					Vector2(0.020, 0.12)], arm_p, 12, wb)
			var ac := arm_p + wb.y * 0.26
			Shapes.arch(u, ac, 0.125, 0.140, 0.014, 18, wb, 0.0, TAU, ["front", "back", "inner", "outer"])
			Shapes.arch(u, ac, 0.112, 0.126, 0.014, 18, wb * Basis(Vector3.UP, PI * 0.5), 0.0, TAU,
					["front", "back", "inner", "outer"])
			Shapes.arch(u, ac, 0.105, 0.118, 0.014, 18, wb * Basis(Vector3.RIGHT, deg_to_rad(66.5)), 0.0, TAU,
					["front", "back", "inner", "outer"])
			Shapes.beam(u, ac - wb.y * 0.14, ac + wb.y * 0.14, Vector2(0.010, 0.010), n)
			# Spiral ivory-pearl chambered shell sculpture on a dark pedestal beside it.
			var sh_p := base_c + wb.x * 0.22 + wb.y * niche_y + n * 0.18
			u.surface(c.soft("iron", true))
			u.colour = EBONY.srgb_to_linear()
			u.box(sh_p + wb.y * 0.025, Vector3(0.16, 0.05, 0.12), wb)
			u.surface(c.soft("plastic", true))
			u.colour = PARCHMENT.srgb_to_linear()
			var sc_ctr := sh_p + wb.y * 0.18
			for k in 9:
				var th := float(k) * 0.58
				var rad := 0.024 + float(k) * 0.011
				var sp_r := 0.018 + float(k) * 0.0055
				var pt := sc_ctr + wb.x * (cos(th) * rad) + wb.y * (sin(th) * rad)
				u.box(pt, Vector3(sp_r * 1.8, sp_r * 1.8, sp_r * 1.4), wb * Basis(Vector3.BACK, th))
		else:
			# Starboard vitrine: polished brass marine spyglass on twin brass crutches + brass astrolabe quadrant!
			var spy_p := base_c + wb.x * (-0.04) + wb.y * (niche_y + 0.16) + n * 0.18
			u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
			u.colour = BRASS_BRIGHT.srgb_to_linear()
			var cyl_x := wb * Basis(Vector3.BACK, -PI * 0.5)
			Shapes.cylinder(u, spy_p - wb.x * 0.30, 0.032, 0.34, 12, cyl_x)
			Shapes.cylinder(u, spy_p + wb.x * 0.04, 0.024, 0.18, 12, cyl_x)
			Shapes.cylinder(u, spy_p + wb.x * 0.22, 0.016, 0.10, 10, cyl_x)
			# Twin mahogany-and-brass cradle stands supporting the spyglass.
			for dx: float in [-0.18, 0.14]:
				Shapes.beam(u, base_c + wb.x * dx + wb.y * niche_y + n * 0.18,
						base_c + wb.x * dx + wb.y * (niche_y + 0.145) + n * 0.18, Vector2(0.018, 0.018), n)
				u.box(base_c + wb.x * dx + wb.y * (niche_y + 0.012) + n * 0.18, Vector3(0.09, 0.024, 0.09), wb)

		var box_p := Cabin._pt(q, side, z_mid, height * 0.5) + n * (depth * 0.5)
		box_p.y = height * 0.5
		c.shapes.append(PhysicsShapes.box(box_p, Vector3(depth, height, len_z), Basis()))


## Fine diagonal diamond brass lattice grille across a bookcase bay.
static func _brass_grille(u: RoomMesh, base_c: Vector3, wb: Basis, n: Vector3, u0: float, u1: float, y0: float,
		y1: float, d_off: float) -> void:
	var cols := 3
	var rows := 4
	var du := (u1 - u0) / float(cols)
	var dy := (y1 - y0) / float(rows)
	for ix in cols:
		for iy in rows:
			var a := base_c + wb.x * (u0 + float(ix) * du) + wb.y * (y0 + float(iy) * dy) + n * d_off
			var b_pt := base_c + wb.x * (u0 + float(ix + 1) * du) + wb.y * (y0 + float(iy + 1) * dy) + n * d_off
			var c_pt := base_c + wb.x * (u0 + float(ix + 1) * du) + wb.y * (y0 + float(iy) * dy) + n * d_off
			var d_pt := base_c + wb.x * (u0 + float(ix) * du) + wb.y * (y0 + float(iy + 1) * dy) + n * d_off
			Shapes.beam(u, a, b_pt, Vector2(0.006, 0.006), n)
			Shapes.beam(u, c_pt, d_pt, Vector2(0.006, 0.006), n)


## Six ornate gooseneck marine brass wall sconces with protective wire cages and two overhead brass-caged ceiling dome
## lanterns (PieceLamps + 4 warm bake lamps).
static func _marine_lamps(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var headroom := float(q["headroom"])
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit

	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	lit.surface(c.shade(LAMP_AMBER))

	# 1. Six marine brass wall sconces mounted on the main structural hull ribs (port & starboard).
	var sconce_zs: Array[float] = [-1.86, 0.86, 2.32]
	var sconce_y := 1.98
	for side: float in [-1.0, 1.0]:
		var wb := Cabin._wall_basis(q, side)
		var n := Cabin._n(q, side)
		var back_rot := wb * Basis(Vector3.RIGHT, PI * 0.5)
		for sz: float in sconce_zs:
			var wall_p := Cabin._pt(q, side, sz, sconce_y / cos(float(q["L"]))) + n * 0.135
			# Turned circular brass backplate + stepped gooseneck bracket arm.
			Shapes.cylinder(u, wall_p, 0.068, 0.020, 12, back_rot)
			var arm_mid := wall_p + n * 0.10 + Vector3(0.0, 0.02, 0.0)
			var globe_top := wall_p + n * 0.155 + Vector3(0.0, -0.02, 0.0)
			Shapes.beam(u, wall_p + n * 0.01, arm_mid, Vector2(0.018, 0.018))
			Shapes.beam(u, arm_mid, globe_top + Vector3(0.0, 0.04, 0.0), Vector2(0.016, 0.016))
			# Flared brass lantern cap + bottom finial nut + 4 slim protective brass cage ribs.
			Shapes.lathe(u, [Vector2(0.058, 0.0), Vector2(0.052, 0.022), Vector2(0.024, 0.042)],
					globe_top, 12)
			Shapes.lathe(u, [Vector2(0.0, -0.175), Vector2(0.028, -0.155), Vector2(0.044, -0.142)],
					globe_top, 12)
			for k in 4:
				var ca := float(k) * PI * 0.5 + PI * 0.25
				var off := Vector3(cos(ca) * 0.056, 0.0, sin(ca) * 0.056)
				Shapes.beam(u, globe_top + off * 0.9, globe_top + off - Vector3(0.0, 0.145, 0.0),
						Vector2(0.006, 0.006))
			# Glowing warm-amber ribbed marine glass globe (PieceLamps).
			Shapes.lathe(lit, [
				Vector2(0.0, -0.145), Vector2(0.036, -0.135), Vector2(0.048, -0.095),
				Vector2(0.046, -0.025), Vector2(0.034, 0.0)
			], globe_top, 12)
			if sz == -1.86 or sz == 0.86:
				c.lamps.append([globe_top - Vector3(0.0, 0.08, 0.0) + n * 0.08, LAMP_AMBER, 0.58])

	# 2. Two grand overhead brass-caged ceiling dome lanterns suspended along the vaulted crown spine
	#    (bottom at y = 2.88 m, strictly above all sight lines!).
	for lz: float in [-1.18, 1.48]:
		var ceil_p := Vector3(cx, headroom - 0.10, lz)
		# Heavy bolted brass ceiling canopy + short suspension stem + decorative ring collar.
		Shapes.lathe(u, [
			Vector2(0.16, 0.0), Vector2(0.15, -0.028), Vector2(0.06, -0.042),
			Vector2(0.026, -0.095), Vector2(0.145, -0.115), Vector2(0.155, -0.135), Vector2(0.135, -0.140)
		], ceil_p, 16)
		# Bottom brass crown finial & equatorial protective cage ring + 6 curved brass meridian bars.
		var dome_c := ceil_p + Vector3(0.0, -0.14, 0.0)
		Shapes.arch(u, dome_c + Vector3(0.0, -0.065, 0.0), 0.138, 0.152, 0.014, 18,
				Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU, ["front", "back", "inner", "outer"])
		Shapes.lathe(u, [Vector2(0.0, -0.195), Vector2(0.032, -0.165), Vector2(0.048, -0.145)], dome_c, 12)
		for k in 6:
			var a := float(k) * TAU / 6.0
			var p_top := dome_c + Vector3(cos(a) * 0.145, 0.0, sin(a) * 0.145)
			var p_mid := dome_c + Vector3(cos(a) * 0.148, -0.085, sin(a) * 0.148)
			var p_bot := dome_c + Vector3(cos(a) * 0.042, -0.150, sin(a) * 0.042)
			Shapes.beam(u, p_top, p_mid, Vector2(0.008, 0.008))
			Shapes.beam(u, p_mid, p_bot, Vector2(0.008, 0.008))
		# Glowing warm-amber glass ceiling lantern hemisphere.
		Shapes.lathe(lit, [
			Vector2(0.0, -0.148), Vector2(0.075, -0.136), Vector2(0.122, -0.095),
			Vector2(0.134, -0.035), Vector2(0.126, 0.0)
		], dome_c, 16)
		c.lamps.append([dome_c + Vector3(0.0, -0.16, 0.0), LAMP_AMBER, 0.85])


## Aft Victorian centerpiece: 21-pipe mahogany-and-brass salon pipe organ with twin ivory/ebony manuals, glowing music
## rack, pedalboard & crimson-velvet bench; working brass marine chronometer (PieceClock) crowning the organ arch;
## starboard brass navigation binnacle with quadrantal spheres & engine-room telegraph dial; port ballast manifold with
## spoked brass isolation handwheels and six illuminated brass pressure/depth gauges (PieceWindows).
static func _aft_organ_and_instruments(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var bz := float(q["back_z"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var basis_aft := Basis(Vector3.UP, PI)

	# --- 1. Grand Victorian 21-Pipe Salon Pipe Organ centered on the aft bulkhead (x = cx, z = 3.06 .. 3.58) ---
	var org_z := bz - 0.28 # 3.32
	var org_w := 2.08
	var org_d := 0.52

	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	# Solid panelled mahogany lower organ base chest & pedal housing (y = 0 .. 1.18).
	s.box(Vector3(cx, 0.59, org_z), Vector3(org_w, 1.18, org_d), Basis(), [RoomMesh.DOWN])
	# Recessed upper pipe-case backboard & flanking mahogany organ towers rising into the hull arch.
	s.box(Vector3(cx, 2.04, bz - 0.08), Vector3(org_w - 0.08, 1.78, 0.12))
	s.colour = MAHOGANY.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var tx := cx + side * (org_w * 0.5 - 0.14)
		var top_y := minf(_roof_y(q, tx + side * 0.14) - 0.08, 3.06)
		s.box(Vector3(tx, top_y * 0.5, org_z + 0.04), Vector3(0.28, top_y, 0.40), Basis(), [RoomMesh.DOWN])
		# Ornate stepped tower crown cornice.
		s.box(Vector3(tx, top_y + 0.03, org_z + 0.02), Vector3(0.34, 0.08, 0.46))
		# Cheek armrests framing the protruding keydesk.
		s.box(Vector3(cx + side * 0.58, 0.88, org_z - 0.32), Vector3(0.08, 0.34, 0.34))
	# Keydesk waist shelf & panelled front kickboard.
	s.box(Vector3(cx, 0.72, org_z - 0.28), Vector3(1.24, 0.12, 0.38))
	s.box(Vector3(cx, 1.19, org_z - 0.02), Vector3(org_w + 0.08, 0.06, org_d + 0.06))
	# Pipe-rack horizontal cross-bar holding the 21 brass pipes cleanly in rank.
	s.box(Vector3(cx, 1.48, org_z - 0.14), Vector3(org_w - 0.48, 0.055, 0.06))

	# Twin stepped ivory & ebony organ keyboard manuals (facing -Z toward the salon!).
	u.surface(c.soft("plastic", true))
	var key_w := 1.04
	for m in 2:
		var ky := 0.805 + 0.072 * float(m)
		var kz := org_z - 0.38 + 0.11 * float(m)
		u.colour = IVORY.srgb_to_linear()
		u.box(Vector3(cx, ky, kz), Vector3(key_w, 0.022, 0.135))
		u.surface(c.soft("iron", true))
		u.colour = EBONY.srgb_to_linear()
		for k in 49:
			if k % 12 in [1, 3, 6, 8, 10]:
				var kx := cx - key_w * 0.5 + (float(k) + 0.5) * key_w / 49.0
				u.box(Vector3(kx, ky + 0.016, kz + 0.026), Vector3(key_w / 49.0 * 0.62, 0.014, 0.080),
						Basis(), [RoomMesh.DOWN])
		u.surface(c.soft("plastic", true))
		# Brass keyslip trim bar below each manual.
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		u.box(Vector3(cx, ky - 0.020, kz - 0.070), Vector3(key_w + 0.02, 0.022, 0.012))
		u.surface(c.soft("plastic", true))

	# Flanking Victorian ivory-tipped draw-stop jamb knobs (2 columns x 4 rows per side).
	for side: float in [-1.0, 1.0]:
		for row in 4:
			for col in 2:
				var sx := cx + side * (0.68 + float(col) * 0.065)
				var sy := 0.82 + float(row) * 0.068
				var sz := org_z - 0.27
				u.surface(c.soft("iron", true))
				u.colour = EBONY.srgb_to_linear()
				Shapes.cylinder(u, Vector3(sx, sy, sz), 0.008, 0.032, 8, Basis(Vector3.RIGHT, -PI * 0.5))
				u.surface(c.soft("plastic", true))
				u.colour = IVORY.srgb_to_linear()
				Shapes.cylinder(u, Vector3(sx, sy, sz - 0.032), 0.015, 0.010, 10, Basis(Vector3.RIGHT, -PI * 0.5))

	# Illuminated parchment music rack & glowing brass music-desk lamp!
	var desk_b := Basis(Vector3.RIGHT, deg_to_rad(18.0))
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY.srgb_to_linear()
	s.box(Vector3(cx, 1.05, org_z - 0.18), Vector3(0.68, 0.24, 0.022), desk_b)
	lit.surface(c.shade(LAMP_AMBER))
	lit.box(Vector3(cx, 1.055, org_z - 0.196), Vector3(0.54, 0.18, 0.010), desk_b)
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	u.box(Vector3(cx, 1.18, org_z - 0.21), Vector3(0.46, 0.024, 0.055))

	# 21 Gleaming Vertical Burnished-Brass Organ Pipes (classic symmetrical Victorian cathedral pipe flat: tall outer
	# bass towers rising up to y = 2.98 m, sweeping gracefully down beneath the central brass marine chronometer!).
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	var pipe_count := 21
	var pipe_span := 1.54
	for i in pipe_count:
		var u_t := float(i) / float(pipe_count - 1) # 0 .. 1
		var dx := (u_t - 0.5) * pipe_span
		var dist_c := absf(dx) / (pipe_span * 0.5) # 0 at centre, 1 at outer towers
		# Cathedral V-wing silhouette: outer towers soar to 2.94 m, dipping gently to 2.38 m under the chronometer!
		var p_top := lerpf(2.34, 2.92, pow(dist_c, 1.35))
		var p_bot := 1.24
		var p_rad := lerpf(0.020, 0.036, dist_c)
		var px := cx + dx
		var pz := org_z - 0.05 + (0.04 if i % 2 == 0 else -0.02)
		u.colour = (BRASS_BRIGHT if i % 2 == 0 else BRASS_WARM).srgb_to_linear()
		# Tapered conical brass pipe foot + cylindrical resonator + flared lip collar!
		Shapes.lathe(u, [
			Vector2(p_rad * 0.35, 0.0), Vector2(p_rad, 0.22), Vector2(p_rad * 1.12, 0.235),
			Vector2(p_rad, 0.25), Vector2(p_rad, p_top - p_bot - 0.03),
			Vector2(p_rad * 1.14, p_top - p_bot)
		], Vector3(px, p_bot, pz), 10)
		# Darkened acoustic mouth slot on the front of each brass pipe.
		u.surface(c.soft("iron", true))
		u.colour = EBONY.srgb_to_linear()
		u.box(Vector3(px, p_bot + 0.24, pz - p_rad - 0.002), Vector3(p_rad * 1.1, 0.048, 0.008))
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))

	# Organ pedalboard tucked under the keydesk + crimson-velvet mahogany organ bench (z = 2.66, well clear of seats!).
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	s.box(Vector3(cx, 0.03, org_z - 0.42), Vector3(0.96, 0.06, 0.36), Basis(), [RoomMesh.DOWN])
	u.surface(c.soft("plastic", true))
	for k in 17:
		var px := cx - 0.42 + float(k) * 0.84 / 16.0
		var sharp := k % 7 in [1, 3, 5]
		u.colour = (EBONY if sharp else WALNUT_WARM).srgb_to_linear()
		u.box(Vector3(px, 0.072 if sharp else 0.064, org_z - 0.38 if sharp else org_z - 0.44),
				Vector3(0.018, 0.024 if sharp else 0.014, 0.16 if sharp else 0.32), Basis(), [RoomMesh.DOWN])

	var bench_z := bz - 0.94 # 2.66 (rear club chair back is at 1.93 -> 0.73 m clear passage!)
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(cx + side * 0.42, 0.25, bench_z), Vector3(0.06, 0.48, 0.30), Basis(), [RoomMesh.DOWN])
	s.box(Vector3(cx, 0.14, bench_z), Vector3(0.84, 0.05, 0.06))
	s.surface(c.tinted("fabric"))
	s.colour = VELVET_CRIMSON.srgb_to_linear()
	s.box(Vector3(cx, 0.52, bench_z), Vector3(0.96, 0.08, 0.34))
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_WARM.srgb_to_linear()
	u.box(Vector3(cx, 0.48, bench_z), Vector3(0.97, 0.018, 0.35))

	c.shapes.append(PhysicsShapes.box(Vector3(cx, 1.45, org_z), Vector3(org_w, 2.90, org_d), Basis()))
	c.shapes.append(PhysicsShapes.box(Vector3(cx, 0.28, bench_z), Vector3(0.96, 0.56, 0.34), Basis()))

	# --- 2. Working Victorian Brass Marine Chronometer (PieceClock) crowning the central organ pediment! ---
	var clk_y := 2.74
	var clk_r := 0.21
	var clk_z := bz - 0.16
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY_DARK.srgb_to_linear()
	s.box(Vector3(cx, clk_y, clk_z + 0.05), Vector3(0.68, 0.56, 0.14))
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, clk_y, clk_z - 0.03), clk_r, clk_r + 0.055, 0.065, 28, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	# Twelve tiny brass bezel bolts around the marine chronometer housing.
	for k in 12:
		var ang := float(k) * TAU / 12.0
		var bx := cx + cos(ang) * (clk_r + 0.028)
		var by := clk_y + sin(ang) * (clk_r + 0.028)
		u.box(Vector3(bx, by, clk_z - 0.066), Vector3(0.018, 0.018, 0.014))
	c.clocks.append([Vector3(cx, clk_y, clk_z - 0.058), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# --- 3. Starboard Aft: Brass Navigation Binnacle Pedestal, Engine-Room Order Telegraph & Pressure Gauges ---
	var stbd_x := cx + 1.56
	var bin_z := bz - 0.52 # 3.08
	# Turned mahogany & brass pillar compass binnacle.
	s.surface(c.tinted("wood"))
	s.colour = MAHOGANY.srgb_to_linear()
	Shapes.lathe(s, [
		Vector2(0.24, 0.0), Vector2(0.24, 0.06), Vector2(0.18, 0.10), Vector2(0.13, 0.24),
		Vector2(0.11, 0.72), Vector2(0.18, 0.84), Vector2(0.19, 0.96)
	], Vector3(stbd_x, 0.0, bin_z), 16)
	# Gleaming domed brass compass hood with viewing slit & port/starboard iron quadrantal spheres!
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_BRIGHT.srgb_to_linear()
	Shapes.lathe(u, [
		Vector2(0.195, 0.94), Vector2(0.195, 1.06), Vector2(0.17, 1.15),
		Vector2(0.11, 1.22), Vector2(0.035, 1.25), Vector2(0.0, 1.27)
	], Vector3(stbd_x, 0.0, bin_z), 16)
	# Cross-arm carrying red port & green starboard quadrantal corrector spheres.
	Shapes.beam(u, Vector3(stbd_x - 0.30, 0.98, bin_z), Vector3(stbd_x + 0.30, 0.98, bin_z), Vector2(0.022, 0.022))
	u.surface(c.soft("plastic", true))
	u.colour = PORT_RED.srgb_to_linear()
	Shapes.dome(u, Vector3(stbd_x - 0.30, 0.98, bin_z), 0.068, 6, 12, false, -PI * 0.5, PI * 0.5)
	u.colour = STBD_GREEN.srgb_to_linear()
	Shapes.dome(u, Vector3(stbd_x + 0.30, 0.98, bin_z), 0.068, 6, 12, false, -PI * 0.5, PI * 0.5)
	# Glowing illuminated compass viewing window inside the brass hood (PieceLamps).
	lit.surface(c.shade(LAMP_AMBER))
	lit.box(Vector3(stbd_x, 1.04, bin_z - 0.194), Vector3(0.14, 0.09, 0.014))
	c.shapes.append(PhysicsShapes.box(Vector3(stbd_x, 0.64, bin_z), Vector3(0.62, 1.28, 0.48), Basis()))

	# Starboard aft bulkhead brass engine-room order telegraph + 3 circular pressure/depth gauges!
	_gauge_panel(c, Vector3(stbd_x, 1.92, bz - 0.04), true)

	# --- 4. Port Aft: Riveted Brass Ballast Manifold, Spoked Handwheels & Depth Manometers ---
	var port_x := cx - 1.56
	_gauge_panel(c, Vector3(port_x, 1.92, bz - 0.04), false)
	# Vertical copper/brass high-pressure ballast pipes & two spoked crimson-and-brass valve handwheels!
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	for px_off: float in [-0.26, 0.0, 0.26]:
		u.colour = (COPPER_PIPE if px_off == 0.0 else BRASS_WARM).srgb_to_linear()
		Shapes.cylinder(u, Vector3(port_x + px_off, 0.02, bz - 0.10), 0.032, 1.44, 10)
		# Bolted pipe flange collars.
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		for fy: float in [0.42, 0.98, 1.38]:
			Shapes.cylinder(u, Vector3(port_x + px_off, fy, bz - 0.10), 0.052, 0.028, 10)
	# Horizontal header manifold linking the three vertical pipes.
	Shapes.beam(u, Vector3(port_x - 0.34, 1.42, bz - 0.10), Vector3(port_x + 0.34, 1.42, bz - 0.10),
			Vector2(0.048, 0.048))
	# Two spoked crimson-painted iron & polished-brass submarine ballast valve handwheels!
	for wh_x: float in [-0.26, 0.26]:
		var wc := Vector3(port_x + wh_x, 1.06, bz - 0.20)
		u.surface(c.soft("plastic", true))
		u.colour = PORT_RED.srgb_to_linear()
		Shapes.arch(u, wc, 0.115, 0.145, 0.024, 16, basis_aft, 0.0, TAU, ["front", "back", "inner", "outer"])
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.cylinder(u, wc + Vector3(0.0, 0.0, 0.02), 0.026, 0.10, 10, Basis(Vector3.RIGHT, PI * 0.5))
		for k in 5:
			var a := float(k) * TAU / 5.0
			Shapes.beam(u, wc, wc + Vector3(cos(a) * 0.125, sin(a) * 0.125, 0.0), Vector2(0.014, 0.014))
	c.shapes.append(PhysicsShapes.box(Vector3(port_x, 0.75, bz - 0.14), Vector3(0.84, 1.50, 0.28), Basis()))


## Bolted mahogany-and-iron instrument plaque with 3 circular glowing brass depth/pressure manometers (and, on the
## starboard plaque, an illuminated engine-room brass order telegraph dial with brass lever!).
static func _gauge_panel(c: Object, at: Vector3, with_telegraph: bool) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var basis_aft := Basis(Vector3.UP, PI)
	var disc_rot := Basis(Vector3.RIGHT, PI * 0.5)

	s.surface(c.tinted("iron"))
	s.colour = IRON_HULL.srgb_to_linear()
	s.box(at, Vector3(0.88, 0.78, 0.05))
	u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
	u.colour = BRASS_WARM.srgb_to_linear()
	# Brass border mouldings around the steel instrument panel.
	for sy: float in [-0.39, 0.39]:
		u.box(at + Vector3(0.0, sy, -0.028), Vector3(0.90, 0.022, 0.020))
	for sx: float in [-0.44, 0.44]:
		u.box(at + Vector3(sx, 0.0, -0.028), Vector3(0.022, 0.80, 0.020))

	# Three large circular brass depth/pressure gauges arranged cleanly in a triangle.
	var gauges: Array = [
		[Vector3(-0.22, 0.16, -0.032), 0.115, 0.65],
		[Vector3(0.22, 0.16, -0.032), 0.115, -0.85],
		[Vector3(0.0, -0.17, -0.032), 0.145, 0.35],
	]
	lit.surface(c.shade(LAMP_AMBER))
	for g: Array in gauges:
		var gp: Vector3 = at + (g[0] as Vector3)
		var gr := float(g[1])
		var needle_ang := float(g[2])
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		Shapes.arch(u, gp, gr, gr + 0.030, 0.048, 20, basis_aft, 0.0, TAU, ["front", "inner", "outer"])
		# Perfectly circular illuminated amber dial disc inside the brass bezel + blued-iron indicator needle!
		Shapes.cylinder(lit, gp + Vector3(0.0, 0.0, -0.016), gr * 1.01, 0.008, 20, disc_rot)
		u.surface(c.soft("iron", true))
		u.colour = EBONY.srgb_to_linear()
		u.box(gp + Vector3(sin(needle_ang) * gr * 0.25, cos(needle_ang) * gr * 0.25, -0.024),
				Vector3(0.012, gr * 0.72, 0.008), Basis(Vector3.BACK, -needle_ang))
		u.surface(c.shiny("gilt", 0.90, 0.72, 0.16))
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		u.box(gp + Vector3(0.0, 0.0, -0.028), Vector3(0.024, 0.024, 0.014))

	if with_telegraph:
		# Brass engine-room order telegraph lever sweeping out from the large lower dial!
		var tp: Vector3 = at + Vector3(0.0, -0.17, -0.048)
		u.colour = BRASS_BRIGHT.srgb_to_linear()
		var tip := tp + Vector3(0.19, 0.16, -0.05)
		Shapes.beam(u, tp, tip, Vector2(0.016, 0.016))
		Shapes.cylinder(u, tip - Vector3(0.0, 0.0, 0.03), 0.022, 0.06, 10, disc_rot)


## Arched ceiling height at world x (mirrors Cabin._roof(q)).
static func _roof_y(q: Dictionary, x: float) -> float:
	var wall_h := float(q["wall_height"])
	var rise := float(q["rise"])
	if rise < 0.001:
		return wall_h
	var th := float(q["top_half"])
	var r := (th * th + rise * rise) / (2.0 * rise)
	var y0 := wall_h + rise - r
	var dx := clampf(x - float(q["cx"]), -th, th)
	return y0 + sqrt(maxf(r * r - dx * dx, 0.0))
