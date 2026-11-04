extends RefCounted

## Lightmaps baked on the headset at run time, with no PC step: a room's static meshes get a second UV set, a
## LightmapGI bakes the room's lights and glowing surfaces into them on the GPU, and the result is kept in
## user://lightmaps/<id>/ with a stamp of what went in. The next start loads it instead of baking again; a changed
## room (geometry, material, light or setting) bakes anew. Needs the engine fork's LightmapGI.bake() (the GPU
## lightmapper and xatlas in the export template, docs/BUILD.md); can_bake() says whether this engine has it.
## Static; preload to use:
##   const RoomBake := preload("res://scripts/env/room_bake.gd")
##   RoomBake.prepare(room, "cinema")              second UVs on every mesh the bake takes; call before load or bake
##   if not RoomBake.load(room, "cinema"):          the kept bake, when its stamp matches the room as it is now
##       var r := RoomBake.bake(room, "cinema", {"progress": func(f: float, text: String) -> void: ...})
##       # r: {ok, error, seconds, size (Vector2i, one layer), layers, bytes, path}
##   RoomBake.clear("cinema")                       forget the kept bake
##   RoomBake.abort(room)                           from inside the progress callback: stop the bake
##
## Which meshes: every visible MeshInstance3D under the room whose gi_mode is GI_MODE_STATIC (the engine's default;
## set GI_MODE_DISABLED on a mesh to leave it out). Which lights: every Light3D under the room whose light_bake_mode
## is not BAKE_DISABLED. BAKE_STATIC bakes the direct light too and the light then stops lighting the baked surfaces
## (the cheapest on the headset); BAKE_DYNAMIC bakes only the bounce. Glowing surfaces (emission) light the room too.
## Materials that show the bake: any lit spatial shader (StandardMaterial3D, room_material_lit.gdshader, room_lit);
## an `unshaded` one (room_material.gdshader, env_unlit) takes part in the bake but shows none of it.
##
## The bake blocks the calling thread (the main thread) for its whole length: no frames are drawn meanwhile, so
## "progress" is called with the bake's steps but anything it changes on screen shows only afterwards.
##
## prepare() options (all optional):
##   texel          metres per lightmap texel on the room's surfaces (0.2)
##   near_texel     metres per texel on surfaces within near_distance of the viewer (0.1)
##   near_distance  metres (1.0); viewer: the eyes' place in the room (Vector3(0, 1.2, 0))
##   xatlas         true: primitives (BoxMesh, ...) are unwrapped by xatlas as ArrayMesh copies too; default: their
##                  own second UVs (PrimitiveMesh.add_uv2), which need no unwrap and no cache
## bake() options (all optional):
##   quality (LightmapGI.BAKE_QUALITY_LOW), bounces (2), bounce_energy (1.0), denoiser (true), texel_scale (1.0),
##   max_texture_size (2048), directional (false), probes (LightmapGI.GENERATE_PROBES_DISABLED),
##   ambient (Color: the room's surroundings as a flat colour; default: none, a closed room), ambient_energy (1.0),
##   progress (Callable(fraction: float, text: String): rises from 0 to 1 over the bake)

const DIR := "user://lightmaps"
const FILE := "lightmap.lmbake"
const STAMP_FILE := "stamp.json"
const MESH_DIR := "meshes"
## The LightmapGI node's name under the room.
const NODE := "RoomLightmap"
## Bumped when what this script bakes changes, so every kept bake is redone once.
const FORMAT := 1
## The primitives' own second UVs are laid out at the project's texel size; the instance scales it to ours.
const PRIMITIVE_TEXEL_SETTING := "rendering/lightmapping/primitive_meshes/texel_size"

const ERRORS := ["ok", "no scene root", "foreign data", "no lightmapper in this engine", "no save path", "no meshes",
		"meshes invalid", "can't create the image", "stopped", "texture size too small", "lightmap too small",
		"atlas too small"]

## The lit library shaders' stand-ins for light (room_material.gdshaderinc, LIT): the hemisphere fill and the film's
## light, drawn as emission. They are not light sources: the bake sets them to nothing while it runs (else every
## surface would glow into the lightmap), and they are not part of the stamp (the film light changes as it plays).
const LIVE_PARAMETERS := {"sky_top": Vector3.ZERO, "sky_bottom": Vector3.ZERO, "screen_light": 0.0}

## Meta on a prepared MeshInstance3D: the stamp of its mesh before the second UVs were added.
const META_SOURCE := &"room_bake_source"

## The last prepare()'s and bake()'s figures, for the tests and the benchmark.
static var last_prepare := {}
static var last_bake := {}


## True when this engine can bake at run time: the fork's LightmapGI.bake() and a GPU renderer.
static func can_bake() -> bool:
	return ClassDB.class_has_method("LightmapGI", "bake") and ClassDB.class_exists("LightmapperRD") \
			and RenderingServer.get_rendering_device() != null


## Gives every mesh the bake takes a second UV set (UV2). Primitives get their own (add_uv2) unless options.xatlas;
## other meshes without UV2 are unwrapped by xatlas as ArrayMesh copies, kept in user://lightmaps/<id>/meshes/ so
## the next start gets the same UVs (the kept lightmap fits only those) without unwrapping again.
## Returns {meshes, primitives, unwrapped, cached, seconds}.
static func prepare(root: Node3D, id: String, options := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var texel := float(options.get("texel", 0.2))
	var near_texel := float(options.get("near_texel", 0.1))
	var near_distance := float(options.get("near_distance", 1.0))
	var viewer: Vector3 = options.get("viewer", Vector3(0.0, 1.2, 0.0))
	var use_xatlas := bool(options.get("xatlas", false))
	var primitive_texel := float(ProjectSettings.get_setting(PRIMITIVE_TEXEL_SETTING, 0.2))
	if primitive_texel <= 0.0:
		primitive_texel = 0.2
	var out := {"meshes": 0, "primitives": 0, "unwrapped": 0, "cached": 0}
	for mi in baked_meshes(root):
		var mesh := mi.mesh
		var wanted := near_texel if _distance(_global_aabb(mi), root.global_transform.affine_inverse(), viewer) \
				< near_distance else texel
		out["meshes"] += 1
		if mi.has_meta(META_SOURCE):
			continue
		var source := _mesh_stamp(mesh)
		if mesh is PrimitiveMesh and not use_xatlas:
			var p := mesh as PrimitiveMesh
			p.add_uv2 = true
			# The size hint is in the project's texel size; this instance's scale turns it into ours.
			mi.gi_lightmap_texel_scale = primitive_texel / wanted
			mi.set_meta(META_SOURCE, source)
			out["primitives"] += 1
			continue
		if _has_uv2(mesh):
			mi.set_meta(META_SOURCE, source)
			continue
		var key := ("%s %s %s" % [source, var_to_str(mi.global_transform.basis), wanted]).sha256_text().left(16)
		var cache := DIR.path_join(id).path_join(MESH_DIR).path_join(key + ".res")
		var unwrapped: ArrayMesh = null
		if ResourceLoader.exists(cache):
			unwrapped = ResourceLoader.load(cache, "ArrayMesh") as ArrayMesh
			if unwrapped != null:
				out["cached"] += 1
		if unwrapped == null:
			unwrapped = _unwrap(mesh, mi.global_transform, wanted)
			if unwrapped == null:
				push_warning("room bake: %s could not be unwrapped; it is left out of the bake" % mi.name)
				mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				continue
			_save_mesh(unwrapped, cache)
			out["unwrapped"] += 1
		# The cached copy holds no materials (they are the room's, maybe huge); the source's go back on.
		for s in mini(unwrapped.get_surface_count(), mesh.get_surface_count()):
			unwrapped.surface_set_material(s, mesh.surface_get_material(s))
		mi.mesh = unwrapped
		mi.set_meta(META_SOURCE, source)
	out["seconds"] = (Time.get_ticks_usec() - t0) / 1e6
	last_prepare = out
	return out


## Bakes the room's lightmap and keeps it with its stamp; the room shows it at once. prepare() first.
## Returns {ok, error (a word from ERRORS), seconds, size, layers, bytes, path}.
static func bake(root: Node3D, id: String, options := {}) -> Dictionary:
	var out := {"ok": false, "error": "", "seconds": 0.0, "size": Vector2i.ZERO, "layers": 0, "bytes": 0, "path": ""}
	if not can_bake():
		out["error"] = "this engine can't bake lightmaps at run time"
		return out
	DirAccess.make_dir_recursive_absolute(DIR.path_join(id))
	var path := DIR.path_join(id).path_join(FILE)
	var lm := _lightmap_node(root)
	_configure(lm, options)
	var stamp := stamp_of(root, options)
	var progress: Callable = options.get("progress", Callable())
	var shown := [0.0]
	var step := func(fraction: float, text: String) -> void:
		# The engine's steps don't rise steadily (the lightmapper's own run maps back to 0.2-0.8): keep the highest.
		shown[0] = maxf(shown[0], fraction)
		if progress.is_valid():
			progress.call(shown[0], text)
	lm.connect("bake_progress", step)
	var live := _darken_live(root)
	var t0 := Time.get_ticks_usec()
	var err := int(lm.call("bake", root, path))
	out["seconds"] = (Time.get_ticks_usec() - t0) / 1e6
	_restore_live(live)
	lm.disconnect("bake_progress", step)
	out["error"] = ERRORS[err] if err >= 0 and err < ERRORS.size() else "error %d" % err
	if err != 0:
		last_bake = out
		return out
	if progress.is_valid():
		progress.call(1.0, "Done")
	# A light already drawn with the room keeps lighting the baked surfaces until it is paired with them anew,
	# which would count its direct light twice: hide and show each one so the renderer pairs it again.
	for l in baked_lights(root):
		l.visible = false
		l.visible = true
	var data: LightmapGIData = lm.light_data
	var textures: Array = data.lightmap_textures if data != null else []
	if not textures.is_empty() and textures[0] is TextureLayered:
		var t := textures[0] as TextureLayered
		out["size"] = Vector2i(t.get_width(), t.get_height())
		out["layers"] = t.get_layers()
	var f := FileAccess.open(path, FileAccess.READ)
	out["bytes"] = f.get_length() if f != null else 0
	out["path"] = path
	out["ok"] = true
	var record := {"stamp": stamp, "format": FORMAT, "seconds": out["seconds"], "width": out["size"].x,
			"height": out["size"].y, "layers": out["layers"], "bytes": out["bytes"],
			"engine": Engine.get_version_info().get("string", ""), "baked": Time.get_datetime_string_from_system()}
	var sf := FileAccess.open(DIR.path_join(id).path_join(STAMP_FILE), FileAccess.WRITE)
	if sf != null:
		sf.store_string(JSON.stringify(record, "\t"))
	last_bake = out
	return out


## Shows the kept bake when its stamp matches the room now (prepare() first, with the bake's options); false when
## there is none, it is stale, or it doesn't load. Pass the options bake() was given: they are part of the stamp.
static func load(root: Node3D, id: String, options := {}) -> bool:
	var path := DIR.path_join(id).path_join(FILE)
	var record := stored(id)
	if record.is_empty() or not FileAccess.file_exists(path):
		return false
	if str(record.get("stamp", "")) != stamp_of(root, options):
		return false
	var data := ResourceLoader.load(path, "LightmapGIData", ResourceLoader.CACHE_MODE_REPLACE) as LightmapGIData
	if data == null:
		return false
	var lm := _lightmap_node(root)
	_configure(lm, options)
	lm.light_data = data
	return true


## The kept bake's record {stamp, format, seconds, width, height, layers, bytes, engine, baked}; {} when none.
static func stored(id: String) -> Dictionary:
	var p := DIR.path_join(id).path_join(STAMP_FILE)
	if not FileAccess.file_exists(p):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Dictionary else {}


## Forgets a room's kept bake and its unwrapped meshes.
static func clear(id: String) -> void:
	var dir := DIR.path_join(id)
	if not DirAccess.dir_exists_absolute(dir):
		return
	var meshes := dir.path_join(MESH_DIR)
	if DirAccess.dir_exists_absolute(meshes):
		for f in DirAccess.get_files_at(meshes):
			DirAccess.remove_absolute(meshes.path_join(f))
		DirAccess.remove_absolute(meshes)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## Stops a bake that is running (call it from the progress callback); bake() then returns error "stopped".
static func abort(root: Node3D) -> void:
	var lm := root.get_node_or_null(NODE)
	if lm != null and lm.has_method("abort_bake"):
		lm.call("abort_bake")


## The meshes a bake takes: visible MeshInstance3D under root with gi_mode static and a mesh.
static func baked_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(root, out)
	return out


## The lights a bake takes: Light3D under root whose bake mode isn't disabled.
static func baked_lights(root: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	for n in root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l.light_bake_mode != Light3D.BAKE_DISABLED and l.is_visible_in_tree():
			out.append(l)
	return out


## What went into a bake, as one hash: each baked mesh (its source mesh, place and materials), each baked light
## (kind, place and settings) and the bake's options. Positions are relative to the room.
static func stamp_of(root: Node3D, options := {}) -> String:
	var to_room := root.global_transform.affine_inverse()
	var parts: Array[String] = ["format %d" % FORMAT]
	for mi in baked_meshes(root):
		var source: String = mi.get_meta(META_SOURCE, _mesh_stamp(mi.mesh))
		var mats: Array[String] = []
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			mats.append(_resource_stamp(m))
		parts.append("mesh %s %s %s %s %s" % [root.get_path_to(mi), var_to_str(to_room * mi.global_transform),
				source, mi.gi_lightmap_texel_scale, ",".join(mats)])
	for l in baked_lights(root):
		parts.append("light %s %s %s" % [root.get_path_to(l), var_to_str(to_room * l.global_transform),
				_resource_stamp(l)])
	var keys := options.keys().filter(func(k: Variant) -> bool: return str(k) != "progress")
	keys.sort()
	for k in keys:
		parts.append("option %s %s" % [k, var_to_str(options[k])])
	return "\n".join(parts).sha256_text()


static func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null and mi.gi_mode == GeometryInstance3D.GI_MODE_STATIC and mi.is_visible_in_tree():
		out.append(mi)
	for c in n.get_children():
		# The lightmap node's own children (none today) and other rooms' lightmaps are not geometry.
		if c is LightmapGI:
			continue
		_collect_meshes(c, out)


static func _lightmap_node(root: Node3D) -> LightmapGI:
	var lm := root.get_node_or_null(NODE) as LightmapGI
	if lm == null:
		lm = LightmapGI.new()
		lm.name = NODE
		root.add_child(lm)
	return lm


static func _configure(lm: LightmapGI, o: Dictionary) -> void:
	lm.quality = int(o.get("quality", LightmapGI.BAKE_QUALITY_LOW)) as LightmapGI.BakeQuality
	lm.bounces = int(o.get("bounces", 2))
	lm.bounce_indirect_energy = float(o.get("bounce_energy", 1.0))
	lm.use_denoiser = bool(o.get("denoiser", true))
	lm.texel_scale = float(o.get("texel_scale", 1.0))
	lm.max_texture_size = int(o.get("max_texture_size", 2048))
	lm.directional = bool(o.get("directional", false))
	lm.generate_probes_subdiv = int(o.get("probes", LightmapGI.GENERATE_PROBES_DISABLED)) as LightmapGI.GenerateProbes
	lm.interior = not o.has("ambient")
	if o.has("ambient"):
		lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
		lm.environment_custom_color = o["ambient"]
		lm.environment_custom_energy = float(o.get("ambient_energy", 1.0))
	else:
		lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_DISABLED


## Sets the live stand-ins of every baked surface's shader to nothing; returns [[material, name, value], ...] to put
## back. Library materials are shared, so each is changed (and restored) once.
static func _darken_live(root: Node) -> Array:
	var saved: Array = []
	var seen := {}
	for mi in baked_meshes(root):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as ShaderMaterial
			if m == null or seen.has(m) or m.shader == null:
				continue
			seen[m] = true
			for u: Dictionary in m.shader.get_shader_uniform_list():
				var n := str(u["name"])
				if LIVE_PARAMETERS.has(n):
					saved.append([m, n, m.get_shader_parameter(n)])
					m.set_shader_parameter(n, LIVE_PARAMETERS[n])
	return saved


static func _restore_live(saved: Array) -> void:
	for e: Array in saved:
		(e[0] as ShaderMaterial).set_shader_parameter(e[1], e[2])


static func _has_uv2(mesh: Mesh) -> bool:
	for s in mesh.get_surface_count():
		if _triangles(mesh, s) and mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV2] == null:
			return false
	return mesh.get_surface_count() > 0


## Whether a surface is triangles (what the bake takes); only an ArrayMesh can be anything else.
static func _triangles(mesh: Mesh, surface: int) -> bool:
	return not (mesh is ArrayMesh) or (mesh as ArrayMesh).surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES


## An ArrayMesh copy of `mesh` with xatlas's second UVs at `texel` metres per texel (in the instance's scale).
static func _unwrap(mesh: Mesh, xform: Transform3D, texel: float) -> ArrayMesh:
	var copy := ArrayMesh.new()
	for s in mesh.get_surface_count():
		if not _triangles(mesh, s):
			continue
		var arrays := mesh.surface_get_arrays(s)
		# lightmap_unwrap() rebuilds the surfaces from vertices, normals and UVs; drop what it can't keep.
		arrays[Mesh.ARRAY_TEX_UV2] = null
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if copy.get_surface_count() == 0:
		return null
	# The engine's scale goes in the transform (texel size is in world metres); placement doesn't matter.
	if copy.lightmap_unwrap(Transform3D(xform.basis, Vector3.ZERO), texel) != OK:
		return null
	return copy


static func _save_mesh(mesh: ArrayMesh, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var bare := mesh.duplicate() as ArrayMesh
	for s in bare.get_surface_count():
		bare.surface_set_material(s, null)
	if ResourceSaver.save(bare, path) != OK:
		push_warning("room bake: could not keep the unwrapped mesh at %s" % path)


static func _global_aabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.get_aabb()


## How far the viewer is from a box (room coordinates): 0 when outside and touching; inside (a room's shell), the
## distance to its nearest face.
static func _distance(world_box: AABB, to_room: Transform3D, viewer: Vector3) -> float:
	var box := to_room * world_box
	if box.has_point(viewer):
		var lo := viewer - box.position
		var hi := box.end - viewer
		return minf(minf(minf(lo.x, hi.x), minf(lo.y, hi.y)), minf(lo.z, hi.z))
	var closest := viewer.clamp(box.position, box.end)
	return closest.distance_to(viewer)


static func _mesh_stamp(mesh: Mesh) -> String:
	if mesh is PrimitiveMesh:
		return "%s %s" % [mesh.get_class(), _resource_stamp(mesh)]
	var arrays: Array = []
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		arrays.append([a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_INDEX]])
	return "%s %d" % [mesh.get_class(), hash(arrays)]


## A resource's stored settings as text: values as they are; resources inside it by their file, or their class,
## name and size (a library texture has no file).
static func _resource_stamp(r: Object, depth := 0) -> String:
	if r == null:
		return "null"
	if r is Resource and (r as Resource).resource_path != "" and not (r as Resource).resource_path.contains("::"):
		return (r as Resource).resource_path
	if r is Texture2D:
		return "%s %s %s" % [r.get_class(), (r as Resource).resource_name, (r as Texture2D).get_size()]
	if depth > 2:
		return r.get_class()
	if r is ShaderMaterial:
		# Not through its property list: listing a ShaderMaterial's properties resets every parameter whose value
		# type differs from the uniform's (a Color in a vec3, as the library's lit fill is) to the default.
		var sm := r as ShaderMaterial
		var out: Array[String] = ["ShaderMaterial", _resource_stamp(sm.shader, depth + 1),
				str(sm.render_priority), _resource_stamp(sm.next_pass, depth + 1)]
		if sm.shader != null:
			for u: Dictionary in sm.shader.get_shader_uniform_list():
				var n := str(u["name"])
				if LIVE_PARAMETERS.has(n):
					continue
				var v: Variant = sm.get_shader_parameter(n)
				out.append("%s=%s" % [n, _resource_stamp(v, depth + 1) if v is Object else var_to_str(v)])
		return " ".join(out)
	var parts: Array[String] = [r.get_class()]
	for p in r.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var name := str(p["name"])
		if name in ["script", "resource_local_to_scene", "resource_name"] or name.begins_with("metadata/"):
			continue
		var v: Variant = r.get(name)
		if v is Object:
			parts.append("%s=%s" % [name, _resource_stamp(v, depth + 1)])
		else:
			parts.append("%s=%s" % [name, var_to_str(v)])
	return " ".join(parts)
