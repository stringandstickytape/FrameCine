extends RefCounted

## --dump-render-models=DIR: writes the runtime's controller model for a hand to DIR/<side>_controller.glb (GLTFDocument:
## node names, hierarchy, meshes, the runtime's own materials and textures, each part's pose at the time) and
## DIR/<side>_controller.json (every node: name, path, parent, local and model-space transforms, mesh AABB local and in
## model space, material names; plus the model's pose relative to the aim pose, and the aim and grip poses).
## For laying out our labels offline (tools/label_layout.tscn) and registering our own controller model to it.
## The model is Valve's asset: never commit the dump (app/docs/reference-models/ is gitignored for it).

## A copy of the model's glTF scene, taken before the app changes its materials. `skip` returns true for our own nodes.
static func copy_scene(model: Node3D, skip: Callable) -> Node3D:
	var root := Node3D.new()
	root.name = "controller"
	for child in model.get_children():
		if skip.call(child):
			continue
		var copy := child.duplicate()
		for n in copy.find_children("*", "", true, false):
			if skip.call(n):
				n.get_parent().remove_child(n)
				n.free()
		root.add_child(copy)
	for n in root.find_children("*", "", true, false):
		n.owner = root
	return root


## DIR/<side>_controller.glb from copy_scene()'s result. Returns the path, or "" on failure.
static func write_glb(dir: String, side: String, copy: Node3D) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("%s_controller.glb" % side)
	copy.name = "%s_controller" % side
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(copy, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	print("XR %s render model dump: %s: %s" % [side, path, error_string(err)])
	return path if err == OK else ""


## DIR/<side>_controller.json. model: the live model node (transforms in the tracked pose); hand: the XRController3D at
## the aim pose (any Node3D in tests). Returns the path, or "" on failure.
static func write_json(dir: String, side: String, model: Node3D, hand: Node3D, skip: Callable) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var base := dir.path_join("%s_controller" % side)
	var nodes: Array = []
	for n: Node in model.find_children("*", "", true, false):
		if skip.call(n) or not n is Node3D:
			continue
		var n3 := n as Node3D
		var entry := {"name": str(n3.name), "path": str(model.get_path_to(n3)), "parent": str(n3.get_parent().name),
				"class": n3.get_class(), "visible": n3.visible, "local": _xform(n3.transform),
				"model": _xform(_relative(n3, model))}
		if n3 is MeshInstance3D and (n3 as MeshInstance3D).mesh != null:
			var mi := n3 as MeshInstance3D
			var aabb := mi.mesh.get_aabb()
			entry["aabb_local"] = _aabb(aabb)
			entry["aabb_model"] = _aabb(_relative(mi, model) * aabb)
			entry["surfaces"] = mi.mesh.get_surface_count()
			var mats: Array = []
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				mats.append({"name": m.resource_name if m != null else "", "class": m.get_class() if m != null else ""})
			entry["materials"] = mats
			var tris := 0
			for i in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(i)
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			entry["triangles"] = tris
		nodes.append(entry)
	var info := {"side": side, "unit": "metre", "space": "model space = the runtime model node's own space",
			"model_in_aim": _xform(_relative(model, hand)),
			"aim_in_origin": _xform(_pose(hand, &"aim")), "grip_in_origin": _xform(_pose(hand, &"grip")),
			"profile": str(hand.get("profile")) if hand.get("profile") != null else "", "nodes": nodes}
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	if f == null:
		print("XR %s render model dump: can't write %s.json: %s" % [side, base, error_string(FileAccess.get_open_error())])
		return ""
	f.store_string(JSON.stringify(info, "  ", false))
	f.close()
	print("XR %s render model dump: %s.json (%d nodes)" % [side, base, nodes.size()])
	return base + ".json"


## A node's transform in an ancestor's space, from the local transforms: the same in or out of the tree (template
## builds give identity global transforms out of the tree). Not an ancestor: the global transforms.
static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	if not ancestor.is_ancestor_of(node) and node != ancestor:
		return ancestor.global_transform.affine_inverse() * node.global_transform
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != ancestor and n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## A pose of the hand's tracker in the XR origin's space (identity when not tracked).
static func _pose(hand: Node3D, pose_name: StringName) -> Transform3D:
	if not hand is XRNode3D:
		return Transform3D()
	var tracker := XRServer.get_tracker((hand as XRNode3D).tracker) as XRPositionalTracker
	if tracker == null:
		return Transform3D()
	var pose := tracker.get_pose(pose_name)
	return pose.transform if pose != null and pose.has_tracking_data else Transform3D()


static func _xform(t: Transform3D) -> Dictionary:
	return {"origin": _v(t.origin), "x": _v(t.basis.x), "y": _v(t.basis.y), "z": _v(t.basis.z)}


static func _aabb(a: AABB) -> Dictionary:
	return {"position": _v(a.position), "size": _v(a.size), "centre": _v(a.get_center())}


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.00001), snappedf(v.y, 0.00001), snappedf(v.z, 0.00001)]
