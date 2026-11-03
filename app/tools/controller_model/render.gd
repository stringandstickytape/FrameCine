extends SceneTree

## Renders our controller models (models/controllers) with the app's unlit controller shader: face, outer and inner
## views per hand, to <DIR>/controller_model_<side>_<view>.png. Needs a renderer.
##   godot --resolution 1024x1024 --path app --script res://tools/controller_model/render.gd -- --out=res://docs/screenshots
const MODEL_SHADER := preload("res://shaders/controller_model.gdshader")
var dir := "res://models/controllers/"
var out := "res://docs/screenshots"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	if out.begins_with("res://"):
		out = ProjectSettings.globalize_path(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.33, 0.36)
	get_root().add_child.call_deferred(env)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.005
	get_root().add_child.call_deferred(cam)
	await process_frame
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "controllers.json"))
	for side in ["right", "left"]:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_buffer(FileAccess.get_file_as_bytes(dir + "%s_controller.glb" % side), "", state)
		var model := doc.generate_scene(state) as Node3D
		get_root().add_child(model)
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
			var mat := ShaderMaterial.new()
			mat.shader = MODEL_SHADER
			mat.set_shader_parameter("albedo", Color.WHITE)
			if src != null and src.albedo_texture != null:
				mat.set_shader_parameter("albedo_texture", src.albedo_texture)
				mat.set_shader_parameter("use_texture", true)
			mi.material_override = mat
		var rows: Array = info["sides"][side]["model_in_aim"]
		var m := Transform3D(Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]),
				Vector3(rows[0][2], rows[1][2], rows[2][2])), Vector3(rows[0][3], rows[1][3], rows[2][3]))
		var aim_in_model := m.affine_inverse()
		var n := (aim_in_model.basis * Vector3.UP).normalized()
		var front := (aim_in_model.basis * Vector3.FORWARD).normalized()
		var outer := front.cross(n).normalized() * (1.0 if side == "right" else -1.0)
		var aabb := AABB()
		var first := true
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			aabb = mi.mesh.get_aabb() if first else aabb.merge(mi.mesh.get_aabb())
			first = false
		var c := aabb.get_center()
		var face_c := c + n * 0.0 - front * 0.0
		var views := {"face": Transform3D(Basis.looking_at(-n, front), face_c + n * 0.3 + front * 0.02),
				"outer": Transform3D(Basis.looking_at(-outer, n), c + outer * 0.3),
				"inner": Transform3D(Basis.looking_at(outer, n), c - outer * 0.3)}
		for v: String in views:
			cam.global_transform = views[v]
			cam.current = true
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(out.path_join("controller_model_%s_%s.png" % [side, v]))
		model.queue_free()
		await process_frame
	print("Rendered our controller models to %s" % out)
	quit()
