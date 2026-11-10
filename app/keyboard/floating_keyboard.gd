## A world-locked keyboard, made by ui_layer.gd, with the same grip and stick rules as a PC pane. Both hands can
## aim and poke independently. The ordinary picture contains only keys; typed content stays in the target and is
## never included in status or dev events. Closing, losing tracking or losing the XR session releases every key.
extends Node3D

const Layout := preload("res://keyboard/key_layout.gd")
const Router := preload("res://keyboard/keyboard_router.gd")
const State := preload("res://keyboard/key_state.gd")
const Decoder := preload("res://keyboard/swipe_decoder.gd")
const Surface := preload("res://keyboard/keyboard_surface.gd")
const Style := preload("res://ui/pane_style.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const Commands := preload("res://scripts/dev/dev_commands.gd")
const MIN_WIDTH := 0.35
const MAX_WIDTH := 1.6
const POKE_DOWN := -0.006
const POKE_UP := 0.012
var app: Node
var router := Router.new()
var state := State.new()
var decoder := Decoder.new()
var width := 0.85
var aims := {}
var alternatives: Array[String] = []
var trails := {}
var _worker: Thread
var _ready_words := false
var _viewport: SubViewport
var _surface: Control
var _mesh: MeshInstance3D
var _candidate_mesh: MeshInstance3D
var _candidate_viewport: SubViewport
var _candidate_surface: Control
var _holds := {}
var _strokes := {}
var _pokes := {}
var _tips := {}
var _lit := {}
var _last_word := {}
var _placed := false
## Desktop tests can supply tracked hand poses without an XR session, as pc_windows.gd does.
var test_xr := false


func setup(p_app: Node) -> void:
	app = p_app
	router.setup(app)
	state.router = router
	width = clampf(float(app.settings.get_value("keyboard", "width", width)), MIN_WIDTH, MAX_WIDTH)
	var saved: Variant = app.settings.get_value("keyboard", "transform", Transform3D()) if app.settings.has_value("keyboard", "transform") else null
	if saved is Transform3D:
		transform = saved
		_placed = true
	visible = false
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(Layout.SIZE * Surface.UNIT)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_surface = Surface.new()
	_surface.keyboard = self
	_surface.size = Vector2(_viewport.size)
	_viewport.add_child(_surface)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _viewport.get_texture()
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	# Suggestions and gestures reveal words. Keep their ink on the same private layer as windows, while the board
	# and its generic target label remain ordinary room furniture in snapshots.
	_candidate_viewport = SubViewport.new()
	_candidate_viewport.size = _viewport.size
	_candidate_viewport.transparent_bg = true
	_candidate_viewport.disable_3d = true
	_candidate_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_candidate_viewport)
	_candidate_surface = Surface.new()
	_candidate_surface.keyboard = self
	_candidate_surface.candidates_only = true
	_candidate_surface.size = _surface.size
	_candidate_viewport.add_child(_candidate_surface)
	_candidate_mesh = MeshInstance3D.new()
	_candidate_mesh.mesh = QuadMesh.new()
	var candidate_mat := mat.duplicate() as StandardMaterial3D
	candidate_mat.albedo_texture = _candidate_viewport.get_texture()
	_candidate_mesh.material_override = candidate_mat
	_candidate_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_candidate_mesh.set_layer_mask_value(1, false)
	_candidate_mesh.set_layer_mask_value(VideoScreen.PRIVATE_LAYER, true)
	_candidate_mesh.position.z = 0.001
	add_child(_candidate_mesh)
	set_width(width)
	_worker = Thread.new()
	_worker.start(decoder.build)
	Commands.register("keyboard", func(a: Dictionary, _ctx: Commands.Call) -> Variant:
		set_shown(bool(a.get("show", true)))
		return {"shown": visible, "width": width}, {
			"description": "Shows or closes the floating keyboard. Keys and typed words are never returned.",
			"params": [{"name": "show", "type": "bool", "default": true}],
			"level": "control", "assistant": "control"})


func set_shown(on: bool) -> void:
	if not on:
		cancel()
		_save()
	elif not _placed:
		recentre()
	visible = on
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		_candidate_viewport.render_target_update_mode = _viewport.render_target_update_mode


func recentre() -> void:
	if app == null:
		return
	var head: Transform3D = app.camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	global_position = head.origin + forward * 0.65 + Vector3.DOWN * 0.35
	global_basis = Basis.looking_at((global_position - head.origin).normalized(), Vector3.UP)
	_placed = true
	_save()


func set_width(value: float) -> void:
	width = clampf(value, MIN_WIDTH, MAX_WIDTH)
	if _mesh != null:
		(_mesh.mesh as QuadMesh).size = Vector2(width, width * Layout.SIZE.y / Layout.SIZE.x)
		(_candidate_mesh.mesh as QuadMesh).size = (_mesh.mesh as QuadMesh).size


func _save() -> void:
	if app != null and _placed:
		app.settings.set_value("keyboard", "transform", transform)
		app.settings.set_value("keyboard", "width", width)


## Face +Z, like pc_pane.gd. A hit on an empty gap or the bar still owns the laser and can be grabbed.
func hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not visible:
		return {}
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * direction
	if d.z >= -0.00001 or o.z <= 0.0:
		return {}
	var t := -o.z / d.z
	var p := o + d * t
	var point := Vector2(p.x / width * Layout.SIZE.x + Layout.SIZE.x / 2.0,
			Layout.SIZE.y / 2.0 - p.y / width * Layout.SIZE.x)
	if not Rect2(Vector2.ZERO, Layout.SIZE).has_point(point):
		return {}
	return {"point": point, "key": key_at(point), "distance": origin.distance_to(global_transform * p)}


func key_at(point: Vector2) -> int:
	for i in state.keys.size():
		if (state.keys[i].rect as Rect2).has_point(point):
			return i
	return -1


func owns_laser(hand: Node) -> bool:
	return visible and (aims.has(hand) or _holds.has(hand) or _strokes.has(hand) or _pokes.has(hand))


## ui_layer calls this before its own pointer, giving each hand one owner for this frame.
func step(delta: float) -> void:
	if _worker != null and not _worker.is_alive():
		_worker.wait_to_finish()
		_worker = null
		_ready_words = true
	if not visible:
		return
	if not app.session_focused:
		cancel()
		return
	state.step(delta)
	if not _last_word.is_empty():
		var target := router.capture()
		if target.is_empty() or target.identity != (_last_word.target as Dictionary).get("identity"):
			_clear_word()
	for hand: Node in app.hands:
		if not (app.use_xr or test_xr) or not (hand.get_is_active() or test_xr):
			_release_hand(hand)
			continue
		if _holds.has(hand):
			var hold: Dictionary = _holds[hand]
			global_position = hand.get_ray_origin() + hand.get_ray_direction() * float(hold.distance)
			global_basis = hand.global_basis.orthonormalized() * (hold.rel as Basis)
			hand.set_laser(true, float(hold.distance), true)
			continue
		var h := hit(hand.get_ray_origin(), hand.get_ray_direction())
		if h.is_empty():
			aims.erase(hand)
		else:
			aims[hand] = h
			if _strokes.has(hand):
				_trace(hand, h)
		if _strokes.has(hand):
			var s: Dictionary = _strokes[hand]
			s.age = float(s.age) + delta
			if not bool(s.swipe) and not bool(s.sent) and float(s.age) >= State.REPEAT_DELAY:
				state.press(hand, int(s.index), s.target, s.modifiers)
				(state.held[hand] as Dictionary).wait = State.REPEAT_INTERVAL
				s.sent = true
		_poke(hand, controller_tip(hand))
		var on := owns_laser(hand)
		if on:
			hand.set_laser(true, float(h.get("distance", 0.1)), true, Style.color(&"laser"), Style.color(&"laser_dot"))
		elif bool(_lit.get(hand, false)):
			hand.set_laser(false)
		_lit[hand] = on
	for trail: Array in trails.values():
		while not trail.is_empty() and Time.get_ticks_msec() / 1000.0 - float(trail[0].time) > 0.7:
			trail.pop_front()
	if _surface != null:
		_surface.queue_redraw()
		_candidate_surface.queue_redraw()


func on_trigger(hand: Node, down: bool) -> bool:
	if not down and _strokes.has(hand):
		_finish(hand)
		return true
	if not down and state.held.has(hand):
		state.release(hand)
		return true
	var h: Dictionary = aims.get(hand, {})
	if h.is_empty() or not visible:
		return false
	if down and not _holds.has(hand):
		var point: Vector2 = h.point
		if Rect2(20.5, 0.12, 2.3, 0.65).has_point(point):
			set_shown(false)
		elif point.y >= 1.0 and point.y <= 1.7:
			choose_alternative(clampi(int(point.x / 7.6) + 1, 1, 3))
		else:
			var index := int(h.key)
			if index >= 0:
				var code := int(state.keys[index].code)
				if code >= KEY_A and code <= KEY_Z and not state.modifier_on(KEY_CTRL) \
						and not state.modifier_on(KEY_ALT) and not state.modifier_on(KEY_META):
					var modifiers := state.capture_modifiers()
					_strokes[hand] = {"index": index, "target": router.capture(), "path": PackedVector2Array([point]),
							"crossed": {index: true}, "swipe": false, "sent": false, "age": 0.0,
							"capital": bool(modifiers.flags.shift), "caps": state.caps, "modifiers": modifiers}
				else:
					_press(hand, index)
		_pulse(hand, false)
	return true


func _press(source: Variant, index: int) -> void:
	if int(state.keys[index].code) == KEY_BACKSPACE and not _last_word.is_empty():
		state.erase(int(_last_word.count), _last_word.target)
		_clear_word()
		return
	if not state.is_modifier(index):
		_clear_word()
	state.press(source, index)


func _trace(hand: Node, h: Dictionary) -> void:
	var s: Dictionary = _strokes[hand]
	if bool(s.sent):
		return
	var path: PackedVector2Array = s.path
	var point: Vector2 = h.point
	if path[-1].distance_to(point) < 0.08:
		return
	path.append(point)
	s.path = path
	var index := int(h.key)
	if index >= 0 and int(state.keys[index].code) >= KEY_A and int(state.keys[index].code) <= KEY_Z:
		s.crossed[index] = true
		s.swipe = (s.crossed as Dictionary).size() >= 3
	if not trails.has(hand):
		trails[hand] = []
	trails[hand].append({"point": point, "time": Time.get_ticks_msec() / 1000.0})


func _finish(hand: Node) -> void:
	var s: Dictionary = _strokes[hand]
	_strokes.erase(hand)
	if bool(s.sent):
		state.release(hand)
	elif bool(s.swipe) and _ready_words:
		var words := decoder.decode(s.path)
		if not words.is_empty():
			alternatives = words
			var word := _case(words[0], bool(s.capital), bool(s.caps)) + " "
			state.type_text(word, s.target)
			_last_word = {"target": s.target, "count": word.length(), "capital": s.capital, "caps": s.caps}
	else:
		_clear_word()
		state.press(hand, int(s.index), s.target, s.modifiers)
		state.release(hand)


func _case(word: String, capital: bool, caps: bool) -> String:
	return word.to_upper() if caps else (word.capitalize() if capital else word)


func choose_alternative(index: int) -> void:
	if _last_word.is_empty() or index >= alternatives.size():
		return
	var target: Dictionary = _last_word.target
	state.erase(int(_last_word.count), target)
	var word := _case(alternatives[index], bool(_last_word.capital), bool(_last_word.caps)) + " "
	state.type_text(word, target)
	_last_word.count = word.length()


func _clear_word() -> void:
	_last_word.clear()
	alternatives.clear()


func on_grip(hand: Node, down: bool) -> bool:
	if not down:
		if _holds.has(hand):
			_holds.erase(hand)
			_save()
			return true
		return false
	var h: Dictionary = aims.get(hand, {})
	if h.is_empty() or not visible:
		return false
	if not _holds.is_empty():
		return true
	_release_hand(hand)
	_holds[hand] = {"distance": h.distance, "rel": hand.global_basis.orthonormalized().inverse() * global_basis}
	return true


func on_stick(hand: Node, stick: Vector2, delta: float) -> bool:
	if _holds.has(hand):
		if absf(stick.x) > 0.2 and absf(stick.x) >= absf(stick.y):
			set_width(width * (1.0 + stick.x * 0.8 * delta))
		elif absf(stick.y) > 0.2:
			_holds[hand].distance = clampf(float(_holds[hand].distance) * (1.0 + stick.y * 1.5 * delta), 0.2, 6.0)
		return true
	return owns_laser(hand)


## Tip crosses inward from the front. Hysteresis and per-key ownership stop chatter and double pokes; the depth
## bound rejects a hand appearing behind the board. The face is only a test plane, never a room physics body.
func _poke(hand: Node, world_tip: Vector3) -> void:
	var tip := to_local(world_tip)
	var point := Vector2(tip.x / width * Layout.SIZE.x + Layout.SIZE.x / 2.0,
			Layout.SIZE.y / 2.0 - tip.y / width * Layout.SIZE.x)
	var previous: Vector3 = _tips.get(hand, tip)
	_tips[hand] = tip
	if _pokes.has(hand):
		if tip.z >= POKE_UP or tip.z < -0.06 or _touch_at(point) != int(_pokes[hand]):
			state.release("poke%d" % hand.get_instance_id())
			_pokes.erase(hand)
		return
	var index := _touch_at(point)
	if index == -1 or tip.z < -0.06 or previous.z < POKE_DOWN or tip.z > POKE_DOWN or tip.z >= previous.z \
			or _pokes.values().has(index) or _strokes.has(hand) or state.held.has(hand):
		return
	_pokes[hand] = index
	if index == -2:
		set_shown(false)
	elif index < -2:
		choose_alternative(-index - 2)
	else:
		_press("poke%d" % hand.get_instance_id(), index)
	_pulse(hand, true)


func _touch_at(point: Vector2) -> int:
	if Rect2(20.5, 0.12, 2.3, 0.65).has_point(point):
		return -2
	if point.x >= 0.0 and point.x < Layout.SIZE.x and point.y >= 1.0 and point.y <= 1.7:
		return -3 - clampi(int(point.x / 7.6), 0, 2)
	return key_at(point)


## As with watch_card.face_of(), measure the runtime mesh in aim-pose space, not its node origin. The foremost
## face's middle is the tip. A runtime model too far from the tracked hand is ignored until it settles there.
static func controller_tip(hand: Node3D) -> Vector3:
	var visual: Node = hand.get("visual")
	var model: Node3D = visual.get("_model_root") if visual != null else null
	if model == null and visual != null:
		model = visual.get("_ours")
	if model != null and is_instance_valid(model):
		var inverse := hand.global_transform.affine_inverse()
		var best := 0.0
		var points := PackedVector3Array()
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			var box := mesh.get_aabb()
			var xf := inverse * mesh.global_transform
			for i in 8:
				var p := xf * box.get_endpoint(i)
				if p.length() < 0.3:
					points.append(p)
					best = minf(best, p.z)
		if best < 0.0:
			var front := Vector3.ZERO
			var count := 0
			for p in points:
				if p.z <= best + 0.003:
					front += p
					count += 1
			return hand.global_transform * (front / maxi(count, 1))
	return hand.global_position - hand.global_basis.z * 0.045


func _pulse(hand: Node, poke: bool) -> void:
	if poke and hand.has_method("trigger_haptic_pulse"):
		hand.trigger_haptic_pulse(&"haptic", 0.0, 0.6, 0.035, 0.0)
	elif hand.has_method("pulse"):
		hand.pulse()


func _release_hand(hand: Node) -> void:
	_strokes.erase(hand)
	state.release(hand)
	state.release("poke%d" % hand.get_instance_id())
	_pokes.erase(hand)
	_tips.erase(hand)
	aims.erase(hand)
	if _holds.has(hand):
		_holds.erase(hand)
		_save()
	if bool(_lit.get(hand, false)):
		hand.set_laser(false)
	_lit.erase(hand)


func cancel() -> void:
	state.cancel()
	for hand: Node in _lit.keys():
		_release_hand(hand)
	_strokes.clear()
	_pokes.clear()
	_tips.clear()
	aims.clear()
	_holds.clear()
	trails.clear()
	_clear_word()


func _exit_tree() -> void:
	cancel()
	if _worker != null:
		_worker.wait_to_finish()
