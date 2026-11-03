extends Node

## Per-folder mode rules (ideas #83): "everything in this folder is 180 side by side". A file without its own mode
## (remembered for it, or in a sidecar, #60) opens in its folder's rule: the deepest folder with a rule wins, so a
## rule on /VR/ and another on /VR/360/ both work. Local paths and shares alike (the path's text).
## Order in main's mode choice: the --mode argument, the file's remembered mode, its sidecar, then this, then the
## test pattern's own, the container's metadata and the name guess.
##
##   rule_for(path) -> {folder, mode} or {}     mode_for(path) -> mode id or ""
##   set_rule(folder, mode_id), clear_rule(folder), rules() -> {folder: mode id}
##   use_current_for_folder()                   the mode on screen now becomes the open file's folder's rule
##   signal changed
## Settings: [folder_modes] rules = {folder: mode id} (one value: folder paths have spaces, colons and slashes).

const VideoMode := preload("res://scripts/video_mode.gd")

signal changed

var main: Node3D


static func normalise(folder: String) -> String:
	var f := folder.strip_edges().replace("\\", "/")
	return f if f.ends_with("/") else f + "/"


func rules() -> Dictionary:
	var v: Variant = main.settings.get_value("folder_modes", "rules", {})
	return (v as Dictionary).duplicate() if v is Dictionary else {}


func rule_for(path: String) -> Dictionary:
	if path == "" or path.begins_with("stub://"):
		return {}
	var r := rules()
	var best := ""
	for folder: String in r:
		if path.begins_with(folder) and folder.length() > best.length():
			best = folder
	return {"folder": best, "mode": r[best]} if best != "" else {}


func mode_for(path: String) -> String:
	return str(rule_for(path).get("mode", ""))


func set_rule(folder: String, mode_id: String) -> void:
	var r := rules()
	r[normalise(folder)] = VideoMode.from_id(mode_id).to_id()
	main.settings.set_value("folder_modes", "rules", r)
	changed.emit()


func clear_rule(folder: String) -> void:
	var r := rules()
	r.erase(normalise(folder))
	main.settings.set_value("folder_modes", "rules", r if not r.is_empty() else null)
	changed.emit()


func use_current_for_folder() -> void:
	if main.current_path == "" or main.current_path.begins_with("stub://"):
		return
	set_rule(main.current_path.get_base_dir(), main.mode.to_id())
