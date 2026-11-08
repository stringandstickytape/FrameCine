extends Node

## The player updates itself from GitHub Releases (docs/framedrop.md, "Our own updates"; docs/decisions.md D32).
## features.update (scripts/play/features.gd).
##
## 1. Check: START_DELAY seconds after the first frame, then once a day while the player runs. latest.json and its
##    signature come from the latest release (--update-url=URL sets another base, for tests), on a thread of its own,
##    CHECK_TIMEOUT seconds in all. The signature is checked first (res://update/release-key.pub.pem), then the
##    version against the install's VERSION, and the versions run.sh rolled back from. A failure is one log line.
## 2. Download: the package to <staging>/package.part, continued with a Range request after a break; it stops after
##    STALL_TIMEOUT seconds with no bytes and continues at the next check. Then the size and the SHA-256.
## 3. Stage: tar unpacks it into <staging>/new, the new engine must start with --version, and new.complete is
##    written last. run.sh swaps it in at the next start (never while the engine runs) and rolls back if the new
##    version shows no frame.
## 4. Ask: "Restart now to update?" in the menu's footer, only with nothing in progress (Core.may_prompt()). Yes saves
##    what is open (file, position, paused, room) to RESTART_PATH, then the player quits and Steam starts it again
##    (steam://rungameid/$SteamGameId, from a unit outside Steam's process tree). The next start opens it again there.
##
## Nothing here waits on the main thread: the network, the hash, tar and the engine check all run on the thread.
## Off with [update] check = false (System, Updates), in runs with read-only settings (tests, tours) unless
## --update-url is given, and when the app does not run from an install (no run.sh and VERSION beside app/).

const Core := preload("res://scripts/update/update_core.gd")
const Fetch := preload("res://scripts/update/update_fetch.gd")

## State or progress changed (the System tab's Updates row).
signal changed

const START_DELAY := 8.0
const CHECK_EVERY := 24.0 * 3600.0
const CHECK_TIMEOUT := 10.0
const STALL_TIMEOUT := 30.0
## What was open when the user said yes; read and removed at the next start.
const RESTART_PATH := "user://update_restart.cfg"
## A restart state older than this (seconds) is not used: the restart did not happen then.
const RESTART_MAX_AGE := 900
## The question stays this long in the footer.
const PROMPT_SECONDS := 60.0

var main: Node3D
## [update] check.
var enabled := true
## Timed checks on (false in tests and outside an install; check_now() still works).
var auto := true
var base_url := Core.DEFAULT_BASE_URL
var key_path := Core.KEY_PATH
var install_dir := ""
var staging_dir := ""
var state_dir := ""
var check_timeout := CHECK_TIMEOUT
var stall_timeout := STALL_TIMEOUT
var start_delay := START_DELAY
## "idle", "checking", "downloading", "staging", "ready".
var state := "idle"
## The installed version (VERSION), "" when it is not a release number.
var installed := ""
## The verified latest.json fields ({} before a check found a newer version).
var latest := {}
## The version in <staging>/new, complete, or "".
var staged_version := ""
## The last outcome, one line (also printed).
var last_result := ""
## "Later" was pressed: no more questions in this run (the swap still happens at the next start).
var declined := false
## The version run.sh just swapped in ("" when this start is not the first after an update).
var just_updated := ""

var _thread: Thread
var _job := ""
var _progress: Fetch.Progress
var _frames := 0
var _next_check_msec := -1
var _prompt_rule := false
var _tick := 0.0
var _last_percent := -1
var _restore := {}


func _ready() -> void:
	enabled = bool(main.settings.get_value("update", "check", true))
	var args: Dictionary = main.get("_args") if main.get("_args") is Dictionary else {}
	if args.has("update-url"):
		base_url = str(args["update-url"])
		if not base_url.ends_with("/"):
			base_url += "/"
	staging_dir = Core.default_staging_dir()
	state_dir = Core.default_state_dir()
	install_dir = Core.detect_install_dir()
	auto = install_dir != "" and (not main.settings.read_only or args.has("update-url"))
	if install_dir == "":
		print("Updates: not an install (no run.sh and VERSION beside app/): no update check")
		return
	installed = Core.installed_version(Core.read_text(install_dir.path_join("VERSION")))
	var record := Core.read_text(state_dir.path_join("swapped"))
	if record != "":
		var v := _record_value(record, "new")
		if v != "" and v == installed:
			just_updated = v
			print("Updates: this is the first start of %s" % v)
	_find_staged()
	if not main.settings.read_only:
		_load_restore.call_deferred()


## Starts a check now (tests; the timed checks call it). False when one cannot start.
func check_now() -> bool:
	if _thread != null or state == "ready" or install_dir == "":
		return false
	_next_check_msec = Time.get_ticks_msec() + int(CHECK_EVERY * 1000.0)
	if installed == "":
		_result("Update check skipped: the installed version is not a release number (VERSION)")
		return false
	if not FileAccess.file_exists(key_path):
		_result("Update check skipped: no release key at %s" % key_path)
		return false
	state = "checking"
	_progress = Fetch.Progress.new()
	_start("check", _check_job.bind(base_url, check_timeout, _progress))
	return true


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("update", "check", on)
	if not on and _job in ["check", "download"] and _progress != null:
		_progress.cancel()
	changed.emit()


## True while a thread works (tests wait on it).
func busy() -> bool:
	return _thread != null


func _process(delta: float) -> void:
	_frames += 1
	if _frames == 2:
		_mark_started()
	if _thread != null and not _thread.is_alive():
		_finish_job()
	if auto and enabled and _thread == null and state != "ready" and _frames >= 2:
		var now := Time.get_ticks_msec()
		if _next_check_msec < 0:
			_next_check_msec = now + int(start_delay * 1000.0)
		elif now >= _next_check_msec:
			check_now()
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	if _job == "download" and _progress != null:
		var p := percent()
		if p != _last_percent:
			_last_percent = p
			changed.emit()
	_update_prompt()


## The download's progress, 0..100 (-1 when not downloading).
func percent() -> int:
	if _job != "download" or _progress == null or int(latest.get("size", 0)) <= 0:
		return -1
	return clampi(int(100.0 * float(_progress.received()) / float(latest["size"])), 0, 100)


## One line for the System tab, translated.
func status_text() -> String:
	if install_dir == "":
		return tr("This copy does not run from an install: no updates.")
	var v := tr("Version %s") % (installed if installed != "" else "?")
	match state:
		"downloading":
			return v + "  ·  " + tr("Downloading version %s: %d %%") % [str(latest.get("version", "")), maxi(percent(), 0)]
		"staging":
			return v + "  ·  " + tr("Preparing version %s...") % str(latest.get("version", ""))
		"ready":
			return v + "  ·  " + tr("Version %s is ready. It goes in at the next start.") % staged_version
	return v


## The release's line for the prompt ("" when none): English, as the release wrote it.
func notes() -> String:
	return str(latest.get("notes", "")) if staged_version != "" and str(latest.get("version", "")) == staged_version \
			else ""


# --- The jobs (each on the thread; static, so they touch no node) ---------------------------------------------------

func _start(job: String, work: Callable) -> void:
	_job = job
	_thread = Thread.new()
	_thread.start(work)
	changed.emit()


func _finish_job() -> void:
	var r: Variant = _thread.wait_to_finish()
	_thread = null
	var job := _job
	_job = ""
	var d: Dictionary = r if r is Dictionary else {"error": "the job returned nothing"}
	match job:
		"check":
			_on_checked(d)
		"download":
			_on_downloaded(d)
		"stage":
			_on_staged(d)
	changed.emit()


static func _check_job(base: String, timeout: float, progress: Fetch.Progress) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	var j := Fetch.fetch(base + Core.LATEST, {"deadline_msec": deadline, "max_bytes": Core.MAX_LATEST_BYTES}, progress)
	if not j["ok"]:
		return {"error": "latest.json: " + str(j["error"])}
	var s := Fetch.fetch(base + Core.SIGNATURE, {"deadline_msec": deadline, "max_bytes": Core.MAX_SIGNATURE_BYTES},
			progress)
	if not s["ok"]:
		return {"error": "latest.json.sig: " + str(s["error"])}
	return {"json": j["body"], "sig": s["body"]}


func _on_checked(r: Dictionary) -> void:
	state = "idle"
	if r.has("error"):
		_result("Update check failed: %s" % r["error"])
		return
	if not Core.verify(r["json"], r["sig"], key_path):
		_result("Update check: the signature of latest.json does not verify; ignored")
		return
	var l := Core.parse_latest(r["json"])
	if l.has("error"):
		_result("Update check: %s" % l["error"])
		return
	if not Core.is_newer(l["version"], installed):
		_result("Update check: %s is the newest (installed %s)" % [l["version"], installed])
		return
	if l["version"] in Core.bad_versions(Core.read_text(state_dir.path_join("bad-versions"))):
		_result("Update check: %s was rolled back on this headset before; skipped" % l["version"])
		return
	latest = l
	_result("Update check: %s is out (installed %s); downloading" % [l["version"], installed])
	state = "downloading"
	_progress = Fetch.Progress.new()
	_last_percent = -1
	_start("download", _download_job.bind(l, staging_dir, stall_timeout, _progress))


static func _download_job(l: Dictionary, staging: String, stall: float, progress: Fetch.Progress) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(staging)
	var part := staging.path_join("package.part")
	var meta_path := part + ".json"
	var json := JSON.new()
	var meta: Variant = json.data if json.parse(Core.read_text(meta_path)) == OK else null
	var same: bool = meta is Dictionary and str(meta.get("version", "")) == l["version"] \
			and str(meta.get("sha256", "")) == l["sha256"] and int(meta.get("size", -1)) == int(l["size"])
	if not same:
		# A .part of another version (or of nothing known) starts again.
		DirAccess.remove_absolute(part)
		Core.write_text(meta_path, JSON.stringify({"version": l["version"], "sha256": l["sha256"], "size": l["size"]}))
	var have := _file_size(part)
	if have > int(l["size"]):
		DirAccess.remove_absolute(part)
		have = 0
	var resumed := have
	if have < int(l["size"]):
		var r := Fetch.fetch(str(l["url"]), {"file": part, "offset": have, "stall_msec": int(stall * 1000.0)}, progress)
		if not r["ok"] and int(r["code"]) != 416:
			return {"error": str(r["error"]), "kept": _file_size(part), "resumed": resumed}
	var size := _file_size(part)
	if size != int(l["size"]):
		DirAccess.remove_absolute(part)
		return {"error": "the package is %d bytes, not %d" % [size, l["size"]], "kept": 0, "resumed": resumed}
	if FileAccess.get_sha256(part) != str(l["sha256"]):
		DirAccess.remove_absolute(part)
		DirAccess.remove_absolute(meta_path)
		return {"error": "the package's SHA-256 is wrong; deleted", "kept": 0, "resumed": resumed}
	return {"ok": true, "part": part, "resumed": resumed}


func _on_downloaded(r: Dictionary) -> void:
	if r.has("error"):
		state = "idle"
		_result("Update download failed: %s (%d bytes kept for the next check)" % [r["error"], int(r.get("kept", 0))])
		return
	if int(r.get("resumed", 0)) > 0:
		print("Updates: the download continued from %d bytes" % int(r["resumed"]))
	state = "staging"
	_start("stage", _stage_job.bind(str(latest["version"]), staging_dir, str(r["part"])))


static func _stage_job(version: String, staging: String, part: String) -> Dictionary:
	var new_dir := staging.path_join("new")
	var unpack := staging.path_join("unpack")
	var marker := staging.path_join("new.complete")
	DirAccess.remove_absolute(marker)
	Core.remove_tree(new_dir)
	Core.remove_tree(unpack)
	DirAccess.make_dir_recursive_absolute(unpack)
	var out := []
	# The host's tar keeps the modes (the engine and run.sh are executable in the package).
	var code := OS.execute("tar", ["-xzf", part, "-C", unpack, "--no-same-owner"], out, true)
	if code != 0:
		Core.remove_tree(unpack)
		return {"error": "tar could not unpack the package (%d): %s" % [code, "".join(out).strip_edges().left(200)]}
	# tools/package.sh puts one top folder (vr-video-player-<version>-<arch>/) in the archive; a flat one works too.
	var root := unpack
	if not FileAccess.file_exists(unpack.path_join("run.sh")):
		var dirs := DirAccess.get_directories_at(unpack)
		if dirs.size() == 1 and DirAccess.get_files_at(unpack).is_empty() \
				and FileAccess.file_exists(unpack.path_join(dirs[0]).path_join("run.sh")):
			root = unpack.path_join(dirs[0])
		else:
			Core.remove_tree(unpack)
			return {"error": "not a player package (no run.sh)"}
	if DirAccess.rename_absolute(root, new_dir) != OK:
		Core.remove_tree(unpack)
		return {"error": "can't move the unpacked package to %s" % new_dir}
	Core.remove_tree(unpack)
	var v := Core.installed_version(Core.read_text(new_dir.path_join("VERSION")))
	if v != version:
		Core.remove_tree(new_dir)
		return {"error": "the package says version %s, latest.json %s" % [v, version]}
	var engine := new_dir.path_join("bin/vr-video-player-engine")
	out = []
	code = OS.execute("timeout", ["30", engine, "--version"], out, true) if FileAccess.file_exists(engine) else -1
	var said := "".join(out).strip_edges()
	if code != 0 or said == "":
		Core.remove_tree(new_dir)
		return {"error": "the new engine does not start here (%d)" % code}
	if not Core.write_text(marker, version + "\n"):
		Core.remove_tree(new_dir)
		return {"error": "can't write %s" % marker}
	DirAccess.remove_absolute(part)
	DirAccess.remove_absolute(part + ".json")
	return {"ok": true, "engine": said.split("\n")[-1]}


func _on_staged(r: Dictionary) -> void:
	if r.has("error"):
		state = "idle"
		_result("Update staging failed: %s" % r["error"])
		return
	staged_version = str(latest["version"])
	state = "ready"
	_result("Update: %s is ready (engine %s); it goes in at the next start" % [staged_version, r.get("engine", "")])


## A complete <staging>/new from an earlier run (run.sh swaps it at start, so only when the app started another way).
func _find_staged() -> void:
	var v := Core.read_text(staging_dir.path_join("new.complete")).strip_edges()
	if v != "" and DirAccess.dir_exists_absolute(staging_dir.path_join("new")) and Core.is_newer(v, installed):
		staged_version = v
		state = "ready"


static func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


func _result(line: String) -> void:
	last_result = line
	print(line)


static func _record_value(text: String, key: String) -> String:
	for line in text.split("\n"):
		if line.begins_with(key + " "):
			return line.trim_prefix(key + " ").strip_edges()
	return ""


# --- After a swap: the started marker -------------------------------------------------------------------------------

## The first frame of a version run.sh just swapped in: the marker that keeps run.sh from rolling it back.
func _mark_started() -> void:
	if install_dir == "" or not FileAccess.file_exists(state_dir.path_join("swapped")):
		return
	var marker := state_dir.path_join("started")
	if not FileAccess.file_exists(marker):
		Core.write_text(marker, installed + "\n")
		print("Updates: %s showed its first frame (started marker written)" % installed)
	if just_updated != "":
		_notice_updated.call_deferred()


func _notice_updated() -> void:
	var layer: Node = main.get("ui")
	if layer != null and layer.has_method("notify"):
		layer.notify(tr("Updated to version %s") % just_updated)


# --- The question and the restart -------------------------------------------------------------------------------------

func prompt_state() -> Dictionary:
	var p: Node = main.player
	var src: Variant = p.source if p.has_source() else null
	return {"staged": state == "ready", "declined": declined, "menu_shown": bool(main.menu_shown),
			"has_source": p.has_source(), "ended": src != null and src.is_ended()}


## Asks once each time the rule turns true (the menu opens with nothing in progress, or the film ends).
func _update_prompt() -> void:
	var want := Core.may_prompt(prompt_state())
	if want and not _prompt_rule:
		ask()
	_prompt_rule = want


## Whether the player can start itself again: through Steam (SteamGameId), from outside Steam's process tree.
static func can_restart() -> bool:
	return OS.get_name() == "Linux" and OS.get_environment("SteamGameId") != "" \
			and FileAccess.file_exists("/usr/bin/systemd-run") and OS.get_environment("XDG_RUNTIME_DIR") != ""


## "Restart now to update?" in the menu's footer (or quit, when the player cannot start itself again).
func ask() -> void:
	var layer: Node = main.get("ui")
	if layer == null or layer.get("ui") == null or staged_version == "":
		return
	var restart := can_restart()
	var text := (tr("Restart now to update to %s?") if restart
			else tr("Quit now to update to %s? Then start the player again.")) % staged_version
	if notes() != "":
		text += "  " + notes()
	layer.ui.show_choice(text, tr("Restart") if restart else tr("Quit"), restart_now, tr("Later"),
			func() -> void: declined = true, PROMPT_SECONDS)


## Yes: saves what is open, then quits; Steam starts the player again, and run.sh swaps the new version in.
func restart_now() -> void:
	if state != "ready":
		return
	save_restart_state()
	main.settings.save_if_dirty()
	if main.features.get("resume") != null:
		main.features.resume.save_now()
	if can_restart():
		_launch_relauncher()
	else:
		print("Updates: quit for the update; start the player again to finish it")
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## What plays, for the next start: file, position, paused, room. A finished film or a window: the room only.
func restart_state() -> Dictionary:
	var p: Node = main.player
	var d := {"env": str(main.env_id), "saved": int(Time.get_unix_time_from_system()), "version": staged_version}
	var path := str(main.current_path)
	var tracked := path != "" and not (path.begins_with("browser://") or path.begins_with("window://")
			or path.begins_with("pcwindow://"))
	if tracked and p.has_source() and not p.source.is_ended():
		d["path"] = path
		d["position"] = snappedf(float(p.get_position()), 0.1)
		d["paused"] = not p.is_playing()
	return d


func save_restart_state() -> void:
	var cfg := ConfigFile.new()
	var d := restart_state()
	for k: String in d:
		cfg.set_value("restart", k, d[k])
	var err := cfg.save(RESTART_PATH)
	if err != OK:
		push_warning("Can't write %s: %s" % [RESTART_PATH, error_string(err)])


## A unit of the user's service manager waits for this process to end, then asks Steam to start the title again.
## Steam's launch wrapper waits for every descendant of the title (docs/assistant.md, the agent terminal), so the
## waiter must not be one.
func _launch_relauncher() -> void:
	var args := relauncher_args(OS.get_process_id(), OS.get_environment("SteamGameId"))
	var out := []
	var code := OS.execute("/usr/bin/systemd-run", args, out, true)
	print("Updates: restart through Steam asked (%d)" % code)


static func relauncher_args(pid: int, game_id: String) -> PackedStringArray:
	var a := PackedStringArray(["--user", "--quiet", "--collect", "--unit=vr-video-player-restart-%d" % pid,
			"--description=Starts the VR video player again after an update"])
	for v in ["DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "PATH", "HOME"]:
		if OS.get_environment(v) != "":
			a.append("--setenv=%s=%s" % [v, OS.get_environment(v)])
	a.append_array(["--", "/bin/sh", "-c",
			'while kill -0 "$1" 2>/dev/null; do sleep 0.5; done; sleep 3; exec steam "steam://rungameid/$2"',
			"vr-video-player-restart", str(pid), game_id])
	return a


## The next start: what played before the restart opens again (when nothing else was asked for on the command line).
func _load_restore() -> void:
	if not FileAccess.file_exists(RESTART_PATH):
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(RESTART_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESTART_PATH))
	if err != OK:
		return
	var d := {}
	for k in (cfg.get_section_keys("restart") if cfg.has_section("restart") else PackedStringArray()):
		d[k] = cfg.get_value("restart", k)
	restore(d)


## Opens what restart_state() saved: the room, then the file at its place (paused if it was).
func restore(d: Dictionary) -> bool:
	if int(Time.get_unix_time_from_system()) - int(d.get("saved", 0)) > RESTART_MAX_AGE:
		print("Updates: the restart state is old; not used")
		return false
	var env := str(d.get("env", ""))
	if env != "" and env != str(main.env_id) and not env.begins_with("assistant:"):
		main.set_environment(env)
	var path := str(d.get("path", ""))
	if path == "" or str(main.current_path) != "":
		return env != ""
	_restore = d
	main.file_opened.connect(_on_restored_open, CONNECT_ONE_SHOT)
	main.open_path(path)
	var layer: Node = main.get("ui")
	if layer != null and layer.has_method("hide_panel"):
		layer.hide_panel()
	return true


func _on_restored_open(path: String) -> void:
	if path != str(_restore.get("path", "")):
		return
	# After the resume feature's own seek (deferred from the same signal): this one is the exact place.
	_seek_restored.call_deferred()


func _seek_restored() -> void:
	var d := _restore
	_restore = {}
	var p: Node = main.player
	var pos := float(d.get("position", 0.0))
	if pos > 0.0 and p.can_seek():
		p.seek(pos)
	if bool(d.get("paused", false)):
		p.pause()
	print("Updates: reopened %s at %.1f s after the restart" % [str(d.get("path", "")).get_file(), pos])


func _exit_tree() -> void:
	if _thread != null:
		if _progress != null:
			_progress.cancel()
		_thread.wait_to_finish()
		_thread = null
