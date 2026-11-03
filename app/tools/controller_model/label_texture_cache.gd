extends Node

## Renders each controller label text once into a small texture (light text, thin dark outline, transparent
## background), for baking the legends into our own controller model (export_legends.gd). The app itself prints with
## scripts/xr/label_font.gd. One SubViewport draws one text per frame on request; the result is copied into an
## ImageTexture and cached by text. Without a renderer (headless) no texture is made.

## Font size the text is drawn at; the bake scales it to the printed size.
const FONT_SIZE := 48
const OUTLINE := 8
## Transparent border: keeps neighbours from bleeding in at the edges through the mipmaps.
const PAD := 12

static var _cache := {}

var _viewport: SubViewport
var _label: Label
## [text, Callable(texture)] waiting to be drawn.
var _queue: Array = []
var _busy := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
	_label.add_theme_constant_override("outline_size", OUTLINE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(PAD, PAD)
	_viewport.add_child(_label)


## Calls `done(texture)` with the text's texture: at once when cached, else after it is drawn (a frame or two).
func request(text: String, done: Callable) -> void:
	if _cache.has(text):
		done.call(_cache[text])
		return
	_queue.append([text, done])
	if not _busy:
		_draw_next()


static func cached(text: String) -> Texture2D:
	return _cache.get(text)


func _draw_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var item: Array = _queue.pop_front()
	var text: String = item[0]
	if _cache.has(text):
		(item[1] as Callable).call(_cache[text])
		_draw_next.call_deferred()
		return
	_label.text = text
	var size := ThemeDB.fallback_font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, FONT_SIZE)
	_label.size = size
	_viewport.size = Vector2i(ceili(size.x) + PAD * 2, ceili(size.y) + PAD * 2)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image() if DisplayServer.get_name() != "headless" else null
	if image != null and not image.is_empty():
		image.generate_mipmaps()
		var texture := ImageTexture.create_from_image(image)
		_cache[text] = texture
		# Callers waiting for the same text.
		(item[1] as Callable).call(texture)
		for i in range(_queue.size() - 1, -1, -1):
			if _queue[i][0] == text:
				(_queue[i][1] as Callable).call(texture)
				_queue.remove_at(i)
	_draw_next()
