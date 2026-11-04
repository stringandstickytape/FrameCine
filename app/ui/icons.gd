extends RefCounted

## The menu's icons (ui/icons/*.svg, see the README there) as textures: texture(name, px, colour) draws one at px
## pixels square in a colour (its "currentColor"; an icon with colours of its own keeps them), once per name, size
## and colour. Buttons take them as their icon with the theme's icon colours white (tools/make_pane_theme.gd), so the
## colour is the texture's.

const FOLDER := "res://ui/icons/"

static var _cache := {}


static func texture(p_name: String, px: int, colour: Color) -> Texture2D:
	var key := "%s|%d|%s" % [p_name, px, colour.to_html()]
	if _cache.has(key):
		return _cache[key]
	var svg := FileAccess.get_file_as_string(FOLDER + p_name + ".svg")
	var tex: Texture2D = null
	if svg != "":
		# SVG takes "#rrggbb" and a separate opacity (an 8-digit hex is not understood by every renderer).
		var hex := "#" + colour.to_html(false)
		var alpha := "%.3f" % colour.a
		svg = svg.replace('stroke="currentColor"', 'stroke="%s" stroke-opacity="%s"' % [hex, alpha])
		svg = svg.replace('fill="currentColor"', 'fill="%s" fill-opacity="%s"' % [hex, alpha])
		svg = svg.replace("currentColor", hex)
		var img := Image.new()
		if img.load_svg_from_string(svg, px / 24.0) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("Icons: no %s" % p_name)
	_cache[key] = tex
	return tex


static func has(p_name: String) -> bool:
	return FileAccess.file_exists(FOLDER + p_name + ".svg")
