extends SceneTree

## A contact sheet of the material library (docs/materials.md): each material on a box corner and a floor patch, lit
## like a room (an ambient level and the screen's spill from a screen up front), one tile each, saved as one PNG. For
## checking a new material by eye. Needs a renderer (not --headless); in WSL with xvfb and lavapipe:
##   xvfb-run -a godot --xr-mode off --path app --script res://tools/material_sheet.gd -- --out=DIR [--only=a,b]
##       [--tile=256] [--ambient=0.25] [--glow=1.0] [--screen=x,y,z] [--near]
## --screen moves the screen (the spill's source; default up front, to the left); --near frames the box's corner close.
## Writes DIR/materials.png and DIR/materials.txt (the ids in tile order, row by row).

const MaterialLibrary := preload("res://scripts/env/material_library.gd")

const COLUMNS := 6


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var out := str(args.get("out", ""))
	if out == "":
		push_error("material_sheet: --out=DIR")
		quit(2)
		return
	var tile := int(args.get("tile", "256"))
	var ids := MaterialLibrary.ids()
	if args.has("only"):
		ids.assign(str(args["only"]).split(","))
	RenderingServer.global_shader_parameter_set("env_light", float(args.get("ambient", "0.25")))
	RenderingServer.global_shader_parameter_set("screen_glow", float(args.get("glow", "1.0")))
	var sc := str(args.get("screen", "-1.2,1.6,-2.5")).split_floats(",")
	RenderingServer.global_shader_parameter_set("screen_center", Vector3(sc[0], sc[1], sc[2]))

	var vp := SubViewport.new()
	vp.size = Vector2i(tile, tile)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 50.0
	vp.add_child(cam)
	if args.has("near"):
		cam.look_at_from_position(Vector3(0.45, 0.75, 0.8), Vector3(0.05, 0.55, 0))
	else:
		cam.look_at_from_position(Vector3(1.0, 1.3, 1.6), Vector3(0, 0.5, 0))
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.0, 1.0)
	box.mesh = bm
	box.position = Vector3(0, 0.5, 0)
	box.rotation_degrees = Vector3(0, 30, 0)
	vp.add_child(box)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	vp.add_child(floor_mi)
	var floor_mat := MaterialLibrary.get_material("smooth_concrete", {"tint": Color(0.5, 0.5, 0.5)})
	floor_mi.material_override = floor_mat

	var rows := ceili(ids.size() / float(COLUMNS))
	var sheet := Image.create_empty(tile * COLUMNS, tile * rows, false, Image.FORMAT_RGB8)
	var listing := PackedStringArray()
	for i in ids.size():
		var id := ids[i]
		var t0 := Time.get_ticks_usec()
		var m := MaterialLibrary.get_material(id)
		var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
		box.material_override = m
		if MaterialLibrary.entry(id).get("tags", []).has("floor"):
			floor_mi.material_override = m
			box.material_override = floor_mat
		else:
			floor_mi.material_override = floor_mat
		for f in 3:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % COLUMNS) * tile, (i / COLUMNS) * tile))
		listing.append("%s\t%.1f ms" % [id, load_ms])
	DirAccess.make_dir_recursive_absolute(out)
	sheet.save_png(out.path_join("materials.png"))
	var f := FileAccess.open(out.path_join("materials.txt"), FileAccess.WRITE)
	f.store_string("\n".join(listing) + "\n")
	f.close()
	print("material sheet: %d materials, %s" % [ids.size(), out.path_join("materials.png")])
	quit(0)
