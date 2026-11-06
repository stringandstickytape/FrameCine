extends RefCounted

## The stick pointer on a captured window (scripts/window_pointer.gd; docs/window-source.md, "Controller mapping"):
## while the viewer looks at the screen, the right stick moves a cursor over the page and the trigger clicks there.
## While they look away the cursor is not drawn, and that is the cue that the stick does its normal job (scroll and
## arrow keys). This is the state alone, with no nodes, so the tests can step it frame by frame.
##
## Pointer mode starts after ON_SECONDS of gaze on the screen (the screen and a MARGIN round it, as fractions of its
## size) and ends after OFF_SECONDS of gaze off it. While the stick is pushed or the trigger is held (a drag), it stays
## on wherever the gaze goes (the latch). When the cursor appears, and when the gaze rests more than JUMP_FRACTION of
## the screen's width from it for JUMP_DWELL seconds while the stick has been still for STICK_QUIET seconds, it jumps
## to where the viewer looks ([browser] pointer_follows_gaze, on by default); the stick then fine-tunes. The stick's
## speed has a curve: past the DEAD_ZONE, ((push - dead) / (1 - dead)) ^ CURVE of full speed, and full tilt crosses the
## window's width in CROSS_SECONDS. It fades in and out over FADE_SECONDS.
##
##   var c := StickCursor.new(); c.size = Vector2(1920, 1080)
##   c.step(delta, gaze_uv, stick, grip, held)   # gaze_uv: Vector2 (0..1 on the window, may lie outside) or null
##   c.mode, c.pos (window pixels), c.alpha, c.shown()

const ON_SECONDS := 0.1
const OFF_SECONDS := 0.4
const MARGIN := 0.05
const JUMP_FRACTION := 0.1
const JUMP_DWELL := 0.15
const STICK_QUIET := 0.6
## The same dead zone as the app's other stick handling (window_pointer.gd's scroll, object_grab.gd, ui_layer.gd).
const DEAD_ZONE := 0.2
const CURVE := 2.0
const CROSS_SECONDS := 1.0
const FADE_SECONDS := 0.1
## How much of the gaze is averaged for a jump (seconds): the eyes jitter by about half a degree.
const AVERAGE_SECONDS := 0.1

## The window's size in pixels.
var size := Vector2(1920, 1080)
## [browser] pointer_follows_gaze.
var follows_gaze := true
## Pointer mode: the stick moves the cursor, the trigger clicks.
var mode := false
## The cursor, in window pixels (kept while hidden: with follows_gaze off it comes back where it was).
var pos := Vector2(-1, -1)
## 0 hidden .. 1 shown.
var alpha := 0.0
## The cursor moved or jumped in the last step().
var moved := false
## The mode changed in the last step().
var mode_changed := false
## The last jump's cause: "appear", "gaze" or "" (tests, the read command).
var last_jump := ""
var _on_time := 0.0
var _off_time := 0.0
var _far_time := 0.0
var _quiet := STICK_QUIET
## [seconds ago, pixel] of the recent gaze on the window, for the average.
var _recent: Array = []
var _far: Array = []


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


static func _mean(points: Array) -> Vector2:
	var s := Vector2.ZERO
	for p: Vector2 in points:
		s += p
	return s / maxf(points.size(), 1.0)


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
	last_jump = ""
	var looking := on_screen(gaze_uv)
	var push := stick.length()
	var pushed := push > DEAD_ZONE
	var gaze_px := _pixel(gaze_uv) if looking else Vector2(-1, -1)
	_age(_recent, delta)
	if looking:
		_recent.append([0.0, gaze_px])
	if not mode:
		_on_time = _on_time + delta if looking else 0.0
		if _on_time >= ON_SECONDS - 0.0001:
			mode = true
			mode_changed = true
			_off_time = 0.0
			_far_time = 0.0
			_far.clear()
			_quiet = STICK_QUIET
			if follows_gaze and not _recent.is_empty():
				_jump(_mean(_recent.map(func(r: Array) -> Vector2: return r[1])), "appear")
			elif pos.x < 0.0:
				_jump(size * 0.5, "appear")
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
		if pushed:
			_quiet = 0.0
			_far_time = 0.0
			_far.clear()
		else:
			_quiet += delta
		_follow(delta, looking, gaze_px, pushed or held)
	var target := 1.0 if mode else 0.0
	alpha = move_toward(alpha, target, delta / FADE_SECONDS)


## Jump to the gaze when it rests far from the cursor (see the header).
func _follow(delta: float, looking: bool, gaze_px: Vector2, busy: bool) -> void:
	if not follows_gaze or not looking or busy or _quiet < STICK_QUIET:
		_far_time = 0.0
		_far.clear()
		return
	if gaze_px.distance_to(pos) <= JUMP_FRACTION * size.x:
		_far_time = 0.0
		_far.clear()
		return
	_far_time += delta
	_far.append(gaze_px)
	if _far_time >= JUMP_DWELL - 0.0001:
		_jump(_mean(_far), "gaze")
		_far_time = 0.0
		_far.clear()


func _pin(delta: float, at: Vector2) -> void:
	moved = false
	mode_changed = not mode
	last_jump = ""
	mode = true
	_off_time = 0.0
	_on_time = 0.0
	_far_time = 0.0
	_far.clear()
	var to := at.clamp(Vector2.ZERO, size - Vector2.ONE)
	if to != pos:
		pos = to
		moved = true
	alpha = move_toward(alpha, 1.0, delta / FADE_SECONDS)


func _jump(to: Vector2, why: String) -> void:
	pos = to.clamp(Vector2.ZERO, size - Vector2.ONE)
	moved = true
	last_jump = why


func _age(list: Array, delta: float) -> void:
	for r: Array in list:
		r[0] = float(r[0]) + delta
	while not list.is_empty() and float(list[0][0]) > AVERAGE_SECONDS:
		list.pop_front()


## Hides at once (the menu opened, the window went): the mode ends, the cursor keeps its place.
func reset() -> void:
	mode = false
	alpha = 0.0
	_on_time = 0.0
	_off_time = 0.0
	_far_time = 0.0
	_far.clear()
	_recent.clear()
	_quiet = STICK_QUIET
