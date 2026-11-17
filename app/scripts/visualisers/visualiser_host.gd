extends Node

## Runs one visualiser (docs/visualisers.md) for the music card (scripts/play/music_source.gd): its shader on a
## ColorRect in a see-through viewport of its own, fed the shared analysis (scripts/play/audio_analysis.gd) and its
## parameters each frame, and shown on the card through the flash limit. The host, not the visualiser, keeps to the
## rules, so a careless one cannot break them:
##   the flash limit   the picture's average relative luminance may stand at most MARGIN over a floor that follows it
##                     down at once and up at most RISE a second; the card scales the picture down when it would
##                     (shaders/visualiser_limit.gdshader measures, visualiser_copy.gdshader remembers,
##                     visualiser_apply.gdshader applies). Flicker of the average faster than 3 Hz stays near 0.1.
##   the GPU budget    the visualiser's own viewport is timed on the GPU; over budget_ms (averaged over a second) it
##                     draws at the next lower SCALES step, stretched to its area. It does not come back up until the
##                     visualiser is chosen again.
## The viewports nest so the engine draws them in order each frame (children first, renderer_viewport.cpp
## _sort_active_viewports): visualiser, then measure, then copy, then the card that holds them all.
##
##   setup(card: SubViewport, output: TextureRect)   output shows the visualiser on the card (the host sets its texture
##                                                   and material; the card places and sizes it)
##   use(id) -> bool        start a visualiser (VisualiserRegistry); false when it is unknown
##   set_area(size)         the area's size in card pixels
##   set_active(on)         off: nothing is drawn or fed (the card shows no visualiser); on again starts afresh
##   id, entry, scale, gpu_ms, budget_ms (0: no budget), cover, playing, frames
##   stats() -> Dictionary  id, area, viewport size, scale, gpu_ms, frames

const Registry := preload("res://scripts/visualisers/visualiser_registry.gd")
const AudioAnalysis := preload("res://scripts/play/audio_analysis.gd")
const LIMIT_SHADER := preload("res://shaders/visualiser_limit.gdshader")
const COPY_SHADER := preload("res://shaders/visualiser_copy.gdshader")
const APPLY_SHADER := preload("res://shaders/visualiser_apply.gdshader")

## The flash limit (relative luminance, linear light, 0..1): at most MARGIN over the floor, which rises at most RISE a
## second. A flicker of the average at f Hz then swings at most MARGIN + RISE / (2 f): 0.11 at 3 Hz.
const MARGIN := 0.08
const RISE := 0.2
## The card behind a see-through visualiser (MusicCard's background, 0.06 0.06 0.08), as relative luminance.
const BEHIND := 0.0049
## GPU milliseconds a visualiser may take each frame (the headset draws a frame in 11 ms at 90 Hz, both eyes).
const BUDGET_MS := 2.0
const SCALES: Array[float] = [1.0, 0.75, 0.5, 0.35]
## The measuring and copying viewports: the engine makes none smaller than 2 x 2, and every pixel holds the same.
const SMALL := Vector2i(2, 2)
## Frames after use() in which the floor starts from the picture itself (a start is one change, not a flicker).
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

var _area := Vector2(640, 160)
var _vp: SubViewport
var _rect: ColorRect
var _mat: ShaderMaterial
var _measure_vp: SubViewport
var _measure_mat: ShaderMaterial
var _copy_vp: SubViewport
var _output: TextureRect
var _scale_step := 0
var _over_s := 0.0
var _grey: Texture2D


func setup(card: SubViewport, output: TextureRect) -> void:
	_output = output
	# Copy (parent) <- measure <- visualiser: drawn visualiser first, the card last.
	_copy_vp = _small_vp("VisualiserCopy")
	card.add_child(_copy_vp)
	_measure_vp = _small_vp("VisualiserMeasure")
	_copy_vp.add_child(_measure_vp)
	_vp = SubViewport.new()
	_vp.name = "Visualiser"
	_vp.disable_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_measure_vp.add_child(_vp)
	_rect = ColorRect.new()
	_rect.color = Color.WHITE
	_vp.add_child(_rect)
	_measure_mat = ShaderMaterial.new()
	_measure_mat.shader = LIMIT_SHADER
	_measure_mat.set_shader_parameter("picture", _vp.get_texture())
	_measure_mat.set_shader_parameter("previous", _copy_vp.get_texture())
	_measure_mat.set_shader_parameter("margin", MARGIN)
	_measure_mat.set_shader_parameter("rise", RISE)
	_measure_mat.set_shader_parameter("behind", BEHIND)
	_measure_vp.add_child(_pixel(_measure_mat))
	var copy_mat := ShaderMaterial.new()
	copy_mat.shader = COPY_SHADER
	copy_mat.set_shader_parameter("source", _measure_vp.get_texture())
	_copy_vp.add_child(_pixel(copy_mat))
	var apply := ShaderMaterial.new()
	apply.shader = APPLY_SHADER
	apply.set_shader_parameter("state", _measure_vp.get_texture())
	_output.material = apply
	_output.texture = _vp.get_texture()
	_output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_output.stretch_mode = TextureRect.STRETCH_SCALE
	_output.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5))
	_grey = ImageTexture.create_from_image(img)
	_resize()


static func _small_vp(vp_name: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = vp_name
	vp.size = SMALL
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return vp


static func _pixel(mat: ShaderMaterial) -> ColorRect:
	var r := ColorRect.new()
	r.size = Vector2(SMALL)
	r.material = mat
	return r


func use(new_id: String) -> bool:
	var shader := Registry.load_shader(new_id)
	if shader == null:
		return false
	id = new_id
	entry = Registry.entry(new_id)
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect.material = _mat
	var a := AudioAnalysis.shared
	if a != null:
		_mat.set_shader_parameter("spectrum", a.spectrum_texture())
		_mat.set_shader_parameter("waveform", a.wave_texture())
	_scale_step = 0
	_over_s = 0.0
	frames = 0
	vis_time = 0.0
	_resize()
	return true


func set_active(on: bool) -> void:
	if on == is_processing() and _vp != null and on == (_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS):
		return
	set_process(on)
	for vp: SubViewport in [_vp, _measure_vp, _copy_vp]:
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
	scale = SCALES[_scale_step]
	var px := Vector2i(maxi(1, roundi(_area.x * scale)), maxi(1, roundi(_area.y * scale)))
	_vp.size = px
	_rect.size = Vector2(px)


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
	_measure_mat.set_shader_parameter("dt", delta)
	_measure_mat.set_shader_parameter("reset", frames <= RESET_FRAMES)
	_budget(delta)


## Times the visualiser's viewport on the GPU and steps the scale down when it stays over budget for a second.
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
			"scale": scale, "gpu_ms": snappedf(gpu_ms, 0.01), "frames": frames}


## The visualiser's own picture (before the flash limit; tests).
func picture() -> Texture2D:
	return _vp.get_texture() if _vp != null else null


## The flash limit's pixel: r, g the floor, b the measured average (square root), a the gain (tests).
func limit_texture() -> Texture2D:
	return _measure_vp.get_texture() if _measure_vp != null else null
