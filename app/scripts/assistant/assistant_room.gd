extends "res://environments/vr_environment.gd"

## A room an assistant made (docs/assistant.md, "Rooms"): a base room (a stock room, or a whole glTF room) and, in the
## child "AssistantLayer", the parts from the room document (room_schema.gd); the base's own parts may be recoloured.
## Everything the assistant adds is under AssistantLayer: never in the player, the panel, the screen or the XR rig.
## Kept rooms are saved as recipes (user://recipes/<name>.room.json, with their models and pictures in
## <name>.files/) and listed with the other rooms (scripts/dev/recipes.gd).
##
##   build(doc, base, assets, base_id) -> this node          doc already validated; assets from room_editor.gd
##   load_saved(path) -> this node                           a kept room, read back (blocking, at a room change)
##   save(doc, assets, name) -> "" or the error              writes a kept room

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomWidget := preload("res://scripts/assistant/room_widget.gd")
const RoomMotion := preload("res://scripts/assistant/room_motion.gd")
const RoomParticles := preload("res://scripts/assistant/room_particles.gd")
const RoomBounds := preload("res://scripts/assistant/room_bounds.gd")
const GltfRoom := preload("res://scripts/env/gltf_room.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const UNLIT_TEX := preload("res://shaders/env_unlit_tex.gdshader")
const RECIPE_DIR := "user://recipes"
const LAYER := "AssistantLayer"
const GLOW_SHADER := preload("res://shaders/room_glow.gdshader")
const RoomReact := preload("res://scripts/assistant/room_react.gd")
const SKY_SHADER := preload("res://shaders/room_sky.gdshader")
const FOG_SHADER := preload("res://shaders/room_fog.gdshader")
const FOG_SIZE := 10.0
const LIT_SHADER := preload("res://shaders/room_lit.gdshader")
const CONTACT_SHADER := preload("res://shaders/room_contact.gdshader")
const LightFlicker := preload("res://scripts/assistant/room_light_flicker.gd")
## Parts whose bottom is this close to the floor get a contact shadow.
const CONTACT_REACH := 0.25
## While a room is built (and its recolours made): {lit, sky_top, sky_bottom, screen}; {} = the unlit rooms' look.
static var _lighting := {}
static var _lit_shaders := {}
const WALL_GAP := 0.15

## The room document this was built from (base64 data included until it is saved).
var doc := {}
## The room it is built on ("dim_room"; "" for a glTF base): Reset room goes back to it.
var base_id := ""
var reflection_floor_y := NAN
var _base: Node3D
var _assets := {}

static var _glow_shaders := {}
static var _sky_shaders := {}


## The base's own parts exist only once it is ready (rooms from primitives build themselves then): recolour them now.
func _ready() -> void:
	_lighting = lighting_of(doc)
	if bool(_lighting["lit"]):
		# The base room's surfaces (built by now) and the models: lit like the rest.
		light_surfaces(_base)
		for n in get_node(LAYER).get_children() if has_node(LAYER) else []:
			if n.has_node("Model"):
				light_surfaces(n.get_node("Model"))
	for r: Dictionary in doc.get("recolour", []):
		if not RoomSchema.split_match(str(r["match"])).is_empty():
			continue  # a placed model's part ("Shelf/Board"): done in build()
		var mat := material(r.get("material", {}), _assets, "recolour:" + str(r["match"]))
		for n in _base.find_children(str(r["match"]), "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).material_override = mat
	_lighting = {}
	# The fog fits the room once its walls have been measured (room_editor.gd measures them on show).
	var known: Variant = RoomBounds.cached(base_id) if base_id != "" else null
	if known is Dictionary:
		fit_fog(get_node_or_null("%s/Fog" % LAYER) as Node3D, known)


## The room document's seats when it has them (the floor point under the viewer), else the base room's.
func get_seats() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if doc.get("seats") is Array and not (doc["seats"] as Array).is_empty():
		for s: Dictionary in doc["seats"]:
			out.append(RoomSchema.vec3(s["position"]))
		return out
	if _base != null and _base.has_method("get_seats"):
		return _base.get_seats()
	return out


func get_seat_names() -> Array[String]:
	var out: Array[String] = []
	if doc.get("seats") is Array:
		for s: Dictionary in doc["seats"]:
			out.append(str(s["name"]))
	return out


## Each seat's facing as a yaw (radians; Basis(UP, yaw) turns -Z to it), or NAN: the base's seats keep the room's
## way round.
func get_seat_yaws() -> Array[float]:
	var out: Array[float] = []
	if doc.get("seats") is Array:
		var screen: Dictionary = doc.get("screen") if doc.get("screen") is Dictionary else {}
		if screen.is_empty():
			screen = {"center": RoomBounds._v(screen_anchor.transform.origin)} if screen_anchor != null else {}
		for s: Dictionary in doc["seats"]:
			var f := RoomSchema.seat_facing(s, screen)
			out.append(atan2(-f.x, -f.z))
	return out


## The seat a viewer starts at when they open the room themselves (not when an assistant changes it), or -1.
func get_default_seat() -> int:
	return get_seat_names().find(str(doc.get("default_seat", ""))) if doc.get("default_seat") is String else -1


## The room has its own screen: Reset room keeps the room and puts the screen back there.
func has_home_screen() -> bool:
	return doc.get("screen") is Dictionary and bool((doc["screen"] as Dictionary).get("home", true))


## Spatial audio (scripts/play/spatial_audio.gd): a stock base room's speakers and acoustics; a glTF base, the
## standard layout. The room document has no say in it (the schema is unchanged).
func get_sound_room() -> Dictionary:
	var base := get_node_or_null("Base")
	return base.get_sound_room() if base != null and base.has_method("get_sound_room") else {}


## The room's own screen curve (0..1), or -1 to leave the viewer's.
func get_home_curve() -> float:
	return float(doc["screen"].get("curve", 0.0)) if has_home_screen() else -1.0


func on_screen_changed(screen_transform: Transform3D, size: Vector2) -> void:
	if _base != null and _base.has_method("on_screen_changed"):
		_base.on_screen_changed(screen_transform, size)


## The room's own parts (the base's meshes) and the assistant's, for room_state: each one's colour, and its library
## material's id when it shows one.
func describe_parts() -> Dictionary:
	var stock: Array = []
	if _base != null:
		for n in _base.find_children("*", "GeometryInstance3D", true, false):
			var d := {"name": str(n.name), "color": _colour_of(n as GeometryInstance3D)}
			if material_id_of(n as GeometryInstance3D) != "":
				d["material"] = material_id_of(n as GeometryInstance3D)
			if effect_id_of(n as GeometryInstance3D) != "":
				d["effect"] = effect_id_of(n as GeometryInstance3D)
			stock.append(d)
	return {"stock": stock}


## What a surface shows: its override, else its first surface's material.
static func _shown_material(g: GeometryInstance3D) -> Material:
	var m: Material = g.material_override
	if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh != null \
			and (g as MeshInstance3D).mesh.get_surface_count() > 0:
		m = (g as MeshInstance3D).get_active_material(0)
	return m


## The library material a surface shows ("oak_planks"; under an effect too), "" when none.
static func material_id_of(g: GeometryInstance3D) -> String:
	var m := _shown_material(g)
	if m != null and m.has_meta("library_material"):
		return str(m.get_meta("library_material"))
	return MaterialLibrary.id_of(m)


## The effect a surface shows ("plasma"), "" when none.
static func effect_id_of(g: GeometryInstance3D) -> String:
	var m := _shown_material(g)
	return str(m.get_meta("effect", "")) if m != null else ""


## A surface's colour as "#rrggbb": its plain colour, or what its library material shows on average (the swatch
## times the tint, under an effect too); "" when it has none the app can read.
static func _colour_of(g: GeometryInstance3D) -> String:
	var m := _shown_material(g)
	if MaterialLibrary.is_library(m):
		return "#" + MaterialLibrary.shown_colour(m).to_html(false)
	if m != null and m.has_meta("shown_colour"):
		return "#" + (m.get_meta("shown_colour") as Color).to_html(false)
	if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("albedo") is Color:
		return "#" + ((m as ShaderMaterial).get_shader_parameter("albedo") as Color).to_html(false)
	if m is BaseMaterial3D:
		return "#" + (m as BaseMaterial3D).albedo_color.to_html(false)
	return ""


## Builds the room. assets: {"models": {part name: {node}}, "images": {key: Image}, "base_model": {node}}.
static func build(p_doc: Dictionary, base: Node3D, assets: Dictionary, p_base_id: String) -> Node3D:
	_lighting = lighting_of(p_doc)
	var room: Node3D = (load("res://scripts/assistant/assistant_room.gd") as GDScript).new()
	room.name = "AssistantRoom"
	room.doc = p_doc
	room.base_id = p_base_id
	room.display_name = str(p_doc.get("name", "")) if str(p_doc.get("name", "")) != "" else "Assistant room"
	base.name = "Base"
	room.add_child(base)
	room._base = base
	var anchor := Marker3D.new()
	anchor.name = "ScreenAnchor"
	anchor.transform = base.get_screen_anchor() if base.has_method("get_screen_anchor") else \
			Transform3D(Basis(), Vector3(0, NOMINAL_EYE_HEIGHT, -3))
	room.add_child(anchor)
	room.screen_anchor = anchor
	room.default_screen_width = float(base.get("default_screen_width")) if base.get("default_screen_width") != null \
			else 3.0
	if p_doc.get("screen") is Dictionary:
		# The room's own screen: its centre, facing +Z the way the picture faces, its width.
		var s: Dictionary = p_doc["screen"]
		var facing := RoomSchema.screen_facing(s)
		anchor.transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), RoomSchema.vec3(s["center"]))
		room.default_screen_width = float(s["size"][0])
	var light: Dictionary = p_doc.get("light", {})
	room.ambient_level = float(light.get("ambient", base.get("ambient_level") if base.get("ambient_level") != null
			else 0.1))
	room.screen_glow = float(light.get("screen_glow", base.get("screen_glow") if base.get("screen_glow") != null
			else 0.5))
	room.reacts_to_film = bool(base.get("reacts_to_film")) if base.get("reacts_to_film") != null else false
	if base.get("reflection_floor_y") != null:
		room.reflection_floor_y = float(base.get("reflection_floor_y"))
	room._assets = assets
	var layer := Node3D.new()
	layer.name = LAYER
	room.add_child(layer)
	var sky: Dictionary = p_doc.get("sky", {})
	if sky.has("color") or assets.get("images", {}).has("sky") or sky.has("stars") or sky.has("clouds") \
			or sky.get("effect") is Dictionary:
		var sphere := SphereMesh.new()
		sphere.radius = 400.0
		sphere.height = 800.0
		sphere.flip_faces = true
		var sm := sky_material(sky, assets.get("images", {}).get("sky"))
		var smi := MeshInstance3D.new()
		smi.name = "Sky"
		smi.mesh = sphere
		smi.material_override = sm
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layer.add_child(smi)
	var atmosphere: Dictionary = p_doc.get("atmosphere", {})
	if atmosphere.has("fog"):
		layer.add_child(fog(atmosphere["fog"]))
	var motion: Node = RoomMotion.new()
	motion.name = "Motion"
	_shared_materials.clear()
	for p: Dictionary in p_doc.get("parts", []):
		var node := _part(p, assets)
		layer.add_child(node)
		if p.has("motion"):
			motion.add(node, p)
	_recolour_parts(layer, p_doc, assets)
	if motion.count() > 0:
		room.add_child(motion)
	else:
		motion.free()
	var react: Node = RoomReact.new()
	react.name = "React"
	for mi in layer.find_children("*", "MeshInstance3D", true, false):
		var gm := (mi as MeshInstance3D).material_override
		if gm is ShaderMaterial and gm.has_meta("react"):
			react.add(gm, str(gm.get_meta("react")))
	var lighting := lighting_of(p_doc)
	if float(lighting.get("screen", 0.0)) > 0.0:
		# The film's light needs the bias light's copy of the picture, kept fresh even with the bias light off.
		react.add(null, "brightness")
	if react.count() > 0:
		room.add_child(react)
	else:
		react.free()
	_add_lights(room, layer, p_doc)
	if bool((p_doc.get("light", {}) if p_doc.get("light") is Dictionary else {}).get("contact_shadows", true)):
		_add_contact_shadows(layer, p_doc)
	_lighting = {}
	return room


## The key light (sun or moon; its shadows, fitted to the room) and the point and spot lights, with their flicker.
static func _add_lights(room: Node3D, layer: Node3D, p_doc: Dictionary) -> void:
	var light: Dictionary = p_doc.get("light", {}) if p_doc.get("light") is Dictionary else {}
	if light.get("key") is Dictionary:
		var o := RoomSchema.with_defaults(RoomSchema.LIGHT_OPTIONS["key"], light["key"])
		var travel: Vector3
		if o["direction"] != null and Vector3(RoomSchema.vec3(o["direction"])).length() > 0.01:
			travel = RoomSchema.vec3(o["direction"]).normalized()
		else:
			var el := deg_to_rad(float(o["elevation"]))
			var az := deg_to_rad(float(o["azimuth"]))
			travel = -Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		var key := DirectionalLight3D.new()
		key.name = "KeyLight"
		var up := Vector3.UP if absf(travel.y) < 0.99 else Vector3.FORWARD
		key.transform = Transform3D(Basis.looking_at(travel, up), Vector3.ZERO)
		key.light_color = RoomSchema.to_color(o["color"])
		key.light_energy = float(o["energy"])
		key.light_specular = 0.5
		key.shadow_enabled = bool(o["shadows"])
		if key.shadow_enabled:
			key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			key.directional_shadow_max_distance = shadow_distance(p_doc)
			key.shadow_blur = 1.5
			key.shadow_bias = 0.03
			key.shadow_normal_bias = 1.5
			room.set_meta("key_shadows", true)
		room.add_child(key)
	var flicker: Node = LightFlicker.new()
	flicker.name = "LightFlicker"
	var i := 0
	for l: Dictionary in p_doc.get("lights", []) if p_doc.get("lights") is Array else []:
		var o := RoomSchema.with_defaults(RoomSchema.POINT_LIGHT_OPTIONS, l)
		var node: Light3D
		if str(o["type"]) == "spot":
			var spot := SpotLight3D.new()
			spot.spot_range = float(o["range"])
			spot.spot_angle = float(o["angle"])
			node = spot
		else:
			var omni := OmniLight3D.new()
			omni.omni_range = float(o["range"])
			node = omni
		node.name = str(o["name"]) if str(o["name"]) != "" else "Light%d" % i
		node.light_color = RoomSchema.to_color(o["color"])
		node.light_energy = float(o["energy"])
		node.shadow_enabled = false
		var at := Vector3.ZERO
		var parent: Node3D = layer
		var attach := str(o["attach"])
		if attach != "" and layer.has_node(attach):
			parent = layer.get_node(attach) as Node3D
			at = RoomSchema.vec3(o["offset"])
		elif o["position"] != null:
			at = RoomSchema.vec3(o["position"])
		var aim := RoomSchema.vec3(o["direction"]) if node is SpotLight3D else Vector3.FORWARD
		if aim.length() < 0.01:
			aim = Vector3.DOWN
		var up := Vector3.UP if absf(aim.normalized().y) < 0.99 else Vector3.FORWARD
		node.transform = Transform3D(Basis.looking_at(aim, up), at)
		parent.add_child(node)
		if o["flicker"] is Dictionary:
			var f := RoomSchema.with_defaults(RoomSchema.FLICKER_OPTIONS, o["flicker"])
			flicker.add(node, float(o["energy"]), float(f["rate"]), float(f["swing"]),
					float(str(node.name).md5_text().substr(0, 4).hex_to_int()) / 65535.0)
		i += 1
	if flicker.count() > 0:
		room.add_child(flicker)
	else:
		flicker.free()


## How far the key light's shadows reach: the farthest part from the room's middle, and some, within 8..60 m.
static func shadow_distance(p_doc: Dictionary) -> float:
	var far := 12.0
	for p: Dictionary in p_doc.get("parts", []):
		var pos := RoomSchema.vec3(p.get("position", [0, 0, 0]))
		var size: Array = p.get("size", [1.0])
		var big := 0.0
		for v: Variant in size:
			big = maxf(big, float(v))
		far = maxf(far, Vector2(pos.x, pos.z).length() + big)
	return clampf(far + 4.0, 8.0, 60.0)


## A soft contact shadow (room_contact.gdshader) under each solid part that stands on the floor (y = 0).
static func _add_contact_shadows(layer: Node3D, p_doc: Dictionary) -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)
	for p: Dictionary in p_doc.get("parts", []):
		if not (str(p.get("type", "")) in ["box", "sphere", "cylinder", "model"]) or str(p.get("widget", "")) != "":
			continue
		var node := layer.get_node_or_null(str(p["name"])) as Node3D
		if node == null or not node.has_meta("local_aabb"):
			continue
		if not RoomSchema.stands_on_floor(p):
			continue
		var box: AABB = node.transform * (node.get_meta("local_aabb") as AABB)
		if box.position.y > CONTACT_REACH or box.end.y < 0.0:
			continue
		var half := Vector2(box.size.x, box.size.z) * 0.5
		var reach := clampf(maxf(half.x, half.y) * 0.5, 0.08, 0.6)
		var m := ShaderMaterial.new()
		m.shader = CONTACT_SHADER
		m.set_shader_parameter("half_size", half)
		m.set_shader_parameter("reach", reach)
		# Fainter as the part's bottom rises off the floor.
		m.set_shader_parameter("strength", 0.45 * (1.0 - clampf(box.position.y / CONTACT_REACH, 0.0, 1.0)))
		var mi := MeshInstance3D.new()
		mi.name = "Contact_" + str(p["name"])
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(box.get_center().x, 0.004, box.get_center().z)
		mi.scale = Vector3(half.x + reach, 1.0, half.y + reach)
		layer.add_child(mi)


## Part-level recolours ("Shelf/Board", room_schema.gd): each entry's material fields over what the part showed (the
## whole model's material when it has one, else the part's own colour), in the document's order, so an entry with only
## an emission keeps the part's colour and a later entry wins where two set the same field. A picture replaces the
## colour unless the entry gives one. Parts that end up alike share one material (two shelves painted the same).
static func _recolour_parts(layer: Node3D, p_doc: Dictionary, assets: Dictionary) -> void:
	var looks := {}
	var whole := {}
	for p: Dictionary in p_doc.get("parts", []):
		if p.get("material") is Dictionary and not (p["material"] as Dictionary).is_empty():
			whole[str(p["name"])] = p["material"]
	for r: Dictionary in p_doc.get("recolour", []):
		var split := RoomSchema.split_match(str(r["match"]))
		if split.is_empty():
			continue
		var m: Dictionary = r.get("material", {}) if r.get("material") is Dictionary else {}
		for mi: MeshInstance3D in part_targets(layer, str(r["match"])):
			if not looks.has(mi):
				var node: Node = mi
				while node != null and node.get_parent() != layer:
					node = node.get_parent()
				var placed := str(node.name) if node != null else ""
				var base: Dictionary = (whole[placed] as Dictionary).duplicate(true) if whole.has(placed) \
						else {"color": _colour_of(mi) if _colour_of(mi) != "" else "#b0b0b0"}
				# The whole model's picture, read under its part's key.
				looks[mi] = {"m": base, "image": "part:" + placed if base.has("texture") or base.has("texture_file")
						else ""}
			var look: Dictionary = looks[mi]
			var before: Dictionary = (look["m"] as Dictionary).duplicate(true)
			if m.has("texture") or m.has("texture_file"):
				before.erase("color")
				look["image"] = "recolour:" + str(r["match"])
			elif m.has("library_material"):
				look["image"] = ""
			# A library material and a picture exclude each other (RoomSchema.merge_material()).
			look["m"] = RoomSchema.merge_material(before, m)
	for mi: MeshInstance3D in looks:
		var look: Dictionary = looks[mi]
		var key: String = look["image"]
		var plain: Dictionary = (look["m"] as Dictionary).duplicate()
		plain.erase("texture")
		plain.erase("texture_file")
		var share := JSON.stringify(plain, "", true) + key
		if not _shared_materials.has(share):
			_shared_materials[share] = material(look["m"], assets, key)
		mi.material_override = _shared_materials[share]


## Materials shared by the parts of the room being built (cleared at each build).
static var _shared_materials := {}


## The parts of placed models a part-level match reaches ("Shelf*/Board?": a pattern on each side), in the layer.
static func part_targets(layer: Node, match: String) -> Array:
	var s := RoomSchema.split_match(match)
	var out: Array = []
	if s.is_empty() or layer == null:
		return out
	for n in layer.get_children():
		if not (n is Node3D) or not n.has_node("Model") or not str(n.name).match(s[0]):
			continue
		var parts := RoomModel.parts_of(n.get_node("Model"))
		for pn: String in parts:
			if pn.match(s[1]):
				out.append(parts[pn])
	return out


## The models placed from the object library (parts with "object"), for room_state and the Room tab:
## [{name, object, parts: [{name, color, material: the library material's id or "", effect: the effect's id or "",
## recolour: the entry that sets it last, or null}]}].
static func placed_objects(env: Node) -> Array:
	var out: Array = []
	if env == null or env.get_script() != load("res://scripts/assistant/assistant_room.gd"):
		return out
	var d: Dictionary = env.get("doc")
	var layer: Node = env.get_node_or_null(LAYER)
	for p: Dictionary in d.get("parts", []):
		if not p.has("object"):
			continue
		var node: Node = layer.get_node_or_null(str(p["name"])) if layer != null else null
		var parts: Array = []
		var by_name := RoomModel.parts_of(node.get_node_or_null("Model") if node != null else null)
		for pn: String in by_name:
			var set_by: Variant = null
			for r: Dictionary in d.get("recolour", []):
				var s := RoomSchema.split_match(str(r["match"]))
				if not s.is_empty() and str(p["name"]).match(s[0]) and pn.match(s[1]):
					set_by = r["match"]
			parts.append({"name": pn, "color": _colour_of(by_name[pn]), "material": material_id_of(by_name[pn]),
					"effect": effect_id_of(by_name[pn]), "recolour": set_by})
		out.append({"name": p["name"], "object": p["object"], "position": p.get("position", [0, 0, 0]),
				"rotation": p.get("rotation", [0, 0, 0]), "scale": p.get("scale", 1.0), "parts": parts})
	return out


func _enter_tree() -> void:
	if has_meta("key_shadows"):
		RenderingServer.directional_shadow_atlas_set_size(RoomSchema.KEY_SHADOW_ATLAS, true)


func _exit_tree() -> void:
	if has_meta("key_shadows"):
		RenderingServer.directional_shadow_atlas_set_size(int(ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/size", 4096)), true)


## CylinderMesh's side takes the top half of the UV square (v 0..0.5; the caps the bottom half): so many repeats of the
## UVs' v per metre of height, for a pattern in metres.
const CYLINDER_SIDE_V := 2.0


static func _part(p: Dictionary, assets: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = str(p["name"])
	node.set_meta("assistant_part", true)
	var pos: Array = p.get("position", [0, 0, 0])
	var rot: Array = p.get("rotation", [0, 0, 0])
	var s: Variant = p.get("scale", 1.0)
	var scale := Vector3.ONE * float(s) if (s is float or s is int) else Vector3(float(s[0]), float(s[1]), float(s[2]))
	node.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])),
			deg_to_rad(float(rot[2])))).scaled(scale), Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
	var type := str(p["type"])
	var size: Array = p.get("size", [1.0])
	var widget := str(p.get("widget", ""))
	# A library material lies on boxes, planes and models by their own axes in metres; spheres and cylinders have no
	# flat faces, so their UVs, repeated to keep the pattern's size in metres (as SphereMesh and CylinderMesh lay them).
	var mesh_uv := Vector2.ZERO
	if type == "sphere":
		mesh_uv = Vector2(PI * float(size[0]) * scale.x, PI * float(size[0]) * 0.5 * scale.y)
	elif type == "cylinder":
		mesh_uv = Vector2(PI * float(size[0]) * scale.x, float(size[1]) * CYLINDER_SIDE_V * scale.y)
	var mat: Material = material(p.get("material", {}), assets, "part:" + str(p["name"]), mesh_uv)
	if widget == "screen_glow":
		mat = glow_material(RoomSchema.to_color(p.get("material", {}).get("color", "#ffffff")),
				RoomSchema.widget_options("screen_glow", p.get("widget_options", {})))
	var mesh: Mesh
	var face := Vector2.ONE
	var face_xf := Transform3D()
	var round_face := false
	## The part's extent in its own frame (before its rotation and scale): the room's warnings use it.
	var local := AABB()
	var per_surface := false
	match type:
		"box":
			var bs := Vector3(float(size[0]), float(size[1]), float(size[2]))
			var uv := str(p.get("material", {}).get("uv", "atlas")) if p.get("material") is Dictionary else "atlas"
			if uv == "atlas" or MaterialLibrary.is_library(mat):
				var b := BoxMesh.new()
				b.size = bs
				mesh = b
			else:
				var plain: Material = mat
				if uv == "front_only":
					var m2: Dictionary = (p.get("material", {}) as Dictionary).duplicate()
					for k in ["texture", "texture_file", "uv"]:
						m2.erase(k)
					if not (p["material"] as Dictionary).has("self_lit"):
						m2.erase("self_lit")
					var front: Dictionary = (p["material"] as Dictionary).duplicate()
					front.erase("color")
					front.erase("emission")
					mat = material(front, assets, "part:" + str(p["name"]))
					plain = material(m2, {}, "")
				mesh = box_mesh(bs, uv, mat, plain)
				per_surface = true
			face = Vector2(bs.x, bs.y)
			face_xf = Transform3D(Basis(), Vector3(0, 0, bs.z * 0.5 + 0.002))
			local = AABB(-bs * 0.5, bs)
		"sphere":
			var sp := SphereMesh.new()
			sp.radius = float(size[0]) * 0.5
			sp.height = float(size[0])
			mesh = sp
			face = Vector2.ONE * sp.radius * 1.2
			face_xf = Transform3D(Basis(), Vector3(0, 0, sp.radius + 0.002))
			local = AABB(-Vector3.ONE * sp.radius, Vector3.ONE * sp.height)
		"cylinder":
			var cy := CylinderMesh.new()
			cy.top_radius = float(size[0]) * 0.5
			cy.bottom_radius = cy.top_radius
			cy.height = float(size[1])
			mesh = cy
			face = Vector2.ONE * float(size[0])
			round_face = true
			face_xf = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, cy.height * 0.5 + 0.002, 0))
			local = AABB(Vector3(-cy.top_radius, -cy.height * 0.5, -cy.top_radius),
					Vector3(cy.top_radius * 2.0, cy.height, cy.top_radius * 2.0))
		"plane":
			var pl := PlaneMesh.new()
			pl.size = Vector2(float(size[0]), float(size[1]))
			mesh = pl
			face = pl.size
			face_xf = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.002, 0))
			local = AABB(Vector3(-pl.size.x * 0.5, 0, -pl.size.y * 0.5), Vector3(pl.size.x, 0, pl.size.y))
		"model":
			var m: Dictionary = assets.get("models", {}).get(str(p["name"]), {})
			if m.has("node"):
				var model: Node3D = (m["node"] as Node).duplicate()
				model.name = "Model"
				node.add_child(model)
				if p.get("material", {}) is Dictionary and not (p.get("material", {}) as Dictionary).is_empty():
					for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
						mi.material_override = mat
				var box := _aabb(model)
				face = Vector2(maxf(box.size.x, 0.05), maxf(box.size.y, 0.05))
				face_xf = Transform3D(Basis(), Vector3(box.get_center().x, box.get_center().y, box.end.z + 0.002))
				local = box
		"text":
			local = _text(node, p)
		"particles":
			var area := Vector3(float(size[0]), float(size[1]), float(size[2]))
			RoomParticles.add_when_safe(node, RoomParticles.build(p))
			local = AABB(-area * 0.5, area)
	node.set_meta("local_aabb", local)
	fit_effect(mat, (p["material"] as Dictionary).get("effect") if p.get("material") is Dictionary else null, local)
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		if not per_surface:
			mi.material_override = mat
		# Solid parts cast the key light's shadow; see-through ones and glows do not.
		var fx: Variant = (p["material"] as Dictionary).get("effect") if p.get("material") is Dictionary else null
		var fx_blend := str(EffectLibrary.entry(str(fx.get("name", ""))).get("blend", "")) if fx is Dictionary else ""
		var see_through: bool = fx_blend in ["alpha", "add"] or (mat is ShaderMaterial
				and (mat as ShaderMaterial).shader != null
				and (mat as ShaderMaterial).shader.code.contains("#define ALPHA_BLEND"))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if see_through or widget == "screen_glow" \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(mi)
	if widget != "" and widget != "screen_glow":
		var w: Node3D = RoomWidget.new()
		w.name = "Widget"
		w.kind = widget
		w.options = RoomSchema.widget_options(widget, p.get("widget_options", {}))
		w.face = face
		w.round_face = round_face
		w.transform = face_xf
		node.add_child(w)
	return node


## BoxMesh's piece of the picture per face (its 3 x 2 layout, measured from the engine: tests/test_assistant_room.gd):
## the top row front (+Z), right (+X), back (-Z); the bottom row left (-X), top (+Y), bottom (-Y).
const BOX_CELLS := {Vector3i(0, 0, 1): Vector2(0, 0), Vector3i(1, 0, 0): Vector2(1.0 / 3.0, 0),
		Vector3i(0, 0, -1): Vector2(2.0 / 3.0, 0), Vector3i(-1, 0, 0): Vector2(0, 0.5),
		Vector3i(0, 1, 0): Vector2(1.0 / 3.0, 0.5), Vector3i(0, -1, 0): Vector2(2.0 / 3.0, 0.5)}


## A box whose faces each show the whole picture, the right way up as on BoxMesh (each_face, one surface), or with the
## picture on the front (+Z) face only and `plain` on the other five (front_only, two surfaces).
static func box_mesh(size: Vector3, uv: String, textured: Material, plain: Material) -> ArrayMesh:
	var b := BoxMesh.new()
	b.size = size
	var a: Array = b.surface_get_arrays(0)
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	for i in uvs.size():
		var cell: Vector2 = BOX_CELLS.get(Vector3i(normals[i].round()), Vector2.ZERO)
		uvs[i] = ((uvs[i] - cell) * Vector2(3.0, 2.0)).clamp(Vector2.ZERO, Vector2.ONE)
	a[Mesh.ARRAY_TEX_UV] = uvs
	var out := ArrayMesh.new()
	if uv != "front_only":
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(0, textured)
		return out
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var front := PackedInt32Array()
	var rest := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var tri := idx.slice(t, t + 3)
		if normals[idx[t]].z > 0.5:
			front.append_array(tri)
		else:
			rest.append_array(tri)
	var af := a.duplicate()
	af[Mesh.ARRAY_INDEX] = front
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, af)
	out.surface_set_material(0, textured)
	var ar := a.duplicate()
	ar[Mesh.ARRAY_INDEX] = rest
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
	out.surface_set_material(1, plain)
	return out


## A text part: a Label3D in a sharp (MSDF) font, a line `size[0]` metres high, facing +Z, centred on the part's
## origin; an optional panel behind it. Returns the text's extent.
static func _text(node: Node3D, p: Dictionary) -> AABB:
	var o := RoomSchema.text_options(p.get("text_options", {}))
	var line_h := float(p.get("size", [RoomSchema.TEXT_LINE_DEFAULT])[0])
	var font := text_font(str(o["weight"]) == "bold")
	var font_px := TEXT_FONT_PX
	var px := line_h / maxf(font.get_height(font_px), 1.0)
	var label := Label3D.new()
	label.name = "Text"
	label.text = str(p["text"])
	label.font = font
	label.font_size = font_px
	label.pixel_size = px
	label.outline_size = 0
	label.modulate = RoomSchema.to_color(o["color"])
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER,
			"right": HORIZONTAL_ALIGNMENT_RIGHT}[str(o["align"])]
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var max_w := float(o["max_width"])
	var width_px := -1.0
	if max_w > 0.0:
		width_px = max_w / px
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = width_px
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var measured := font.get_multiline_string_size(label.text, label.horizontal_alignment, width_px, font_px, -1,
			TextServer.BREAK_MANDATORY | (TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE if max_w > 0.0
			else 0)) * px
	var w := maxf(measured.x, max_w) if max_w > 0.0 else measured.x
	var size := Vector2(w, maxf(measured.y, line_h))
	if o["background"] != null:
		var pad := line_h * 0.3
		var quad := QuadMesh.new()
		quad.size = size + Vector2.ONE * pad * 2.0
		var bg := StandardMaterial3D.new()
		bg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bg.albedo_color = RoomSchema.to_color(o["background"])
		if bg.albedo_color.a < 1.0:
			bg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var back := MeshInstance3D.new()
		back.name = "Background"
		back.mesh = quad
		back.material_override = bg
		back.position = Vector3(0, 0, -0.003)
		back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(back)
		size = quad.size
	node.add_child(label)
	return AABB(Vector3(-size.x * 0.5, -size.y * 0.5, -0.003), Vector3(size.x, size.y, 0.003))


const TEXT_FONT := "res://ui/fonts/inter_regular.res"
## Glyphs are drawn this many pixels high; MSDF keeps them sharp at any distance.
const TEXT_FONT_PX := 64
static var _fonts := {}


## The panel's font as a multichannel signed distance field (sharp edges at any size), regular or bold.
static func text_font(bold: bool) -> Font:
	if _fonts.has(bold):
		return _fonts[bold]
	if not _fonts.has(false):
		var base: Font = load(TEXT_FONT) as Font
		if base is FontFile:
			var f := (base as FontFile).duplicate() as FontFile
			f.multichannel_signed_distance_field = true
			f.msdf_pixel_range = 8
			f.msdf_size = 48
			f.generate_mipmaps = true
			base = f
		_fonts[false] = base if base != null else ThemeDB.fallback_font
	if bold:
		var v := FontVariation.new()
		v.base_font = _fonts[false]
		v.variation_embolden = 0.9
		_fonts[true] = v
	return _fonts[bold]


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := Transform3D()
		var cur: Node = mi
		while cur != null and cur != n:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## The rooms' unlit material from a material object (room_schema.gd). What shows (env_unlit_tex.gdshader):
##   color x texture x light + emission x emission_strength
## light is the room's light (its ambient level and the screen's spill, as on the stock rooms' walls), or 1 when
## self_lit: the surface shows at its own brightness whatever the room's light. A part with a texture is self_lit
## unless it says "self_lit": false, and its colour defaults to white, so a picture looks like the picture.
## With "library_material" the material library's shared material instead (library_surface()); an id it doesn't know
## is left out and the rest applies (room_editor.gd warns). mesh_uv: see library_surface().
static func material(m: Dictionary, assets: Dictionary, image_key: String, mesh_uv := Vector2.ZERO) -> Material:
	if m.has("library_material") and MaterialLibrary.has(str(m["library_material"])) and m.get("effect") is Dictionary:
		# A layered look: the effect over the library material's picture (its own material, not shared).
		var layered := ShaderMaterial.new()
		if _effect_layered(layered, m, image_key, mesh_uv) == "":
			layered.set_shader_parameter("self_lit", bool(m.get("self_lit", false)))
			if m.has("emission"):
				layered.set_shader_parameter("emission", RoomSchema.to_color(m["emission"])
						* float(m.get("emission_strength", 1.0)))
			return layered
	if m.has("library_material"):
		var lib := library_surface(m, mesh_uv)
		if lib != null and not (m.get("effect") is Dictionary):
			return lib
		m = m.duplicate()
		m.erase("library_material")
		for k: String in RoomSchema.LIBRARY_OPTIONS:
			m.erase(k)
	var mat := ShaderMaterial.new()
	var img: Image = assets.get("images", {}).get(image_key)
	var textured := img != null or m.has("texture") or m.has("texture_file")
	var colour := RoomSchema.to_color(m.get("color", "#ffffff" if textured else "#b0b0b0"))
	var lit := bool(_lighting.get("lit", false))
	# In a lit room a picture is lit like everything else (stone, wood); self_lit is for things that glow.
	var self_lit := bool(m.get("self_lit", textured and not lit))
	var mode := alpha_mode(m, colour, bool(assets.get("alpha", {}).get(image_key, false)))
	mat.shader = unlit_shader(mode)
	if m.get("effect") is Dictionary:
		_effect(mat, m["effect"], image_key)
	elif lit and not self_lit:
		mat.shader = lit_shader(mode)
		_light_material(mat)
		mat.set_shader_parameter("roughness", float(m.get("roughness", 0.85)))
		# Pictures keep their colours (no highlight); plain surfaces get a little sheen.
		mat.set_shader_parameter("specular", 0.0 if textured else 0.15)
	mat.set_shader_parameter("albedo", colour)
	mat.set_shader_parameter("alpha", colour.a)
	mat.set_shader_parameter("self_lit", self_lit)
	if m.has("emission"):
		mat.set_shader_parameter("emission", RoomSchema.to_color(m["emission"]) * float(m.get("emission_strength",
				1.0)))
	if img != null:
		mat.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("use_texture", true)
	return mat


## A material object's library material (scripts/env/material_library.gd) as the library's shared ShaderMaterial, so
## every surface with the same material and options shares one material and its textures: "color" is the colour it
## shows on average (the library's colour option), "tint" multiplies it, "tiling" metres per repeat, "triplanar",
## emission x emission_strength added; in a room with real lighting (and not self_lit) its lit form. mesh_uv: metres
## the mesh's UV square spans (spheres, cylinders: no flat faces), so the pattern keeps its size in metres there;
## zero: the surface's own axes in metres (boxes, planes, models). Null when the library doesn't know the id.
static func library_surface(m: Dictionary, mesh_uv := Vector2.ZERO) -> ShaderMaterial:
	var id := str(m.get("library_material", ""))
	if not MaterialLibrary.has(id):
		return null
	var o := {}
	if m.has("color"):
		o["colour"] = RoomSchema.to_color(m["color"])
	if m.has("tint"):
		o["tint"] = RoomSchema.to_color(m["tint"])
	if m.has("tiling"):
		o["tiling"] = float(m["tiling"])
	if bool(m.get("triplanar", false)):
		o["triplanar"] = true
	elif mesh_uv != Vector2.ZERO:
		var tiling := float(m.get("tiling", MaterialLibrary.entry(id).get("tiling", 1.0)))
		# Whole repeats round the circumference, so the UVs' seam doesn't show.
		o["uv"] = true
		o["repeat"] = Vector2(maxf(roundf(mesh_uv.x / tiling), 1.0), maxf(snappedf(mesh_uv.y / tiling, 0.01), 0.01))
	if m.has("emission"):
		o["emission"] = RoomSchema.to_color(m["emission"]) * float(m.get("emission_strength", 1.0))
	if bool(_lighting.get("lit", false)) and not bool(m.get("self_lit", false)):
		o["lit"] = {"sky_top": _lighting["sky_top"], "sky_bottom": _lighting["sky_bottom"],
				"screen": _lighting["screen"]}
	return MaterialLibrary.get_material(id, o)


const EffectLibrary := preload("res://scripts/effects/effect_library.gd")


## A named effect (the effect library, docs/effects.md; RoomSchema.EFFECTS) on a material: its shader and options
## (EffectLibrary.apply: the group shader compiled with the effect's define, the defaults for what isn't given, a seed
## from the part so copies don't pulse in step, a second pass for toon_outline), and for a reactive one the film's path
## (meta "react": build() hands it to the room's RoomReact node).
static func _effect(mat: ShaderMaterial, fx: Dictionary, key: String) -> void:
	var opts := fx.duplicate()
	opts.erase("name")
	EffectLibrary.apply(mat, str(fx["name"]), opts, EffectLibrary.seed_of(key))
	mat.set_meta("effect", str(fx["name"]))
	var react := str(EffectLibrary.entry(str(fx["name"])).get("react", ""))
	if react != "":
		mat.set_meta("react", react)


## A layered look: an effect that keeps the surface under it over a library material's picture (its albedo map, in
## its colour or tint, repeating at its tiling): on the part's own axes in metres (triplanar), or by the mesh's UVs
## where it has no flat faces (mesh_uv, as library_surface()) and for the first eight (UV only). "" or why it can't.
static func _effect_layered(mat: ShaderMaterial, m: Dictionary, key: String, mesh_uv: Vector2) -> String:
	var id := str(m["library_material"])
	var fx: Dictionary = m["effect"]
	var opts := fx.duplicate()
	opts.erase("name")
	var e := MaterialLibrary.entry(id)
	var tint := MaterialLibrary.tint_for(id, RoomSchema.to_color(m["color"])) if m.has("color") \
			else Color.from_string(str(e.get("tint", "#ffffff")), Color.WHITE)
	if m.has("tint"):
		tint *= RoomSchema.to_color(m["tint"])
	var tiling := maxf(float(m.get("tiling", e.get("tiling", 1.0))), 0.01)
	var base := {"texture": MaterialLibrary.textures(id).get("albedo"), "color": tint, "triplanar": tiling}
	if mesh_uv != Vector2.ZERO:
		base = {"texture": base["texture"], "color": tint, "uv_scale": mesh_uv / tiling}
	var seed_value := EffectLibrary.seed_of(key)
	var why := EffectLibrary.apply_layered(mat, str(fx["name"]), opts, seed_value, base)
	if why != "" and base.has("triplanar"):
		base.erase("triplanar")
		base["uv_scale"] = Vector2.ONE
		why = EffectLibrary.apply_layered(mat, str(fx["name"]), opts, seed_value, base)
	var react := str(EffectLibrary.entry(str(fx["name"])).get("react", ""))
	if why == "" and react != "":
		mat.set_meta("react", react)
	if why == "":
		# What it shows, for room_state: the effect over the library material.
		mat.set_meta("effect", str(fx["name"]))
		mat.set_meta("library_material", id)
		mat.set_meta("shown_colour", (Color.from_string(str(e.get("swatch", "#ffffff")), Color.WHITE).srgb_to_linear()
				* tint.srgb_to_linear()).linear_to_srgb())
	return why


## Sizes an effect's shader can't know, from the part's own extent (its frame before rotation and scale) when the
## document leaves them out: wipe's and scan_in's size (the length along their axis), wind_sway's foot and height.
static func fit_effect(mat: Material, fx: Variant, local: AABB) -> void:
	if not (mat is ShaderMaterial) or not (fx is Dictionary) or local.size == Vector3.ZERO:
		return
	var f: Dictionary = fx
	var name := str(f.get("name", ""))
	var spec: Dictionary = EffectLibrary.entry(name).get("options", {})
	var fill := {}
	match name:
		"wipe":
			fill["size"] = local.size[["x", "y", "z"].find(str(f.get("axis", "y")))]
		"scan_in":
			fill["size"] = local.size.y
		"wind_sway":
			fill["base"] = local.position.y
			fill["height"] = local.size.y
	for k: String in fill:
		if f.has(k) or not spec.has(k):
			continue
		var o: Dictionary = spec[k]
		(mat as ShaderMaterial).set_shader_parameter(str(o["uniform"]), clampf(float(fill[k]), float(o["min"]),
				float(o["max"])))


## How a material treats transparency: its "alpha" when given; else a picture with transparent pixels is a cut-out,
## and a colour with alpha below 1 is see-through (blend); else opaque.
static func alpha_mode(m: Dictionary, colour: Color, picture_has_alpha: bool) -> String:
	if m.has("alpha"):
		return str(m["alpha"])
	if picture_has_alpha:
		return "cutout"
	return "blend" if colour.a < 0.999 else "opaque"


static var _alpha_shaders := {}


## env_unlit_tex.gdshader as it is (opaque), or compiled with ALPHA_CUT / ALPHA_BLEND defined.
## room_lit.gdshader for an alpha mode (opaque, cutout, blend).
static func lit_shader(mode: String) -> Shader:
	if mode == "opaque" or not (mode in ["cutout", "blend"]):
		return LIT_SHADER
	if not _lit_shaders.has(mode):
		var s := Shader.new()
		s.code = LIT_SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n#define %s" % (
				"ALPHA_CUT" if mode == "cutout" else "ALPHA_BLEND"))
		_lit_shaders[mode] = s
	return _lit_shaders[mode]


## The room's lighting for its materials: {lit, sky_top, sky_bottom, screen} ({lit: false}: the unlit look).
static func lighting_of(p_doc: Dictionary) -> Dictionary:
	if not RoomSchema.is_lit(p_doc):
		return {"lit": false}
	var light: Dictionary = p_doc.get("light", {}) if p_doc.get("light") is Dictionary else {}
	var out := {"lit": true, "sky_top": Color.BLACK, "sky_bottom": Color.BLACK, "screen": 0.0}
	if light.get("sky") is Dictionary:
		var o := RoomSchema.with_defaults(RoomSchema.LIGHT_OPTIONS["sky"], light["sky"])
		out["sky_top"] = RoomSchema.to_color(o["top"]) * float(o["energy"])
		out["sky_bottom"] = RoomSchema.to_color(o["bottom"]) * float(o["energy"])
	if light.get("screen") is Dictionary:
		out["screen"] = float(RoomSchema.with_defaults(RoomSchema.LIGHT_OPTIONS["screen"], light["screen"])["energy"])
	return out


static func _light_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("sky_top", _lighting["sky_top"])
	mat.set_shader_parameter("sky_bottom", _lighting["sky_bottom"])
	mat.set_shader_parameter("screen_light", _lighting["screen"])


## The base room's (or a model's) unlit surfaces as lit ones: env_unlit / env_unlit_tex materials become
## room_lit.gdshader with their colour, picture and emission; library materials (the built-in rooms' floors, walls and
## seats) their lit form (MaterialLibrary.lit_variant(): the same maps, shared).
static func light_surfaces(root_node: Node) -> void:
	for n in root_node.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.material_override != null:
			var lm := _lit_from(g.material_override)
			if lm != null:
				g.material_override = lm
		# Under an override the surfaces' own materials don't show: they are left as they are.
		elif g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var src: Material = mi.get_surface_override_material(s)
				if src == null:
					src = mi.mesh.surface_get_material(s)
				var lm := _lit_from(src)
				if lm != null:
					mi.set_surface_override_material(s, lm)
		if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and g is MeshInstance3D \
				and not (g is MultiMeshInstance3D):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _lit_from(src: Material) -> Material:
	if not (src is ShaderMaterial) or (src as ShaderMaterial).shader == null:
		return null
	if MaterialLibrary.is_library(src):
		return MaterialLibrary.lit_variant(src, _lighting)
	var path := (src as ShaderMaterial).shader.resource_path
	var code := (src as ShaderMaterial).shader.code
	if not (path.ends_with("env_unlit.gdshader") or path.ends_with("env_unlit_tex.gdshader")
			or (path == "" and code.begins_with(UNLIT_TEX.code.left(60)))):
		return null
	var s := src as ShaderMaterial
	if s.get_shader_parameter("self_lit") == true:
		return null
	var mode := "blend" if code.contains("#define ALPHA_BLEND") else ("cutout" if code.contains("#define ALPHA_CUT")
			else "opaque")
	var m := ShaderMaterial.new()
	m.shader = lit_shader(mode)
	for k in ["albedo", "albedo_texture", "use_texture", "emission", "alpha"]:
		var v: Variant = s.get_shader_parameter(k)
		if v != null:
			m.set_shader_parameter(k, v)
	_light_material(m)
	m.set_shader_parameter("specular", 0.1)
	return m


static func unlit_shader(mode: String) -> Shader:
	if mode == "opaque" or not (mode in ["cutout", "blend"]):
		return UNLIT_TEX
	if not _alpha_shaders.has(mode):
		var s := Shader.new()
		s.code = UNLIT_TEX.code.replace("shader_type spatial;", "shader_type spatial;\n#define %s" % (
				"ALPHA_CUT" if mode == "cutout" else "ALPHA_BLEND"))
		_alpha_shaders[mode] = s
	return _alpha_shaders[mode]


## The sky's material (shaders/room_sky.gdshader): a colour or a picture, with STARS and CLOUDS defined when named; or
## a sky from the effect library (sky.effect: its shader on the same sphere).
static func sky_material(sky: Dictionary, image: Variant) -> ShaderMaterial:
	if sky.get("effect") is Dictionary and EffectLibrary.has(str(sky["effect"].get("name", ""))):
		var fx := (sky["effect"] as Dictionary).duplicate()
		var name := str(fx["name"])
		fx.erase("name")
		var em := ShaderMaterial.new()
		EffectLibrary.apply(em, name, fx, EffectLibrary.seed_of("sky"))
		var react := str(EffectLibrary.entry(name).get("react", ""))
		if react != "":
			em.set_meta("react", react)
		return em
	var defines := ""
	for k in ["stars", "clouds"]:
		if sky.has(k):
			defines += "#define %s\n" % k.to_upper()
	if not _sky_shaders.has(defines):
		var s: Shader = SKY_SHADER
		if defines != "":
			s = Shader.new()
			s.code = SKY_SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n" + defines)
		_sky_shaders[defines] = s
	var mat := ShaderMaterial.new()
	mat.shader = _sky_shaders[defines]
	mat.set_shader_parameter("sky_color", RoomSchema.to_color(sky.get("color",
			"#02040a" if (sky.has("stars") or sky.has("clouds")) and image == null else "#ffffff")))
	if image is Image:
		mat.set_shader_parameter("sky_texture", ImageTexture.create_from_image(image))
		mat.set_shader_parameter("use_texture", true)
	if sky.has("stars"):
		var o := RoomSchema.with_defaults(RoomSchema.SKY_OPTIONS["stars"], sky["stars"])
		mat.set_shader_parameter("star_density", float(o["density"]))
		mat.set_shader_parameter("twinkle", minf(float(o["twinkle"]), RoomSchema.MAX_SWING))
		mat.set_shader_parameter("star_color", RoomSchema.to_color(o["color"]))
	if sky.has("clouds"):
		var o := RoomSchema.with_defaults(RoomSchema.SKY_OPTIONS["clouds"], sky["clouds"])
		mat.set_shader_parameter("cloud_cover", float(o["cover"]))
		mat.set_shader_parameter("cloud_speed", float(o["speed"]))
		mat.set_shader_parameter("cloud_color", RoomSchema.to_color(o["color"]))
	return mat


## Low fog near the floor: FOG_LAYERS soft layers (shaders/room_fog.gdshader) up to its height, denser low down,
## FOG_SIZE metres across around the room's middle.
static func fog(f: Dictionary) -> Node3D:
	var o := RoomSchema.with_defaults(RoomSchema.ATMOSPHERE_OPTIONS["fog"], f)
	var node := Node3D.new()
	node.name = "Fog"
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var n := RoomSchema.FOG_LAYERS
	var weights: Array[float] = []
	var total := 0.0
	for i in n:
		weights.append(exp(-2.0 * float(i) / n))
		total += weights[i]
	for i in n:
		var mat := ShaderMaterial.new()
		mat.shader = FOG_SHADER
		mat.set_shader_parameter("fog_color", RoomSchema.to_color(o["color"]))
		# Together the layers reach the density's opacity where the view crosses them all.
		mat.set_shader_parameter("opacity", 0.7 * float(o["density"]) * weights[i] / total)
		mat.set_shader_parameter("speed", float(o["speed"]))
		mat.set_shader_parameter("level", float(i) / maxf(n - 1, 1))
		mat.set_shader_parameter("half_size", Vector2(FOG_SIZE, FOG_SIZE) / 2.0)
		var mi := MeshInstance3D.new()
		mi.name = "Layer%d" % i
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3(FOG_SIZE / 2.0, 1.0, FOG_SIZE / 2.0)
		mi.position = Vector3(0.0, 0.03 + (float(o["height"]) - 0.03) * float(i) / maxf(n - 1, 1), 0.0)
		# The upper layers drawn first, so the denser low ones blend over them as seen from above.
		mi.sorting_offset = float(n - i)
		node.add_child(mi)
	return node


## Fits the fog to the room's interior (RoomBounds.interior, in the room frame): its floor, and up to WALL_GAP short
## of the walls it has; open sides keep FOG_SIZE / 2 from the middle.
static func fit_fog(node: Node3D, inside: Dictionary) -> void:
	if node == null or not inside.has("min"):
		return
	var lo: Array = inside["min"]
	var hi: Array = inside["max"]
	var open: Array = inside.get("open", [])
	var x0: float = -FOG_SIZE / 2.0 if "left" in open else float(lo[0]) + WALL_GAP
	var x1: float = FOG_SIZE / 2.0 if "right" in open else float(hi[0]) - WALL_GAP
	var z0: float = -FOG_SIZE / 2.0 if "front" in open else float(lo[2]) + WALL_GAP
	var z1: float = FOG_SIZE / 2.0 if "back" in open else float(hi[2]) - WALL_GAP
	if x1 - x0 < 0.5 or z1 - z0 < 0.5:
		return
	var walled := open.size() < 3
	node.position.y = 0.0 if "floor" in open else float(lo[1])
	for mi: MeshInstance3D in node.get_children():
		mi.position.x = (x0 + x1) / 2.0
		mi.position.z = (z0 + z1) / 2.0
		mi.scale = Vector3((x1 - x0) / 2.0, 1.0, (z1 - z0) / 2.0)
		var mat := mi.material_override as ShaderMaterial
		mat.set_shader_parameter("half_size", Vector2(x1 - x0, z1 - z0) / 2.0)
		mat.set_shader_parameter("boxed", walled)


## The screen_glow widget's material (shaders/room_glow.gdshader); with "react", compiled with REACT_<SOURCE> and
## STYLE_<STYLE> defined, and its source kept in meta "react" for the room's RoomReact node.
static func glow_material(colour: Color, o: Dictionary) -> ShaderMaterial:
	var react := str(o.get("react", "none"))
	var key := "none" if react == "none" else react + ":" + str(o.get("style", "shimmer"))
	if not _glow_shaders.has(key):
		var s: Shader = GLOW_SHADER
		if react != "none":
			s = Shader.new()
			s.code = GLOW_SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n#define REACT_%s\n"
					% react.to_upper() + "#define STYLE_%s" % str(o.get("style", "shimmer")).to_upper())
		_glow_shaders[key] = s
	var mat := ShaderMaterial.new()
	mat.shader = _glow_shaders[key]
	mat.set_shader_parameter("albedo", colour)
	mat.set_shader_parameter("strength", float(o.get("strength", 1.0)))
	mat.set_shader_parameter("amount", minf(float(o.get("amount", 0.25)), RoomSchema.MAX_SWING))
	if react != "none":
		mat.set_meta("react", react)
	return mat


# --- Kept rooms ----------------------------------------------------------------------------------------------------

static func files_dir(name: String) -> String:
	return RECIPE_DIR.path_join(name + ".files")


static func json_path(name: String) -> String:
	return RECIPE_DIR.path_join(name + ".room.json")


## Writes a kept room: the document with its models and pictures as files beside it. "" or the error.
static func save(p_doc: Dictionary, name: String) -> String:
	DirAccess.make_dir_recursive_absolute(files_dir(name))
	# The files of the room saved under this name before: written again below, or no longer used.
	for f in DirAccess.get_files_at(files_dir(name)):
		DirAccess.remove_absolute(files_dir(name).path_join(f))
	var out := p_doc.duplicate(true)
	out["name"] = name
	var n := [0]
	# The same data twice (a library object placed twice) is one file.
	var written := {}
	var write := func(b64: String, ext: String) -> String:
		var key := b64.md5_text()
		if written.has(key):
			return written[key]
		n[0] += 1
		var file := "%02d.%s" % [n[0], ext]
		var f := FileAccess.open(files_dir(name).path_join(file), FileAccess.WRITE)
		if f == null:
			return ""
		f.store_buffer(Marshalls.base64_to_raw(b64))
		f.close()
		written[key] = file
		return file
	if out.has("base_model"):
		out["base_model_file"] = write.call(out["base_model"], "glb")
		out.erase("base_model")
	var sky: Dictionary = out.get("sky", {})
	if sky.has("image"):
		sky["image_file"] = write.call(sky["image"], "img")
		sky.erase("image")
	for p: Dictionary in out.get("parts", []):
		if p.has("model"):
			p["model_file"] = write.call(p["model"], "glb")
			p.erase("model")
		var m: Dictionary = p.get("material", {})
		if m.has("texture"):
			m["texture_file"] = write.call(m["texture"], "img")
			m.erase("texture")
	for r: Dictionary in out.get("recolour", []):
		var m: Dictionary = r.get("material", {}) if r.get("material") is Dictionary else {}
		if m.has("texture"):
			m["texture_file"] = write.call(m["texture"], "img")
			m.erase("texture")
	var f := FileAccess.open(json_path(name), FileAccess.WRITE)
	if f == null:
		return "can't write %s" % json_path(name)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	return ""


## A kept room read back: its files turned into base64 again, then built like a fresh one (blocking: it runs when
## the room is chosen, as glTF rooms do). Null when it can't be read.
static func load_saved(path: String) -> Node3D:
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		push_warning("Assistant room %s: not readable" % path)
		return null
	var d: Dictionary = j.data
	var v := RoomSchema.validate(d, "saved")
	if not v["ok"]:
		push_warning("Assistant room %s: %s" % [path, v["errors"]])
		return null
	var dir := path.trim_suffix(".room.json") + ".files"
	var read := func(file: String) -> String:
		return Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(dir.path_join(file)))
	if d.has("base_model_file"):
		d["base_model"] = read.call(d["base_model_file"])
		d.erase("base_model_file")
	var sky: Dictionary = d.get("sky", {})
	if sky.has("image_file"):
		sky["image"] = read.call(sky["image_file"])
		sky.erase("image_file")
	for p: Dictionary in d.get("parts", []):
		if p.has("model_file"):
			p["model"] = read.call(p["model_file"])
			p.erase("model_file")
		var m: Dictionary = p.get("material", {})
		if m.has("texture_file"):
			m["texture"] = read.call(m["texture_file"])
			m.erase("texture_file")
	for r: Dictionary in d.get("recolour", []):
		var m: Dictionary = r.get("material", {})
		if m.has("texture_file"):
			m["texture"] = read.call(m["texture_file"])
			m.erase("texture_file")
	var editor := load("res://scripts/assistant/room_editor.gd") as GDScript
	var assets: Dictionary = editor.call("load_assets_now", d)
	if assets.has("error"):
		push_warning("Assistant room %s: %s" % [path, assets["error"]])
		return null
	var base: Node3D = editor.call("make_base", d, assets)
	var room: Node3D = build(d, base, assets, str(d.get("base", ""))) if base != null else null
	editor.call("free_assets", assets)  # the room holds copies
	return room
