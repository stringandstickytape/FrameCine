extends RefCounted

## The scene control port (idea #10): list and change the live scene from the PC. spawn, set_prop, get_prop, call,
## free, load_gltf and run (a GDScript snippet). Spawned and loaded nodes go under a "Remote" node of the main scene
## unless a parent is given. Every change sets a summary and, where it can, an undo, so the permission ring
## (permission_ring.gd) shows a toast with undo for it. list_tree is in builtin_commands.gd.
##
## Values: JSON values are converted to the property's type. [x, y, z] becomes a Vector3, [r, g, b, a] or "#rrggbb" a
## Color, a "res://..." or absolute path a loaded resource, {"class": "BoxMesh", "size": [1, 2, 1]} a new resource
## with those properties, and other text is read with str_to_var() ("Transform3D(...)") when the property is not text.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const BuiltinCommands := preload("res://scripts/dev/builtin_commands.gd")

const REMOTE_ROOT := "Remote"
## Nodes `free` refuses: the app itself and the dev node.
const PROTECTED: Array[String] = ["/root", "/root/DevHost"]

## scripts/dev/dev_host.gd
var host: Node


func register_all() -> void:
	var node_param := {"name": "node", "type": "string", "required": true,
			"description": "absolute (/root/Main/...) or relative to the main scene"}
	DevCommands.register("spawn", _cmd_spawn, {
		"description": "Adds a node: a class (MeshInstance3D, OmniLight3D, ...) or a scene file, with properties.",
		"params": [
			{"name": "type", "type": "string", "default": "Node3D", "description": "an engine class deriving from Node"},
			{"name": "scene", "type": "string", "default": "", "description": "a .tscn / .scn path instead of type"},
			{"name": "parent", "type": "string", "default": "", "description": "default: the main scene's Remote node"},
			{"name": "name", "type": "string", "default": ""},
			{"name": "properties", "type": "object", "default": {},
					"description": "{\"position\": [0, 1, -2], \"mesh\": {\"class\": \"BoxMesh\"}}"}],
		"level": "change", "returns": "{path}"})
	DevCommands.register("set_prop", _cmd_set_prop, {
		"description": "Sets a property of a node (a sub-path such as mesh:size or material_override:albedo_color works).",
		"params": [node_param, {"name": "property", "type": "string", "required": true},
				{"name": "value", "type": "any", "required": true}],
		"level": "change", "returns": "the new value"})
	DevCommands.register("get_prop", _cmd_get_prop, {
		"description": "A property of a node; with no property, all its editor-visible properties.",
		"params": [node_param, {"name": "property", "type": "string", "default": ""}],
		"returns": "the value, or {name: value}"})
	DevCommands.register("call", _cmd_call, {
		"description": "Calls a method of a node with arguments (converted as for set_prop where the types are known).",
		"params": [node_param, {"name": "method", "type": "string", "required": true},
				{"name": "args", "type": "array", "default": []}],
		"level": "change", "returns": "what the method returns"})
	DevCommands.register("free", _cmd_free, {
		"description": "Removes a node (kept for undo until the undo is dropped).",
		"params": [node_param], "level": "change", "returns": "{freed: path}"})
	DevCommands.register("load_gltf", _cmd_load_gltf, {
		"description": "Loads a glTF / GLB at runtime from a path on the headset, or from data sent inline (base64).",
		"params": [
			{"name": "path", "type": "string", "default": ""},
			{"name": "data", "type": "string", "default": "", "description": "the .glb file, base64"},
			{"name": "parent", "type": "string", "default": ""},
			{"name": "name", "type": "string", "default": ""},
			{"name": "position", "type": "vector3", "default": Vector3(0, 1.2, -2)},
			{"name": "scale", "type": "float", "default": 1.0}],
		"level": "change", "returns": "{path, nodes}"})
	DevCommands.register("run", _cmd_run, {
		"description": "Runs a GDScript snippet as the body of a function and returns its value. In scope: main, "
				+ "tree, remote (the Remote node), dev (the dev node). It may await.",
		"params": [{"name": "code", "type": "string", "required": true}],
		"level": "code", "returns": "the snippet's return value"})


func _main() -> Node:
	return host.main if host != null and is_instance_valid(host.main) else null


## The main scene's Remote node, made on first use.
func remote_root() -> Node3D:
	var m := _main()
	var r := m.get_node_or_null(REMOTE_ROOT) as Node3D
	if r == null:
		r = Node3D.new()
		r.name = REMOTE_ROOT
		m.add_child(r)
	return r


func _resolve(path: String) -> Node:
	var m := _main()
	if path == "" or path == ".":
		return m
	if path.begins_with("/"):
		return host.get_tree().root.get_node_or_null(NodePath(path))
	return m.get_node_or_null(NodePath(path)) if m != null else null


func _parent(path: String) -> Node:
	return remote_root() if path == "" else _resolve(path)


func _cmd_spawn(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var parent := _parent(args["parent"])
	if parent == null:
		return ctx.fail("no parent %s" % args["parent"])
	var node: Node
	if args["scene"] != "":
		var packed := load(args["scene"]) as PackedScene
		if packed == null:
			return ctx.fail("can't load the scene %s" % args["scene"])
		node = packed.instantiate()
	else:
		var type: String = args["type"]
		if not ClassDB.class_exists(type) or not ClassDB.can_instantiate(type) \
				or not ClassDB.is_parent_class(type, "Node"):
			return ctx.fail("%s is not an engine class that derives from Node" % type)
		node = ClassDB.instantiate(type)
	if args["name"] != "":
		node.name = args["name"]
	var props: Dictionary = args["properties"]
	for key: String in props:
		var err := set_value(node, key, props[key])
		if err != "":
			node.free()
			return ctx.fail(err)
	parent.add_child(node, true)
	var path := node.get_path()
	ctx.summary = "spawn %s" % node.name
	ctx.undo = func() -> void:
		var n := host.get_tree().root.get_node_or_null(path)
		if n != null:
			n.queue_free()
	return {"path": str(path)}


func _cmd_set_prop(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var node := _resolve(args["node"])
	if node == null:
		return ctx.fail("no node %s" % args["node"])
	var prop: String = args["property"]
	if BuiltinCommands.is_private(prop) or BuiltinCommands.is_secret_field(node, prop):
		return ctx.fail("%s is private" % prop)
	var old: Variant = node.get_indexed(NodePath(prop))
	var err := set_value(node, prop, args["value"])
	if err != "":
		return ctx.fail(err)
	ctx.summary = "%s.%s" % [node.name, prop]
	var ref: WeakRef = weakref(node)
	ctx.undo = func() -> void:
		var n: Object = ref.get_ref()
		if n != null:
			n.set_indexed(NodePath(prop), old)
	return DevCommands.to_json(node.get_indexed(NodePath(prop)))


func _cmd_get_prop(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var node := _resolve(args["node"])
	if node == null:
		return ctx.fail("no node %s" % args["node"])
	if args["property"] == "":
		return BuiltinCommands.node_properties(node)
	if BuiltinCommands.is_private(args["property"]) or BuiltinCommands.is_secret_field(node, args["property"]):
		return ctx.fail("%s is private" % args["property"])
	return DevCommands.to_json(node.get_indexed(NodePath(args["property"])))


func _cmd_call(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var node := _resolve(args["node"])
	if node == null:
		return ctx.fail("no node %s" % args["node"])
	var method: String = args["method"]
	# Generic accessors would read what get_prop refuses; private methods are not part of the node's interface.
	if method in ["get", "get_indexed", "get_meta", "set", "set_indexed", "set_meta", "call", "callv", "call_deferred",
			"get_property_list", "get_script"] or BuiltinCommands.is_private(method) \
			or BuiltinCommands.is_secret_field(node, method):
		return ctx.fail("%s is private" % method)
	if not node.has_method(method):
		return ctx.fail("%s has no method %s" % [node.name, method])
	var values: Array = args["args"]
	var call_args: Array = []
	var arg_types := _method_arg_types(node, method)
	for i in values.size():
		var conv := convert_value(values[i], arg_types[i] if i < arg_types.size() else TYPE_NIL, "")
		if conv[1] != "":
			return ctx.fail("argument %d: %s" % [i, conv[1]])
		call_args.append(conv[0])
	ctx.summary = "%s.%s()" % [node.name, method]
	var result: Variant = await node.callv(method, call_args)
	return DevCommands.to_json(result)


func _cmd_free(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var node := _resolve(args["node"])
	if node == null:
		return ctx.fail("no node %s" % args["node"])
	var path := str(node.get_path())
	if path in PROTECTED or node == _main() or node.is_ancestor_of(host) or node == host:
		return ctx.fail("%s can't be freed" % path)
	var parent := node.get_parent()
	var index := node.get_index()
	parent.remove_child(node)
	ctx.summary = "free %s" % node.name
	var parent_ref: WeakRef = weakref(parent)
	ctx.undo = func() -> void:
		var p: Node = parent_ref.get_ref()
		if p != null and is_instance_valid(node) and node.get_parent() == null:
			p.add_child(node)
			p.move_child(node, mini(index, p.get_child_count() - 1))
	ctx.cleanup = func() -> void:
		if is_instance_valid(node) and node.get_parent() == null:
			node.queue_free()
	return {"freed": path}


func _cmd_load_gltf(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var parent := _parent(args["parent"])
	if parent == null:
		return ctx.fail("no parent %s" % args["parent"])
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: Error
	var label: String
	if args["data"] != "":
		var bytes := Marshalls.base64_to_raw(args["data"])
		if bytes.is_empty():
			return ctx.fail("data is not base64")
		err = doc.append_from_buffer(bytes, "", state)
		label = "inline (%d bytes)" % bytes.size()
	elif args["path"] != "":
		var path: String = args["path"]
		if path.begins_with("~/"):
			path = OS.get_environment("HOME").path_join(path.trim_prefix("~/"))
		if not FileAccess.file_exists(path):
			return ctx.fail("no such file on the headset: %s" % path)
		err = doc.append_from_file(path, state)
		label = path.get_file()
	else:
		return ctx.fail("give path or data")
	if err != OK:
		return ctx.fail("glTF: %s" % error_string(err))
	var scene := doc.generate_scene(state)
	if scene == null:
		return ctx.fail("glTF: no scene in %s" % label)
	if args["name"] != "":
		scene.name = args["name"]
	if scene is Node3D:
		(scene as Node3D).position = args["position"]
		(scene as Node3D).scale = Vector3.ONE * float(args["scale"])
	parent.add_child(scene, true)
	var count := [0]
	_count_nodes(scene, count)
	var node_path := scene.get_path()
	ctx.summary = "load %s" % label
	ctx.undo = func() -> void:
		var n := host.get_tree().root.get_node_or_null(node_path)
		if n != null:
			n.queue_free()
	return {"path": str(node_path), "nodes": count[0]}


static func _count_nodes(n: Node, count: Array) -> void:
	count[0] += 1
	for c in n.get_children():
		_count_nodes(c, count)


func _cmd_run(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var code: String = args["code"]
	var body := ""
	for line in code.split("\n"):
		body += "\t" + line + "\n"
	if not code.contains("return"):
		body += "\treturn null\n"
	var script := GDScript.new()
	script.source_code = "extends RefCounted\n\nvar main\nvar tree\nvar remote\nvar dev\n\n\nfunc run():\n" + body
	if script.reload() != OK:
		return ctx.fail("the snippet does not compile (the error event has the reason)")
	var obj: Object = script.new()
	obj.set("main", _main())
	obj.set("tree", host.get_tree())
	obj.set("remote", remote_root())
	obj.set("dev", host)
	ctx.summary = "run %s" % code.strip_edges().get_slice("\n", 0).left(40)
	var result: Variant = await obj.call("run")
	return DevCommands.to_json(result)


# --- Values ---------------------------------------------------------------------------------------------------

## Sets obj's property (or sub-path) from a JSON value. Returns "" or the error.
static func set_value(obj: Object, prop: String, json: Variant) -> String:
	var conv := convert_value(json, _prop_type(obj, prop), _prop_class(obj, prop))
	if conv[1] != "":
		return "%s: %s" % [prop, conv[1]]
	obj.set_indexed(NodePath(prop), conv[0])
	return ""


## The Variant type of a property or sub-path: from the current value, else from the property list.
static func _prop_type(obj: Object, prop: String) -> int:
	var current: Variant = obj.get_indexed(NodePath(prop))
	if current != null:
		return typeof(current)
	var name := prop.get_slice(":", 0)
	if prop.contains(":"):
		return TYPE_NIL
	for p: Dictionary in obj.get_property_list():
		if p["name"] == name:
			return int(p["type"])
	return TYPE_NIL


## The class hint of an object property ("Mesh", "Material"), or "".
static func _prop_class(obj: Object, prop: String) -> String:
	if prop.contains(":"):
		return ""
	for p: Dictionary in obj.get_property_list():
		if p["name"] == prop:
			return str(p.get("class_name", "")) if p.get("class_name", "") != "" else str(p.get("hint_string", ""))
	return ""


static func _method_arg_types(obj: Object, method: String) -> Array:
	for m: Dictionary in obj.get_method_list():
		if m["name"] == method:
			var out: Array = []
			for a: Dictionary in m["args"]:
				out.append(int(a["type"]))
			return out
	return []


## [value, error]: a JSON value converted for a property of Variant type `type` (TYPE_NIL: unknown).
static func convert_value(v: Variant, type: int, class_hint: String) -> Array:
	# A new resource: {"class": "BoxMesh", "size": [1, 2, 1], ...}
	if v is Dictionary and (v as Dictionary).has("class"):
		var cls := str(v["class"])
		if not ClassDB.class_exists(cls) or not ClassDB.can_instantiate(cls):
			return [null, "no class %s" % cls]
		var obj: Object = ClassDB.instantiate(cls)
		for k: String in v:
			if k == "class":
				continue
			var err := set_value(obj, k, v[k])
			if err != "":
				return [null, err]
		return [obj, ""]
	if v is String:
		var s: String = v
		if type == TYPE_OBJECT or (type == TYPE_NIL and (s.begins_with("res://") or s.begins_with("user://"))):
			if s == "" or s == "null":
				return [null, ""]
			if s.begins_with("res://") or s.begins_with("user://") or s.is_absolute_path():
				var res := load(s)
				return [res, ""] if res != null else [null, "can't load %s" % s]
			if ClassDB.class_exists(s) and ClassDB.can_instantiate(s):
				return [ClassDB.instantiate(s), ""]
			return [null, "expected a resource path or {\"class\": ...}"]
		if type in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH, TYPE_NIL]:
			return [s if type != TYPE_NODE_PATH else NodePath(s), ""]
		if type == TYPE_COLOR and Color.html_is_valid(s):
			return [Color.html(s), ""]
		var parsed: Variant = str_to_var(s)
		if parsed != null and typeof(parsed) == type:
			return [parsed, ""]
		return [null, "can't read %s as %s" % [s, type_string(type)]]
	if v is Array:
		var a: Array = v
		match type:
			TYPE_VECTOR2, TYPE_VECTOR2I:
				if a.size() == 2:
					return [type_convert(Vector2(a[0], a[1]), type), ""]
			TYPE_VECTOR3, TYPE_VECTOR3I:
				if a.size() == 3:
					return [type_convert(Vector3(a[0], a[1], a[2]), type), ""]
			TYPE_VECTOR4, TYPE_VECTOR4I:
				if a.size() == 4:
					return [type_convert(Vector4(a[0], a[1], a[2], a[3]), type), ""]
			TYPE_QUATERNION:
				if a.size() == 4:
					return [Quaternion(a[0], a[1], a[2], a[3]), ""]
			TYPE_COLOR:
				if a.size() in [3, 4]:
					return [Color(a[0], a[1], a[2], a[3] if a.size() == 4 else 1.0), ""]
			TYPE_ARRAY, TYPE_NIL:
				return [a, ""]
			_:
				if type >= TYPE_PACKED_BYTE_ARRAY:
					return [type_convert(a, type), ""]
		return [null, "a list of %d can't be a %s" % [a.size(), type_string(type)]]
	if v == null:
		return [null, ""]
	if type == TYPE_NIL or typeof(v) == type:
		return [v, ""]
	if (v is float or v is int or v is bool) and type in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		return [type_convert(v, type), ""]
	return [null, "expected a %s" % type_string(type)]
