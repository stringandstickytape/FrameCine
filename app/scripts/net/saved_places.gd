extends RefCounted

## Places the viewer added to the file browser (an assistant's add_place, confirmed on the card): local folders under
## the home folder, listed after the built-in places. Network shares go to NetworkHosts and web pages to WebPages, as
## the Network and Browser places keep them. Static like those; main.gd calls load_from() once. Stored in
## user://settings.cfg, section "places", key "saved": [{label, path}].

const AppSettings := preload("res://scripts/app_settings.gd")

static var places: Array[Dictionary] = []
static var _settings: AppSettings


static func load_from(settings: AppSettings) -> void:
	_settings = settings
	places.clear()
	for p: Variant in settings.get_value("places", "saved", []):
		if p is Dictionary and str((p as Dictionary).get("path", "")) != "":
			places.append({"label": str(p.get("label", "")), "path": str(p["path"])})


static func find(path: String) -> Dictionary:
	for p in places:
		if p["path"] == path:
			return p
	return {}


static func add(label: String, path: String) -> void:
	if not find(path).is_empty():
		return
	places.append({"label": label, "path": path})
	_persist()


static func remove(path: String) -> bool:
	for i in places.size():
		if places[i]["path"] == path:
			places.remove_at(i)
			_persist()
			return true
	return false


static func _persist() -> void:
	if _settings != null:
		_settings.set_value("places", "saved", places.duplicate(true))
