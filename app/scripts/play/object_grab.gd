extends Node

## Picking objects up with the controllers (docs/physics.md, "Controls"; object physics:
## scripts/play/object_physics.gd). Either controller, and one is enough:
##   point at an object      the laser shows to it (it fades after LASER_LINGER seconds of a still controller, so a
##                           hand resting in the lap with an object ahead doesn't light a laser through the film)
##   grip (hold)             picks it up at the laser's end; with the controller in (or within HAND_REACH of) an
##                           object, picks it up in the hand instead
##   stick, while holding    up / down: further / nearer (on the laser); left / right: turns it about up, as Place
##   let go of the grip      drops it; let go while the controller moves and it is thrown at the speed of the laser's
##                           tip (or the hand), smoothed over the last THROW_WINDOW seconds
##   B (or Y), while holding back where it was picked up
##   trigger, while holding  nothing (it doesn't pause the film or bring the zoom lens)
## A wall object (a clock, a picture, a shelf) stays on its wall while held, until it is pulled off it.
## The grip still does what it did elsewhere: a quick squeeze is a right click on a captured window, a held one the
## zoom lens's modifier in 180 / 360; the grab takes the grip only when the controller points at an object or is in
## one. Not while Place, seat picking or marking a window has the laser, nor on the hand a captured window has, nor
## where the menu's laser is.
##
##   on_grip(hand, pressed), on_trigger(hand, pressed), on_stick(hand, stick, delta), on_back(hand) -> bool (used)
##   holding(hand) -> the name held or "", aimed(hand) -> the name the laser shows or "", owns_laser(hand)
##   signal changed     a hold began or ended (the controller legends change)

const XRHand := preload("res://scripts/xr/xr_hand.gd")

signal changed

## How far the laser reaches, and the hand's reach (metres, from the controller's tip to an object's shape).
const REACH := 10.0
const HAND_REACH := 0.08
## The stick: further / nearer (e-folds a second at full stick), within DISTANCE_RANGE; turns TURN_RATE degrees a
## second; nothing under STICK_DEAD.
const NEAR_FAR_RATE := 1.2
const DISTANCE_RANGE := Vector2(0.3, 10.0)
const TURN_RATE := 120.0
const STICK_DEAD := 0.2
## The throw: the tip's speed over this window (seconds), no faster than THROW_MAX (m/s); the controller's spin times
## SPIN_SHARE.
const THROW_WINDOW := 0.075
const THROW_MAX := 25.0
const SPIN_SHARE := 0.3
## The laser to an aimed object: shown while the controller turns, for this long after it stops; "turns": more than
## LASER_WAKE_DEG from where it pointed.
const LASER_LINGER := 2.0
const LASER_WAKE_DEG := 3.0

var main: Node3D
## hand -> {name, by ("laser" | "hand"), distance, offset (laser: the object from the grab point, world; hand: the
## object in the hand's frame), basis (laser: the object's rotation when picked up), turn, history: [[t, point]],
## spins: [[t, angular velocity]]}
var _holds := {}
## hand -> {name, distance, dir (where it pointed when the laser woke), shown_until}
var _aims := {}


func _physics() -> Node:
	return main.features.get("physics") if main.get("features") != null else null


func holding(hand: Node) -> String:
	return str(_holds[hand]["name"]) if _holds.has(hand) else ""


func aimed(hand: Node) -> String:
	var a: Dictionary = _aims.get(hand, {})
	return str(a.get("name", "")) if _laser_shown(a) else ""


## This hand's laser is the grab's this frame: holding on the laser, or aimed at an object with the laser awake.
func owns_laser(hand: Node) -> bool:
	if _holds.has(hand):
		return str(_holds[hand]["by"]) == "laser"
	return aimed(hand) != ""


## The laser is free for the grab: nothing else (Place, seat picking, marking a window, the menu, a captured window)
## has it on this hand.
func _free(hand: Node) -> bool:
	var ph: Node = _physics()
	if ph == null or not ph.available():
		return false
	if main.window_pointer != null and main.window_pointer_owns(hand as XRHand):
		return false
	var ui: Node = main.ui
	if ui != null and ui.has_method("laser_in_use") and ui.laser_in_use(hand):
		return false
	return true


# --- Input ------------------------------------------------------------------------------------------------------

func on_grip(hand: Node, pressed: bool) -> bool:
	if not pressed:
		if not _holds.has(hand):
			return false
		_let_go(hand)
		return true
	if _holds.has(hand) or not _free(hand):
		return false
	var ph: Node = _physics()
	var tip: Vector3 = hand.get_ray_origin()
	var name: String = ph.near(tip, HAND_REACH)
	if name != "" and _held_elsewhere(name):
		name = ""
	if name != "":
		return _begin(hand, name, "hand", 0.0, tip)
	var a: Dictionary = _aims.get(hand, {})
	if a.is_empty():
		_update_aim(hand)
		a = _aims.get(hand, {})
	if a.is_empty() or _held_elsewhere(str(a["name"])):
		return false
	return _begin(hand, str(a["name"]), "laser", float(a["distance"]), a["point"])


func _held_elsewhere(name: String) -> bool:
	for h: Node in _holds:
		if _holds[h]["name"] == name:
			return true
	return false


func _begin(hand: Node, name: String, by: String, distance: float, point: Vector3) -> bool:
	var ph: Node = _physics()
	if not ph.pick_up(name):
		return false
	var obj: Transform3D = ph.body_transform(name)
	var hold := {"name": name, "by": by, "distance": maxf(distance, DISTANCE_RANGE.x), "turn": 0.0, "history": [],
			"spins": [], "basis": obj.basis, "last_basis": (hand as Node3D).global_basis}
	if by == "laser":
		hold["offset"] = obj.origin - point
	else:
		hold["offset"] = (hand as Node3D).global_transform.affine_inverse() * obj
	_holds[hand] = hold
	if hand.has_method("pulse"):
		hand.pulse()
	changed.emit()
	return true


func _let_go(hand: Node) -> void:
	var hold: Dictionary = _holds[hand]
	_holds.erase(hand)
	var ph: Node = _physics()
	if ph != null:
		ph.let_go(str(hold["name"]), throw_velocity(hold["history"]), throw_spin(hold["spins"]) * SPIN_SHARE)
	changed.emit()


## The trigger while holding does nothing: no pause, no zoom lens.
func on_trigger(hand: Node, _pressed: bool) -> bool:
	return _holds.has(hand)


## B (or Y) while holding: back where it was picked up.
func on_back(hand: Node) -> bool:
	if not _holds.has(hand):
		return false
	var name := str(_holds[hand]["name"])
	_holds.erase(hand)
	var ph: Node = _physics()
	if ph != null:
		ph.cancel(name)
	changed.emit()
	return true


## The stick while holding: up / down further and nearer on the laser, left / right turns it.
func on_stick(hand: Node, stick: Vector2, delta: float) -> bool:
	if not _holds.has(hand):
		return false
	var hold: Dictionary = _holds[hand]
	if absf(stick.x) > STICK_DEAD:
		hold["turn"] = wrapf(float(hold["turn"]) - stick.x * deg_to_rad(TURN_RATE) * delta, -PI, PI)
	if absf(stick.y) > STICK_DEAD and str(hold["by"]) == "laser":
		hold["distance"] = clampf(float(hold["distance"]) * exp(stick.y * NEAR_FAR_RATE * delta), DISTANCE_RANGE.x,
				DISTANCE_RANGE.y)
	return true


# --- Each frame -------------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var ph: Node = _physics()
	for hand: Node in _holds.keys():
		# Gone, or put down by something else (Tidy up settles what is held): the hold ends.
		if not is_instance_valid(hand) or ph == null or not ph.available() \
				or not (str(_holds[hand]["name"]) in ph.names()) or not ph.is_held(str(_holds[hand]["name"])):
			_holds.erase(hand)
			changed.emit()
	for hand: XRHand in main.hands:
		if _holds.has(hand):
			_hold(hand)
			_aims.erase(hand)
		elif main.use_xr and hand.get_is_active() and _free(hand):
			_update_aim(hand)
		else:
			_aims.erase(hand)
		# The laser: on while it is the grab's; off once when it stops being (unless the menu uses it now).
		var want := owns_laser(hand)
		if want and not _holds.has(hand):
			hand.set_laser(true, float(_aims[hand]["distance"]), true)
		elif not want and bool(_lit.get(hand, false)):
			var ui: Node = main.ui
			if ui == null or not ui.has_method("laser_in_use") or not ui.laser_in_use(hand):
				hand.set_laser(false)
		_lit[hand] = want


## hand -> the grab lit its laser last frame.
var _lit := {}


## Where the held object goes this frame: the laser's tip (plus where on it it was taken) or the hand; the throw's
## history; the laser to it.
func _hold(hand: XRHand) -> void:
	var hold: Dictionary = _holds[hand]
	var ph: Node = _physics()
	var turn := Basis(Vector3.UP, float(hold["turn"]))
	var target: Transform3D
	if str(hold["by"]) == "laser":
		var tip: Vector3 = hand.get_ray_origin() + hand.get_ray_direction() * float(hold["distance"])
		target = Transform3D(turn * (hold["basis"] as Basis), tip + turn * (hold["offset"] as Vector3))
		hand.set_laser(true, float(hold["distance"]), true)
	else:
		var in_hand: Transform3D = hand.global_transform * (hold["offset"] as Transform3D)
		target = Transform3D(turn * in_hand.basis, in_hand.origin)
	ph.hold_to(str(hold["name"]), target)
	var now := Time.get_ticks_usec() / 1000000.0
	var history: Array = hold["history"]
	history.append([now, target.origin])
	while history.size() > 2 and now - float(history[1][0]) > THROW_WINDOW:
		history.pop_front()
	# The controller's spin from its turn since the last frame.
	var spins: Array = hold["spins"]
	var b0: Basis = hold["last_basis"]
	var b1 := hand.global_basis
	var dt := now - float(history[-2][0]) if history.size() >= 2 else 0.0
	if dt > 0.0:
		var q := (b1.get_rotation_quaternion() * b0.get_rotation_quaternion().inverse()).normalized()
		if q.w < 0.0:
			q = -q
		var axis := Vector3(q.x, q.y, q.z)
		spins.append([now, axis.normalized() * 2.0 * acos(clampf(q.w, -1.0, 1.0)) / dt if axis.length() > 1e-6
				else Vector3.ZERO])
		while spins.size() > 1 and now - float(spins[0][0]) > THROW_WINDOW:
			spins.pop_front()
	hold["last_basis"] = b1


## The throw: the held point's velocity over the window ([[t, point]], oldest first), at most THROW_MAX.
static func throw_velocity(history: Array) -> Vector3:
	if history.size() < 2:
		return Vector3.ZERO
	var dt := float(history[-1][0]) - float(history[0][0])
	if dt <= 1e-4:
		return Vector3.ZERO
	return (((history[-1][1] as Vector3) - (history[0][1] as Vector3)) / dt).limit_length(THROW_MAX)


static func throw_spin(spins: Array) -> Vector3:
	if spins.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for s: Array in spins:
		sum += s[1] as Vector3
	return sum / spins.size()


## The object the hand's ray meets now (the laser wakes when it meets a new one or the controller turns).
func _update_aim(hand: Node) -> void:
	var ph: Node = _physics()
	var dir: Vector3 = hand.get_ray_direction()
	var hit: Dictionary = ph.aim(hand.get_ray_origin(), dir, REACH) if ph != null else {}
	if hit.is_empty():
		_aims.erase(hand)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var a: Dictionary = _aims.get(hand, {})
	if a.get("name", "") != hit["name"] or (a.get("dir", dir) as Vector3).angle_to(dir) > deg_to_rad(LASER_WAKE_DEG):
		a["dir"] = dir
		a["shown_until"] = now + LASER_LINGER
	a["name"] = hit["name"]
	a["distance"] = hit["distance"]
	a["point"] = hit["point"]
	_aims[hand] = a


func _laser_shown(a: Dictionary) -> bool:
	return not a.is_empty() and Time.get_ticks_msec() / 1000.0 < float(a.get("shown_until", 0.0))
