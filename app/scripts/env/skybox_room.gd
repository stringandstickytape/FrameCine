extends "res://environments/vr_environment.gd"

## Any equirectangular photo as a room (ideas #18): a sphere around the viewer showing the photo, centred on the eyes so
## the photo's horizon sits at eye level, the screen floating in front. The photo decodes on a worker thread
## (image_source.gd's decode: EXIF, photo-sphere padding, the size limit); the sphere is black until it is ready.
## A side-by-side or top-bottom stereo panorama uses its left (top) eye. A picture narrower than 2:1 is centred
## ahead with black around it (a 180 photo covers the front half).
##
##   photo_path     the file (user://skyboxes/<name>.jpg for the ones in the list)
##   is_ready()     the photo is on the sphere
## Brightness follows the room's level (ambient_level 1.0, so the room light setting is the photo's brightness).

const ImageSource := preload("res://scripts/play/image_source.gd")
const SKY_SHADER := preload("res://shaders/sky_photo.gdshader")
const RADIUS := 60.0

var photo_path := ""
var _material: ShaderMaterial
var _task := -1
var _ready_photo := false


func _init(p_path := "") -> void:
	photo_path = p_path
	display_name = p_path.get_file().get_basename()
	ambient_level = 1.0
	screen_glow = 0.0
	default_screen_width = 3.2
	var anchor := Marker3D.new()
	anchor.name = "ScreenAnchor"
	anchor.position = Vector3(0, NOMINAL_EYE_HEIGHT, -3.4)
	add_child(anchor)
	screen_anchor = anchor


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_material = ShaderMaterial.new()
	_material.shader = SKY_SHADER
	var black := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	_material.set_shader_parameter("photo", ImageTexture.create_from_image(black))
	var mi := MeshInstance3D.new()
	mi.name = "Sky"
	mi.mesh = sphere
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, NOMINAL_EYE_HEIGHT, 0)
	add_child(mi)
	if photo_path != "":
		var p := photo_path
		_task = WorkerThreadPool.add_task(func() -> void:
			_loaded.call_deferred(prepare(FileAccess.get_file_as_bytes(p), p.get_extension())), false, "skybox")


func is_ready() -> bool:
	return _ready_photo


## Bytes -> an equirectangular Image for the sphere (one eye, 2:1), or null.
static func prepare(bytes: PackedByteArray, extension: String) -> Image:
	var r := ImageSource.decode(bytes, extension)
	if not r.has("image"):
		return null
	var img: Image = r["image"]
	var info: Dictionary = r["info"]
	var w := img.get_width()
	var h := img.get_height()
	if str(info.get("stereo_mode", "")) == "sbs":
		img = img.get_region(Rect2i(0, 0, w / 2, h))
	elif str(info.get("stereo_mode", "")) == "tb":
		img = img.get_region(Rect2i(0, 0, w, h / 2))
	w = img.get_width()
	h = img.get_height()
	if w < h * 2:
		var out := Image.create_empty(h * 2, h, false, img.get_format())
		out.fill(Color(0, 0, 0, 1))
		out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(h - w / 2, 0))
		img = out
	return img


func _loaded(img: Image) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if img == null or not is_inside_tree():
		if img == null:
			push_warning("Skybox: can't read %s" % photo_path)
		return
	_material.set_shader_parameter("photo", ImageTexture.create_from_image(img))
	_ready_photo = true


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
