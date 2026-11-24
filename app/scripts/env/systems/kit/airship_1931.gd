extends RefCounted

## The Airship 1931 promenade lounge (docs/environments/rooms/airship_1931.md): a golden-age rigid airship's airy
## observation salon dressed over an outward-leaning `cabin` builder and `seats` (`lounge`) rows.
## Built by Gemini 4 Neon Extra High. Everything is ours, drawn from boxes, strips, beams and lathed shapes; no people,
## no real airship name, maker or badge.
##
##   airship_1931_promenade  the rigid airship's 1931 aeronautical Art Deco architecture:
##                           - exposed brushed-duralumin triangular lattice ring-girders with zig-zag diagonal web
##                             cross-bracing running up every leaning-out window pier and arching across the vaulted
##                             fabric deckhead, tied fore-and-aft by longitudinal purlin trusses
##                           - pale birch window-sill viewing ledges, delicate tubular aluminium safety guardrails
##                             inside the leaning-out observation windows, and brass-and-leather observation binoculars
##                             resting on the starboard window ledge beside the viewer
##                           - streamlined cream-lacquer & brushed-aluminium Art Deco screen proscenium on a low dais
##                             with subtle champagne/silver indirect cove wash (`PieceCove`), winged chevron header
##                             crest, three streamlined ceiling luminaire fins, and two slim modernist aluminium &
##                             3-tier frosted-glass torchière floor lamps (`PieceLamps`, `bake_lamps: 2`)
##                           - aft bulkhead with a crisp modernist brushed-aluminium & brass bulkhead clock
##                             (`PieceClock`), streamlined companionway door hardware, a tubular aluminium & pale-birch
##                             navigation chart table with a brass-rimmed aerial compass rose, brass dividers and a
##                             folded great-circle route chart, plus a port-side lounge credenza & framed altitude chart
##   airship_1931_piano      a sleek 1931 featherweight brushed-aluminium & cream-lacquered baby grand piano in the
##                           forward-port promenade bay:
##                           - S-curved cream & duralumin rim, propped-open lid on an aluminium prop stick revealing
##                             the pale spruce soundboard, cast champagne-bronze harp frame with lightening cutouts and
##                             gilded bass/treble strings, tubular aluminium legs with casters, brass pedal lyre,
##                             pierced aluminium music desk with score sheets, and a matching tubular piano bench
##                           - 61 animated moving ivory & ebony keys in one `MultiMeshInstance3D` (`AirshipPianoKeys`,
##                             1 draw, 0 lights) driven live via `c.halls` from `music.held_notes()` while the piano
##                             plays itself

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")

const PIECES: Array[String] = ["airship_1931_promenade", "airship_1931_piano"]

## Palette (sRGB): brushed duralumin, warm champagne cream, pale birch, champagne brass, russet upholstery.
const DURALUMIN := Color(0.84, 0.87, 0.90)
const DURALUMIN_DARK := Color(0.56, 0.60, 0.65)
const CREAM_LACQUER := Color(0.91, 0.87, 0.79)
const CREAM_WARM := Color(0.86, 0.80, 0.70)
const BIRCH_PALE := Color(0.76, 0.62, 0.44)
const BIRCH_DEEP := Color(0.54, 0.41, 0.27)
const BRASS_CHAMPAGNE := Color(0.90, 0.74, 0.40)
const RUSSET := Color(0.56, 0.24, 0.16)
const NAVY_DEEP := Color(0.10, 0.16, 0.26)
const CHARCOAL := Color(0.11, 0.12, 0.14)
const PAPER_CREAM := Color(0.92, 0.89, 0.80)
const VERMILION := Color(0.78, 0.20, 0.14)
const LAMP_CHAMPAGNE := Color(1.0, 0.87, 0.64)

## Grand piano contour in local (x, z) metres: straight bass spine on -X, S-curved treble bentside on +X,
## semicircular tail at -Z, front cheek face at z = +0.36 (behind the projecting keybed at z = +0.36..+0.62).
const GRAND_CONTOUR: Array[Vector2] = [
	Vector2(-0.62, 0.36),
	Vector2(-0.62, -0.44),
	Vector2(-0.58, -0.58),
	Vector2(-0.48, -0.69),
	Vector2(-0.34, -0.75),
	Vector2(-0.18, -0.75),
	Vector2(-0.02, -0.69),
	Vector2(0.11, -0.58),
	Vector2(0.20, -0.42),
	Vector2(0.28, -0.22),
	Vector2(0.41, -0.04),
	Vector2(0.54, 0.10),
	Vector2(0.61, 0.24),
	Vector2(0.62, 0.36),
]

## 61 keys (5 octaves, C2 = MIDI 36 to C7 = MIDI 96): covers every note music.gd plays without wrapping.
const PIANO_KEYS := 61
const PIANO_LOW_NOTE := 36
const KEY_SPAN := 1.04
const KEYBED_TOP_Y := 0.712


## Animated moving keys helper registered on `c.halls`: builds one MultiMeshInstance3D in finish(kit) and depresses
## held keys smoothly in tick(delta) by querying the room's piano music system.
class PianoKeysHall:
	var xf: Transform3D
	var kit: Node
	var keys_mm: MultiMesh
	var keys_node: MultiMeshInstance3D
	var key_rest: Array[Transform3D] = []
	var key_pivot: Array[Vector3] = []
	var key_depth: Array[float] = []
	var key_press: Array[float] = []
	var key_active: Array[bool] = []
	var _music: Node

	func _init(p_xf: Transform3D) -> void:
		xf = p_xf

	func finish(k: Node) -> void:
		kit = k
		var whites := 0
		for i in PIANO_KEYS:
			if not _is_black(PIANO_LOW_NOTE + i):
				whites += 1
		var ww := KEY_SPAN / float(whites)
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		box.material = k._ctx.soft("plastic", true)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = box
		mm.instance_count = PIANO_KEYS
		var wi := 0
		var b_rot := xf.basis.orthonormalized()
		for i in PIANO_KEYS:
			var black := _is_black(PIANO_LOW_NOTE + i)
			var lx: float
			var local_xf: Transform3D
			var piv_local: Vector3
			if black:
				lx = -KEY_SPAN * 0.5 + float(wi) * ww
				local_xf = Transform3D(Basis().scaled(Vector3(ww * 0.56, 0.018, 0.095)),
						Vector3(lx, KEYBED_TOP_Y + 0.024, 0.435))
				piv_local = Vector3(lx, KEYBED_TOP_Y + 0.024, 0.388)
				mm.set_instance_color(i, Color(0.06, 0.06, 0.07))
			else:
				lx = -KEY_SPAN * 0.5 + (float(wi) + 0.5) * ww
				local_xf = Transform3D(Basis().scaled(Vector3(ww - 0.0018, 0.018, 0.148)),
						Vector3(lx, KEYBED_TOP_Y + 0.012, 0.465))
				piv_local = Vector3(lx, KEYBED_TOP_Y + 0.012, 0.391)
				mm.set_instance_color(i, Color(0.96, 0.94, 0.88))
				wi += 1
			var world_xf := Transform3D(b_rot, xf.origin) * local_xf
			mm.set_instance_transform(i, world_xf)
			key_rest.append(world_xf)
			key_pivot.append(xf.origin + b_rot * piv_local)
			key_depth.append(0.0 if black else 0.0)
			key_press.append(0.0)
			key_active.append(false)
		var mi := MultiMeshInstance3D.new()
		mi.name = "AirshipPianoKeys"
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.set_meta("env_placed", key_rest.duplicate())
		mi.set_meta("instances", PIANO_KEYS)
		mi.set_meta("keys_down", 0)
		k.own(mi)
		keys_mm = mm
		keys_node = mi

	func tick(delta: float) -> void:
		if keys_mm == null or kit == null or kit.host == null:
			return
		if _music == null or not is_instance_valid(_music):
			for s: Node in kit.host.systems_of_kind("music"):
				if str(s.params.get("instrument", "")) == "piano":
					_music = s
					break
		var want: Array[bool] = []
		want.resize(PIANO_KEYS)
		want.fill(false)
		if _music != null and is_instance_valid(_music):
			var held: Array = _music.call("held_notes")
			for m: int in held:
				var idx := m - PIANO_LOW_NOTE
				while idx < 0:
					idx += 12
				while idx >= PIANO_KEYS:
					idx -= 12
				want[idx] = true
		var b_rot := xf.basis.orthonormalized()
		var hinge_axis := b_rot.x.normalized()
		var down_count := 0
		var rate := maxf(delta * 20.0, 0.0)
		for i in PIANO_KEYS:
			var target := 1.0 if want[i] else 0.0
			var cur := key_press[i]
			var next := target if rate <= 0.0 else move_toward(cur, target, rate)
			if not is_equal_approx(next, cur) or want[i] != key_active[i]:
				key_press[i] = next
				key_active[i] = want[i]
				var t := key_rest[i]
				if next > 0.001:
					var piv := key_pivot[i]
					# Positive rotation around piano's +X axis dips the +Z front tip of the key cleanly downward.
					var rot := Basis(hinge_axis, deg_to_rad(4.2) * next)
					t = Transform3D(Basis(), piv) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis(), -piv) * t
				keys_mm.set_instance_transform(i, t)
			if key_press[i] > 0.2:
				down_count += 1
		if keys_node != null and is_instance_valid(keys_node):
			keys_node.set_meta("keys_down", down_count)

	static func _is_black(midi: int) -> bool:
		return (midi % 12) in [1, 3, 6, 8, 10]


static func build(piece: String, c: Object, xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"airship_1931_promenade":
			_promenade(c)
		"airship_1931_piano":
			_piano(c, xf)


# --- The 1931 rigid airship promenade lounge --------------------------------------------------------------------------

static func _promenade(c: Object) -> void:
	if (c.builder_params as Dictionary).is_empty():
		return
	var q: Dictionary = Cabin.resolved(c.builder_params)
	_lattice_girders(c, q)
	_window_guardrails_and_binoculars(c, q)
	_proscenium_and_luminaires(c, q)
	_aft_bulkhead(c, q)


## Exposed brushed-duralumin triangular lattice ring-girders between every leaning-out observation window and across
## the arched deckhead, tied together fore-and-aft by longitudinal purlin ribs and a central ridge spine.
static func _lattice_girders(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var wall_len := float(q["wall_len"])
	var marks: Array[float] = Cabin._bay_marks(q)
	var roof: Array = Cabin._roof(q)
	var rpts: PackedVector2Array = roof[0]
	var rns: PackedVector2Array = roof[1]

	var u: RoomMesh = c.u
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()

	var chord_sz := Vector2(0.022, 0.022)
	var apex_sz := Vector2(0.024, 0.024)
	var strut_sz := Vector2(0.013, 0.013)
	var half_z := 0.082
	var proj_wall := 0.145
	var proj_roof := 0.135

	for z: float in marks:
		# Leaning-out side wall triangular lattice columns on both port and starboard walls.
		for s: float in [-1.0, 1.0]:
			var n := Cabin._n(q, s)
			var wall_off := n * 0.014
			var apex_off := n * proj_wall
			var v0 := 0.02
			var v1 := wall_len
			# Two outer chords hugging the wall + one prominent inner apex chord projecting into the lounge.
			for dz: float in [-half_z, half_z]:
				var a := Cabin._pt(q, s, z + dz, v0) + wall_off
				var b := Cabin._pt(q, s, z + dz, v1) + wall_off
				Shapes.beam(u, a, b, chord_sz)
			var apex_a := Cabin._pt(q, s, z, v0) + apex_off
			var apex_b := Cabin._pt(q, s, z, v1 - 0.06) + apex_off
			Shapes.beam(u, apex_a, apex_b, apex_sz)
			# Seamless mitered knee-joint linking wall lattice apex directly into arched roof truss apex!
			var roof_end := 0 if s < 0.0 else rpts.size() - 1
			var roof_p := Vector3(rpts[roof_end].x, rpts[roof_end].y, z)
			var roof_n := Vector3(rns[roof_end].x, rns[roof_end].y, 0.0)
			var roof_apex := roof_p + roof_n * proj_roof
			Shapes.beam(u, apex_b, roof_apex, apex_sz)
			for dz: float in [-half_z, half_z]:
				var wall_top := Cabin._pt(q, s, z + dz, v1) + wall_off
				var roof_o := roof_p + roof_n * 0.014 + Vector3(0.0, 0.0, dz)
				Shapes.beam(u, wall_top, roof_o, chord_sz)
				Shapes.beam(u, wall_top, roof_apex, strut_sz)
			# Zig-zag diagonal cross-bracing web struts along both triangular faces of the girder.
			var bays := 8
			for k in bays:
				var va := lerpf(v0, v1 - 0.06, float(k) / bays)
				var vb := lerpf(v0, v1 - 0.06, float(k + 1) / bays)
				var vm := (va + vb) * 0.5
				var p_apex := Cabin._pt(q, s, z, vm) + apex_off
				for dz: float in [-half_z, half_z]:
					var p0 := Cabin._pt(q, s, z + dz, va) + wall_off
					var p1 := Cabin._pt(q, s, z + dz, vb) + wall_off
					Shapes.beam(u, p0, p_apex, strut_sz)
					Shapes.beam(u, p_apex, p1, strut_sz)
			# Crisp horizontal tie-gusset bars at the floor foot, sill line, and upper knee.
			for vt: float in [v0 + 0.04, float(q["window_sill"]) / cos(float(q["L"])), v1 - 0.08]:
				var pl := Cabin._pt(q, s, z - half_z, vt) + wall_off
				var pr := Cabin._pt(q, s, z + half_z, vt) + wall_off
				var pa := Cabin._pt(q, s, z, vt) + apex_off
				Shapes.beam(u, pl, pr, strut_sz)
				Shapes.beam(u, pl, pa, strut_sz)
				Shapes.beam(u, pr, pa, strut_sz)

		# Arched deckhead triangular lattice truss spanning from port wall top to starboard wall top.
		for i in rpts.size() - 1:
			var p0 := Vector3(rpts[i].x, rpts[i].y, z)
			var p1 := Vector3(rpts[i + 1].x, rpts[i + 1].y, z)
			var n0 := Vector3(rns[i].x, rns[i].y, 0.0)
			var n1 := Vector3(rns[i + 1].x, rns[i + 1].y, 0.0)
			var pm := (p0 + p1) * 0.5
			var nm := (n0 + n1).normalized()
			var a0 := p0 + n0 * proj_roof
			var a1 := p1 + n1 * proj_roof
			var am := pm + nm * proj_roof
			Shapes.beam(u, a0, a1, apex_sz)
			for dz: float in [-half_z, half_z]:
				var o0 := p0 + n0 * 0.014 + Vector3(0.0, 0.0, dz)
				var o1 := p1 + n1 * 0.014 + Vector3(0.0, 0.0, dz)
				Shapes.beam(u, o0, o1, chord_sz)
				Shapes.beam(u, o0, am, strut_sz)
				Shapes.beam(u, am, o1, strut_sz)

	# Longitudinal brushed-duralumin purlin girders tying all six ring frames fore-and-aft.
	var span := bz - fz - 0.1
	var mid_z := (fz + bz) * 0.5
	for s: float in [-1.0, 1.0]:
		var basis_w := Cabin._wall_basis(q, s)
		var n := Cabin._n(q, s)
		# Upper window-header twin longitudinal chord rails (above the panoramic glazing).
		for dv: float in [wall_len - 0.28, wall_len - 0.12]:
			var pt := Cabin._pt(q, s, mid_z, dv) + n * 0.036
			u.box(pt, Vector3(span, 0.028, 0.032), basis_w)
	# Two arched-ceiling longitudinal purlin beams + a sleek central ridge spine at the roof crown.
	for idx: int in [2, rpts.size() - 3]:
		var p := rpts[idx] + rns[idx] * 0.045
		var ang := atan2(-rns[idx].x, -rns[idx].y)
		u.box(Vector3(p.x, p.y, mid_z), Vector3(0.042, 0.048, span), Basis(Vector3.BACK, ang))
	var crown_y := float(q["headroom"]) - 0.028
	u.box(Vector3(cx, crown_y, mid_z), Vector3(0.11, 0.032, span))
	u.colour = Color.WHITE


## Pale warm birch window-sill ledges, delicate tubular brushed-aluminium safety guardrails inside the leaning-out
## windows, and a pair of 1931 brass-and-leather observation binoculars resting on the starboard middle sill.
static func _window_guardrails_and_binoculars(c: Object, q: Dictionary) -> void:
	var wzs: Array = q["window_zs"]
	if wzs.is_empty():
		return
	var lean := float(q["L"])
	var sill := float(q["window_sill"])
	var ww := float(q["window_width"])
	var z0 := float(wzs[0]) - ww * 0.55
	var z1 := float(wzs[-1]) + ww * 0.55
	var rail_len := z1 - z0
	var rail_mid := (z0 + z1) * 0.5
	var marks: Array[float] = Cabin._bay_marks(q)

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis_z := Basis(Vector3.RIGHT, PI * 0.5)

	for side: float in [-1.0, 1.0]:
		var n := Cabin._n(q, side)
		# Horizontal pale-birch viewing ledge running cleanly along the top of the dado beneath the slanted windows.
		var sill_pt := Cabin._pt(q, side, rail_mid, sill / cos(lean))
		var ledge_x := sill_pt.x - side * 0.075
		s.surface(c.tinted("wood"))
		s.colour = BIRCH_PALE.srgb_to_linear()
		s.box(Vector3(ledge_x, sill - 0.015, rail_mid), Vector3(0.16, 0.032, rail_len + 0.16))
		s.colour = BIRCH_DEEP.srgb_to_linear()
		s.box(Vector3(ledge_x - side * 0.068, sill - 0.038, rail_mid), Vector3(0.024, 0.024, rail_len + 0.12))

		# Twin delicate tubular brushed-aluminium safety guardrails inside the leaning-out observation windows.
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = DURALUMIN.srgb_to_linear()
		var y_top := sill + 0.27
		var y_mid := sill + 0.135
		var top_wall := Cabin._pt(q, side, z0, y_top / cos(lean))
		var mid_wall := Cabin._pt(q, side, z0, y_mid / cos(lean))
		var rx_top := top_wall.x - side * 0.115
		var rx_mid := mid_wall.x - side * 0.115
		Shapes.cylinder(u, Vector3(rx_top, y_top, z0), 0.015, rail_len, 10, basis_z)
		Shapes.cylinder(u, Vector3(rx_mid, y_mid, z0), 0.009, rail_len, 8, basis_z)
		# Slim vertical tubular stanchions rising from the birch sill ledge at every window bay mark.
		for mz: float in marks:
			if mz < z0 - 0.2 or mz > z1 + 0.2:
				continue
			var cz := clampf(mz, z0 + 0.02, z1 - 0.02)
			var base_p := Vector3(rx_top, sill, cz)
			Shapes.cylinder(u, base_p, 0.011, y_top - sill, 8)
			Shapes.cylinder(u, base_p, 0.022, 0.014, 10)
			# Small horizontal tie strut back to the leaning window pier frame.
			var pier_p := Cabin._pt(q, side, cz, y_top / cos(lean)) + n * 0.02
			Shapes.beam(u, Vector3(rx_top, y_top, cz), pier_p, Vector2(0.014, 0.014))

	# Pair of slim brass-and-leather 1931 observation binoculars resting on the starboard middle window-sill ledge.
	var bz := float(wzs[wzs.size() / 2]) - 0.16
	var bsill := Cabin._pt(q, 1.0, bz, sill / cos(lean))
	var bin_at := Vector3(bsill.x - 0.075, sill + 0.002, bz)
	var bin_basis := Basis(Vector3.UP, deg_to_rad(58.0))
	var cyl_rot := bin_basis * Basis(Vector3.RIGHT, PI * 0.5)
	u.surface(c.soft("plastic", true))
	u.colour = CHARCOAL.srgb_to_linear()
	for side_b: float in [-1.0, 1.0]:
		var off := bin_basis * Vector3(side_b * 0.036, 0.028, -0.07)
		Shapes.cylinder(u, bin_at + off, 0.024, 0.115, 10, cyl_rot)
		var eye_off := bin_basis * Vector3(side_b * 0.032, 0.028, 0.045)
		Shapes.cylinder(u, bin_at + eye_off, 0.015, 0.034, 10, cyl_rot)
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	for side_b: float in [-1.0, 1.0]:
		var obj_off := bin_basis * Vector3(side_b * 0.036, 0.028, -0.082)
		Shapes.cylinder(u, bin_at + obj_off, 0.0265, 0.018, 10, cyl_rot)
		var ring_off := bin_basis * Vector3(side_b * 0.032, 0.028, 0.036)
		Shapes.cylinder(u, bin_at + ring_off, 0.017, 0.012, 10, cyl_rot)
	# Central bridge hinge and brass focusing wheel.
	Shapes.cylinder(u, bin_at + bin_basis * Vector3(0.0, 0.034, -0.015), 0.009, 0.068, 8, cyl_rot)
	u.box(bin_at + bin_basis * Vector3(0.0, 0.034, -0.03), Vector3(0.072, 0.012, 0.018), bin_basis)
	u.box(bin_at + bin_basis * Vector3(0.0, 0.034, 0.032), Vector3(0.064, 0.012, 0.014), bin_basis)

	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Streamlined Art Deco cream-and-aluminium screen proscenium, subtle indirect champagne/silver cove wash (PieceCove),
## two slim modernist aluminium & frosted-glass torchière floor lamps (PieceLamps), and three streamlined Art Deco
## ceiling luminaire fins nestled between the arched deckhead lattice frames.
static func _proscenium_and_luminaires(c: Object, q: Dictionary) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D())
	var sc_sz: Vector2 = scr.get("size", Vector2(3.6, 2.025))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var hw := sc_sz.x * 0.5
	var hh := sc_sz.y * 0.5
	var fz := float(q["front_z"])
	var bz := float(q["back_z"])
	var wall_h := float(q["wall_height"])
	var headroom := float(q["headroom"])
	var sc_bot := cy - hh
	var sc_top := cy + hh

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var lit: RoomMesh = c.lit

	# Low streamlined cream-lacquer & pale-birch dais beneath the screen.
	var dais_w := 5.36
	var dais_h := 0.20
	var dais_d := 0.56
	s.surface(c.tinted("wood"))
	s.colour = BIRCH_DEEP.srgb_to_linear()
	s.box(Vector3(cx, 0.04, fz + dais_d * 0.45), Vector3(dais_w - 0.16, 0.08, dais_d * 0.9), Basis(), [RoomMesh.DOWN])
	s.surface(c.tinted("plastic"))
	s.colour = CREAM_WARM.srgb_to_linear()
	s.box(Vector3(cx, 0.14, fz + dais_d * 0.5), Vector3(dais_w, 0.12, dais_d), Basis(), [RoomMesh.DOWN])
	c.shapes.append(PhysicsShapes.box(Vector3(cx, dais_h * 0.5, fz + dais_d * 0.5), Vector3(dais_w, dais_h, dais_d),
			Basis()))

	# Three-tier stepped streamlined cream-lacquer proscenium flanks framing the screen cleanly without obstructing it.
	s.colour = CREAM_LACQUER.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var tiers := [
			[hw + 0.14, 0.24, 0.12],
			[hw + 0.40, 0.28, 0.20],
			[hw + 0.68, 0.28, 0.28],
		]
		for tr: Array in tiers:
			var tx := cx + side * float(tr[0])
			var tw := float(tr[1])
			var td := float(tr[2])
			var top_y := minf(_roof_y(q, tx + side * tw * 0.5) - 0.04, sc_top + 0.22)
			var h := top_y - dais_h
			s.box(Vector3(tx, dais_h + h * 0.5, fz + td * 0.5), Vector3(tw, h, td), Basis(), [RoomMesh.DOWN])
		var flank_h := minf(_roof_y(q, cx + side * (hw + 0.82)) - 0.04, sc_top + 0.22) - dais_h
		c.shapes.append(PhysicsShapes.box(Vector3(cx + side * (hw + 0.42), dais_h + flank_h * 0.5, fz + 0.14),
				Vector3(0.84, flank_h, 0.28), Basis()))
	# Streamlined header fascia spanning above the screen + shallow under-screen dado plinth.
	var hdr_h := minf(headroom - sc_top - 0.06, 0.19)
	s.box(Vector3(cx, sc_top + hdr_h * 0.5 + 0.02, fz + 0.12), Vector3(sc_sz.x + 0.64, hdr_h, 0.24))
	s.colour = CREAM_WARM.srgb_to_linear()
	s.box(Vector3(cx, (dais_h + sc_bot - 0.03) * 0.5, fz + 0.06), Vector3(sc_sz.x + 0.08, sc_bot - dais_h - 0.03, 0.12))

	# Gleaming brushed-duralumin speed-lines on dais, stepped proscenium piers, and header fascia.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	u.box(Vector3(cx, 0.185, fz + dais_d + 0.008), Vector3(dais_w + 0.02, 0.022, 0.018))
	u.box(Vector3(cx, 0.125, fz + dais_d + 0.008), Vector3(dais_w + 0.02, 0.014, 0.014))
	u.box(Vector3(cx, sc_bot - 0.018, fz + 0.125), Vector3(sc_sz.x + 0.12, 0.024, 0.02))
	u.box(Vector3(cx, sc_top + 0.022, fz + 0.245), Vector3(sc_sz.x + 0.66, 0.022, 0.02))
	for side: float in [-1.0, 1.0]:
		var x_in := cx + side * (hw + 0.02)
		var x_out := cx + side * (hw + 0.82)
		var h_in := sc_top + 0.02 - dais_h
		var h_out := minf(_roof_y(q, x_out) - 0.04, sc_top + 0.20) - dais_h
		u.box(Vector3(x_in, dais_h + h_in * 0.5, fz + 0.125), Vector3(0.026, h_in, 0.022))
		u.box(Vector3(x_out, dais_h + h_out * 0.5, fz + 0.285), Vector3(0.028, h_out, 0.024))
		# Horizontal Art Deco speed-bars across the stepped cream piers.
		for k in 3:
			var by := sc_bot + 0.25 + 0.72 * k
			u.box(Vector3(cx + side * (hw + 0.54), by, fz + 0.285), Vector3(0.56, 0.018, 0.018))

	# Champagne-brass winged Art Deco chevron crest centered on the proscenium header.
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	var crest_y := sc_top + hdr_h * 0.55 + 0.02
	u.box(Vector3(cx, crest_y, fz + 0.255), Vector3(0.22, 0.055, 0.022))
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var w_wing := 0.56 - 0.14 * k
			var wy := crest_y + 0.032 - 0.028 * k
			u.box(Vector3(cx + side * (0.12 + w_wing * 0.5), wy, fz + 0.252), Vector3(w_wing, 0.015, 0.016))

	# Pale birch dado panelling & brushed-aluminium rail continuing across the outer forward bulkhead wings.
	var floor_hw := float(q["hw"])
	var wing_in := hw + 0.82
	var wing_w := floor_hw - wing_in
	if wing_w > 0.15:
		var dado_h := float(q["dado"])
		s.surface(c.tinted("wood"))
		s.colour = BIRCH_PALE.srgb_to_linear()
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = DURALUMIN.srgb_to_linear()
		for side: float in [-1.0, 1.0]:
			var wx := cx + side * (wing_in + wing_w * 0.5)
			s.box(Vector3(wx, dado_h * 0.5, fz + 0.015), Vector3(wing_w, dado_h, 0.03), Basis(), [RoomMesh.DOWN])
			u.box(Vector3(wx, dado_h, fz + 0.032), Vector3(wing_w, 0.028, 0.024))
			# Subtle Art Deco vertical aluminium accent rib on each forward wing.
			var rib_x := cx + side * (wing_in + wing_w * 0.48)
			var rib_top := _roof_y(q, rib_x) - 0.1
			u.box(Vector3(rib_x, (dado_h + rib_top) * 0.5, fz + 0.022), Vector3(0.024, rib_top - dado_h, 0.02))

	# Subtle champagne / moonlight-silver cove wash (PieceCove): proscenium vertical setbacks, header soffit, and
	# tucked upper-wall indirect uplight coves hidden neatly behind a slim cream-and-aluminium cornice trough!
	cove.surface(c.kit.cove_material())
	var cove_lin := CREAM_LACQUER.srgb_to_linear()
	cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.94)
	for side: float in [-1.0, 1.0]:
		for cx_d: Array in [[hw + 0.26, 0.21, sc_top + 0.14], [hw + 0.54, 0.29, sc_top + 0.08]]:
			var vx := cx + side * float(cx_d[0])
			var vz := fz + float(cx_d[1])
			var vtop := minf(_roof_y(q, vx) - 0.06, float(cx_d[2]))
			cove.face([Vector3(vx - 0.045, dais_h + 0.08, vz), Vector3(vx + 0.045, dais_h + 0.08, vz),
					Vector3(vx + 0.045, vtop, vz), Vector3(vx - 0.045, vtop, vz)], Vector3.BACK)
	# Header cove wash band above the picture.
	cove.face([Vector3(cx - hw - 0.18, sc_top + 0.04, fz + 0.244), Vector3(cx + hw + 0.18, sc_top + 0.04, fz + 0.244),
			Vector3(cx + hw + 0.18, sc_top + 0.14, fz + 0.244), Vector3(cx - hw - 0.18, sc_top + 0.14, fz + 0.244)],
			Vector3.BACK)
	# Tucked indirect uplight cove cornice along both eaves: slim cream valance hides the lamp edge from below while
	# washing champagne/silver light smoothly upward onto the arched taut-fabric ceiling between the ring-girders!
	var top_half := float(q["top_half"])
	var cove_span := bz - fz - 0.2
	var cove_mid := (fz + bz) * 0.5
	s.surface(c.tinted("plastic"))
	s.colour = CREAM_LACQUER.srgb_to_linear()
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var x_wall := cx + side * (top_half - 0.02)
		var x_lip := cx + side * (top_half - 0.13)
		var y_val := wall_h - 0.055
		# Slim sculpted valance lip tucked neatly behind the lattice girder apex so girders stand proud.
		s.box(Vector3(x_lip, y_val, cove_mid), Vector3(0.024, 0.052, cove_span))
		s.box(Vector3((x_wall + x_lip) * 0.5, y_val - 0.02, cove_mid), Vector3(absf(x_wall - x_lip), 0.018, cove_span))
		u.box(Vector3(x_lip - side * 0.014, y_val - 0.014, cove_mid), Vector3(0.012, 0.014, cove_span))
		# Soft architectural cove wash strip glowing smoothly along the curved deckhead springline!
		cove.colour = Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.62)
		var x_c0 := cx + side * (top_half - 0.04)
		var x_c1 := cx + side * (top_half - 0.22)
		var y_c0 := wall_h + 0.008
		var y_c1 := _roof_y(q, x_c1) - 0.008
		var n_cove := Vector3(-side * 0.25, -0.968, 0.0).normalized()
		var p0 := Vector3(x_c0, y_c0, fz + 0.18)
		var p1 := Vector3(x_c1, y_c1, fz + 0.18)
		var p2 := Vector3(x_c1, y_c1, bz - 0.18)
		var p3 := Vector3(x_c0, y_c0, bz - 0.18)
		if side < 0.0:
			cove.face([p0, p1, p2, p3], n_cove)
		else:
			cove.face([p1, p0, p3, p2], n_cove)
	cove.colour = Color.WHITE

	# Two slim modernist 1931 brushed-aluminium & 3-tier frosted-glass torchière floor lamps flanking the screen.
	lit.surface(c.shade(LAMP_CHAMPAGNE))
	for side: float in [-1.0, 1.0]:
		var tx := cx + side * (hw + 0.48)
		var tz := fz + 0.38
		var base := Vector3(tx, dais_h, tz)
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = DURALUMIN.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.16, 0.0), Vector2(0.16, 0.028), Vector2(0.125, 0.032), Vector2(0.125, 0.056),
			Vector2(0.065, 0.068), Vector2(0.032, 0.12), Vector2(0.024, 1.24),
			Vector2(0.115, 1.30), Vector2(0.135, 1.325), Vector2(0.11, 1.335)
		], base, 14)
		# Crisp aluminium fin collars separating the three frosted-glass tiers.
		Shapes.lathe(u, [Vector2(0.105, 1.47), Vector2(0.122, 1.482), Vector2(0.095, 1.495)], base, 14)
		Shapes.lathe(u, [Vector2(0.078, 1.60), Vector2(0.092, 1.612), Vector2(0.064, 1.625)], base, 14)
		# Glowing 3-tier modernist frosted-glass lantern spire.
		Shapes.lathe(lit, [
			Vector2(0.098, 1.33), Vector2(0.114, 1.355), Vector2(0.108, 1.475),
			Vector2(0.090, 1.49), Vector2(0.082, 1.605),
			Vector2(0.060, 1.62), Vector2(0.048, 1.72), Vector2(0.0, 1.76)
		], base, 14)
		c.lamps.append([Vector3(tx, dais_h + 1.56, tz), LAMP_CHAMPAGNE, 0.72])
		c.shapes.append(PhysicsShapes.box(Vector3(tx, dais_h + 0.88, tz), Vector3(0.28, 1.76, 0.28), Basis()))

	# Three sleek streamlined frosted-glass & aluminium Art Deco ceiling luminaire fins along the deckhead spine.
	var wzs: Array = q["window_zs"]
	var lum_zs: Array[float] = []
	if wzs.size() >= 4:
		lum_zs = [float(wzs[1]), float(wzs[2]), float(wzs[3])]
	else:
		lum_zs = [-1.6, 0.0, 1.6]
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	for lz: float in lum_zs:
		var ly := headroom - 0.055
		# Tapered aluminium end-caps and slim underside speed-rib.
		for ez: float in [-0.46, 0.46]:
			u.box(Vector3(cx, ly + 0.01, lz + ez), Vector3(0.24, 0.055, 0.04))
		u.box(Vector3(cx, ly - 0.032, lz), Vector3(0.022, 0.014, 0.94))
		# Glowing frosted-glass stepped diffuser trough.
		lit.box(Vector3(cx, ly, lz), Vector3(0.20, 0.048, 0.88), Basis(), [RoomMesh.UP])

	s.colour = Color.WHITE
	u.colour = Color.WHITE


## Aft bulkhead: crisp modernist brushed-aluminium bulkhead clock (PieceClock), companionway door trim, starboard
## navigation chart table with a brass-rimmed aerial compass rose, dividers and folded great-circle route chart, and
## a port-side tubular lounge credenza with a framed geometric altitude-profile plaque.
static func _aft_bulkhead(c: Object, q: Dictionary) -> void:
	var cx := float(q["cx"])
	var hw := float(q["hw"])
	var bz := float(q["back_z"])
	var dado_h := float(q["dado"])
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var basis_aft := Basis(Vector3.UP, PI)

	# Continuing pale birch dado panelling & brushed-aluminium dado rail across the aft bulkhead (flanking the door),
	# plus twin vertical Art Deco brushed-aluminium pilasters framing the companionway portal up to the clock.
	var door_half := 0.34
	var side_w := hw - door_half
	s.surface(c.tinted("wood"))
	s.colour = BIRCH_PALE.srgb_to_linear()
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	for side: float in [-1.0, 1.0]:
		var dx := cx + side * (door_half + side_w * 0.5)
		s.box(Vector3(dx, dado_h * 0.5, bz - 0.015), Vector3(side_w, dado_h, 0.03), Basis(), [RoomMesh.DOWN])
		u.box(Vector3(dx, dado_h, bz - 0.032), Vector3(side_w, 0.028, 0.024))
		# Vertical brushed-duralumin structural pilasters framing the companionway door & rising to the ceiling arch.
		var pil_x := cx + side * 0.52
		var pil_top := _roof_y(q, pil_x) - 0.05
		u.box(Vector3(pil_x, pil_top * 0.5, bz - 0.028), Vector3(0.042, pil_top, 0.036))
		# Outer structural bulkhead ribs aligning with the navigation table and credenza bays.
		var out_x := cx + side * (hw - 0.45)
		var out_top := _roof_y(q, out_x) - 0.06
		u.box(Vector3(out_x, (dado_h + out_top) * 0.5, bz - 0.022), Vector3(0.026, out_top - dado_h, 0.022))
	# Horizontal brushed-duralumin transom frieze bar tying the door pilasters together above the companionway door.
	u.box(Vector3(cx, 1.94, bz - 0.03), Vector3(1.12, 0.032, 0.03))

	# Streamlined brushed-aluminium door kick-plate, glazed-port bezel & modernist lever handle on the aft door.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	u.box(Vector3(cx, 0.15, bz - 0.025), Vector3(0.58, 0.28, 0.01))
	# Clean frame around the door's glowing pane (door window is x: cx +- 0.15, y: 1.3..1.7).
	for sx: float in [-1.0, 1.0]:
		u.box(Vector3(cx + sx * 0.165, 1.5, bz - 0.028), Vector3(0.024, 0.44, 0.016))
	for sy: float in [1.288, 1.712]:
		u.box(Vector3(cx, sy, bz - 0.028), Vector3(0.354, 0.024, 0.016))
	u.box(Vector3(cx - 0.21, 0.98, bz - 0.048), Vector3(0.11, 0.022, 0.018))

	# Crisp modernist 1931 brushed-aluminium & brass bulkhead clock centered above the companionway door (PieceClock).
	var clk_y := 2.48
	var clk_r := 0.23
	s.surface(c.tinted("plastic"))
	s.colour = CREAM_WARM.srgb_to_linear()
	s.box(Vector3(cx, clk_y, bz - 0.022), Vector3(1.56, 0.34, 0.042))
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	Shapes.arch(u, Vector3(cx, clk_y, bz - 0.056), clk_r, clk_r + 0.042, 0.052, 28, basis_aft, 0.0, TAU,
			["front", "inner", "outer"])
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var ww := 0.46 - 0.11 * k
			var wy := clk_y + (1 - k) * 0.068
			u.box(Vector3(cx + side * (clk_r + 0.07 + ww * 0.5), wy, bz - 0.048), Vector3(ww, 0.018, 0.018))
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	for k in 4:
		var ang := k * PI * 0.5
		var mx := cx + sin(ang) * (clk_r + 0.022)
		var my := clk_y + cos(ang) * (clk_r + 0.022)
		u.box(Vector3(mx, my, bz - 0.084), Vector3(0.018, 0.042, 0.012), Basis(Vector3.BACK, -ang))
	c.clocks.append([Vector3(cx, clk_y, bz - 0.078), Vector3(-clk_r, 0.0, 0.0), Vector3(0.0, clk_r, 0.0),
			Vector3.FORWARD])

	# Starboard aft navigation chart table (tubular brushed aluminium legs, pale birch top, brass fiddle lip,
	# folded transoceanic route chart, brass-rimmed aerial compass rose binnacle, dividers & rolled chart tube).
	var tx := cx + hw * 0.54
	var tz := bz - 0.34
	var tw := 1.24
	var th := 0.80
	var td := 0.56
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var foot := Vector3(tx + sx * (tw * 0.5 - 0.05), 0.0, tz + sz * (td * 0.5 - 0.05))
			var top_p := Vector3(tx + sx * (tw * 0.5 - 0.08), th - 0.03, tz + sz * (td * 0.5 - 0.07))
			Shapes.beam(u, foot, top_p, Vector2(0.024, 0.024))
		# Side cross-stretcher bars.
		Shapes.beam(u, Vector3(tx + sx * (tw * 0.5 - 0.06), 0.24, tz - td * 0.5 + 0.06),
				Vector3(tx + sx * (tw * 0.5 - 0.06), 0.24, tz + td * 0.5 - 0.06), Vector2(0.018, 0.018))
	Shapes.beam(u, Vector3(tx - tw * 0.5 + 0.06, 0.24, tz), Vector3(tx + tw * 0.5 - 0.06, 0.24, tz),
			Vector2(0.018, 0.018))
	# Pale birch chart desk top + lower map shelf.
	s.surface(c.tinted("wood"))
	s.colour = BIRCH_PALE.srgb_to_linear()
	s.box(Vector3(tx, th - 0.018, tz), Vector3(tw, 0.036, td))
	s.colour = BIRCH_DEEP.srgb_to_linear()
	s.box(Vector3(tx, 0.24, tz), Vector3(tw - 0.16, 0.022, td - 0.12))
	# Slim brass anti-slip fiddle gallery around the back and sides of the chart table.
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	u.box(Vector3(tx, th + 0.012, tz + td * 0.5 - 0.01), Vector3(tw, 0.024, 0.014))
	for sx: float in [-1.0, 1.0]:
		u.box(Vector3(tx + sx * (tw * 0.5 - 0.01), th + 0.012, tz), Vector3(0.014, 0.024, td))

	# Folded cream-and-navy transoceanic route chart on the left side of the chart table.
	var map_at := Vector3(tx - 0.16, th + 0.004, tz - 0.02)
	var map_b := Basis(Vector3.UP, deg_to_rad(-6.0))
	u.surface(c.soft("plastic", true))
	u.colour = PAPER_CREAM.srgb_to_linear()
	u.box(map_at, Vector3(0.58, 0.006, 0.38), map_b)
	# Slightly lifted folded corner flap on the chart's outer edge for organic craft.
	u.box(map_at + map_b * Vector3(-0.27, 0.008, 0.0), Vector3(0.06, 0.004, 0.37),
			map_b * Basis(Vector3.BACK, deg_to_rad(-11.0)))
	# Soft ocean-slate bathymetry wash panel & delicate great-circle route track line (pure geometry, no text).
	u.colour = Color(0.72, 0.78, 0.84).srgb_to_linear()
	u.box(map_at + map_b * Vector3(0.0, 0.004, 0.0), Vector3(0.50, 0.002, 0.30), map_b)
	u.colour = Color(0.56, 0.62, 0.70).srgb_to_linear()
	for gx: float in [-0.16, 0.0, 0.16]:
		u.box(map_at + map_b * Vector3(gx, 0.0055, 0.0), Vector3(0.004, 0.0015, 0.29), map_b)
	for gz: float in [-0.08, 0.08]:
		u.box(map_at + map_b * Vector3(0.0, 0.0055, gz), Vector3(0.49, 0.0015, 0.004), map_b)
	# Vermilion great-circle route arc across the chart.
	u.colour = VERMILION.srgb_to_linear()
	var prev_pt := map_at + map_b * Vector3(-0.21, 0.007, 0.06)
	for seg in 5:
		var t_seg := float(seg + 1) / 5.0
		var nx := lerpf(-0.21, 0.21, t_seg)
		var nz := lerpf(0.06, -0.05, t_seg) - 0.075 * sin(t_seg * PI)
		var nxt := map_at + map_b * Vector3(nx, 0.007, nz)
		Shapes.beam(u, prev_pt, nxt, Vector2(0.005, 0.002))
		prev_pt = nxt

	# Brass-rimmed aerial compass rose binnacle on the right side of the chart table.
	var comp_at := Vector3(tx + 0.36, th, tz + 0.02)
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	Shapes.lathe(u, [
		Vector2(0.118, 0.0), Vector2(0.118, 0.014), Vector2(0.105, 0.018),
		Vector2(0.105, 0.044), Vector2(0.094, 0.052), Vector2(0.084, 0.048)
	], comp_at, 20)
	# Deep midnight-navy compass card + 4-point brass star rose + vermilion north pointer.
	u.surface(c.soft("plastic", true))
	u.colour = NAVY_DEEP.srgb_to_linear()
	Shapes.cylinder(u, comp_at + Vector3(0.0, 0.01, 0.0), 0.088, 0.028, 18)
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	for k in 4:
		var a := k * PI * 0.25
		var l_star := 0.145 if k % 2 == 0 else 0.105
		u.box(comp_at + Vector3(0.0, 0.040, 0.0), Vector3(0.011, 0.003, l_star), Basis(Vector3.UP, a))
	u.surface(c.soft("plastic", true))
	u.colour = VERMILION.srgb_to_linear()
	u.box(comp_at + Vector3(0.0, 0.043, -0.036), Vector3(0.010, 0.004, 0.068))
	# Pair of slim brass navigation dividers resting beside the compass + rolled brass chart tube on the lower shelf.
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	var div_piv := Vector3(tx + 0.18, th + 0.008, tz - 0.14)
	Shapes.beam(u, div_piv, div_piv + Vector3(0.05, 0.0, 0.13), Vector2(0.006, 0.005))
	Shapes.beam(u, div_piv, div_piv + Vector3(0.11, 0.0, 0.10), Vector2(0.006, 0.005))
	Shapes.cylinder(u, Vector3(tx - 0.34, 0.285, tz + 0.04), 0.034, 0.64, 12,
			Basis(Vector3.BACK, -PI * 0.5) * Basis(Vector3.UP, 0.08))
	c.shapes.append(PhysicsShapes.box(Vector3(tx, th * 0.5, tz), Vector3(tw, th, td), Basis()))

	# Port aft lounge credenza & framed geometric altitude-layer route plaque (symmetrical balance).
	var px := cx - hw * 0.54
	var pz := bz - 0.28
	var pw := 1.12
	var ph := 0.78
	var pd := 0.44
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Shapes.cylinder(u, Vector3(px + sx * (pw * 0.5 - 0.05), 0.0, pz + sz * (pd * 0.5 - 0.05)),
					0.014, ph - 0.03, 8)
	s.surface(c.tinted("wood"))
	s.colour = BIRCH_PALE.srgb_to_linear()
	s.box(Vector3(px, ph - 0.018, pz), Vector3(pw, 0.036, pd))
	s.colour = BIRCH_DEEP.srgb_to_linear()
	s.box(Vector3(px, 0.26, pz), Vector3(pw - 0.12, 0.024, pd - 0.1))
	# Cream-and-brass leather route logbook resting on the credenza top.
	u.surface(c.soft("plastic", true))
	u.colour = RUSSET.srgb_to_linear()
	u.box(Vector3(px - 0.16, ph + 0.014, pz), Vector3(0.28, 0.024, 0.22), Basis(Vector3.UP, 0.14))
	u.colour = PAPER_CREAM.srgb_to_linear()
	u.box(Vector3(px - 0.16, ph + 0.014, pz), Vector3(0.26, 0.018, 0.20), Basis(Vector3.UP, 0.14))
	# Sleek brushed-aluminium carafe & two tumblers on a small tray.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	u.box(Vector3(px + 0.22, ph + 0.008, pz), Vector3(0.32, 0.012, 0.22))
	Shapes.lathe(u, [Vector2(0.048, 0.012), Vector2(0.052, 0.08), Vector2(0.026, 0.17), Vector2(0.034, 0.22),
			Vector2(0.0, 0.22)], Vector3(px + 0.16, ph, pz - 0.02), 12)
	for dz_t: float in [-0.04, 0.05]:
		Shapes.lathe(u, [Vector2(0.024, 0.012), Vector2(0.028, 0.085)], Vector3(px + 0.29, ph, pz + dz_t), 10)
	c.shapes.append(PhysicsShapes.box(Vector3(px, ph * 0.5, pz), Vector3(pw, ph, pd), Basis()))

	# Framed Art Deco geometric cloud-layer & flight-altitude plaque mounted on the port aft bulkhead, plus a matching
	# framed transoceanic great-circle route map panel above the starboard navigation chart table (pure geometry).
	var plaque_y := 1.62
	s.surface(c.tinted("wood"))
	s.colour = BIRCH_DEEP.srgb_to_linear()
	s.box(Vector3(px, plaque_y, bz - 0.02), Vector3(0.96, 0.62, 0.03))
	s.box(Vector3(tx, plaque_y, bz - 0.02), Vector3(0.96, 0.62, 0.03))
	u.surface(c.soft("plastic", true))
	u.colour = NAVY_DEEP.srgb_to_linear()
	u.box(Vector3(px, plaque_y, bz - 0.036), Vector3(0.86, 0.52, 0.008))
	u.colour = Color(0.14, 0.22, 0.34).srgb_to_linear()
	u.box(Vector3(tx, plaque_y, bz - 0.036), Vector3(0.86, 0.52, 0.008))
	# Port plaque: golden stylized airship flight profile arc & cloud-deck waves.
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	for k in 3:
		var wy := plaque_y - 0.15 + 0.07 * k
		u.box(Vector3(px, wy, bz - 0.042), Vector3(0.76, 0.009, 0.006))
	var arc_prev := Vector3(px - 0.34, plaque_y - 0.15, bz - 0.044)
	for k in 6:
		var t_a := float(k + 1) / 6.0
		var ax := lerpf(px - 0.34, px + 0.34, t_a)
		var ay := plaque_y - 0.15 + 0.30 * sin(t_a * PI)
		var arc_nxt := Vector3(ax, ay, bz - 0.044)
		Shapes.beam(u, arc_prev, arc_nxt, Vector2(0.011, 0.006))
		arc_prev = arc_nxt
	# Starboard plaque: framed geometric transoceanic route map (champagne coast silhouettes, grid lines & red arc).
	for gx_m: float in [-0.26, 0.0, 0.26]:
		u.box(Vector3(tx + gx_m, plaque_y, bz - 0.042), Vector3(0.006, 0.48, 0.004))
	for gy_m: float in [-0.14, 0.0, 0.14]:
		u.box(Vector3(tx, plaque_y + gy_m, bz - 0.042), Vector3(0.80, 0.006, 0.004))
	u.surface(c.soft("plastic", true))
	u.colour = CREAM_WARM.srgb_to_linear()
	u.box(Vector3(tx - 0.31, plaque_y + 0.02, bz - 0.043), Vector3(0.16, 0.34, 0.005))
	u.box(Vector3(tx + 0.32, plaque_y - 0.04, bz - 0.043), Vector3(0.15, 0.28, 0.005))
	u.colour = VERMILION.srgb_to_linear()
	var r_prev := Vector3(tx - 0.24, plaque_y - 0.06, bz - 0.046)
	for k in 6:
		var t_r := float(k + 1) / 6.0
		var rx := lerpf(tx - 0.24, tx + 0.25, t_r)
		var ry := lerpf(plaque_y - 0.06, plaque_y + 0.04, t_r) + 0.12 * sin(t_r * PI)
		var r_nxt := Vector3(rx, ry, bz - 0.046)
		Shapes.beam(u, r_prev, r_nxt, Vector2(0.010, 0.005))
		r_prev = r_nxt

	s.colour = Color.WHITE
	u.colour = Color.WHITE


# --- The 1931 featherweight brushed-aluminium & cream-lacquered baby grand piano --------------------------------------

static func _piano(c: Object, xf: Transform3D) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var rot := xf.basis.orthonormalized()
	var pxf := Transform3D(rot, xf.origin)
	var rim_bot := 0.68
	var rim_top := 0.94
	var sound_y := 0.79

	# 1. Cream-lacquered S-curved grand piano rim walls (outer & inner faces + bottom floor + recessed soundboard).
	s.surface(c.tinted("plastic"))
	s.colour = CREAM_LACQUER.srgb_to_linear()
	var n_pts := GRAND_CONTOUR.size()
	var rim_thick := 0.034
	var centroid := Vector2(-0.08, -0.18)
	var outer_bot := PackedVector3Array()
	var outer_top := PackedVector3Array()
	var outer_n := PackedVector3Array()
	var inner_bot := PackedVector3Array()
	var inner_top := PackedVector3Array()
	var inner_n := PackedVector3Array()
	var top_poly_out: Array[Vector3] = []
	var bot_poly_out: Array[Vector3] = []
	var sound_poly: Array[Vector3] = []
	for i in n_pts:
		var p: Vector2 = GRAND_CONTOUR[i]
		var prev_p: Vector2 = GRAND_CONTOUR[(i - 1 + n_pts) % n_pts]
		var next_p: Vector2 = GRAND_CONTOUR[(i + 1) % n_pts]
		var tang := (next_p - prev_p).normalized()
		# Contour runs clockwise in (x, z) when viewed from +Y -> outward normal is (-tang.y, tang.x)? Verify against centroid!
		var n2 := Vector2(-tang.y, tang.x)
		if n2.dot(p - centroid) < 0.0:
			n2 = -n2
		var p_in := p - n2 * rim_thick
		var n3 := (rot * Vector3(n2.x, 0.0, n2.y)).normalized()
		outer_bot.append(pxf * Vector3(p.x, rim_bot, p.y))
		outer_top.append(pxf * Vector3(p.x, rim_top, p.y))
		outer_n.append(n3)
		inner_bot.append(pxf * Vector3(p_in.x, sound_y, p_in.y))
		inner_top.append(pxf * Vector3(p_in.x, rim_top, p_in.y))
		inner_n.append(-n3)
		top_poly_out.append(pxf * Vector3(p.x, rim_top, p.y))
		bot_poly_out.append(pxf * Vector3(p.x, rim_bot, p.y))
		sound_poly.append(pxf * Vector3(p_in.x, sound_y, p_in.y))
	# Close the rim strips seamlessly back to index 0.
	outer_bot.append(outer_bot[0])
	outer_top.append(outer_top[0])
	outer_n.append(outer_n[0])
	inner_bot.append(inner_bot[0])
	inner_top.append(inner_top[0])
	inner_n.append(inner_n[0])
	s.strip(outer_bot, outer_top, outer_n)
	s.strip(inner_top, inner_bot, inner_n)
	# Top lip band of the curved rim (between outer and inner perimeter at rim_top).
	var rim_up := PackedVector3Array()
	for i in n_pts + 1:
		rim_up.append(rot * Vector3.UP)
	s.strip(outer_top, inner_top, rim_up)
	# Underside floor plate of the grand case.
	s.polygon(PackedVector3Array(bot_poly_out), rot * Vector3.DOWN)

	# 2. Pale warm spruce/birch interior soundboard.
	s.surface(c.tinted("wood"))
	s.colour = BIRCH_PALE.srgb_to_linear()
	s.polygon(PackedVector3Array(sound_poly), rot * Vector3.UP)

	# 3. Gleaming champagne-bronze cast harp frame (with featherweight airship struts) + diagonal golden strings!
	u.surface(c.shiny("gilt", 0.88, 0.72, 0.14))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	var harp_y := sound_y + 0.032
	# Curved hitch-pin tail arc and front wrest-plank header bar.
	for i in range(1, n_pts - 1):
		var pa: Vector2 = GRAND_CONTOUR[i].lerp(centroid, 0.16)
		var pb: Vector2 = GRAND_CONTOUR[i + 1].lerp(centroid, 0.16)
		Shapes.beam(u, pxf * Vector3(pa.x, harp_y, pa.y), pxf * Vector3(pb.x, harp_y, pb.y), Vector2(0.036, 0.022))
	_pbox(u, pxf, Vector3(0.0, harp_y, 0.25), Vector3(1.12, 0.024, 0.10))
	# Three radial cast harp ribs spanning from the wrest-plank back to the tail curve.
	for rib: Array in [[Vector2(-0.46, 0.24), Vector2(-0.46, -0.58)],
			[Vector2(-0.10, 0.24), Vector2(-0.22, -0.64)],
			[Vector2(0.28, 0.24), Vector2(0.06, -0.44)]]:
		var ra: Vector2 = rib[0]
		var rb: Vector2 = rib[1]
		Shapes.beam(u, pxf * Vector3(ra.x, harp_y + 0.012, ra.y), pxf * Vector3(rb.x, harp_y + 0.012, rb.y),
				Vector2(0.030, 0.026))
	# Fan of gilded treble strings and overstrung bass strings glinting beneath the open lid.
	var str_y := harp_y + 0.022
	for k in 14:
		var t_s := float(k) / 13.0
		var sx0 := lerpf(-0.48, 0.48, t_s)
		var sx1 := lerpf(-0.44, 0.42, t_s)
		var sz1 := lerpf(-0.62, 0.04, pow(t_s, 1.35))
		Shapes.beam(u, pxf * Vector3(sx0, str_y, 0.25), pxf * Vector3(sx1, str_y, sz1), Vector2(0.006, 0.006))
	for k in 6:
		var t_b := float(k) / 5.0
		var bx0 := lerpf(-0.50, -0.24, t_b)
		var bx1 := lerpf(-0.16, 0.08, t_b)
		var bz1 := lerpf(-0.63, -0.44, t_b)
		Shapes.beam(u, pxf * Vector3(bx0, str_y + 0.014, 0.24), pxf * Vector3(bx1, str_y + 0.014, bz1),
				Vector2(0.008, 0.008))
	# Dark felt russet damper bar crossing the strings cleanly.
	u.surface(c.soft("plastic", true))
	u.colour = RUSSET.srgb_to_linear()
	_pbox(u, pxf, Vector3(-0.02, str_y + 0.016, 0.14), Vector3(0.98, 0.020, 0.040))

	# 4. Brushed-duralumin Art Deco twin speed-ribs wrapping the outer curved cream rim!
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	for ry: float in [rim_bot + 0.024, rim_top - 0.018]:
		for i in n_pts:
			var pa: Vector2 = GRAND_CONTOUR[i]
			var pb: Vector2 = GRAND_CONTOUR[(i + 1) % n_pts]
			Shapes.beam(u, pxf * Vector3(pa.x, ry, pa.y), pxf * Vector3(pb.x, ry, pb.y), Vector2(0.016, 0.016))

	# 5. Propped-open cream & brushed-aluminium baby grand lid (tilted 34 deg around the straight -X bass spine)
	#    with exact concave polygon triangulation and three featherweight duralumin underside acoustic ribs!
	var hinge_local := Vector3(-0.62, rim_top + 0.012, 0.0)
	var lid_tilt := Basis(Vector3.BACK, deg_to_rad(34.0))
	var lid_xf := pxf * Transform3D(Basis(), hinge_local) * Transform3D(lid_tilt, Vector3.ZERO) \
			* Transform3D(Basis(), -hinge_local)
	var lid_thick := 0.024
	var lid_top_poly: Array[Vector3] = []
	var lid_bot_poly: Array[Vector3] = []
	var lid_edge_b := PackedVector3Array()
	var lid_edge_t := PackedVector3Array()
	var lid_edge_n := PackedVector3Array()
	for i in n_pts:
		var p: Vector2 = GRAND_CONTOUR[i]
		var prev_p: Vector2 = GRAND_CONTOUR[(i - 1 + n_pts) % n_pts]
		var next_p: Vector2 = GRAND_CONTOUR[(i + 1) % n_pts]
		var tang := (next_p - prev_p).normalized()
		var n2 := Vector2(-tang.y, tang.x)
		if n2.dot(p - centroid) < 0.0:
			n2 = -n2
		var pb := lid_xf * Vector3(p.x, rim_top + 0.008, p.y)
		var pt := lid_xf * Vector3(p.x, rim_top + 0.008 + lid_thick, p.y)
		lid_bot_poly.append(pb)
		lid_top_poly.append(pt)
		lid_edge_b.append(pb)
		lid_edge_t.append(pt)
		lid_edge_n.append((lid_xf.basis * Vector3(n2.x, 0.0, n2.y)).normalized())
	lid_edge_b.append(lid_edge_b[0])
	lid_edge_t.append(lid_edge_t[0])
	lid_edge_n.append(lid_edge_n[0])
	s.surface(c.tinted("plastic"))
	s.colour = CREAM_LACQUER.srgb_to_linear()
	s.polygon(PackedVector3Array(lid_top_poly), (lid_xf.basis * Vector3.UP).normalized())
	s.surface(c.tinted("wood"))
	s.colour = BIRCH_PALE.srgb_to_linear()
	s.polygon(PackedVector3Array(lid_bot_poly), (lid_xf.basis * Vector3.DOWN).normalized())
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	u.strip(lid_edge_b, lid_edge_t, lid_edge_n)
	# Three gleaming brushed-duralumin acoustic stiffening ribs across the underside of the propped grand lid!
	for lrib: Array in [[Vector2(-0.56, 0.16), Vector2(0.46, 0.16)],
			[Vector2(-0.56, -0.14), Vector2(0.26, -0.14)],
			[Vector2(-0.54, -0.44), Vector2(0.08, -0.44)]]:
		var la: Vector2 = lrib[0]
		var lb: Vector2 = lrib[1]
		Shapes.beam(u, lid_xf * Vector3(la.x, rim_top + 0.002, la.y), lid_xf * Vector3(lb.x, rim_top + 0.002, lb.y),
				Vector2(0.016, 0.014))
	# Brushed-aluminium tubular lid prop stick rising from the treble inner rim to the open lid underside!
	var prop_bot := pxf * Vector3(0.42, rim_top - 0.02, 0.04)
	var prop_top := lid_xf * Vector3(0.42, rim_top + 0.008, 0.04)
	Shapes.beam(u, prop_bot, prop_top, Vector2(0.016, 0.016))
	# Three gleaming aluminium lid hinges along the bass spine.
	for hz: float in [-0.36, -0.04, 0.26]:
		_pbox(u, pxf, Vector3(-0.625, rim_top + 0.01, hz), Vector3(0.022, 0.02, 0.055))

	# 6. Projecting keybed, cream & aluminium cheeks, open folded fallboard & pierced aluminium music desk.
	s.surface(c.tinted("plastic"))
	s.colour = CREAM_LACQUER.srgb_to_linear()
	# Keybed slab projecting forward (z = +0.34 .. +0.60, top at KEYBED_TOP_Y = 0.712).
	_pbox(s, pxf, Vector3(0.0, KEYBED_TOP_Y - 0.032, 0.47), Vector3(1.24, 0.064, 0.27))
	# Rounded keyslip lip along front of keys + flanking cheek blocks.
	_pbox(s, pxf, Vector3(0.0, KEYBED_TOP_Y - 0.002, 0.592), Vector3(1.12, 0.026, 0.026))
	for sx: float in [-1.0, 1.0]:
		_pbox(s, pxf, Vector3(sx * 0.585, KEYBED_TOP_Y + 0.055, 0.47), Vector3(0.072, 0.115, 0.27))
	# Open folded fallboard & nameboard behind the 61 keys.
	_pbox(s, pxf, Vector3(0.0, KEYBED_TOP_Y + 0.088, 0.365), Vector3(1.12, 0.14, 0.045))
	# Subtle brushed-aluminium inlay strip along the front keybed & cheek tops.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	_pbox(u, pxf, Vector3(0.0, KEYBED_TOP_Y - 0.032, 0.608), Vector3(1.25, 0.016, 0.014))
	for sx: float in [-1.0, 1.0]:
		_pbox(u, pxf, Vector3(sx * 0.585, KEYBED_TOP_Y + 0.116, 0.47), Vector3(0.076, 0.012, 0.275))
	# Pierced modernist aluminium music desk resting over the fallboard, holding two open cream score pages.
	var desk_b := Basis(Vector3.RIGHT, deg_to_rad(-18.0))
	_pbox(u, pxf, Vector3(0.0, KEYBED_TOP_Y + 0.24, 0.33), Vector3(0.76, 0.018, 0.016), desk_b)
	_pbox(u, pxf, Vector3(0.0, KEYBED_TOP_Y + 0.40, 0.275), Vector3(0.76, 0.016, 0.014), desk_b)
	_pbox(u, pxf, Vector3(0.0, KEYBED_TOP_Y + 0.225, 0.355), Vector3(0.78, 0.014, 0.042))
	for k in 5:
		var dx := lerpf(-0.34, 0.34, float(k) / 4.0)
		_pbox(u, pxf, Vector3(dx, KEYBED_TOP_Y + 0.32, 0.302), Vector3(0.014, 0.165, 0.012), desk_b)
	u.surface(c.soft("plastic", true))
	u.colour = PAPER_CREAM.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		_pbox(u, pxf, Vector3(sx * 0.115, KEYBED_TOP_Y + 0.325, 0.312), Vector3(0.21, 0.25, 0.005),
				desk_b * Basis(Vector3.UP, -sx * 0.05))
	# Subtle dark staff-line stripes across the open music pages (pure geometry).
	u.colour = CHARCOAL.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		for st_i in 4:
			var sy := KEYBED_TOP_Y + 0.25 + 0.048 * st_i
			_pbox(u, pxf, Vector3(sx * 0.115, sy, 0.316 + (sy - (KEYBED_TOP_Y + 0.325)) * -0.32),
					Vector3(0.16, 0.007, 0.003), desk_b * Basis(Vector3.UP, -sx * 0.05))

	# 7. Three featherweight tapered tubular brushed-aluminium legs with Art Deco speed collars & brass casters.
	var leg_places: Array[Vector2] = [Vector2(-0.50, 0.42), Vector2(0.50, 0.42), Vector2(-0.22, -0.58)]
	for lp: Vector2 in leg_places:
		var leg_base := pxf * Vector3(lp.x, 0.0, lp.y)
		u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
		u.colour = DURALUMIN.srgb_to_linear()
		Shapes.lathe(u, [
			Vector2(0.018, 0.045), Vector2(0.022, 0.07), Vector2(0.036, 0.56),
			Vector2(0.048, 0.58), Vector2(0.038, 0.60), Vector2(0.048, 0.625),
			Vector2(0.056, 0.68)
		], leg_base, 12, rot)
		# Brass caster shoe at foot of each leg.
		u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
		u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
		Shapes.lathe(u, [Vector2(0.014, 0.0), Vector2(0.024, 0.018), Vector2(0.022, 0.045)], leg_base, 10, rot)

	# 8. Modernist tubular aluminium pedal lyre with twin diagonal stay rods and three gleaming brass pedals.
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		Shapes.cylinder(u, pxf * Vector3(sx * 0.11, 0.075, 0.28), 0.014, 0.59, 8, rot)
		Shapes.beam(u, pxf * Vector3(sx * 0.11, 0.11, 0.27), pxf * Vector3(sx * 0.22, 0.66, -0.05),
				Vector2(0.011, 0.011))
	_pbox(u, pxf, Vector3(0.0, 0.085, 0.28), Vector3(0.28, 0.055, 0.075))
	u.surface(c.shiny("gilt", 0.86, 0.68, 0.15))
	u.colour = BRASS_CHAMPAGNE.srgb_to_linear()
	for sx: float in [-1.0, 0.0, 1.0]:
		_pbox(u, pxf, Vector3(sx * 0.068, 0.065, 0.35), Vector3(0.028, 0.014, 0.12))

	# 9. Matching featherweight tubular brushed-aluminium & russet-upholstered piano bench in front of the keyboard.
	var bench_z := 0.96
	var bench_h := 0.47
	u.surface(c.shiny("chrome", 0.92, 0.78, 0.14))
	u.colour = DURALUMIN.srgb_to_linear()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var fb := pxf * Vector3(sx * 0.33, 0.0, bench_z + sz * 0.155)
			var tb := pxf * Vector3(sx * 0.30, bench_h - 0.06, bench_z + sz * 0.135)
			Shapes.beam(u, fb, tb, Vector2(0.020, 0.020))
		Shapes.beam(u, pxf * Vector3(sx * 0.315, 0.16, bench_z - 0.145),
				pxf * Vector3(sx * 0.315, 0.16, bench_z + 0.145), Vector2(0.014, 0.014))
	Shapes.beam(u, pxf * Vector3(-0.315, 0.16, bench_z), pxf * Vector3(0.315, 0.16, bench_z), Vector2(0.014, 0.014))
	_pbox(u, pxf, Vector3(0.0, bench_h - 0.055, bench_z), Vector3(0.68, 0.032, 0.32))
	u.surface(c.soft("plastic", true))
	u.colour = RUSSET.srgb_to_linear()
	u.rounded_box(Vector3.ZERO, Vector3(0.66, 0.075, 0.31), 0.028, pxf * Transform3D(Basis(),
			Vector3(0.0, bench_h, bench_z)), 1)

	# Clean physics boxes enclosing the grand piano & bench (strictly inside cabin floor box).
	c.shapes.append(PhysicsShapes.box(pxf * Vector3(-0.04, 0.48, -0.04), Vector3(1.24, 0.96, 1.32), rot))
	c.shapes.append(PhysicsShapes.box(pxf * Vector3(0.0, bench_h * 0.5, bench_z), Vector3(0.68, bench_h, 0.34), rot))

	# Register the animated 61-key MultiMesh helper on c.halls!
	c.halls.append(PianoKeysHall.new(pxf))
	s.colour = Color.WHITE
	u.colour = Color.WHITE


# --- Geometry helpers -------------------------------------------------------------------------------------------------

static func _pbox(b: RoomMesh, xf: Transform3D, centre: Vector3, size: Vector3, local_b := Basis()) -> void:
	b.box(xf * centre, size, xf.basis * local_b)


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
