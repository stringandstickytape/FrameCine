extends Node

## Auto letterbox crop (ideas #42): a 2.39 film stored in a 16:9 frame has black bars above and below; the crop shows
## only the picture and grows the screen to keep its height (constant height, as a cinema's scope screen is wider),
## so the bars do not take room, light the room (#29) or show on the floor (#62). Pillarboxed 4:3 in 16:9 keeps its
## height and loses the black sides.
##
## The engine finds the picture (MediaSource.letterbox_detection, set before the file opens, through
## HWVideoSource.letterbox_detection; fork c318810fdd): a nice-10 thread decodes a keyframe now and then and reports
## get_letterbox() {uv_rect, bars, picture_aspect, known, done, ...}. The rectangle is snapped to the nearest cinema
## aspect within SNAP (2.39, 2.35, 1.85, ...). 3D: side-by-side files take only the rows (bars above and below each
## eye), top-and-bottom files only the columns. Off by default; turning it on reopens the open file at its place.
##
##   enabled, set_enabled(on)        [picture] auto_crop (default off)
##   grow, set_grow(on)              [picture] auto_crop_grow (default on): keep the picture's height; off keeps the width
##   crop                            the whole-frame UV rectangle shown now (Rect2(0, 0, 1, 1): none)
##   aspect                          the picture's aspect after the crop (0 before)
##   state() -> {enabled, detecting, known, bars, aspect, text}    for the footer
##   static crop_for(letterbox, layout, base_aspect) -> Rect2
##   signal changed

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const VideoMode := preload("res://scripts/video_mode.gd")

signal changed

const ASPECTS: Array[float] = [1.33, 1.375, 1.43, 1.5, 1.66, 1.78, 1.85, 1.9, 2.0, 2.2, 2.35, 2.39, 2.76]
const SNAP := 0.025
const POLL_SECONDS := 0.5

var main: Node3D
var enabled := false
var grow := true
var crop := Rect2(0, 0, 1, 1)
var aspect := 0.0
var _lb := {}
var _since := 0.0
var _reopen_at := -1.0
var _applied := false


func _ready() -> void:
	enabled = bool(main.settings.get_value("picture", "auto_crop", false))
	grow = bool(main.settings.get_value("picture", "auto_crop_grow", true))
	HWVideoSource.letterbox_detection = enabled
	main.file_opened.connect(_on_file_opened)
	main.mode_changed.connect(func(_m: Variant, _t: String) -> void: _apply.call_deferred())
	main.player.format_changed.connect(func() -> void: _apply.call_deferred())


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("picture", "auto_crop", true if on else null)
	HWVideoSource.letterbox_detection = on
	var src: Object = main.player.source
	if on and src != null and src.has_method("get_letterbox") and not bool(src.get_letterbox().get("enabled", false)) \
			and main.current_path != "":
		# The detector starts when the file opens: open it again where it was.
		_reopen_at = main.player.get_position()
		main.open_path(main.current_path, false)
		return
	_update_crop()
	changed.emit()


func set_grow(on: bool) -> void:
	grow = on
	main.settings.set_value("picture", "auto_crop_grow", null if on else false)
	_apply()


## localised: text in the menus' language (the footer, docs/i18n.md); else English (the dev link).
func state(localised := false) -> Dictionary:
	var known := bool(_lb.get("known", false))
	var bars := bool(_lb.get("bars", false))
	var detecting := enabled and not _lb.is_empty() and not bool(_lb.get("done", false)) and not known
	var text := "Off"
	if enabled:
		if _lb.is_empty():
			text = "Not available for this file"
		elif detecting:
			text = "Looking for bars"
		elif known and bars:
			text = (TranslationServer.translate("Cropped to %.2f:1") if localised else "Cropped to %.2f:1") % aspect
		else:
			text = "No bars"
	if localised and not (known and bars and enabled):
		text = TranslationServer.translate(text)
	return {"enabled": enabled, "detecting": detecting, "known": known, "bars": bars, "aspect": aspect, "text": text}


## The whole-frame UV rectangle to show for the detector's result, snapped to a cinema aspect. base_aspect: one eye's
## display aspect of the full frame (VideoMode.display_aspect()).
static func crop_for(lb: Dictionary, layout: int, base_aspect: float) -> Rect2:
	if not bool(lb.get("known", false)) or not bool(lb.get("bars", false)):
		return Rect2(0, 0, 1, 1)
	var r: Rect2 = lb.get("uv_rect", Rect2(0, 0, 1, 1))
	if layout == VideoMode.Layout.SBS:
		r = Rect2(0.0, r.position.y, 1.0, r.size.y)
	elif layout == VideoMode.Layout.TB:
		r = Rect2(r.position.x, 0.0, r.size.x, 1.0)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return Rect2(0, 0, 1, 1)
	var a := base_aspect * r.size.x / r.size.y
	var best := 0.0
	for c in ASPECTS:
		if absf(a / c - 1.0) < SNAP and (best == 0.0 or absf(a - c) < absf(a - best)):
			best = c
	if best > 0.0:
		var centre := r.get_center()
		if r.size.y < 1.0:
			r.size.y = minf(base_aspect * r.size.x / best, 1.0)
		else:
			r.size.x = minf(best * r.size.y / base_aspect, 1.0)
		r.position = centre - r.size * 0.5
	return r


func _on_file_opened(_path: String) -> void:
	_lb = {}
	crop = Rect2(0, 0, 1, 1)
	aspect = 0.0
	_since = POLL_SECONDS
	if _reopen_at >= 0.0:
		var t := _reopen_at
		_reopen_at = -1.0
		if main.player.can_seek():
			main.player.seek(t)
	_apply()
	changed.emit()


func _process(delta: float) -> void:
	if not enabled:
		return
	_since += delta
	if _since < POLL_SECONDS:
		return
	_since = 0.0
	var src: Object = main.player.source
	if src == null or not src.has_method("get_letterbox"):
		return
	if bool(_lb.get("done", false)) and bool(_lb.get("known", false)):
		return
	_lb = src.get_letterbox()
	_update_crop()


func _update_crop() -> void:
	var r := Rect2(0, 0, 1, 1)
	if enabled and not main.mode.is_spherical():
		r = crop_for(_lb, int(main.mode.layout), main.mode.display_aspect(main._frame_size()))
	if r != crop:
		crop = r
		_apply()
		changed.emit()


func _apply() -> void:
	var screen: Node3D = main.screen
	var src: Object = main.player.source
	if src == null:
		return
	var vis: Rect2 = src.get_visible_uv_rect()
	var full: Vector2 = main._frame_size()
	var on: bool = crop != Rect2(0, 0, 1, 1) and not main.mode.is_spherical()
	if on:
		screen.set_mode(main.mode, full * crop.size)
		screen.set_visible_rect(Rect2(vis.position + crop.position * vis.size, crop.size * vis.size))
		aspect = main.mode.display_aspect(full * crop.size)
	else:
		if _applied:
			# Back to the whole frame.
			screen.set_mode(main.mode, full)
			screen.set_visible_rect(vis)
		aspect = main.mode.display_aspect(full) if bool(_lb.get("known", false)) else 0.0
	_applied = on
	var s := crop.size.x / crop.size.y if on and grow else 1.0
	if not is_equal_approx(screen.size_scale, s) or on:
		screen.size_scale = s
		main._place_screen()
