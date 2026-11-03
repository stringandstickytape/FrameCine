extends Node

## Pictures for the Library place, so a wall of posters costs the film nothing. One worker task at a time, at low
## priority, decodes a picture, crops and scales it to the size it is shown at and keeps that as a small JPEG in
## user://library_cache/; a later look needs only that small file. Finished pictures reach the GPU one per frame, and
## LIMIT of them stay in memory.
##
##   images.request(path, size, func(tex: Texture2D) -> void: ...)   may answer at once, from memory
##   images.forget_waiting()   the view changed: pictures not begun yet are dropped

const CACHE_DIR := "user://library_cache"
## A bigger file isn't decoded.
const MAX_BYTES := 33554432
const JPEG_QUALITY := 0.85
## Textures kept in memory: a screen of posters, and the screens around it.
const LIMIT := 120

## Tests: how many pictures were decoded from the source and read from the cache.
var decoded := 0
var cached := 0

var _mutex := Mutex.new()
## Waiting: [{key, path, size}].
var _queue: Array[Dictionary] = []
## Ready for the main thread: [{key, image}].
var _done: Array[Dictionary] = []
var _task := -1
var _stop := false
## key -> callbacks waiting for it.
var _waiting := {}
## key -> texture, the oldest first.
var _textures := {}


func request(path: String, size: Vector2i, on_ready: Callable) -> void:
	if path == "" or size.x <= 0 or size.y <= 0:
		return
	var key := "%s|%dx%d" % [path, size.x, size.y]
	if _textures.has(key):
		var tex: Texture2D = _textures[key]
		_textures.erase(key)
		_textures[key] = tex
		on_ready.call(tex)
		return
	if _waiting.has(key):
		(_waiting[key] as Array).append(on_ready)
		return
	_waiting[key] = [on_ready]
	_mutex.lock()
	_queue.append({"key": key, "path": path, "size": size})
	_mutex.unlock()
	_start()


func forget_waiting() -> void:
	_mutex.lock()
	for job: Dictionary in _queue:
		_waiting.erase(job["key"])
	_queue.clear()
	_mutex.unlock()


func _start() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
	_task = WorkerThreadPool.add_task(_work, false, "library pictures")


func _work() -> void:
	while true:
		_mutex.lock()
		var job: Dictionary = _queue.pop_front() if not _queue.is_empty() and not _stop else {}
		_mutex.unlock()
		if job.is_empty():
			return
		var img := _load(str(job["path"]), job["size"])
		_mutex.lock()
		_done.append({"key": job["key"], "image": img})
		_mutex.unlock()


## On the worker: the picture at `size`, or null.
func _load(path: String, size: Vector2i) -> Image:
	var stamp := FileAccess.get_modified_time(path)
	var file := "%s/%s.jpg" % [CACHE_DIR, ("%s|%d|%dx%d" % [path, stamp, size.x, size.y]).md5_text()]
	if FileAccess.file_exists(file):
		var kept := Image.new()
		if kept.load_jpg_from_buffer(FileAccess.get_file_as_bytes(file)) == OK:
			_mutex.lock()
			cached += 1
			_mutex.unlock()
			return kept
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return null
	var bytes := f.get_buffer(f.get_length())
	f = null
	var img := _decode(bytes, path.get_extension().to_lower())
	if img == null:
		return null
	if img.is_compressed() or img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var cover := maxf(float(size.x) / img.get_width(), float(size.y) / img.get_height())
	var crop := Vector2i(mini(roundi(size.x / cover), img.get_width()), mini(roundi(size.y / cover), img.get_height()))
	img = img.get_region(Rect2i((Vector2i(img.get_width(), img.get_height()) - crop) / 2, crop))
	img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var out := FileAccess.open(file, FileAccess.WRITE)
	if out != null:
		out.store_buffer(img.save_jpg_to_buffer(JPEG_QUALITY))
	_mutex.lock()
	decoded += 1
	_mutex.unlock()
	return img


## Tries the extension's format, then the others: a picture's name doesn't always tell what it is. null if none reads.
static func _decode(bytes: PackedByteArray, extension: String) -> Image:
	var img := Image.new()
	var order: Array[String] = ["jpg", "png", "webp"]
	if extension == "png" or extension == "webp":
		order.erase(extension)
		order.push_front(extension)
	# A wrong guess prints an engine error, so look at the first bytes rather than try each one.
	if bytes.size() >= 12:
		if bytes[0] == 0xFF and bytes[1] == 0xD8:
			order = ["jpg"]
		elif bytes[0] == 0x89 and bytes[1] == 0x50:
			order = ["png"]
		elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
			order = ["webp"]
		else:
			return null
	for kind in order:
		var err: int = FAILED
		match kind:
			"jpg":
				err = img.load_jpg_from_buffer(bytes)
			"png":
				err = img.load_png_from_buffer(bytes)
			"webp":
				err = img.load_webp_from_buffer(bytes)
		if err == OK and not img.is_empty():
			return img
	return null


func _process(_delta: float) -> void:
	_mutex.lock()
	var job: Dictionary = _done.pop_front() if not _done.is_empty() else {}
	_mutex.unlock()
	if job.is_empty():
		return
	var key := str(job["key"])
	var callbacks: Array = _waiting.get(key, [])
	_waiting.erase(key)
	var img: Image = job["image"]
	if img == null or callbacks.is_empty():
		return
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	while _textures.size() > LIMIT:
		_textures.erase(_textures.keys()[0])
	for c: Callable in callbacks:
		if c.is_valid():
			c.call(tex)


func _exit_tree() -> void:
	_mutex.lock()
	_stop = true
	_queue.clear()
	_mutex.unlock()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
