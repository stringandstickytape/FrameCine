extends "res://scripts/video/test_card.gd"

## Calibration cards for the test lab (idea #48; docs/test-lab.md), drawn like the test card (each eye in its place of
## the frame) by LabVideoSource:
##   alignment     per-eye grids and nonius lines: the two eyes' half-lines meet in one straight cross when the
##                 pictures line up; a step shows the misalignment in pixels against the tick scale.
##   convergence   rings at crossed and uncrossed disparities from near to far: each should fuse into one ring. Far
##                 rings that stay double mean the eyes are asked to diverge (the screen or IPD is off).
##   judder        a bar and a frame counter moving at the content rate (24, 30 or 60 fps): the bar should glide
##                 evenly; the row of cells lights one per content frame, so a repeated or dropped frame shows as a
##                 cell held twice or skipped.
##   av_sync       A/V latency (idea #24): the whole card flashes white for two content frames at each whole second,
##                 when the source's audio track beeps (LabVideoSource.beep_stream()); move the A/V offset until the
##                 flash and the beep land together.
##   zoneplate, starfield   sharpness: a zone plate and single-pixel stars, pixel-exact over the whole frame
##                 (shaders/lab_pattern.gdshader), drawn once: how the picture holds up shrunk or stretched.

## The card: "alignment", "convergence", "judder", "av_sync", "zoneplate" or "starfield".
var card_id := "alignment"
## Content frame rate (judder).
var fps := 24.0
## The content frame index (judder), set by the source.
var frame_index := 0

const DISPARITIES: Array[float] = [-64.0, -32.0, -16.0, 0.0, 16.0, 32.0, 64.0]
const PATTERN_SHADER := preload("res://shaders/lab_pattern.gdshader")
const PATTERNS := {"zoneplate": 0, "starfield": 1}
const LEFT_LINE := Color(1.0, 0.45, 0.35)
const RIGHT_LINE := Color(0.35, 0.85, 1.0)


func _ready() -> void:
	super()
	if PATTERNS.has(card_id):
		# The whole frame, pixel for pixel, from the shader (the card draws nothing over it).
		var rect := ColorRect.new()
		rect.name = "Pattern"
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = PATTERN_SHADER
		mat.set_shader_parameter("px_size", size)
		mat.set_shader_parameter("kind", PATTERNS[card_id])
		rect.material = mat
		add_child(rect)


func _draw_eye(r: Rect2, eye: int) -> void:
	if PATTERNS.has(card_id):
		return
	match card_id:
		"alignment":
			_draw_alignment(r, eye)
		"convergence":
			_draw_convergence(r, eye)
		"judder":
			_draw_judder(r)
		"av_sync":
			_draw_av_sync(r)
		_:
			super(r, eye)


func _line_color(eye: int) -> Color:
	return LEFT_LINE if eye <= 0 else RIGHT_LINE


func _draw_alignment(r: Rect2, eye: int) -> void:
	draw_set_transform(r.position)
	var d := r.size
	var c := d * 0.5
	draw_rect(Rect2(Vector2.ZERO, d), Color(0.05, 0.05, 0.06))
	var col := _line_color(eye)
	# A fine grid in the eye's colour (they overlap in white where the eyes agree).
	# Offset by half a cell, so no grid line hides the nonius lines through the centre.
	var cell := d.y / 12.0
	var x := fmod(c.x + cell * 0.5, cell)
	while x < d.x:
		draw_line(Vector2(x, 0), Vector2(x, d.y), Color(col, 0.35), 1.5)
		x += cell
	var y := fmod(c.y + cell * 0.5, cell)
	while y < d.y:
		draw_line(Vector2(0, y), Vector2(d.x, y), Color(col, 0.35), 1.5)
		y += cell
	# Nonius lines: the left eye draws the upper half of the vertical line and the left half of the horizontal one,
	# the right eye the other halves. Fused, they form one cross when the pictures line up.
	var gap := d.y * 0.01
	if eye <= 0:
		draw_line(Vector2(c.x, d.y * 0.1), Vector2(c.x, c.y - gap), col, 3.0)
		draw_line(Vector2(d.x * 0.1, c.y), Vector2(c.x - gap, c.y), col, 3.0)
	else:
		draw_line(Vector2(c.x, c.y + gap), Vector2(c.x, d.y * 0.9), col, 3.0)
		draw_line(Vector2(c.x + gap, c.y), Vector2(d.x * 0.9, c.y), col, 3.0)
	# Tick scales beside each half-line, every 2 px of the eye's picture, longer every 10: read a step against them.
	for i in range(-20, 21):
		var tick := 18.0 if i % 5 == 0 else 8.0
		if eye <= 0:
			draw_line(Vector2(c.x + i * 2.0, d.y * 0.1 - tick), Vector2(c.x + i * 2.0, d.y * 0.1), col, 1.0)
			draw_line(Vector2(d.x * 0.1 - tick, c.y + i * 2.0), Vector2(d.x * 0.1, c.y + i * 2.0), col, 1.0)
		else:
			draw_line(Vector2(c.x + i * 2.0, d.y * 0.9), Vector2(c.x + i * 2.0, d.y * 0.9 + tick), col, 1.0)
			draw_line(Vector2(d.x * 0.9, c.y + i * 2.0), Vector2(d.x * 0.9 + tick, c.y + i * 2.0), col, 1.0)
	draw_rect(Rect2(Vector2(3, 3), d - Vector2(6, 6)), Color(col, 0.8), false, 4.0)
	var fs := int(d.y * 0.035)
	_text(Vector2(c.x, d.y * 0.04), "%s: ALIGNMENT" % _eye_name(eye), fs, col)
	_text(Vector2(c.x, d.y * 0.96), "The half-lines should meet in one straight cross. Ticks: 2 px, long 10 px.",
			int(fs * 0.7), Color(0.85, 0.85, 0.85))
	draw_set_transform(Vector2.ZERO)


func _draw_convergence(r: Rect2, eye: int) -> void:
	draw_set_transform(r.position)
	var d := r.size
	draw_rect(Rect2(Vector2.ZERO, d), Color(0.06, 0.06, 0.07))
	var col := _line_color(eye)
	var n := DISPARITIES.size()
	var spacing := d.x / (n + 1)
	var radius := minf(spacing * 0.32, d.y * 0.12)
	var fs := int(d.y * 0.035)
	for i in n:
		var disp: float = DISPARITIES[i]
		# Crossed (negative) disparity: the left eye's copy moves right; it floats in front of the screen.
		var shift := -_eye_shift(eye, disp) if eye >= 0 else 0.0
		var p := Vector2(spacing * (i + 1) + shift, d.y * 0.5)
		draw_arc(p, radius, 0.0, TAU, 64, Color.WHITE, 4.0)
		draw_circle(p, radius * 0.12, col)
		var label := "screen" if disp == 0.0 else ("near" if disp < 0.0 else "far")
		_text(Vector2(spacing * (i + 1), d.y * 0.5 + radius + fs * 1.4), "%+d px" % int(disp), fs, Color.WHITE)
		_text(Vector2(spacing * (i + 1), d.y * 0.5 + radius + fs * 2.8), label, int(fs * 0.8), Color(0.8, 0.8, 0.8))
	_text(Vector2(d.x * 0.5, d.y * 0.1), "%s: CONVERGENCE" % _eye_name(eye), fs, col)
	_text(Vector2(d.x * 0.5, d.y * 0.9), "Each ring should fuse into one. Far rings that stay double: check the IPD.",
			int(fs * 0.7), Color(0.85, 0.85, 0.85))
	draw_set_transform(Vector2.ZERO)


func _draw_av_sync(r: Rect2) -> void:
	draw_set_transform(r.position)
	var d := r.size
	var per_second := maxi(int(round(fps)), 1)
	var in_second := frame_index % per_second
	var flash := in_second < 2
	draw_rect(Rect2(Vector2.ZERO, d), Color.WHITE if flash else Color(0.1, 0.1, 0.11))
	# A sweep round the second, so the flash can be anticipated.
	var a := float(in_second) / per_second * TAU - PI * 0.5
	var c := Vector2(d.x * 0.5, d.y * 0.45)
	draw_arc(c, d.y * 0.22, 0.0, TAU, 64, Color(0.35, 0.35, 0.37), 3.0)
	draw_line(c, c + Vector2(cos(a), sin(a)) * d.y * 0.22, Color(1, 0.85, 0.3), 4.0)
	var fs := int(d.y * 0.05)
	var ink := Color(0.1, 0.1, 0.1) if flash else Color(1, 0.95, 0.6)
	_text(Vector2(d.x * 0.5, d.y * 0.08), "A/V SYNC", fs, ink)
	_text(Vector2(d.x * 0.5, d.y * 0.84), "second %d" % (frame_index / per_second), fs, ink)
	_text(Vector2(d.x * 0.5, d.y * 0.93), "Move the A/V offset until the flash and the beep land together.",
			int(fs * 0.6), ink)
	draw_set_transform(Vector2.ZERO)


func _draw_judder(r: Rect2) -> void:
	draw_set_transform(r.position)
	var d := r.size
	draw_rect(Rect2(Vector2.ZERO, d), Color(0.18, 0.18, 0.19))
	var t := frame_index / maxf(fps, 1.0)
	# The bar: one pass every 4 s, moved once per content frame.
	var bx := fposmod(t / 4.0, 1.0) * d.x
	draw_rect(Rect2(Vector2(bx - d.x * 0.006, d.y * 0.15), Vector2(d.x * 0.012, d.y * 0.45)), Color.WHITE)
	# A ball on a circle, one turn every 2 s.
	var a := fposmod(t / 2.0, 1.0) * TAU
	draw_circle(Vector2(d.x * 0.5, d.y * 0.38) + Vector2(cos(a), sin(a)) * d.y * 0.16, d.y * 0.03,
			Color(1, 0.85, 0.3))
	# One cell per content frame of the current second: a held or skipped cell is a repeated or dropped frame.
	var cells := int(fps)
	var cw := d.x * 0.9 / cells
	var lit := frame_index % cells
	for i in cells:
		var on := i == lit
		draw_rect(Rect2(Vector2(d.x * 0.05 + i * cw + 1, d.y * 0.68), Vector2(cw - 2, d.y * 0.06)),
				Color(1, 1, 1) if on else Color(0.3, 0.3, 0.32))
	var fs := int(d.y * 0.05)
	_text(Vector2(d.x * 0.5, d.y * 0.08), "JUDDER  %d fps" % int(fps), fs, Color(1, 0.95, 0.6))
	_text(Vector2(d.x * 0.5, d.y * 0.84), "frame %d" % frame_index, fs)
	_text(Vector2(d.x * 0.5, d.y * 0.93), "The bar should glide evenly; one cell lights per frame.", int(fs * 0.6),
			Color(0.85, 0.85, 0.85))
	draw_set_transform(Vector2.ZERO)
