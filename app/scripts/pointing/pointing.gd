extends Node
## One answer to "what is this hand's laser on" (docs/dev/surfaces-design.md, step 1), and the selection. Named for
## pointing: "surfaces" already means the materials of a room here (scripts/assistant).
##
## Every part that can be pointed at is a provider: the menu, the floating keyboard, the PC windows, an agent's
## terminal, the objects of the room. A provider has
##   point_hit(hand, origin, direction) -> Dictionary   {} or what the ray meets, with "distance" in metres
##   point_holds(hand) -> bool                            it has this hand whatever it points at: a drag, a held key
## The hand belongs to the provider that holds it, else to the one whose hit is nearest. Each provider asks hit()
## for its own hand and gets its hit, or {} when another has the hand. Before this each part asked the others, in an
## order written by hand (the keyboard first, then objects, the menu, PC windows, the terminal), and a new part meant
## an exception in each of the old ones.
##
## A claimant is something that is not a surface yet and takes a hand whole, as before: the browser's stick pointer.
## It comes before every provider.
##
## The answer for a hand is worked out once a frame, at the first question. Providers must not change what
## point_hit() would say because of what hit() said in the same frame.

## The selected surface changed (null: none). The selection is where typing and voice go; it is explicit and it stays.
signal selection_changed(surface: Object)

var _providers: Array[Object] = []
var _claimants: Array[Callable] = []
var _frame := -1
## hand -> {"owner": Object or null, "hit": Dictionary, "claimed": bool}
var _answers := {}
var selected: Object


func add(provider: Object) -> void:
	if not _providers.has(provider):
		_providers.append(provider)
	refresh()


func remove(provider: Object) -> void:
	_providers.erase(provider)
	if selected == provider:
		select(null)
	refresh()


## Something that takes a hand whole and is not a surface yet: (hand) -> bool.
func add_claimant(claims: Callable) -> void:
	_claimants.append(claims)


## Forgets this frame's answers (a test that moves things within one frame; a provider that came or went).
func refresh() -> void:
	_answers.clear()


## The provider that has this hand now, or null (nothing, or a claimant).
func owner_of(hand: Object) -> Object:
	return _answer(hand)["owner"]


## A claimant has this hand.
func claimed(hand: Object) -> bool:
	return bool(_answer(hand)["claimed"])


## This provider's hit for the hand, when the hand is its own; else {}. A provider that holds the hand off every
## surface gets {"held": true}.
func hit(provider: Object, hand: Object) -> Dictionary:
	var a: Dictionary = _answer(hand)
	return a["hit"] if a["owner"] == provider else {}


## For a provider that may run without the registry (a test's stand-in for the app): the registry's answer, else
## the provider's own.
static func hit_for(app: Object, provider: Object, hand: Object) -> Dictionary:
	var s: Variant = app.get("pointing") if app != null else null
	if s is Node and (s as Node).has_method("owner_of"):
		return (s as Node).call("hit", provider, hand)
	return provider.call("point_hit", hand, hand.call("get_ray_origin"), hand.call("get_ray_direction"))


func select(surface: Object) -> void:
	if surface == selected:
		return
	selected = surface
	selection_changed.emit(surface)


func _answer(hand: Object) -> Dictionary:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_answers.clear()
	if not _answers.has(hand):
		_answers[hand] = _resolve(hand)
	return _answers[hand]


func _resolve(hand: Object) -> Dictionary:
	_providers = _providers.filter(func(p: Object) -> bool: return is_instance_valid(p))
	var origin: Vector3 = hand.call("get_ray_origin")
	var direction: Vector3 = hand.call("get_ray_direction")
	# A hand that is held stays held: its own surface's hit if the ray is still on it, so a drag can read where.
	for p: Object in _providers:
		if bool(p.call("point_holds", hand)):
			var own: Dictionary = p.call("point_hit", hand, origin, direction)
			return {"owner": p, "hit": own if not own.is_empty() else {"held": true}, "claimed": false}
	for c: Callable in _claimants:
		if c.is_valid() and bool(c.call(hand)):
			return {"owner": null, "hit": {}, "claimed": true}
	var best: Object = null
	var best_hit := {}
	for p: Object in _providers:
		var h: Dictionary = p.call("point_hit", hand, origin, direction)
		if h.is_empty():
			continue
		if best == null or float(h["distance"]) < float(best_hit["distance"]):
			best = p
			best_hit = h
	return {"owner": best, "hit": best_hit, "claimed": false}
