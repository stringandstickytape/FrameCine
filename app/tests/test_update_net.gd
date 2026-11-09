extends SceneTree

## The updater against a local server (app/tests/update_server.py) in the real main scene, with a test film playing:
## the offline rules (docs/framedrop.md, "Offline: never wait for the network") and the whole path to a staged
## update. Each case checks that the frames keep coming while the updater works.
##   no network (a closed port), an address that does not answer, a name that does not resolve, a server that accepts
##   and sends nothing (the 10 s limit), a wrong signature, a changed latest.json, a wrong hash, a bad version, no
##   newer version, a download cut at half then continued with a Range request, a download that stalls, a .part of
##   another version, a redirect, a package without a top folder, an engine that does not start, a new/ left half way.
## Needs python3, openssl and tar (WSL or Linux). Takes about half a minute.
## godot --headless --xr-mode off --path app --script res://tests/test_update_net.gd

const Core := preload("res://scripts/update/update_core.gd")

var main: Node3D
var up: Node
var _failures := 0
var _checks := 0
var _tmp := ""
var _root := ""
var _log := ""
var _port := 0
var _server_pid := -1
var _key := ""
var _other_key := ""
## The longest gap between two frames while the updater worked, seconds.
var _max_gap := 0.0
var _elapsed := 0.0
var _film_moved := 0.0


func _init() -> void:
	_tmp = "/tmp/vrvp-update-net-%d" % OS.get_process_id()
	_root = _tmp.path_join("www")
	_log = _tmp.path_join("requests.log")
	DirAccess.make_dir_recursive_absolute(_root)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _sh(cmd: String) -> int:
	return OS.execute("bash", ["-c", cmd], [], true)


func _write(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


## A package as tools/package.sh makes it (one top folder), or flat. engine_ok: --version prints and exits 0.
func _package(name: String, version: String, engine_ok: bool, top := true) -> String:
	var src := _tmp.path_join("src-" + name)
	var dir := src.path_join("framecine-%s-x86_64" % version) if top else src
	DirAccess.make_dir_recursive_absolute(dir.path_join("bin"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("app"))
	_write(dir.path_join("run.sh"), "#!/bin/bash\necho run\n".to_utf8_buffer())
	_write(dir.path_join("VERSION"), ("version %s\narch x86_64\n" % version).to_utf8_buffer())
	var engine := "#!/bin/bash\necho 4.7.2.fake\nexit 0\n" if engine_ok else "#!/bin/bash\nexit 1\n"
	_write(dir.path_join("bin/framecine-engine"), engine.to_utf8_buffer())
	_sh("chmod 755 '%s/run.sh' '%s/bin/framecine-engine' && head -c 1500000 /dev/urandom > '%s/app/blob.bin'"
			% [dir, dir, dir])
	var out := _root.path_join(name + ".tar.gz")
	if top:
		_sh("tar -czf '%s' -C '%s' '%s'" % [out, src, dir.get_file()])
	else:
		_sh("tar -czf '%s' -C '%s' ." % [out, src])
	return out


## latest.json (+ .sig) in www/<case>/, for a package file in www/ served under `mode`.
func _publish(case_name: String, pkg: String, mode := "ok", fields := {}, key := "") -> void:
	var d := {"version": "1.1.0", "tag": "v1.1.0", "notes": "Test release.",
			"package": {"url": "http://127.0.0.1:%d/%s/%s" % [_port, mode, pkg.get_file()],
					"size": int(FileAccess.open(pkg, FileAccess.READ).get_length()), "sha256": FileAccess.get_sha256(pkg)}}
	for k: String in fields:
		if k.begins_with("package."):
			d["package"][k.trim_prefix("package.")] = fields[k]
		else:
			d[k] = fields[k]
	var path := _root.path_join(case_name).path_join("latest.json")
	_write(path, (JSON.stringify(d, "  ") + "\n").to_utf8_buffer())
	_sh("openssl dgst -sha256 -sign '%s' -out '%s.sig' '%s'" % [key if key != "" else _key, path, path])


func _start_server() -> bool:
	var port_file := _tmp.path_join("port")
	var script := ProjectSettings.globalize_path("res://tests/update_server.py")
	_server_pid = OS.create_process("python3", [script, _root, port_file, _log])
	var t0 := Time.get_ticks_msec()
	while not FileAccess.file_exists(port_file) and Time.get_ticks_msec() - t0 < 5000:
		OS.delay_msec(50)
	_port = Core.read_text(port_file).to_int()
	return _port > 0


func _requests() -> PackedStringArray:
	var out := PackedStringArray()
	for line in Core.read_text(_log).split("\n"):
		if line.strip_edges() != "":
			out.append(line)
	return out


func _package_requests() -> PackedStringArray:
	var out := PackedStringArray()
	for line in _requests():
		if ".tar.gz" in line:
			out.append(line)
	return out


func _reset() -> void:
	up.state = "idle"
	up.staged_version = ""
	up.latest = {}
	up.installed = "1.0.0"
	up.base_url = "http://127.0.0.1:%d/ok/ok/" % _port
	up.check_timeout = 10.0
	up.stall_timeout = 30.0
	Core.remove_tree(up.staging_dir)
	_write(_log, PackedByteArray())


## One check (and the download and stage it leads to), with the frame gaps and the film's progress measured.
func _check_with(base: String) -> void:
	up.base_url = base
	var t0 := Time.get_ticks_msec()
	var pos0: float = main.player.get_position()
	var last := t0
	_max_gap = 0.0
	if not up.check_now():
		_elapsed = 0.0
		return
	while up.busy() and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		var now := Time.get_ticks_msec()
		_max_gap = maxf(_max_gap, (now - last) / 1000.0)
		last = now
	_elapsed = (Time.get_ticks_msec() - t0) / 1000.0
	_film_moved = main.player.get_position() - pos0


func _smooth(what: String) -> void:
	_check("%s: the frames kept coming (longest gap %.3f s)" % [what, _max_gap], _max_gap < 0.25)


func _run() -> void:
	await _frames(5)
	for tool in ["python3", "openssl", "tar"]:
		if _sh("command -v %s > /dev/null" % tool) != 0:
			_check("%s is there" % tool, false)
			quit(1)
			return
	_key = _tmp.path_join("key.pem")
	_other_key = _tmp.path_join("other.pem")
	var pub := _tmp.path_join("pub.pem")
	_sh("openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out '%s' 2>/dev/null" % _key)
	_sh("openssl pkey -in '%s' -pubout -out '%s'" % [_key, pub])
	_sh("openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out '%s' 2>/dev/null" % _other_key)
	if not _start_server():
		_check("the test server starts", false)
		quit(1)
		return
	var pkg := _package("pkg", "1.1.0", true)
	var flat := _package("flat", "1.1.0", true, false)
	var bad_engine := _package("badengine", "1.1.0", false)
	_publish("ok", pkg)
	_publish("half", pkg, "half")
	_publish("stall", pkg, "stall")
	_publish("wronghash", pkg, "ok", {"package.sha256": "0".repeat(64)})
	_publish("wrongsig", pkg, "ok", {}, _other_key)
	_publish("tampered", pkg)
	var tampered := _root.path_join("tampered/latest.json")
	_write(tampered, Core.read_text(tampered).replace("Test release.", "Test release!").to_utf8_buffer())
	_publish("flat", flat)
	_publish("badengine", bad_engine)

	up = main.features.update
	var install := _tmp.path_join("install")
	_write(install.path_join("VERSION"), "version 1.0.0\n".to_utf8_buffer())
	_write(install.path_join("run.sh"), "#!/bin/bash\n".to_utf8_buffer())
	up.install_dir = install
	up.staging_dir = _tmp.path_join("staging")
	up.state_dir = _tmp.path_join("state")
	up.key_path = pub
	up.auto = false
	_reset()
	# A film plays the whole time: the updater must not slow it.
	main.open_path("stub://flat_mono")
	await _frames(5)

	await _offline_cases()
	await _trust_cases()
	await _download_cases()
	await _stage_cases()

	main.close_media()
	OS.kill(_server_pid)
	OS.execute("rm", ["-rf", _tmp])
	print("update net: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(_failures)


func _offline_cases() -> void:
	# No network: nothing listens.
	_reset()
	await _check_with("http://127.0.0.1:1/")
	_check("no network: one quiet failure (%s)" % up.last_result, up.last_result.begins_with("Update check failed:")
			and up.state == "idle" and _elapsed < 3.0)
	_smooth("no network")
	# An address that never answers (TEST-NET-1): the total limit ends it.
	_reset()
	up.check_timeout = 2.0
	await _check_with("http://192.0.2.1/")
	_check("no answer: ends at the limit (%.1f s, %s)" % [_elapsed, up.last_result], _elapsed >= 1.8
			and _elapsed < 4.0 and up.last_result.begins_with("Update check failed:"))
	_smooth("no answer")
	# A name that does not resolve.
	_reset()
	await _check_with("http://update-test.invalid/")
	_check("no name: a failure within the limit (%.1f s, %s)" % [_elapsed, up.last_result], _elapsed < 11.0
			and up.last_result.begins_with("Update check failed:") and up.state == "idle")
	_smooth("no name")
	# A server that accepts and sends nothing: the real 10 s limit, the film plays on at its speed.
	_reset()
	await _check_with("http://127.0.0.1:%d/silent/" % _port)
	_check("silent server: timed out at 10 s (%.1f s, %s)" % [_elapsed, up.last_result], _elapsed >= 9.8
			and _elapsed < 11.5 and up.last_result.contains("timed out"))
	_smooth("silent server")
	_check("silent server: the film played at its speed (%.1f s in %.1f s)" % [_film_moved, _elapsed],
			_film_moved > _elapsed * 0.9 and _film_moved < _elapsed * 1.1)


func _trust_cases() -> void:
	_reset()
	await _check_with("http://127.0.0.1:%d/ok/wrongsig/" % _port)
	_check("wrong signature: ignored, no download (%s)" % up.last_result, up.last_result.contains("does not verify")
			and _package_requests().is_empty() and up.state == "idle")
	_reset()
	await _check_with("http://127.0.0.1:%d/ok/tampered/" % _port)
	_check("changed latest.json: ignored, no download", up.last_result.contains("does not verify")
			and _package_requests().is_empty())
	_reset()
	_write(up.state_dir.path_join("bad-versions"), "1.1.0\n".to_utf8_buffer())
	await _check_with("http://127.0.0.1:%d/ok/ok/" % _port)
	_check("bad version: skipped, no download (%s)" % up.last_result, up.last_result.contains("rolled back")
			and _package_requests().is_empty())
	DirAccess.remove_absolute(up.state_dir.path_join("bad-versions"))
	_reset()
	up.installed = "1.1.0"
	await _check_with("http://127.0.0.1:%d/ok/ok/" % _port)
	_check("same version: nothing to do (%s)" % up.last_result, up.last_result.contains("is the newest")
			and _package_requests().is_empty())
	_reset()
	# VERSION "version abc1234" reads as no release number.
	up.installed = Core.installed_version("version abc1234\n")
	_check("a commit-named install: no check at all", not up.check_now() and _requests().is_empty())


func _staged_ok(what: String) -> void:
	var new_dir: String = up.staging_dir.path_join("new")
	_check("%s: staged (%s)" % [what, up.last_result], up.state == "ready" and up.staged_version == "1.1.0")
	_check("%s: new.complete says 1.1.0" % what, Core.read_text(up.staging_dir.path_join("new.complete")) == "1.1.0\n")
	_check("%s: new/ is the package, executable kept" % what,
			Core.installed_version(Core.read_text(new_dir.path_join("VERSION"))) == "1.1.0"
			and _sh("test -x '%s/run.sh' && test -x '%s/bin/framecine-engine'" % [new_dir, new_dir]) == 0
			and FileAccess.file_exists(new_dir.path_join("app/blob.bin")))
	_check("%s: the .part and the unpack folder are gone" % what,
			not FileAccess.file_exists(up.staging_dir.path_join("package.part"))
			and not DirAccess.dir_exists_absolute(up.staging_dir.path_join("unpack")))


func _download_cases() -> void:
	var size := FileAccess.open(_root.path_join("pkg.tar.gz"), FileAccess.READ).get_length()
	var part: String = _tmp.path_join("staging/package.part")
	# The whole path, plain.
	_reset()
	await _check_with("http://127.0.0.1:%d/ok/ok/" % _port)
	_staged_ok("plain")
	_smooth("plain download and stage")
	_check("plain: no second check while staged", not up.check_now())
	# Cut at half, then continued from there.
	_reset()
	await _check_with("http://127.0.0.1:%d/ok/half/" % _port)
	var kept := FileAccess.open(part, FileAccess.READ).get_length() if FileAccess.file_exists(part) else -1
	_check("cut: a quiet failure, half kept (%d of %d; %s)" % [kept, size, up.last_result], up.state == "idle"
			and up.last_result.begins_with("Update download failed:") and kept == size / 2)
	await _check_with("http://127.0.0.1:%d/ok/half/" % _port)
	var pr := _package_requests()
	_check("cut: the next check asks for the rest (%s)" % [pr], pr.size() == 2 and pr[0].ends_with("range=-")
			and pr[1].ends_with("range=bytes=%d-" % (size / 2)))
	_staged_ok("cut and continued")
	# No bytes for a while: stops, keeps what it has.
	_reset()
	up.stall_timeout = 1.5
	await _check_with("http://127.0.0.1:%d/ok/stall/" % _port)
	kept = FileAccess.open(part, FileAccess.READ).get_length() if FileAccess.file_exists(part) else -1
	_check("stall: stops after the stall time (%.1f s, %s)" % [_elapsed, up.last_result], up.state == "idle"
			and up.last_result.contains("no data") and _elapsed < 5.0 and kept == size / 2)
	_smooth("stall")
	await _check_with("http://127.0.0.1:%d/ok/stall/" % _port)
	_staged_ok("stall and continued")
	# A .part of another version starts again from 0.
	_reset()
	DirAccess.make_dir_recursive_absolute(up.staging_dir)
	_write(part, "x".repeat(1000).to_utf8_buffer())
	_write(part + ".json", JSON.stringify({"version": "0.9.0", "sha256": "1".repeat(64), "size": 5}).to_utf8_buffer())
	await _check_with("http://127.0.0.1:%d/ok/ok/" % _port)
	pr = _package_requests()
	_check("other version's .part: deleted, the download from 0 (%s)" % [pr], pr.size() == 1
			and pr[0].ends_with("range=-"))
	_staged_ok("other version's .part")
	# A wrong hash: the package is deleted and nothing is staged.
	_reset()
	await _check_with("http://127.0.0.1:%d/ok/wronghash/" % _port)
	_check("wrong hash: nothing staged, the package deleted (%s)" % up.last_result, up.state == "idle"
			and up.last_result.contains("SHA-256") and not FileAccess.file_exists(part)
			and not DirAccess.dir_exists_absolute(up.staging_dir.path_join("new")))
	# A redirect, as GitHub sends from /releases/latest/download/.
	_reset()
	await _check_with("http://127.0.0.1:%d/redirect/ok/" % _port)
	_staged_ok("redirect")


func _stage_cases() -> void:
	# A package without a top folder.
	_reset()
	await _check_with("http://127.0.0.1:%d/ok/flat/" % _port)
	_staged_ok("no top folder")
	# An engine that does not start here: nothing is staged.
	_reset()
	await _check_with("http://127.0.0.1:%d/ok/badengine/" % _port)
	_check("engine does not start: nothing staged (%s)" % up.last_result, up.state == "idle"
			and up.last_result.contains("does not start")
			and not DirAccess.dir_exists_absolute(up.staging_dir.path_join("new"))
			and not FileAccess.file_exists(up.staging_dir.path_join("new.complete")))
	# A new/ left half way (no new.complete) is replaced.
	_reset()
	_write(up.staging_dir.path_join("new/leftover.txt"), "x".to_utf8_buffer())
	await _check_with("http://127.0.0.1:%d/ok/ok/" % _port)
	_staged_ok("a half new/ before")
	_check("a half new/ before: its files are gone",
			not FileAccess.file_exists(up.staging_dir.path_join("new/leftover.txt")))
	_reset()
