extends "res://environments/vr_environment.gd"

## A room from a glTF file at runtime (ideas #53), following the environments' convention (app/docs/rooms.md): the
## viewer at the origin facing -Z, the floor at y = 0, metres; a node named ScreenAnchor marks the screen's centre
## (facing +Z) and its X scale, when not 1, is the default screen width in metres. Optional <file>.json next to it:
## {"name", "ambient_level", "screen_glow", "screen_width", "reflection_floor_y"}.
##
## Every material becomes unlit (env_unlit_tex.gdshader: base colour and texture lit by the room's level and the
## screen's spill, emission added), since the app has no lights; transparent materials become unshaded standard ones.
## Lights, cameras and animations in the file are ignored.
##
##   load_room(path) -> this script's node, or null (with last_error)   (static; blocking: reads and builds the file)

const UNLIT_TEX := preload("res://shaders/env_unlit_tex.gdshader")

static var last_error := ""

var reflection_floor_y := NAN


static func load_room(path: String) -> Node3D:
	last_error = ""
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		last_error = "can't read %s (%s)" % [path.get_file(), error_string(err)]
		return null
	var scene := doc.generate_scene(state)
	if scene == null:
		last_error = "%s has no scene" % path.get_file()
		return null
	var room: Node3D = (load("res://scripts/env/gltf_room.gd") as GDScript).new()
	room.name = "GltfRoom"
	room.display_name = path.get_file().get_basename()
	room.ambient_level = 0.15
	room.screen_glow = 0.6
	room.default_screen_width = 3.0
	room.add_child(scene)
	room.call("_settle", scene, path)
	return room


func _settle(scene: Node, path: String) -> void:
	var found := _find_anchor(scene)
	var anchor := Marker3D.new()
	anchor.name = "ScreenAnchor"
	add_child(anchor)
	if found != null:
		var t: Transform3D = _relative_transform(found)
		var sx := t.basis.get_scale().x
		anchor.transform = Transform3D(t.basis.orthonormalized(), t.origin)
		if absf(sx - 1.0) > 0.01:
			default_screen_width = sx
		found.visible = false
	else:
		anchor.position = Vector3(0, NOMINAL_EYE_HEIGHT, -3.0)
	screen_anchor = anchor
	var side := path.get_basename() + ".json"
	if FileAccess.file_exists(side):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(side))
		if j is Dictionary:
			display_name = str(j.get("name", display_name))
			ambient_level = clampf(float(j.get("ambient_level", ambient_level)), 0.0, 1.0)
			screen_glow = clampf(float(j.get("screen_glow", screen_glow)), 0.0, 2.0)
			default_screen_width = clampf(float(j.get("screen_width", default_screen_width)), 0.5, 40.0)
			if j.has("reflection_floor_y"):
				reflection_floor_y = float(j["reflection_floor_y"])
	_unlit(scene)
	for n in scene.find_children("*", "Light3D", true, false):
		n.queue_free()
	for n in scene.find_children("*", "Camera3D", true, false):
		n.queue_free()


func _find_anchor(n: Node) -> Node3D:
	if n is Node3D and str(n.name).to_lower().replace("_", "") == "screenanchor":
		return n
	for c in n.get_children():
		var f := _find_anchor(c)
		if f != null:
			return f
	return null


## The node's transform relative to this room (it isn't in the tree yet, so global_transform can't be used).
func _relative_transform(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != self:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _unlit(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			mi.set_surface_override_material(s, convert_material(src))


static func convert_material(src: Material) -> Material:
	var base := src as BaseMaterial3D
	if base == null:
		var m := ShaderMaterial.new()
		m.shader = UNLIT_TEX
		m.set_shader_parameter("albedo", Color(0.5, 0.5, 0.5))
		return m
	if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		var t := base.duplicate() as BaseMaterial3D
		t.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return t
	var m := ShaderMaterial.new()
	m.shader = UNLIT_TEX
	m.set_shader_parameter("albedo", base.albedo_color)
	if base.albedo_texture != null:
		m.set_shader_parameter("albedo_texture", base.albedo_texture)
		m.set_shader_parameter("use_texture", true)
	if base.emission_enabled:
		var e := base.emission * base.emission_energy_multiplier
		m.set_shader_parameter("emission", e)
	return m
