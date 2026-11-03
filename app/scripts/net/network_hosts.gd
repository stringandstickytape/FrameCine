extends RefCounted

## Saved network (SMB) hosts and their credentials: the core's store, used by the file browser (listing) and by
## HWVideoSource (opening smb:// files). Static so both reach it without wiring; main.gd calls load_from() once.
## Stored in user://settings.cfg, section "network", key "hosts", PASSWORDS IN PLAIN TEXT (see README, Decisions).
##
## A host entry: {"host": "nas.local", "share": "Movies" (optional), "user": "", "password": "", "domain": "",
## "label": "" (optional: a name for the place, e.g. from an assistant's add_place)}.
## Paths look like smb://host/share/dir/file.mkv; credentials are matched by host.

const AppSettings := preload("res://scripts/app_settings.gd")

static var hosts: Array[Dictionary] = []
static var _settings: AppSettings


static func load_from(settings: AppSettings) -> void:
	_settings = settings
	hosts.clear()
	for h: Variant in settings.get_value("network", "hosts", []):
		if h is Dictionary and str((h as Dictionary).get("host", "")) != "":
			hosts.append(_normalized(h))


static func _normalized(h: Dictionary) -> Dictionary:
	return {"host": str(h.get("host", "")).strip_edges().trim_prefix("smb://").trim_suffix("/"),
			"share": str(h.get("share", "")).strip_edges().trim_prefix("/").trim_suffix("/"),
			"user": str(h.get("user", "")), "password": str(h.get("password", "")),
			"domain": str(h.get("domain", "")), "label": str(h.get("label", ""))}


## Adds or (same index) replaces a host; index -1 adds.
static func save_host(index: int, entry: Dictionary) -> void:
	var h := _normalized(entry)
	if h["host"] == "":
		return
	if index >= 0 and index < hosts.size():
		hosts[index] = h
	else:
		hosts.append(h)
	_persist()


static func remove_host(index: int) -> void:
	if index >= 0 and index < hosts.size():
		hosts.remove_at(index)
		_persist()


static func _persist() -> void:
	if _settings != null:
		_settings.set_value("network", "hosts", hosts.duplicate(true))


## The browsing root of a saved host: smb://host or smb://host/share.
static func root_path(h: Dictionary) -> String:
	var p := "smb://" + str(h["host"])
	if str(h.get("share", "")) != "":
		p += "/" + str(h["share"])
	return p


static func is_smb(path: String) -> bool:
	return path.begins_with("smb://")


## "nas.local" for smb://nas.local/Movies/a.mkv.
static func host_of(path: String) -> String:
	return path.trim_prefix("smb://").get_slice("/", 0)


static func find_host(host: String) -> Dictionary:
	for h in hosts:
		if str(h["host"]).to_lower() == host.to_lower():
			return h
	return {}


## Gives the saved credentials for path's host to an engine object that takes them (MediaSource, MediaBrowser).
## Returns false if there is nothing to give or the object has no set_smb_credentials().
static func apply_credentials(target: Object, path: String) -> bool:
	if target == null or not is_smb(path) or not target.has_method("set_smb_credentials"):
		return false
	var h := find_host(host_of(path))
	if h.is_empty():
		return false
	target.call("set_smb_credentials", h["host"], h["user"], h["password"], h["domain"])
	return true
