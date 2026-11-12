extends Node

## The film screen as a surface (docs/dev/surfaces-design.md, step 5), while it is flat: it answers the pointing layer
## (scripts/pointing/pointing.gd) like a PC window's pane or the menu, and wears the same frame (ui/surface_frame.gd)
## while the windows' chrome is shown: a title bar with what is playing, and a side stack with Previous and Next (a
## browser or an Android app on the screen: Back). There is no Close: the screen is always there.
##
##   The trigger on the bar selects the screen and takes it: it follows the hand, in the room's terms (main.gd's
##   screen placement: the stick meanwhile makes it bigger or smaller, further or nearer), and the point taken stays
##   under the laser.
##   A captured window on the screen (the browser, an Android app, a terminal): the trigger on the picture selects
##   the screen and is the left button at the laser's pixel (scripts/window_pointer.gd). The laser is the pointer, and
##   where the viewer looks changes nothing.
##   A film's picture answers no ray at all, so no laser is drawn over a film: its bar is what selects it.
##
## A 180 or 360 picture is not a surface: it has no edge to wear a frame on.

const Pointing := preload("res://scripts/pointing/pointing.gd")
const SurfaceFrame := preload("res://ui/surface_frame.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")

## scripts/main.gd
var main: Node3D
var frame: SurfaceFrame
## What each hand's laser is on here: {"what": "frame", "part", ["id"], "distance"} or {"what": "screen", "uv",
## "distance", ["pixel": the window's]}.
var aims := {}
## Tests: hands count without an XR session.
var test_xr := false
var _lit := {}
var _drag: Object = null
var _stack := ""


func _ready() -> void:
	if main != null and main.get("pointing") is Pointing:
		main.pointing.add(self)


## The screen is flat and showing (a window on it counts before its first picture is drawn).
func shows() -> bool:
	return main.screen != null and (main.mode as VideoMode).projection == VideoMode.Proj.FLAT 			and (main.screen.is_shown() or window() != null)


## The captured window on the screen, with a picture; else null.
func window() -> WindowVideoSource:
	var src: WindowVideoSource = main.window_pointer.get_source()
	return src if src != null and src.has_frame() else null


## This hand's laser is the screen's: it is on it, or it has it by the bar.
func has_hand(hand: Object) -> bool:
	return aims.has(hand) or _drag == hand


func point_hit(_hand: Object, origin: Vector3, direction: Vector3) -> Dictionary:
	if frame == null or not shows():
		return {}
	var h: Dictionary = main.window_pointer.ray_to_uv(origin, direction)
	if h.is_empty():
		return {}
	var uv: Vector2 = h["uv"]
	var size: Vector2 = main.screen.get_flat_size()
	var part: Dictionary = frame.hit(Vector2((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y))
	if not part.is_empty():
		part["what"] = "frame"
		part["distance"] = h["distance"]
		return part
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return {}
	# A film's picture answers no ray: no laser is drawn over a film, and what is behind it can still be pointed at.
	var src := window()
	if src == null:
		return {}
	var px := Vector2(src.get_size())
	return {"what": "screen", "uv": uv, "distance": h["distance"],
			"pixel": (uv * px).clamp(Vector2.ZERO, px - Vector2.ONE)}


func point_holds(hand: Object) -> bool:
	return _drag == hand or bool(main.window_pointer.holds(hand))


func _process(_delta: float) -> void:
	step()


## One frame (tests call it).
func step() -> void:
	if main.screen == null:
		return
	if frame == null:
		frame = SurfaceFrame.new()
		frame.name = "Frame"
		frame.has_close = false
		main.screen.add_child(frame)
	var on := shows()
	if on:
		frame.set_content_size(main.screen.get_flat_size())
		frame.set_title(str(main.display_title()))
		_set_stack()
	var chrome: bool = on and main.pointing.ui_shown
	if frame.shown != chrome:
		frame.set_shown(chrome)
	frame.set_state(false, main.pointing.selected == main.screen)
	if _drag != null and (not on or not is_instance_valid(_drag)):
		_end_drag()
	var hover := ""
	for hand: Node in main.hands:
		var tracked: bool = (main.use_xr and hand.get_is_active()) or test_xr
		var h: Dictionary = main.pointing.hit(self, hand) if on and tracked else {}
		if h.is_empty() or h.has("held"):
			aims.erase(hand)
		else:
			aims[hand] = h
			if h["what"] == "frame":
				hover = str(h.get("id", h["part"]))
		var lit := has_hand(hand)
		if lit:
			hand.set_laser(true, float(h.get("distance", 3.0)), true)
		elif bool(_lit.get(hand, false)):
			hand.set_laser(false)
		_lit[hand] = lit
	frame.hover = "bar" if _drag != null else hover


## The side stack for what is on the screen: a window has Back, a film has Previous and Next.
func _set_stack() -> void:
	var src := window()
	var want := "none" if src != null and src.is_terminal() else ("window" if src != null else "film")
	if want == _stack:
		return
	_stack = want
	match want:
		"window":
			frame.set_buttons([{"id": "back", "text": tr("Back")}])
		"film":
			frame.set_buttons([{"id": "previous", "text": tr("Previous")}, {"id": "next", "text": tr("Next")}])
		_:
			frame.set_buttons([])


## The trigger on the screen or its frame. True when used.
func on_trigger(hand: Node, pressed: bool) -> bool:
	if not pressed:
		if _drag == hand:
			_end_drag()
			return true
		return bool(main.window_pointer.on_trigger(hand, false))
	var aim: Dictionary = aims.get(hand, {})
	if aim.is_empty():
		return false
	if aim["what"] == "frame":
		match str(aim["part"]):
			"bar":
				main.pointing.select(main.screen)
				if _drag == null:
					_drag = hand
					main.start_screen_drag(hand, float(aim["distance"]))
			"button":
				_press(str(aim.get("id", "")))
			_:
				return false
	else:
		main.pointing.select(main.screen)
		if aim.has("pixel"):
			main.window_pointer.click(hand, aim["pixel"])
	if hand.has_method("pulse"):
		hand.pulse()
	return true


func _end_drag() -> void:
	_drag = null
	main.end_screen_drag()


## A button of the side stack.
func _press(id: String) -> void:
	match id:
		"previous":
			main.previous_file()
		"next":
			main.next_file()
		"back":
			var src := window()
			if main.android_apps != null and main.android_apps.on_big_screen():
				main.android_apps.back()
			elif src != null:
				src.tap_key(KEY_BACK)
