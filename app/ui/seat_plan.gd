extends Control

## The room's seats from above, with its screen, under Current in the Room tab (the user, 2026-11-08: an overhead
## plan in place of the Seat buttons). The screen across the top (the room turned so it faces down the plan), each
## seat a dot, the one in use filled in the accent, the room's own spot (Default seat) a diamond. Pointing at a seat
## shows its name; the trigger (a click) sits there, as the seat buttons did (seat_choice.go_to_seat()).
## What it shows comes from the app: main.features.seat (seats(), names(), seat), main.env (the screen's anchor and
## width). refresh() takes them again (the Room tab calls it when the room or the seat changes).

const PaneStyle := preload("res://ui/pane_style.gd")

## Pixels round the drawing; the dots' radius bounds.
const MARGIN := 14.0
const DOT_MIN := 3.0
const DOT_MAX := 9.0

var app: Node

## The plan in room metres, turned so the screen faces +y (down the plan): seats, the own spot, the screen's ends.
var _seats: PackedVector2Array = []
var _names: Array = []
var _spot := Vector2.ZERO
var _screen: PackedVector2Array = []
var _bounds := Rect2()
var _hover := -2
## The room and seat count refresh() last took, and the closest seats' spacing in metres.
var _key := ""
var _spacing := 1.0
## Drawn with: metres to pixels, the drawing's origin, the dots' radius.
var _scale := 1.0
var _offset := Vector2.ZERO
var _dot := 5.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 200)
	resized.connect(_layout)
	mouse_exited.connect(func() -> void:
		_hover = -2
		tooltip_text = ""
		queue_redraw())


## The seats and the screen again, from the room in use.
func refresh() -> void:
	var env0: Node = app.get("env") if app != null else null
	var key := "%s:%d" % [env0.get_instance_id() if env0 != null else 0, app.features.seat.seats().size() if app != null else 0]
	if key == _key:
		queue_redraw()
		return
	_key = key
	_seats.clear()
	_names = []
	_screen.clear()
	var env: Node = app.get("env") if app != null else null
	var seat: Node = app.features.seat if app != null else null
	if env == null or seat == null:
		queue_redraw()
		return
	var anchor: Transform3D = env.get_screen_anchor() if env.has_method("get_screen_anchor") else Transform3D()
	# Turned so the screen's picture faces down the plan.
	var f := anchor.basis.z
	var turn := -atan2(f.x, f.z)
	var to_plan := func(p: Vector3) -> Vector2:
		return Vector2(p.x, p.z).rotated(turn)
	for p: Vector3 in seat.seats():
		_seats.append(to_plan.call(p))
	_names = seat.names()
	_spot = to_plan.call(Vector3.ZERO)
	var w := float(env.get("default_screen_width")) if env.get("default_screen_width") != null else 3.0
	var across := anchor.basis.x * w * 0.5
	_screen.append(to_plan.call(anchor.origin - across))
	_screen.append(to_plan.call(anchor.origin + across))
	_bounds = Rect2(_spot, Vector2.ZERO)
	for p: Vector2 in _seats:
		_bounds = _bounds.expand(p)
	for p: Vector2 in _screen:
		_bounds = _bounds.expand(p)
	_bounds = _bounds.grow(0.4)
	_spacing = INF
	for i in mini(_seats.size(), 400):
		for j in range(i + 1, mini(_seats.size(), 400)):
			_spacing = minf(_spacing, _seats[i].distance_to(_seats[j]))
	if _spacing == INF:
		_spacing = 1.0
	_layout()


func _layout() -> void:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		queue_redraw()
		return
	# As tall as the room's shape asks at this width, within bounds.
	var avail_w := maxf(size.x - MARGIN * 2.0, 50.0)
	var want_h := clampf(avail_w * _bounds.size.y / _bounds.size.x + MARGIN * 2.0 + 18.0, 160.0, 420.0)
	if absf(custom_minimum_size.y - want_h) > 1.0:
		custom_minimum_size.y = want_h
	var avail := Vector2(avail_w, maxf(size.y - MARGIN * 2.0 - 18.0, 50.0))
	_scale = minf(avail.x / _bounds.size.x, avail.y / _bounds.size.y)
	var drawn := _bounds.size * _scale
	_offset = Vector2(MARGIN, MARGIN + 18.0) + (avail - drawn) * 0.5 - _bounds.position * _scale
	# The dots: about a third of the closest seats' spacing.
	_dot = clampf(_spacing * _scale * 0.36, DOT_MIN, DOT_MAX)
	queue_redraw()


func _px(p: Vector2) -> Vector2:
	return p * _scale + _offset


func _draw() -> void:
	var text := PaneStyle.color(&"text")
	var muted := PaneStyle.color(&"muted")
	var accent := PaneStyle.color(&"accent")
	var field := PaneStyle.color(&"field")
	draw_rect(Rect2(Vector2.ZERO, size), field)
	if _screen.size() < 2:
		return
	var font := get_theme_font(&"font", &"Label")
	var fs := maxi(get_theme_font_size(&"font_size", &"Label") - 4, 10)
	# The screen: a bright bar, its name over it.
	var a := _px(_screen[0])
	var b := _px(_screen[1])
	draw_line(a, b, text, 4.0, true)
	var mid := (a + b) * 0.5
	var label := tr("Screen")
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, mid + Vector2(-lw * 0.5, -8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
	var at := int(app.features.seat.seat) if app != null else -1
	for i in _seats.size():
		var p := _px(_seats[i])
		if i == at:
			draw_circle(p, _dot + 2.0, accent)
		elif i == _hover:
			draw_circle(p, _dot + 1.0, text)
		else:
			draw_circle(p, _dot, muted * Color(1, 1, 1, 0.75))
	# The room's own spot: a diamond, filled when in use.
	var s := _px(_spot)
	var r := maxf(_dot + 3.0, 7.0)
	var diamond := PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r), s + Vector2(-r, 0)])
	if at < 0:
		draw_colored_polygon(diamond, accent)
	else:
		diamond.append(diamond[0])
		draw_polyline(diamond, text if _hover == -1 else muted, 2.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _hit((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			tooltip_text = _name_of(h)
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var h := _hit(mb.position)
			if h != -2 and app != null:
				app.features.seat.go_to_seat(h)
				accept_event()


## The seat under a point (its index), -1 for the room's own spot, -2 for none.
func _hit(pos: Vector2) -> int:
	var best := -2
	var best_d := maxf(_dot * 1.8, 10.0)
	for i in _seats.size():
		var d := pos.distance_to(_px(_seats[i]))
		if d < best_d:
			best_d = d
			best = i
	if pos.distance_to(_px(_spot)) < maxf(best_d, 12.0) and (best == -2 or pos.distance_to(_px(_spot)) < best_d):
		best = -1
	return best


func _name_of(i: int) -> String:
	if i == -1:
		return tr("Default seat")
	if i >= 0 and i < _names.size() and str(_names[i]) != "":
		return str(_names[i])
	return tr("Seat %d") % (i + 1) if i >= 0 else ""


## For tests: where seat `i` (-1: the own spot) is drawn, in the plan's pixels.
func point_of(i: int) -> Vector2:
	return _px(_spot) if i < 0 else _px(_seats[i])
