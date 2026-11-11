## scripts/pointing/pointing.gd: the nearest surface has the hand, a holder keeps it, a claimant comes first, and the
## selection stays where it was put.
## godot --headless --xr-mode off --path app --script res://tests/test_pointing.gd
extends SceneTree

const Pointing := preload("res://scripts/pointing/pointing.gd")

class Hand extends RefCounted:
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD
	func get_ray_origin() -> Vector3: return origin
	func get_ray_direction() -> Vector3: return direction

## A square 1 m wide facing +Z at `z` on the -Z axis.
class Wall extends RefCounted:
	var z := -1.0
	var x := 0.0
	var held := {}
	var asked := 0
	func point_hit(_hand: Object, origin: Vector3, direction: Vector3) -> Dictionary:
		asked += 1
		if direction.z >= 0.0:
			return {}
		var t := (z - origin.z) / direction.z
		var p := origin + direction * t
		if t <= 0.0 or absf(p.x - x) > 0.5 or absf(p.y) > 0.5:
			return {}
		return {"distance": t * direction.length(), "point": p}
	func point_holds(hand: Object) -> bool:
		return held.has(hand)

var _checks := 0
var _failures := 0


func _init() -> void:
	var p := Pointing.new()
	var hand := Hand.new()
	var near := Wall.new()
	near.z = -1.0
	var far := Wall.new()
	far.z = -3.0
	p.add(far)
	p.add(near)
	_check("the nearest surface has the hand, whatever the order they were added in", p.owner_of(hand) == near)
	_check("its own hit, with the distance", is_equal_approx(float(p.hit(near, hand).get("distance", 0)), 1.0))
	_check("the one behind gets nothing", p.hit(far, hand).is_empty())
	var asked := near.asked
	p.owner_of(hand)
	p.hit(near, hand)
	_check("one answer a frame: no second ray", near.asked == asked)
	near.x = 5.0
	_check("the answer holds within the frame", p.owner_of(hand) == near)
	p.refresh()
	_check("refresh: the surface behind has the hand once the near one is aside", p.owner_of(hand) == far)
	near.x = 0.0
	far.held[hand] = true
	p.refresh()
	_check("a surface that holds the hand keeps it, in front of a nearer one", p.owner_of(hand) == far
			and is_equal_approx(float(p.hit(far, hand).get("distance", 0)), 3.0))
	hand.direction = Vector3.UP
	p.refresh()
	_check("held and off every surface: held, with no place", p.owner_of(hand) == far and p.hit(far, hand) == {"held": true})
	far.held.clear()
	p.refresh()
	_check("pointing at nothing: nobody has the hand", p.owner_of(hand) == null and not p.claimed(hand))
	hand.direction = Vector3.FORWARD
	var other := Hand.new()
	other.direction = Vector3.UP
	p.refresh()
	_check("each hand has its own answer", p.owner_of(hand) == near and p.owner_of(other) == null)
	var claims := [false]
	p.add_claimant(func(h: Object) -> bool: return claims[0] and h == hand)
	claims[0] = true
	p.refresh()
	_check("a claimant takes the hand before any surface", p.owner_of(hand) == null and p.claimed(hand)
			and p.hit(near, hand).is_empty())
	near.held[hand] = true
	p.refresh()
	_check("but not from a surface that holds it", p.owner_of(hand) == near and not p.claimed(hand))
	near.held.clear()
	claims[0] = false
	p.remove(near)
	_check("a surface that leaves gives the hand up", p.owner_of(hand) == far)

	var seen: Array = []
	p.selection_changed.connect(func(s: Object) -> void: seen.append(s))
	p.select(far)
	p.select(far)
	_check("selecting says so once", p.selected == far and seen == [far])
	hand.direction = Vector3.UP
	p.refresh()
	p.owner_of(hand)
	_check("pointing elsewhere leaves the selection", p.selected == far and seen.size() == 1)
	p.remove(far)
	_check("the selected surface leaving clears the selection", p.selected == null and seen == [far, null])

	# Without the registry (a test's stand-in for the app): a part answers for itself.
	hand.direction = Vector3.FORWARD
	_check("hit_for without a registry is the part's own hit", is_equal_approx(float(
			Pointing.hit_for(null, near, hand).get("distance", 0)), 1.0))
	p.free()
	print("test_pointing: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(0 if _failures == 0 else 1)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
