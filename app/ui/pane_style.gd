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
const MakeTheme := preload("res://tools/make_pane_theme.gd")

static var path := DEFAULT_PATH
static var _theme: Theme
## The theme the custom-drawn parts read their tokens from while it is set (the tablet's, ui_layer.gd
## apply_tablet_mode()); null: the pane's own.
static var _active: Theme
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


## The tablet's theme (ui/tablet.gd menu_colours(): the palette's text, muted, accent and surface over the defaults),
## flat: no borders on buttons in any state. Made once per set of colours.
static var _tablet_themes := {}


static func tablet_theme(colours: Dictionary) -> Theme:
	var key := str(colours)
	if not _tablet_themes.has(key):
		_tablet_themes[key] = MakeTheme.build({"colours": colours, "flat": true})
	return _tablet_themes[key]


## Makes a theme the one the tokens are read from (color(), constant(), ...; null: the pane's own again), and tells
## the custom-drawn parts.
static func set_active(t: Theme) -> void:
	if t == _active:
		return
	_active = t
	holder().changed.emit()


static func active() -> Theme:
	return _active if _active != null else theme()


## A copy of a theme (the pane's, or the tablet's) with every font size times `s` (the tablet's bigger text,
## ui/pane_ui.gd set_text_scale()).
static func scaled_theme(s: float, base: Theme = null) -> Theme:
	var t := (base if base != null else theme()).duplicate() as Theme
	if t.default_font_size > 0:
		t.default_font_size = roundi(t.default_font_size * s)
	for type in t.get_font_size_type_list():
		for n in t.get_font_size_list(type):
			t.set_font_size(n, type, roundi(t.get_font_size(n, type) * s))
	return t


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
	return active().get_color(token, TOKENS)


static func constant(token: StringName) -> int:
	return active().get_constant(token, TOKENS)


static func font(token: StringName) -> Font:
	return active().get_font(token, TOKENS)


static func font_size(token: StringName) -> int:
	return active().get_font_size(token, TOKENS)


static func stylebox(token: StringName) -> StyleBox:
	return active().get_stylebox(token, TOKENS)


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
