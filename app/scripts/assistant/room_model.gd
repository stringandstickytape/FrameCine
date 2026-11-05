extends RefCounted

## glTF models from the assistant (docs/assistant.md, "Rooms"): checked before the engine reads them, read with
## GLTFDocument (no import plugins, nothing executable: glTF has no scripts), and cleaned after: animation players,
## cameras, lights and audio go, materials become the rooms' unlit ones (scripts/env/gltf_room.gd). Static; the
## loading runs on a worker thread (room_editor.gd), so the frame never waits for it.
##
##   precheck(bytes) -> "" or why it is refused                  (the GLB container, its JSON, extensions, URIs)
##   load_glb(bytes) -> {node, triangles, textures, removed, turned, parts} or {error}   (worker-safe: not in a tree)
##   turn_inside_out_shapes(mesh) -> [the fixed ArrayMesh or null, how many shapes were turned]
##   decode_image(bytes) -> {image} or {error}
##   parts_of(node) -> {part name: MeshInstance3D}                 a read model's parts (meta PART_META)
##
## A model's parts (docs/assistant.md, "Objects"): every mesh node of the file, named by its glTF node name, else its
## mesh's name, else part_1, part_2, ... in the file's node order; made plain (letters, digits, space, - and _) and
## unique (Board, Board_2). The name is kept on the MeshInstance3D as meta PART_META, so a placed copy's parts can be
## addressed as "<placed name>/<part name>".

const GltfRoom := preload("res://scripts/env/gltf_room.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

## Extensions a model may use: materials and geometry only. Anything else (behaviour graphs such as
## KHR_interactivity, audio, vendor extensions) is refused, so a file can't ask for more than shapes and pictures.
const ALLOWED_EXTENSIONS: Array[String] = [
	"KHR_materials_emissive_strength", "KHR_materials_unlit", "KHR_texture_transform", "KHR_mesh_quantization",
	"KHR_materials_ior", "KHR_materials_specular", "KHR_materials_transmission", "KHR_materials_clearcoat",
	"KHR_materials_sheen", "KHR_materials_volume", "KHR_materials_pbrSpecularGlossiness", "KHR_lights_punctual",
	"KHR_materials_variants", "KHR_materials_anisotropy", "KHR_materials_iridescence", "KHR_materials_dispersion",
	"EXT_texture_webp", "GODOT_single_root",
]
## Keys in a file's "extras" that ask for code to run somewhere: refused outright.
const SCRIPT_KEYS: Array[String] = ["script", "gdscript", "code", "eval", "javascript", "shader"]
## The meta on a model's MeshInstance3D that holds its part name.
const PART_META := "object_part"
const PART_NAME_MAX := 40


static func precheck(bytes: PackedByteArray) -> String:
	if bytes.size() < 20 or bytes.decode_u32(0) != 0x46546C67:  # "glTF"
		return "not a binary glTF (.glb) file"
	if bytes.decode_u32(4) != 2:
		return "glTF version %d; version 2 is needed" % bytes.decode_u32(4)
	var json_len := bytes.decode_u32(12)
	if bytes.decode_u32(16) != 0x4E4F534A or 20 + json_len > bytes.size():  # "JSON"
		return "the .glb has no JSON chunk"
	var j := JSON.new()
	if j.parse(bytes.slice(20, 20 + json_len).get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return "the .glb's JSON does not parse"
	var g: Dictionary = j.data
	for key in ["extensionsUsed", "extensionsRequired"]:
		for ext: Variant in g.get(key, []):
			if not (str(ext) in ALLOWED_EXTENSIONS):
				return "the extension %s is not allowed (allowed: %s)" % [ext, ", ".join(ALLOWED_EXTENSIONS)]
	for key in ["buffers", "images"]:
		for item: Variant in g.get(key, []):
			if item is Dictionary and (item as Dictionary).has("uri") \
					and not str(item["uri"]).begins_with("data:"):
				return "the .glb refers to an outside file (%s); embed everything" % str(item["uri"]).left(60)
	var found := _script_key(g, 0)
	if found != "":
		return "the .glb carries a script (\"%s\" in its extras); models are data only" % found
	return ""


## A key that names code anywhere under an "extras" object, or "".
static func _script_key(v: Variant, depth: int, in_extras := false) -> String:
	if depth > 24:
		return ""
	if v is Dictionary:
		for k: Variant in v:
			if in_extras and str(k).to_lower() in SCRIPT_KEYS:
				return str(k)
			var f := _script_key(v[k], depth + 1, in_extras or str(k) == "extras")
			if f != "":
				return f
	elif v is Array:
		for x: Variant in v:
			var f := _script_key(x, depth + 1, in_extras)
			if f != "":
				return f
	return ""


## Reads a checked .glb into nodes (not in the tree). Safe on a worker thread.
static func load_glb(bytes: PackedByteArray) -> Dictionary:
	var why := precheck(bytes)
	if why != "":
		return {"error": why}
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, "", state)
	if err != OK:
		return {"error": "the .glb does not read (%s)" % error_string(err)}
	var scene := doc.generate_scene(state)
	if scene == null:
		return {"error": "the .glb has no scene"}
	_name_parts(_json_of(bytes), state, scene)
	var removed: Array[String] = []
	for n in scene.find_children("*", "", true, false):
		if n is AnimationPlayer or n is AnimationTree or n is Camera3D or n is Light3D or n is AudioStreamPlayer3D \
				or n is AudioStreamPlayer:
			removed.append("%s %s" % [n.get_class(), n.name])
			n.get_parent().remove_child(n)
			n.free()
		elif n.get_script() != null:
			n.set_script(null)
			removed.append("a script on %s" % n.name)
	var turned := 0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh:
			var t := turn_inside_out_shapes(mi.mesh as ArrayMesh)
			if t[0] != null:
				mi.mesh = t[0]
				turned += int(t[1])
	var triangles := 0
	var textures := {}
	var parts: Array = []
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		var part := {"name": str(mi.get_meta(PART_META, mi.name)), "color": "", "texture": false, "triangles": 0}
		for s in mi.mesh.get_surface_count():
			var idx: int = mi.mesh.surface_get_array_index_len(s)
			var n: int = (idx if idx > 0 else mi.mesh.surface_get_array_len(s)) / 3
			triangles += n
			part["triangles"] += n
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src != null and src.albedo_texture != null:
				textures[src.albedo_texture.get_rid()] = src.albedo_texture
				part["texture"] = true
			if s == 0:
				part["color"] = "#" + (src.albedo_color.to_html(false) if src != null else "808080")
			mi.set_surface_override_material(s, GltfRoom.convert_material(mi.get_active_material(s)))
		parts.append(part)
	var biggest := 0
	for t: Texture2D in textures.values():
		biggest = maxi(biggest, maxi(t.get_width(), t.get_height()))
	return {"node": scene, "triangles": triangles, "textures": textures.size(), "texture_size": biggest,
			"removed": removed, "turned": turned, "parts": parts}


## The .glb's JSON chunk (precheck() has read it already), or {}.
static func _json_of(bytes: PackedByteArray) -> Dictionary:
	var json_len := bytes.decode_u32(12)
	var j := JSON.new()
	if j.parse(bytes.slice(20, 20 + json_len).get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return {}
	return j.data


## Names each mesh node's part (meta PART_META): its glTF node name, else its mesh's, else part_N; plain and unique.
static func _name_parts(g: Dictionary, state: GLTFState, scene: Node) -> void:
	var nodes: Array = g.get("nodes", []) if g.get("nodes") is Array else []
	var meshes: Array = g.get("meshes", []) if g.get("meshes") is Array else []
	# The engine names each scene node after its GLTFNode, unique in the file (the state's own node map points at
	# the importer's nodes, freed once the scene is made).
	var gltf_nodes := state.get_nodes()
	var taken := {}
	var unnamed := 0
	for i in nodes.size():
		var n: Variant = nodes[i]
		if not (n is Dictionary) or not (n as Dictionary).has("mesh") or i >= gltf_nodes.size():
			continue
		var godot_name := String(gltf_nodes[i].resource_name)
		var scene_node: Node = scene if String(scene.name) == godot_name else scene.find_child(godot_name, true, false)
		if not (scene_node is MeshInstance3D):
			continue
		var name := plain_part_name(str(n.get("name", "")))
		var m := int(n["mesh"])
		if name == "" and m >= 0 and m < meshes.size() and meshes[m] is Dictionary:
			name = plain_part_name(str(meshes[m].get("name", "")))
		if name == "":
			unnamed += 1
			name = "part_%d" % unnamed
		var unique := name
		var k := 2
		while taken.has(unique):
			unique = "%s_%d" % [name.left(PART_NAME_MAX - 4), k]
			k += 1
		taken[unique] = true
		scene_node.set_meta(PART_META, unique)


## A part name made plain: letters, digits, space, - and _ (anything else becomes _), at most PART_NAME_MAX.
static func plain_part_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		out += c if c.is_valid_identifier() or c.is_valid_int() or c in " -_" else "_"
	return out.strip_edges().left(PART_NAME_MAX)


## A read model's parts by name (its MeshInstance3D nodes with PART_META; a node without it, by its own name).
static func parts_of(node: Node) -> Dictionary:
	var out := {}
	if node == null:
		return out
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		out[str(mi.get_meta(PART_META, mi.name))] = mi
	return out


## Closed shapes built inside out (normals in, triangles wound the wrong way) turned the right way. Seen on the Frame
## (2026-11-01): an assistant's generated room had every sphere inside out (the football, the lamp bases): the outside
## was culled and the viewer saw the far inside. Per surface, the triangles are grouped into connected pieces (by
## welded positions); a closed piece (every edge shared by two triangles) whose signed volume has the wrong sign (in
## Godot's winding a closed shape's is negative) gets its triangles reversed and its normals negated. Open pieces
## (planes, cards) have no inside and are left alone. Returns [a new ArrayMesh, count] or [null, 0] when nothing changed.
static func turn_inside_out_shapes(mesh: ArrayMesh) -> Array:
	var surfaces: Array = []
	var total := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var n := 0
		if mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES:
			n = _turn_surface(arrays)
		surfaces.append(arrays)
		total += n
	if total == 0:
		return [null, 0]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES if mesh.surface_get_primitive_type(s)
				== Mesh.PRIMITIVE_TRIANGLES else mesh.surface_get_primitive_type(s), surfaces[s])
		out.surface_set_material(s, mesh.surface_get_material(s))
		out.surface_set_name(s, mesh.surface_get_name(s))
	return [out, total]


## Turns the inside-out closed pieces of one triangle surface's arrays in place; returns how many.
static func _turn_surface(arrays: Array) -> int:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if v.is_empty():
		return 0
	var tri := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		tri = arrays[Mesh.ARRAY_INDEX]
	else:
		tri.resize(v.size())
		for i in v.size():
			tri[i] = i
	# Weld positions (glTF splits vertices at seams), then join the triangles that share one.
	var weld := PackedInt32Array()
	weld.resize(v.size())
	var ids := {}
	for i in v.size():
		var key := Vector3i((v[i] * 10000.0).round())
		if not ids.has(key):
			ids[key] = ids.size()
		weld[i] = ids[key]
	var parent: Array[int] = []  # an Array, not a packed one: the lambda below must see its changes
	parent.resize(ids.size())
	for i in parent.size():
		parent[i] = i
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	var tris := tri.size() / 3
	for t in tris:
		var a: int = find.call(weld[tri[t * 3]])
		for k in [1, 2]:
			var b: int = find.call(weld[tri[t * 3 + k]])
			if a != b:
				parent[b] = a
	# Per piece: its triangles, its edges' counts, its signed volume about its own middle.
	var pieces := {}
	for t in tris:
		var root: int = find.call(weld[tri[t * 3]])
		if not pieces.has(root):
			pieces[root] = []
		(pieces[root] as Array).append(t)
	var turned := 0
	var normals = arrays[Mesh.ARRAY_NORMAL]
	for root: int in pieces:
		var list: Array = pieces[root]
		var edges := {}
		var middle := Vector3.ZERO
		for t: int in list:
			# A triangle collapsed at a pole (two corners welded) has no area and no real edges.
			var w0 := weld[tri[t * 3]]
			var w1 := weld[tri[t * 3 + 1]]
			var w2 := weld[tri[t * 3 + 2]]
			if w0 == w1 or w1 == w2 or w0 == w2:
				continue
			for k in 3:
				var a := weld[tri[t * 3 + k]]
				var b := weld[tri[t * 3 + (k + 1) % 3]]
				var e := Vector2i(mini(a, b), maxi(a, b))
				edges[e] = int(edges.get(e, 0)) + 1
				middle += v[tri[t * 3 + k]]
		middle /= list.size() * 3.0
		if not edges.values().all(func(c: int) -> bool: return c == 2):
			continue
		var volume := 0.0
		for t: int in list:
			var p0 := v[tri[t * 3]] - middle
			var p1 := v[tri[t * 3 + 1]] - middle
			var p2 := v[tri[t * 3 + 2]] - middle
			volume += p0.dot(p1.cross(p2))
		if volume <= 1e-12:
			continue  # already right (negative), or flat
		var done := {}
		for t: int in list:
			var i1 := tri[t * 3 + 1]
			tri[t * 3 + 1] = tri[t * 3 + 2]
			tri[t * 3 + 2] = i1
			if normals != null and (normals as PackedVector3Array).size() == v.size():
				for k in 3:
					var vi := tri[t * 3 + k]
					if not done.has(vi):
						done[vi] = true
						normals[vi] = -normals[vi]
		turned += 1
	if turned > 0:
		if arrays[Mesh.ARRAY_INDEX] != null and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			arrays[Mesh.ARRAY_INDEX] = tri
		else:
			# No index: the vertices themselves are reordered.
			var nv := PackedVector3Array()
			nv.resize(v.size())
			for i in v.size():
				nv[i] = v[tri[i]]
			arrays[Mesh.ARRAY_VERTEX] = nv
			for k in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV2]:
				if arrays[k] == null:
					continue
				var src = arrays[k]
				var dst = src.duplicate()
				var width := 4 if k == Mesh.ARRAY_TANGENT else 1
				for i in v.size():
					for w in width:
						dst[i * width + w] = src[tri[i] * width + w]
				arrays[k] = dst
		if normals != null and arrays[Mesh.ARRAY_INDEX] != null:
			arrays[Mesh.ARRAY_NORMAL] = normals
	return turned


static func decode_image(bytes: PackedByteArray) -> Dictionary:
	var img := Image.new()
	# The first bytes say which it is: a wrong guess prints an engine warning ("Not a PNG file") for every JPEG.
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() >= 12:
		if bytes[0] == 0x89 and bytes[1] == 0x50:
			err = img.load_png_from_buffer(bytes)
		elif bytes[0] == 0xFF and bytes[1] == 0xD8:
			err = img.load_jpg_from_buffer(bytes)
		elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
			err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return {"error": "not a PNG, JPEG or WebP picture"}
	var cap: int = RoomSchema.LIMITS["texture_size"]
	if img.get_width() > cap or img.get_height() > cap:
		return {"error": "texture_size: at most %d x %d pixels (this one is %d x %d)" % [cap, cap, img.get_width(),
				img.get_height()]}
	img.generate_mipmaps()
	# Transparent pixels anywhere: the part is drawn as a cut-out unless its material says otherwise.
	return {"image": img, "alpha": img.detect_alpha() != Image.ALPHA_NONE}
