extends Node3D

## What the user sees of one controller, with each bound input's label printed on it.
##
## Geometry: the runtime's render model when it provides one (XR_EXT_render_model + XR_EXT_interaction_render_model,
## through the engine's OpenXRRenderModelManager, added by xr_hand.gd), else a hand-built low-poly mesh shaped like
## the Steam Frame controller (one unlit mesh with baked shading: one draw call). The fallback is built in AIM pose
## space (this node is a child of the aim-posed hand): the controller's head at the origin, top face +Y, front -Z,
## handle down and back. Layout per side (README, "Controller labels", from Valve's drawing): thumbstick on the inner
## side of the oval face, A/B/X/Y (right) or the d-pad (left) on the outer side, menu / view near the front edge, the
## Steam button behind the face buttons, the bumper above the trigger at the front, the grip button on the handle's
## inner side.
##
## Labels are printed on the plastic: each short legend ("NEXT", "MENU") is a small mesh that lies on the controller's
## actual triangles, so the text wraps it like print (label_surface.gd), with its glyphs from one shared distance-field
## atlas (label_font.gd, controller_label.gdshader). Where: see PLACEMENT. Face labels lie on the face plate, top of the
## text towards the front, read from above and behind as you hold the controller; wall labels run along the side wall,
## top of the text up. Legends on one part of the model are one mesh under that part's node, so they move with it: one
## draw call per part with print on it, usually just the body.
##
## Where things are: with a runtime model, each input's matched node (names printed once, so the device log shows
## them) and the centre of its meshes' bounds, laid onto the face plane (fitted through the face buttons) for face
## controls. The labels are placed in the model's space, so they stay on it whatever its parents do. Without a model,
## the fallback's own anchors and axes. Placement is computed when the labels show (and when texts or the model
## change), never per frame. The print is always there, like real print: nothing runs for it per frame, its meshes are
## built only for what changed, and each legend is kept, so one seen before costs almost nothing. `debug_anchors`
## (--labels-debug) adds a 2 mm sphere at each anchor.

## Printed text: metres per line (capitals about 60 % of it tall), and the gap between a control's edge and its label.
const PRINT_LINE := LabelLayout.DEFAULT_LINE
const GAP := 0.0015
## How far the print looks for the surface along its normal (half each way from where the surface is expected).
const PRINT_DEPTH := 0.016
## Wall labels: how far in from the body's bounds the print reaches to find the wall.
const WALL_REACH := 0.035
const DEBUG_RADIUS := 0.001
const LabelFont := preload("res://scripts/xr/label_font.gd")
const LabelSurface := preload("res://scripts/xr/label_surface.gd")
const LABEL_SHADER := preload("res://shaders/controller_label.gdshader")
const BODY_COLOR := Color(0.2, 0.21, 0.23)
const PART_COLOR := Color(0.36, 0.37, 0.4)
const ACCENT_COLOR := Color(0.55, 0.58, 0.62)
const MODEL_SHADER := preload("res://shaders/controller_model.gdshader")
## The runtime model as the real controller looks: black plastic, in controller_model.gdshader's terms, with the rim and a
## sheen to keep its shape in a dark room. Every other user of the shader keeps its defaults.
const BLACK_LIFT := 0.003
const BLACK_RIM := 0.07
const BLACK_SHEEN := 0.014
## Parts whose moulded art goes white. Not the body: its atlas has the small round port near the menu button, at 0.76.
const INK_PARTS: Array[String] = ["button_a", "button_b", "button_x", "button_y", "button_menu", "button_view", "button_system"]
const RenderModelDump := preload("res://scripts/xr/render_model_dump.gd")
const LabelLayout := preload("res://scripts/xr/label_layout.gd")
## Our layout, authored on the runtime model (tools/label_layout.tscn); used for the inputs it has whenever a model is
## attached. Inputs it lacks, and the hand-built body, fall back to the placement computed here.
const LAYOUT_PATH := "res://xr/controller_labels_layout.tres"
## Our own controller models (tools/controller_model/: derived from Valve's controller CAD, CC BY-NC-SA 4.0, see
## models/controllers/LICENSE-controller.md), with the legends printed into their texture.
const OUR_MODELS := "res://models/controllers"
const ControllerLook := preload("res://scripts/xr/controller_look.gd")
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
## The parts the controllers' look goes on (controller_look.gd): the shell, by its node's name or an ancestor's. The
## rest keep their own colours.
const SHELL_PARTS: Array[String] = ["body", "battery_door"]

## Right controller, aim space (metres): where each input sits. Mirrored in x for the left controller. Measured from
## Valve's controller drawing (README, "Controller labels"), scaled to a face 65 mm wide.
const ANCHORS := {
	"thumbstick": Vector3(-0.0123, 0.011, 0.0071),
	"y": Vector3(0.0116, 0.003, -0.0104),
	"b": Vector3(0.0201, 0.003, -0.005),
	"a": Vector3(0.0142, 0.003, 0.0035),
	"x": Vector3(0.0059, 0.003, -0.0026),
	# Left controller: the d-pad sits where A/B/X/Y are on the right; its left arm is on the outer side.
	"dpad": Vector3(0.013, 0.003, -0.0036),
	"dpad_up": Vector3(0.013, 0.003, -0.0136),
	"dpad_left": Vector3(0.0225, 0.003, -0.0036),
	"dpad_down": Vector3(0.013, 0.003, 0.0064),
	"dpad_right": Vector3(0.0035, 0.003, -0.0036),
	"menu": Vector3(-0.0028, 0.002, -0.0135),
	"view": Vector3(-0.0028, 0.002, -0.0135),
	"system": Vector3(0.0054, 0.002, 0.0151),
	"bumper": Vector3(0.0, -0.006, -0.035),
	"trigger": Vector3(0.0, -0.024, -0.03),
	"squeeze": Vector3(-0.008, -0.035, 0.03),
}
## Fallback: half-size of each control (metres), so text starts just past its edge.
const RADII := {"thumbstick": 0.0095, "a": 0.0045, "b": 0.0045, "x": 0.0045, "y": 0.0045, "dpad": 0.012,
		"dpad_up": 0.0045, "dpad_down": 0.0045, "dpad_left": 0.0045, "dpad_right": 0.0045, "menu": 0.0035,
		"view": 0.0035, "system": 0.004, "squeeze": 0.004}
## Where each label is printed: on the face plate ("face") beside its control, or on the body's side wall ("wall"),
## and which way from the control: outer / inner / front / back. The face is crowded (A/B/X/Y and the stick fill it),
## so labels go where there is plastic: beside A/B on the outer side, Y / the d-pad / menu / view in the strip in
## front, the stick in the strip behind it; trigger and bumper on the head's outer side wall, grip on the handle's
## inner side.
const PLACEMENT := {
	"thumbstick": ["face", "back"],
	"a": ["face", "outer"], "b": ["face", "outer"], "y": ["face", "front"], "x": ["face", "back"],
	"dpad": ["face", "front"], "dpad_up": ["face", "front"], "dpad_down": ["face", "back"],
	"dpad_left": ["face", "outer"], "dpad_right": ["face", "back"],
	"menu": ["face", "front"], "view": ["face", "front"], "system": ["face", "back"],
	"bumper": ["wall", "outer"], "trigger": ["wall", "outer"], "squeeze": ["wall", "inner"],
}
## Inputs on the face plate whose positions define its plane (the thumbstick's cap stands above it).
const FACE_INPUTS := ["a", "b", "x", "y", "menu", "view", "system", "dpad", "dpad_up", "dpad_down", "dpad_left",
		"dpad_right"]
## Handle tilt back from the face normal, degrees.
const HANDLE_TILT := 40.0
## Words to find an input's node in a runtime model (node names split at non-letters, lower case). Single letters
## must be a whole word next to "button" (or the whole name). The headset's models use "button_a", "button_grip",
## "button_menu", "button_view", "button_system", "dpad", "thumbstick", "trigger", "bumper", "body".
const NODE_WORDS := {
	"trigger": ["trigger"],
	"squeeze": ["squeeze", "grip"],
	"thumbstick": ["thumbstick", "joystick", "stick"],
	"bumper": ["bumper", "shoulder"],
	"menu": ["menu", "start"],
	"view": ["view", "select", "back"],
	"system": ["system", "home"],
	"dpad_up": ["dpadup"],
	"dpad_down": ["dpaddown"],
	"dpad_left": ["dpadleft"],
	"dpad_right": ["dpadright"],
	"dpad": ["dpad"],
	"body": ["body"],
}


var side := "right"
## A 2 mm sphere at every label anchor (--labels-debug), to check alignment in the headset.
var debug_anchors := false
## --dump-render-models: write the runtime model of this hand here once it arrives ("" = off).
var dump_dir := ""
## Apply the authored layout (xr/controller_labels_layout.tres) to a model. Off for stand-ins of another shape (tour).
var use_layout := true
## Our model with printed legends (use_our_model()), or null. Its texture per state: "normal", "menu", "window".
var _ours: Node3D
## Moving parts of our model: part name -> {node, rest (in model space), parent (in model space), kind, ...}.
var _moving := {}
## input name -> action name, for the buttons (from the bound profile; set_input_bindings()).
var _button_actions := {}
var _stick_click_action := ""
var _ours_material: ShaderMaterial
var _ours_textures := {}
var _print_state := "normal"
var _dump_done := false
var _sign := 1.0
var _body: MeshInstance3D
## Input -> where it is printed: {"transform": X along the text, Y out of the surface, Z down the text; "size": text
## width, how far to look for the surface, text height; "line": metres per line}, and once built {"key", "laid"}.
var _labels := {}
## Input -> its legend.
var _texts := {}
## Input -> debug sphere, and the anchors the last layout used (label root space).
var _anchors := {}
var _debug := {}
## The model's triangles while labels are in use, read once per model (the first time they show).
var _surface: LabelSurface
## Laid legends by legend and place, so a state seen before needs no new mesh.
var _laid := {}
## Part the print lies on -> its MeshInstance3D.
var _print := {}
## A legend went without another changing.
var _print_stale := false
static var _print_material: ShaderMaterial
## Input -> Node3D of the runtime model (absent: fallback anchor). "body" is the model's body, for its extent.
var _model_nodes := {}
var _model_root: Node3D
## Parent of the labels: this node (fallback) or the runtime model's node, so labels move with the model whatever
## its parents do. All placement is computed in its space.
var _label_root: Node3D
## Label root's space from global, during _layout().
var _space := Transform3D()
## The aim direction in the model's space, once seen consistent (zero until then). Fixed per controller design.
var _model_front := Vector3.ZERO
var _reattach_pending := false
var _shown := false
var _front_timer := false
## Normals of the fallback mesh while it is built.
var _normals := PackedVector3Array()
## The face the last layout used, in the label root's space: centre of the face buttons, normal, body centre.
var _face_centre := Vector3.ZERO
static var _layout_res: LabelLayout
static var _layout_loaded := false
var _face_normal := Vector3.ZERO
var _body_centre := Vector3.ZERO
## The look on show (set_look()) and its shell materials by target ("ours", "runtime", "fallback"), made when first
## needed; none for the default.
var _look_id := ControllerLook.DEFAULT
var _look_options := {}
var _look_materials := {}
var _fallback_material: Material
## The print on a shell that has a look: its ink and backing (both hands show the same look).
static var _look_print_material: ShaderMaterial


func configure(p_side: String) -> void:
	side = p_side
	_sign = -1.0 if side == "left" else 1.0
	_body = MeshInstance3D.new()
	_body.name = "FallbackBody"
	_body.mesh = _build_body()
	# The model shader, colours from the vertices, no fake light.
	var mat := ShaderMaterial.new()
	mat.shader = MODEL_SHADER
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("lift", 0.0)
	mat.set_shader_parameter("fake_light", 0.0)
	_fallback_material = mat
	_body.material_override = mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)
	_label_root = Node3D.new()
	_label_root.name = "Labels"
	add_child(_label_root)


## input -> legend; "" or absent removes that input's label. Lays out; the print is built once it shows.
func set_texts(texts: Dictionary) -> void:
	for input: String in _labels.keys():
		if not texts.has(input) or texts[input] == "":
			_labels.erase(input)
			_print_stale = true
			_texts.erase(input)
			if _debug.has(input):
				(_debug[input] as Node).queue_free()
				_debug.erase(input)
	for input: String in texts:
		var text: String = texts[input]
		if text == "" or not ANCHORS.has(input):
			continue
		if not _labels.has(input):
			_make_label(input)
		_texts[input] = text
	_layout()
	_update_print()
	_apply_visibility()


func uses_fallback_body() -> bool:
	return _body.visible


## Shows our own controller model instead of the hand-built one (desktop, and --controller-model=ours on the
## device): models/controllers/<side>_controller.glb at its pose relative to the aim pose (controllers.json), unlit,
## with the legends printed in its texture. The print meshes stay off: the print is always there, like real print.
## False (and the hand-built body stays) when the files aren't there.
func use_our_model() -> bool:
	var glb := OUR_MODELS.path_join("%s_controller.glb" % side)
	var json_path := OUR_MODELS.path_join("controllers.json")
	if not FileAccess.file_exists(glb) or not FileAccess.file_exists(json_path):
		print("XR %s: our controller model isn't there (%s); hand-built controller" % [side, glb])
		return false
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var bytes := FileAccess.get_file_as_bytes(glb)
	if doc.append_from_buffer(bytes, "", state) != OK:
		print("XR %s: can't read %s; hand-built controller" % [side, glb])
		return false
	_ours = doc.generate_scene(state) as Node3D
	_ours.name = "OurModel"
	var rows: Array = info["sides"][side]["model_in_aim"]
	_ours.transform = Transform3D(Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]),
			Vector3(rows[0][1], rows[1][1], rows[2][1]), Vector3(rows[0][2], rows[1][2], rows[2][2])),
			Vector3(rows[0][3], rows[1][3], rows[2][3]))
	add_child(_ours)
	_ours_material = ShaderMaterial.new()
	_ours_material.shader = MODEL_SHADER
	_ours_material.set_shader_parameter("albedo", Color.WHITE)
	_ours_material.set_shader_parameter("use_texture", true)
	var centre := Vector3.ZERO
	var count := 0
	for mi: MeshInstance3D in _ours.find_children("*", "MeshInstance3D", true, false):
		var src := mi.mesh.surface_get_material(0) as BaseMaterial3D if mi.mesh != null else null
		if src != null and src.albedo_texture != null and not _ours_textures.has("normal"):
			_ours_textures["normal"] = src.albedo_texture
		mi.material_override = _ours_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if match_node_name(str(mi.name)) in FACE_INPUTS or str(mi.name) == "thumbstick":
			centre += _ours.transform * (mi.transform * mi.mesh.get_aabb().get_center())
			count += 1
	for st in ["menu", "window"]:
		var png := OUR_MODELS.path_join("%s_controller_%s.png" % [side, st])
		if FileAccess.file_exists(png):
			var img := Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(png)) == OK:
				img.generate_mipmaps()
				_ours_textures[st] = ImageTexture.create_from_image(img)
	# Mipmapped as the other states are: a look's backing behind the legends reads a coarser level of it.
	var normal := _ours_textures.get("normal") as Texture2D
	if normal != null and normal.get_image() != null and not normal.get_image().has_mipmaps():
		var img := normal.get_image()
		img.generate_mipmaps()
		_ours_textures["normal"] = ImageTexture.create_from_image(img)
	_apply_print_state()
	_setup_animation()
	_body.visible = false
	_apply_look()
	# The face for the snapshot cameras: square to the aim pose's up, centred on the face controls.
	_face_normal = Vector3.UP
	_face_centre = centre / maxf(count, 1)
	_body_centre = _ours.transform * Vector3.ZERO
	_forget_surface()
	_apply_visibility()
	for input: String in _debug:
		(_debug[input] as Node).queue_free()
	_debug.clear()
	print("XR %s: our controller model (%d parts, printed legends: %s)" % [side,
			_ours.find_children("*", "MeshInstance3D", true, false).size(), _ours_textures.keys()])
	return true


func uses_our_model() -> bool:
	return _ours != null


## Which printed legends our model shows: "normal", "menu" (the menu is open) or "window" (a captured window has the
## input). main.gd sets it with the texts.
func set_print_state(state: String) -> void:
	_print_state = state
	_apply_print_state()


func _apply_print_state() -> void:
	if _ours_material != null:
		_ours_material.set_shader_parameter("albedo_texture", _print_texture())
	var look := _look_materials.get("ours") as ShaderMaterial
	if look != null:
		look.set_shader_parameter("print_texture", _print_texture())


## Our model's texture for the print state on show.
func _print_texture() -> Texture2D:
	return _ours_textures.get(_print_state, _ours_textures.get("normal"))


## A runtime render model for this hand appeared (or its scene was reloaded): hide the fallback body, make the model
## unlit, move the labels under it and anchor them to its matching nodes.
func attach_render_model(model: Node3D, tries := 5) -> void:
	_reattach_pending = false
	if not is_instance_valid(model):
		return
	_model_nodes.clear()
	var names: Array[String] = []
	for n in model.find_children("*", "Node3D", true, false):
		if _is_ours(n):
			continue
		names.append(str(n.name))
		var input := match_node_name(str(n.name))
		if input != "" and not _model_nodes.has(input):
			_model_nodes[input] = n
	if names.is_empty() and tries > 0:
		# The runtime may still be loading the model's glTF: look again in a second.
		get_tree().create_timer(1.0).timeout.connect(attach_render_model.bind(model, tries - 1))
		return
	if _model_root != model:
		_model_root = model
		_model_front = Vector3.ZERO
		# The runtime model node adds its glTF scene as a child, and may replace it later: redo all of this then.
		if not model.child_entered_tree.is_connected(_on_model_child_entered):
			model.child_entered_tree.connect(_on_model_child_entered)
	if dump_dir != "" and not _dump_done:
		_dump_done = true
		_dump_later(model)
	_forget_surface()
	if _label_root.get_parent() != model:
		_label_root.reparent(model, false)
		_label_root.transform = Transform3D()
	_make_unlit(model)
	_mark_agent_button()
	_look_materials.erase("runtime")
	_apply_look()
	_body.visible = false
	if _ours != null and _ours.visible:
		_ours.visible = false
		# Its labels are meshes again: the anchor spheres come back with --labels-debug.
		if debug_anchors:
			set_debug_anchors(true)
	print("XR %s render model: %d nodes %s; label anchors from it: %s" % [side, names.size(), names,
			_model_nodes.keys()])
	_layout()
	_update_print()
	_apply_visibility()



## --dump-render-models: the .glb now, with the runtime's own materials (before _make_unlit); the .json 2 s later,
## when the model sits at the hand and the poses are tracked.
func _dump_later(model: Node3D) -> void:
	var copy := RenderModelDump.copy_scene(model, _is_ours)
	RenderModelDump.write_glb(dump_dir, side, copy)
	copy.free()
	var model_id := model.get_instance_id()
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		var live := instance_from_id(model_id) as Node3D
		if live != null:
			RenderModelDump.write_json(dump_dir, side, live, get_parent() as Node3D, _is_ours)
		else:
			print("XR %s render model dump: the model went away before its .json was written" % side))


## The controller's face in global space, for the snapshot cameras: {"centre": face button centre, "normal": out of the
## face, "body_centre"}. Before the first layout: this node's origin and up.
func get_face_frame() -> Dictionary:
	if _face_normal == Vector3.ZERO:
		return {"centre": global_position, "normal": global_basis.y.normalized(), "body_centre": global_position}
	var t := _label_root.global_transform
	return {"centre": t * _face_centre, "normal": (t.basis * _face_normal).normalized(), "body_centre": t * _body_centre}


## Our own label nodes (print meshes, debug spheres) hang under the model too: never take them for parts of it.
func _is_ours(node: Node) -> bool:
	return node == _label_root or _label_root.is_ancestor_of(node) or node.has_meta(&"controller_print")

func _on_model_child_entered(node: Node) -> void:
	if node == _label_root or _reattach_pending:
		return
	_reattach_pending = true
	attach_render_model.call_deferred(_model_root)


## Prints where the labels are, in the model's space and relative to the aim pose (expected: a few cm from it).
func _report_labels() -> void:
	var report := PackedStringArray()
	var to_aim := global_transform.affine_inverse() * _label_root.global_transform
	for input: String in _labels:
		var at: Transform3D = _labels[input].get("transform", Transform3D())
		var anchor: Vector3 = _anchors.get(input, Vector3.ZERO)
		report.append("%s anchor %s text %s" % [input, (to_aim * anchor).snapped(Vector3.ONE * 0.001),
				(to_aim * at.origin).snapped(Vector3.ONE * 0.001)])
	print("XR %s labels (aim space, m): %s" % [side, ", ".join(report)])


## What the print comes to in the eye's image, for judging it on the device: the size of that image is the runtime's
## and sets what any print can resolve. At the centre of the view; a line of print seen square on at arm's length. The
## last line is what tools/label_proof.gd needs to draw the same image on the PC.
func _report_print_size() -> void:
	var xr := XRServer.primary_interface
	if xr == null or not xr.is_initialized():
		return
	var size := xr.get_render_target_size()
	var across := 0.0
	var down := 0.0
	for view in xr.get_view_count():
		var p := xr.get_projection_for_view(view, size.x / size.y, 0.05, 100.0)
		# Tangents of the view's edges, left, right, down, up: the frustum is not centred on the eye.
		var edges := [(p.z.x - 1.0) / p.x.x, (p.z.x + 1.0) / p.x.x, (p.z.y - 1.0) / p.y.y, (p.z.y + 1.0) / p.y.y]
		print("XR view %d tangents (left, right, down, up): %s" % [view, edges])
		across = maxf(across, edges[1] - edges[0])
		down = maxf(down, edges[3] - edges[2])
	var per_degree := size.x / across * PI / 180.0
	var capital := PRINT_LINE / LabelFont.LINE_STEP * LabelFont.CAP_HEIGHT
	print("XR %s print: eye image %s, %.1f pixels per degree at its centre; a %.1f mm capital at 45 cm is %.1f pixels" % [side,
			size, per_degree, capital * 1000.0, rad_to_deg(atan(capital / 0.45)) * per_degree])
	print("XR label proof: --eye=%d --tan=%.3f,%.3f" % [size.x, across, down])


## Adds or removes the 2 mm anchor spheres (--labels-debug).
func set_debug_anchors(on: bool) -> void:
	debug_anchors = on
	if on:
		_report_print_size()
	for input: String in _debug:
		(_debug[input] as Node).queue_free()
	_debug.clear()
	if on:
		for input: String in _labels:
			_add_debug_sphere(input)
		_layout()


## The runtime model's glTF materials are lit PBR, black without lights: swap each for controller_model.gdshader with
## the same base colour, texture, vertex colours and emission, the plastic black and the buttons' moulded art white. Shared materials are converted once. Runs once per
## model; the runtime only moves the nodes afterwards (buttons, stick and trigger animate as before).
func _make_unlit(model: Node3D) -> void:
	var converted := {}
	var count := 0
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		if _is_ours(mi):
			continue
		if mi.mesh == null:
			continue
		# A look on the shell stays (_apply_look() sets it again); its own surfaces are made unlit under it.
		if mi.material_override != null and not mi.material_override.has_meta(&"controller_look"):
			mi.material_override = _unlit(mi.material_override, converted, str(mi.name) in INK_PARTS)
		else:
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i)
				if src != null:
					mi.set_surface_override_material(i, _unlit(src, converted, str(mi.name) in INK_PARTS))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		count += 1
	print("XR %s render model: %d mesh instances, %d materials made unlit" % [side, count, converted.size()])


## Once per model: the A, B, X and Y caps' own copies of their material, each with its picture (MARKS). The other parts
## keep theirs.
func _mark_agent_button() -> void:
	if side != "right":
		return
	for input: String in MARKS:
		var cap: MeshInstance3D = _model_nodes.get(input) as MeshInstance3D
		if cap == null or cap.mesh == null:
			continue
		var mat := cap.get_active_material(0) as ShaderMaterial
		if mat == null or mat.get_shader_parameter("use_mark") == true:
			continue
		var known: Rect2 = MARKS[input]["uvs"]
		var range := Rect2(mesh_uvs(cap)[0], Vector2.ZERO)
		for uv in mesh_uvs(cap):
			range = range.expand(uv)
		if not range.grow(0.002).encloses(known) or not known.grow(0.002).encloses(range):
			print("XR right render model: the %s cap's atlas is not the one we know (%s): it keeps its letter"
					% [input.to_upper(), range])
			continue
		var marked := mat.duplicate() as ShaderMaterial
		marked.set_shader_parameter("use_mark", true)
		marked.set_shader_parameter("mark_kind", int(MARKS[input]["kind"]))
		marked.set_shader_parameter("mark_centre", MARKS[input]["centre"])
		marked.set_shader_parameter("mark_right", MARKS[input]["right"])
		marked.set_shader_parameter("mark_mm_per_uv", MARK_MM_PER_UV)
		marked.set_shader_parameter("mark_erase_mm", MARK_ERASE_MM)
		marked.set_shader_parameter("mark_cap", MARK_CAP)
		if cap.material_override != null:
			cap.material_override = marked
		else:
			cap.set_surface_override_material(0, marked)


static func mesh_uvs(mi: MeshInstance3D) -> PackedVector2Array:
	return mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]


func _unlit(src: Material, converted: Dictionary, ink: bool) -> Material:
	if src is ShaderMaterial and (src as ShaderMaterial).shader == MODEL_SHADER:
		return src
	if converted.has(src):
		return converted[src]
	var mat := ShaderMaterial.new()
	mat.shader = MODEL_SHADER
	mat.set_shader_parameter("lift", BLACK_LIFT)
	mat.set_shader_parameter("rim_gain", BLACK_RIM)
	mat.set_shader_parameter("sheen", BLACK_SHEEN)
	mat.set_shader_parameter("use_ink", ink)
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		mat.set_shader_parameter("albedo", b.albedo_color)
		if b.albedo_texture != null:
			mat.set_shader_parameter("albedo_texture", b.albedo_texture)
			mat.set_shader_parameter("use_texture", true)
		mat.set_shader_parameter("use_vertex_color", b.vertex_color_use_as_albedo)
		if b.emission_enabled:
			mat.set_shader_parameter("emission", b.emission * b.emission_energy_multiplier)
	converted[src] = mat
	return mat


## The runtime model is about to go: labels back under this node, the hand-built body back on.
func detach_render_model() -> void:
	_body.visible = _ours == null
	if _ours != null:
		_ours.visible = true
	_model_nodes.clear()
	if _model_root != null and is_instance_valid(_model_root) \
			and _model_root.child_entered_tree.is_connected(_on_model_child_entered):
		_model_root.child_entered_tree.disconnect(_on_model_child_entered)
	_model_root = null
	_model_front = Vector3.ZERO
	_forget_surface()
	if _label_root.get_parent() != self:
		_label_root.reparent(self, false)
		_label_root.transform = Transform3D()
	_layout()
	_update_print()
	_apply_visibility()


static func match_node_name(node_name: String) -> String:
	var words := PackedStringArray()
	# Words: snake_case, kebab, dots and camelCase ("AButton" -> a, button).
	var re := RegEx.create_from_string("[A-Z]?[a-z]+|[A-Z]+(?![a-z])")
	for m in re.search_all(node_name):
		words.append(m.get_string().to_lower())
	var joined := "".join(words)
	for input: String in NODE_WORDS:
		for w: String in NODE_WORDS[input]:
			if w in words or (w.begins_with("dpad") and w != "dpad" and joined.contains(w)):
				return input
	# Face buttons: "button_a", "a_button", "abutton", or just "a".
	for letter: String in ["a", "b", "x", "y"]:
		if (letter in words and ("button" in words or words.size() == 1)) or joined == letter + "button" \
				or joined == "button" + letter:
			return letter
	return ""




## The model's aim direction isn't known yet (its pose wasn't consistent with the hand's): look again in a moment, until
## it is, once per model.
func _on_front_timer() -> void:
	_front_timer = false
	if _waiting_for_front():
		_layout()
		_update_print()
	_watch_front()


func _watch_front() -> void:
	if not _front_timer and _waiting_for_front() and is_inside_tree():
		_front_timer = true
		get_tree().create_timer(0.5).timeout.connect(_on_front_timer)


func _waiting_for_front() -> bool:
	return _shown and _model_front == Vector3.ZERO and _model_root != null and is_instance_valid(_model_root)


func _apply_visibility() -> void:
	# Our model has the legends printed: no print meshes on it.
	var shown := not _labels.is_empty() and (_ours == null or not _ours.visible)
	var showing := shown and not _shown
	_shown = shown
	if showing:
		_layout()  # Where the model's nodes are now.
		_update_print()
	for mesh: MeshInstance3D in _print.values():
		if is_instance_valid(mesh):
			mesh.visible = _shown
	_watch_front()


# --- Placement ----------------------------------------------------------------------------------------------------

## Places every label: a rectangle on the surface next to its control, oriented with the surface.
func _layout() -> void:
	if _labels.is_empty():
		return
	var model := _model_root != null and is_instance_valid(_model_root) and not _model_nodes.is_empty()
	# Everything below is in the label root's space: the runtime model's own space, or this node's (the fallback).
	# Positions within the model are consistent whatever its parents do in this frame.
	_space = _label_root.global_transform.affine_inverse()
	# Face plane: fitted through the face buttons.
	var face_points: Array[Vector3] = []
	for input: String in FACE_INPUTS:
		if model and _model_nodes.has(input):
			face_points.append(_center(_model_nodes[input]))
		elif not model and ANCHORS.has(input) and input not in ["dpad_up", "dpad_down", "dpad_left", "dpad_right"]:
			face_points.append(_m(ANCHORS[input]))
	var centroid := Vector3.ZERO
	for p in face_points:
		centroid += p
	centroid /= maxf(face_points.size(), 1)
	var body := _corners(_model_nodes["body"]) if model and _model_nodes.has("body") else \
			(_corners(_model_root) if model else _aabb_corners(_body.get_aabb(), Transform3D()))
	var body_center := Vector3.ZERO
	for p in body:
		body_center += p
	body_center /= maxf(body.size(), 1)
	var n := Vector3.UP
	if model:
		n = _plane_normal(face_points, n)
		if n.dot(centroid - body_center) < 0.0:
			n = -n
	_face_centre = centroid
	_face_normal = n
	_body_centre = body_center
	# Front: the aim direction laid onto the face (the menu and system buttons are not in line front to back, so
	# they would skew the text). For the model, the aim direction in its space is taken once the model sits where
	# the hand is (on the first tracked frame it may not yet); until then, from the body towards the face centre.
	var front := Vector3.FORWARD
	if model:
		if _model_front == Vector3.ZERO and (_space * global_position).length() < 0.3:
			_model_front = (_space.basis * -global_basis.z).normalized()
			_layout_labels(n, centroid, body, model)
			_report_labels()
			return
		front = _model_front if _model_front != Vector3.ZERO else centroid - body_center
	_layout_labels(n, centroid, body, model, front)


func _layout_labels(n: Vector3, centroid: Vector3, body: Array[Vector3], model: bool, front := Vector3.ZERO) -> void:
	if front == Vector3.ZERO:
		front = _model_front
	var raw := front.length()
	front = front - n * front.dot(n)
	if raw < 1e-6 or front.length() < 0.2 * raw:
		# The face stands edge-on to it: the face's own "up" instead.
		front = Vector3.UP - n * Vector3.UP.dot(n)
	front = front.normalized()
	var right := front.cross(n)
	var outer := right * _sign
	var dirs := {"outer": outer, "inner": -outer, "front": front, "back": -front}
	for input: String in _labels:
		var label: Dictionary = _labels[input]
		var entry := layout_entry(side, input) if model and use_layout else {}
		if not entry.is_empty():
			# Authored offline in the model's own space, which is the label root's space here.
			var xf: Transform3D = entry["transform"]
			label["transform"] = xf
			label["size"] = LabelLayout.print_size(entry, _texts.get(input, ""))
			label["line"] = LabelLayout.fitted_line(entry, _texts.get(input, ""))
			_anchors[input] = xf.origin
			if _debug.has(input):
				(_debug[input] as MeshInstance3D).position = xf.origin
			continue
		var place: Array = PLACEMENT.get(input, ["face", "outer"])
		var d: Vector3 = dirs[place[1]]
		var anchor := _anchor(input)
		var printed := LabelLayout.print_size({"line_height": PRINT_LINE}, _texts.get(input, ""))
		var size := Vector2(printed.x, printed.z)
		var x: Vector3
		var y: Vector3
		var center: Vector3
		var depth := PRINT_DEPTH
		if place[0] == "face":
			# On the face plate: the control's centre laid onto the face plane, then past its edge along d.
			anchor = anchor - n * (anchor - centroid).dot(n)
			var radius: float = RADII.get(input, 0.004)
			if model and _model_nodes.has(input):
				radius = clampf(_extent(_corners(_model_nodes[input]), anchor, d), 0.002, 0.03)
			var half := size.x * 0.5 if absf(d.dot(right)) > 0.5 else size.y * 0.5
			x = right
			y = n
			center = anchor + d * (radius + GAP + half)
		else:
			# On the side wall at the control, the text running back from it along the wall. The body's bounds
			# overstate where the wall is (the head is wider than the handle, the oval narrows at the front), so the
			# print looks WALL_REACH in from the bounds; only surfaces facing out along d take it.
			x = n.cross(d)
			y = d
			depth = WALL_REACH + 0.005
			center = anchor + d * (maxf(_extent(body, anchor, d), 0.0) + 0.005 - depth * 0.5) \
					- front * (size.x * 0.5 - 0.004)
		# The print finds the surface along Y; the text runs along +X and down along +Z.
		var z := x.cross(y)
		label["transform"] = Transform3D(Basis(x, y, z), center)
		label["size"] = Vector3(size.x, depth, size.y)
		label["line"] = PRINT_LINE
		_anchors[input] = anchor
		if _debug.has(input):
			var sphere: MeshInstance3D = _debug[input]
			sphere.position = anchor
			# Pink: on the face plate. Cyan: the trigger, bumper and grip (under the head or on the handle, drawn through).
			(sphere.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.2, 0.6) if place[0] == "face" \
					else Color(0.2, 0.9, 1.0)


## The authored layout's entry for an input, or {} (no layout file, or the input isn't in it).
static func layout_entry(p_side: String, input: String) -> Dictionary:
	if not _layout_loaded:
		_layout_loaded = true
		if ResourceLoader.exists(LAYOUT_PATH):
			_layout_res = load(LAYOUT_PATH) as LabelLayout
		print("Controller label layout: %s" % ("%s, %d legends" % [LAYOUT_PATH, _layout_res.entries.size()]
				if _layout_res != null else "none (placement computed from the model)"))
	return _layout_res.find(p_side, input) if _layout_res != null else {}


# --- Print -------------------------------------------------------------------------------------------------------

## Builds the print of what changed. Each legend is laid once per place and text; the parts whose legends changed get a
## new mesh. Nothing happens while our own model shows, which has the legends in its texture.
func _update_print() -> void:
	if not _shown:
		return
	if _surface == null:
		_surface = _read_surface()
	var changed := _print_stale
	_print_stale = false
	for input: String in _labels:
		var label: Dictionary = _labels[input]
		if not label.has("transform"):
			continue
		var at: Transform3D = label["transform"]
		var key := "%s|%s|%s|%s" % [_texts.get(input, ""), at.origin.snapped(Vector3.ONE * 0.0001), at.basis.y.snapped(
				Vector3.ONE * 0.001), label["line"]]
		if label.get("key", "") == key:
			continue
		label["key"] = key
		changed = true
		if not _laid.has(key):
			var shaped := LabelFont.shape(_texts.get(input, ""))
			_laid[key] = _surface.lay(at, label["size"], shaped["quads"], LabelLayout.metres_per_em(label["line"]))
		label["laid"] = _laid[key]
	if changed:
		_rebuild_print()


## part -> the laid legends on it.
func _print_parts() -> Dictionary:
	var parts := {}
	for input: String in _labels:
		var laid: Dictionary = _labels[input].get("laid", {})
		if not laid.is_empty():
			if not parts.has(laid["node"]):
				parts[laid["node"]] = []
			(parts[laid["node"]] as Array).append(laid)
	return parts


func _rebuild_print() -> void:
	# A glyph new to the atlas reaches the GPU here.
	LabelFont.texture()
	var parts := _print_parts()
	for part: Variant in _print.keys():
		if not is_instance_valid(part) or not parts.has(part):
			if is_instance_valid(_print[part]):
				(_print[part] as Node).queue_free()
			_print.erase(part)
	for part: MeshInstance3D in parts:
		if not _print.has(part):
			var mesh := MeshInstance3D.new()
			mesh.name = "Print"
			mesh.set_meta(&"controller_print", true)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.material_override = _print_material_for(part)
			mesh.visible = _shown
			part.add_child(mesh)
			_print[part] = mesh
		(_print[part] as MeshInstance3D).mesh = _surface.mesh_for(part, parts[part])


static func _label_material() -> ShaderMaterial:
	if _print_material == null:
		_print_material = ShaderMaterial.new()
		_print_material.shader = LABEL_SHADER
		_print_material.set_shader_parameter("atlas", LabelFont.texture())
		_print_material.set_shader_parameter("field_range", float(LabelFont.FIELD_RANGE))
		_print_material.set_shader_parameter("atlas_span", float(LabelFont.ATLAS_SPAN))
	return _print_material


## The print on a part: on a shell with a look, in the look's ink with its backing; elsewhere white, as always.
func _print_material_for(part: Node) -> ShaderMaterial:
	if _look_id == ControllerLook.DEFAULT or not _is_shell(part):
		return _label_material()
	if _look_print_material == null:
		_look_print_material = _label_material().duplicate() as ShaderMaterial
	var style := ControllerLook.print_style(_look_id, _look_options)
	_look_print_material.set_shader_parameter("ink", style["ink"])
	_look_print_material.set_shader_parameter("backing", style["backing"])
	_look_print_material.set_shader_parameter("backing_width",
			ControllerLook.BACKING_WIDTH if bool(style["backing_on"]) else 0.0)
	return _look_print_material


# --- Look --------------------------------------------------------------------------------------------------------

## The controllers' look (controller_look.gd; main.gd sets the same on both hands): its shell materials go on our
## model's, the runtime model's and the hand-built body's shell, and the print on them takes the look's ink. The
## default puts the models' own materials back. Nothing runs per frame for it.
func set_look(id: String, options := {}) -> void:
	if not ControllerLook.has(id):
		id = ControllerLook.DEFAULT
	_look_id = id
	_look_options = options.duplicate(true)
	_look_materials.clear()
	_apply_look()
	for part: Variant in _print:
		if is_instance_valid(part) and is_instance_valid(_print[part]):
			(_print[part] as MeshInstance3D).material_override = _print_material_for(part)


func look() -> Dictionary:
	return {"id": _look_id, "options": _look_options.duplicate(true)}


func _apply_look() -> void:
	if _ours != null:
		for mi in _shell_meshes(_ours):
			var m := _look_material("ours", mi)
			mi.material_override = m if m != null else _ours_material
	if _model_root != null and is_instance_valid(_model_root):
		for mi in _shell_meshes(_model_root):
			# The model's own override (or none), kept to go back to; an Array, as a null meta would be no meta.
			if not mi.has_meta(&"look_restore"):
				mi.set_meta(&"look_restore", [mi.material_override])
			var m := _look_material("runtime", mi)
			mi.material_override = m if m != null else (mi.get_meta(&"look_restore") as Array)[0]
	if _body != null:
		var m := _look_material("fallback", _body)
		_body.material_override = m if m != null else _fallback_material


## A target's shell material for the look on show, made once (null: the default).
func _look_material(target: String, mi: MeshInstance3D) -> ShaderMaterial:
	if _look_id == ControllerLook.DEFAULT:
		return null
	if not _look_materials.has(target):
		_look_materials[target] = ControllerLook.material(_look_id, _look_options, target,
				_print_texture() if target == "ours" else null, _metres_per_unit(mi), EffectLibrary.seed_of(side))
	return _look_materials[target]


## The shell's meshes under a model: those whose node, or a node above it in the model, is named as a shell part.
func _shell_meshes(top: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in top.find_children("*", "MeshInstance3D", true, false):
		if not _is_ours(mi) and mi.mesh != null and _is_shell(mi):
			out.append(mi)
	return out


## Whether a part is the shell: the hand-built body, or a node of a model named as a shell part (or under one).
func _is_shell(part: Node) -> bool:
	if part == _body:
		return true
	var n: Node = part
	while n != null and n != _model_root and n != _ours and n != self:
		if str(n.name).to_lower() in SHELL_PARTS:
			return true
		n = n.get_parent()
	return false


## Metres per unit of a mesh's own space (1 unless a model scales its parts), so a look's sizes stay in metres.
func _metres_per_unit(mi: Node3D) -> float:
	if mi == null or not mi.is_inside_tree() or not is_inside_tree():
		return 1.0
	var s := mi.global_basis.get_scale().x / maxf(global_basis.get_scale().x, 1e-6)
	return s if absf(s - 1.0) > 0.01 else 1.0


## The triangles the print lies on: the runtime model's parts (hidden ones are not there to print on), or the hand-built
## body, in the label root's space, in the pose they have now.
func _read_surface() -> LabelSurface:
	var surface := LabelSurface.new()
	var to_root := _label_root.global_transform.affine_inverse()
	var model := _model_root != null and is_instance_valid(_model_root) and not _model_nodes.is_empty()
	var meshes: Array = _model_root.find_children("*", "MeshInstance3D", true, false) if model else [_body]
	for mi: MeshInstance3D in meshes:
		if not _is_ours(mi) and _shown_in(mi, _model_root if model else self):
			surface.add_part(mi, to_root * mi.global_transform)
	return surface


## Whether nothing up to `top` hides the node (whatever hides the hand itself until it is tracked).
static func _shown_in(node: Node3D, top: Node) -> bool:
	var n: Node = node
	while n != null and n != top:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## The model changed: its triangles and everything laid on them go, and the print with them.
func _forget_surface() -> void:
	_surface = null
	_laid.clear()
	for input: String in _labels:
		(_labels[input] as Dictionary).erase("key")
		(_labels[input] as Dictionary).erase("laid")
	for mesh: Variant in _print.values():
		if is_instance_valid(mesh):
			(mesh as Node).queue_free()
	_print.clear()


func _make_label(input: String) -> void:
	_labels[input] = {}
	if debug_anchors:
		_add_debug_sphere(input)


func _add_debug_sphere(input: String) -> void:
	# Our model's legends are in its texture, not placed: no anchors to show on it.
	if _ours != null and _ours.visible:
		return
	var sphere := MeshInstance3D.new()
	sphere.name = "Anchor_" + input
	var mesh := SphereMesh.new()
	mesh.radius = DEBUG_RADIUS
	mesh.height = DEBUG_RADIUS * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.2, 0.6)
	mat.no_depth_test = true
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label_root.add_child(sphere)
	_debug[input] = sphere


func _anchor(input: String) -> Vector3:
	var node: Node3D = _model_nodes.get(input)
	if node != null and is_instance_valid(node):
		return _center(node)
	return _m(ANCHORS[input])


## The centre of a node's meshes' bounds, in the label root's space (_space); its origin if it has no meshes.
func _center(node: Node3D) -> Vector3:
	var corners := _corners(node)
	if corners.is_empty():
		return _space * node.global_position
	var box := AABB(corners[0], Vector3.ZERO)
	for p in corners:
		box = box.expand(p)
	return box.get_center()


## Bounding-box corners of a node's meshes (itself and below), in the label root's space (_space).
func _corners(node: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if node == null or not is_instance_valid(node):
		return out
	var to_here := _space
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi: MeshInstance3D in meshes:
		if _is_ours(mi):
			continue
		if mi.mesh != null:
			out.append_array(_aabb_corners(mi.get_aabb(), to_here * mi.global_transform))
	return out


static func _aabb_corners(box: AABB, xform: Transform3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(xform * box.get_endpoint(i))
	return out


## How far `points` reach from `from` along `dir`.
static func _extent(points: Array[Vector3], from: Vector3, dir: Vector3) -> float:
	var best := 0.0
	for p in points:
		best = maxf(best, (p - from).dot(dir))
	return best


## Normal of the plane through `points` (the widest triangle among them), or `fallback` with fewer than 3.
static func _plane_normal(points: Array[Vector3], fallback: Vector3) -> Vector3:
	var best := Vector3.ZERO
	for i in points.size():
		for j in range(i + 1, points.size()):
			for k in range(j + 1, points.size()):
				var c := (points[j] - points[i]).cross(points[k] - points[i])
				if c.length() > best.length():
					best = c
	return best.normalized() if best.length() > 1e-8 else fallback




# --- Fallback body ----------------------------------------------------------------------------------------------

## One mesh, vertex colours with baked shading (light from above-front), so an unshaded material reads as 3D.
## Layout from the maker's drawing: an oval face (65 x 60 mm) with the thumbstick on the inner side, A/B/X/Y (right) or
## the d-pad (left) on the outer side, menu / view near the front edge, the system button behind the face buttons;
## bumper above the trigger at the front of the head; the handle below and behind, with the grip button on its inner
## side just under the head.
func _build_body() -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	_normals = PackedVector3Array()
	var indices := PackedInt32Array()
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-HANDLE_TILT))
	var handle_dir := Vector3(0.0, -cos(deg_to_rad(HANDLE_TILT)), sin(deg_to_rad(HANDLE_TILT)))
	# Head: an oval disc, top face at y = 0.
	_add_cylinder(verts, colors, indices, 1.0, 0.026, _m(Vector3(0, -0.013, 0)), BODY_COLOR, Vector3(0.0324, 1, 0.030), 20)
	# Handle, slightly to the outer side, and the grip button on its inner side.
	_add_box(verts, colors, indices, Vector3(0.028, 0.08, 0.03),
			Transform3D(tilt, _m(Vector3(0.01, -0.02, 0.02) + handle_dir * 0.04)), BODY_COLOR)
	_add_box(verts, colors, indices, Vector3(0.006, 0.02, 0.012), Transform3D(tilt, _m(Vector3(-0.005, -0.035, 0.03))),
			PART_COLOR)
	# Trigger and bumper at the front.
	_add_box(verts, colors, indices, Vector3(0.02, 0.016, 0.012),
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-20.0)), _m(Vector3(0, -0.024, -0.026))), PART_COLOR)
	_add_box(verts, colors, indices, Vector3(0.026, 0.006, 0.01), Transform3D(Basis(), _m(Vector3(0, -0.007, -0.031))),
			PART_COLOR)
	# Thumbstick: post and cap.
	_add_cylinder(verts, colors, indices, 0.004, 0.008, _m(Vector3(-0.0123, 0.004, 0.0071)), PART_COLOR)
	_add_cylinder(verts, colors, indices, 0.0087, 0.004, _m(Vector3(-0.0123, 0.009, 0.0071)), ACCENT_COLOR)
	if side == "right":
		for input: String in ["a", "b", "x", "y"]:
			var p: Vector3 = ANCHORS[input]
			_add_cylinder(verts, colors, indices, 0.0042, 0.003, _m(Vector3(p.x, 0.0015, p.z)), ACCENT_COLOR)
	else:
		_add_box(verts, colors, indices, Vector3(0.022, 0.003, 0.007), Transform3D(Basis(), _m(Vector3(0.013, 0.0015, -0.0036))),
				ACCENT_COLOR)
		_add_box(verts, colors, indices, Vector3(0.007, 0.003, 0.022), Transform3D(Basis(), _m(Vector3(0.013, 0.0015, -0.0036))),
				ACCENT_COLOR)
	# Menu (right) / view (left) and the system button.
	_add_box(verts, colors, indices, Vector3(0.007, 0.002, 0.0026), Transform3D(Basis(), _m(Vector3(-0.0028, 0.001, -0.0135))),
			ACCENT_COLOR)
	_add_cylinder(verts, colors, indices, 0.0038, 0.002, _m(Vector3(0.0054, 0.001, 0.0151)), PART_COLOR)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Right-controller coordinates to this side's.
func _m(p: Vector3) -> Vector3:
	return Vector3(p.x * _sign, p.y, p.z)


func _append(verts: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, src: Array,
		xform: Transform3D, color: Color) -> void:
	var base := verts.size()
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var light := Vector3(0.3, 1.0, -0.5).normalized()
	for i in sv.size():
		verts.append(xform * sv[i])
		var n := (xform.basis * sn[i]).normalized()
		colors.append(color * (0.55 + 0.45 * maxf(n.dot(light), 0.0)))
		_normals.append(n)
	for idx in (src[Mesh.ARRAY_INDEX] as PackedInt32Array):
		indices.append(base + idx)


func _add_box(verts: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, size: Vector3,
		xform: Transform3D, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	_append(verts, colors, indices, box.get_mesh_arrays(), xform, color)


func _add_cylinder(verts: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, radius: float,
		height: float, pos: Vector3, color: Color, scale := Vector3.ONE, segments := 12) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	_append(verts, colors, indices, c.get_mesh_arrays(), Transform3D(Basis.from_scale(scale), pos), color)


# --- Our model's moving parts -------------------------------------------------------------------------------------
#
# The runtime's model moves its parts from the device's input state. Ours has the same parts as separate meshes in
# model space, so it moves them from the actions the hand reads: the trigger turns about a hinge at its top, the grip
# button moves in toward the body with the squeeze, the stick tilts about a point under the face and sinks on a click,
# and buttons sink on a press. Pivots and directions come from each part's own vertices, with the face normal of the
# runtime model's frame (FACE_NORMAL_MODEL). Ranges are guesses until compared with the runtime's model on the device.
# Buttons move only when an action is bound to them (X, Y and the d-pad have none in the shipped map).

const FACE_NORMAL_MODEL := Vector3(0.0, 0.766, -0.643)
const FACE_FORWARD_MODEL := Vector3(0.0, -0.643, -0.766)
const BUTTON_TRAVEL := 0.0012
const STICK_CLICK_TRAVEL := 0.001
const STICK_TILT := deg_to_rad(18.0)
## The stick turns about a point this far under the bottom of its mesh.
const STICK_PIVOT_DEPTH := 0.006
const TRIGGER_TRAVEL := deg_to_rad(16.0)
const GRIP_TRAVEL := 0.0015
## The sparkle on the right controller's Y cap, for what Y does there (scripts/agents/local_agents.gd). The moulded letter
## is in the atlas, so controller_model.gdshader paints it out: no texture, mesh or draw call of its own, it moves with the
## cap and nothing runs for it per frame. These are the headset's model: the letter's centre in the atlas, in texels of
## 2048, the atlas's scale, how far from the centre to paint (the cap's flat top, past the letter, so a smaller mip of
## the letter does not ring it), and the cap's colour there. Its own colours are in the shader. MARK_Y_UVS, the Y mesh's
## whole UV range, tells that this is that model: another atlas keeps its Y.
const MARK_CENTRE_UV := Vector2(1728.0, 1556.5) / 2048.0
const MARK_MM_PER_UV := 108.2
const MARK_ERASE_MM := 3.9
const MARK_CAP := Color(0.067, 0.071, 0.071)
const MARK_Y_UVS := Rect2(0.6993, 0.6355, 0.1855, 0.26)
## The pictures on the right controller's caps, for what the buttons always do (docs/dev/surfaces-design.md): Y the sparkle
## (AI), A play and pause, B a keyboard (its tap; its hold is in print above it), X an eye (the UI shown or hidden). "kind":
## the picture in controller_model.gdshader; "centre": the moulded letter's centre in the atlas; "right": the way the
## letter's right lies there, measured from the model (each letter lies its own way); "uvs": the cap mesh's whole UV
## range, which tells that this is the model we know.
const MARKS := {
	"y": {"kind": 0, "centre": MARK_CENTRE_UV, "right": Vector2(0.0, 1.0), "uvs": MARK_Y_UVS},
	"a": {"kind": 1, "centre": Vector2(1729.0, 1746.0) / 2048.0, "right": Vector2(0.0, -1.0),
			"uvs": Rect2(0.6794, 0.028, 0.2056, 0.8675)},
	"b": {"kind": 2, "centre": Vector2(1749.5, 1944.5) / 2048.0, "right": Vector2(1.0, 0.0),
			"uvs": Rect2(0.7465, 0.0093, 0.1506, 0.9832)},
	"x": {"kind": 3, "centre": Vector2(1830.5, 1394.5) / 2048.0, "right": Vector2(1.0, 0.0),
			"uvs": Rect2(0.0174, 0.3409, 0.9193, 0.3828)},
}
## Part name -> input name (as in the profile bindings).
const PART_INPUTS := {"button_a": "a", "button_b": "b", "button_x": "x", "button_y": "y", "button_menu": "menu",
		"button_view": "view", "button_system": "system", "dpad": "dpad"}


## Records each moving part's rest pose and works out its pivot or travel direction.
func _setup_animation() -> void:
	_moving.clear()
	if _ours == null:
		return
	var body_centre := Vector3.ZERO
	var parts := {}
	for mi: MeshInstance3D in _ours.find_children("*", "MeshInstance3D", true, false):
		var in_model := _in_model(mi)
		parts[str(mi.name)] = [mi, in_model]
		if str(mi.name) == "body" and mi.mesh != null:
			body_centre = in_model * mi.mesh.get_aabb().get_center()
	for part_name: String in parts:
		var mi: MeshInstance3D = parts[part_name][0]
		var in_model: Transform3D = parts[part_name][1]
		if mi.mesh == null:
			continue
		var entry := {"node": mi, "rest": in_model, "parent": in_model * mi.transform.affine_inverse()}
		var points := _model_points(mi, in_model)
		if points.is_empty():
			continue
		var centre := Vector3.ZERO
		for v in points:
			centre += v
		centre /= points.size()
		match part_name:
			"trigger":
				# The hinge: the trigger's top (furthest along the face normal), turning about the model's X axis. The
				# sign makes the lowest point move back, toward the grip.
				var top := points[0]
				var bottom := points[0]
				for v in points:
					if v.dot(FACE_NORMAL_MODEL) > top.dot(FACE_NORMAL_MODEL):
						top = v
					if v.dot(FACE_NORMAL_MODEL) < bottom.dot(FACE_NORMAL_MODEL):
						bottom = v
				var hinge := Vector3(centre.x, top.y, top.z)
				var turned := hinge + Basis(Vector3.RIGHT, 0.2) * (bottom - hinge)
				var sign := 1.0 if (turned - bottom).dot(FACE_FORWARD_MODEL) < 0.0 else -1.0
				entry.merge({"kind": "trigger", "pivot": hinge, "axis": Vector3.RIGHT * sign})
			"thumbstick":
				var low := INF
				for v in points:
					low = minf(low, v.dot(FACE_NORMAL_MODEL))
				var pivot := centre + FACE_NORMAL_MODEL * (low - centre.dot(FACE_NORMAL_MODEL) - STICK_PIVOT_DEPTH)
				entry.merge({"kind": "stick", "pivot": pivot})
			"button_grip":
				var inward := (body_centre - centre)
				inward -= FACE_NORMAL_MODEL * inward.dot(FACE_NORMAL_MODEL) * 0.5
				entry.merge({"kind": "grip", "dir": inward.normalized()})
			_:
				if PART_INPUTS.has(part_name):
					entry.merge({"kind": "button", "input": PART_INPUTS[part_name]})
				else:
					continue
		_moving[part_name] = entry


## A part's pose in the model's space (_ours' local space).
func _in_model(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != _ours:
		t = (p as Node3D).transform * t if p is Node3D else t
		p = p.get_parent()
	return t


## A part's vertices in model space (every 4th, enough for extents).
static func _model_points(mi: MeshInstance3D, in_model: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(0, verts.size(), 4):
			out.append(in_model * verts[i])
	return out


## Input name -> action from the bound profile's bindings ([input, action, is_click], main._profile_bindings()).
func set_input_bindings(bindings: Array) -> void:
	_button_actions.clear()
	_stick_click_action = ""
	for b: Array in bindings:
		var input := str(b[0])
		if input == "thumbstick" and bool(b[2]):
			_stick_click_action = str(b[1])
		elif input.begins_with("dpad"):
			_button_actions["dpad"] = str(b[1])
		elif not input in ["thumbstick", "trigger", "squeeze"]:
			_button_actions[input] = str(b[1])


## Reads the hand's actions and poses the parts (XRHand calls this each frame while our model shows).
func animate_from(hand: XRController3D) -> void:
	if _moving.is_empty() or _ours == null or not _ours.visible:
		return
	var pressed := {}
	for input: String in _button_actions:
		pressed[input] = hand.is_button_pressed(_button_actions[input])
	pose_inputs({"trigger": hand.get_float(&"trigger"), "squeeze": hand.get_float(&"squeeze"),
			"thumbstick": hand.get_vector2(&"thumbstick"),
			"stick_click": _stick_click_action != "" and hand.is_button_pressed(_stick_click_action), "pressed": pressed})


## Poses the moving parts from an input state: {trigger: 0..1, squeeze: 0..1, thumbstick: Vector2, stick_click: bool,
## pressed: {input: bool}}. Missing keys mean at rest.
func pose_inputs(state: Dictionary) -> void:
	for part_name: String in _moving:
		var e: Dictionary = _moving[part_name]
		var motion := Transform3D()
		match e["kind"]:
			"trigger":
				var pivot: Vector3 = e["pivot"]
				var angle := clampf(float(state.get("trigger", 0.0)), 0.0, 1.0) * TRIGGER_TRAVEL
				motion = Transform3D(Basis(e["axis"], angle), pivot - Basis(e["axis"], angle) * pivot)
			"stick":
				var stick: Vector2 = state.get("thumbstick", Vector2.ZERO)
				stick = stick.limit_length(1.0)
				var dir := Vector3.RIGHT * stick.x + FACE_FORWARD_MODEL * stick.y
				var pivot: Vector3 = e["pivot"]
				if dir.length() > 0.01:
					var axis := FACE_NORMAL_MODEL.cross(dir).normalized()
					var b := Basis(axis, stick.length() * STICK_TILT)
					motion = Transform3D(b, pivot - b * pivot)
				if bool(state.get("stick_click", false)):
					motion = Transform3D(Basis(), -FACE_NORMAL_MODEL * STICK_CLICK_TRAVEL) * motion
			"grip":
				motion = Transform3D(Basis(), (e["dir"] as Vector3) * GRIP_TRAVEL
						* clampf(float(state.get("squeeze", 0.0)), 0.0, 1.0))
			"button":
				if bool((state.get("pressed", {}) as Dictionary).get(e["input"], false)):
					motion = Transform3D(Basis(), -FACE_NORMAL_MODEL * BUTTON_TRAVEL)
		var node: MeshInstance3D = e["node"]
		node.transform = (e["parent"] as Transform3D).affine_inverse() * motion * (e["rest"] as Transform3D)


## What is printed now, for tools/label_proof.gd: [{"input", "text", "line", "size", "laid", "to_global", "control": the
## centre of the input's meshes in the label root's space}].
func printed_legends() -> Array:
	var out := []
	_space = _label_root.global_transform.affine_inverse()
	for input: String in _labels:
		var label: Dictionary = _labels[input]
		var laid: Dictionary = label.get("laid", {})
		if not laid.is_empty():
			out.append({"input": input, "text": _texts.get(input, ""), "line": label["line"], "size": label["size"], "laid": laid,
					"to_global": _label_root.global_transform, "control": _anchor(input)})
	return out


## The moving parts' names and kinds (tests).
func moving_parts() -> Dictionary:
	var out := {}
	for part_name: String in _moving:
		out[part_name] = _moving[part_name]["kind"]
	return out
