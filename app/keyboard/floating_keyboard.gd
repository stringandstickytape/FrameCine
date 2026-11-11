## A world-locked keyboard, made by ui_layer.gd, with the same grip and stick rules as a PC pane. Both hands can
## aim and poke independently. A key goes down when the trigger or the tip does, and up when it leaves. The ordinary
## picture contains only the panel and the legends; typed content stays in the target and is never included in
## status or dev events. Closing, losing tracking or losing the XR session releases every key.
extends Node3D

const Pointing := preload("res://scripts/pointing/pointing.gd")

const Layout := preload("res://keyboard/key_layout.gd")
const Router := preload("res://keyboard/keyboard_router.gd")
const State := preload("res://keyboard/key_state.gd")
const Surface := preload("res://keyboard/keyboard_surface.gd")
const Style := preload("res://ui/pane_style.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const Commands := preload("res://scripts/dev/dev_commands.gd")
const MIN_WIDTH := 0.35
const MAX_WIDTH := 1.6
const POKE_DOWN := -0.006
const POKE_UP := 0.012
## The Close box in the bar, in key units.
const CLOSE := Rect2(20.5, 0.17, 2.3, 0.66)
var app: Node
var router := Router.new()
var state := State.new()
var width := 0.85
var aims := {}
var _viewport: SubViewport
var _surface: Control
var _mesh: MeshInstance3D
var _light_mesh: MeshInstance3D
var _light_viewport: SubViewport
var _light_surface: Control
var _holds := {}
var _pokes := {}
var _tips := {}
var _lit := {}
var _placed := false
## What the two pictures last showed (_redraw()).
var _drawn := []
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
	# Lit and hovered keys reveal what is typed. Keep their ink on the same private layer as windows, while the
	# board and its generic target label remain ordinary room furniture in snapshots.
	_light_viewport = SubViewport.new()
	_light_viewport.size = _viewport.size
	_light_viewport.transparent_bg = true
	_light_viewport.disable_3d = true
	_light_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_light_viewport)
	_light_surface = Surface.new()
	_light_surface.keyboard = self
	_light_surface.lights_only = true
	_light_surface.size = _surface.size
	_light_viewport.add_child(_light_surface)
	_light_mesh = MeshInstance3D.new()
	_light_mesh.mesh = QuadMesh.new()
	var light_mat := mat.duplicate() as StandardMaterial3D
	light_mat.albedo_texture = _light_viewport.get_texture()
	_light_mesh.material_override = light_mat
	_light_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light_mesh.set_layer_mask_value(1, false)
	_light_mesh.set_layer_mask_value(VideoScreen.PRIVATE_LAYER, true)
	_light_mesh.position.z = 0.001
	add_child(_light_mesh)
	set_width(width)
	if app.get("pointing") is Pointing:
		app.pointing.add(self)
	Commands.register("keyboard", func(a: Dictionary, _ctx: Commands.Call) -> Variant:
		set_shown(bool(a.get("show", true)))
		return {"shown": visible, "width": width}, {
			"description": "Shows or closes the floating keyboard. Keys and typed text are never returned.",
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
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_light_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_drawn = []


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
		(_light_mesh.mesh as QuadMesh).size = (_mesh.mesh as QuadMesh).size


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


## For scripts/pointing/pointing.gd: what this hand's ray meets here, and whether the keyboard has the hand anyway
## (it is held by it, or it has a key down with it).
func point_hit(_hand: Object, origin: Vector3, direction: Vector3) -> Dictionary:
	return hit(origin, direction)


func point_holds(hand: Object) -> bool:
	return visible and (_holds.has(hand) or state.held.has(hand))


func key_at(point: Vector2) -> int:
	for i in state.keys.size():
		if (state.keys[i].rect as Rect2).has_point(point):
			return i
	return -1


func owns_laser(hand: Node) -> bool:
	return visible and (aims.has(hand) or _holds.has(hand) or state.held.has(hand) or _pokes.has(hand))


## ui_layer calls this before its own pointer, giving each hand one owner for this frame.
func step(delta: float) -> void:
	if not visible:
		return
	if not app.session_focused:
		cancel()
		return
	state.step(delta)
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
		# The nearest thing the laser is on has the hand: the keyboard's hit only when that is the keyboard.
		var h := Pointing.hit_for(app, self, hand)
		if h.is_empty() or h.has("held"):
			aims.erase(hand)
		else:
			aims[hand] = h
		_poke(hand, controller_tip(hand))
		var on := owns_laser(hand)
		if on:
			hand.set_laser(true, float(h.get("distance", 0.1)), true, Style.color(&"laser"), Style.color(&"laser_dot"))
		elif bool(_lit.get(hand, false)):
			hand.set_laser(false)
		_lit[hand] = on
	_redraw()


## Two pictures of 2300 x 725 with 104 legends each are not free: draw them only when what they show has changed,
## not on every frame the keyboard is open.
func _redraw() -> void:
	if _surface == null:
		return
	var hovered := []
	for a: Dictionary in aims.values():
		hovered.append(int(a.get("key", -1)))
	var lit := []
	for i in state.keys.size():
		if state.lit(i):
			lit.append(i)
	var now := [hovered, lit, state.modifiers.duplicate(), state.caps, state.modifier_on(KEY_SHIFT),
			router.target_name(), Style.active().get_instance_id(), Style.active().default_font_size]
	if now == _drawn:
		return
	_drawn = now
	_surface.queue_redraw()
	_light_surface.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_light_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func on_trigger(hand: Node, down: bool) -> bool:
	if not down and state.held.has(hand):
		state.release(hand)
		return true
	var h: Dictionary = aims.get(hand, {})
	if h.is_empty() or not visible:
		return false
	if down and not _holds.has(hand):
		if CLOSE.has_point(h.point):
			set_shown(false)
		elif int(h.key) >= 0:
			state.press(hand, int(h.key))
		_pulse(hand, false)
	return true


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
			or _pokes.values().has(index) or state.held.has(hand):
		return
	_pokes[hand] = index
	if index == -2:
		set_shown(false)
	else:
		state.press("poke%d" % hand.get_instance_id(), index)
	_pulse(hand, true)


func _touch_at(point: Vector2) -> int:
	if CLOSE.has_point(point):
		return -2
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
	_pokes.clear()
	_tips.clear()
	aims.clear()
	_holds.clear()


func _exit_tree() -> void:
	cancel()
