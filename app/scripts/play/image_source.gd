extends "res://scripts/video/video_source.gd"

## Still pictures as a video source (ideas #22): JPEG, PNG and WebP through Godot's Image, shown on the same screen,
## meshes and projections as video (the RGB path of video.gdshader, like a captured window). The picture is decoded
## on a worker thread; the screen shows once it is ready (format_changed).
##
## What the file says picks the mode, as a container's metadata does for video (scripts/play/container_mode.gd):
##   photo spheres     XMP GPano:ProjectionType "equirectangular": 360, or 180 when it covers 200 degrees or less. A
##                     partial panorama is padded with black to its place in the full sphere.
##   VR180 photos      the right eye's JPEG in XMP GImage:Data (extended XMP): the two eyes side by side, 180.
##   .jps              side by side, right eye first (cross-eyed layout).
##   .mpo              the first two images of the file (MPF index) side by side, left then right.
##   EXIF orientation  phone photos are turned upright.
## Otherwise the file-name and shape guess applies as for video (a 2:1 picture named ..._360 is a 360).
##
## Sizes: flat pictures are scaled down to FLAT_MAX on their long side (the screen shows ~1500 pixels across, and the
## shader samples without mipmaps), spheres and stereo pairs to SPHERE_MAX wide.
##
## Clock: with slide_seconds > 0 (the slideshow, scripts/play/slideshow.gd) the picture "plays" for that long and then
## ends, so the queue moves on; otherwise it stays (duration 0). A picture that follows another of the same shape
## crossfades from it over crossfade_seconds (a SubViewport mixes the two, then the plain texture takes over).
## Files on a share need MediaBrowser.read_file in the engine (not there yet).

const ImageMeta := preload("res://scripts/play/image_meta.gd")

const EXTENSIONS: Array[String] = ["jpg", "jpeg", "png", "webp", "jps", "mpo"]
const FLAT_MAX := 2560
const SPHERE_MAX := 8192

## Set by the slideshow feature: seconds each picture shows (0: stays), and the crossfade.
static var slide_seconds := 0.0
static var crossfade_seconds := 1.0
## The last picture shown (to crossfade from), and its size.
static var _last_texture: Texture2D
static var _last_size := Vector2i.ZERO

var _host: Node
var _tex: ImageTexture
var _info := {}
var _ready := false
var _playing := true
var _pos := 0.0
var _duration := 0.0
var _task := -1
var _serial := 0
var _fade_vp: SubViewport
var _fade_new: TextureRect
var _fade_t := -1.0


static func is_image_path(p: String) -> bool:
	return p.get_extension().to_lower() in EXTENSIONS


## Drops the remembered last picture (a video opened: nothing to crossfade from, and its memory goes).
static func forget_last() -> void:
	_last_texture = null
	_last_size = Vector2i.ZERO


func get_kind() -> String:
	return "image"


func attach(host: Node) -> void:
	_host = host


func open(p: String) -> Error:
	path = p
	_duration = slide_seconds
	var read_file := p.begins_with("smb://") and ClassDB.class_has_method("MediaBrowser", "read_file")
	if p.begins_with("smb://") and not read_file:
		last_error = "Pictures on a share need MediaBrowser.read_file in the engine"
		return ERR_UNAVAILABLE
	_serial += 1
	var serial := _serial
	_task = WorkerThreadPool.add_task(func() -> void:
		var result := decode(_read(p), p.get_extension())
		_loaded.call_deferred(serial, result), false, "picture " + p.get_file())
	return OK


static func _read(p: String) -> PackedByteArray:
	if p.begins_with("smb://"):
		var browser: Object = ClassDB.instantiate("MediaBrowser")
		var data: Variant = browser.call("read_file", p)
		return data if data is PackedByteArray else PackedByteArray()
	return FileAccess.get_file_as_bytes(p)


## Bytes of a picture file -> {image: Image, info: {}} or {error}. Pure: runs on a worker thread, tested directly.
static func decode(bytes: PackedByteArray, extension: String) -> Dictionary:
	if bytes.is_empty():
		return {"error": "can't read the file"}
	var ext := extension.to_lower()
	var info := {"codec": "image", "fps": 0.0, "bit_depth": 8}
	var img: Image
	if ext == "mpo":
		var parts := ImageMeta.mpo_images(bytes)
		if parts.size() >= 2:
			var left := _load_jpeg(parts[0])
			var right := _load_jpeg(parts[1])
			if left != null and right != null:
				img = _side_by_side(left, right)
				info["stereo_mode"] = "sbs"
		if img == null:
			img = _load_jpeg(bytes)
	elif ext in ["jpg", "jpeg", "jps"]:
		img = _load_jpeg(bytes)
		if img != null and ext != "jps":
			ImageMeta.apply_orientation(img, ImageMeta.exif_orientation(bytes))
	elif ext == "png":
		img = Image.new()
		if img.load_png_from_buffer(bytes) != OK:
			img = null
	elif ext == "webp":
		img = Image.new()
		if img.load_webp_from_buffer(bytes) != OK:
			img = null
	if img == null or img.is_empty():
		return {"error": "can't decode the picture"}
	if ext == "jps":
		info["stereo_mode"] = "sbs"
		info["stereo_inverted"] = true
	var x := ImageMeta.xmp(bytes)
	var pano := ImageMeta.gpano(x)
	if ext in ["jpg", "jpeg"]:
		var right_bytes := ImageMeta.right_eye_jpeg(bytes)
		if not right_bytes.is_empty():
			var right := _load_jpeg(right_bytes)
			if right != null:
				if not pano.is_empty() and str(pano["projection"]) == "equirectangular":
					img = _pad_to_sphere(img, pano)
					right = _pad_to_sphere(right, pano)
					info["projection"] = "equirectangular"
					info["projection_fov"] = _fov(pano)
				img = _side_by_side(img, right)
				info["stereo_mode"] = "sbs"
				pano = {}
	if not pano.is_empty() and str(pano["projection"]) == "equirectangular":
		img = _pad_to_sphere(img, pano)
		info["projection"] = "equirectangular"
		info["projection_fov"] = _fov(pano)
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	var sphere := info.has("projection") or info.has("stereo_mode") or _looks_spherical(img.get_size())
	var limit := SPHERE_MAX if sphere else FLAT_MAX
	var size := img.get_size()
	var scale := minf(1.0, float(limit) / float(maxi(size.x, size.y) if not sphere else size.x))
	if scale < 1.0:
		img.resize(maxi(roundi(size.x * scale), 1), maxi(roundi(size.y * scale), 1), Image.INTERPOLATE_LANCZOS)
	info["width"] = img.get_width()
	info["height"] = img.get_height()
	return {"image": img, "info": info}


static func _load_jpeg(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	return img if img.load_jpg_from_buffer(bytes) == OK else null


static func _side_by_side(left: Image, right: Image) -> Image:
	if right.get_size() != left.get_size():
		right.resize(left.get_width(), left.get_height(), Image.INTERPOLATE_BILINEAR)
	if right.get_format() != left.get_format():
		right.convert(left.get_format())
	var out := Image.create_empty(left.get_width() * 2, left.get_height(), false, left.get_format())
	out.blit_rect(left, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i.ZERO)
	out.blit_rect(right, Rect2i(Vector2i.ZERO, right.get_size()), Vector2i(left.get_width(), 0))
	return out


static func _looks_spherical(size: Vector2i) -> bool:
	return size.y > 0 and absf(float(size.x) / size.y - 2.0) < 0.02 and size.x >= 4000


## Degrees covered: Vector2(horizontal, vertical).
static func _fov(p: Dictionary) -> Vector2:
	var fw := maxi(int(p["full_w"]), 1)
	var fh := maxi(int(p["full_h"]), 1)
	var cw := int(p["crop_w"]) if int(p["crop_w"]) > 0 else fw
	var ch := int(p["crop_h"]) if int(p["crop_h"]) > 0 else fh
	return Vector2(360.0 * cw / fw, 180.0 * ch / fh)


## A cropped panorama on black at its place: the full sphere (360), or 180 x 180 around the crop's centre.
static func _pad_to_sphere(img: Image, p: Dictionary) -> Image:
	var fw := int(p["full_w"])
	var fh := int(p["full_h"])
	if fw <= 0 or fh <= 0:
		return img
	# The crop's pixels are in the file's scale; the image may differ (a smaller preview).
	var cw := int(p["crop_w"]) if int(p["crop_w"]) > 0 else fw
	var k := float(img.get_width()) / cw
	var full := Vector2i(roundi(fw * k), roundi(fh * k))
	var at := Vector2i(roundi(int(p["crop_left"]) * k), roundi(int(p["crop_top"]) * k))
	var fov := _fov(p)
	var canvas := full
	if fov.x <= 200.0:
		canvas.x = full.x / 2
		at.x = canvas.x / 2 - img.get_width() / 2
	if canvas == img.get_size() and at == Vector2i.ZERO:
		return img
	var out := Image.create_empty(canvas.x, canvas.y, false, img.get_format())
	out.fill(Color(0, 0, 0, 1))
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	return out


func _loaded(serial: int, result: Dictionary) -> void:
	if serial != _serial:
		return
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if result.has("error"):
		last_error = "%s: %s" % [path.get_file(), result["error"]]
		push_warning("Picture: " + last_error)
		return
	var img: Image = result["image"]
	_info = result["info"]
	_tex = ImageTexture.create_from_image(img)
	var size := img.get_size()
	if _last_texture != null and crossfade_seconds > 0.0 and _host != null and _last_size.y > 0 \
			and absf(float(_last_size.x) / _last_size.y - float(size.x) / size.y) < 0.02:
		_start_fade(_last_texture, size)
	_last_texture = _tex
	_last_size = size
	_ready = true
	format_changed.emit()


func _start_fade(from: Texture2D, size: Vector2i) -> void:
	_fade_vp = SubViewport.new()
	_fade_vp.size = size
	_fade_vp.disable_3d = true
	_fade_vp.gui_disable_input = true
	_fade_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var old := TextureRect.new()
	old.texture = from
	old.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	old.stretch_mode = TextureRect.STRETCH_SCALE
	old.size = size
	_fade_vp.add_child(old)
	_fade_new = TextureRect.new()
	_fade_new.texture = _tex
	_fade_new.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade_new.stretch_mode = TextureRect.STRETCH_SCALE
	_fade_new.size = size
	_fade_new.modulate.a = 0.0
	_fade_vp.add_child(_fade_new)
	_host.add_child(_fade_vp)
	_fade_t = 0.0


func _end_fade() -> void:
	if _fade_vp != null:
		_fade_vp.queue_free()
	_fade_vp = null
	_fade_new = null
	_fade_t = -1.0


func is_fading() -> bool:
	return _fade_t >= 0.0


func close() -> void:
	_serial += 1
	_end_fade()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_ready = false


func play() -> void:
	_playing = true


func pause() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func can_seek() -> bool:
	return _duration > 0.0


func seek(seconds: float) -> void:
	_pos = clampf(seconds, 0.0, _duration)


func get_position() -> float:
	return _pos


func get_duration() -> float:
	return _duration


## The slideshow changed while this picture shows.
func set_duration(seconds: float) -> void:
	_duration = maxf(seconds, 0.0)
	_pos = minf(_pos, _duration)


func update(delta: float, _master_clock: float) -> void:
	if _fade_t >= 0.0:
		_fade_t += delta
		var a := clampf(_fade_t / maxf(crossfade_seconds, 0.001), 0.0, 1.0)
		_fade_new.modulate.a = a
		if a >= 1.0:
			_end_fade()
			format_changed.emit()
	if _ready and _playing and _duration > 0.0:
		_pos = minf(_pos + delta, _duration)


func has_frame() -> bool:
	return _ready


func is_ended() -> bool:
	return _ready and _duration > 0.0 and _pos >= _duration


func get_rgb_texture() -> Texture2D:
	if _fade_vp != null:
		return _fade_vp.get_texture()
	return _tex


func get_video_info() -> Dictionary:
	return _info


func get_stats() -> Dictionary:
	return {"picture": "%dx%d" % [int(_info.get("width", 0)), int(_info.get("height", 0))], "fading": is_fading()}
