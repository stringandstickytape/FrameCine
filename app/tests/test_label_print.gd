extends SceneTree

## The print on the controllers (scripts/xr/label_surface.gd, label_font.gd, controller_visual.gd): a legend lies on the
## model's real triangles within CONFORM, the text stretches no more than STRETCH, it follows the part it lies on and no
## other, it is rebuilt when its text changes and not otherwise, and hidden labels build nothing. Run on a dome, on the
## hand-built body and on our own model, with the shipped layout. Needs no renderer. Run:
##   godot --headless --xr-mode off --path app --script res://tests/test_label_print.gd [-- --model-dir=DIR]
## With --model-dir (dumped runtime models, never committed) it also measures them, and prints what was measured.

const ControllerVisual := preload("res://scripts/xr/controller_visual.gd")
const LabelFont := preload("res://scripts/xr/label_font.gd")
const LabelLayout := preload("res://scripts/xr/label_layout.gd")
const LabelSurface := preload("res://scripts/xr/label_surface.gd")
const Main := preload("res://scripts/main.gd")

## Largest allowed distance of a print vertex from the plastic, past the print's own height (metres).
const CONFORM := 0.00025
## Largest allowed stretch of the text along any edge of its patches: 1.12 = 12 % longer than flat.
const STRETCH := 1.12
## [menu shown, on a window, an agent's terminal shows (X is Enter)].
const STATES := [[false, false, false], [true, false, false], [false, true, false], [false, false, true]]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	var t0 := Time.get_ticks_usec()
	LabelFont.shape("A")
	print("Measured atlas: %.1f ms, first use" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_test_dome()
	_test_tilted_plane()
	_test_bridges_a_step()
	_test_off_the_edge()
	_test_curved_wall()
	await _test_follows_its_part()
	await _test_text_changes()
	await _test_fallback_body()
	await _test_labels_stay_out_of_the_model()
	await _test_our_model()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model-dir="):
			await _measure_runtime_models(a.trim_prefix("--model-dir="))
	print("test_label_print: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)


## A mesh under a node in the tree, as a model's part.
func _part(part_name: String, mesh: Mesh, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	return mesh


func _flat(size: Vector2) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = 8
	mesh.subdivide_depth = 8
	return mesh


## Lays a legend; {"laid", "gap", "stretch"}.
func _lay(surface: LabelSurface, frame: Transform3D, text: String, line: float, depth := 0.012) -> Dictionary:
	var shaped := LabelFont.shape(text)
	var scale := LabelLayout.metres_per_em(line)
	var size: Vector2 = shaped["size"] * scale
	var laid := surface.lay(frame, Vector3(size.x, depth, size.y), shaped["quads"], scale)
	if laid.is_empty():
		return {"laid": laid, "gap": INF, "stretch": INF}
	var gap := surface.worst_gap(laid)
	return {"laid": laid, "gap": gap.x, "bridge": gap.y, "stretch": LabelSurface.stretch(laid, shaped["quads"], scale)}


## On a ball the size of the controller's dome, off-centre, so the surface slopes under the text.
func _test_dome() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var ball := _part("body", _sphere(0.06), holder)
	var surface := LabelSurface.new()
	surface.add_part(ball, Transform3D())
	var frame := Transform3D(Basis(), Vector3(0.012, 0.0588, 0.0))
	var r := _lay(surface, frame, "PLAY / PAUSE", 0.0045)
	print("Dome: gap %.3f mm, stretch %.3f, cover %.2f" % [r["gap"] * 1000.0, r["stretch"], r["laid"]["cover"]])
	_check("dome: laid", not r["laid"].is_empty())
	_check("dome: conforms (%.3f mm)" % (r["gap"] * 1000.0), r["gap"] <= CONFORM)
	_check("dome: no stretch (%.3f)" % r["stretch"], r["stretch"] <= STRETCH)
	_check("dome: it all lies on the surface", r["laid"]["cover"] > 0.98)
	# Every vertex just above the ball, none under it.
	var inside := 0
	for v: Vector3 in r["laid"]["vertices"]:
		if v.length() < 0.06:
			inside += 1
	_check("dome: no vertex under the surface (%d)" % inside, inside == 0)
	var below := surface.lay(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 0.0588, 0.0)), Vector3(0.01, 0.012, 0.004),
			LabelFont.shape("A")["quads"], 0.004)
	_check("dome: a surface facing away takes no print", below.is_empty())
	holder.free()


## A flat plate turned 30 degrees under a frame square to the world: a flat projection would stretch the text by 15 %.
func _test_tilted_plane() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var plate := _part("body", _flat(Vector2(0.1, 0.1)), holder)
	var pose := Transform3D(Basis(Vector3.BACK, deg_to_rad(30.0)), Vector3.ZERO)
	var surface := LabelSurface.new()
	surface.add_part(plate, pose)
	var r := _lay(surface, Transform3D(), "NEXT", 0.0045, 0.03)
	print("Tilted plate: stretch %.3f" % r["stretch"])
	_check("tilted plate: the frame turns to it (%.3f)" % r["stretch"], r["stretch"] < 1.01)
	_check("tilted plate: lies on it", r["gap"] <= 0.00005)
	holder.free()


## A plate with a pit under part of the text, as the wells round the buttons: the print stays level and doesn't dive in.
func _test_bridges_a_step() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var plate := _part("body", _flat(Vector2(0.1, 0.1)), holder)
	var surface := LabelSurface.new()
	surface.add_part(plate, Transform3D())
	# Cut as the wells are: the plate's triangles over the pit are gone, and its floor, 3 mm down, is the same part.
	var floor_part := _part("floor", _flat(Vector2(0.006, 0.024)), holder)
	var floor_mesh: PackedVector3Array = Transform3D(Basis(), Vector3(0.0, -0.003, 0.0)) * floor_part.mesh.get_faces()
	var faces := PackedVector3Array()
	var plate_faces: PackedVector3Array = surface.parts[0]["faces"]
	for t in range(0, plate_faces.size(), 3):
		var c := (plate_faces[t] + plate_faces[t + 1] + plate_faces[t + 2]) / 3.0
		if absf(c.x) > 0.003 or absf(c.z) > 0.012:
			faces.append(plate_faces[t])
			faces.append(plate_faces[t + 1])
			faces.append(plate_faces[t + 2])
	faces.append_array(floor_mesh)
	surface.parts[0]["faces"] = faces
	var r := _lay(surface, Transform3D(), "PLAY / PAUSE", 0.0045)
	var lowest := INF
	for v: Vector3 in r["laid"]["vertices"]:
		lowest = minf(lowest, v.y)
	print("Step: lowest vertex %.3f mm, bridged %.2f, stretch %.3f" % [lowest * 1000.0, r["laid"]["bridged"], r["stretch"]])
	_check("over a step: the print doesn't dive in (%.3f mm)" % (lowest * 1000.0), lowest > 0.0)
	_check("over a step: no stretch (%.3f)" % r["stretch"], r["stretch"] <= STRETCH)
	_check("over a step: it knows", float(r["laid"]["bridged"]) > 0.01)
	holder.free()


## Past the edge of a part there is nothing to print on: those glyphs go, and none hangs in the air.
func _test_off_the_edge() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var plate := _part("body", _flat(Vector2(0.03, 0.03)), holder)
	var surface := LabelSurface.new()
	surface.add_part(plate, Transform3D())
	var shaped := LabelFont.shape("PLAY / PAUSE")
	var scale := LabelLayout.metres_per_em(0.0045)
	var size: Vector2 = shaped["size"] * scale
	var whole := surface.lay(Transform3D(), Vector3(size.x, 0.012, size.y), shaped["quads"], scale)
	# Half of it past the plate's edge.
	var over := surface.lay(Transform3D(Basis(), Vector3(0.015, 0.0, 0.0)), Vector3(size.x, 0.012, size.y), shaped["quads"], scale)
	var furthest := 0.0
	for v: Vector3 in over["vertices"]:
		furthest = maxf(furthest, v.x)
	print("Off the edge: %d of %d vertices kept, furthest %.1f mm past the edge" % [(over["vertices"] as PackedVector3Array).size(),
			(whole["vertices"] as PackedVector3Array).size(), (furthest - 0.015) * 1000.0])
	_check("off the edge: glyphs are left out", (over["vertices"] as PackedVector3Array).size() < (whole["vertices"] as PackedVector3Array).size())
	_check("off the edge: none hangs in the air (%.1f mm)" % ((furthest - 0.015) * 1000.0), furthest < 0.0185)
	holder.free()


## A wall curved along the text: spaced along the flat frame, the glyphs at its ends would stretch by the slope.
func _test_curved_wall() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var ball := _part("body", _sphere(0.02), holder)
	var surface := LabelSurface.new()
	surface.add_part(ball, Transform3D())
	# About 22 mm of text on a 40 mm ball: its ends lie about 30 degrees round.
	var r := _lay(surface, Transform3D(Basis(), Vector3(0.0, 0.0195, 0.0)), "SEEK / DIST", 0.0042, 0.02)
	print("Curved wall: stretch %.3f, gap %.3f mm" % [r["stretch"], r["gap"] * 1000.0])
	_check("curved wall: no stretch (%.3f)" % r["stretch"], r["stretch"] <= 1.06)
	holder.free()


## A body and a button standing on it, as the runtime's model: a legend on the body stays when the button moves, and one
## on the button goes with it.
func _test_follows_its_part() -> void:
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	_part("body", _flat(Vector2(0.1, 0.1)), model)
	var button := _part("button_a", _flat(Vector2(0.03, 0.02)), model)
	button.position = Vector3(0.0, 0.002, -0.02)
	var hand := Node3D.new()
	root.add_child(hand)
	var visual: Node3D = ControllerVisual.new()
	hand.add_child(visual)
	visual.configure("right")
	visual.use_layout = false
	visual.attach_render_model(model)
	visual.set_texts({"a": "NEXT", "system": "HOME"})
	await process_frame
	var on_button := button.find_child("Print", false, false) as MeshInstance3D
	var on_body := model.get_node("body").find_child("Print", false, false) as MeshInstance3D
	# The legend beside the button is placed by the visual; the one laid here goes on the button.
	var surface := LabelSurface.new()
	for part: Node in model.get_children():
		if part is MeshInstance3D:
			surface.add_part(part, (part as Node3D).transform)
	var shaped := LabelFont.shape("A")
	var laid := surface.lay(Transform3D(Basis(), button.position), Vector3(0.008, 0.002, 0.003), shaped["quads"], 0.003)
	_check("a legend over the button belongs to it", laid.get("node") == button)
	var mesh := surface.mesh_for(button, [laid])
	var extra := MeshInstance3D.new()
	extra.mesh = mesh
	button.add_child(extra)
	var before := extra.global_transform * mesh.get_aabb().get_center()
	var held: Node3D = on_body if on_body != null else on_button
	_check("the print is under a part of the model", held != null)
	var body_before := held.global_transform.origin
	button.position += Vector3(0.0, -0.0012, 0.0)
	await process_frame
	var after := extra.global_transform * mesh.get_aabb().get_center()
	_check("it follows the button down", after.distance_to(before + Vector3(0.0, -0.0012, 0.0)) < 1e-6)
	if on_body != null:
		_check("a legend on the body stays when the button moves", on_body.global_transform.origin.distance_to(
				body_before) < 1e-9)
	# The mesh is in the part's own space: built with the part moved, it still lands where it should.
	var moved := LabelSurface.new()
	moved.add_part(button, Transform3D(Basis(), Vector3(0.0, 0.002, -0.02)))
	var again := moved.lay(Transform3D(Basis(), Vector3(0.0, 0.002, -0.02)), Vector3(0.008, 0.002, 0.003), shaped["quads"], 0.003)
	var local := moved.mesh_for(button, [again])
	_check("the mesh is in the part's space", absf(local.get_aabb().get_center().z) < 0.001
			and absf(local.get_aabb().get_center().y - LabelSurface.OFFSET) < 0.0001)
	hand.free()
	model.free()


## The print is there as soon as there are texts: one mesh. A new text changes it; the same text does not; removing a
## legend does. Nothing is left to run per frame.
func _test_text_changes() -> void:
	var hand := Node3D.new()
	root.add_child(hand)
	var visual: Node3D = ControllerVisual.new()
	hand.add_child(visual)
	visual.configure("right")
	var body: Node3D = visual.get_node("FallbackBody")
	_check("no texts: no print", body.find_child("Print", false, false) == null)
	visual.set_texts({"a": "NEXT", "b": "PREV"})
	var print_mesh := body.find_child("Print", false, false) as MeshInstance3D
	_check("always on: one mesh for the part", print_mesh != null and body.get_child_count() == 1)
	_check("always on: visible with no button held", print_mesh != null and print_mesh.visible)
	_check("no per-frame work", not visual.is_processing() and not visual.is_physics_processing())
	var first: Mesh = print_mesh.mesh
	_check("one surface, one draw call", first.get_surface_count() == 1)
	var count: int = first.surface_get_array_len(0)
	visual.set_texts({"a": "NEXT", "b": "PREV"})
	_check("same texts: not rebuilt", print_mesh.mesh == first)
	visual.set_texts({"a": "CHAPTER -", "b": "PREV"})
	_check("new text: rebuilt", print_mesh.mesh != first and print_mesh.mesh.surface_get_array_len(0) != count)
	var laid_before: int = visual._laid.size()
	visual.set_texts({"a": "NEXT", "b": "PREV"})
	_check("a text seen before is reused", visual._laid.size() == laid_before)
	_check("back to the first text", print_mesh.mesh.surface_get_array_len(0) == count)
	visual.set_texts({"a": "NEXT"})
	_check("a legend removed is gone", print_mesh.mesh.surface_get_array_len(0) < count)
	visual.set_texts({})
	await process_frame
	await process_frame
	_check("no legends: no print", body.find_child("Print", false, false) == null)
	hand.free()


## A hand's legends in one of STATES.
static func _labels(side: String, state: Array) -> Dictionary:
	return Main.controller_labels(Main.PREVIEW_PROFILE, side, state[0], state[1], false, false, false, {}, false, state[2])


## Every input of every profile state on the hand-built body, at the computed placement.
func _test_fallback_body() -> void:
	var legends := 0
	for side: String in ["left", "right"]:
		var hand := Node3D.new()
		root.add_child(hand)
		var visual: Node3D = ControllerVisual.new()
		hand.add_child(visual)
		visual.configure(side)
		for state: Array in STATES:
			var texts := _labels(side, state)
			visual.set_texts(texts)
			await process_frame
			for input: String in texts:
				var laid: Dictionary = visual._labels[input].get("laid", {})
				_check("fallback %s %s: on the body" % [side, input], not laid.is_empty()
						and laid["node"] == visual.get_node("FallbackBody"))
				legends += 1
		hand.free()
	print("Fallback body: %d legends laid" % legends)


## Our nodes under the model are never taken for parts of it, so a second attach and the dump see the same model.
func _test_labels_stay_out_of_the_model() -> void:
	var model := Node3D.new()
	root.add_child(model)
	var body := _part("body", _flat(Vector2(0.1, 0.1)), model)
	var hand := Node3D.new()
	root.add_child(hand)
	var visual: Node3D = ControllerVisual.new()
	hand.add_child(visual)
	visual.configure("right")
	visual.use_layout = false
	visual.attach_render_model(model)
	visual.set_texts({"system": "HOME"})
	await process_frame
	var printed := body.find_child("Print", false, false) as Node
	_check("the print hangs under the part", printed != null)
	_check("it is known as ours", printed != null and visual._is_ours(printed))
	_check("the part itself is not", not visual._is_ours(body))
	var tris: int = (visual._surface.parts[0]["faces"] as PackedVector3Array).size()
	visual.attach_render_model(model)
	await process_frame
	_check("attached again: no print read as model", visual._surface != null
			and (visual._surface.parts[0]["faces"] as PackedVector3Array).size() == tris)
	visual.detach_render_model()
	await process_frame
	_check("detached: the print leaves the model", body.find_child("Print", false, false) == null)
	hand.free()
	model.free()


## The same code on our own model (it shows its baked legends, so this only exercises the surface): the shipped layout's
## spots, every state's legend.
func _test_our_model() -> void:
	var hand := Node3D.new()
	root.add_child(hand)
	var visual: Node3D = ControllerVisual.new()
	hand.add_child(visual)
	visual.configure("right")
	if not visual.use_our_model():
		print("Our model isn't there: skipped")
		hand.free()
		return
	var ours: Node3D = visual._ours
	var surface := LabelSurface.new()
	for mi: MeshInstance3D in ours.find_children("*", "MeshInstance3D", true, false):
		surface.add_part(mi, ours.global_transform.affine_inverse() * mi.global_transform)
	var r := _measure(surface, "right")
	print("Our model: worst gap %.3f mm, worst stretch %.3f, least cover %.2f" % [r["gap"] * 1000.0, r["stretch"], r["cover"]])
	_check("our model: every legend lands", int(r["missing"]) == 0)
	_check("the print stays off while it shows its own", visual.find_children("Print", "MeshInstance3D", true, false).is_empty())
	hand.free()


## Worst figures over a side's legends in all states, at the shipped layout. Rays per vertex are slow: legends are laid
## for the stretch and cover, and the gap is measured once per input.
func _measure(surface: LabelSurface, side: String, report := false) -> Dictionary:
	var out := {"gap": 0.0, "bridge": 0.0, "stretch": 1.0, "cover": 1.0, "bridged": 0.0, "missing": 0}
	var seen := {}
	for state: Array in STATES:
		var texts := _labels(side, state)
		for input: String in texts:
			var entry := ControllerVisual.layout_entry(side, input)
			if entry.is_empty():
				continue
			var text: String = texts[input]
			var line := LabelLayout.fitted_line(entry, text)
			var shaped := LabelFont.shape(text)
			var scale := LabelLayout.metres_per_em(line)
			var size := LabelLayout.print_size(entry, text)
			var laid := surface.lay(entry["transform"], size, shaped["quads"], scale)
			if laid.is_empty():
				out["missing"] = int(out["missing"]) + 1
				printerr("  %s %s: nothing under it" % [side, input])
				continue
			var stretch := LabelSurface.stretch(laid, shaped["quads"], scale)
			out["stretch"] = maxf(out["stretch"], stretch)
			out["cover"] = minf(out["cover"], laid["cover"])
			out["bridged"] = maxf(out["bridged"], laid["bridged"])
			var gap := -1.0
			if not seen.has(input):
				seen[input] = true
				var gaps := surface.worst_gap(laid)
				gap = gaps.x
				out["gap"] = maxf(out["gap"], gaps.x)
				out["bridge"] = maxf(out["bridge"], gaps.y)
			if report:
				print("Measured %s %-10s %-26s line %.1f mm, on %s, stretch %.3f, cover %.2f, bridged %.2f, frame turned %.1f deg, heights %.2f mm%s" % [
						side, input, text.replace("\n", " | "), line * 1000.0, (laid["node"] as Node).name, stretch, laid["cover"],
						laid["bridged"],
						rad_to_deg((laid["frame"] as Transform3D).basis.y.angle_to((entry["transform"] as Transform3D).basis.y)),
						float(laid["reach"]) * 1000.0, ", gap %.3f mm" % (gap * 1000.0) if gap >= 0.0 else ""])
	return out


## The sparkle on the Y cap of the dumped right model, and on no other part. Its pixels are tools/label_proof.gd's.
func _test_agent_mark(scene: Node3D, side: String) -> void:
	var hand := Node3D.new()
	root.add_child(hand)
	var visual: Node3D = ControllerVisual.new()
	hand.add_child(visual)
	visual.configure(side)
	var model := Node3D.new()
	scene.get_parent().remove_child(scene)
	model.add_child(scene)
	hand.add_child(model)
	visual.attach_render_model(model)
	var marked := func(part: String) -> bool:
		var mi := model.find_child(part, true, false) as MeshInstance3D
		var mat := mi.get_active_material(0) as ShaderMaterial if mi != null else null
		return mat != null and mat.get_shader_parameter("use_mark") == true
	if side == "right":
		_check("the Y cap has the sparkle", marked.call("button_y"))
		var ink := func(part: String) -> bool:
			return (model.find_child(part, true, false) as MeshInstance3D).get_active_material(0).get_shader_parameter("use_ink") == true
		for part: String in ["button_a", "button_b", "button_x", "button_y", "button_menu", "button_system"]:
			_check("%s: its art goes white" % part, ink.call(part))
		for part: String in ["body", "thumbstick", "trigger", "bumper", "button_grip"]:
			_check("%s: no art to whiten" % part, not ink.call(part))
		var body := (model.find_child("body", true, false) as MeshInstance3D).get_active_material(0) as ShaderMaterial
		_check("the plastic is black", body.get_shader_parameter("lift") == ControllerVisual.BLACK_LIFT)
		var kind := func(part: String) -> int:
			return int((model.find_child(part, true, false) as MeshInstance3D).get_active_material(0).get_shader_parameter("mark_kind"))
		_check("A, B and X have their pictures: play and pause, the keyboard, the window", marked.call("button_a")
				and marked.call("button_b") and marked.call("button_x") and kind.call("button_y") == 0
				and kind.call("button_a") == 1 and kind.call("button_b") == 2 and kind.call("button_x") == 3)
		for part: String in ["button_menu", "button_system", "body"]:
			_check("%s does not" % part, not marked.call(part))
		var y := model.find_child("button_y", true, false) as MeshInstance3D
		var mat := y.get_active_material(0)
		visual.attach_render_model(model)
		_check("a second attach changes nothing", y.get_active_material(0) == mat and marked.call("button_y"))
		_check("nothing runs for it per frame", not visual.is_processing() and not visual.is_physics_processing())
		var mark: Vector2 = ControllerVisual.MARK_CENTRE_UV
		# The letter's ink in the atlas, texels of 2048: x 1689 to 1767, y 1526 to 1587.
		var reach := Vector2(1767.0, 1587.0) / 2048.0 - mark
		_check("painting out reaches past the letter", reach.length() * ControllerVisual.MARK_MM_PER_UV < ControllerVisual.MARK_ERASE_MM)
		# Another atlas keeps its letter: the mark needs to know where that is.
		var other := ArrayMesh.new()
		var arrays := y.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in uvs.size():
			uvs[i] *= 0.5
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		other.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var moved: ShaderMaterial = (mat as ShaderMaterial).duplicate()
		moved.set_shader_parameter("use_mark", false)
		y.mesh = other
		y.set_surface_override_material(0, moved)
		visual.attach_render_model(model)
		_check("an atlas we don't know keeps its letter", not marked.call("button_y"))
	else:
		var view := model.find_child("button_view", true, false) as MeshInstance3D
		_check("the left's view icon goes white", view.get_active_material(0).get_shader_parameter("use_ink") == true)
		_check("the left has no sparkle", model.find_children("*", "MeshInstance3D", true, false).all(func(mi: MeshInstance3D) -> bool:
				var mat := mi.get_active_material(0) as ShaderMaterial
				return mat == null or mat.get_shader_parameter("use_mark") != true))
	visual.detach_render_model()
	scene.get_parent().remove_child(scene)
	hand.free()
	root.add_child(scene)


## The dumped runtime models: conformance, stretch and time. Not in the repository, so only with --model-dir.
func _measure_runtime_models(dir: String) -> void:
	for side: String in ["right", "left"]:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(dir.path_join("%s_controller.glb" % side), state) != OK:
			printerr("Can't read the %s model in %s" % [side, dir])
			_failures += 1
			continue
		var scene := doc.generate_scene(state) as Node3D
		root.add_child(scene)
		_test_agent_mark(scene, side)
		var t0 := Time.get_ticks_usec()
		var surface := LabelSurface.new()
		var tris := 0
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			if str(mi.name) != "status":
				surface.add_part(mi, scene.global_transform.affine_inverse() * mi.global_transform)
				tris += (surface.parts[-1]["faces"] as PackedVector3Array).size() / 3
		var read := Time.get_ticks_usec() - t0
		var legends := 0
		t0 = Time.get_ticks_usec()
		for st: Array in STATES:
			var texts := _labels(side, st)
			for input: String in texts:
				var entry := ControllerVisual.layout_entry(side, input)
				if not entry.is_empty():
					var line := LabelLayout.fitted_line(entry, texts[input])
					surface.lay(entry["transform"], LabelLayout.print_size(entry, texts[input]),
							LabelFont.shape(texts[input])["quads"], LabelLayout.metres_per_em(line))
					legends += 1
		var laying := Time.get_ticks_usec() - t0
		print("Measured %s build: %d triangles read in %.1f ms; %d legends laid in %.1f ms (%.2f ms each)" % [side, tris,
				read / 1000.0, legends, laying / 1000.0, laying / 1000.0 / maxi(legends, 1)])
		var r := _measure(surface, side, true)
		print("Measured %s worst: gap %.3f mm, stretch %.3f, cover %.2f, bridged %.2f, standing %.2f mm over a step" % [side,
				r["gap"] * 1000.0, r["stretch"], r["cover"], r["bridged"], r["bridge"] * 1000.0])
		_check("runtime %s: every legend lands" % side, int(r["missing"]) == 0)
		_check("runtime %s: conforms (%.3f mm)" % [side, r["gap"] * 1000.0], r["gap"] <= CONFORM)
		_check("runtime %s: no stretch (%.3f)" % [side, r["stretch"]], r["stretch"] <= STRETCH)
		_check("runtime %s: little bridged (%.2f)" % [side, r["bridged"]], r["bridged"] <= 0.1)
		scene.free()
