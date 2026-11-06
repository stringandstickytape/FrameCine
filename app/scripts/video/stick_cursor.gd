extends RefCounted

## The stick pointer on a captured window (scripts/window_pointer.gd; docs/window-source.md, "Controller mapping"):
## while the viewer looks at the screen, the right stick moves a cursor over the page and the trigger clicks there.
## While they look away the cursor is not drawn, and that is the cue that the stick does its normal job (scroll and
## arrow keys). This is the state alone, with no nodes, so the tests can step it frame by frame.
##
## Pointer mode starts after ON_SECONDS of gaze on the screen (the screen and a MARGIN round it, as fractions of its
## size) and ends after OFF_SECONDS of gaze off it. While the stick is pushed or the trigger is held (a drag), it stays
## on wherever the gaze goes (the latch). The gaze only chooses the mode: the cursor never follows it (the user,
## 2026-11-06: "the mouse pointer was never meant to follow your gaze"). It starts in the window's middle and stays
## where the stick leaves it, hidden or shown. The stick's speed has a curve: past the DEAD_ZONE, ((push - dead) / (1 - dead)) ^ CURVE of full speed, and full tilt crosses the
## window's width in CROSS_SECONDS. It fades in and out over FADE_SECONDS.
##
##   var c := StickCursor.new(); c.size = Vector2(1920, 1080)
##   c.step(delta, gaze_uv, stick, grip, held)   # gaze_uv: Vector2 (0..1 on the window, may lie outside) or null
##   c.mode, c.pos (window pixels), c.alpha, c.shown()

const ON_SECONDS := 0.1
const OFF_SECONDS := 0.4
const MARGIN := 0.05
## The same dead zone as the app's other stick handling (window_pointer.gd's scroll, object_grab.gd, ui_layer.gd).
const DEAD_ZONE := 0.2
const CURVE := 2.0
const CROSS_SECONDS := 1.0
const FADE_SECONDS := 0.1

## The window's size in pixels.
var size := Vector2(1920, 1080)
## Pointer mode: the stick moves the cursor, the trigger clicks.
var mode := false
## The cursor, in window pixels (kept while hidden: it comes back where it was).
var pos := Vector2(-1, -1)
## 0 hidden .. 1 shown.
var alpha := 0.0
## The cursor moved in the last step().
var moved := false
## The mode changed in the last step().
var mode_changed := false
var _on_time := 0.0
var _off_time := 0.0


func shown() -> bool:
	return alpha > 0.0


## Whether a gaze point (window UV) counts as on the screen: the window and the margin round it.
static func on_screen(uv: Variant) -> bool:
	if not (uv is Vector2):
		return false
	var p: Vector2 = uv
	return p.x >= -MARGIN and p.x <= 1.0 + MARGIN and p.y >= -MARGIN and p.y <= 1.0 + MARGIN


## The stick's push after the dead zone, 0..1, with the curve.
static func speed_of(push: float) -> float:
	var t := clampf((push - DEAD_ZONE) / (1.0 - DEAD_ZONE), 0.0, 1.0)
	return pow(t, CURVE)


func _pixel(uv: Vector2) -> Vector2:
	return (uv.clamp(Vector2.ZERO, Vector2.ONE) * size).clamp(Vector2.ZERO, size - Vector2.ONE)


## One frame. gaze_uv: where the gaze meets the window's plane (0..1 inside the window; outside values are off it), or
## null when it misses or there is no gaze. stick: the right stick. grip: the squeeze is held (the stick scrolls then,
## and the cursor stays put). held: the trigger is held (a drag keeps the mode). pinned: a window pixel the cursor is
## put on and kept at, in pointer mode whatever the gaze (the laser, [browser] laser), or null.
func step(delta: float, gaze_uv: Variant, stick: Vector2, grip := false, held := false, pinned: Variant = null) -> void:
	if pinned is Vector2:
		_pin(delta, pinned)
		return
	moved = false
	mode_changed = false
	var looking := on_screen(gaze_uv)
	var push := stick.length()
	var pushed := push > DEAD_ZONE
	if not mode:
		_on_time = _on_time + delta if looking else 0.0
		if _on_time >= ON_SECONDS - 0.0001:
			mode = true
			mode_changed = true
			_off_time = 0.0
			# The first time only: the window's middle. After that, where the stick left it.
			if pos.x < 0.0:
				pos = (size * 0.5).clamp(Vector2.ZERO, size - Vector2.ONE)
				moved = true
	else:
		_off_time = 0.0 if looking or pushed or held else _off_time + delta
		if _off_time >= OFF_SECONDS - 0.0001:
			mode = false
			mode_changed = true
			_on_time = 0.0
	if mode:
		if pushed and not grip:
			var dir := stick / maxf(push, 0.0001)
			var step_px := size.x / CROSS_SECONDS * speed_of(minf(push, 1.0)) * delta
			# Stick up is up the page; window pixels grow downwards.
			var to := (pos + Vector2(dir.x, -dir.y) * step_px).clamp(Vector2.ZERO, size - Vector2.ONE)
			if to != pos:
				pos = to
				moved = true
	var target := 1.0 if mode else 0.0
	alpha = move_toward(alpha, target, delta / FADE_SECONDS)


func _pin(delta: float, at: Vector2) -> void:
	moved = false
	mode_changed = not mode
	mode = true
	_off_time = 0.0
	_on_time = 0.0
	var to := at.clamp(Vector2.ZERO, size - Vector2.ONE)
	if to != pos:
		pos = to
		moved = true
	alpha = move_toward(alpha, 1.0, delta / FADE_SECONDS)


## Hides at once (the menu opened, the window went): the mode ends, the cursor keeps its place.
func reset() -> void:
	mode = false
	alpha = 0.0
	_on_time = 0.0
	_off_time = 0.0
