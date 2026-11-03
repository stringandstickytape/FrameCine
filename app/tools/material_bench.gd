extends SceneTree

## What the material library's shader costs against the rooms' plain one (docs/materials.md, "Cost"): a surface that
## fills a square view of one eye (1728 x 1728, the headset's size), drawn with env_unlit.gdshader, with
## room_material.gdshader (box projection, and the mesh's UVs) and with room_material_triplanar.gdshader, once facing
## the camera and once as a floor seen at a low angle (where anisotropic filtering reads the most). GPU time per frame
## from the renderer's own timestamps, the median of the measured frames, minus an empty view's. Also the time to read
## and decode every map (without the upload), and to make every material.
## Needs a renderer (not --headless):
##   xvfb-run -a godot --xr-mode off --path app --script res://tools/material_bench.gd -- [--size=1728] [--frames=40]
##       [--material=red_brick]
## On a PC's software renderer the absolute numbers are the CPU's; the ratios between the shaders are what carry over.

const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const ENV_SHADER := preload("res://shaders/env_unlit.gdshader")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var size := int(args.get("size", "1728"))
	var frames := int(args.get("frames", "40"))
	var id := str(args.get("material", "red_brick"))

	# Reading and decoding the maps, without the upload (the headset uploads them as they are).
	var t0 := Time.get_ticks_usec()
	var bytes_total := 0
	for mid in MaterialLibrary.ids():
		for k in MaterialLibrary.MAPS:
			var b := FileAccess.get_file_as_bytes(MaterialLibrary.DIR.path_join(str(MaterialLibrary.entry(mid)["maps"][k])))
			bytes_total += b.size()
			MaterialLibrary.decode_mtex(b)
	var read_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("Bench: read and decoded %d maps (%.1f MB) in %.0f ms" % [MaterialLibrary.ids().size() * 3,
			bytes_total / 1048576.0, read_ms])

	RenderingServer.global_shader_parameter_set("env_light", 0.1)
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	RenderingServer.global_shader_parameter_set("screen_center", Vector3(0, 1.6, -6))
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var cam := Camera3D.new()
	cam.fov = 100.0
	vp.add_child(cam)
	var quad := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	quad.mesh = pm
	vp.add_child(quad)

	var plain := ShaderMaterial.new()
	plain.shader = ENV_SHADER
	plain.set_shader_parameter("albedo", Color(0.4, 0.3, 0.3))
	t0 = Time.get_ticks_usec()
	var made := 0
	for mid in MaterialLibrary.ids():
		if MaterialLibrary.get_material(mid) != null:
			made += 1
	print("Bench: made %d materials (with uploads; a PC decompresses ASTC first) in %.0f ms" % [made,
			(Time.get_ticks_usec() - t0) / 1000.0])
	var cases := [["empty", null], ["env_unlit", plain], ["material box", MaterialLibrary.get_material(id)],
			["material uv", MaterialLibrary.get_material(id, {"uv": true, "repeat": Vector2(200, 200)})],
			["material triplanar", MaterialLibrary.get_material(id, {"triplanar": true})]]
	var results := {}
	for view in ["facing", "floor"]:
		if view == "facing":
			quad.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.6, -3))
			cam.look_at_from_position(Vector3(0, 1.6, 0), Vector3(0, 1.6, -3))
		else:
			quad.transform = Transform3D()
			cam.look_at_from_position(Vector3(0, 1.2, 0), Vector3(0, 0.6, -6))
		for c: Array in cases:
			quad.visible = c[1] != null
			quad.material_override = c[1]
			for i in 10:
				await process_frame
			var samples: Array[float] = []
			for i in frames:
				await process_frame
				samples.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
			samples.sort()
			results["%s %s" % [view, c[0]]] = samples[samples.size() / 2]
		var base: float = results["%s empty" % view]
		var unlit: float = results["%s env_unlit" % view] - base
		for c: Array in cases:
			var ms: float = results["%s %s" % [view, c[0]]] - base
			print("Bench: %s, %s: %.2f ms over the empty view%s" % [view, c[0], ms,
					(", %.1fx env_unlit" % (ms / unlit)) if c[0] != "empty" and unlit > 0.0 else ""])
	quit(0)
