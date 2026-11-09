extends RefCounted

## The updater's pure parts (docs/framedrop.md, "Our own updates"): versions, the signed `latest.json`, the bad
## versions that run.sh recorded, the prompt rule, and the folders. No network and no nodes here, so the tests call
## these directly.
##
## Folders (the same in run.sh, written by tools/package.sh):
##   install  the folder that holds run.sh (the app is install/app, run with --path); never a fixed path
##   staging  ${XDG_DATA_HOME:-~/.local/share}/framecine/update: package.part (+ .json), unpack/, new/,
##            new.complete (written last), old/ (the install before the last swap)
##   state    ${XDG_STATE_HOME:-~/.local/state}/framecine: swapped (run.sh's swap record), started (the new
##            version's first frame), bad-versions (one per line)

## The release's own folder of files: GitHub redirects /latest/download/<file> to the newest full release.
const DEFAULT_BASE_URL := "https://github.com/stringandstickytape/FrameCine/releases/latest/download/"
const KEY_PATH := "res://update/release-key.pub.pem"
const LATEST := "latest.json"
const SIGNATURE := "latest.json.sig"
## latest.json is small; more than this is not ours.
const MAX_LATEST_BYTES := 64 * 1024
const MAX_SIGNATURE_BYTES := 4096


## "1.4.0" -> [1, 4, 0]; [] when it is not plain MAJOR.MINOR.PATCH.
static func parse_version(text: String) -> Array:
	var parts := text.strip_edges().split(".")
	if parts.size() != 3:
		return []
	var out := []
	for p in parts:
		if p == "" or not p.is_valid_int() or p.begins_with("+") or p.begins_with("-") or p.length() > 6:
			return []
		out.append(p.to_int())
	return out


## The installed version from the VERSION file's text ("version 0.1.0"). A leading v and a git describe tail
## ("v0.1.0-3-gabc1234") are allowed: the release part counts. "" when there is none (a build named by its commit).
static func installed_version(version_file_text: String) -> String:
	for line in version_file_text.split("\n"):
		var l := line.strip_edges()
		if not l.begins_with("version "):
			continue
		var v := l.trim_prefix("version ").strip_edges().trim_prefix("v")
		v = v.split("-")[0]
		return v if not parse_version(v).is_empty() else ""
	return ""


## -1, 0 or 1 (a before, equal, after b). Unparseable versions compare as equal, so nothing updates on them.
static func compare(a: String, b: String) -> int:
	var x := parse_version(a)
	var y := parse_version(b)
	if x.is_empty() or y.is_empty():
		return 0
	for i in 3:
		if x[i] != y[i]:
			return -1 if x[i] < y[i] else 1
	return 0


static func is_newer(remote: String, installed: String) -> bool:
	return compare(remote, installed) > 0


## True when `sig` is the release key's RSA PKCS#1 v1.5 signature over the SHA-256 of `data` (what
## `openssl dgst -sha256 -sign key.pem` writes). A key that does not load verifies nothing.
static func verify(data: PackedByteArray, sig: PackedByteArray, key_path: String) -> bool:
	if sig.is_empty() or sig.size() > MAX_SIGNATURE_BYTES or not FileAccess.file_exists(key_path):
		return false
	var key := CryptoKey.new()
	if key.load(key_path, true) != OK:
		return false
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	var digest := ctx.finish()
	return Crypto.new().verify(HashingContext.HASH_SHA256, digest, sig, key)


## The fields of a verified latest.json, checked: {version, tag, url, size, sha256, notes}, or {"error": why}.
static func parse_latest(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_LATEST_BYTES:
		return {"error": "latest.json too large"}
	# JSON.new().parse(): a captive portal's page is no error in the log, only the one line.
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(data.get_string_from_utf8()) == OK else null
	if not parsed is Dictionary:
		return {"error": "latest.json is not a JSON object"}
	var d: Dictionary = parsed
	var pkg: Variant = d.get("package")
	if not pkg is Dictionary:
		return {"error": "latest.json has no package"}
	var version := str(d.get("version", ""))
	if parse_version(version).is_empty():
		return {"error": "latest.json: version is not MAJOR.MINOR.PATCH"}
	var url := str(pkg.get("url", ""))
	if not (url.begins_with("https://") or url.begins_with("http://")):
		return {"error": "latest.json: package url is not http(s)"}
	var size_v: Variant = pkg.get("size")
	if not (size_v is float or size_v is int) or float(size_v) <= 0.0 or float(size_v) != floorf(float(size_v)):
		return {"error": "latest.json: package size is not a positive whole number"}
	var sha := str(pkg.get("sha256", ""))
	if RegEx.create_from_string("^[0-9a-f]{64}$").search(sha) == null:
		return {"error": "latest.json: sha256 is not 64 lowercase hex digits"}
	# One line for the prompt; a long or many-line note is cut.
	var notes := str(d.get("notes", "")).replace("\r", " ").replace("\n", " ").strip_edges()
	if notes.length() > 200:
		notes = notes.left(197) + "..."
	return {"version": version, "tag": str(d.get("tag", "")), "url": url, "size": int(size_v), "sha256": sha,
			"notes": notes}


## The versions run.sh rolled back from (the bad-versions file's text), so the check skips them.
static func bad_versions(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var v := line.strip_edges()
		if v != "" and not v in out:
			out.append(v)
	return out


## The prompt rule: never during a film. The question shows when an update is staged and the menu is open with
## nothing in progress: no source, or the source has ended (the end of the film opens the menu). A paused film is
## still a film. `s`: {staged, declined, menu_shown, has_source, ended}.
static func may_prompt(s: Dictionary) -> bool:
	if not bool(s.get("staged", false)) or bool(s.get("declined", false)) or not bool(s.get("menu_shown", false)):
		return false
	return not bool(s.get("has_source", false)) or bool(s.get("ended", false))


static func _home() -> String:
	return OS.get_environment("HOME")


## ${XDG_DATA_HOME:-~/.local/share}/framecine/update (outside ~/devkit-game: Valve's tools treat each folder
## there as a title).
static func default_staging_dir() -> String:
	var base := OS.get_environment("XDG_DATA_HOME")
	if base == "":
		base = _home().path_join(".local/share")
	return base.path_join("framecine/update")


static func default_state_dir() -> String:
	var base := OS.get_environment("XDG_STATE_HOME")
	if base == "":
		base = _home().path_join(".local/state")
	return base.path_join("framecine")


## The folder that holds run.sh: the parent of the app folder (res://). "" when the app does not run from an
## install (a run from the repository has no run.sh and VERSION beside app/).
static func detect_install_dir() -> String:
	var app_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dir := app_dir.get_base_dir()
	if dir == "" or not FileAccess.file_exists(dir.path_join("run.sh")) \
			or not FileAccess.file_exists(dir.path_join("VERSION")):
		return ""
	return dir


static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


static func write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


## Deletes a folder and everything in it (no links followed). True when it is gone.
static func remove_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			return DirAccess.remove_absolute(path) == OK
		return true
	var out := []
	# rm keeps the file modes and links out of it; a link to a folder is removed, not followed.
	OS.execute("rm", ["-rf", "--", path], out)
	return not DirAccess.dir_exists_absolute(path)
