extends SceneTree

## Exports the printed legends for baking into our controller model's texture (tools/controller_model/bake.py):
## for each hand and state (normal; menu open; a captured window has the input), each legend's texture
## (label_texture_cache.gd) and the box it is printed through, from xr/controller_labels_layout.tres.
## Also the letters on the right controller's face buttons ("caps": printed on top of the button, any state).
## Writes <DIR>/legends.json and <DIR>/<side>_<state>_<input>.png, cap_<letter>.png. Needs a renderer (not --headless).
##   godot --path app --script res://tools/controller_model/export_legends.gd -- --out=DIR

const LabelLayout := preload("res://scripts/xr/label_layout.gd")
const LabelTextureCache := preload("res://tools/controller_model/label_texture_cache.gd")
const Main := preload("res://scripts/main.gd")

const LAYOUT_PATH := "res://xr/controller_labels_layout.tres"
## state -> [menu shown, window has the input]
const STATES := {"normal": [false, false], "menu": [true, false], "window": [false, true]}
## Button part -> its letter, and the printed height of a letter line.
const CAPS := {"button_a": "A", "button_b": "B", "button_x": "X", "button_y": "Y"}
const CAP_LINE := 0.0045


## The box a legend's texture is printed through: the texture's size (font size, padding) at line_height metres per font
## line, and the entry's depth.
static func _box(entry: Dictionary, text: String) -> Vector3:
	var font := ThemeDB.fallback_font
	var px := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, LabelTextureCache.FONT_SIZE) \
			+ Vector2.ONE * LabelTextureCache.PAD * 2.0
	var size := px * float(entry.get("line_height", 0.0042)) / font.get_height(LabelTextureCache.FONT_SIZE)
	return Vector3(size.x, float(entry.get("depth", 0.012)), size.y)


func _initialize() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	if out == "":
		push_error("--out=DIR is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var layout := load(LAYOUT_PATH) as LabelLayout
	var cache := LabelTextureCache.new()
	root.add_child.call_deferred(cache)
	await process_frame
	var items: Array = []
	var pending := [0]
	for side in ["left", "right"]:
		for state: String in STATES:
			var flags: Array = STATES[state]
			var texts := Main.controller_labels(Main.PREVIEW_PROFILE, side, flags[0], flags[1])
			for input: String in texts:
				var entry := layout.find(side, input)
				if entry.is_empty():
					print("%s %s %s: not in the layout, not printed" % [side, state, input])
					continue
				var text: String = texts[input]
				var png := "%s_%s_%s.png" % [side, state, input]
				var t: Transform3D = entry["transform"]
				var size := _box(entry, text)
				items.append({"side": side, "state": state, "input": input, "text": text, "png": png,
						"origin": _v(t.origin), "x": _v(t.basis.x), "y": _v(t.basis.y), "z": _v(t.basis.z),
						"size": _v(size)})
				pending[0] += 1
				cache.request(text, func(tex: Texture2D) -> void:
					tex.get_image().save_png(out.path_join(png))
					pending[0] -= 1)
	var caps: Array = []
	for part: String in CAPS:
		var letter: String = CAPS[part]
		var png := "cap_%s.png" % letter
		caps.append({"side": "right", "part": part, "text": letter, "png": png,
				"size": _v(_box({"line_height": CAP_LINE, "depth": 0.006}, letter))})
		pending[0] += 1
		cache.request(letter, func(tex: Texture2D) -> void:
			tex.get_image().save_png(out.path_join(png))
			pending[0] -= 1)
	while pending[0] > 0:
		await process_frame
	var f := FileAccess.open(out.path_join("legends.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"layout": LAYOUT_PATH, "legends": items, "caps": caps}, "  "))
	f.close()
	print("Exported %d legends to %s" % [items.size(), out])
	quit()


static func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
