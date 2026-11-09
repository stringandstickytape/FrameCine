extends Node3D

## Label layout tool (tools/label_layout.tscn): places our printed legends on a controller model and saves them as
## xr/controller_labels_layout.tres (scripts/xr/label_layout.gd), which the app applies to the runtime model.
## The model is the runtime's own, dumped on the device with --dump-render-models into app/docs/reference-models/
## (gitignored: Valve's asset). <side>_controller.json gives the aim pose, so "forward" is the controller's aim.
##
##   godot --path app res://tools/label_layout.tscn -- [--model-dir=DIR] [--side=right|left] [--auto] [--save]
##                                                     [--render=DIR] [--quit]
##   --auto     lay out every legend by rule, for both sides
##   --place-x  lay out X's legend alone (ENTER, while an agent's terminal shows), clear of the legends the layout has
##   --save     save the layout after --auto or --place-x
##   --render   write <DIR>/labels_<side>_face.png, _outer.png, _inner.png (1024x1024) for both sides
##
## Text rule: on the face, the text lies flat on the surface, its baseline along that hand's menu or view button, measured
## from the button (tools/menu_direction.gd), the top of the letters towards the aim direction: it reads level with the
## button's lines when you look down at the face with the controller pointing away. On the side walls it runs along the
## controller, upright with the face up.
## The legends here are the app's own print (scripts/xr/label_surface.gd). --auto places them by rule from the controls'
## measured bounds, on the right hand, and mirrors that to the left, so the two are deliberate mirrors. Each group of
## related legends takes the largest size that fits, with a margin, every legend of it at one size and one offset from its
## control, kept for its largest text in any state. Legends are read with the controller brought close, so the rules
## ask for a legend in sight from those views and do not care how it looks at arm's length.
##
## Keys (interactive): Tab / Shift+Tab next / previous legend; click on the model: move the legend there (flat on the
## surface under the click); Q / E turn it 5 degrees; arrows nudge 0.5 mm; + / - line height; 1 / 2 left / right
## hand; F / O / I face / outer / inner view; right drag orbit, wheel zoom; A auto-layout; Ctrl+S save;
## R render; Esc quit.

const LabelLayout := preload("res://scripts/xr/label_layout.gd")
const LabelFont := preload("res://scripts/xr/label_font.gd")
const LabelSurface := preload("res://scripts/xr/label_surface.gd")
const MenuDirection := preload("res://tools/menu_direction.gd")
const ControllerVisual := preload("res://scripts/xr/controller_visual.gd")
const Main := preload("res://scripts/main.gd")

const LAYOUT_PATH := "res://xr/controller_labels_layout.tres"
const DEFAULT_MODEL_DIR := "res://docs/reference-models"
const DEPTH := 0.012
## How far a wall legend looks for the wall: walls curve away more than the face.
const WALL_DEPTH := 0.024
const RENDER_SIZE := Vector2i(1024, 1024)
## Plastic kept clear round a legend: to the rim and to a control's edge.
const MARGIN := 0.001
## Between legends.
const LEGEND_GAP := 0.0022
## Between a control's edge and its legend.
const GAP := 0.001
## How far a legend's points may lie above or below its centre on the domed face (DEPTH keeps it in reach).
const FLAT_TOLERANCE := 0.007
## The views a legend must be in sight from, as a controller brought close to read it: degrees above the face plane from
## behind, degrees round to the inner side.
const READ_VIEWS := [[65.0, 0.0], [55.0, 0.0], [65.0, 20.0]]
## Least sine of the angle between such a view and the surface under a legend.
const MIN_FACING := 0.25
## Line heights tried, largest first.
const FACE_LINES: Array[float] = [0.006, 0.0058, 0.0056, 0.0054, 0.0052, 0.005, 0.0048, 0.0046, 0.0044, 0.0042]
## X's legend may go below the face sizes: the diamond and the stick leave it the least room.
const X_LINES: Array[float] = [0.004, 0.0038, 0.0036, 0.0035, 0.0034, 0.0033, 0.0032, 0.0031, 0.003]
const WALL_LINES: Array[float] =[0.008, 0.0075, 0.007, 0.0065, 0.006, 0.0056, 0.005]
## The state flags of Main.controller_labels(): normal, menu open, a captured window has the input, a terminal has it,
## an agent's terminal shows (X is Enter).
const STATES := [[false, false, false, false], [true, false, false, false], [false, true, false, false],
		[false, false, true, false], [false, false, false, true]]
const FACE_CONTROLS: Array[String] = ["a", "b", "x", "y", "menu", "view", "system", "thumbstick", "dpad"]
## Round controls count as circles; the rest as their bounds.
const ROUND_CONTROLS: Array[String] = ["a", "b", "x", "y", "system", "thumbstick"]
## In the model's space: along the wall towards the front, and down the wall, with the face up.
const FRONT := Vector3(0.0, -0.642788, -0.766044)
const DOWN := Vector3(0.0, -0.766044, 0.642788)
## The side walls, right hand, from the model's middle.
const WALL_X := 0.0175
## Worst a legend may lie, with some in hand against the limits of the proof and tests/test_label_print.gd.
const MAX_STRETCH := 1.09
const MAX_BRIDGED := 0.05
const MIN_COVER := 0.97
const MAX_GAP := 0.0002

var side := "right"
var model_dir := DEFAULT_MODEL_DIR
var layout: LabelLayout
## Per side: {"root": Node3D, "nodes": {input: Node3D}, "n", "front", "right", "centre", "body": AABB} (model space).
var _models := {}
var _labels := {}
var _texts := {}
var _camera: Camera3D
var _orbit := Vector2(0.0, -60.0)
var _distance := 0.3
var _selected := 0
var _help: Label
var _dragging := false


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	side = str(args.get("side", "right"))
	model_dir = str(args.get("model-dir", DEFAULT_MODEL_DIR))
	layout = load(LAYOUT_PATH) if ResourceLoader.exists(LAYOUT_PATH) else LabelLayout.new()
	if layout == null:
		layout = LabelLayout.new()

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.33, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)
	_camera = Camera3D.new()
	_camera.near = 0.005
	_camera.fov = 40.0
	add_child(_camera)
	_help = Label.new()
	_help.position = Vector2(10, 10)
	var layer := CanvasLayer.new()
	layer.add_child(_help)
	add_child(layer)

	for s in ["left", "right"]:
		_load_model(s)
	for s: String in _models:
		_frame(s, _models[s])
		var m: Dictionary = _models[s]
		print("%s face frame (model space): normal %s, forward %s, right %s (%s); text along %s, %.2f degrees from right" % [s,
				(m["n"] as Vector3).snapped(Vector3.ONE * 0.001), (m["front"] as Vector3).snapped(Vector3.ONE * 0.001),
				(m["right"] as Vector3).snapped(Vector3.ONE * 0.001), m["frame_from"],
				(m["text_right"] as Vector3).snapped(Vector3.ONE * 0.001), m["text_angle"]])
	if _models.is_empty():
		push_error("No models in %s: copy <side>_controller.glb + .json there (--dump-render-models on the device)" % model_dir)
		get_tree().quit(1)
		return
	if not _models.has(side):
		side = _models.keys()[0]
	# Trimesh collision needs a physics frame before rays hit it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if args.has("place-x"):
		place_x_only()
		if args.has("save"):
			save()
	elif args.has("auto"):
		auto_layout()
		if args.has("save"):
			save()
	_show_side(side)
	if args.has("render"):
		await render_all(str(args["render"]))
	if args.has("render") or args.has("quit"):
		get_tree().quit()


# --- Models ------------------------------------------------------------------------------------------------------

func _load_model(s: String) -> void:
	var glb := model_dir.path_join("%s_controller.glb" % s)
	var path := ProjectSettings.globalize_path(glb) if glb.begins_with("res://") else glb
	if not FileAccess.file_exists(path):
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("Can't read %s" % path)
		return
	var root := doc.generate_scene(state) as Node3D
	root.name = "%s_model" % s
	add_child(root)
	# Apart, so each model's collision answers only its own rays.
	root.position = Vector3(-0.5 if s == "left" else 0.5, 0.0, 0.0)
	var info := {}
	var json := path.get_basename() + ".json"
	if FileAccess.file_exists(json):
		info = JSON.parse_string(FileAccess.get_file_as_string(json))
	# The runtime hides some parts (the status light); the .glb doesn't keep that, the .json does.
	for e: Dictionary in info.get("nodes", []):
		if not bool(e.get("visible", true)):
			var hidden := root.find_child(str(e["name"]), true, false) as Node3D
			if hidden != null:
				hidden.visible = false
	var nodes := {}
	var tris: Array = []
	var surface := LabelSurface.new()
	var body := AABB()
	var first := true
	for n in root.find_children("*", "Node3D", true, false):
		var input := ControllerVisual.match_node_name(str(n.name))
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree():
			var mi := n as MeshInstance3D
			var box := _model_aabb(root, mi)
			tris.append({"aabb": box, "faces": _faces(root, mi), "part": str(mi.name)})
			surface.add_part(mi, root.global_transform.affine_inverse() * mi.global_transform)
			body = box if first else body.merge(box)
			first = false
			if input != "" and not nodes.has(input):
				nodes[input] = mi
		elif input != "" and not nodes.has(input):
			# A node without its own mesh: its first mesh below stands for it.
			var meshes := n.find_children("*", "MeshInstance3D", true, false)
			if not meshes.is_empty():
				nodes[input] = meshes[0]
	_models[s] = {"root": root, "nodes": nodes, "body": body, "info": info, "tris": tris, "surface": surface}
	print("%s model: %s; controls %s" % [s, path, nodes.keys()])


## The face frame in model space: n = the aim pose's up (the face plate is square to it on the device's model),
## front = the aim direction laid onto the face, right = front x n. The aim pose comes from <side>_controller.json
## when the hand was tracked when it was written; else from the other hand's, mirrored in X (the models are mirror
## images); else a plane through the face controls.
func _frame(s: String, m: Dictionary) -> void:
	var aim: Variant = _aim_in_model(m["info"])
	m["frame_from"] = "%s aim pose" % s
	if aim == null:
		var other: Dictionary = _models.get("left" if s == "right" else "right", {})
		var other_aim: Variant = _aim_in_model(other.get("info", {}))
		if other_aim != null:
			var mirror := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
			aim = Transform3D(mirror * (other_aim as Transform3D).basis * mirror, Vector3.ZERO)
			m["frame_from"] = "the other hand's aim pose, mirrored"
	var pts: Array[Vector3] = []
	for input in ["a", "b", "x", "y", "menu", "view", "system", "thumbstick", "dpad"]:
		if (m["nodes"] as Dictionary).has(input):
			pts.append(_centre(m["root"], m["nodes"][input]))
	var aim_fwd := Vector3.FORWARD
	var aim_up := Vector3.UP
	var n := aim_up
	if aim != null:
		aim_fwd = ((aim as Transform3D).basis * Vector3.FORWARD).normalized()
		aim_up = ((aim as Transform3D).basis * Vector3.UP).normalized()
		n = aim_up
	elif pts.size() >= 3:
		n = _plane_normal(pts, aim_up)
		m["frame_from"] = "a plane through the face controls"
	if n.dot(aim_up) < 0.0:
		n = -n
	var front := (aim_fwd - n * aim_fwd.dot(n)).normalized()
	m["n"] = n
	m["front"] = front
	m["right"] = front.cross(n).normalized()
	var c := Vector3.ZERO
	for p in pts:
		c += p
	m["centre"] = c / maxf(pts.size(), 1) if not pts.is_empty() else (m["body"] as AABB).get_center()
	m["sign"] = 1.0 if s == "right" else -1.0
	# The face legends' axes: the menu or view button's own direction, each hand's.
	m["text_right"] = m["right"]
	m["text_angle"] = 0.0
	var button: MeshInstance3D = (m["nodes"] as Dictionary).get("menu" if s == "right" else "view")
	if button != null:
		var root: Node3D = m["root"]
		var seen := MenuDirection.measure(button, root.global_transform.affine_inverse() * button.global_transform, n, m["right"])
		m["text_right"] = seen["lines"]
		m["text_angle"] = seen["angle"]
	m["text_front"] = n.cross(m["text_right"]).normalized()


## The aim pose in model space from a dump's info, or null when the hand wasn't tracked as it was written.
static func _aim_in_model(info: Dictionary) -> Variant:
	if not info.has("model_in_aim") or not info.has("aim_in_origin"):
		return null
	if _xform(info["aim_in_origin"]).is_equal_approx(Transform3D()):
		return null
	return _xform(info["model_in_aim"]).affine_inverse()


static func _xform(d: Dictionary) -> Transform3D:
	var v := func(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2])
	return Transform3D(Basis(v.call(d["x"]), v.call(d["y"]), v.call(d["z"])), v.call(d["origin"]))


static func _model_aabb(root: Node3D, mi: MeshInstance3D) -> AABB:
	return (root.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()


static func _centre(root: Node3D, mi: MeshInstance3D) -> Vector3:
	return _model_aabb(root, mi).get_center()


## Least-squares plane normal through points (smallest-variance direction by power iteration on the inverse is
## overkill here: the normal of the best pair of spread vectors, averaged).
static func _plane_normal(pts: Array[Vector3], hint: Vector3) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var acc := Vector3.ZERO
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var nn := (pts[i] - c).cross(pts[j] - c)
			if nn.dot(hint) < 0.0:
				nn = -nn
			acc += nn
	return acc.normalized() if acc.length() > 1e-9 else hint


# --- Labels ------------------------------------------------------------------------------------------------------

func _show_side(s: String) -> void:
	side = s
	for k: String in _models:
		(_models[k]["root"] as Node3D).visible = k == s
	for d: Node in _labels.values():
		d.queue_free()
	_labels.clear()
	_texts = Main.controller_labels(Main.PREVIEW_PROFILE, side, false)
	var root: Node3D = _models[side]["root"]
	for input: String in _texts:
		var mesh := MeshInstance3D.new()
		mesh.name = "Label_" + input
		mesh.material_override = ControllerVisual._label_material()
		root.add_child(mesh)
		_labels[input] = mesh
		_apply(input)
	_selected = clampi(_selected, 0, maxi(_texts.size() - 1, 0))
	_view("face")
	_update_help()


func _apply(input: String) -> void:
	var mesh: MeshInstance3D = _labels.get(input)
	if mesh == null:
		return
	var e := layout.find(side, input)
	mesh.visible = not e.is_empty()
	if e.is_empty():
		return
	var surface: LabelSurface = _models[side]["surface"]
	var text: String = _texts[input]
	var laid := surface.lay(e["transform"], LabelLayout.print_size(e, text), LabelFont.shape(text)["quads"],
			LabelLayout.metres_per_em(e["line_height"]))
	mesh.visible = not laid.is_empty()
	if not laid.is_empty():
		mesh.mesh = surface.mesh_for(laid["node"], [laid])
		mesh.reparent(laid["node"], false)
		mesh.transform = Transform3D()


## Places every legend by rule. In face-plane coordinates of the right hand: x along its menu button, y square to that,
## towards the front.
func auto_layout() -> void:
	var m: Dictionary = _models["right"]
	var right: Vector3 = m["text_right"]
	var front: Vector3 = m["text_front"]
	var controls := {}
	for input: String in m["nodes"]:
		if input in FACE_CONTROLS:
			controls[input] = _footprint(m["root"], m["nodes"][input], right, front)
	var placed := {}
	_place_stick_and_menu(m, controls, placed)
	var taken: Array[Rect2] = []
	for input: String in placed:
		var e: Dictionary = placed[input]
		var size := Vector2(e["size"].x, e["size"].z)
		taken.append(Rect2((e["at"] as Vector2) - size * 0.5, size))
	_place_pair(m, controls, taken, placed)
	for input: String in ["a", "b"]:
		if placed.has(input):
			var e: Dictionary = placed[input]
			taken.append(Rect2((e["at"] as Vector2) - Vector2(e["size"].x, e["size"].z) * 0.5,
					Vector2(e["size"].x, e["size"].z)))
	_place_x(m, controls, taken, placed, float(placed["a"]["line"]) if placed.has("a") else FACE_LINES[0])
	var report := PackedStringArray()
	for s: String in _models:
		var texts := _all_texts(s)
		for input: String in placed:
			var legend := "view" if input == "menu" and s == "left" else input
			if not texts.has(legend):
				continue
			var e: Dictionary = placed[input]
			layout.set_entry(s, legend, _node_name(s, legend), _face_frame(s, e["at"]), e["line"], DEPTH, (e["size"] as Vector3).x)
			report.append("%s %s line %.1f mm, %.1f x %.1f mm" % [s, legend, float(e["line"]) * 1000.0, e["size"].x * 1000.0, e["size"].z * 1000.0])
	_place_walls(report)
	print("Auto layout: %s" % "; ".join(report))
	for input: String in _labels:
		_apply(input)


## The menu button's legend behind the button, as near square on it as it fits, then the stick's two lines, the largest
## that fit in front of the stick, as near over it as they can be.
func _place_stick_and_menu(m: Dictionary, controls: Dictionary, placed: Dictionary) -> void:
	var menu: Dictionary = controls["menu"]
	for line: float in FACE_LINES:
		var size := _largest("menu", line).max(_largest("view", line))
		var from := Vector2(menu["c"].x, (menu["box"] as Rect2).position.y - GAP - size.z * 0.5)
		var spot := _first_spot(m, controls, [], size, _offsets(from, -0.003, 0.003, -0.002, 0.0))
		if not spot.is_empty():
			placed["menu"] = {"at": spot["at"], "line": line, "size": size}
			break
	var stick: Dictionary = controls["thumbstick"]
	for line: float in FACE_LINES:
		var block := _largest("thumbstick", line)
		var from: Vector2 = (stick["c"] as Vector2) + Vector2(0.0, float(stick["r"]) + GAP + block.z * 0.5)
		var spot := _first_spot(m, controls, [], block, _offsets(from, -0.004, 0.016, 0.0, 0.016))
		if not spot.is_empty():
			placed["thumbstick"] = {"at": spot["at"], "line": line, "size": block}
			break


## A and B: one size and one offset from the button. Behind it, as the eye looks along the controller, and to the outer side,
## where the plastic is free. Each is measured by its own text, so the longer does not push the shorter about.
func _place_pair(m: Dictionary, controls: Dictionary, taken: Array, placed: Dictionary) -> void:
	for line: float in FACE_LINES:
		var sizes := {"a": _largest("a", line), "b": _largest("b", line)}
		for extra in range(0, 13):
			for shift in range(0, 17):
				var offset := Vector2(shift * 0.0005, -(float(controls["a"]["r"]) + GAP + sizes["a"].z * 0.5 + extra * 0.0005))
				var taken_now := taken.duplicate()
				for input: String in sizes:
					var spot := _first_spot(m, controls, taken_now, sizes[input], [(controls[input]["c"] as Vector2) + offset])
					if spot.is_empty():
						break
					taken_now.append(spot["rect"])
				if taken_now.size() < taken.size() + sizes.size():
					continue
				var flush := true
				for input: String in sizes:
					var frame := _face_frame("right", (controls[input]["c"] as Vector2) + offset)
					flush = flush and _quality("right", input, frame, line, DEPTH) < INF and _conforms("right", input, frame, line, DEPTH)
				if flush:
					for input: String in sizes:
						placed[input] = {"at": (controls[input]["c"] as Vector2) + offset, "line": line, "size": sizes[input]}
					return


## X: its legend (ENTER while an agent's terminal shows), no larger than A's and B's: behind the button as theirs are, or
## the nearest spot round that, at most 8 mm off, where it lies on the plastic clear of the controls and of `taken`.
## X sits between the stick and A, Y and B: the nearest room for the five letters is behind it, between the stick
## and A, at a 3.5 mm line (2026-11-09, the Frame's model); the face has no room for them at A's size near X.
func _place_x(m: Dictionary, controls: Dictionary, taken: Array, placed: Dictionary, top: float) -> void:
	if not controls.has("x"):
		return
	var c: Dictionary = controls["x"]
	for line: float in FACE_LINES + X_LINES:
		if line > top + 1e-6:
			continue
		var size := _largest("x", line)
		if size.x <= 0.0:
			return
		var from: Vector2 = (c["c"] as Vector2) + Vector2(0.0, -(float(c["r"]) + GAP + size.z * 0.5))
		for at: Vector2 in _offsets(from, -0.008, 0.006, -0.008, 0.002):
			if _first_spot(m, controls, taken, size, [at]).is_empty():
				continue
			var frame := _face_frame("right", at)
			if _quality("right", "x", frame, line, DEPTH) < INF and _conforms("right", "x", frame, line, DEPTH):
				placed["x"] = {"at": at, "line": line, "size": size}
				return


## --place-x: X's legend alone, clear of the face legends the layout has now (theirs as saved, at their own line).
func place_x_only() -> void:
	var m: Dictionary = _models["right"]
	var right: Vector3 = m["text_right"]
	var front: Vector3 = m["text_front"]
	var controls := {}
	for input: String in m["nodes"]:
		if input in FACE_CONTROLS:
			controls[input] = _footprint(m["root"], m["nodes"][input], right, front)
	var taken: Array[Rect2] = []
	var top := FACE_LINES[0]
	for e: Dictionary in layout.entries:
		if e.get("side") != "right" or not (str(e.get("input")) in FACE_CONTROLS) or e.get("input") == "x":
			continue
		var o: Vector3 = (e["transform"] as Transform3D).origin
		var size := _largest(str(e["input"]), float(e["line_height"]))
		var at := Vector2(o.dot(right), o.dot(front))
		taken.append(Rect2(at - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))
		if e.get("input") == "a":
			top = float(e["line_height"])
	var placed := {}
	_place_x(m, controls, taken, placed, top)
	if not placed.has("x"):
		push_error("X: no spot for its legend")
		return
	var e: Dictionary = placed["x"]
	layout.set_entry("right", "x", _node_name("right", "x"), _face_frame("right", e["at"]), e["line"], DEPTH,
			(e["size"] as Vector3).x)
	print("X legend: line %.1f mm, %.1f x %.1f mm, at %s (X at %s)" % [float(e["line"]) * 1000.0,
			e["size"].x * 1000.0, e["size"].z * 1000.0, (e["at"] as Vector2).snapped(Vector2.ONE * 0.0001),
			(controls["x"]["c"] as Vector2).snapped(Vector2.ONE * 0.0001)])
	_apply("x")


## Candidates round a point, the nearest to it first.
static func _offsets(from: Vector2, x0: float, x1: float, y0: float, y1: float) -> Array:
	var out: Array = []
	var x := x0
	while x <= x1 + 1e-6:
		var y := y0
		while y <= y1 + 1e-6:
			out.append(from + Vector2(x, y))
			y += 0.0005
		x += 0.0005
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(from) < b.distance_to(from))
	return out


## The first of the spots where a legend of `size` (x across, z along) fits: {"at", "rect"}, or {}.
func _first_spot(m: Dictionary, controls: Dictionary, taken: Array, size: Vector3, spots: Array) -> Dictionary:
	var right: Vector3 = m["text_right"]
	var front: Vector3 = m["text_front"]
	for at: Vector2 in spots:
		var rect := Rect2(at - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
		if _overlaps(rect, controls, taken) != "":
			continue
		var p: Vector3 = right * at.x + front * at.y
		if _flat_spot(p, right, front, m["n"], size, right) == "":
			return {"at": at, "rect": rect}
	return {}


## Trigger and bumper on the outer wall, centred on one point along it, one row under the other at one size; the grip's
## legend on the inner wall by the button. Laid for real, on both hands: the first spot where they lie flush.
func _place_walls(report: PackedStringArray) -> void:
	var rows := {}
	for line: float in WALL_LINES:
		var trigger := _largest("trigger", line)
		var bumper := _largest("bumper", line)
		var spots := []
		for along in range(27, 72, 3):
			for down in range(42, 70, 2):
				var t := Vector2(along, down) * 0.001
				var b := t - Vector2(0.0, (trigger.z + bumper.z) * 0.5 + LEGEND_GAP)
				var worst := 1.0
				for s: String in _models:
					worst = maxf(worst, _quality(s, "trigger", _wall_frame(s, t, 1.0), line, WALL_DEPTH))
					worst = maxf(worst, _quality(s, "bumper", _wall_frame(s, b, 1.0), line, WALL_DEPTH))
				if worst < INF:
					spots.append({"worst": worst, "trigger": t, "bumper": b})
		spots.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["worst"] < y["worst"])
		for spot: Dictionary in spots.slice(0, 16):
			var flush := true
			for s: String in _models:
				flush = flush and _conforms(s, "trigger", _wall_frame(s, spot["trigger"], 1.0), line, WALL_DEPTH)
				flush = flush and _conforms(s, "bumper", _wall_frame(s, spot["bumper"], 1.0), line, WALL_DEPTH)
			if flush:
				rows = {"line": line, "trigger": spot["trigger"], "bumper": spot["bumper"]}
				break
		if not rows.is_empty():
			break
	for s: String in _models:
		for input: String in ["trigger", "bumper"]:
			if rows.has(input):
				var size := _largest(input, rows["line"])
				layout.set_entry(s, input, _node_name(s, input), _wall_frame(s, rows[input], 1.0), rows["line"], WALL_DEPTH, size.x)
				report.append("%s %s line %.1f mm, %.1f x %.1f mm" % [s, input, float(rows["line"]) * 1000.0, size.x * 1000.0, size.z * 1000.0])
	var grip := Vector2.ZERO
	var m: Dictionary = _models["right"]
	if (m["nodes"] as Dictionary).has("squeeze"):
		var c: Vector3 = _centre(m["root"], m["nodes"]["squeeze"])
		grip = Vector2(c.dot(-FRONT), c.dot(DOWN))
	var spot := {}
	for line: float in WALL_LINES:
		var best := INF
		for along in range(-24, 25, 3):
			for down in range(-24, 25, 3):
				var at := grip + Vector2(along, down) * 0.001
				var q := _quality("right", "squeeze", _wall_frame("right", at, -1.0), line, WALL_DEPTH)
				if q < INF and at.distance_to(grip) < best:
					best = at.distance_to(grip)
					spot = {"line": line, "at": at}
		if best < INF:
			break
	if not spot.is_empty():
		for s: String in _models:
			var size := _largest("squeeze", spot["line"])
			layout.set_entry(s, "squeeze", _node_name(s, "squeeze"), _wall_frame(s, spot["at"], -1.0), spot["line"], WALL_DEPTH, size.x)
			report.append("%s squeeze line %.1f mm, %.1f x %.1f mm" % [s, float(spot["line"]) * 1000.0, size.x * 1000.0, size.z * 1000.0])


## A wall legend's frame: at (along, down) of the wall, wall = 1 the outer and -1 the inner, the text upright with the face
## up and reading along the controller.
func _wall_frame(s: String, at: Vector2, wall: float) -> Transform3D:
	var outward := Vector3.RIGHT * (1.0 if s == "right" else -1.0) * wall
	var x := FRONT * (1.0 if outward.x > 0.0 else -1.0)
	return Transform3D(Basis(x, outward, x.cross(outward)), outward * WALL_X - FRONT * at.x + DOWN * at.y)


## A face legend's frame: at (x, y) of the right hand's face, mirrored for the left, on the plastic under it.
func _face_frame(s: String, at: Vector2) -> Transform3D:
	var m: Dictionary = _models[s]
	var right: Vector3 = m["text_right"]
	var n: Vector3 = m["n"]
	var p: Vector3 = right * at.x * float(m["sign"]) + (m["text_front"] as Vector3) * at.y
	var hit := _surface_on(s, p + n * 0.03, -n)
	return Transform3D(Basis(right, n, right.cross(n)), hit.get("position", p))


## How badly a legend lies in a frame: its texts' worst stretch; INF when one doesn't fit: off the body, or over steps.
func _quality(s: String, input: String, frame: Transform3D, line: float, depth: float) -> float:
	var surface: LabelSurface = _models[s]["surface"]
	var scale := LabelLayout.metres_per_em(line)
	var worst := 1.0
	for state: Array in STATES:
		var texts := _labels_in(s, state)
		if not texts.has(input):
			continue
		var shaped := LabelFont.shape(texts[input])
		var laid := surface.lay(frame, LabelLayout.print_size({"line_height": line, "depth": depth}, texts[input]), shaped["quads"], scale)
		if laid.is_empty() or str((laid["node"] as Node).name) != "body":
			return INF
		if float(laid["bridged"]) > MAX_BRIDGED or float(laid["cover"]) < MIN_COVER:
			return INF
		worst = maxf(worst, LabelSurface.stretch(laid, shaped["quads"], scale))
	return worst if worst <= MAX_STRETCH else INF


## Whether the legend's longest text stays on the plastic. Slow: each vertex is a ray against the whole part.
func _conforms(s: String, input: String, frame: Transform3D, line: float, depth: float) -> bool:
	var text := str(_all_texts(s).get(input, ""))
	if text == "":
		return true
	var surface: LabelSurface = _models[s]["surface"]
	var shaped := LabelFont.shape(text)
	var laid := surface.lay(frame, LabelLayout.print_size({"line_height": line, "depth": depth}, text), shaped["quads"],
			LabelLayout.metres_per_em(line))
	return not laid.is_empty() and surface.worst_gap(laid).x <= MAX_GAP


func _node_name(s: String, input: String) -> String:
	var nodes: Dictionary = _models[s]["nodes"]
	return str((nodes[input] as Node).name) if nodes.has(input) else ""


## The legends of a hand in one of STATES.
static func _labels_in(s: String, state: Array) -> Dictionary:
	return Main.controller_labels(Main.PREVIEW_PROFILE, s, state[0], state[1], state[2], false, false, {}, false, state[3])


## Every legend a hand can print, by input: the longest text of each.
func _all_texts(s: String) -> Dictionary:
	var out := {}
	for state: Array in STATES:
		var texts := _labels_in(s, state)
		for input: String in texts:
			if str(texts[input]).length() > str(out.get(input, "")).length():
				out[input] = texts[input]
	return out


## The room to keep for an input, on either hand: the widest and the tallest of its legends in any state, at a line height.
func _largest(input: String, line_height: float) -> Vector3:
	var out := Vector3(0.0, DEPTH, 0.0)
	var entry := {"line_height": line_height, "depth": DEPTH}
	for s: String in _models:
		for state: Array in STATES:
			var texts := _labels_in(s, state)
			if texts.has(input):
				out = out.max(LabelLayout.print_size(entry, texts[input]))
	return out


## Points over a legend's rectangle, centre first: a grid across its width, since a long legend can leave the plastic
## between its corners.
static func _grid(p: Vector3, x: Vector3, z: Vector3, size: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = [p]
	var columns := maxi(ceili(size.x / 0.004), 2)
	for j in 3:
		for i in columns + 1:
			out.append(p + x * size.x * (float(i) / columns - 0.5) + z * size.z * (j * 0.5 - 0.5))
	return out


## "" when a legend centred at p (size in the face plane: x across, z along), with its margin, lies on the plastic: rays
## down onto points all over it all hit the body, within FLAT_TOLERANCE of the centre's level, and from each reading
## view nothing stands in front of them and the surface faces the eye well enough. Else why not. Tried on the corners
## first: most spots fail there, and rays cost.
func _flat_spot(p: Vector3, right: Vector3, front: Vector3, n: Vector3, size: Vector3, outer: Vector3) -> String:
	var grown := size + Vector3(MARGIN * 2.0, 0.0, MARGIN * 2.0)
	var level := 0.0
	var corners: Array[Vector3] = [p]
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		corners.append(p + right * corner.x * grown.x * 0.5 + front * corner.y * grown.z * 0.5)
	for i in corners.size():
		var hit := _surface(corners[i] + n * 0.03 - n * 0.0265, -n)
		if hit.is_empty() or hit["part"] != "body":
			return "a corner off the body"
		var h := (hit["position"] as Vector3).dot(n)
		if i == 0:
			level = h
		elif absf(h - level) > FLAT_TOLERANCE:
			return "not flat"
	var views: Array[Vector3] = []
	for v: Array in READ_VIEWS:
		var up := deg_to_rad(float(v[0]))
		var round_side := deg_to_rad(float(v[1]))
		views.append(n * sin(up) + (-front * cos(round_side) - outer * sin(round_side)) * cos(up))
	for q in _grid(p, right, front, grown):
		var hit := _surface(q + n * 0.03 - n * 0.0265, -n)
		if hit.is_empty():
			return "off the controller"
		if hit["part"] != "body":
			return "on %s" % hit["part"]
		var h := (hit["position"] as Vector3).dot(n)
		if absf(h - level) > FLAT_TOLERANCE:
			return "not flat (%.1f mm)" % (absf(h - level) * 1000.0)
		for view in views:
			if (hit["normal"] as Vector3).dot(view) < MIN_FACING:
				return "turned from the eye (%.2f)" % (hit["normal"] as Vector3).dot(view)
			var seen := _surface((hit["position"] as Vector3) + n * 0.0005, view)
			if not seen.is_empty():
				return "hidden by %s" % seen["part"]
	return ""


## A control's footprint on the face: its vertices projected onto the face plane (right, front), as a circle
## {"c": centre, "r": radius} around the middle of their extent, and "box": their bounds.
static func _footprint(root: Node3D, mi: MeshInstance3D, right: Vector3, front: Vector3) -> Dictionary:
	var t := root.global_transform.affine_inverse() * mi.global_transform
	var pts: Array[Vector2] = []
	for i in mi.mesh.get_surface_count():
		for v: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			var w := t * v
			pts.append(Vector2(w.dot(right), w.dot(front)))
	var lo := pts[0]
	var hi := pts[0]
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var c := (lo + hi) * 0.5
	var r := 0.0
	for q in pts:
		r = maxf(r, q.distance_to(c))
	return {"c": c, "r": r, "box": Rect2(lo, hi - lo)}


## What a legend's rectangle (face-plane coordinates) would cover: "" when free, else the control or "a legend".
func _overlaps(rect: Rect2, controls: Dictionary, taken: Array) -> String:
	for r: Rect2 in taken:
		if r.grow(LEGEND_GAP).intersects(rect):
			return "a legend"
	for input: String in controls:
		var c: Dictionary = controls[input]
		if input in ROUND_CONTROLS:
			var at: Vector2 = c["c"]
			var closest := at.clamp(rect.position, rect.end)
			if closest.distance_to(at) < float(c["r"]) + MARGIN:
				return input
		elif (c["box"] as Rect2).grow(MARGIN).intersects(rect):
			return input
	return ""


func _surface_on(s: String, from: Vector3, dir: Vector3) -> Dictionary:
	var shown := side
	side = s
	var hit := _surface(from, dir)
	side = shown
	return hit


## First hit of a model-space ray on the current model's collision, in model space: {position, normal} or {}.
## Casts against the model's own triangles (no physics: queries work at any time, and match the mesh exactly).
## In millimetres: Geometry3D.ray_intersects_triangle() takes a triangle as edge-on to the ray below a fixed epsilon
## (1e-5), which in metres drops every triangle with edges under about 3 mm, the whole of the buttons.
func _surface(from: Vector3, dir: Vector3) -> Dictionary:
	if not _models.has(side):
		return {}
	var best := INF
	var out := {}
	var d := dir.normalized()
	var from_mm := from * 1000.0
	for part: Dictionary in _models[side]["tris"]:
		var box: AABB = part["aabb"]
		if box.grow(0.0005).intersects_ray(from, d) == null:
			continue
		var f: PackedVector3Array = part["faces"]
		for i in range(0, f.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from_mm, d, f[i], f[i + 1], f[i + 2])
			if hit == null:
				continue
			var dist := from_mm.distance_to(hit)
			if dist < best:
				best = dist
				var nn := (f[i + 1] - f[i]).cross(f[i + 2] - f[i]).normalized()
				out = {"position": (hit as Vector3) / 1000.0, "normal": nn if nn.dot(d) < 0.0 else -nn,
						"part": part["part"]}
	return out


## A mesh's triangles in model space, in millimetres (three vertices each; see _surface()).
static func _faces(root: Node3D, mi: MeshInstance3D) -> PackedVector3Array:
	var t := root.global_transform.affine_inverse() * mi.global_transform
	var out := PackedVector3Array()
	for v in mi.mesh.get_faces():
		out.append((t * v) * 1000.0)
	return out


func save() -> void:
	var err := ResourceSaver.save(layout, LAYOUT_PATH)
	print("Saved %s (%d legends): %s" % [LAYOUT_PATH, layout.entries.size(), error_string(err)])


# --- Views and rendering -----------------------------------------------------------------------------------------

func _view(which: String) -> void:
	var m: Dictionary = _models[side]
	var root: Node3D = m["root"]
	var n: Vector3 = root.global_basis * (m["n"] as Vector3)
	var front: Vector3 = root.global_basis * (m["front"] as Vector3)
	var outer: Vector3 = root.global_basis * ((m["right"] as Vector3) * float(m["sign"]))
	var centre: Vector3 = root.global_transform * (m["centre"] as Vector3)
	var body: Vector3 = root.global_transform * (m["body"] as AABB).get_center()
	match which:
		"face":
			_camera.global_transform = Transform3D(Basis.looking_at(-n, front), centre + n * 0.25)
		"outer":
			_camera.global_transform = Transform3D(Basis.looking_at(-outer, n), body + outer * 0.25)
		"inner":
			_camera.global_transform = Transform3D(Basis.looking_at(outer, n), body - outer * 0.25)


func render_all(dir: String) -> void:
	var out := ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = RENDER_SIZE
	for s: String in _models:
		_show_side(s)
		# Textures draw a frame at a time.
		for i in 12:
			await RenderingServer.frame_post_draw
		for which in ["face", "outer", "inner"]:
			_view(which)
			_help.visible = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := out.path_join("labels_%s_%s.png" % [s, which])
			print("Render %s: %s" % [path, error_string(img.save_png(path))])
	_help.visible = true


# --- Interaction -------------------------------------------------------------------------------------------------

func _selected_input() -> String:
	var keys := _texts.keys()
	return keys[_selected] if _selected < keys.size() else ""


func _update_help() -> void:
	var input := _selected_input()
	var e := layout.find(side, input)
	_help.text = "%s hand | legend: %s (%s) %s\nTab next | click place | Q/E turn | arrows nudge | +/- size | 1/2 hand | F/O/I view | A auto | Ctrl+S save | R render" % [
			side, input, str(_texts.get(input, "")).replace("\n", " / "), "" if not e.is_empty() else "(not placed)"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = b.pressed
		elif b.button_index == MOUSE_BUTTON_WHEEL_UP and b.pressed:
			_camera.global_position += -_camera.global_basis.z * 0.01
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN and b.pressed:
			_camera.global_position -= -_camera.global_basis.z * 0.01
		elif b.button_index == MOUSE_BUTTON_LEFT and b.pressed:
			_place_at(b.position)
	elif event is InputEventMouseMotion and _dragging:
		var centre: Vector3 = (_models[side]["root"] as Node3D).global_transform * (_models[side]["centre"] as Vector3)
		var rel := (event as InputEventMouseMotion).relative * 0.01
		var offset := _camera.global_position - centre
		offset = offset.rotated(Vector3.UP, -rel.x).rotated(_camera.global_basis.x, -rel.y)
		_camera.global_transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), centre + offset)
	elif event is InputEventKey and event.pressed:
		_key(event as InputEventKey)


func _key(k: InputEventKey) -> void:
	var input := _selected_input()
	var e := layout.find(side, input)
	match k.keycode:
		KEY_TAB:
			_selected = (_selected + (-1 if k.shift_pressed else 1) + _texts.size()) % maxi(_texts.size(), 1)
		KEY_Q, KEY_E:
			if not e.is_empty():
				var t: Transform3D = e["transform"]
				t.basis = t.basis.rotated(t.basis.y.normalized(), deg_to_rad(5.0 if k.keycode == KEY_Q else -5.0))
				layout.set_entry(side, input, e["node"], t, e["line_height"], e["depth"], e.get("width", 0.0))
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if not e.is_empty():
				var t: Transform3D = e["transform"]
				var step: Vector3 = {KEY_LEFT: -t.basis.x, KEY_RIGHT: t.basis.x, KEY_UP: -t.basis.z, KEY_DOWN: t.basis.z}[k.keycode]
				t.origin += (step as Vector3).normalized() * 0.0005
				layout.set_entry(side, input, e["node"], t, e["line_height"], e["depth"], e.get("width", 0.0))
		KEY_PLUS, KEY_EQUAL, KEY_MINUS:
			if not e.is_empty():
				var h := float(e["line_height"]) + (0.0002 if k.keycode != KEY_MINUS else -0.0002)
				layout.set_entry(side, input, e["node"], e["transform"], maxf(h, 0.002), e["depth"], e.get("width", 0.0))
		KEY_1:
			if _models.has("left"):
				_show_side("left")
		KEY_2:
			if _models.has("right"):
				_show_side("right")
		KEY_F:
			_view("face")
		KEY_O:
			_view("outer")
		KEY_I:
			_view("inner")
		KEY_A:
			auto_layout()
		KEY_S:
			if k.ctrl_pressed:
				save()
		KEY_R:
			# Pictures of the runtime's model: never in the repository.
			render_all("user://label_renders")
		KEY_ESCAPE:
			get_tree().quit()
	_apply(input)
	_update_help()


## Moves the selected legend to the surface under the mouse, flat on it, text across the controller.
func _place_at(screen_pos: Vector2) -> void:
	var input := _selected_input()
	if input == "":
		return
	var m: Dictionary = _models[side]
	var inv := (m["root"] as Node3D).global_transform.affine_inverse()
	var hit := _surface(inv * _camera.project_ray_origin(screen_pos),
			inv.basis * _camera.project_ray_normal(screen_pos))
	if hit.is_empty():
		return
	var p: Vector3 = hit["position"]
	var y: Vector3 = hit["normal"]
	var x := (m["text_front"] as Vector3).cross(y)
	if x.length() < 0.1:
		x = (m["text_right"] as Vector3)
	x = x.normalized()
	var e := layout.find(side, input)
	layout.set_entry(side, input, e.get("node", ""), Transform3D(Basis(x, y, x.cross(y)), p),
			float(e.get("line_height", LabelLayout.DEFAULT_LINE)), float(e.get("depth", DEPTH)), float(e.get("width", 0.0)))
	_apply(input)
	_update_help()
