extends RefCounted

## Where the panel is (docs/ui-design.md, "Revision 2: a front panel"). Pure functions and two small state machines,
## no nodes, so tests/test_pane.gd can drive them with made-up poses and button timings.
##
## Placement: on opening, DISTANCE ahead of the eyes along the line of sight, at eye height, facing the head, and level:
## its top edge stays horizontal (world up) whatever the head's roll (the user, 2026-10-31: "it should always be
## level"). Only when the head looks nearly straight up or down does world up stop defining level; then the head's own
## up is used, so lying back and looking at the ceiling puts the panel overhead, the right way up for the face. Then it
## stays where it is in the world ([pane] world_locked, the default). With world_locked off it follows the head
## lazily: nothing while the panel is near the line of sight, a smooth catch-up once the head has turned
## FOLLOW_START away from it.
##
## The menu button: a short press toggles the panel; held RECENTRE_HOLD seconds while it is open, it recentres the panel
## in front of the head instead (MenuPress below). All numbers are to be tuned in the headset.

## Default distance from the eyes ([pane] distance) and its limits.
## From the headset (2026-10-31): 0.9 m was unreadable; 0.6 m with [pane] scale 1.4 was better, "maybe a little
## bigger", so 0.6 m and scale 1.6 (in ui_layer.gd) are the defaults.
const DISTANCE := 0.6
const MIN_DISTANCE := 0.4
const MAX_DISTANCE := 3.0
## Default hold time for the recentre ([pane] recentre_hold).
const RECENTRE_HOLD := 0.6
## Past this much pitch (the sine of about 64°: nearly straight up or down), the panel takes the head's up.
const STEEP := 0.9
## Head follow (world_locked off): start catching up when the panel is this far off the line of sight, stop when it
## is this close; the catch-up's time constant.
const FOLLOW_START := deg_to_rad(25.0)
const FOLLOW_STOP := deg_to_rad(3.0)
const FOLLOW_SECONDS := 0.35


## The front pose: `distance` along the head's line of sight, facing the head (+Z toward the eyes).
static func front(head: Transform3D, distance := DISTANCE) -> Transform3D:
	var forward := -head.basis.z.normalized()
	var up := Vector3.UP if absf(forward.y) < STEEP else head.basis.y.normalized()
	return facing(head.origin + forward * distance, head.origin, up)


## A pose at pos whose +Z points at target.
static func facing(pos: Vector3, target: Vector3, up: Vector3) -> Transform3D:
	var dir := target - pos
	if dir.length() < 1e-4:
		return Transform3D(Basis(), pos)
	if absf(dir.normalized().dot(up.normalized())) > 0.999:
		up = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir, up, true), pos)


## The angle between the head's line of sight and the direction to the panel's centre.
static func off_axis(head: Transform3D, pose: Transform3D) -> float:
	return Follow.off_axis(head, pose)


## Head follow with a lazy catch-up, for [pane] world_locked = false.
class Follow:
	extends RefCounted

	var catching := false

	static func off_axis(head: Transform3D, pose: Transform3D) -> float:
		var to_panel := pose.origin - head.origin
		if to_panel.length() < 1e-4:
			return 0.0
		return (-head.basis.z).angle_to(to_panel)

	## One frame: the pose to show, given the pose shown now and the front pose for the head now (front()). Pressed:
	## the pointer holds a button on the panel (a slider drag), so the panel stays put.
	func step(pose: Transform3D, head: Transform3D, target: Transform3D, delta: float, pressed := false) -> Transform3D:
		var off := off_axis(head, pose)
		if not catching and off > FOLLOW_START and not pressed:
			catching = true
		if not catching:
			return pose
		var k := 1.0 - exp(-delta / FOLLOW_SECONDS)
		var out := pose.interpolate_with(target, k)
		if off_axis(head, out) < FOLLOW_STOP or pressed:
			catching = false
		return out


## The menu button's press, hold and release. press() answers what to do at once: "open" (the panel was closed: it
## opens in front of the head, which is the recentre too), "cancel" (another use took the press, such as seat picking)
## or "" (it was open: wait). step() answers "recentre" once when the button has been held `hold` seconds; release()
## answers "close" for a short press on an open panel, else "".
class MenuPress:
	extends RefCounted

	var hold := RECENTRE_HOLD
	var held := -1.0
	var hand: Object
	var _waiting := false

	func press(p_hand: Object, open: bool, cancel := false) -> String:
		hand = p_hand
		held = 0.0
		_waiting = open and not cancel
		if cancel:
			return "cancel"
		return "" if open else "open"

	func step(delta: float) -> String:
		if held < 0.0:
			return ""
		held += delta
		if _waiting and held >= hold:
			_waiting = false
			return "recentre"
		return ""

	func release(p_hand: Object) -> String:
		if held < 0.0 or p_hand != hand:
			return ""
		held = -1.0
		if _waiting:
			_waiting = false
			return "close"
		return ""

	func is_held() -> bool:
		return held >= 0.0
