extends Node

## Sidecar JSON for the chosen mode (ideas #60): when the user picks a mode for a file, it is also written next to the
## file, so the choice travels with it (another headset, a reinstall, a copy on a stick). On open, a sidecar is read
## when the settings remember no mode for the file; it wins over the test pattern, the container metadata and the name.
##
## File: "<video file name>.vrmode.json" in the same folder, e.g. "Holiday.mkv.vrmode.json":
##   {"mode": "flat_sbs_half", "version": 1}
## Local files only: the share browser has no write call, so smb:// files only read nothing and write nothing. A folder
## that can't be written to is skipped with a log line. "Auto" in the menu (main.auto_mode) deletes the sidecar,
## but only one this format wrote (it has a "mode" key and nothing unknown).
##
##   read_mode(path) -> mode id or ""
##   write_mode(path, id), remove(path), sidecar_path(path)
##   enabled ([sidecar] write, default off: writing into the library is the user's call): writing only; reading is
##                     always on
## Settings: [sidecar] write.

signal written(path: String)

const SUFFIX := ".vrmode.json"
const VERSION := 1

var main: Node3D
var enabled := false
var _last_written := ""


func _ready() -> void:
	enabled = bool(main.settings.get_value("sidecar", "write", false))
	main.mode_changed.connect(_on_mode_changed)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("sidecar", "write", on)


static func is_local(path: String) -> bool:
	return path != "" and not path.contains("://") or path.begins_with("user://")


static func sidecar_path(path: String) -> String:
	return path + SUFFIX


## The mode id in the file's sidecar, or "".
static func read_mode(path: String) -> String:
	if not is_local(path):
		return ""
	var sp := sidecar_path(path)
	if not FileAccess.file_exists(sp):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(sp))
	if data is Dictionary and (data as Dictionary).get("mode", "") is String:
		return str(data["mode"])
	push_warning("Sidecar %s: not a mode file" % sp)
	return ""


func write_mode(path: String, mode_id: String) -> bool:
	if not is_local(path) or mode_id == "":
		return false
	var sp := sidecar_path(path)
	var f := FileAccess.open(sp, FileAccess.WRITE)
	if f == null:
		print("Sidecar: can't write %s (%s)" % [sp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"mode": mode_id, "version": VERSION}, "  ") + "\n")
	f.close()
	_last_written = sp
	written.emit(sp)
	return true


## Deletes the file's sidecar if it is one of ours.
func remove(path: String) -> void:
	if not is_local(path):
		return
	var sp := sidecar_path(path)
	if not FileAccess.file_exists(sp):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(sp))
	if data is Dictionary and (data as Dictionary).has("mode") \
			and (data as Dictionary).keys().all(func(k: Variant) -> bool: return k in ["mode", "version"]):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))


func _on_mode_changed(_m: Variant, _auto: String) -> void:
	var path: String = main.current_path
	if path == "" or not is_local(path):
		return
	match main.mode_source:
		"user":
			if enabled and read_mode(path) != main.mode.to_id():
				write_mode(path, main.mode.to_id())
		"auto", "metadata":
			# "Auto" chosen in the menu (auto_mode) forgets the choice: the sidecar goes too. Opening a file without a
			# remembered mode also lands here, but then there is no sidecar (it would have been read).
			if enabled and read_mode(path) != "":
				remove(path)
