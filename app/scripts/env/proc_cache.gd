extends RefCounted

## The pictures a room draws for itself, kept between runs (docs/environments/checks.md, "Build time").
##
## A room's own maps and pictures (pressed tin, a mosaic, the bills on a wall, coloured glass, Earth's map) are drawn
## in code, a pixel at a time, the first time a room that uses them is built in a run; each generator keeps them in
## memory after that. Measured 2026-11-09 on the desktop: the first build of the Shopfront takes 1.3 s and the second
## 0.04 s, the Nave 1.1 s and 0.2 s, the Screening room 1.0 s and 0.06 s; the headset is several times slower, and
## the main thread is held all that time. So the drawing is nearly all of the wait for most rooms, and it gives
## the same picture every time. This keeps the pictures on disk under the generators' own memory: a room is slow
## once after an update, not once in every run.
##
##   ProcCache.images(key, make) -> Array[Image]    the pictures for this key: from disk, else make() (an Array of
##                                                  Image) and kept. One key holds whatever one drawing makes: a
##                                                  material's colour, normal and roughness maps come out of one pass
##   ProcCache.image(key, make) -> Image            one picture (make() -> Image)
##   ProcCache.enabled                              false: always drawn, nothing read or written (the test compares)
##   ProcCache.hits, misses, made_ms                this run's count (the test, the dev link's perf)
##   ProcCache.verify, mismatches                   the test's: what is read is also drawn, and the two compared
##
## The key says which picture: "<the generator's file>:<its own memory's name>:<that memory's key>". A generator that
## already keeps its pictures in memory by a key has decided what tells one picture from another; the same key
## serves here, so adding the disk under it takes no new judgment and can leave nothing out.
##
## The stamp says which code drew it: one MD5 over every script under res://scripts/env. A change to any of them
## empties the whole cache. Coarse on purpose: a generator calls helpers in other files, and a finer stamp would have
## to know which. An update redraws every room once.
##
## Main thread only (as the generators are).

const DIR := "user://env_cache"
const SCRIPTS := "res://scripts/env"
const MAGIC := "ROOMPIC1"

static var enabled := true
static var hits := 0
static var misses := 0
static var made_ms := 0.0
## The test's: every picture read from disk is also drawn, and the two compared (`mismatches` counts those that
## differ). A key that leaves out something its picture depends on shows up here and nowhere else.
static var verify := false
static var mismatches := 0
static var _stamp := ""


static func image(key: String, make: Callable) -> Image:
	return images(key, func() -> Array: return [make.call()])[0]


static func images(key: String, make: Callable) -> Array[Image]:
	var out: Array[Image] = []
	if enabled:
		out = _read(key)
		if not out.is_empty():
			hits += 1
			if verify and not _same(out, make.call()):
				mismatches += 1
				push_error("ProcCache: the pictures kept for \"%s\" are not what is drawn now" % key)
			return out
	var t0 := Time.get_ticks_usec()
	for img: Variant in make.call():
		out.append(img as Image)
	made_ms += (Time.get_ticks_usec() - t0) / 1000.0
	misses += 1
	if enabled:
		_write(key, out)
	return out


## Whether two lists of pictures are the same, pixel for pixel.
static func _same(a: Array, b: Variant) -> bool:
	if not (b is Array) or a.size() != (b as Array).size():
		return false
	for i in a.size():
		var x: Image = a[i]
		var y: Image = b[i]
		if y == null or x.get_size() != y.get_size() or x.get_format() != y.get_format() \
				or x.has_mipmaps() != y.has_mipmaps() or x.get_data() != y.get_data():
			return false
	return true


## This run's stamp: the scripts' MD5s in one (the app's version where the scripts cannot be listed).
static func stamp() -> String:
	if _stamp != "":
		return _stamp
	var files: Array[String] = []
	_scripts(SCRIPTS, files)
	files.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(str(ProjectSettings.get_setting("application/config/version", "")).to_utf8_buffer())
	for f in files:
		ctx.update((f + FileAccess.get_md5(f)).to_utf8_buffer())
	_stamp = ctx.finish().hex_encode()
	_forget_other_stamps()
	return _stamp


static func _scripts(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))


## The folders of older stamps go: their pictures can never be asked for again.
static func _forget_other_stamps() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for d in DirAccess.get_directories_at(DIR):
		if d == _stamp:
			continue
		var old := DIR.path_join(d)
		for f in DirAccess.get_files_at(old):
			DirAccess.remove_absolute(old.path_join(f))
		DirAccess.remove_absolute(old)


static func path_of(key: String) -> String:
	return DIR.path_join(stamp()).path_join(key.sha256_text().left(32) + ".pic")


## The pictures on disk for a key ([] when there are none, or the file is not whole: it is drawn again).
static func _read(key: String) -> Array[Image]:
	var out: Array[Image] = []
	var none: Array[Image] = []
	var f := FileAccess.open(path_of(key), FileAccess.READ)
	if f == null:
		return none
	if f.get_pascal_string() != MAGIC or f.get_pascal_string() != key:
		return none
	var count := f.get_32()
	for i in count:
		var w := f.get_32()
		var h := f.get_32()
		var format := f.get_32()
		var mipmaps := f.get_8() != 0
		var size := f.get_32()
		var packed := f.get_buffer(f.get_32())
		var data := packed.decompress(size, FileAccess.COMPRESSION_ZSTD)
		if w <= 0 or h <= 0 or data.size() != size:
			return none
		var img := Image.create_from_data(w, h, mipmaps, format as Image.Format, data)
		if img == null or img.is_empty():
			return none
		out.append(img)
	# The last word on the file says it was written to its end.
	if f.get_pascal_string() != MAGIC:
		return none
	return out


## Written beside its place and moved into it, so a file is whole or not there.
static func _write(key: String, pictures: Array[Image]) -> void:
	var path := path_of(key)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_pascal_string(MAGIC)
	f.store_pascal_string(key)
	f.store_32(pictures.size())
	for img in pictures:
		var data := img.get_data()
		var packed := data.compress(FileAccess.COMPRESSION_ZSTD)
		f.store_32(img.get_width())
		f.store_32(img.get_height())
		f.store_32(img.get_format())
		f.store_8(1 if img.has_mipmaps() else 0)
		f.store_32(data.size())
		f.store_32(packed.size())
		f.store_buffer(packed)
	f.store_pascal_string(MAGIC)
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)
