extends RefCounted

## Shared low-poly furniture (docs/environments.md, "The kit" and "domestic"): each piece draws itself into a RoomMesh
## in its own frame (xf places it: the middle of its foot at local y 0, its front facing local +Z), one surface a
## material, so a room pays draws by material, not by piece. The kit's pieces (pieces.gd) and the domestic builder's
## telly stands use them. Each returns its physics boxes, [[centre, size]] in its own frame. Plain boxes and turned
## shapes of our own: no maker's shape, no badge, no lettering. Static.
##
##   stand(kind, b, xf, size, m)     one of the next five by its name
##   desk(b, xf, size, m)            a top, a pedestal of three drawers on its right, legs on its left, a modesty panel
##   tv_unit(b, xf, size, m)         a low cabinet: an open shelf under the top (a video recorder's), doors below
##   radiogram(b, xf, size, m)       a long low cabinet on splayed legs: a grille of slats, two sliding doors
##   sideboard(b, xf, size, m)       doors either side, three drawers in the middle, short legs, the top overhanging
##   coffee_table(b, xf, size, m)    a top on four legs, a shelf under it
##   computer(b, xf, size, m, monitor)   a desktop case, a CRT monitor on it (or none), a keyboard in front
##   video_recorder(b, xf, size, m) -> [centre, right, up, normal, height]: its display window, for its digits
##   standard_lamp(b, lit, xf, size, m) -> the shade's middle (local): a round base, a pole, a drum shade (into lit)
##   rug(b, xf, size, m)             a field, a border, a fringe at either end
##   seven_segments(text, centre, right, up, normal, height) -> quads   a clock's digits ("12:00") as glow quads
## m: {"body": Material, "detail": Material (handles, slots, the screen's glass; the body's when missing), "pole",
## "shade"}.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")

## The tv_unit's open shelf: its height (a video recorder fits) and the top board's thickness.
const SHELF_H := 0.14
const TOP_T := 0.03
## A seven-segment digit's segments: a top, b upper right, c lower right, d bottom, e lower left, f upper left,
## g middle.
const DIGITS := {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
		"7": "abc", "8": "abcdefg", "9": "abcdfg"}


## A stand or a table by its name (desk, tv_unit, radiogram, sideboard, coffee_table): its physics boxes.
static func stand(kind: String, b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Array:
	match kind:
		"desk":
			return desk(b, xf, size, m)
		"tv_unit":
			return tv_unit(b, xf, size, m)
		"radiogram":
			return radiogram(b, xf, size, m)
		"sideboard":
			return sideboard(b, xf, size, m)
		"coffee_table":
			return coffee_table(b, xf, size, m)
	return []


static func _box(b: RoomMesh, xf: Transform3D, centre: Vector3, size: Vector3, basis := Basis(), skip: Array = []) -> void:
	b.box(xf * centre, size * xf.basis.get_scale().x, xf.basis.orthonormalized() * basis, skip)


static func _detail(m: Dictionary) -> Material:
	return m.get("detail", m["body"])


## A handle: a short bar on a front at z.
static func _handle(b: RoomMesh, xf: Transform3D, at: Vector3, width := 0.1) -> void:
	_box(b, xf, at, Vector3(width, 0.014, 0.018), Basis(), [RoomMesh.BACK])


# --- Stands and cabinets -------------------------------------------------------------------------------------------

static func desk(b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Array:
	var w := size.x
	var h := size.y
	var d := size.z
	var under := maxf(h - TOP_T, 0.05)
	var pw := minf(0.42, w * 0.36)
	var px := w * 0.5 - pw * 0.5 - 0.02
	b.surface(m["body"])
	_box(b, xf, Vector3(0, h - TOP_T * 0.5, 0), Vector3(w, TOP_T, d))
	_box(b, xf, Vector3(px, under * 0.5, -0.01), Vector3(pw, under, d - 0.04), Basis(), [RoomMesh.DOWN, RoomMesh.UP])
	for s: float in [-1.0, 1.0]:
		_box(b, xf, Vector3(-w * 0.5 + 0.045, under * 0.5, s * (d * 0.5 - 0.05)), Vector3(0.045, under, 0.045), Basis(),
				[RoomMesh.DOWN, RoomMesh.UP])
	_box(b, xf, Vector3((-w * 0.5 + 0.07 + px - pw * 0.5) * 0.5, h - TOP_T - under * 0.22, -d * 0.5 + 0.04),
			Vector3(px - pw * 0.5 - (-w * 0.5 + 0.07), under * 0.44, 0.018))
	var rows := 3
	var dh := under / rows
	for k in rows:
		var y := under - (k + 0.5) * dh
		_box(b, xf, Vector3(px, y, d * 0.5 - 0.022), Vector3(pw - 0.03, dh - 0.02, 0.014), Basis(), [RoomMesh.BACK])
	b.surface(_detail(m))
	for k in rows:
		_handle(b, xf, Vector3(px, under - (k + 0.5) * dh, d * 0.5 - 0.006))
	return [[Vector3(0, h - TOP_T * 0.5, 0), Vector3(w, TOP_T, d)], [Vector3(px, under * 0.5, 0), Vector3(pw, under, d)]]


static func tv_unit(b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Array:
	var w := size.x
	var h := size.y
	var d := size.z
	var shelf := shelf_floor(h)
	b.surface(m["body"])
	_box(b, xf, Vector3(0, h - TOP_T * 0.5, 0), Vector3(w, TOP_T, d))
	for s: float in [-1.0, 1.0]:
		_box(b, xf, Vector3(s * (w * 0.5 - 0.0125), (h - TOP_T) * 0.5, 0), Vector3(0.025, h - TOP_T, d), Basis(),
				[RoomMesh.DOWN, RoomMesh.UP])
	_box(b, xf, Vector3(0, 0.03, 0), Vector3(w - 0.05, 0.06, d - 0.04), Basis(), [RoomMesh.DOWN])
	_box(b, xf, Vector3(0, (h - TOP_T + 0.06) * 0.5, -d * 0.5 + 0.008), Vector3(w - 0.05, h - TOP_T - 0.06, 0.016),
			Basis(), [RoomMesh.BACK])
	if shelf > 0.12:
		_box(b, xf, Vector3(0, shelf - 0.0125, 0), Vector3(w - 0.05, 0.025, d - 0.02))
		# Two doors under the shelf.
		var dh := shelf - 0.025 - 0.07
		if dh > 0.08:
			var dw := (w - 0.06) * 0.5 - 0.004
			for s: float in [-1.0, 1.0]:
				_box(b, xf, Vector3(s * (dw * 0.5 + 0.004), 0.065 + dh * 0.5, d * 0.5 - 0.009), Vector3(dw, dh, 0.018),
						Basis(), [RoomMesh.BACK])
			b.surface(_detail(m))
			for s: float in [-1.0, 1.0]:
				_box(b, xf, Vector3(s * 0.04, 0.065 + dh * 0.75, d * 0.5 + 0.006), Vector3(0.014, 0.08, 0.018), Basis(),
						[RoomMesh.BACK])
	return [[Vector3(0, h * 0.5, 0), Vector3(w, h, d)]]


## The tv_unit's shelf: the floor of the opening under its top (h: the unit's height); 0 when it is too low for one.
static func shelf_floor(h: float) -> float:
	var y := h - TOP_T - SHELF_H
	return y if y > 0.12 else 0.0


static func radiogram(b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Array:
	var w := size.x
	var h := size.y
	var d := size.z
	var legs := minf(0.16, h * 0.3)
	var body := h - legs
	b.surface(m["body"])
	_box(b, xf, Vector3(0, legs + body * 0.5, 0), Vector3(w, body, d))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var splay := Basis(Vector3.BACK, deg_to_rad(-8.0 * sx)) * Basis(Vector3.RIGHT, deg_to_rad(6.0 * sz))
			_box(b, xf, Vector3(sx * (w * 0.5 - 0.1), legs * 0.5 + 0.005, sz * (d * 0.5 - 0.08)),
					Vector3(0.035, legs + 0.02, 0.035), splay, [RoomMesh.UP])
	# The grille: slats over the left third; two sliding doors over the rest, one a little behind the other.
	var gw := w * 0.32
	var gx := -w * 0.5 + 0.04 + gw * 0.5
	var slats := maxi(int(gw / 0.04), 3)
	for k in slats:
		var x := gx - gw * 0.5 + (k + 0.5) * gw / slats
		_box(b, xf, Vector3(x, legs + body * 0.5, d * 0.5 + 0.006), Vector3(0.016, body * 0.72, 0.012), Basis(),
				[RoomMesh.BACK])
	var rest := w - gw - 0.12
	var dw := rest * 0.5 + 0.02
	for k in 2:
		var x := gx + gw * 0.5 + 0.04 + dw * 0.5 + k * (rest - dw)
		_box(b, xf, Vector3(x, legs + body * 0.5, d * 0.5 + 0.004 + k * 0.012), Vector3(dw, body * 0.78, 0.012),
				Basis(), [RoomMesh.BACK])
	b.surface(_detail(m))
	for k in 2:
		var x := gx + gw * 0.5 + 0.04 + dw * 0.5 + k * (rest - dw) + (dw * 0.38 if k == 0 else -dw * 0.38)
		_box(b, xf, Vector3(x, legs + body * 0.5, d * 0.5 + 0.012 + k * 0.012), Vector3(0.014, 0.07, 0.008), Basis(),
				[RoomMesh.BACK])
	return [[Vector3(0, h * 0.5, 0), Vector3(w, h, d)]]


static func sideboard(b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Array:
	var w := size.x
	var h := size.y
	var d := size.z
	var legs := minf(0.14, h * 0.2)
	var body := h - legs - 0.025
	b.surface(m["body"])
	_box(b, xf, Vector3(0, h - 0.0125, 0.0), Vector3(w + 0.04, 0.025, d + 0.02))
	_box(b, xf, Vector3(0, legs + body * 0.5, -0.01), Vector3(w, body, d - 0.02), Basis(), [RoomMesh.UP])
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(b, xf, Vector3(sx * (w * 0.5 - 0.06), legs * 0.5, sz * (d * 0.5 - 0.06)), Vector3(0.035, legs, 0.035),
					Basis(), [RoomMesh.UP])
	# Doors either side, three drawers between them.
	var door := w * 0.31
	var mid := w - door * 2.0 - 0.06
	var front := d * 0.5 - 0.01
	for s: float in [-1.0, 1.0]:
		_box(b, xf, Vector3(s * (w * 0.5 - 0.015 - door * 0.5), legs + body * 0.5, front), Vector3(door, body - 0.03, 0.016),
				Basis(), [RoomMesh.BACK])
	var dh := (body - 0.03) / 3.0
	for k in 3:
		_box(b, xf, Vector3(0, legs + 0.015 + (k + 0.5) * dh, front), Vector3(mid, dh - 0.012, 0.016), Basis(),
				[RoomMesh.BACK])
	b.surface(_detail(m))
	for s: float in [-1.0, 1.0]:
		_box(b, xf, Vector3(s * (w * 0.5 - 0.015 - door + 0.04), legs + body * 0.55, front + 0.012),
				Vector3(0.014, 0.1, 0.014), Basis(), [RoomMesh.BACK])
	for k in 3:
		_handle(b, xf, Vector3(0, legs + 0.015 + (k + 0.5) * dh, front + 0.012), minf(0.14, mid * 0.4))
	return [[Vector3(0, h * 0.5, 0), Vector3(w, h, d)]]


static func coffee_table(b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Array:
	var w := size.x
	var h := size.y
	var d := size.z
	b.surface(m["body"])
	_box(b, xf, Vector3(0, h - 0.015, 0), Vector3(w, 0.03, d))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(b, xf, Vector3(sx * (w * 0.5 - 0.06), (h - 0.03) * 0.5, sz * (d * 0.5 - 0.06)),
					Vector3(0.04, h - 0.03, 0.04), Basis(), [RoomMesh.UP])
	_box(b, xf, Vector3(0, 0.12, 0), Vector3(w - 0.12, 0.02, d - 0.12))
	return [[Vector3(0, h - 0.015, 0), Vector3(w, 0.03, d)], [Vector3(0, 0.12, 0), Vector3(w - 0.1, 0.02, d - 0.1)]]


# --- Things on a desk or a shelf -----------------------------------------------------------------------------------

## A desktop computer: a flat case at the back with two drive slots, a CRT monitor standing on it (monitor false: none,
## a telly is its screen), a keyboard in front with its rows of keys.
static func computer(b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary, monitor := true) -> Array:
	var w := minf(size.x, 0.46)
	var d := size.z
	var case_d := minf(0.34, d * 0.56)
	var case_z := -d * 0.5 + case_d * 0.5
	var case_h := 0.11
	var out: Array = [[Vector3(0, case_h * 0.5, case_z), Vector3(w, case_h, case_d)]]
	b.surface(m["body"])
	_box(b, xf, Vector3(0, case_h * 0.5, case_z), Vector3(w, case_h, case_d), Basis(), [RoomMesh.DOWN])
	var kw := minf(size.x, 0.44)
	var kd := minf(0.17, d * 0.3)
	var kz := d * 0.5 - kd * 0.5
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(5.0))
	_box(b, xf, Vector3(0, 0.016, kz), Vector3(kw, 0.03, kd), tilt, [RoomMesh.DOWN])
	if monitor:
		var mw := minf(w * 0.8, 0.36)
		var mh := mw * 0.86
		var my := case_h + mh * 0.5 + 0.01
		var mz := case_z + case_d * 0.5 - 0.05
		_box(b, xf, Vector3(0, my, mz), Vector3(mw, mh, 0.08))
		_box(b, xf, Vector3(0, my + 0.01, mz - 0.04 - 0.11), Vector3(mw * 0.72, mh * 0.74, 0.22), Basis(),
				[RoomMesh.FRONT])
		_box(b, xf, Vector3(0, case_h + 0.005, mz - 0.08), Vector3(mw * 0.5, 0.012, 0.2), Basis(), [RoomMesh.DOWN])
		out.append([Vector3(0, my, mz - 0.1), Vector3(mw, mh, 0.3)])
	b.surface(_detail(m))
	if monitor:
		var mw := minf(w * 0.8, 0.36)
		var mh := mw * 0.86
		_box(b, xf, Vector3(0, case_h + mh * 0.5 + 0.02, case_z + case_d * 0.5 - 0.009), Vector3(mw * 0.78, mh * 0.7,
				0.004), Basis(), [RoomMesh.BACK])
	for k in 2:
		_box(b, xf, Vector3(w * 0.18, case_h * (0.68 - k * 0.32), case_z + case_d * 0.5 + 0.002),
				Vector3(w * 0.32, 0.008, 0.004), Basis(), [RoomMesh.BACK])
	# The keys' rows: raised strips in the keyboard's top, the space bar shorter at the front.
	for r in 5:
		var z := kz - kd * 0.5 + 0.022 + r * (kd - 0.04) / 4.0
		var width := (kw - 0.05) * (0.55 if r == 4 else 1.0)
		_box(b, xf, Vector3(0, 0.033 + (kd * 0.5 - (z - kz + kd * 0.5)) * tan(deg_to_rad(5.0)), z),
				Vector3(width, 0.008, 0.024), tilt, [RoomMesh.DOWN])
	out.append([Vector3(0, 0.02, kz), Vector3(kw, 0.04, kd)])
	return out


## A video recorder: a slim case, the cassette's door, a row of buttons, the display window on the right. Returns the
## window's place for its digits: [centre, right, up, normal, digit height] in the room.
static func video_recorder(b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Array:
	var w := size.x
	var h := size.y
	var d := size.z
	b.surface(m["body"])
	_box(b, xf, Vector3(0, h * 0.5 + 0.006, 0), Vector3(w, h - 0.012, d), Basis(), [RoomMesh.DOWN])
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(b, xf, Vector3(sx * (w * 0.5 - 0.04), 0.003, sz * (d * 0.5 - 0.04)), Vector3(0.03, 0.006, 0.03), Basis(),
					[RoomMesh.DOWN, RoomMesh.UP])
	var front := d * 0.5
	b.surface(_detail(m))
	_box(b, xf, Vector3(-w * 0.17, h * 0.6, front + 0.002), Vector3(w * 0.44, h * 0.34, 0.004), Basis(), [RoomMesh.BACK])
	for k in 5:
		_box(b, xf, Vector3(-w * 0.37 + k * w * 0.05, h * 0.26, front + 0.003), Vector3(w * 0.035, h * 0.09, 0.006),
				Basis(), [RoomMesh.BACK])
	var win := Vector2(w * 0.26, h * 0.36)
	var at := Vector3(w * 0.27, h * 0.58, front + 0.0015)
	_box(b, xf, at, Vector3(win.x, win.y, 0.003), Basis(), [RoomMesh.BACK])
	var k := xf.basis.get_scale().x
	var basis := xf.basis.orthonormalized()
	return [xf * (at + Vector3(0, 0, 0.0035)), basis.x, basis.y, basis.z, win.y * 0.62 * k]


## A standard lamp: a round weighted base, a thin pole (m.pole, or the body), and a drum shade drawn into lit (m.shade:
## the lamp's glow, unbaked). Returns the shade's middle, in its own frame.
static func standard_lamp(b: RoomMesh, lit: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Vector3:
	var h := size.y
	var r := clampf(size.x * 0.5, 0.12, 0.35)
	var k := xf.basis.get_scale().x
	var basis := xf.basis.orthonormalized()
	b.surface(m.get("pole", m["body"]))
	var base: Array = []
	for p: Vector2 in [Vector2(r * 0.7, 0.0), Vector2(r * 0.7, 0.02), Vector2(r * 0.45, 0.045), Vector2(0.02, 0.06)]:
		base.append(p * k)
	Shapes.lathe(b, base, xf * Vector3.ZERO, 14, basis)
	var shade_h := clampf(h * 0.18, 0.18, 0.34)
	var pole_top := h - shade_h * 0.6
	Shapes.cylinder(b, xf * Vector3(0, 0.05, 0), 0.012 * k, (pole_top - 0.05) * k, 6, basis, false)
	lit.surface(m["shade"])
	var shade: Array = []
	for p: Vector2 in [Vector2(r, h - shade_h), Vector2(r * 0.78, h)]:
		shade.append(p * k)
	Shapes.lathe(lit, shade, xf * Vector3.ZERO, 16, basis)
	return Vector3(0, h - shade_h * 0.5, 0)


## A rug on the floor: its field, a border round it a little raised, a fringe at either end (along its width).
static func rug(b: RoomMesh, xf: Transform3D, size: Vector3, m: Dictionary) -> Array:
	var w := size.x
	var d := size.z
	var t := 0.012
	var bw := minf(w, d) * 0.08
	b.surface(m["body"])
	_box(b, xf, Vector3(0, t * 0.5, 0), Vector3(w, t, d), Basis(), [RoomMesh.DOWN])
	b.surface(_detail(m))
	var y := t + 0.001
	for s: float in [-1.0, 1.0]:
		_face(b, xf, [Vector3(-w * 0.5, y, s * d * 0.5), Vector3(w * 0.5, y, s * d * 0.5),
				Vector3(w * 0.5, y, s * (d * 0.5 - bw)), Vector3(-w * 0.5, y, s * (d * 0.5 - bw))], Vector3.UP)
		_face(b, xf, [Vector3(s * w * 0.5, y, -d * 0.5 + bw), Vector3(s * (w * 0.5 - bw), y, -d * 0.5 + bw),
				Vector3(s * (w * 0.5 - bw), y, d * 0.5 - bw), Vector3(s * w * 0.5, y, d * 0.5 - bw)], Vector3.UP)
		# The fringe, on the floor beyond the end.
		_face(b, xf, [Vector3(-w * 0.5 + 0.02, 0.002, s * d * 0.5), Vector3(w * 0.5 - 0.02, 0.002, s * d * 0.5),
				Vector3(w * 0.5 - 0.02, 0.002, s * (d * 0.5 + 0.05)), Vector3(-w * 0.5 + 0.02, 0.002, s * (d * 0.5 + 0.05))],
				Vector3.UP)
	return []


static func _face(b: RoomMesh, xf: Transform3D, corners: Array, n: Vector3) -> void:
	var w: Array = []
	for p: Vector3 in corners:
		w.append(xf * p)
	b.face(w, (xf.basis * n).normalized())


## A clock's digits as glow quads ([centre, half across, half up, facing] each) in a seven-segment face: text of
## digits and colons ("12:00"), centred on `centre` in the plane of right and up, `height` tall.
static func seven_segments(text: String, centre: Vector3, right: Vector3, up: Vector3, normal: Vector3,
		height: float) -> Array:
	var dw := height * 0.55
	var t := height * 0.14
	var gap := height * 0.22
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var cw := t if ch == ":" else dw
		widths.append(cw)
		total += cw + gap
	total -= gap
	var out: Array = []
	var x := -total * 0.5
	for i in text.length():
		var ch := text[i]
		var cx := x + widths[i] * 0.5
		if ch == ":":
			for s: float in [-1.0, 1.0]:
				out.append([centre + right * cx + up * (s * height * 0.2), right * t * 0.5, up * t * 0.5, normal])
		else:
			var hx := dw * 0.5
			var hy := height * 0.5
			var long_h := hx - t * 0.6
			var long_v := hy * 0.5 - t * 0.6
			var seg := {"a": [Vector2(0, hy - t * 0.5), true], "d": [Vector2(0, -hy + t * 0.5), true],
					"g": [Vector2(0, 0), true], "f": [Vector2(-hx + t * 0.5, hy * 0.5), false],
					"b": [Vector2(hx - t * 0.5, hy * 0.5), false], "e": [Vector2(-hx + t * 0.5, -hy * 0.5), false],
					"c": [Vector2(hx - t * 0.5, -hy * 0.5), false]}
			for s: String in str(DIGITS.get(ch, "")):
				var p: Vector2 = seg[s][0]
				var across := bool(seg[s][1])
				out.append([centre + right * (cx + p.x) + up * p.y, right * (long_h if across else t * 0.5),
						up * (t * 0.5 if across else long_v), normal])
		x += widths[i] + gap
	return out
