## Keys shared by both hands. Modifiers are held, latched for one stroke, or locked; each stroke wraps real key
## events round its captured target. Windows do their own repeat; only menu fields get echo events from step().
extends RefCounted

const Layout := preload("res://keyboard/key_layout.gd")
const Router := preload("res://keyboard/keyboard_router.gd")
const REPEAT_DELAY := 0.5
const REPEAT_INTERVAL := 1.0 / 30.0
var router: Router
var keys := Layout.keys()
var caps := false
var num := true
var scroll := false
## Key index -> 1 (one-shot), 2 (locked). Physically held modifiers live in held too.
var modifiers := {}
var held := {}
var _held_outputs := {}


func is_modifier(index: int) -> bool:
	return int(keys[index].code) in Layout.MODIFIERS


func modifier_on(code: int) -> bool:
	for index: int in modifiers:
		if int(keys[index].code) == code:
			return true
	for stroke: Dictionary in held.values():
		if bool(stroke.modifier) and int(keys[int(stroke.index)].code) == code:
			return true
	return false


func lit(index: int) -> bool:
	var code := int(keys[index].code)
	return modifiers.has(index) or held.values().any(func(s: Dictionary) -> bool: return int(s.index) == index) \
			or (code == KEY_CAPSLOCK and caps) or (code == KEY_NUMLOCK and num) or (code == KEY_SCROLLLOCK and scroll)


func press(source: Variant, index: int, target: Variant = null, snapshot: Dictionary = {}) -> void:
	if held.has(source) or index < 0 or index >= keys.size():
		return
	if is_modifier(index):
		held[source] = {"index": index, "modifier": true, "used": false, "before": int(modifiers.get(index, 0))}
		return
	var destination: Dictionary = router.capture() if target == null else target
	var captured := snapshot if not snapshot.is_empty() else capture_modifiers()
	var mods: Array = (captured.mods as Array).duplicate()
	var k: Dictionary = keys[index]
	if not held.values().any(func(s: Dictionary) -> bool: return not bool(s.modifier) and int(s.index) == index):
		match int(k.code):
			KEY_CAPSLOCK: caps = not caps
			KEY_NUMLOCK: num = not num
			KEY_SCROLLLOCK: scroll = not scroll
	var flags: Dictionary = captured.flags
	for m in mods:
		var physical := held.values().any(func(s: Dictionary) -> bool: return bool(s.modifier) and int(s.index) == m)
		if physical and not destination.is_empty():
			if not _held_outputs.has(m):
				_held_outputs[m] = []
			var outputs: Array = _held_outputs[m]
			if not outputs.any(func(o: Dictionary) -> bool: return o.target.identity == destination.identity):
				outputs.append({"target": destination, "flags": flags})
				router.key(event(m, true, flags), destination)
		router.key(event(m, true, flags), destination)
	var e := event(index, true, flags)
	router.key(e, destination)
	held[source] = {"index": index, "modifier": false, "target": destination, "mods": mods, "flags": flags,
			"event": e, "wait": REPEAT_DELAY}


## Capture on trigger down, even for a buffered letter. Releasing Shift while drawing must not change its case,
## and two simultaneous gestures must not both claim a one-shot.
func capture_modifiers() -> Dictionary:
	var mods: Array[int] = []
	for m: int in modifiers:
		mods.append(m)
	for s: Dictionary in held.values():
		if bool(s.modifier):
			s.used = true
			if not mods.has(int(s.index)):
				mods.append(int(s.index))
	var flags := {"shift": modifier_on(KEY_SHIFT), "ctrl": modifier_on(KEY_CTRL),
			"alt": modifier_on(KEY_ALT), "meta": modifier_on(KEY_META), "caps": caps, "num": num}
	for m in mods:
		if int(modifiers.get(m, 0)) == 1:
			modifiers.erase(m)
	return {"mods": mods, "flags": flags}


func release(source: Variant) -> void:
	if not held.has(source):
		return
	var s: Dictionary = held[source]
	held.erase(source)
	var index := int(s.index)
	if bool(s.modifier):
		# A physical modifier can come up before the ordinary key. Remove that stroke's reference as well, so the
		# window sees the release now, rather than waiting for the last letter to come up.
		for stroke: Dictionary in held.values():
			if not bool(stroke.modifier) and (stroke.mods as Array).has(index):
				router.key(event(index, false, stroke.flags), stroke.target)
				(stroke.mods as Array).erase(index)
		for output: Dictionary in _held_outputs.get(index, []):
			router.key(event(index, false, output.flags), output.target)
		_held_outputs.erase(index)
		if not bool(s.used):
			var before := int(s.before)
			if before == 2:
				modifiers.erase(index)
			else:
				modifiers[index] = before + 1
		return
	var up := (s.event as InputEventKey).duplicate() as InputEventKey
	up.pressed = false
	up.echo = false
	router.key(up, s.target)
	for m: int in s.mods:
		router.key(event(m, false, s.flags), s.target)


func event(index: int, down: bool, flags: Dictionary = {}) -> InputEventKey:
	var e := InputEventKey.new()
	var k: Dictionary = keys[index]
	e.keycode = int(k.code) as Key
	e.physical_keycode = e.keycode
	e.location = int(k.location) as KeyLocation
	e.pressed = down
	e.shift_pressed = bool(flags.get("shift", false))
	e.ctrl_pressed = bool(flags.get("ctrl", false))
	e.alt_pressed = bool(flags.get("alt", false))
	e.meta_pressed = bool(flags.get("meta", false))
	e.unicode = Layout.character(k, e.shift_pressed, bool(flags.get("caps", caps)), bool(flags.get("num", num)))
	return e


func step(delta: float) -> void:
	for s: Dictionary in held.values():
		if bool(s.modifier) or not bool((s.target as Dictionary).get("repeat", false)) \
				or int(keys[int(s.index)].code) in [KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]:
			continue
		s.wait = float(s.wait) - delta
		while float(s.wait) <= 0.0:
			# A modifier can come up while a letter is still held. Echoes use the stroke's remaining modifiers and
			# the current locks, rather than freezing the case that was present at its first down.
			var flags := {"shift": false, "ctrl": false, "alt": false, "meta": false}
			for m: int in s.mods:
				match int(keys[m].code):
					KEY_SHIFT: flags.shift = true
					KEY_CTRL: flags.ctrl = true
					KEY_ALT: flags.alt = true
					KEY_META: flags.meta = true
			var e := event(int(s.index), true, flags)
			e.echo = true
			router.key(e, s.target)
			s.wait = float(s.wait) + REPEAT_INTERVAL


func cancel() -> void:
	for source: Variant in held.keys():
		release(source)
	modifiers.clear()


## Words use the same physical keys as taps, so shells and remote windows get shortcuts and text by one route.
func type_text(text: String, target: Dictionary) -> void:
	for ch in text:
		var upper := ch.to_upper()
		var code := upper.unicode_at(0)
		var index := find_key(code)
		if index < 0:
			continue
		var letter := code >= KEY_A and code <= KEY_Z
		var flags := {"shift": (ch != ch.to_lower()) != caps if letter else false}
		var shift := find_key(KEY_SHIFT)
		if bool(flags.shift):
			router.key(event(shift, true, flags), target)
		var e := event(index, true, flags)
		# Word case is already chosen; Caps is a local light as well as a physical toggle in windows.
		e.unicode = ch.unicode_at(0)
		router.key(e, target)
		e = e.duplicate()
		e.pressed = false
		router.key(e, target)
		if bool(flags.shift):
			router.key(event(shift, false, flags), target)


func find_key(code: int) -> int:
	for i in keys.size():
		if int(keys[i].code) == code:
			return i
	return -1


func erase(count: int, target: Dictionary) -> void:
	var back := find_key(KEY_BACKSPACE)
	for i in count:
		var e := event(back, true)
		router.key(e, target)
		e = e.duplicate()
		e.pressed = false
		router.key(e, target)
