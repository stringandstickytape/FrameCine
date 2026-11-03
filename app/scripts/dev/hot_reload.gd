extends Node

## Hot-reload (dev mode): watches the app folder and reloads changed files in place, so a change pushed to the
## headset (tools/push-app.sh) shows without taking the headset off. Made by dev_host.gd only with --dev or
## [dev] hot_reload = true; it does not exist otherwise.
##
## Polls file times: every POLL_SECONDS it stats the known files, and every RESCAN_POLLS polls it lists the folders
## again for new files. A change is acted on once the file has been unchanged for SETTLE_MSEC (a copy in progress).
## What happens per file type (docs/dev/hot-reload.md):
##   .gdshader, .gdshaderinc  ResourceLoader CACHE_MODE_REPLACE: the cached Shader takes the new code in place, every
##                            material using it recompiles. Includes notify their shaders.
##   .tres, .res              the same; the cached resource (a theme, a material, a mesh) takes the new properties and
##                            emits changed.
##   .gd                      the cached GDScript gets the new source and reload(true): live instances keep their member
##                            values and run the new functions from the next call. _ready() is not run again. A copy is
##                            compiled first; if it fails, the old script stays and the errors are logged.
##   .tscn                    the cached PackedScene is replaced; live instances are not rebuilt (`reload app` does).
##   environments/*           after the reload, the current environment is instanced again from its scene.
## Files nothing has loaded yet are skipped: the next load reads them from disk anyway.
## One log line per reload: `Hot-reload: <kind> <path> (<ms> ms)[: note]`.

signal reloaded(info: Dictionary)

const POLL_SECONDS := 0.5
const RESCAN_POLLS := 4
const SETTLE_MSEC := 150
const EXTENSIONS: Array[String] = ["gd", "gdshader", "gdshaderinc", "tres", "res", "tscn"]
## Folders never watched (relative to res://).
const SKIP_DIRS: Array[String] = [".godot", "docs", ".git", ".import"]
## Reloading the script that is running the reload is not safe: these need a restart.
const SELF_PATHS: Array[String] = ["res://scripts/dev/hot_reload.gd"]

## scripts/main.gd (set by dev_host.gd; may change on `reload app`).
var main: Node
var root_dir := "res://"
## path -> [mtime, size]
var _known := {}
## path -> msec of the last change seen
var _pending := {}
var _timer := 0.0
var _polls := 0
var _env_dirty := false


func _ready() -> void:
	_scan(true)
	print("Hot-reload: watching %s (%d files)" % [ProjectSettings.globalize_path(root_dir), _known.size()])


func _process(delta: float) -> void:
	_timer += delta
	if _timer < POLL_SECONDS and _pending.is_empty():
		return
	if _timer >= POLL_SECONDS:
		_timer = 0.0
		_polls += 1
		if _polls % RESCAN_POLLS == 0:
			_scan(false)
		else:
			_check_known()
	_flush_pending()


## Number of files watched.
func file_count() -> int:
	return _known.size()


## Reloads every file whose time changed since the last poll, now (the `reload` command). Returns the infos.
func reload_changed() -> Array:
	_scan(false)
	var out: Array = []
	for path: String in _pending.keys():
		out.append(reload_path(path))
	_pending.clear()
	finish_batch()
	return out


## Reloads one file now, whatever its time. Returns {path, kind, ok, ms, note}.
func reload_path(path: String) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var info := {"path": path, "kind": path.get_extension(), "ok": true, "note": ""}
	if path in SELF_PATHS:
		info["ok"] = false
		info["note"] = "the reloader itself; restart to apply"
	elif not FileAccess.file_exists(path):
		info["ok"] = false
		info["note"] = "no such file"
	else:
		match path.get_extension():
			"gd":
				_reload_script(path, info)
			"tscn":
				_reload_resource(path, info)
				if info["ok"] and info["note"] == "":
					info["note"] = "live instances unchanged (reload app rebuilds them)"
			_:
				_reload_resource(path, info)
		if path.begins_with("res://environments/") and info["ok"]:
			_env_dirty = true
	info["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	print("Hot-reload: %s %s (%.1f ms)%s" % [info["kind"], path, info["ms"],
			(": " + str(info["note"])) if info["note"] != "" else ""])
	reloaded.emit(info)
	return info


func _scan(first: bool) -> void:
	var seen := {}
	_walk(root_dir, seen)
	for path: String in seen:
		var stamp: Array = seen[path]
		if not _known.has(path):
			_known[path] = stamp
			if not first:
				print("Hot-reload: new file %s" % path)
		elif _known[path] != stamp:
			_known[path] = stamp
			_pending[path] = Time.get_ticks_msec()
	for path: String in _known.keys():
		if not seen.has(path):
			_known.erase(path)


func _walk(dir: String, out: Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in EXTENSIONS:
			var path := dir.path_join(f)
			out[path] = _stamp(path)
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or (dir == root_dir and d in SKIP_DIRS):
			continue
		_walk(dir.path_join(d), out)


static func _stamp(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var size := f.get_length() if f != null else -1
	return [FileAccess.get_modified_time(path), size]


func _check_known() -> void:
	for path: String in _known:
		var stamp := _stamp(path)
		if stamp != _known[path]:
			_known[path] = stamp
			_pending[path] = Time.get_ticks_msec()


func _flush_pending() -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	var ready: Array[String] = []
	for path: String in _pending:
		if now - int(_pending[path]) >= SETTLE_MSEC:
			# Still being written? Look once more.
			var stamp := _stamp(path)
			if stamp != _known[path]:
				_known[path] = stamp
				_pending[path] = now
			else:
				ready.append(path)
	if ready.is_empty():
		return
	# Includes and resources before the scripts and scenes that use them.
	ready.sort_custom(func(a: String, b: String) -> bool: return _order(a) < _order(b))
	for path in ready:
		_pending.erase(path)
		reload_path(path)
	finish_batch()


static func _order(path: String) -> int:
	return ["gdshaderinc", "gdshader", "res", "tres", "gd", "tscn"].find(path.get_extension())


## After one or more reload_path() calls: the environment again, once, if a file under environments/ changed.
func finish_batch() -> void:
	if not _env_dirty:
		return
	_env_dirty = false
	if main != null and main.has_method("set_environment"):
		var t0 := Time.get_ticks_usec()
		main.set_environment(main.env_id)
		var info := {"path": "environment:" + str(main.env_id), "kind": "environment", "ok": true,
				"ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1), "note": "instanced again"}
		print("Hot-reload: environment %s instanced again (%.1f ms)" % [main.env_id, info["ms"]])
		reloaded.emit(info)


## Shaders, includes, .tres/.res and scenes: the cached resource takes the new contents in place.
func _reload_resource(path: String, info: Dictionary) -> void:
	if not ResourceLoader.has_cached(path):
		info["note"] = "not loaded, nothing to do"
		return
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if res == null:
		info["ok"] = false
		info["note"] = "load failed, the old version stays"
		return
	res.emit_changed()


## A script: compile a copy first, so a typo does not leave the live script invalid.
func _reload_script(path: String, info: Dictionary) -> void:
	if not ResourceLoader.has_cached(path):
		info["note"] = "not loaded, nothing to do"
		return
	var script := ResourceLoader.get_cached_ref(path) as GDScript
	if script == null:
		info["ok"] = false
		info["note"] = "cached resource is not a GDScript"
		return
	var source := FileAccess.get_file_as_string(path)
	if source == script.source_code:
		info["note"] = "source unchanged"
		return
	var probe := GDScript.new()
	probe.source_code = source
	if probe.reload() != OK:
		info["ok"] = false
		info["note"] = "does not compile (errors above), the old version stays"
		return
	# A new member variable on a script with live instances: the instances don't get it, and the first access crashes
	# the engine (seen on the headset, 2026-10-31: main.gd gained _grip_down, a squeeze crashed the player). Refuse;
	# `reload app` rebuilds the scene, which is safe.
	if _count_instances(script) > 0:
		var had := {}
		for p: Dictionary in script.get_script_property_list():
			had[p["name"]] = true
		var added: Array[String] = []
		for p: Dictionary in probe.get_script_property_list():
			if not had.has(p["name"]):
				added.append(str(p["name"]))
		if not added.is_empty():
			info["ok"] = false
			info["note"] = "new member variable(s) %s on a script with live instances: not reloaded, use `reload app`" \
					% ", ".join(added)
			return
	# Command scripts: the registry holds lambdas made from the old script, and reloading it crashed the player on the
	# headset (2026-10-31, builtin_commands.gd). Their commands take effect after a restart of the app.
	if path.get_file().ends_with("_commands.gd") and path.begins_with("res://scripts/dev/"):
		info["ok"] = false
		info["note"] = "a command script (the registry holds its lambdas): not reloaded, restart the app"
		return
	var old_source := script.source_code
	script.source_code = source
	var err := script.reload(true)
	if err != OK:
		script.source_code = old_source
		script.reload(true)
		info["ok"] = false
		info["note"] = "reload failed (%s), the old version is back" % error_string(err)
		return
	info["note"] = "%d live instance(s) keep their state; _ready() not run again" % _count_instances(script)


func _count_instances(script: Script) -> int:
	var n := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_script() == script:
			n += 1
		stack.append_array(node.get_children(true))
	return n
