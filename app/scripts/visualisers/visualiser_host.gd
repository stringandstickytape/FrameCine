extends Node

## Runs one visualiser (docs/visualisers.md) for the music card (scripts/play/music_source.gd): its shader on a
## ColorRect in a see-through viewport of its own, fed the shared analysis (scripts/play/audio_analysis.gd) and its
## parameters each frame, and shown on the card through the flash limit. The host, not the visualiser, keeps to the
## rules, so a careless one cannot break them:
##   the flash limit   two rules, measured on the GPU each frame (docs/visualisers.md, "The flash limit"):
##                     the whole picture's brightness may stand at most MARGIN over a floor that follows it down at
##                     once and up at most RISE a second (a gain on the whole picture); and flicker over an area: each
##                     of TAPS sample points keeps its own slow average, its distance from it is its flicker, pooled
##                     in CELLS and over the card by area; over FLICKER_MAX, the most flickering cells are dimmed just
##                     enough to bring it down. The second catches patterns that swap with a steady average
##                     (checkerboards, stripes) and flicker in part of the picture.
##   the GPU budget    a new visualiser first draws PROBE_FRAMES frames at about PROBE_PIXELS, timed on the GPU; from
##                     that the full size's cost is estimated, and it starts at the largest SCALES step within
##                     budget_ms, or is refused (over REFUSE_MS at the smallest) and the one before stays. While it
##                     runs, more than budget_ms (averaged) for a second steps the scale down. It does not come back up
##                     until the visualiser is chosen again.
## The viewports nest so the engine draws them in order each frame (children first, renderer_viewport.cpp
## _sort_active_viewports): visualiser, sample points, cells, limit, then the copies of the points and the limit (read
## next frame), then the card that holds them all. Nothing is read back to the CPU.
##
##   setup(card: SubViewport, output: TextureRect)   output shows the visualiser on the card (the host sets its texture
##                                                   and material; the card places and sizes it)
##   use(id) -> bool        start a visualiser (VisualiserRegistry); false when it is unknown or never compiled. The
##                          probe then runs; a refusal puts the one before back (refused, last_refusal)
##   set_area(size)         the area's size in card pixels
##   set_active(on)         off: nothing is drawn or fed (the card shows no visualiser); on again starts afresh
##   probing() -> bool      the first frames' timing is still running
##   id, entry, scale, gpu_ms, budget_ms (0: no budget and no probe), cover, playing, frames, last_refusal
##   stats() -> Dictionary  id, area, viewport size, scale, gpu_ms, frames, probe
##   signal refused(id, why)

signal refused(refused_id: String, why: String)

const Registry := preload("res://scripts/visualisers/visualiser_registry.gd")
const AudioAnalysis := preload("res://scripts/play/audio_analysis.gd")
const TAPS_SHADER := preload("res://shaders/visualiser_taps.gdshader")
const CELLS_SHADER := preload("res://shaders/visualiser_cells.gdshader")
const LIMIT_SHADER := preload("res://shaders/visualiser_limit.gdshader")
const COPY_SHADER := preload("res://shaders/visualiser_copy.gdshader")
const APPLY_SHADER := preload("res://shaders/visualiser_apply.gdshader")

## The whole picture's brightness (relative luminance, linear light, 0..1): at most MARGIN over the floor, which rises
## at most RISE a second. A flicker of the average at f Hz then swings at most MARGIN + RISE / (2 f): 0.11 at 3 Hz.
const MARGIN := 0.08
const RISE := 0.2
## Flicker over an area: sample points (each with a slow average over TAU seconds) and cells (8 x 8 points each).
const TAPS := Vector2i(128, 72)
const CELLS := Vector2i(16, 9)
const TAU := 0.25
## The flicker total allowed, as a share of the card: the mean of every point's distance from its own average,
## weighted by the visualiser's share of the card. A black and white pattern swapping over the whole card is 0.5;
## 0.1 of contrast swapping over a quarter of it (where the guidance starts) is 0.0125. The app's own visualisers on
## the drums test signal stay under it (docs/visualisers.md has the measured figures).
const FLICKER_MAX := 0.02
## A dimmed cell's cap doubles every RECOVER seconds back towards none.
const RECOVER := 0.25
## The card behind a see-through visualiser (MusicCard's background, 0.06 0.06 0.08), as relative luminance.
const BEHIND := 0.0049
## GPU milliseconds a visualiser may take each frame (the headset draws a frame in 11 ms at 90 Hz, both eyes).
const BUDGET_MS := 2.0
const SCALES: Array[float] = [1.0, 0.75, 0.5, 0.35]
## The first frames' timing: this many frames at about this many pixels; refused when even the smallest scale would
## take more than REFUSE_MS.
const PROBE_FRAMES := 6
const PROBE_PIXELS := 256 * 144
const REFUSE_MS := 4.0
## The engine makes no viewport smaller than 2 x 2.
const SMALL := Vector2i(2, 2)
## Frames after a start in which the limit starts from the picture itself (a start is one change, not a flicker).
const RESET_FRAMES := 3

var id := ""
var entry := {}
var scale := 1.0
var gpu_ms := 0.0
var budget_ms := BUDGET_MS
var cover: Texture2D
var playing := true
var frames := 0
var vis_time := 0.0
## {id, why, estimate_ms} of the last visualiser refused by the probe, or {}.
var last_refusal := {}
## Tests: the probe's measured milliseconds instead of the GPU's (-1: the GPU's).
var probe_ms_override := -1.0

var _area := Vector2(640, 160)
var _card_px := 1280.0 * 720.0
var _vp: SubViewport
var _rect: ColorRect
var _mat: ShaderMaterial
var _small: Array[SubViewport] = []
var _taps_vp: SubViewport
var _taps_mat: ShaderMaterial
var _cells_vp: SubViewport
var _limit_vp: SubViewport
var _limit_mat: ShaderMaterial
var _output: TextureRect
var _scale_step := 0
var _over_s := 0.0
var _grey: Texture2D
var _probe_left := 0
var _probe_ms := 0.0
var _probe_px := 1.0
var _before := {}


func setup(card: SubViewport, output: TextureRect) -> void:
	_output = output
	_card_px = float(card.size.x * card.size.y)
	# Nested so the innermost draws first: limit copy > points copy > limit > cells > points > visualiser.
	var limit_copy := _small_vp("VisualiserLimitCopy", SMALL)
	card.add_child(limit_copy)
	var taps_copy := _small_vp("VisualiserPointsCopy", TAPS)
	limit_copy.add_child(taps_copy)
	_limit_vp = _small_vp("VisualiserLimit", SMALL)
	taps_copy.add_child(_limit_vp)
	_cells_vp = _small_vp("VisualiserCells", CELLS)
	_limit_vp.add_child(_cells_vp)
	_taps_vp = _small_vp("VisualiserPoints", TAPS)
	_cells_vp.add_child(_taps_vp)
	_vp = SubViewport.new()
	_vp.name = "Visualiser"
	_vp.disable_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_taps_vp.add_child(_vp)
	_rect = ColorRect.new()
	_rect.color = Color.WHITE
	_rect.visible = false
	_vp.add_child(_rect)
	_small = [_taps_vp, _cells_vp, _limit_vp, taps_copy, limit_copy]
	_taps_mat = _material(TAPS_SHADER, {"picture": _vp.get_texture(), "previous": taps_copy.get_texture(),
			"taps": Vector2(TAPS), "tau": TAU, "behind": BEHIND})
	_taps_vp.add_child(_fill(_taps_mat, TAPS))
	_cells_vp.add_child(_fill(_material(CELLS_SHADER, {"points": _taps_vp.get_texture(), "taps": Vector2(TAPS),
			"cells": Vector2(CELLS)}), CELLS))
	_limit_mat = _material(LIMIT_SHADER, {"cells": _cells_vp.get_texture(), "previous": limit_copy.get_texture(),
			"grid": Vector2(CELLS), "margin": MARGIN, "rise": RISE, "flicker_max": FLICKER_MAX, "recover": RECOVER})
	_limit_vp.add_child(_fill(_limit_mat, SMALL))
	taps_copy.add_child(_fill(_material(COPY_SHADER, {"source": _taps_vp.get_texture()}), TAPS))
	limit_copy.add_child(_fill(_material(COPY_SHADER, {"source": _limit_vp.get_texture()}), SMALL))
	_output.material = _material(APPLY_SHADER, {"state": _limit_vp.get_texture(), "cells": _cells_vp.get_texture()})
	_output.texture = _vp.get_texture()
	_output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_output.stretch_mode = TextureRect.STRETCH_SCALE
	_output.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5))
	_grey = ImageTexture.create_from_image(img)
	_resize()


static func _small_vp(vp_name: String, size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = vp_name
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return vp


static func _material(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _fill(mat: ShaderMaterial, size: Vector2i) -> ColorRect:
	var r := ColorRect.new()
	r.size = Vector2(size)
	r.material = mat
	return r


func use(new_id: String) -> bool:
	var shader := Registry.load_shader(new_id)
	if shader == null:
		return false
	if id != "" and _probe_left == 0:
		_before = {"id": id, "entry": entry, "mat": _mat, "step": _scale_step}
	id = new_id
	entry = Registry.entry(new_id)
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	var a := AudioAnalysis.shared
	if a != null:
		_mat.set_shader_parameter("spectrum", a.spectrum_texture())
		_mat.set_shader_parameter("waveform", a.wave_texture())
	_start(0)
	if budget_ms > 0.0:
		_probe_left = PROBE_FRAMES
		_probe_ms = 0.0
		_resize()
	return true


## (Re)starts the material on the rect at a scale step: the limit and the clock afresh.
func _start(step: int) -> void:
	_rect.material = _mat
	_rect.visible = _mat != null
	_scale_step = step
	_over_s = 0.0
	frames = 0
	vis_time = 0.0
	_probe_left = 0
	_resize()


func probing() -> bool:
	return _probe_left > 0


func set_active(on: bool) -> void:
	if on == is_processing() and _vp != null and on == (_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS):
		return
	set_process(on)
	for vp: SubViewport in _small + [_vp]:
		if vp != null:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		frames = 0


func set_area(size: Vector2) -> void:
	if size.is_equal_approx(_area):
		return
	_area = size
	_resize()


func _resize() -> void:
	if _vp == null:
		return
	var px: Vector2i
	if _probe_left > 0:
		# The probe: the area's shape at about PROBE_PIXELS (never larger than the area).
		var k := minf(1.0, sqrt(PROBE_PIXELS / maxf(_area.x * _area.y, 1.0)))
		px = Vector2i(maxi(2, roundi(_area.x * k)), maxi(2, roundi(_area.y * k)))
		_probe_px = float(px.x * px.y)
		scale = k
	else:
		scale = SCALES[_scale_step]
		px = Vector2i(maxi(2, roundi(_area.x * scale)), maxi(2, roundi(_area.y * scale)))
	_vp.size = px
	_rect.size = Vector2(px)
	if _limit_mat != null:
		_limit_mat.set_shader_parameter("area_share", clampf(_area.x * _area.y / _card_px, 0.0, 1.0))


func _process(delta: float) -> void:
	if _mat == null:
		return
	frames += 1
	if playing:
		vis_time += delta
	var a := AudioAnalysis.shared
	if a != null:
		for k: String in ["bass", "mid", "treble", "level", "beat"]:
			_mat.set_shader_parameter(k, float(a.get(k)))
		_mat.set_shader_parameter("beats", float(a.beats))
	_mat.set_shader_parameter("vis_time", vis_time)
	_mat.set_shader_parameter("size", _area)
	_mat.set_shader_parameter("cover", cover if cover != null else _grey)
	_mat.set_shader_parameter("has_cover", 1.0 if cover != null else 0.0)
	var vals := Registry.values(id)
	for pname: String in vals:
		_mat.set_shader_parameter(pname, vals[pname])
	var reset := frames <= RESET_FRAMES
	for m: ShaderMaterial in [_taps_mat, _limit_mat]:
		m.set_shader_parameter("dt", delta)
		m.set_shader_parameter("reset", reset)
	if _probe_left > 0:
		_probe(delta)
	else:
		_budget(delta)


## The first frames: the most the GPU took for one (the first two are not measured yet), then the decision.
func _probe(delta: float) -> void:
	var ms := probe_ms_override if probe_ms_override >= 0.0 \
			else RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid())
	gpu_ms = lerpf(gpu_ms, ms, clampf(delta * 4.0, 0.0, 1.0))
	if PROBE_FRAMES - _probe_left >= 2:
		_probe_ms = maxf(_probe_ms, ms)
	_probe_left -= 1
	if _probe_left > 0:
		return
	var full := _probe_ms * maxf(_area.x * _area.y, 1.0) / _probe_px
	var step := 0
	while step < SCALES.size() - 1 and full * SCALES[step] * SCALES[step] > budget_ms:
		step += 1
	var smallest := full * SCALES[step] * SCALES[step]
	if smallest > REFUSE_MS:
		var why := "too heavy for the headset: about %.0f ms a frame at full size (%.1f at the smallest; the most " \
				% [full, smallest] + "allowed is %.0f). Fewer loop steps or cheaper maths per pixel." % REFUSE_MS
		last_refusal = {"id": id, "why": why, "estimate_ms": snappedf(full, 0.1)}
		print("Visualiser: %s refused: %s" % [id, why])
		var refused_id := id
		_restore()
		refused.emit(refused_id, why)
		return
	if step > 0:
		print("Visualiser: %s would take about %.1f ms at full size; drawing at %d %%" % [id, full,
				roundi(SCALES[step] * 100.0)])
	_start(step)


## The visualiser before a refused one, as it was; or none.
func _restore() -> void:
	if _before.is_empty():
		id = ""
		entry = {}
		_mat = null
		_start(0)
		return
	id = _before["id"]
	entry = _before["entry"]
	_mat = _before["mat"]
	_start(_before["step"])


## While it runs: steps the scale down when it stays over budget for a second.
func _budget(delta: float) -> void:
	var ms := RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid())
	gpu_ms = lerpf(gpu_ms, ms, clampf(delta * 4.0, 0.0, 1.0))
	if budget_ms <= 0.0 or _scale_step >= SCALES.size() - 1:
		return
	_over_s = _over_s + delta if gpu_ms > budget_ms else 0.0
	if _over_s >= 1.0:
		_over_s = 0.0
		_scale_step += 1
		print("Visualiser: %s takes %.1f ms on the GPU (budget %.1f); drawing at %d %%" % [id, gpu_ms, budget_ms,
				roundi(SCALES[_scale_step] * 100.0)])
		_resize()


func stats() -> Dictionary:
	return {"id": id, "area": [roundi(_area.x), roundi(_area.y)], "viewport": [_vp.size.x, _vp.size.y] if _vp else [],
			"scale": snappedf(scale, 0.01), "gpu_ms": snappedf(gpu_ms, 0.01), "frames": frames, "probe": probing()}


## The flash limit's state now (reads four pixels back: status and tests only, never every frame).
func limit_state() -> Dictionary:
	var img := _limit_vp.get_texture().get_image()
	var p := img.get_pixel(0, 0)
	var k := img.get_pixel(1, 0)
	var f := img.get_pixel(0, 1)
	var cap := k.r + k.g / 255.0
	var most := f.b * f.b
	return {"gain": p.a, "floor": p.r + p.g / 255.0, "average": p.b * p.b, "flicker": f.r + f.g / 255.0,
			"flicker_max": FLICKER_MAX, "cap": cap, "most_flicker": most,
			"dimming": p.a < 0.99 or cap < most - 0.0005}


## The visualiser's own picture (before the flash limit; tests).
func picture() -> Texture2D:
	return _vp.get_texture() if _vp != null else null


## The flash limit's 2 x 2 results (pixel (0, 0): r, g the floor, b the average's square root, a the gain; tests).
func limit_texture() -> Texture2D:
	return _limit_vp.get_texture() if _limit_vp != null else null
