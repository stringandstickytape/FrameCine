extends Node3D

## The watch-along card (idea #54, the UI half): a short answer pushed from the PC link (the AI listener) shown on a
## small themed panel held above the pointer controller, like a phone ([card] place = hand, the default: the viewer
## holds that controller for push-to-talk anyway, and the conversation is personal; the user's call, 2026-11-01), or
## beside the screen ([card] place = screen, and while the card offers choices: the laser can't reach a card on its own
## hand): its top-left corner just right of the picture's top-right corner, or 2.5 m ahead and to the right in 180/360. About 24° wide at its distance (15 px text is then about 0.75°). The right laser and the trigger
## dismiss it; otherwise it times out. One card at a time: a new one replaces the old. It never covers the film.
##
## Commands (registered in the dev registry, scripts/dev/dev_commands.gd; level "control"):
##   card {text, title?, image? (base64 PNG or JPEG, at most 256 KB), seconds? (20; 0 = until dismissed), id?} -> {id}
##   card_clear {id? ("" = any)} -> {cleared}
## Event: card_dismissed {id, how: "user" | "timeout" | "replaced" | "cleared"}.

const PaneStyle := preload("res://ui/pane_style.gd")
const W := preload("res://ui/pane_widgets.gd")
const Pane := preload("res://ui/pane.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const DevHost := preload("res://scripts/dev/dev_host.gd")

signal dismissed(id: String, how: String)

const WIDTH_PX := 480
const MAX_HEIGHT_PX := 640
const IMAGE_MAX_PX := 180
const ANGLE := deg_to_rad(24.0)
## Between the picture's corner and the card, and how much nearer than the corner the card hangs (fractions of its
## distance).
const GAP := 0.025
const FRONT := 0.02
const SPHERE_DISTANCE := 2.5
## Beside a flat screen, the card keeps the screen's direction but comes no further than this from the head.
const NEAR_DISTANCE := 2.0
const SPHERE_YAW := deg_to_rad(32.0)
## On the hand: laid on the controller's top face, in the plane through its X, Y and B buttons (the user marked them
## and confirmed: "that's your plane"), fixed to the controller: turning the controller turns the card (turned toward
## the head it took odd angles). The plane is taken from the runtime's render model of that controller (face_of());
## FACE_NORMAL and FACE_CENTRE (aim-pose space, the Frame's right controller) stand in without one. The card's middle
## lies in that plane right over the laser's line, its bottom edge just beyond the controller's front (HAND_ALONG).
const HAND_WIDTH := 0.18
const FACE_NORMAL := Vector3(-0.083, 0.990, 0.115)
const FACE_CENTRE := Vector3(0.013, 0.005, 0.033)
const HAND_LIFT := 0.0
## Where the card's bottom edge starts along the laser from the laser's origin: the Frame controller's front is 1.2 cm
## along it, and the card begins a little beyond that (the user's spec), centred across the laser.
const HAND_ALONG := 0.027
const DEFAULT_SECONDS := 20.0
const MAX_IMAGE_BYTES := 256 * 1024

## scripts/main.gd
var app: Node3D
var id := ""
var viewport: SubViewport
var size_m := Vector2(0.5, 0.25)
var _root: PanelContainer
var _title: Label
var _text: Label
var _image: TextureRect
## The card's choices ({actions}): buttons along its bottom; the trigger on one dismisses the card with its id as how.
var _actions: HBoxContainer
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _left := 0.0
var _opacity := 0.0
var _target := 0.0
var _next_id := 1


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "CardViewport"
	viewport.size = Vector2i(WIDTH_PX, 200)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	_root = PanelContainer.new()
	_root.theme = PaneStyle.theme()
	_root.theme_type_variation = &"PaneRoot"
	_root.custom_minimum_size = Vector2(WIDTH_PX, 0)
	viewport.add_child(_root)
	var box := W.vbox()
	_root.add_child(box)
	_title = W.caps("")
	box.add_child(_title)
	_text = W.label("")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH_PX - 2 * PaneStyle.constant(&"pad"), 0)
	box.add_child(_text)
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_image)
	_actions = W.hbox([])
	box.add_child(_actions)

	_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = Pane.PANE_SHADER
	_mat.shader = shader
	_mat.set_shader_parameter("tex", viewport.get_texture())
	_mat.set_shader_parameter("opacity", 0.0)
	# Above the windows to the real room (scripts/play/real_windows.gd PRIORITY, 2).
	_mat.render_priority = 4
	_mesh = MeshInstance3D.new()
	_mesh.name = "CardQuad"
	_mesh.mesh = QuadMesh.new()
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


## Registers `card` and `card_clear` (and the event) in the dev registry. Cheap; done whether or not dev mode is on.
func register_commands() -> void:
	DevCommands.register("card", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var err := ""
		var data := {"text": args["text"], "title": args["title"], "seconds": args["seconds"], "id": args["id"]}
		if str(args["image"]) != "":
			var bytes := Marshalls.base64_to_raw(str(args["image"]))
			if bytes.size() > MAX_IMAGE_BYTES:
				err = "image too big (%d KB, at most %d)" % [bytes.size() / 1024, MAX_IMAGE_BYTES / 1024]
			else:
				data["image_bytes"] = bytes
		if err != "":
			return ctx.fail(err)
		var shown := show_card(data)
		var words := str(args["title"]) if str(args["title"]) != "" else str(args["text"]).left(40)
		ctx.summary = "card: %s" % words
		return {"id": shown}, {
		"description": "Shows a short answer on a card beside the screen until the user dismisses it (laser and "
				+ "trigger) or it times out. A new card replaces the old one.",
		"params": [{"name": "text", "type": "string", "required": true, "description": "the answer, a few lines"},
				{"name": "title", "type": "string", "default": "", "description": "a short heading"},
				{"name": "image", "type": "string", "default": "", "description": "base64 PNG or JPEG, at most 256 KB"},
				{"name": "seconds", "type": "float", "default": DEFAULT_SECONDS, "description": "0: until dismissed"},
				{"name": "id", "type": "string", "default": "", "description": "empty: a new id"}],
		"level": "control", "assistant": "card",
		"returns": "{id}"})
	DevCommands.register("card_clear", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var n := 0
		if visible and (str(args["id"]) == "" or str(args["id"]) == id):
			dismiss("cleared")
			n = 1
			ctx.summary = "card cleared"
		return {"cleared": n}, {
		"description": "Takes the card away (a given id, or any).",
		"params": [{"name": "id", "type": "string", "default": "", "description": "empty: any card"}],
		"level": "control", "assistant": "card",
		"returns": "{cleared}"})
	DevCommands.register_event("card_dismissed", "A watch-along card went away.",
			{"id": "string", "how": "user | timeout | replaced | cleared"})


## Shows a card: {text, title?, seconds?, id?, image_bytes? (PackedByteArray), image? (Image)}. Returns its id.
func show_card(data: Dictionary) -> String:
	if visible and _target > 0.0:
		_emit_dismissed("replaced")
	id = str(data.get("id", ""))
	if id == "":
		id = "card%d" % _next_id
		_next_id += 1
	_title.text = str(data.get("title", ""))
	_title.visible = _title.text != ""
	_text.text = str(data.get("text", ""))
	if _text.has_meta(&"live_base"):
		_text.remove_meta(&"live_base")  # _fit() sets it again for a live line
	var img: Image = data.get("image")
	if img == null and data.get("image_bytes") is PackedByteArray:
		img = _decode(data["image_bytes"])
	_image.texture = ImageTexture.create_from_image(img) if img != null else null
	_image.visible = img != null
	if img != null:
		var h := mini(IMAGE_MAX_PX, int(float(img.get_height()) * (WIDTH_PX - 32) / maxf(img.get_width(), 1.0)))
		_image.custom_minimum_size = Vector2(0, h)
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for act: Dictionary in data.get("actions", []):
		var b: Button = W.button(str(act.get("label", act.get("id", ""))), func() -> void: pass)
		b.set_meta(&"action", str(act.get("id", "")))
		_actions.add_child(b)
	_actions.visible = _actions.get_child_count() > 0
	var seconds := float(data.get("seconds", DEFAULT_SECONDS))
	_left = seconds if seconds > 0.0 else INF
	_target = 1.0
	visible = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_fit.call_deferred()
	return id


static func _decode(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	if img.load_png_from_buffer(bytes) == OK or img.load_jpg_from_buffer(bytes) == OK \
			or img.load_webp_from_buffer(bytes) == OK:
		return img
	return null


## Fits the viewport and the quad to the content's height, then places the card.
func _fit() -> void:
	# Too long for the card: drop whole lines from the top, so the newest lines (the end of a conversation) always
	# show; the bottom used to be cut off instead (seen in the headset, 2026-10-31).
	var lines := _text.text.split("\n")
	while lines.size() > 1 and _root.get_combined_minimum_size().y > MAX_HEIGHT_PX:
		lines.remove_at(0)
		while lines.size() > 1 and lines[0].strip_edges() == "":
			lines.remove_at(0)
		_text.text = "\n".join(lines)
	# One line still too tall (a long speech): drop words from its start, marked with "...", keeping the end.
	if _root.get_combined_minimum_size().y > MAX_HEIGHT_PX:
		var words := _text.text.split(" ")
		while words.size() > 8 and _root.get_combined_minimum_size().y > MAX_HEIGHT_PX:
			words = words.slice(4)
			_text.text = "... " + " ".join(words)
	if _text.text.ends_with(" ..."):
		_text.set_meta(&"live_base", _text.text.trim_suffix(" ..."))
	elif _text.has_meta(&"live_base"):
		_text.remove_meta(&"live_base")
	var h := clampi(int(_root.get_combined_minimum_size().y), 60, MAX_HEIGHT_PX)
	viewport.size = Vector2i(WIDTH_PX, h)
	_root.size = Vector2(WIDTH_PX, h)
	place()


func dismiss(how := "user") -> void:
	if not visible or _target <= 0.0:
		return
	_target = 0.0
	_emit_dismissed(how)


func _emit_dismissed(how: String) -> void:
	dismissed.emit(id, how)
	var dev := DevHost.instance()
	if dev != null and dev.get("link") != null:
		dev.link.send_event("card_dismissed", {"id": id, "how": how})


## A new text for the card on show if it is card_id (a download's progress): no new card, no dismissed event.
func set_card_text(card_id: String, text: String) -> bool:
	if not is_showing() or id != card_id:
		return false
	_text.text = text
	if _text.has_meta(&"live_base"):
		_text.remove_meta(&"live_base")
	_fit.call_deferred()
	return true


func is_showing() -> bool:
	return visible and _target > 0.0


## Beside the screen: the card's top-left corner just right of the picture's top-right corner (on a curved screen, the
## curve's corner), or ahead and to the right in 180/360. About ANGLE wide.
func place() -> void:
	if app == null:
		return
	var head: Vector3 = app.camera.global_position
	var aspect := float(viewport.size.y) / WIDTH_PX
	if on_hand():
		size_m = Vector2(HAND_WIDTH, HAND_WIDTH * aspect)
		global_transform = hand_transform(app.ui.pointer_hand, size_m.y)
	elif app.mode.is_spherical():
		var yaw: float = app.screen_yaw + SPHERE_YAW
		var w := 2.0 * SPHERE_DISTANCE * tan(ANGLE * 0.5)
		size_m = Vector2(w, w * aspect)
		var pos := Vector3(head.x + sin(yaw) * SPHERE_DISTANCE, head.y, head.z - cos(yaw) * SPHERE_DISTANCE)
		global_transform = Transform3D(Basis(Vector3.UP, -yaw), pos)
	else:
		# Hung by its top-left corner: placed by its centre and turned toward the viewer, the card's inner edge swung back
		# behind the screen and a curved screen's edge came forward over it (seen in the headset, 2026-11-01).
		var corner: Vector3 = app.screen.top_right_corner()
		# Same direction from the head, but no further than NEAR_DISTANCE: at the screen's own distance the card ends up
		# inside an environment's walls (the cinema's screen spans its wall; seen in the headset, 2026-10-31).
		var dir: Vector3 = (corner - head).normalized() if corner.distance_to(head) > 0.01 else -app.camera.global_basis.z
		var dist := minf(corner.distance_to(head), NEAR_DISTANCE)
		var w := 2.0 * dist * tan(ANGLE * 0.5)
		size_m = Vector2(w, w * aspect)
		# A little nearer than the corner, so the screen's edge never covers the card's.
		var top_left: Vector3 = head + dir * (dist - FRONT * dist)
		# Square to the viewer: turn it about its vertical axis toward the head.
		var to_head: Vector3 = head - top_left
		to_head.y = 0.0
		var basis := Basis.looking_at(to_head, Vector3.UP, true) if to_head.length() > 0.01 else Basis()
		var pos: Vector3 = top_left + basis.x * (GAP * dist + size_m.x * 0.5) - basis.y * size_m.y * 0.5
		global_transform = Transform3D(basis, pos)
	(_mesh.mesh as QuadMesh).size = size_m


## On the hand: a pane of this height laid on the controller (the agents' pane uses it too).
static func hand_transform(hand: Node3D, height: float) -> Transform3D:
	var face := face_of(hand)
	# Its sides exactly parallel to the laser (the aim pose's -Z, the user's call): the face's plane turned about its
	# cross axis by the few degrees the laser leaves it (4.9 on the Frame), through the three buttons' middle.
	var up := Vector3.FORWARD
	var n: Vector3 = face[0]
	n = (n - up * n.dot(up)).normalized()
	# In the face's plane (through the buttons' middle), right over the laser's line, bottom edge HAND_ALONG out.
	var centre: Vector3 = up * (HAND_ALONG + height * 0.5) + n * ((face[1] as Vector3).dot(n) + HAND_LIFT)
	return hand.global_transform * Transform3D(Basis(up.cross(n), up, n), centre)


## [normal, centre] of the plane through the controller's X, Y and B buttons, in its aim-pose space, from the runtime's
## render model (the button meshes nearest the hand, found once and kept as meta on the hand); the constants without.
static func face_of(hand: XRController3D) -> Array:
	var buttons: Array = hand.get_meta(&"face_buttons", [])
	if buttons.size() != 3 or not buttons.all(func(b: Object) -> bool: return is_instance_valid(b)):
		buttons = []
		for want in ["button_x", "button_y", "button_b"]:
			# By the mesh's middle: a runtime model's button node may sit far from its mesh (0.75 m, seen on the Frame).
			var best: MeshInstance3D = null
			var best_d := 0.3
			for m in hand.get_tree().root.find_children(want, "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				if not mi.is_visible_in_tree():
					continue
				var d := (mi.global_transform * mi.get_aabb().get_center()).distance_to(hand.global_position)
				if d < best_d:
					best = mi
					best_d = d
			if best == null:
				return [FACE_NORMAL.normalized(), FACE_CENTRE]
			buttons.append(best)
		hand.set_meta(&"face_buttons", buttons)
	var inv := hand.global_transform.affine_inverse()
	var p: Array[Vector3] = []
	for b: MeshInstance3D in buttons:
		p.append(inv * (b.global_transform * b.get_aabb().get_center()))
	var n := (p[1] - p[0]).cross(p[2] - p[0])
	if n.length() < 1e-6:
		return [FACE_NORMAL.normalized(), FACE_CENTRE]
	n = n.normalized()
	if n.dot(FACE_NORMAL) < 0.0:
		n = -n
	return [n, (p[0] + p[1] + p[2]) / 3.0]


## Held above the pointer controller now (see the top of this file).
func on_hand() -> bool:
	if not app.use_xr or _actions.visible or str(app.settings.get_value("card", "place", "hand")) != "hand":
		return false
	# The agents' pane has the hand while it shows: a card goes beside the screen then.
	if app.get("local_agents") != null and app.local_agents.pane_shown():
		return false
	var hand: XRController3D = app.ui.pointer_hand if app.ui != null else null
	return hand != null and hand.get_is_active()


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left <= 0.0 and _target > 0.0:
		dismiss("timeout")
	# A live line (a transcription in progress, ending in " ..."): three dots that dance, one big dot running
	# along them, so it is plain that the words are still coming (the user: "they're not dancing nearly enough").
	if _text.has_meta(&"live_base"):
		const FRAMES := ["●  •  •", "•  ●  •", "•  •  ●", "•  ●  •"]
		_text.text = str(_text.get_meta(&"live_base")) + "  " + FRAMES[(Time.get_ticks_msec() / 160) % FRAMES.size()]
	var step := delta / maxf(PaneStyle.constant(&"fade_ms") / 1000.0, 0.001)
	_opacity = move_toward(_opacity, _target, step)
	_mat.set_shader_parameter("opacity", _opacity)
	if _opacity <= 0.0 and _target <= 0.0:
		visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		place()


## The trigger on the card at `point` (a ray_hit point): on one of its choices, the card goes with that choice's id as
## how ("go", "stay"); anywhere else, dismissed by the viewer. Returns how.
func click(point: Vector3) -> String:
	if not is_showing():
		return ""
	var how := "user"
	var p := global_transform.affine_inverse() * point
	var px := Vector2((p.x / size_m.x + 0.5) * viewport.size.x, (0.5 - p.y / size_m.y) * viewport.size.y)
	for b in _actions.get_children():
		if b is Control and (b as Control).get_global_rect().grow(4.0).has_point(px):
			how = str(b.get_meta(&"action"))
	dismiss(how)
	return how


## Where on the card a choice's button is, as a world point (tests; the pointer's aim), or null.
func action_point(action_id: String) -> Variant:
	for b in _actions.get_children():
		if b is Control and str(b.get_meta(&"action")) == action_id:
			var c := (b as Control).get_global_rect().get_center()
			return global_transform * Vector3((c.x / viewport.size.x - 0.5) * size_m.x,
					(0.5 - c.y / viewport.size.y) * size_m.y, 0.0)
	return null


## {"distance": float, "point": Vector3} where the ray meets the card, or {}.
func ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not is_showing():
		return {}
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var dv := inv.basis * direction
	if o.z <= 0.0 or dv.z >= -1e-6:
		return {}
	var t := -o.z / dv.z
	var p := o + dv * t
	if absf(p.x) > size_m.x * 0.5 or absf(p.y) > size_m.y * 0.5:
		return {}
	var world := global_transform * p
	return {"distance": world.distance_to(origin), "point": world}
