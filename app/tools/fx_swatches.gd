extends SceneTree

## The effect picker's swatches (ui/object_section.gd): each effect's preview (docs/shots/effects/<id>.png, made by
## tools/fx_lab.gd --previews) made small, into textures/fx/swatches/<id>.png, which ship with the app (the previews
## don't). Run again after the previews change:
##   godot --headless --xr-mode off --path app --script res://tools/fx_swatches.gd

const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const SIZE := 32
const OUT := "res://textures/fx/swatches"


func _initialize() -> void:
	var previews := ProjectSettings.globalize_path("res://").path_join("..").path_join(EffectLibrary.PREVIEWS)
	DirAccess.make_dir_recursive_absolute(OUT)
	var made := 0
	var missing: Array[String] = []
	for id in EffectLibrary.ids():
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(previews.path_join(id + ".png"))) != OK:
			missing.append(id)
			continue
		img.convert(Image.FORMAT_RGB8)
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		img.save_png(OUT.path_join(id + ".png"))
		made += 1
	print("fx_swatches: %d made in %s%s" % [made, OUT, ", missing: %s" % [missing] if not missing.is_empty() else ""])
	quit(1 if not missing.is_empty() else 0)
