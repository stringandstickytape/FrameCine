extends RefCounted

## The pane's style: one Theme resource (docs/ui-design.md, "Theming"), written by tools/make_pane_theme.gd. Controls
## get it by inheritance from the pane's root; custom-drawn parts (seek bar, laser, pane edge and halo, chips, mode
## diagrams) read the token dictionary through color() / constant() / font() / font_size(), which are the theme's
## items of the type "Tokens". No pane script writes a colour or a font itself.
##
## A theme is a new .tres and nothing else: [pane] theme = "res://ui/themes/<name>.tres" in user://settings.cfg.
## reload() reads the file again (dev hot-reload, or main.ui.reload_theme()); the pane listens to changed().

const DEFAULT_PATH := "res://ui/themes/default.tres"
const TOKENS := &"Tokens"

static var path := DEFAULT_PATH
static var _theme: Theme
## Emitted (through the holder's signal) when reload() swapped the theme.
static var _holder: Holder


class Holder:
	extends RefCounted
	signal changed


static func holder() -> Holder:
	if _holder == null:
		_holder = Holder.new()
	return _holder


static func theme() -> Theme:
	if _theme == null:
		_theme = load(path) as Theme
		if _theme == null:
			push_error("Pane style: %s did not load; using the engine's default theme" % path)
			_theme = Theme.new()
		_theme.changed.connect(func() -> void: holder().changed.emit())
	return _theme


## Uses another theme file (settings) and tells the pane.
static func use(p_path: String) -> void:
	if p_path == "" or p_path == path and _theme != null:
		return
	path = p_path
	_theme = null
	theme()
	holder().changed.emit()


## Reads the theme file again from disk (hot-reload of a restyle).
static func reload() -> void:
	_theme = ResourceLoader.load(path, "Theme", ResourceLoader.CACHE_MODE_REPLACE) as Theme
	if _theme == null:
		_theme = Theme.new()
	else:
		_theme.changed.connect(func() -> void: holder().changed.emit())
	holder().changed.emit()


static func color(token: StringName) -> Color:
	return theme().get_color(token, TOKENS)


static func constant(token: StringName) -> int:
	return theme().get_constant(token, TOKENS)


static func font(token: StringName) -> Font:
	return theme().get_font(token, TOKENS)


static func font_size(token: StringName) -> int:
	return theme().get_font_size(token, TOKENS)


static func stylebox(token: StringName) -> StyleBox:
	return theme().get_stylebox(token, TOKENS)


## Pane size in pixels and metres. scale: [pane] scale in the settings (1 = the doc's 24 x 19.5 cm).
static func pane_pixels() -> Vector2i:
	return Vector2i(constant(&"pane_width_px"), constant(&"pane_height_px"))


static func pane_metres(scale := 1.0) -> Vector2:
	return Vector2(pane_pixels()) / float(maxi(constant(&"pane_px_per_m"), 1)) * scale


## A small theme that only swaps the focus boxes for the stick-focus look (1 px accent outline added). Put it on a
## Control above the panel's controls: Godot looks a theme item up in each ancestor's theme in turn, so every other
## item still comes from the main theme.
static func docked_focus_theme() -> Theme:
	var t := Theme.new()
	for type in ["Button", "RowButton", "PlaceButton", "TransportButton", "TabButton", "KeyButton", "PlayButton"]:
		var key := StringName("focus_docked_" + type)
		if theme().has_stylebox(key, TOKENS):
			t.set_stylebox("focus", type, theme().get_stylebox(key, TOKENS))
	return t
