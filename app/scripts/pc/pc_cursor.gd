extends Sprite3D

## The mouse cursor in the headset (docs/pc-windows.md, "The cursor"): a small arrow, or the shape the PC reports for
## the window under it (`cursor`), drawn over everything (no depth test) at the same size to the eye wherever it is
## (SIZE_DEG), so it is always readable. Over a pane it is on the private layer with the pane (where it points is part
## of the window); over nothing it is on the ordinary layer. The pictures are drawn here once, white with a dark edge.

const VideoScreen := preload("res://scripts/video_screen.gd")

const SIZE_DEG := 1.6
const PIXELS := 32

static var _textures := {}

var shape := "arrow"


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	shaded = false
	double_sided = true
	render_priority = 10
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	centered = false
	set_shape("arrow")
	visible = false


func set_shape(s: String) -> void:
	shape = s if s in ["arrow", "ibeam", "hand", "wait", "cross", "size_we", "size_ns", "size_nwse", "size_nesw",
			"move", "no"] else "arrow"
	texture = texture_for(shape)
	# The arrow's tip is the point; the others are centred on it.
	offset = Vector2.ZERO if shape == "arrow" or shape == "hand" else Vector2(-PIXELS / 2.0, -PIXELS / 2.0)
	if shape == "hand":
		offset = Vector2(-PIXELS * 0.35, -PIXELS * 0.05)
	# Sprite3D's y goes up: the picture hangs below the point.
	offset.y = -PIXELS - offset.y if shape == "arrow" or shape == "hand" else offset.y


## At `point`, seen from `eye`: sized for SIZE_DEG; private while over a pane.
func place(point: Vector3, eye: Vector3, over_pane: bool) -> void:
	global_position = point
	var d := maxf(eye.distance_to(point), 0.1)
	pixel_size = 2.0 * d * tan(deg_to_rad(SIZE_DEG) / 2.0) / PIXELS
	set_layer_mask_value(VideoScreen.PRIVATE_LAYER, over_pane)
	set_layer_mask_value(1, not over_pane)
	visible = true


static func texture_for(s: String) -> Texture2D:
	if _textures.has(s):
		return _textures[s]
	var img := Image.create_empty(PIXELS, PIXELS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var white := Color(1, 1, 1, 1)
	var edge := Color(0.05, 0.05, 0.05, 1)
	var c := PIXELS / 2
	match s:
		"arrow":
			_polygon(img, PackedVector2Array([Vector2(1, 1), Vector2(1, 23), Vector2(7, 18), Vector2(11, 27),
					Vector2(15, 25), Vector2(11, 17), Vector2(19, 17)]), white, edge)
		"hand":
			_disc(img, Vector2(11, 14), 7.0, white, edge)
			_rect(img, Rect2i(9, 1, 5, 12), white, edge)
		"ibeam":
			_rect(img, Rect2i(c - 1, 5, 3, 22), white, edge)
			_rect(img, Rect2i(c - 5, 4, 11, 3), white, edge)
			_rect(img, Rect2i(c - 5, 25, 11, 3), white, edge)
		"wait":
			_ring(img, Vector2(c, c), 10.0, 4.0, white, edge)
		"cross":
			_rect(img, Rect2i(c - 1, 3, 3, 26), white, edge)
			_rect(img, Rect2i(3, c - 1, 26, 3), white, edge)
		"move":
			_rect(img, Rect2i(c - 2, 2, 5, 28), white, edge)
			_rect(img, Rect2i(2, c - 2, 28, 5), white, edge)
		"size_we":
			_rect(img, Rect2i(3, c - 2, 26, 5), white, edge)
			_rect(img, Rect2i(3, c - 6, 4, 13), white, edge)
			_rect(img, Rect2i(25, c - 6, 4, 13), white, edge)
		"size_ns":
			_rect(img, Rect2i(c - 2, 3, 5, 26), white, edge)
			_rect(img, Rect2i(c - 6, 3, 13, 4), white, edge)
			_rect(img, Rect2i(c - 6, 25, 13, 4), white, edge)
		"size_nwse", "size_nesw":
			for i in range(4, 28):
				var x := i if s == "size_nwse" else PIXELS - 1 - i
				_rect(img, Rect2i(x - 2, i - 2, 5, 5), white, edge)
		"no":
			_ring(img, Vector2(c, c), 12.0, 3.0, white, edge)
			for i in range(8, 24):
				_rect(img, Rect2i(i - 1, i - 1, 3, 3), white, edge)
	var t := ImageTexture.create_from_image(img)
	_textures[s] = t
	return t


static func _put(img: Image, x: int, y: int, col: Color, edge: Color) -> void:
	if x < 1 or y < 1 or x >= PIXELS - 1 or y >= PIXELS - 1:
		return
	img.set_pixel(x, y, col)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if img.get_pixel(x + d.x, y + d.y).a < 0.5:
			img.set_pixel(x + d.x, y + d.y, edge)


static func _rect(img: Image, r: Rect2i, col: Color, edge: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put(img, x, y, col, edge)


static func _disc(img: Image, centre: Vector2, radius: float, col: Color, edge: Color) -> void:
	for y in PIXELS:
		for x in PIXELS:
			if Vector2(x, y).distance_to(centre) <= radius:
				_put(img, x, y, col, edge)


static func _ring(img: Image, centre: Vector2, radius: float, thick: float, col: Color, edge: Color) -> void:
	for y in PIXELS:
		for x in PIXELS:
			var d := Vector2(x, y).distance_to(centre)
			if d <= radius and d >= radius - thick:
				_put(img, x, y, col, edge)


static func _polygon(img: Image, pts: PackedVector2Array, col: Color, edge: Color) -> void:
	for y in PIXELS:
		for x in PIXELS:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				_put(img, x, y, col, edge)
