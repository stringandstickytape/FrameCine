extends SceneTree

## --dump-render-models on a stand-in model: the .glb keeps the parts (names, hierarchy, poses, material), leaves out
## our label nodes, and reads back; the .json lists every node with transforms and mesh bounds.

const RenderModelDump := preload("res://scripts/xr/render_model_dump.gd")

var _failures := 0


func _initialize() -> void:
	var hand := Node3D.new()
	hand.name = "RightHand"
	root.add_child.call_deferred(hand)
	await process_frame
	var model := Node3D.new()
	model.name = "RenderModel"
	model.position = Vector3(0.0, -0.01, 0.02)
	hand.add_child(model)
	var scene := Node3D.new()
	scene.name = "frame_controller_right"
	model.add_child(scene)
	var plastic := StandardMaterial3D.new()
	plastic.resource_name = "plastic"
	plastic.albedo_color = Color(0.1, 0.1, 0.12)
	var body := _part("body", BoxMesh.new(), plastic, Vector3.ZERO)
	scene.add_child(body)
	var trigger := _part("trigger", SphereMesh.new(), plastic, Vector3(0.0, -0.02, -0.05))
	trigger.rotation_degrees = Vector3(20, 0, 0)
	body.add_child(trigger)
	var labels := Node3D.new()
	labels.name = "Labels"
	model.add_child(labels)
	labels.add_child(_part("label_dot", SphereMesh.new(), plastic, Vector3.ZERO))
	var skip := func(n: Node) -> bool: return n == labels or labels.is_ancestor_of(n)

	var dir := OS.get_user_data_dir().path_join("dump_test")
	var copy := RenderModelDump.copy_scene(model, skip)
	var glb := RenderModelDump.write_glb(dir, "right", copy)
	copy.free()
	_check("glb written", glb != "" and FileAccess.file_exists(glb))
	var json_path := RenderModelDump.write_json(dir, "right", model, hand, skip)
	_check("json written", json_path != "" and FileAccess.file_exists(json_path))

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	_check("glb reads back", doc.append_from_file(glb, state) == OK)
	var back := doc.generate_scene(state)
	var names: Array[String] = []
	for n in back.find_children("*", "", true, false):
		names.append(str(n.name))
	print("  glb nodes: %s" % [names])
	_check("parts kept with their names", names.has("body") and names.has("trigger") and names.has("frame_controller_right"))
	_check("our label nodes left out", not names.has("Labels") and not names.has("label_dot"))
	var t: Node3D = back.find_child("trigger", true, false)
	_check("part pose kept", t != null and t.position.distance_to(Vector3(0.0, -0.02, -0.05)) < 1e-4
			and absf(t.rotation_degrees.x - 20.0) < 0.01)
	var mi := back.find_child("body", true, false) as MeshInstance3D
	var mat := mi.mesh.surface_get_material(0) if mi != null and mi.mesh != null else null
	_check("material kept (%s)" % (mat.resource_name if mat != null else "none"), mat != null and mat.resource_name == "plastic")
	back.free()

	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var by_name := {}
	for e: Dictionary in info["nodes"]:
		by_name[e["name"]] = e
	_check("json lists the parts, not ours (%s)" % [by_name.keys()], by_name.has("body") and by_name.has("trigger")
			and not by_name.has("Labels"))
	var tri: Dictionary = by_name.get("trigger", {})
	_check("json has model-space bounds and materials", tri.has("aabb_model") and tri.has("aabb_local")
			and tri["materials"][0]["name"] == "plastic" and int(tri["triangles"]) > 0)
	var origin: Array = info["model_in_aim"]["origin"]
	_check("json has the model's pose relative to the hand", absf(origin[1] + 0.01) < 1e-4 and absf(origin[2] - 0.02) < 1e-4)

	print("test_render_model_dump: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)


func _part(part_name: String, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	mesh.surface_set_material(0, mat) if mesh is ArrayMesh else (mesh as PrimitiveMesh).set("material", mat)
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	return mi


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
