extends SceneTree

## The effect library's bench (docs/effects.md): previews, the measured cost of each effect, and its brightness over
## time against the photosensitivity ceiling. Needs a renderer:
##
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" godot --xr-mode off \
##       --path app --script res://tools/fx_lab.gd -- [--previews=DIR] [--measure] [--photo] [--ids=a,b] [--size=N]
##
##   --previews=DIR  DIR/<id>.png (160 x 160: a sphere in a dim room, or the sky looking a little up; defaults, the
##                   clock at 3.7 s) and DIR/sheet.png (all of them, named). The repository keeps them in
##                   docs/shots/effects/.
##   --measure       the GPU time of a sphere filling a size x size view (default 1024) with each effect, against the
##                   plain surface (env_unlit_tex.gdshader: the median of it measured beside each) and the empty view:
##                   ratio =
##                   (effect - empty) / (plain - empty), and the tier it falls in (EffectLibrary.tier_of). Prints
##                   JSON; --out=FILE writes it.
##   --photo         each animated effect at its fastest options, 4 s at 30 pictures a second: the steepest change of
##                   any pixel against the ceiling (effect_lab.gd photo_check).
##   --preview-size=N  the previews N x N (160).
##   --ids=a,b       only these effects.
##   --table         the catalogue as docs/effects.md's table (no renderer needed).

const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const EffectLab := preload("res://scripts/effects/effect_lab.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("table"):
		_table()
		quit()
		return
	if not EffectLab.has_renderer():
		printerr("fx_lab needs a renderer (see the header)")
		quit(2)
		return
	EffectLab.set_room(self)
	var ids := EffectLibrary.ids()
	if args.has("ids"):
		ids.assign(str(args["ids"]).split(",", false))
	await process_frame
	if args.has("previews"):
		await _previews(ids, str(args["previews"]), int(args.get("preview-size", "160")))
	if args.has("measure"):
		await _measure(ids, int(args.get("size", "1024")), str(args.get("out", "")))
	if args.has("photo"):
		await _photo(ids)
	quit()


func _previews(ids: Array[String], dir: String, tile := 160) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var tiles: Array[Image] = []
	for id in ids:
		var img: Image = await EffectLab.preview(self, id, Vector2i(tile, tile))
		if img == null:
			printerr("%s: no preview" % id)
			continue
		img.convert(Image.FORMAT_RGB8)
		img.save_png(dir.path_join(id + ".png"))
		tiles.append(img)
		print("preview %s" % id)
	# The sheet: 8 a row, each tile with its id under it in a strip (drawn by a Label in a viewport).
	var cols := 8
	var strip := 18
	var rows := ceili(tiles.size() / float(cols))
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * tile, rows * (tile + strip))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.07)
	bg.size = vp.size
	vp.add_child(bg)
	for i in tiles.size():
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(tiles[i])
		tr.position = Vector2((i % cols) * tile, (i / cols) * (tile + strip))
		vp.add_child(tr)
		var l := Label.new()
		l.text = ids[i]
		l.add_theme_font_size_override("font_size", 12)
		l.position = tr.position + Vector2(4, tile)
		vp.add_child(l)
	root.add_child(vp)
	for f in 3:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(dir.path_join("sheet.png"))
	vp.queue_free()


func _measure(ids: Array[String], size: int, out_file: String) -> void:
	var empty: float = await EffectLab.gpu_ms(self, null, false, size)
	var out := {"size": size, "empty_ms": snappedf(empty, 0.001), "renderer": RenderingServer.get_video_adapter_name(),
			"effects": {}}
	# The plain surface beside each effect; the ratio is against their median, so neither a slow drift of the machine
	# (the software renderer shares its cores) nor one odd plain measurement moves an effect's number much.
	var plains: Array[float] = []
	var times := {}
	for id in ids:
		var sky := str(EffectLibrary.entry(id)["surfaces"]) == "sky"
		plains.append(await EffectLab.gpu_ms(self, EffectLab.plain_material(), false, size))
		times[id] = await EffectLab.gpu_ms(self, EffectLab.material(id), sky, size)
	plains.sort()
	var plain: float = plains[plains.size() / 2] if not plains.is_empty() else empty
	out["plain_ms"] = snappedf(plain, 0.001)
	print("empty %.3f ms, plain %.3f ms (%s)" % [empty, plain, out["renderer"]])
	for id in ids:
		var ms: float = times[id]
		var ratio := (ms - empty) / maxf(plain - empty, 1e-4)
		out["effects"][id] = {"ms": snappedf(ms, 0.001), "ratio": snappedf(ratio, 0.01),
				"tier": EffectLibrary.tier_of(ratio), "declared": EffectLibrary.entry(id).get("cost", "")}
		print("%-18s %7.3f ms  ratio %5.2f  %s (declared %s)" % [id, ms, ratio, EffectLibrary.tier_of(ratio),
				EffectLibrary.entry(id).get("cost", "")])
	if out_file != "":
		var f := FileAccess.open(out_file, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  ") + "\n")


## docs/effects.md's catalogue table, from the catalogue (Markdown, to stdout).
func _table() -> void:
	print("| Preview | Id | Name | Group | Blend | Layers | Cost (ratio) | Animates (Hz, swing) | Description |")
	print("|---|---|---|---|---|---|---|---|---|")
	for id in EffectLibrary.ids():
		var e := EffectLibrary.public_entry(id)
		var a: Dictionary = e["animation"]
		var anim := "still" if a.is_empty() else "%s..%s, %s" % [a["hz"][0], a["hz"][1], a["swing"]]
		print("| ![](shots/effects/%s.png) | `%s` | %s | %s | %s | %s | %s (%.2f) | %s | %s |" % [id, id, e["name"],
				e["group"], e["blend"], "yes" if e["layers"] else "no", e["cost"], float(e["cost_ratio"]), anim,
				e["description"]])


func _photo(ids: Array[String]) -> void:
	for id in ids:
		if (EffectLibrary.entry(id).get("animation", {}) as Dictionary).is_empty():
			continue
		var opts := EffectLab.fastest_options(id)
		var frames: Array[Image] = await EffectLab.clip(self, id, opts)
		if frames.is_empty():
			print("%-18s (the engine's clock: checked by its declared bounds)" % id)
			continue
		var r := EffectLab.photo_check(frames)
		print("%-18s slope %.2f of %.2f a second (%3d %% of the ceiling), swing %.2f, %d pixels  %s" % [id,
				r["slope"], r["max_slope"], int(r["of_ceiling"] * 100), r["swing"], r["pixels"], opts])
