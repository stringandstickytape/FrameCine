extends Control

## Draws one frame of a test video laid out like real content of the given mode: each eye's picture in its place
## (left / right half, top / bottom half), in the eye's own projection (flat card, equirectangular grid, fisheye
## circle). Every eye says which eye it is and the eyes have different tints, so the per-eye mapping can be checked
## at a glance; stereo patterns also carry a ring with crossed disparity that floats IN FRONT of the background when
## the eyes are right (and sinks behind it when they are swapped). Rendered in a SubViewport by StubVideoSource.

const VideoMode := preload("res://scripts/video_mode.gd")
const DualFisheye := preload("res://scripts/play/dual_fisheye.gd")

const TINT_MONO := Color(0.22, 0.22, 0.24)
const TINT_LEFT := Color(0.36, 0.13, 0.10)
const TINT_RIGHT := Color(0.08, 0.16, 0.38)
const BARS: Array[Color] = [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0),
		Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75), Color(0.05, 0.05, 0.05)]

var mode: VideoMode = VideoMode.new()
var title := "Test pattern"
var subtitle := ""
var time := 0.0
## Crossed disparity of the flat pattern's depth ring, in pixels of the eye's picture (spherical patterns: 1 degree).
var disparity := 24.0

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if mode.layout == VideoMode.Layout.MONO:
		_draw_eye(Rect2(Vector2.ZERO, size), -1)
		return
	var first := Rect2(Vector2.ZERO, size * (Vector2(0.5, 1) if mode.layout == VideoMode.Layout.SBS else Vector2(1, 0.5)))
	var second := Rect2(first.position + (Vector2(first.size.x, 0) if mode.layout == VideoMode.Layout.SBS
			else Vector2(0, first.size.y)), first.size)
	# A swapped file stores the right eye first.
	_draw_eye(first, 1 if mode.swap else 0)
	_draw_eye(second, 0 if mode.swap else 1)


func _eye_name(eye: int) -> String:
	return ["LEFT EYE", "RIGHT EYE"][eye] if eye >= 0 else "MONO"


func _eye_tint(eye: int) -> Color:
	return [TINT_LEFT, TINT_RIGHT][eye] if eye >= 0 else TINT_MONO


## Crossed disparity of `total` pixels between the eyes: the left eye's copy moves right, the right eye's left.
func _eye_shift(eye: int, total: float) -> float:
	return [total * 0.5, -total * 0.5][eye] if eye >= 0 else 0.0


func _timecode() -> String:
	var t := maxf(time, 0.0)
	return "%02d:%02d:%02d.%d" % [int(t / 3600.0), int(t / 60.0) % 60, int(t) % 60, int(t * 10.0) % 10]


func _text(pos: Vector2, text: String, font_size: int, color := Color.WHITE, center := true) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := pos + Vector2(-width * 0.5 if center else 0.0, font_size * 0.35)
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, font_size / 10), Color.BLACK)
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_eye(r: Rect2, eye: int) -> void:
	match mode.projection:
		VideoMode.Proj.FLAT:
			_draw_flat(r, eye)
		VideoMode.Proj.EQUIRECT_180:
			_draw_equirect(r, eye, 180.0)
		VideoMode.Proj.EQUIRECT_360:
			_draw_equirect(r, eye, 360.0)
		VideoMode.Proj.FISHEYE:
			_draw_fisheye(r, eye)
		VideoMode.Proj.DUAL_FISHEYE:
			_draw_dual_fisheye(r)


## Flat: drawn in display space and squeezed for half layouts, so circles come out round only when the player
## stretches the eye back to the right aspect.
func _draw_flat(r: Rect2, eye: int) -> void:
	var squeeze := Vector2.ONE
	if mode.half and mode.layout == VideoMode.Layout.SBS:
		squeeze = Vector2(0.5, 1)
	elif mode.half and mode.layout == VideoMode.Layout.TB:
		squeeze = Vector2(1, 0.5)
	var d := r.size / squeeze
	draw_set_transform(r.position, 0.0, squeeze)
	draw_rect(Rect2(Vector2.ZERO, d), _eye_tint(eye))
	# Square grid, 9 cells high.
	var cell := d.y / 9.0
	var grid := Color(1, 1, 1, 0.25)
	var x := fmod(d.x * 0.5, cell)
	while x < d.x:
		draw_line(Vector2(x, 0), Vector2(x, d.y), grid, 2.0)
		x += cell
	var y := fmod(d.y * 0.5, cell)
	while y < d.y:
		draw_line(Vector2(0, y), Vector2(d.x, y), grid, 2.0)
		y += cell
	draw_rect(Rect2(Vector2(3, 3), d - Vector2(6, 6)), Color.WHITE, false, 6.0)
	var c := d * 0.5
	draw_arc(c, d.y * 0.36, 0.0, TAU, 96, Color(1, 1, 1, 0.8), 4.0)
	draw_line(c - Vector2(d.y * 0.05, 0), c + Vector2(d.y * 0.05, 0), Color.WHITE, 3.0)
	draw_line(c - Vector2(0, d.y * 0.05), c + Vector2(0, d.y * 0.05), Color.WHITE, 3.0)
	# Colour bars and a grey ramp along the bottom (chroma order / swapped planes show at once).
	var bar_w := d.x * 0.6 / BARS.size()
	var bar_y := d.y * 0.80
	for i in BARS.size():
		draw_rect(Rect2(Vector2(d.x * 0.2 + i * bar_w, bar_y), Vector2(bar_w, d.y * 0.07)), BARS[i])
	for i in 16:
		var v := i / 15.0
		draw_rect(Rect2(Vector2(d.x * 0.2 + i * d.x * 0.6 / 16.0, bar_y + d.y * 0.07), Vector2(d.x * 0.6 / 16.0,
				d.y * 0.04)), Color(v, v, v))
	# Corners, to spot flips.
	var fs := int(d.y * 0.045)
	_text(Vector2(d.x * 0.06, d.y * 0.07), "TOP LEFT", fs, Color.WHITE, false)
	_text(Vector2(d.x * 0.94 - fs * 5.6, d.y * 0.07), "TOP RIGHT", fs, Color.WHITE, false)
	_text(Vector2(d.x * 0.06, d.y * 0.93), "BOTTOM LEFT", fs, Color.WHITE, false)
	_text(Vector2(d.x * 0.94 - fs * 7.5, d.y * 0.93), "BOTTOM RIGHT", fs, Color.WHITE, false)
	_text(Vector2(c.x, d.y * 0.2), _eye_name(eye), int(d.y * 0.12), Color(1, 0.95, 0.6))
	_text(Vector2(c.x, d.y * 0.32), "%s  |  %s" % [title, mode.describe()], int(d.y * 0.04))
	_text(Vector2(c.x, d.y * 0.38), subtitle, int(d.y * 0.032), Color(0.85, 0.85, 0.85))
	_text(c + Vector2(0, d.y * 0.12), _timecode(), int(d.y * 0.08))
	# Sweep bar: one pass every 4 s.
	var sx := fposmod(time / 4.0, 1.0) * d.x
	draw_rect(Rect2(Vector2(sx - 4, d.y * 0.42), Vector2(8, d.y * 0.32)), Color(1, 1, 0.2))
	if eye >= 0:
		_depth_ring(c + Vector2(_eye_shift(eye, disparity), -d.y * 0.02), d.y * 0.1)
	draw_set_transform(Vector2.ZERO)


func _depth_ring(p: Vector2, radius: float) -> void:
	draw_arc(p, radius, 0.0, TAU, 64, Color(0.3, 1.0, 0.4), radius * 0.12)
	_text(p, "3D", int(radius * 0.6), Color(0.3, 1.0, 0.4))


## Equirectangular: the eye's rectangle spans span_deg of longitude (centred on straight ahead) and 180 degrees of
## latitude. Grid every 15 degrees, labelled directions on the horizon.
func _draw_equirect(r: Rect2, eye: int, span_deg: float) -> void:
	draw_rect(r, _eye_tint(eye))
	# Ground half darker, to tell up from down.
	draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5)),
			_eye_tint(eye).darkened(0.45))
	var ppd := Vector2(r.size.x / span_deg, r.size.y / 180.0)
	var to_px := func(lon: float, lat: float) -> Vector2:
		return r.position + Vector2((lon + span_deg * 0.5) * ppd.x, (90.0 - lat) * ppd.y)
	var lon := -span_deg * 0.5
	while lon <= span_deg * 0.5 + 0.01:
		var major := is_zero_approx(fmod(lon, 45.0))
		var w := 6.0 if is_zero_approx(lon) else (3.0 if major else 1.5)
		draw_line(to_px.call(lon, 90.0), to_px.call(lon, -90.0), Color(1, 1, 1, 0.6 if major else 0.3), w)
		lon += 15.0
	var lat := -75.0
	while lat <= 75.0:
		var w2 := 6.0 if is_zero_approx(lat) else 2.0
		draw_line(to_px.call(-span_deg * 0.5, lat), to_px.call(span_deg * 0.5, lat), Color(1, 1, 1, 0.45), w2)
		lat += 15.0
	var fs := int(ppd.y * 5.0)
	var labels := {0: "FRONT", 90: "RIGHT 90°", -90: "LEFT 90°", 45: "45°", -45: "-45°", 135: "135°", -135: "-135°",
			180: "BACK", -180: "BACK"}
	for l: int in labels:
		if absf(l) <= span_deg * 0.5:
			_text(to_px.call(clampf(l, -span_deg * 0.5 + 8.0, span_deg * 0.5 - 8.0), 5.0), labels[l], fs)
	_text(to_px.call(0.0, 62.0), "UP", fs)
	_text(to_px.call(0.0, -62.0), "DOWN", fs)
	for l2: float in [-60.0, 60.0]:
		if absf(l2) < span_deg * 0.5:
			_text(to_px.call(l2, 30.0), _eye_name(eye), int(fs * 1.4), Color(1, 0.95, 0.6))
	_text(to_px.call(0.0, 32.0), _eye_name(eye), int(fs * 2.2), Color(1, 0.95, 0.6))
	_text(to_px.call(0.0, 20.0), "%s  |  %s" % [title, mode.describe()], int(fs * 0.7))
	_text(to_px.call(0.0, -14.0), _timecode(), int(fs * 1.3))
	_text(to_px.call(0.0, -24.0), subtitle, int(fs * 0.6), Color(0.85, 0.85, 0.85))
	# A dot running along the horizon at 30 degrees per second.
	var run := fposmod(time * 30.0 + span_deg * 0.5, span_deg) - span_deg * 0.5
	draw_circle(to_px.call(run, 0.0), ppd.y * 2.0, Color(1, 1, 0.2))
	if eye >= 0:
		# One degree of crossed disparity.
		_depth_ring(to_px.call(0.0, 0.0) + Vector2(_eye_shift(eye, ppd.x), 0), ppd.y * 7.0)


## Equidistant fisheye: image circle inscribed in the eye's rectangle, radius = half the field of view. Rings every
## 30 degrees off axis, spokes every 30 degrees around.
func _draw_fisheye(r: Rect2, eye: int) -> void:
	var c := r.get_center()
	var radius := minf(r.size.x, r.size.y) * 0.5
	var half_fov := mode.fisheye_fov * 0.5
	draw_circle(c, radius, _eye_tint(eye))
	draw_circle(c + Vector2(0, radius * 0.5), radius * 0.5, _eye_tint(eye).darkened(0.3))
	var theta := 30.0
	while theta < half_fov + 0.01:
		draw_arc(c, radius * theta / half_fov, 0.0, TAU, 96, Color(1, 1, 1, 0.5), 6.0 if is_equal_approx(theta, 90.0) else 2.5)
		theta += 30.0
	draw_arc(c, radius - 2.0, 0.0, TAU, 128, Color.WHITE, 4.0)
	for i in 12:
		var a := i * TAU / 12.0
		draw_line(c, c + Vector2(cos(a), sin(a)) * radius, Color(1, 1, 1, 0.3), 2.0)
	var fs := int(radius * 0.07)
	var ring60 := radius * 60.0 / half_fov
	_text(c + Vector2(0, -ring60), "UP", fs)
	_text(c + Vector2(0, ring60), "DOWN", fs)
	_text(c + Vector2(ring60, 0), "RIGHT", fs)
	_text(c + Vector2(-ring60, 0), "LEFT", fs)
	_text(c + Vector2(0, -radius * 0.32), _eye_name(eye), int(fs * 1.6), Color(1, 0.95, 0.6))
	_text(c + Vector2(0, -radius * 0.2), "%s  |  %s" % [title, mode.describe()], int(fs * 0.6))
	_text(c + Vector2(0, radius * 0.25), _timecode(), int(fs * 1.1))
	var a2 := time * TAU / 8.0
	draw_circle(c + Vector2(cos(a2), sin(a2)) * radius * 45.0 / half_fov, radius * 0.025, Color(1, 1, 0.2))
	if eye >= 0:
		_depth_ring(c + Vector2(_eye_shift(eye, radius / half_fov), 0), radius * 0.1)


## Dual fisheye 360 (a 360 camera's raw frame): the front lens's circle on the left, the back lens's on the right, each
## filling its half, equidistant at the generic profile's field of view (scripts/play/dual_fisheye.gd). Rings every 30
## degrees off each lens's axis and the 90 degree ring (the seam) bold. The labels say where each part of a circle
## shows: the back lens looks the other way, so its picture's left is the viewer's right. A rainbow band runs round
## the horizon, its hue following the direction (green straight ahead): across both seams it must continue.
func _draw_dual_fisheye(r: Rect2) -> void:
	var half_fov: float = DualFisheye.DEFAULTS["generic"]["front"]["fov"] * 0.5
	var radius := minf(r.size.x * 0.5, r.size.y) * 0.5
	for lens in 2:
		var c := r.position + Vector2(r.size.x * (0.25 + 0.5 * lens), r.size.y * 0.5)
		var tint := TINT_LEFT if lens == 0 else TINT_RIGHT
		draw_circle(c, radius, tint)
		# The ground (below the horizon) a little darker.
		draw_circle(c + Vector2(0, radius * 0.5), radius * 0.5, tint.darkened(0.3))
		var theta := 30.0
		while theta < half_fov + 0.01:
			draw_arc(c, radius * theta / half_fov, 0.0, TAU, 96, Color(1, 1, 1, 0.5),
					6.0 if is_equal_approx(theta, 90.0) else 2.5)
			theta += 30.0
		draw_arc(c, radius - 2.0, 0.0, TAU, 128, Color.WHITE, 4.0)
		for i in 12:
			var a := i * TAU / 12.0
			draw_line(c, c + Vector2(cos(a), sin(a)) * radius, Color(1, 1, 1, 0.3), 2.0)
		# The horizon band: world longitude from -180 (behind, on the left) to 180, as colours. For the front lens
		# image x grows with the longitude; for the back lens it falls (mirrored).
		var steps := 72
		for i in steps:
			var lon0 := -180.0 + 360.0 * i / steps
			var lon1 := lon0 + 360.0 / steps
			var mid := (lon0 + lon1) * 0.5
			var col := Color.from_hsv(fposmod(0.33 - mid / 360.0, 1.0), 0.9, 1.0)
			var seg: Array[Vector2] = []
			for lon in [lon0, lon1]:
				# Off-axis angle and the side, on the horizon: front lens axis at longitude 0, back at 180.
				var off: float = absf(lon) if lens == 0 else 180.0 - absf(lon)
				if off > half_fov:
					seg.clear()
					break
				var side := signf(lon) if lens == 0 else -signf(lon)
				seg.append(c + Vector2(side * radius * off / half_fov, 0))
			if seg.size() == 2:
				draw_line(seg[0], seg[1], col, radius * 0.03)
		var fs := int(radius * 0.07)
		var ring60 := radius * 60.0 / half_fov
		_text(c + Vector2(0, -ring60), "UP", fs)
		_text(c + Vector2(0, ring60), "DOWN", fs)
		_text(c + Vector2(ring60, -fs * 1.2), "LOOK RIGHT" if lens == 0 else "LOOK LEFT", fs)
		_text(c + Vector2(-ring60, -fs * 1.2), "LOOK LEFT" if lens == 0 else "LOOK RIGHT", fs)
		_text(c + Vector2(0, -radius * 0.32), "FRONT LENS" if lens == 0 else "BACK LENS", int(fs * 1.6),
				Color(1, 0.95, 0.6))
		if lens == 0:
			_text(c + Vector2(0, -radius * 0.2), "%s  |  %s" % [title, mode.describe()], int(fs * 0.6))
			_text(c + Vector2(0, radius * 0.25), _timecode(), int(fs * 1.1))
