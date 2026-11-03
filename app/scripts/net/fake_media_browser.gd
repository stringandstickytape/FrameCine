extends RefCounted

## Stand-in for the engine's MediaBrowser (modules/hwvideo), used when the engine build has none, so the network part
## of the file browser can be used and tested on any desktop build. Same calls as the real one: set_smb_credentials(),
## list_shares(host) -> [share names], list_dir(path) -> [{name, is_dir, size, mtime}], get_last_error() ("" on
## success). Answers after a delay, like a network would. Host "offline.invalid" fails; password "wrong" is refused.

const DELAY_MSEC := 400

var _user := ""
var _password := ""
var _last_error := ""

const TREE := {
	"Movies": {
		"3D": {
			"Animated.Feature.2.3D.2019.MULTi.1080p.Half-SBS.mkv": 11752993139,
			"Documentary.3D.Full-SBS.mkv": 6484543492,
		},
		"VR": {
			"beach_180x180_3dh_LR.mp4": 2400000000,
			"pano_360_TB.mp4": 1800000000,
			"concert_fisheye200.mp4": 3100000000,
		},
		"Comedy.1980.1080p.mkv": 8100000000,
		"notes.txt": 1200,
	},
	"Public": {},
}


func set_smb_credentials(_host: String, user: String, password: String, _domain: String) -> void:
	_user = user
	_password = password


func get_last_error() -> String:
	return _last_error


func list_shares(host: String) -> Array:
	OS.delay_msec(DELAY_MSEC)
	if not _check(host):
		return []
	var out: Array = []
	for share: String in TREE:
		out.append(share)
	return out


func list_dir(path: String) -> Array:
	OS.delay_msec(DELAY_MSEC)
	var parts := path.trim_prefix("smb://").split("/", false)
	if parts.is_empty() or not _check(parts[0]):
		return []
	var node: Variant = TREE
	for i in range(1, parts.size()):
		if not (node is Dictionary and (node as Dictionary).has(parts[i])):
			_last_error = "No such folder: %s" % path
			return []
		node = (node as Dictionary)[parts[i]]
	var out: Array = []
	for name: String in node:
		var v: Variant = node[name]
		out.append({"name": name, "is_dir": v is Dictionary, "size": 0 if v is Dictionary else int(v), "mtime": 0})
	return out


func _check(host: String) -> bool:
	_last_error = ""
	if host == "offline.invalid":
		_last_error = "Can't reach %s (simulated)" % host
		return false
	if _password == "wrong":
		_last_error = "Access denied for user '%s' (simulated)" % _user
		return false
	return true
