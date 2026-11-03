extends Node3D

## Control: screenshot the window at frame 60 to --screenshot=PATH, then quit at frame 100.
## Expected: red quad filling the middle of the view, blue square top-left.

var screenshot_path := ""
var frames := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg == "--sky":
			# Fullscreen sky pass: no mesh, no instance data. Renders if the pipeline/depth path is sane.
			var sky_mat := ProceduralSkyMaterial.new()
			sky_mat.sky_top_color = Color(0.1, 0.3, 1.0)
			sky_mat.sky_horizon_color = Color(0.0, 1.0, 0.0)
			sky_mat.ground_bottom_color = Color(1.0, 1.0, 0.0)
			var sky := Sky.new()
			sky.sky_material = sky_mat
			var env := Environment.new()
			env.background_mode = Environment.BG_SKY
			env.sky = sky
			var we := WorldEnvironment.new()
			we.environment = env
			add_child(we)
			print("Sky enabled")
		elif arg == "--nodepth":
			# Quad with depth test and culling off: appears iff the depth buffer is what hides it.
			var m := $Quad.material_override as StandardMaterial3D
			m.no_depth_test = true
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.render_priority = 10
			print("Quad: no depth test, no culling")
		elif arg == "--bigquad":
			$Quad.scale = Vector3(20, 20, 1)
			print("Quad scaled x20")
		elif arg == "--arraymesh" or arg == "--arraymesh-compressed":
			# Hand-built quad: float positions only (uncompressed) vs ARRAY_FLAG_COMPRESS_ATTRIBUTES
			# (packed 10/16-bit normals/UVs). Separates "vertex format" from "any mesh draw".
			var verts := PackedVector3Array([Vector3(-1, -0.5, 0), Vector3(1, -0.5, 0), Vector3(1, 0.5, 0),
					Vector3(-1, -0.5, 0), Vector3(1, 0.5, 0), Vector3(-1, 0.5, 0)])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			var flags := 0
			if arg == "--arraymesh-compressed":
				arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK,
						Vector3.BACK, Vector3.BACK, Vector3.BACK])
				arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0),
						Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)])
				flags = Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
			$Quad.mesh = am
			print("ArrayMesh quad, flags=%d, format=0x%x" % [flags, am.surface_get_format(0)])
		elif arg == "--clipquad":
			# Vertex shader writes clip-space POSITION directly: no camera, no instance transform, no SSBO reads
			# needed for position. If this draws, the instance-data/transform path is what's broken.
			var sh := Shader.new()
			sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
void vertex() {
	POSITION = vec4(VERTEX.xy * 0.8, 0.5, 1.0);
}
void fragment() {
	ALBEDO = vec3(1.0, 0.0, 0.0);
}
"""
			var sm := ShaderMaterial.new()
			sm.shader = sh
			$Quad.material_override = sm
			print("Clip-space quad shader")
		elif arg == "--poly2d":
			# 2D draw that uses a real vertex buffer (unlike ColorRect). Separates "vertex fetch" from "scene shader".
			var poly := Polygon2D.new()
			poly.polygon = PackedVector2Array([Vector2(400, 300), Vector2(900, 300), Vector2(900, 800), Vector2(400, 800)])
			poly.color = Color(0, 1, 0)
			$CanvasLayer.add_child(poly)
			print("Polygon2D added")
		elif arg == "--immediate":
			var im := ImmediateMesh.new()
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for v in [Vector3(-1, -0.5, 0), Vector3(1, -0.5, 0), Vector3(1, 0.5, 0),
					Vector3(-1, -0.5, 0), Vector3(1, 0.5, 0), Vector3(-1, 0.5, 0)]:
				im.surface_add_vertex(v)
			im.surface_end()
			$Quad.mesh = im
			print("ImmediateMesh quad")
	print("Control: camera=%s quad_visible=%s can_draw=%s" % [get_viewport().get_camera_3d(),
			$Quad.is_visible_in_tree(), DisplayServer.window_can_draw()])


func _process(_delta: float) -> void:
	frames += 1
	if frames == 60 and screenshot_path != "":
		_shoot()
	if frames >= 100:
		get_tree().quit()


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("Control screenshot %s: %s" % [screenshot_path, error_string(img.save_png(screenshot_path))])
