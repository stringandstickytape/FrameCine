extends RefCounted

## A stable key for remembering things per file (resume position, 3D depth, subtitle delay, ...): a hash of the path
## and, for local files, the size, so a file replaced under the same name starts fresh. Network (smb://) files use the
## path alone: their size isn't known without opening them. Test patterns use their stub:// path.
## Preload to use (no class_name).

static var _sizes := {}


## "f" + 16 hex digits.
static func key(path: String) -> String:
	return key_for_size(path, size_of(path))


## The same with the size already known. Keeps to its arguments, so a worker thread can use it.
static func key_for_size(path: String, size: int) -> String:
	return "f" + (path + "|" + str(size)).md5_text().substr(0, 16)


## The file's size in bytes for local files (cached per path), -1 for network paths, test patterns and missing files.
static func size_of(path: String) -> int:
	if path == "" or path.contains("://"):
		return -1
	if _sizes.has(path):
		return _sizes[path]
	var size := -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		size = f.get_length()
	_sizes[path] = size
	return size


## Forget cached sizes (a file may have changed).
static func clear_cache() -> void:
	_sizes.clear()
