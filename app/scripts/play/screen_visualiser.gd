extends Node

## A visualiser on the screen for whatever plays (docs/visualisers.md, "On the screen for anything"): a film or a
## captured window keeps playing, and its picture gives way to the visualiser of its sound, on the whole screen. The
## buttons beside the screen (ui/screen_buttons.gd) turn it on and off and step through the visualisers; this is what
## they call.
##
## A music file, and a still picture shown as the music card, already have a visualiser on their card
## (scripts/play/music_source.gd): for those, on / off is the card's visualiser against "off", and nothing here draws.
## For anything else that is flat, while on: a viewport the shape of the screen's picture (HEIGHT tall) runs the
## chosen visualiser through the same host as the card (scripts/visualisers/visualiser_host.gd: the flash limit, the
## GPU budget), and the screen's mesh draws that viewport with a plain material of its own (VideoScreen.set_override),
## so none of the film's picture code (stereo layout, crop, zoom, tone mapping, the pointer's cursor) touches it. The
## film layer steps aside (FilmLayer.request_scene) while it shows.
## A visualiser with "picture": true in its manifest is also given the picture of what plays, to put where it likes
## inside itself (host.film): a window's own texture, or a film's planes drawn to RGB in a small viewport
## (PICTURE_HEIGHT tall; shaders/still_picture.gdshader: the file's matrix and range, one eye of a 3D film, no HDR tone
## mapping). Only while such a visualiser runs.
## The sound is the shared analysis's (scripts/play/audio_analysis.gd): the Film bus for a file; a captured window's
## own sound when the app can hear it (scripts/play/window_audio.gd).
## On is for what plays now: a new file starts with its own picture. --visualiser[=ID] turns it on for the first file
## opened.
##
##   usable() -> bool      something flat is playing
##   is_on() -> bool       the visualiser shows in place of the picture (or on the card)
##   set_on(on), toggle()
##   step(by)              the next (+1) or previous (-1) visualiser, in the menu's order; never "off"
##   style_name() -> String   the chosen visualiser's name, for people
##   host                  the VisualiserHost while it draws (null otherwise)
##   signal changed        on / off, the visualiser, or what plays changed

signal changed

const MusicSource := preload("res://scripts/play/music_source.gd")
const Registry := preload("res://scripts/visualisers/visualiser_registry.gd")
const VisualiserHost := preload("res://scripts/visualisers/visualiser_host.gd")
const AudioAnalysis := preload("res://scripts/play/audio_analysis.gd")
const HEIGHT := 720
const MAX_WIDTH := 1728
const WHO := "visualiser"
const VideoMode := preload("res://scripts/video_mode.gd")
const HdrToneMap := preload("res://scripts/play/hdr_tone_map.gd")
const STILL_SHADER := preload("res://shaders/still_picture.gdshader")
const PICTURE_HEIGHT := 540
## The viewport on the screen's mesh, as it is: its values are sRGB-encoded, as the music card's are.
const SHADER := """shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque, specular_disabled;
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
void fragment() {
	ALBEDO = texture(tex, UV).rgb;
}
"""

var main: Node3D
var host: VisualiserHost
## Asked for, for what plays now (a film or a window; the card's own state is MusicSource.style).
var _on := false
## The visualiser last chosen that was not "off": what on brings back.
var _last := ""
var _vp: SubViewport
var _rect: TextureRect
var _mat: ShaderMaterial
var _showing := false
var _was_usable := false
## A film's picture as RGB for a visualiser that asks for it.
var _pic_vp: SubViewport
var _pic_mat: ShaderMaterial


func _ready() -> void:
	# After the player and the features that place the screen.
	process_priority = 90
	# --visualiser[=ID]: on for the first file opened (a check on a desktop, a tour).
	var args: Dictionary = main.get("_args") if main.get("_args") is Dictionary else {}
	var start: Variant = args.get("visualiser")
	var first := [start != null]
	main.file_opened.connect(func(p: String) -> void:
		_on = false
		if first[0] and p != "":
			first[0] = false
			if start is String and Registry.has(start):
				get_parent().call("set_visualiser", start)
			elif MusicSource.style == MusicSource.OFF:
				get_parent().call("set_visualiser", _default())
			_on = true
		changed.emit())
	# The features node (this one's parent) says when a visualiser is chosen.
	if get_parent().has_signal("visualisers_changed"):
		get_parent().connect("visualisers_changed", func() -> void: changed.emit())


func usable() -> bool:
	if main == null or main.player == null or not main.player.has_source():
		return false
	return not main.mode.is_spherical() and main.screen.is_shown()


## What plays draws a card with a visualiser of its own (a music file, a still picture as the card).
func on_card() -> bool:
	var src: Object = main.player.source if main.player != null else null
	if src == null:
		return false
	return src is MusicSource or (src.has_method("shows_card") and bool(src.shows_card()))


func is_on() -> bool:
	if not usable():
		return false
	return MusicSource.style != MusicSource.OFF and (_on or on_card())


func set_on(on: bool) -> void:
	if not usable():
		return
	if MusicSource.style != MusicSource.OFF:
		_last = MusicSource.style
	if on_card():
		main.features.set_visualiser(_default() if on else MusicSource.OFF)
	else:
		_on = on
		if on and MusicSource.style == MusicSource.OFF:
			main.features.set_visualiser(_default())
	changed.emit()


func toggle() -> void:
	set_on(not is_on())


## The next or the previous visualiser in the menu's order (round the ends), turned on.
func step(by: int) -> void:
	var ids := Registry.ids()
	if ids.is_empty() or not usable():
		return
	var now := MusicSource.style if MusicSource.style != MusicSource.OFF else _default()
	var i := ids.find(now)
	main.features.set_visualiser(ids[posmod(i + by, ids.size())] if i >= 0 else ids[0])
	if not on_card():
		_on = true
	changed.emit()


func style_name() -> String:
	var id := MusicSource.style if MusicSource.style != MusicSource.OFF else _default()
	return str(Registry.entry(id).get("name", id)) if Registry.has(id) else id


func _default() -> String:
	return _last if _last != "" and Registry.has(_last) else MusicSource.DEFAULT_STYLE


func _process(_delta: float) -> void:
	var can := usable()
	if can != _was_usable:
		_was_usable = can
		changed.emit()
	if MusicSource.style == MusicSource.OFF and _on:
		# Off chosen in the Picture tab: the picture again.
		_on = false
		changed.emit()
	var want := _on and can and not on_card()
	if want != _showing:
		_show(want)
	if not _showing:
		return
	var px := _pixels()
	if _vp.size != px:
		_vp.size = px
		_rect.size = Vector2(px)
	var style := MusicSource.style
	if style != host.id and not host.probing() and not host.use(style):
		# Unknown, or a user's shader that never compiled: the one before stays; with none, the picture again.
		push_warning("Visualiser %s is not usable; keeping %s" % [style, host.id if host.id != "" else "the picture"])
		if host.id != "":
			main.features.set_visualiser(host.id)
		else:
			_on = false
			changed.emit()
			return
	host.set_active(true)
	host.playing = main.player.is_playing()
	host.set_area(Vector2(px))
	_feed_picture()


## The picture of what plays, for a visualiser that asks for it; none otherwise (and nothing drawn for it).
func _feed_picture() -> void:
	var src: Object = main.player.source
	var wants: bool = host.wants_picture() and src != null
	if _pic_vp != null:
		_pic_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if wants and src.get_rgb_texture() == null \
				else SubViewport.UPDATE_DISABLED
	if not wants:
		host.film = null
		return
	var flat: Vector2 = main.screen.get_flat_size()
	host.film_aspect = flat.x / maxf(flat.y, 0.001)
	var rgb: Texture2D = src.get_rgb_texture()
	if rgb != null:
		host.film = rgb
		return
	var y: Texture2D = src.get_plane_texture(0)
	if y == null:
		host.film = null
		return
	if _pic_vp == null:
		_pic_vp = SubViewport.new()
		_pic_vp.name = "ScreenVisualiserPicture"
		_pic_vp.disable_3d = true
		_pic_mat = ShaderMaterial.new()
		_pic_mat.shader = STILL_SHADER
		_pic_mat.set_shader_parameter("dim", 1.0)
		var rect := ColorRect.new()
		rect.material = _pic_mat
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pic_vp.add_child(rect)
		# Before the visualiser's viewport, so this frame's picture is in it.
		add_child(_pic_vp)
		move_child(_pic_vp, 0)
		_pic_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var w := mini(MAX_WIDTH, roundi(PICTURE_HEIGHT * host.film_aspect))
	var want_px := Vector2i(maxi(2, w - w % 2), PICTURE_HEIGHT)
	if _pic_vp.size != want_px:
		_pic_vp.size = want_px
	_pic_mat.set_shader_parameter("y_tex", y)
	_pic_mat.set_shader_parameter("uv_tex", src.get_plane_texture(1))
	_pic_mat.set_shader_parameter("p010", bool(src.is_p010()))
	# One eye of a 3D film: the left half, or the top.
	var r: Rect2 = src.get_visible_uv_rect()
	var mode: VideoMode = main.mode
	if mode.layout == VideoMode.Layout.SBS:
		r.size.x *= 0.5
	elif mode.layout == VideoMode.Layout.TB:
		r.size.y *= 0.5
	_pic_mat.set_shader_parameter("visible_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	var colour: Dictionary = HdrToneMap.describe(src.get_video_info())
	_pic_mat.set_shader_parameter("yuv_matrix", int(colour.get("matrix", 0)))
	_pic_mat.set_shader_parameter("full_range", bool(colour.get("full_range", false)))
	host.film = _pic_vp.get_texture()


## The viewport's size: HEIGHT tall, as wide as the screen's picture is (at most MAX_WIDTH), even numbers.
func _pixels() -> Vector2i:
	var flat: Vector2 = main.screen.get_flat_size()
	var aspect := flat.x / maxf(flat.y, 0.001)
	var w := mini(MAX_WIDTH, roundi(HEIGHT * aspect))
	return Vector2i(maxi(2, w - w % 2), HEIGHT)


func _show(on: bool) -> void:
	_showing = on
	var film_layer: Node = main.features.get("film_layer")
	if on:
		if _vp == null:
			_build()
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var a := AudioAnalysis.shared
		if a != null:
			a.request(self, true, true)
		main.screen.set_override(_mat)
	else:
		main.screen.set_override(null)
		if host != null:
			host.set_active(false)
			host.film = null
		if _pic_vp != null:
			_pic_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _vp != null:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var a := AudioAnalysis.shared
		if a != null:
			a.request(self, false)
	if film_layer != null:
		film_layer.request_scene(WHO, on)
	# A captured window's sound is not the app's: it is recorded for the analysis while the visualiser shows.
	var window_audio: Node = main.features.get("window_audio")
	if window_audio != null:
		window_audio.request(on and main.player.has_source() and main.player.source.get_kind() == "window")
	changed.emit()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.name = "ScreenVisualiser"
	_vp.size = _pixels()
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var back := ColorRect.new()
	back.color = MusicSource.BACKGROUND
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(back)
	_rect = TextureRect.new()
	_rect.name = "VisualiserArea"
	_rect.size = Vector2(_vp.size)
	_vp.add_child(_rect)
	host = VisualiserHost.new()
	host.name = "VisualiserHost"
	_vp.add_child(host)
	host.setup(_vp, _rect)
	host.refused.connect(_on_refused)
	# --visualiser on a desktop (a check under a software renderer, which no budget fits): no budget, no probe.
	if not bool(main.get("use_xr")) and main.get("_args") is Dictionary and (main.get("_args") as Dictionary).has("visualiser"):
		host.budget_ms = 0.0
	add_child(_vp)
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("tex", _vp.get_texture())


## Too heavy for the budget: the one before stays (the host has put it back). With none before, the picture again:
## asking for another would be refused the same way, every frame.
func _on_refused(_id: String, _why: String) -> void:
	if host.id != "":
		main.features.set_visualiser(host.id)
	else:
		_on = false
		changed.emit()


func _exit_tree() -> void:
	if _showing and is_instance_valid(main) and is_instance_valid(main.screen):
		main.screen.set_override(null)
