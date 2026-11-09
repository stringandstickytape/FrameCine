extends RefCounted

## Persistent settings in user://settings.cfg (on the headset: ~/.local/share/godot/app_userdata/FrameCine/).
## Writes are batched: set() marks the file dirty, save_if_dirty() (called every second and on exit) writes it.

const PATH := "user://settings.cfg"

## Tests and screenshot runs: start from defaults and never write.
var read_only := false
var _cfg := ConfigFile.new()
var _dirty := false


func load_file() -> void:
	if read_only:
		return
	var err := _cfg.load(PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("Can't read %s (%s); using defaults." % [PATH, error_string(err)])


func get_value(section: String, key: String, default: Variant) -> Variant:
	return _cfg.get_value(section, key, default)


func has_value(section: String, key: String) -> bool:
	return _cfg.has_section_key(section, key)


## The keys of a section ([] if it doesn't exist).
func get_keys(section: String) -> PackedStringArray:
	return _cfg.get_section_keys(section) if _cfg.has_section(section) else PackedStringArray()


## value null erases the key.
func set_value(section: String, key: String, value: Variant) -> void:
	if value == null:
		if _cfg.has_section_key(section, key):
			_cfg.erase_section_key(section, key)
			_dirty = true
		return
	if _cfg.has_section_key(section, key) and _cfg.get_value(section, key) == value:
		return
	_cfg.set_value(section, key, value)
	_dirty = true


func save_if_dirty() -> void:
	if not _dirty or read_only:
		return
	var err := _cfg.save(PATH)
	if err != OK:
		push_warning("Can't write %s: %s" % [PATH, error_string(err)])
	_dirty = false


## Remembered mode for a file, or "" (keys are the path's hash; the path itself is kept for reference).
func get_file_mode(file_path: String) -> String:
	return str(_cfg.get_value("files", _file_key(file_path), ""))


func set_file_mode(file_path: String, mode_id: String) -> void:
	set_value("files", _file_key(file_path), mode_id)


func _file_key(file_path: String) -> String:
	return "m" + file_path.md5_text().substr(0, 16)
