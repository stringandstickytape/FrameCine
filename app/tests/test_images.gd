extends SceneTree

## Tests for still pictures (ideas #22): scripts/play/image_meta.gd and image_source.gd's decode on files built here
## (EXIF orientation, photo spheres, JPS, MPO, VR180 photos, XMP in PNG and WebP), then the real main scene showing
## pictures from a folder with the slideshow and crossfade. Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_images.gd

const ImageMeta := preload("res://scripts/play/image_meta.gd")
const ImageSource := preload("res://scripts/play/image_source.gd")
const ContainerMode := preload("res://scripts/play/container_mode.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const Factory := preload("res://scripts/video/video_source_factory.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_decode_checks()
	await _scene_checks()
	print("test_images: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _jpeg(w: int, h: int, colour: Color) -> PackedByteArray:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	img.fill(colour)
	return img.save_jpg_to_buffer(0.9)


## A JPEG with one more marker segment right after SOI.
func _with_segment(jpeg: PackedByteArray, marker: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([0xFF, 0xD8, 0xFF, marker, (payload.size() + 2) >> 8, (payload.size() + 2) & 0xFF])
	out.append_array(payload)
	out.append_array(jpeg.slice(2))
	return out


func _exif_orientation(o: int) -> PackedByteArray:
	# "Exif\0\0", little-endian TIFF, IFD0 at 8 with one entry: 0x0112 SHORT 1 = o.
	var p := "Exif".to_ascii_buffer()
	p.append_array([0, 0, 0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, o, 0, 0, 0,
			0, 0, 0, 0])
	return p


func _xmp_segment(xml: String) -> PackedByteArray:
	var p := ImageMeta.XMP_ID.to_ascii_buffer()
	p.append(0)
	p.append_array(xml.to_utf8_buffer())
	return p


func _gpano(full_w: int, full_h: int, crop_w: int, crop_h: int, left: int, top: int, extra := "") -> String:
	return ('<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF><rdf:Description GPano:ProjectionType="equirectangular" ' +
			'GPano:FullPanoWidthPixels="%d" GPano:FullPanoHeightPixels="%d" GPano:CroppedAreaImageWidthPixels="%d" ' +
			'GPano:CroppedAreaImageHeightPixels="%d" GPano:CroppedAreaLeftPixels="%d" GPano:CroppedAreaTopPixels="%d" %s/>' +
			'</rdf:RDF></x:xmpmeta>') % [full_w, full_h, crop_w, crop_h, left, top, extra]


func _mode(r: Dictionary, name: String) -> VideoMode:
	var info: Dictionary = r["info"]
	return ContainerMode.from_info(info, name, int(info["width"]), int(info["height"]))["mode"]


func _decode_checks() -> void:
	# PNG: plain flat picture.
	var png := Image.create_empty(300, 200, false, Image.FORMAT_RGBA8)
	png.fill(Color(0.2, 0.4, 0.6))
	var r := ImageSource.decode(png.save_png_to_buffer(), "png")
	_check("png decodes (%s)" % r.get("info", r), r.has("image") and r["info"]["width"] == 300 and r["info"]["height"] == 200
			and not r["info"].has("projection"))
	_check("broken file: an error", ImageSource.decode(PackedByteArray([1, 2, 3]), "jpg").has("error"))
	# EXIF orientation 6 (turn 90 degrees clockwise): 40x20 stored -> 20x40 shown.
	var j := _with_segment(_jpeg(40, 20, Color.RED), 0xE1, _exif_orientation(6))
	_check("EXIF orientation read", ImageMeta.exif_orientation(j) == 6)
	r = ImageSource.decode(j, "jpg")
	_check("EXIF 6: upright (%dx%d)" % [r["info"]["width"], r["info"]["height"]], r["info"]["width"] == 20
			and r["info"]["height"] == 40)
	_check("no EXIF: orientation 1", ImageMeta.exif_orientation(_jpeg(8, 8, Color.RED)) == 1)
	# Photo sphere, 180 degrees wide and 90 high, cropped from a 2000x1000 panorama: padded to 1000x1000.
	j = _with_segment(_jpeg(1000, 500, Color(0.9, 0.9, 0.2)), 0xE1, _xmp_segment(_gpano(2000, 1000, 1000, 500, 500, 250)))
	r = ImageSource.decode(j, "jpg")
	var img: Image = r["image"]
	_check("partial sphere padded to 180 x 180 (%dx%d, fov %s)" % [img.get_width(), img.get_height(), r["info"].get("projection_fov")],
			img.get_size() == Vector2i(1000, 1000) and r["info"]["projection"] == "equirectangular"
			and r["info"]["projection_fov"] == Vector2(180, 90))
	_check("black above, the picture in the middle", img.get_pixel(500, 100).r < 0.05 and img.get_pixel(500, 500).r > 0.8)
	var m := _mode(r, "pano.jpg")
	_check("mode: 180 (%s)" % (m.describe() if m != null else "none"), m != null and m.projection == VideoMode.Proj.EQUIRECT_180)
	# Full-width 360 with the poles missing: padded to the whole sphere.
	j = _with_segment(_jpeg(2000, 800, Color.WHITE), 0xE1, _xmp_segment(_gpano(2000, 1000, 2000, 800, 0, 100)))
	r = ImageSource.decode(j, "jpg")
	m = _mode(r, "pano.jpg")
	_check("360 padded to 2000x1000, mode 360", (r["image"] as Image).get_size() == Vector2i(2000, 1000) and m != null
			and m.projection == VideoMode.Proj.EQUIRECT_360)
	# JPS: side by side, right eye first.
	r = ImageSource.decode(_jpeg(800, 300, Color.GREEN), "jps")
	m = _mode(r, "stereo.jps")
	_check("jps: flat side by side, eyes swapped", m != null and m.layout == VideoMode.Layout.SBS and m.swap
			and m.projection == VideoMode.Proj.FLAT)
	# MPO: two JPEGs, the first with an MPF index in APP2.
	var left := _jpeg(64, 48, Color.RED)
	var right := _jpeg(64, 48, Color.BLUE)
	var mpf_len := 4 + 8 + 2 + 12 + 4 + 32
	var first_size := left.size() + 4 + mpf_len
	var t := 2 + 4 + 4  # the MPF TIFF header's place in the file
	var mpf := "MPF".to_ascii_buffer()
	mpf.append(0)
	mpf.append_array([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0, 1, 0, 0x02, 0xB0, 7, 0, 32, 0, 0, 0, 26, 0, 0, 0, 0, 0, 0, 0])
	mpf.append_array(_u32le(0x20030000) + _u32le(first_size) + _u32le(0) + PackedByteArray([0, 0, 0, 0]))
	mpf.append_array(_u32le(0x00020002) + _u32le(right.size()) + _u32le(first_size - t) + PackedByteArray([0, 0, 0, 0]))
	_check("mpf segment size", mpf.size() == mpf_len)
	var mpo := _with_segment(left, 0xE2, mpf)
	mpo.append_array(right)
	_check("mpo: two images found", ImageMeta.mpo_images(mpo).size() == 2)
	r = ImageSource.decode(mpo, "mpo")
	img = r["image"]
	_check("mpo: left | right (%dx%d)" % [img.get_width(), img.get_height()], img.get_size() == Vector2i(128, 48)
			and img.get_pixel(10, 20).r > 0.8 and img.get_pixel(100, 20).b > 0.8 and r["info"]["stereo_mode"] == "sbs")
	# VR180 photo: left eye in the file, right eye in extended XMP (GImage:Data), both 180 x 180.
	var eye_r := _jpeg(500, 500, Color.BLUE)
	var ext := _ext_xmp('<x:xmpmeta><rdf:Description GImage:Data="%s"/></x:xmpmeta>' % Marshalls.raw_to_base64(eye_r))
	j = _with_segment(_with_segment(_jpeg(500, 500, Color.RED), 0xE1, ext), 0xE1,
			_xmp_segment(_gpano(1000, 500, 500, 500, 250, 0, 'xmpNote:HasExtendedXMP="0123"')))
	_check("extended XMP read", ImageMeta.right_eye_jpeg(j).size() == eye_r.size())
	r = ImageSource.decode(j, "jpg")
	img = r["image"]
	m = _mode(r, "IMG_0001.vr.jpg")
	_check("VR180 photo: two eyes side by side, 180 SBS (%dx%d, %s)" % [img.get_width(), img.get_height(),
			m.describe() if m != null else "none"], img.get_size() == Vector2i(1000, 500) and img.get_pixel(100, 250).r > 0.8
			and img.get_pixel(900, 250).b > 0.8 and m != null and m.projection == VideoMode.Proj.EQUIRECT_180
			and m.layout == VideoMode.Layout.SBS)
	# XMP in PNG (iTXt) and WebP (XMP chunk): the reader only.
	var x := _gpano(4000, 2000, 4000, 2000, 0, 0)
	var itxt := "XML:com.adobe.xmp".to_ascii_buffer()
	itxt.append_array([0, 0, 0, 0, 0])
	itxt.append_array(x.to_utf8_buffer())
	var fake_png := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + _u32be(itxt.size()) \
			+ "iTXt".to_ascii_buffer() + itxt + PackedByteArray([0, 0, 0, 0])
	_check("png XMP", ImageMeta.gpano(ImageMeta.xmp(fake_png)).get("projection", "") == "equirectangular")
	var chunk := x.to_utf8_buffer()
	var fake_webp := "RIFF".to_ascii_buffer() + _u32le(0) + "WEBP".to_ascii_buffer() + "XMP ".to_ascii_buffer() \
			+ _u32le(chunk.size()) + chunk
	_check("webp XMP", ImageMeta.gpano(ImageMeta.xmp(fake_webp)).get("full_w", 0) == 4000)
	# Big flat pictures are scaled to FLAT_MAX; a plain 2:1 picture of 4000+ is treated as a sphere (kept larger).
	r = ImageSource.decode(Image.create_empty(5000, 1000, false, Image.FORMAT_RGB8).save_png_to_buffer(), "png")
	_check("flat scaled to %d (%d)" % [ImageSource.FLAT_MAX, r["info"]["width"]], r["info"]["width"] == ImageSource.FLAT_MAX)
	r = ImageSource.decode(Image.create_empty(6000, 3000, false, Image.FORMAT_RGB8).save_png_to_buffer(), "png")
	_check("2:1 at 6000 kept (%d)" % r["info"]["width"], r["info"]["width"] == 6000)
	_check("factory: pictures are media files", Factory.is_media_file("a.JPG") and Factory.is_image_file("b.webp")
			and not Factory.is_image_file("c.mkv") and Factory.is_media_file("c.mkv"))


func _ext_xmp(xml: String) -> PackedByteArray:
	var data := xml.to_utf8_buffer()
	var p := ImageMeta.EXT_XMP_ID.to_ascii_buffer()
	p.append(0)
	p.append_array("0123456789ABCDEF0123456789ABCDEF".to_ascii_buffer())
	p.append_array(_u32be(data.size()))
	p.append_array(_u32be(0))
	p.append_array(data)
	return p


func _u32le(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])


func _u32be(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


func _scene_checks() -> void:
	var dir := ProjectSettings.globalize_path("user://test_pictures")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var colours := [Color.RED, Color.GREEN, Color.BLUE]
	for i in 3:
		var img := Image.create_empty(320, 180, false, Image.FORMAT_RGB8)
		img.fill(colours[i])
		img.save_png(dir.path_join("pic_%d.png" % i))
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settings.read_only = true
	root.add_child(main)
	await _frames(5)
	var show: Node = main.features.slideshow
	show.set_enabled(false)
	show.set_crossfade(0.5)
	main.open_path(dir.path_join("pic_0.png"))
	await _wait(func() -> bool: return main.player.source != null and main.player.source.has_frame(), 5.0)
	var src: Object = main.player.source
	_check("a picture opens as the image source", src.get_kind() == "image" and main.playlist.size() == 3)
	await _frames(2)
	var mat: ShaderMaterial = main.screen.material
	_check("the screen shows its texture (RGB path)", main.screen.is_shown() and mat.get_shader_parameter("rgb_source")
			and mat.get_shader_parameter("rgb_tex") == src.get_rgb_texture())
	_check("flat 16:9", main.mode.projection == VideoMode.Proj.FLAT and main.mode.layout == VideoMode.Layout.MONO)
	await _sleep(0.5)
	_check("slideshow off: the picture stays", main.current_path.ends_with("pic_0.png") and not src.is_ended())
	show.set_seconds(2.0)
	show.set_enabled(true)
	_check("slideshow on: this picture now lasts 2 s", is_equal_approx(src.get_duration(), 2.0))
	await _wait(func() -> bool: return main.current_path.ends_with("pic_1.png"), 5.0)
	_check("the next picture opens after 2 s", main.current_path.ends_with("pic_1.png"))
	await _wait(func() -> bool: return main.player.source.has_frame(), 5.0)
	var src2: Object = main.player.source
	_check("it crossfades from the last one", src2.is_fading())
	await _frames(2)
	_check("the screen shows the crossfade's mix", mat.get_shader_parameter("rgb_tex") == src2.get_rgb_texture()
			and src2.get_rgb_texture() is ViewportTexture)
	await _wait(func() -> bool: return not src2.is_fading(), 3.0)
	await _frames(2)
	_check("after the crossfade the plain picture shows", not src2.is_fading()
			and mat.get_shader_parameter("rgb_tex") == src2.get_rgb_texture() and src2.get_rgb_texture() is ImageTexture)
	main.player.pause()
	await _sleep(2.5)
	_check("pause holds the picture", main.current_path.ends_with("pic_1.png"))
	show.set_enabled(false)
	main.open_path("stub://flat_mono")
	await _frames(3)
	_check("a video after pictures: nothing kept to fade from", ImageSource._last_texture == null)
	main.queue_free()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


func _wait(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
	else:
		print("PASS " + what)
