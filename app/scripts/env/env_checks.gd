extends RefCounted

## The checks every room document passes (docs/environments.md, "The checks"): schema, the headset budget (the room
## built and measured), a clear sight line from every seat, comfort, licences, names, no people. Each returns a list
## of problems ([] when it passes), worded for the person or the agent who made the room. Static; preload to use.
## tests/test_environments.gd runs them over every app/environments/*.env.json; tests/test_env_checks.gd shows each
## one catching a bad document.

const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const ScreenFrame := preload("res://scripts/env/systems/screen_frame.gd")

## The headset budget per room (the Frame at 72 Hz with a film playing; docs/environments.md has the table).
const BUDGET := {"draws": 40, "triangles": 400000, "lights": 2, "particles": 4000, "texture_mb": 96.0}
## Eyes over a seat's floor point.
const EYE_HEIGHT := 1.2
## The screen's points the sight line goes to: its centre, corners and edges, this far in.
const SCREEN_INSET := 0.05
## Real marks a room's text may not name (whole words, any case). Pastiche is fine ("Sirclive", "FreeDTV"); the mark
## itself never. Add to it; never take one out.
const MARKS: Array[String] = ["Odeon", "Nickelodeon", "Regal", "Omnimax", "IMAX", "Atmos", "Dolby", "THX",
		"Compton", "Wurlitzer", "Tron", "Quality Street", "Kia-Ora", "Trinitron", "Baird Televisor", "HD Ready",
		"Sinclair", "Freeview", "Cinerama", "Technicolor", "Cineworld", "Showcase Cinemas", "AMC", "Pathe",
		"Gaumont", "Sony", "Panasonic", "Philips", "Grundig", "Teletext", "Ceefax", "Betamax", "VHS", "Walkman",
		"Coca-Cola", "Pepsi", "Butterkist", "Maltesers", "Kit Kat", "Space Invaders", "Pac-Man", "ZX Spectrum",
		"Commodore", "Atari", "Nintendo", "SEGA", "Disney", "Pixar", "Warner Bros", "Paramount", "MGM", "Netflix"]
## Words that mark a person, a people or a crowd in an object's or a system's name.
const PEOPLE_WORDS: Array[String] = ["person", "people", "crowd", "audience", "human", "mannequin", "figure",
		"man", "woman", "child", "usher", "projectionist", "spectator", "avatar"]
## Comfort: a brightness may change no faster than the photosensitivity ceiling.
static var MIN_SMOOTH: float = 1.0 / (TAU * RoomSchema.MAX_HZ)
static var MIN_FADE: float = 1.0 / (2.0 * RoomSchema.MAX_HZ)


# --- Schema ------------------------------------------------------------------------------------------------------------

static func schema(doc: Dictionary) -> Array:
	return EnvDoc.validate(doc)["errors"].map(func(e: Dictionary) -> String: return "%s: %s" % [e["path"], e["error"]])


# --- Budget ------------------------------------------------------------------------------------------------------------

## The built room's figures: draws (a mesh surface each), triangles, live lights (visible, not the bake's hidden
## ones), particles (their amounts) and texture memory (the images' bytes with their mip levels, each texture once).
## Texture memory is the headset's: a library map loaded from its .mtex counts its ASTC blocks (MaterialLibrary's
## frame_bytes meta), also where this GPU has no ASTC and holds it decompressed (lavapipe, a PC), so the figure is
## the same headless, rendered and on the Frame.
static func measure(room: Node) -> Dictionary:
	var draws := 0
	var tris := 0
	var particles := 0
	var lights := 0
	var textures := {}
	for g: Node in room.find_children("*", "GeometryInstance3D", true, false):
		if not (g as GeometryInstance3D).visible:
			continue
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			draws += mi.mesh.get_surface_count()
			tris += _triangles(mi.mesh)
			for s in mi.mesh.get_surface_count():
				_textures(mi.get_active_material(s), textures)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			var n := int(g.get_meta("instances", mm.instance_count))
			draws += mm.mesh.get_surface_count()
			tris += _triangles(mm.mesh) * n
			for s in mm.mesh.get_surface_count():
				_textures(mm.mesh.surface_get_material(s), textures)
		elif g is GPUParticles3D:
			draws += 1
			particles += (g as GPUParticles3D).amount
		elif g is CPUParticles3D:
			draws += 1
			particles += (g as CPUParticles3D).amount
	for l: Node in room.find_children("*", "Light3D", true, false):
		if (l as Light3D).is_visible_in_tree() or ((l as Light3D).visible and not l.is_inside_tree()):
			lights += 1
	var bytes := 0
	for t: Variant in textures.values():
		bytes += int(t)
	return {"draws": draws, "triangles": tris, "lights": lights, "particles": particles,
			"texture_mb": snappedf(bytes / 1048576.0, 0.1)}


static func _triangles(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null and (idx as PackedInt32Array).size() > 0 \
				else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


static func _textures(m: Material, out: Dictionary) -> void:
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		for u: Dictionary in (m as ShaderMaterial).shader.get_shader_uniform_list():
			var t: Variant = (m as ShaderMaterial).get_shader_parameter(u["name"])
			if t is ImageTexture and not out.has((t as Texture2D).get_rid()):
				out[(t as Texture2D).get_rid()] = _texture_bytes(t as ImageTexture)
	elif m is BaseMaterial3D:
		var t: Texture2D = (m as BaseMaterial3D).albedo_texture
		if t is ImageTexture and not out.has(t.get_rid()):
			out[t.get_rid()] = _texture_bytes(t as ImageTexture)


## A texture's bytes on the headset: its frame_bytes meta (a library map's ASTC size), else its image's.
static func _texture_bytes(t: ImageTexture) -> int:
	if t.has_meta(MaterialLibrary.FRAME_BYTES_META):
		return int(t.get_meta(MaterialLibrary.FRAME_BYTES_META))
	var img := t.get_image()
	return img.get_data_size() if img != null else 0


static func budget(stats: Dictionary, limits := BUDGET) -> Array:
	var out: Array = []
	for k: String in limits:
		if float(stats.get(k, 0)) > float(limits[k]):
			out.append("%s: %s, over the headset's budget of %s" % [k, stats[k], limits[k]])
	return out


# --- Sight line -----------------------------------------------------------------------------------------------------------

## From every seat's eyes to the screen's nine points, nothing static in the way: the room's meshes and seats as one
## physics mesh in the tree's world, ray by ray. Awaitable (the shape needs a physics frame). [] when clear.
## room: the built room, in the tree at the origin.
static func sight_line(tree: SceneTree, room: Node3D, max_reports := 8) -> Array:
	var faces := PackedVector3Array()
	var inv := room.global_transform.affine_inverse()
	for mi: Node in room.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree() or mi.is_in_group(ScreenFrame.SEE_THROUGH) \
				or (mi as MeshInstance3D).mesh == null:
			continue
		var xf: Transform3D = inv * (mi as MeshInstance3D).global_transform
		for v: Vector3 in (mi as MeshInstance3D).mesh.get_faces():
			faces.append(xf * v)
	var seats: Array[Transform3D] = room.call("room_seat_transforms") if room.has_method("room_seat_transforms") \
			else []
	for mm: Node in room.find_children("*", "MultiMeshInstance3D", true, false):
		var mesh_faces := (mm as MultiMeshInstance3D).multimesh.mesh.get_faces()
		# Things placed by their own instances, not seats (the cars parked round a drive-in's: since 2026-11-08):
		# each where it stands, its transform in the meta env_placed (a headless MultiMesh keeps none).
		var placed: Variant = mm.get_meta("env_placed", null)
		if placed is Array:
			var mxf: Transform3D = inv * (mm as MultiMeshInstance3D).global_transform
			for t: Transform3D in placed:
				var ixf := mxf * t
				for v: Vector3 in mesh_faces:
					faces.append(ixf * v)
			continue
		for st in seats:
			for v: Vector3 in mesh_faces:
				faces.append(st * v)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	tree.root.add_child(body)
	body.global_transform = room.global_transform
	await tree.physics_frame
	await tree.physics_frame
	var space := tree.root.get_world_3d().direct_space_state
	var anchor: Transform3D = room.call("get_screen_anchor")
	var w := float(room.get("default_screen_width"))
	var doc: Dictionary = room.get("doc") if room.get("doc") is Dictionary else {}
	var h := w * 9.0 / 16.0
	if doc.get("screen") is Dictionary and (doc["screen"]["size"] as Array).size() > 1:
		h = float(doc["screen"]["size"][1])
	var points: Array[Vector3] = []
	for sx: float in [-0.5 + SCREEN_INSET, 0.0, 0.5 - SCREEN_INSET]:
		for sy: float in [-0.5 + SCREEN_INSET, 0.0, 0.5 - SCREEN_INSET]:
			# A hair in front of the picture: the masking behind it is not in the way.
			points.append(room.global_transform * (anchor * Vector3(sx * w, sy * h, 0.05)))
	var out: Array = []
	if seats.is_empty():
		seats = [Transform3D()]
	for i in seats.size():
		var eye: Vector3 = room.global_transform * (seats[i].origin + Vector3.UP * EYE_HEIGHT)
		for p in points:
			var q := PhysicsRayQueryParameters3D.create(eye, p)
			q.hit_back_faces = true
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				out.append("seat %d (%s): the view of the screen's point %s is blocked at %s" % [i, seats[i].origin,
						_r(p), _r(hit["position"])])
				break
		if out.size() >= max_reports:
			out.append("(and maybe more)")
			break
	body.queue_free()
	return out


static func _r(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


# --- Comfort --------------------------------------------------------------------------------------------------------------

## No system moves the viewer; motion parameters within their limits; brightness kept under the photosensitivity
## ceiling (bindings smoothed, fades long enough). spec_of(system name) -> spec (the registry's by default).
static func comfort(doc: Dictionary, spec_of := Callable()) -> Array:
	var specs := spec_of if spec_of.is_valid() else func(n: String) -> Dictionary: return Registry.spec(n)
	var out: Array = []
	var by_id := {}
	for entry: Dictionary in doc.get("systems", []):
		var n := str(entry["system"])
		var spec: Dictionary = specs.call(n)
		by_id[str(entry.get("id", n))] = spec
		if bool(spec.get("moves_viewer", false)):
			out.append("%s moves the viewer: no system may" % n)
		var ps: Dictionary = spec.get("params", {})
		var given: Dictionary = entry.get("params", {})
		for k: String in ps:
			var v: Variant = given.get(k, ps[k].get("default"))
			if ps[k].has("motion"):
				var limit := float(ps[k]["motion"].get("max", 0.0))
				var top := _max_value(v)
				if absf(top) > limit:
					out.append("%s.%s: %s, over its motion limit of %s" % [entry.get("id", n), k, top, limit])
			if bool(ps[k].get("brightness", false)) and EnvDoc.is_binding(v):
				var ch := str(v["bind"])
				if not ch.begins_with(EnvDoc.SETTING_PREFIX) and float(v.get("smooth", 0.0)) < MIN_SMOOTH:
					out.append("%s.%s follows %s with smooth %s: at least %.3f s (the photosensitivity ceiling)" % [
							entry.get("id", n), k, ch, v.get("smooth", 0.0), MIN_SMOOTH])
	for c: Dictionary in doc.get("cues", []):
		for s: Dictionary in c.get("steps", []):
			if s.has("set") or s.has("release"):
				var t := str(s.get("set", s.get("release")))
				var bits := t.split(".")
				var ps: Dictionary = by_id.get(bits[0], {}).get("params", {})
				if bits.size() == 2 and bool(ps.get(bits[1], {}).get("brightness", false)) \
						and float(s.get("seconds", 0.0)) < MIN_FADE:
					out.append("cue %s: %s changes in %s s: at least %.3f s (the photosensitivity ceiling)" % [c["name"],
							t, s.get("seconds", 0.0), MIN_FADE])
	return out


static func _max_value(v: Variant) -> float:
	if EnvDoc.is_binding(v):
		var top := 0.0
		for x: Variant in v.get("range", []):
			top = maxf(top, absf(float(x)))
		for p: Variant in v.get("keys", []):
			top = maxf(top, absf(float(p[1])))
		for x: Variant in (v.get("map", {}) as Dictionary).values():
			top = maxf(top, absf(float(x)))
		return top
	return float(v) if (v is float or v is int) else 0.0


# --- Licences ------------------------------------------------------------------------------------------------------------

## Every library material the room uses (its systems' material parameters, defaults included) is CC0 and credited;
## every asset in its credits is CC0, exists, and is in app/environments/CREDITS.md. Synthesised sounds are ours.
static func licences(doc: Dictionary, credits_file := "res://environments/CREDITS.md",
		materials_credits := "res://materials/CREDITS.md") -> Array:
	var out: Array = []
	var mat_credits := FileAccess.get_file_as_string(materials_credits)
	for id: String in materials_of(doc):
		var e := MaterialLibrary.entry(id)
		var lic := str((e.get("source", {}) as Dictionary).get("licence", ""))
		if not lic.begins_with("CC0"):
			out.append("library material %s: licence %s, not CC0" % [id, lic if lic != "" else "not given"])
		if not mat_credits.contains("`%s`" % id):
			out.append("library material %s: not in %s" % [id, materials_credits])
	var credits := FileAccess.get_file_as_string(credits_file)
	for c: Dictionary in doc.get("credits", []):
		var asset := str(c.get("asset", ""))
		if not str(c.get("licence", "")).begins_with("CC0"):
			out.append("%s: licence %s, not CC0" % [asset, c.get("licence")])
		if not FileAccess.file_exists("res://environments/" + asset):
			out.append("%s: not bundled under environments/" % asset)
		if not credits.contains(asset):
			out.append("%s: not credited in %s" % [asset, credits_file])
	return out


## The library materials a document's systems use (their material parameters, the defaults too).
static func materials_of(doc: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in doc.get("systems", []):
		var ps: Dictionary = Registry.spec(str(entry["system"])).get("params", {})
		var p := EnvDoc.with_defaults(ps, entry.get("params", {}))
		for k: String in ps:
			if ps[k].get("type") == "material" and p[k] is Dictionary and (p[k] as Dictionary).has("library"):
				var id := str(p[k]["library"])
				if not (id in out):
					out.append(id)
	for part: Variant in doc.get("parts", []):
		if part is Dictionary and (part as Dictionary).get("material") is Dictionary:
			var id := str(part["material"].get("library_material", ""))
			if id != "" and not (id in out):
				out.append(id)
	return out


# --- Names -----------------------------------------------------------------------------------------------------------------

## No real mark in any text of the document (whole words, any case).
static func names(doc: Variant) -> Array:
	var texts: Array[String] = []
	_texts(doc, texts)
	var out: Array = []
	for m: String in MARKS:
		var re := RegEx.create_from_string("(?i)(^|[^\\p{L}\\p{N}])" + _escape(m) + "($|[^\\p{L}\\p{N}])")
		for t in texts:
			if re.search(t) != null:
				out.append("\"%s\" names a real mark (%s): use a pastiche of your own" % [t.left(60), m])
				break
	return out


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += "\\" + ch if ch in ".^$*+?()[]{}|\\-" else ch
	return out


static func _texts(v: Variant, out: Array[String]) -> void:
	if v is String:
		out.append(v)
	elif v is Array:
		for x: Variant in v:
			_texts(x, out)
	elif v is Dictionary:
		for k: Variant in v:
			if k is String:
				out.append(k)
			_texts(v[k], out)


# --- No people ------------------------------------------------------------------------------------------------------------

## No system of a people kind, no object or system whose name says person, people, crowd, audience and so on.
static func no_people(doc: Dictionary) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("(?i)(^|[^a-z])(" + "|".join(PEOPLE_WORDS) + ")s?($|[^a-z])")
	for entry: Dictionary in doc.get("systems", []):
		var kind := str(Registry.spec(str(entry["system"])).get("kind", ""))
		if kind in ["people", "crowd"]:
			out.append("system %s: no people in a room" % entry["system"])
		for t: String in [str(entry["system"]), str(entry.get("id", ""))]:
			if re.search(t.replace("_", " ")) != null:
				out.append("system %s: no people in a room" % t)
	for part: Variant in doc.get("parts", []):
		if not (part is Dictionary):
			continue
		for k: String in ["name", "object", "model"]:
			var t := str((part as Dictionary).get(k, "")).replace("_", " ")
			if k != "model" and re.search(t) != null:
				out.append("%s %s: no people in a room (no person models, no crowds)" % [k, part[k]])
	return out


## Every check that needs no built room: [{check, problems}].
static func static_checks(doc: Dictionary) -> Dictionary:
	return {"schema": schema(doc), "comfort": comfort(doc), "licences": licences(doc), "names": names(doc),
			"no_people": no_people(doc)}
