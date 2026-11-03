extends SceneTree

## Writes the pane's Theme (docs/ui-design.md, "Style" and "Theming") to res://ui/themes/default.tres.
##
##   godot --headless --xr-mode off --path app --script res://tools/make_pane_theme.gd [-- --out=res://ui/themes/x.tres]
##
## One resource holds everything the pane draws with: the Theme items of the ordinary controls (Label, Button,
## LineEdit, HSlider, scroll bars, ...), the pane's own type variations (PaneRoot, TitleLabel, TabButton, RowButton,
## PlayButton, ...), and the token dictionary for the custom-drawn parts (seek bar, laser, pane edge and halo, chips,
## mode diagrams) as the colours, constants, fonts and font sizes of the type "Tokens". Menu code reads tokens through
## ui/pane_style.gd and never writes a colour or a font itself.
##
## This tool is the only place the default token values are written down. A new theme is a new .tres: edit a copy in
## the editor, or change TOKENS here and write it under another name. The doc's numbers are the defaults; all of them
## are to be tuned in the headset.

## The font file as shipped (SIL OFL 1.1, ui/fonts/LICENSE.Inter.txt), and the FontFile resource made from it. The app
## runs from its source folder without the editor's import step, so the theme refers to a saved FontFile (.res), not
## to the .woff2 itself.
const FONT_SOURCE := "res://ui/fonts/Inter_Regular.woff2"
const FONT_RESOURCE := "res://ui/fonts/inter_regular.res"
const OUT_DEFAULT := "res://ui/themes/default.tres"

## The doc's tokens. Colours are [hex, alpha]. "accent*" alphas are fractions of the accent colour.
const BASE := {
	"surface": ["#0C0F13", 0.94],
	"text": ["#E6EAEE", 1.0],
	"muted": ["#8B95A1", 1.0],
	"accent": ["#9CCBE8", 1.0],
}
## Derived colours: [base token, alpha].
const DERIVED := {
	"edge": ["accent", 0.28],
	"halo": ["accent", 0.28],
	"focus_fill": ["accent", 0.10],
	"hover_fill": ["accent", 0.14],
	"pressed_fill": ["accent", 0.22],
	"selection": ["accent", 0.30],
	"chip": ["accent", 1.0],
	"seek_played": ["accent", 1.0],
	"seek_knob": ["accent", 1.0],
	"seek_track": ["muted", 0.45],
	"seek_tick": ["text", 0.55],
	"diagram": ["muted", 1.0],
	"diagram_on": ["accent", 1.0],
	"laser": ["text", 0.9],
	"laser_dot": ["accent", 1.0],
	"scroll_grabber": ["muted", 0.40],
	"field": ["text", 0.06],
}
## Hairline rules: 9 % white. The QR code must stay black on white to scan.
const FIXED := {
	"hairline": ["#FFFFFF", 0.09],
	"qr_dark": ["#000000", 1.0],
	"qr_light": ["#FFFFFF", 1.0],
}
const CONSTANTS := {
	# Pane: 740 x 600 px at about 3080 px/m is 24 x 19.5 cm.
	"pane_width_px": 740,
	"pane_height_px": 600,
	"pane_px_per_m": 3080,
	"radius_pane": 8,
	"radius_row": 6,
	"pad": 16,
	"gap": 8,
	"row_height": 40,
	"button_height": 44,
	"play_size": 52,
	"seek_height": 24,
	"seek_track": 2,
	"seek_knob": 12,
	"tab_height": 32,
	"places_width": 150,
	"halo_px": 24,
	"fade_ms": 150,
	# Letter spacing of the 11 px labels: 0.14 em is 1.5 px.
	"label_tracking": 2,
}
const SIZES := {
	"body": 15,
	"label": 11,
	"title": 22,
	"clock": 96,
}


func _init() -> void:
	var out := OUT_DEFAULT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var theme := build()
	var err := ResourceSaver.save(theme, out)
	print("Pane theme: %s (%s)" % [out, "ok" if err == OK else error_string(err)])
	quit(0 if err == OK else 1)


static func colours() -> Dictionary:
	var c := {}
	for k: String in BASE:
		c[k] = Color(BASE[k][0], BASE[k][1])
	for k: String in FIXED:
		c[k] = Color(FIXED[k][0], FIXED[k][1])
	for k: String in DERIVED:
		var base: Color = c[DERIVED[k][0]]
		c[k] = Color(base, DERIVED[k][1])
	return c


static func build() -> Theme:
	var c := colours()
	var t := Theme.new()
	var base_font := font_resource()
	var tnum := {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	var fonts := {
		"regular": _variation(base_font, tnum, 0.0, 0),
		"medium": _variation(base_font, tnum, 0.35, 0),
		"semibold": _variation(base_font, tnum, 0.7, 0),
		"light": _variation(base_font, tnum, -0.35, 0),
		"label": _variation(base_font, tnum, 0.35, int(CONSTANTS["label_tracking"])),
	}
	t.default_font = fonts["regular"]
	t.default_font_size = SIZES["body"]

	# Tokens: everything custom-drawn reads these.
	for k: String in c:
		t.set_color(k, "Tokens", c[k])
	for k: String in CONSTANTS:
		t.set_constant(k, "Tokens", CONSTANTS[k])
	for k: String in fonts:
		t.set_font(k, "Tokens", fonts[k])
	for k: String in SIZES:
		t.set_font_size(k, "Tokens", SIZES[k])
	var row_radius: int = CONSTANTS["radius_row"]

	# The pane itself: surface, 1 px lit edge, 8 px corners.
	var pane := _box(c["surface"], CONSTANTS["radius_pane"], 1, c["edge"])
	_margins(pane, CONSTANTS["pad"], CONSTANTS["pad"])
	_variation_of(t, "PaneRoot", "PanelContainer")
	t.set_stylebox("panel", "PaneRoot", pane)
	_variation_of(t, "BodyPanel", "PanelContainer")
	t.set_stylebox("panel", "BodyPanel", StyleBoxEmpty.new())
	var toast := _box(c["hover_fill"], row_radius)
	_margins(toast, 10, 4)
	_variation_of(t, "ToastPanel", "PanelContainer")
	t.set_stylebox("panel", "ToastPanel", toast)
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())

	# Labels.
	t.set_color("font_color", "Label", c["text"])
	t.set_font("font", "Label", fonts["regular"])
	_label_variation(t, "MutedLabel", fonts["regular"], SIZES["body"], c["muted"])
	_label_variation(t, "CapsLabel", fonts["label"], SIZES["label"], c["muted"])
	_label_variation(t, "TitleLabel", fonts["semibold"], SIZES["title"], c["text"])
	_label_variation(t, "TimeLabel", fonts["medium"], SIZES["body"], c["text"])
	_label_variation(t, "ClockLabel", fonts["light"], SIZES["clock"], c["text"])
	_label_variation(t, "AccentLabel", fonts["medium"], SIZES["body"], c["accent"])
	_label_variation(t, "ChipLabel", fonts["label"], SIZES["label"], c["chip"])
	var chip := _box(Color(c["accent"], 0.0), 4, 1, c["chip"])
	_margins(chip, 6, 1)
	t.set_stylebox("normal", "ChipLabel", chip)
	_label_variation(t, "DockedTag", fonts["label"], SIZES["label"], c["accent"])
	t.set_stylebox("normal", "DockedTag", chip.duplicate())

	# Hairline rules.
	var rule := StyleBoxLine.new()
	rule.color = c["hairline"]
	rule.thickness = 1
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_constant("separation", "HSeparator", 1)
	var vrule := StyleBoxLine.new()
	vrule.color = c["hairline"]
	vrule.thickness = 1
	vrule.vertical = true
	t.set_stylebox("separator", "VSeparator", vrule)
	t.set_constant("separation", "VSeparator", 1)

	# Buttons. Normal: a hairline outline. Hover: 14 % accent fill with a 1 px accent inset ring. Focus: a 2 px accent
	# bar at the left edge and a 10 % accent fill. Toggled on (pressed): accent text on the focus fill.
	_button_styles(t, "Button", c, row_radius, true)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", c["text"])
	t.set_color("font_pressed_color", "Button", c["accent"])
	t.set_color("font_hover_pressed_color", "Button", c["accent"])
	t.set_color("font_disabled_color", "Button", Color(c["muted"], 0.6))
	t.set_font("font", "Button", fonts["medium"])
	t.set_constant("h_separation", "Button", 6)

	# List rows and places: no outline at rest.
	_variation_of(t, "RowButton", "Button")
	_button_styles(t, "RowButton", c, row_radius, false)
	t.set_font("font", "RowButton", fonts["regular"])
	_variation_of(t, "PlaceButton", "Button")
	_button_styles(t, "PlaceButton", c, row_radius, false)
	t.set_font("font", "PlaceButton", fonts["regular"])
	t.set_color("font_color", "PlaceButton", c["muted"])

	# Tabs: uppercase 11 px labels, letter-spaced; the active tab has an accent underline.
	_variation_of(t, "TabButton", "Button")
	t.set_font("font", "TabButton", fonts["label"])
	t.set_font_size("font_size", "TabButton", SIZES["label"])
	t.set_color("font_color", "TabButton", c["muted"])
	t.set_color("font_hover_color", "TabButton", c["text"])
	t.set_color("font_focus_color", "TabButton", c["muted"])
	t.set_color("font_pressed_color", "TabButton", c["text"])
	t.set_color("font_hover_pressed_color", "TabButton", c["text"])
	var tab_rest := _box(Color(c["accent"], 0.0), 0)
	_margins(tab_rest, 10, 6)
	var tab_on := tab_rest.duplicate() as StyleBoxFlat
	tab_on.border_width_bottom = 2
	tab_on.border_color = c["accent"]
	var tab_hover := _box(c["hover_fill"], row_radius)
	_margins(tab_hover, 10, 6)
	t.set_stylebox("normal", "TabButton", tab_rest)
	t.set_stylebox("hover", "TabButton", tab_hover)
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_stylebox("focus", "TabButton", _focus_box(c, row_radius))
	t.set_stylebox("disabled", "TabButton", tab_rest)

	# Transport: 44 px words; play/pause ringed, 52 px.
	_variation_of(t, "TransportButton", "Button")
	_button_styles(t, "TransportButton", c, row_radius, false)
	_variation_of(t, "PlayButton", "Button")
	var play_size: int = CONSTANTS["play_size"]
	var ring := _box(Color(c["accent"], 0.0), play_size / 2, 2, c["accent"])
	var ring_hover := _box(c["hover_fill"], play_size / 2, 2, c["accent"])
	var ring_down := _box(c["pressed_fill"], play_size / 2, 2, c["accent"])
	for s in [ring, ring_hover, ring_down]:
		_margins(s, 4, 4)
	t.set_stylebox("normal", "PlayButton", ring)
	t.set_stylebox("hover", "PlayButton", ring_hover)
	t.set_stylebox("pressed", "PlayButton", ring_down)
	t.set_stylebox("hover_pressed", "PlayButton", ring_down)
	t.set_stylebox("disabled", "PlayButton", ring)
	var ring_focus := _box(c["focus_fill"], play_size / 2)
	t.set_stylebox("focus", "PlayButton", ring_focus)
	t.set_font("font", "PlayButton", fonts["semibold"])

	# Keys of the on-pane keyboard: as buttons, a little tighter.
	_variation_of(t, "KeyButton", "Button")
	var key := _box(c["field"], 4, 1, c["hairline"])
	_margins(key, 2, 2)
	t.set_stylebox("normal", "KeyButton", key)

	# Text fields.
	var field := _box(c["field"], row_radius, 1, c["hairline"])
	_margins(field, 10, 6)
	var field_focus := _box(c["field"], row_radius, 1, c["accent"])
	_margins(field_focus, 10, 6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", c["text"])
	t.set_color("font_placeholder_color", "LineEdit", Color(c["muted"], 0.7))
	t.set_color("caret_color", "LineEdit", c["accent"])
	t.set_color("selection_color", "LineEdit", c["selection"])
	t.set_font("font", "LineEdit", fonts["regular"])

	# Sliders: a 2 px track, the filled part in the accent, a 12 px accent knob.
	var track := _box(c["seek_track"], 1)
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	var filled := _box(c["accent"], 1)
	filled.content_margin_top = 1
	filled.content_margin_bottom = 1
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var knob := _disc(CONSTANTS["seek_knob"], c["accent"])
	var knob_big := _disc(CONSTANTS["seek_knob"] + 4, c["accent"])
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob_big)
	t.set_icon("grabber_disabled", "HSlider", _disc(CONSTANTS["seek_knob"], c["muted"]))
	t.set_icon("tick", "HSlider", _disc(2, c["seek_tick"]))
	t.set_constant("center_grabber", "HSlider", 1)

	# Scroll bars: thin, muted, no track.
	for bar in ["VScrollBar", "HScrollBar"]:
		var grab := _box(c["scroll_grabber"], 3)
		_margins(grab, 3, 3)
		var grab_hi := _box(c["accent"], 3)
		_margins(grab_hi, 3, 3)
		var bg := StyleBoxEmpty.new()
		bg.content_margin_left = 3
		bg.content_margin_right = 3
		bg.content_margin_top = 3
		bg.content_margin_bottom = 3
		t.set_stylebox("scroll", bar, bg)
		t.set_stylebox("scroll_focus", bar, bg)
		t.set_stylebox("grabber", bar, grab)
		t.set_stylebox("grabber_highlight", bar, grab_hi)
		t.set_stylebox("grabber_pressed", bar, grab_hi)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())

	# Docked: the focused control also gets a 1 px accent outline (ui/pane_style.gd swaps this in).
	for k in ["Button", "RowButton", "PlaceButton", "TransportButton", "TabButton", "KeyButton"]:
		t.set_stylebox("focus_docked_" + k, "Tokens", _focus_box(c, row_radius, true))
	t.set_stylebox("focus_docked_PlayButton", "Tokens", _box(c["focus_fill"], play_size / 2, 1, c["accent"]))
	return t


## Makes FONT_RESOURCE from FONT_SOURCE when it is missing or older, and returns it loaded from its path (so the
## theme refers to it instead of embedding it).
static func font_resource() -> FontFile:
	var src := ProjectSettings.globalize_path(FONT_SOURCE)
	var dst := ProjectSettings.globalize_path(FONT_RESOURCE)
	if not FileAccess.file_exists(dst) or FileAccess.get_modified_time(dst) < FileAccess.get_modified_time(src):
		var f := FontFile.new()
		var err := f.load_dynamic_font(FONT_SOURCE)
		if err != OK:
			push_error("Pane theme: can't read %s (%s)" % [FONT_SOURCE, error_string(err)])
			return null
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		f.generate_mipmaps = true
		ResourceSaver.save(f, FONT_RESOURCE)
	return load(FONT_RESOURCE) as FontFile


static func _variation(base: FontFile, features: Dictionary, embolden: float, tracking: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.opentype_features = features
	f.variation_embolden = embolden
	f.spacing_glyph = tracking
	return f


static func _box(bg: Color, radius: int, border := 0, border_colour := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_colour
	s.anti_aliasing = true
	return s


static func _margins(s: StyleBox, h: float, v: float) -> void:
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v


## The focus look: a 2 px accent bar at the left edge plus a 10 % accent fill; docked adds a 1 px accent outline.
static func _focus_box(c: Dictionary, radius: int, docked := false) -> StyleBoxFlat:
	var s := _box(c["focus_fill"], radius, 1 if docked else 0, c["accent"])
	s.border_width_left = 2
	s.border_color = c["accent"]
	s.draw_center = true
	return s


static func _button_styles(t: Theme, type: String, c: Dictionary, radius: int, outlined: bool) -> void:
	var normal := _box(Color(c["accent"], 0.0), radius, 1 if outlined else 0, c["hairline"])
	var hover := _box(c["hover_fill"], radius, 1, c["accent"])
	var pressed := _box(c["focus_fill"], radius, 1 if outlined else 0, c["hairline"])
	var hover_pressed := _box(c["hover_fill"], radius, 1, c["accent"])
	var disabled := normal.duplicate() as StyleBoxFlat
	for s in [normal, hover, pressed, hover_pressed, disabled]:
		_margins(s, 12, 6)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, hover_pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, _focus_box(c, radius))


static func _variation_of(t: Theme, type: String, base: String) -> void:
	t.set_type_variation(type, base)


static func _label_variation(t: Theme, type: String, font: Font, size: int, colour: Color) -> void:
	_variation_of(t, type, "Label")
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, colour)


## A filled circle, for the slider knob.
static func _disc(diameter: int, colour: Color) -> ImageTexture:
	var img := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(colour, colour.a * clampf(r - d + 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
