extends SceneTree

## The updater's own parts (scripts/update/, docs/framedrop.md "Our own updates"): versions, the installed VERSION,
## latest.json's checks, the signature against a real openssl signature (and a wrong key, a changed byte, junk), the
## bad-version list, the prompt rule (never during a film) in the real main scene, the question in the footer, the
## restart state and its restore, the relauncher's command, the started marker, and the System row.
## No network: test_update_net.gd has the server cases.
## godot --headless --xr-mode off --path app --script res://tests/test_update.gd

const Core := preload("res://scripts/update/update_core.gd")
const Fetch := preload("res://scripts/update/update_fetch.gd")
const Updater := preload("res://scripts/update/updater.gd")

var main: Node3D
var _failures := 0
var _checks := 0
var _tmp := ""


func _init() -> void:
	_tmp = "/tmp/vrvp-update-test-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_tmp)
	_test_versions()
	_test_latest()
	_test_signature()
	_test_bad_versions()
	_test_prompt_rule()
	_test_urls()
	_test_relauncher()
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


## The updater looks at the prompt rule four times a second.
func _seconds(s: float) -> void:
	await create_timer(s).timeout
	await process_frame


func _test_versions() -> void:
	_check("parse 1.4.0", Core.parse_version("1.4.0") == [1, 4, 0])
	for bad in ["1.4", "1.4.0.1", "v1.4.0", "1.x.0", "", "1..0", "+1.2.3", "1.2.-3", "1.2.3-rc1"]:
		_check("parse rejects %s" % bad, Core.parse_version(bad).is_empty())
	_check("newer patch", Core.is_newer("0.1.1", "0.1.0"))
	_check("newer minor beats patch", Core.is_newer("0.2.0", "0.1.9"))
	_check("numbers, not text: 0.10.0 after 0.9.0", Core.is_newer("0.10.0", "0.9.0"))
	_check("equal is not newer", not Core.is_newer("1.0.0", "1.0.0"))
	_check("older is not newer", not Core.is_newer("0.9.9", "1.0.0"))
	_check("unparseable compares equal (no update)", Core.compare("junk", "1.0.0") == 0
			and not Core.is_newer("2.0.0", ""))
	_check("VERSION: plain", Core.installed_version("version 0.1.0\narch arm64\n") == "0.1.0")
	_check("VERSION: a v and a describe tail", Core.installed_version("version v0.3.2-4-gabc1234\n") == "0.3.2")
	_check("VERSION: a commit name is no release", Core.installed_version("version abc1234-dirty\n") == "")
	_check("VERSION: empty", Core.installed_version("") == "")


func _latest(fields: Dictionary) -> PackedByteArray:
	var d := {"version": "0.2.0", "tag": "v0.2.0", "notes": "Faster menus.",
			"package": {"url": "https://example.com/framecine-0.2.0-arm64.tar.gz", "size": 61234567,
					"sha256": "ab".repeat(32)}}
	for k: String in fields:
		if k.begins_with("package."):
			d["package"][k.trim_prefix("package.")] = fields[k]
		else:
			d[k] = fields[k]
	return JSON.stringify(d).to_utf8_buffer()


func _test_latest() -> void:
	var l := Core.parse_latest(_latest({}))
	_check("latest: the fields (%s)" % [l], l.get("version") == "0.2.0" and l.get("size") == 61234567
			and l.get("sha256") == "ab".repeat(32) and l.get("notes") == "Faster menus." and l.get("tag") == "v0.2.0")
	_check("latest: a long note is cut to one line", str(Core.parse_latest(_latest({"notes": "a\nb" + "c".repeat(300)}))
			.get("notes")).length() == 200 and not "\n" in str(Core.parse_latest(_latest({"notes": "a\nb"}))["notes"]))
	for bad: Dictionary in [{"version": "0.2"}, {"version": "v0.2.0"}, {"package.url": "file:///x.tar.gz"},
			{"package.size": -1}, {"package.size": 1.5}, {"package.size": "12"}, {"package.sha256": "AB".repeat(32)},
			{"package.sha256": "ab".repeat(31)}, {"package.sha256": "0x" + "ab".repeat(31)}, {"package": 3}]:
		_check("latest: rejects %s" % [bad], Core.parse_latest(_latest(bad)).has("error"))
	_check("latest: not JSON", Core.parse_latest("nope".to_utf8_buffer()).has("error"))
	_check("latest: too large", Core.parse_latest(_big()).has("error"))


func _big() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(Core.MAX_LATEST_BYTES + 1)
	b.fill(32)
	return b


func _sh(cmd: String) -> int:
	return OS.execute("bash", ["-c", cmd], [], true)


func _test_signature() -> void:
	if _sh("command -v openssl > /dev/null") != 0:
		_check("openssl is there for the signature tests", false)
		return
	var key := _tmp.path_join("key.pem")
	var pub := _tmp.path_join("pub.pem")
	var other := _tmp.path_join("other.pem")
	var other_pub := _tmp.path_join("other.pub.pem")
	var data := _tmp.path_join("latest.json")
	_sh("openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out '%s' 2>/dev/null" % key)
	_sh("openssl pkey -in '%s' -pubout -out '%s'" % [key, pub])
	_sh("openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out '%s' 2>/dev/null" % other)
	_sh("openssl pkey -in '%s' -pubout -out '%s'" % [other, other_pub])
	var bytes := _latest({})
	var f := FileAccess.open(data, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	_sh("openssl dgst -sha256 -sign '%s' -out '%s.sig' '%s'" % [key, data, data])
	var sig := FileAccess.get_file_as_bytes(data + ".sig")
	_check("signature: openssl's signature is 256 bytes", sig.size() == 256)
	_check("signature: openssl's signature verifies", Core.verify(bytes, sig, pub))
	_check("signature: not with another key", not Core.verify(bytes, sig, other_pub))
	var changed := bytes.duplicate()
	changed[10] = changed[10] ^ 1
	_check("signature: not over a changed byte", not Core.verify(changed, sig, pub))
	var cut := sig.slice(0, 255)
	_check("signature: not a cut signature", not Core.verify(bytes, cut, pub))
	_check("signature: not an empty one", not Core.verify(bytes, PackedByteArray(), pub))
	_check("signature: not junk", not Core.verify(bytes, "x".repeat(256).to_utf8_buffer(), pub))
	_check("signature: no key file, no trust", not Core.verify(bytes, sig, _tmp.path_join("missing.pem")))
	# The round trip the other way: Godot's own signature verifies with openssl.
	var ck := CryptoKey.new()
	ck.load(key)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var own := Crypto.new().sign(HashingContext.HASH_SHA256, ctx.finish(), ck)
	var own_path := _tmp.path_join("own.sig")
	var g := FileAccess.open(own_path, FileAccess.WRITE)
	g.store_buffer(own)
	g.close()
	_check("signature: Godot's own signature verifies with openssl", _sh(
			"openssl dgst -sha256 -verify '%s' -signature '%s' '%s' > /dev/null" % [pub, own_path, data]) == 0)
	_check("signature: both are the same PKCS#1 v1.5 bytes", own == sig)


func _test_bad_versions() -> void:
	var bad := Core.bad_versions("0.2.0\n\n 0.3.0 \n0.2.0\n")
	_check("bad versions: one each, trimmed (%s)" % [bad], bad == PackedStringArray(["0.2.0", "0.3.0"]))
	_check("bad versions: none", Core.bad_versions("").is_empty())


func _test_prompt_rule() -> void:
	var base := {"staged": true, "declined": false, "menu_shown": true, "has_source": false, "ended": false}
	_check("prompt: menu open, nothing playing", Core.may_prompt(base))
	_check("prompt: never during a film (open, not ended)",
			not Core.may_prompt(base.merged({"has_source": true}, true)))
	_check("prompt: at the end of the film", Core.may_prompt(base.merged({"has_source": true, "ended": true}, true)))
	_check("prompt: not with the menu closed", not Core.may_prompt(base.merged({"menu_shown": false}, true)))
	_check("prompt: not with the menu closed at the end", not Core.may_prompt(base.merged(
			{"menu_shown": false, "has_source": true, "ended": true}, true)))
	_check("prompt: not before anything is staged", not Core.may_prompt(base.merged({"staged": false}, true)))
	_check("prompt: not after Later", not Core.may_prompt(base.merged({"declined": true}, true)))


func _test_urls() -> void:
	var u := Fetch.split_url("https://github.com/a/b/releases/latest/download/latest.json")
	_check("url: https", u.get("tls") == true and u.get("host") == "github.com" and u.get("port") == 443
			and u.get("path") == "/a/b/releases/latest/download/latest.json")
	var v := Fetch.split_url("http://127.0.0.1:8123/ok/x?y=1")
	_check("url: a port and a query", v.get("tls") == false and v.get("port") == 8123 and v.get("path") == "/ok/x?y=1")
	_check("url: no credentials", Fetch.split_url("https://user:pw@example.com/x").is_empty())
	_check("url: not ftp", Fetch.split_url("ftp://example.com/x").is_empty())
	_check("redirect: absolute", Fetch.resolve("https://a.com/x/y", "https://b.com/z") == "https://b.com/z")
	_check("redirect: from the root", Fetch.resolve("http://a.com:81/x/y", "/z") == "http://a.com:81/z")
	_check("redirect: relative", Fetch.resolve("https://a.com/x/y", "z") == "https://a.com:443/x/z")


func _test_relauncher() -> void:
	var a := Updater.relauncher_args(4242, "12345678901234567890")
	var joined := " ".join(a)
	_check("relauncher: a collected user unit (%s)" % joined, a[0] == "--user" and "--collect" in a
			and "--unit=framecine-restart-4242" in a)
	var script := a[a.size() - 1]
	_check("relauncher: waits for this process, then Steam's rungameid (%s)" % script,
			script.begins_with("while kill -0 4242 2>/dev/null;")
			and script.ends_with("exec steam steam://rungameid/12345678901234567890"))
	_check("relauncher: no $, quote, backtick or backslash in any argument (OS.execute runs them through popen)",
			Array(a).all(func(s: String) -> bool: return Updater.shell_safe(s)))
	# The path that failed on the headset: OS.execute with output. Every argument comes back as it went in.
	if OS.get_name() == "Linux":
		var out := []
		var code := OS.execute("printf", ["%s\n"] + Array(a), out, true)
		var back := str(out[0]).trim_suffix("\n").split("\n") if not out.is_empty() else PackedStringArray()
		_check("relauncher: the arguments pass OS.execute unchanged (%d; %s)" % [code, script],
				code == 0 and back == a)
	_check("game id: a library shortcut's 64-bit id", Updater.is_game_id("13009753868613976064"))
	_check("game id: not empty, not text, not a script", not Updater.is_game_id("")
			and not Updater.is_game_id("12a") and not Updater.is_game_id("1; rm -rf ~")
			and not Updater.is_game_id("-5") and not Updater.is_game_id("123456789012345678901"))
	_check("relauncher: a bad game id never reaches the script",
			Updater.relauncher_args(1, "1; reboot")[-1].ends_with("rungameid/0"))
	_check("environment: a value with a quote or $ is left out", not Updater.shell_safe('a"b')
			and not Updater.shell_safe("$HOME") and Updater.shell_safe("/usr/local/bin:/usr/bin"))
	_check("relauncher: no SteamGameId in this test run, so no restart through Steam",
			OS.get_environment("SteamGameId") != "" or not Updater.can_restart())


func _run() -> void:
	await _frames(5)
	var up: Node = main.features.update
	_check("feature: in the hub", up != null and up is Updater)
	_check("feature: no timed check from a run in the repository", not up.auto and up.install_dir == "")
	_check("feature: on by default", up.enabled == true)
	await _test_prompt_in_app(up)
	await _test_restore(up)
	_test_marker(up)
	await _test_row(up)
	OS.execute("rm", ["-rf", _tmp])
	print("update: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(_failures)


func _toast_text() -> String:
	var t: Label = main.ui.ui._toast_label
	return t.text if main.ui.ui._toast.visible else ""


func _test_prompt_in_app(up: Node) -> void:
	up.install_dir = _tmp
	up.state = "ready"
	up.staged_version = "0.2.0"
	up.latest = {"version": "0.2.0", "notes": "Faster menus."}
	main.ui.hide_panel()
	main.ui.ui.hide_toast()
	main.open_path("stub://flat_mono")
	await _frames(5)
	main.ui.show_panel()
	await _seconds(0.5)
	_check("app: menu over a playing film: no question", _toast_text() == "")
	main.player.pause()
	main.ui.hide_panel()
	await _seconds(0.5)
	main.ui.show_panel()
	await _seconds(0.5)
	_check("app: menu over a paused film: no question (%s)" % _toast_text(), _toast_text() == "")
	main.ui.hide_panel()
	main.close_media()
	await _seconds(0.5)
	main.ui.show_panel()
	await _seconds(0.5)
	var t := _toast_text()
	_check("app: menu with nothing open: the question with the notes (%s)" % t,
			t == "Quit now to update to 0.2.0? Then start the player again.  Faster menus.")
	_check("app: the buttons are Quit and Later", main.ui.ui._toast_button.text == "Quit"
			and main.ui.ui._toast_button2.text == "Later")
	main.ui.ui._toast_button2.pressed.emit()
	_check("app: Later is remembered for this run", up.declined)
	main.ui.hide_panel()
	await _seconds(0.5)
	main.ui.show_panel()
	await _seconds(0.5)
	_check("app: no second question after Later", _toast_text() == "")
	up.declined = false
	up.state = "idle"
	up.staged_version = ""
	# The notices: downloading, and ready.
	main.ui.ui.hide_toast()
	main.ui.show_panel()
	await _seconds(0.3)
	_check("notice: downloading, in the footer with the menu open", up.notice("Downloading version 0.2.0")
			and _toast_text() == "Downloading version 0.2.0")
	main.ui.ui.hide_toast()
	main.open_path("stub://flat_mono")
	await _frames(5)
	_check("notice: none while a film plays", not up.notice("Downloading version 0.2.0") and _toast_text() == "")
	main.player.pause()
	up.latest = {"version": "0.2.0"}
	up._on_staged({"ok": true, "engine": "test"})
	await _seconds(0.5)
	t = _toast_text()
	_check("notice: ready, over a paused film (no question there) (%s)" % t,
			t == "Version 0.2.0 is downloaded. It installs when you say yes in the menu.")
	main.close_media()
	main.ui.ui.hide_toast()
	# Check now (System, Updates): its answer is a notice.
	up.state = "idle"
	up._by_hand = true
	up._on_checked({"error": "test"})
	await _seconds(0.3)
	t = _toast_text()
	_check("check now: a failure says so (%s)" % t, t == "Could not check for updates. Try again later.")
	main.ui.ui.hide_toast()
	up._on_checked({"error": "test"})
	await _seconds(0.3)
	_check("a timed check's failure: no notice", _toast_text() == "")
	up.state = "ready"
	_check("check now with a version ready: the ready notice", up.check_by_hand()
			and _toast_text() == "Version 0.2.0 is downloaded. It installs when you say yes in the menu.")
	main.ui.ui.hide_toast()
	# The yes: run.sh swaps only with new.approved naming the staged version (tools/test_player_run.sh).
	var keep_staging: String = up.staging_dir
	up.staging_dir = _tmp.path_join("staging")
	var approved: String = up.staging_dir.path_join(Updater.APPROVED)
	_check("yes: written with the staged version", up.approve()
			and Core.read_text(approved) == "0.2.0\n")
	up.staged_version = ""
	DirAccess.remove_absolute(approved)
	_check("yes: nothing staged, nothing written", not up.approve() and not FileAccess.file_exists(approved))
	up.staging_dir = keep_staging
	up.state = "idle"
	up.latest = {}
	up.install_dir = ""
	main.ui.hide_panel()


func _test_restore(up: Node) -> void:
	main.open_path("stub://flat_mono")
	await _frames(5)
	main.player.seek(42.0)
	main.player.pause()
	await _frames(3)
	var d: Dictionary = up.restart_state()
	_check("restart state: file, position, paused, room (%s)" % [d], d.get("path") == "stub://flat_mono"
			and absf(float(d.get("position", 0.0)) - 42.0) < 0.5 and d.get("paused") == true
			and d.get("env") == main.env_id and int(d.get("saved", 0)) > 0)
	main.close_media()
	await _frames(3)
	_check("restart state: nothing open, the room only", not up.restart_state().has("path"))
	_check("restore: an old state is not used", not up.restore(d.merged({"saved": 1}, true)))
	_check("restore: opens the file", up.restore(d))
	await _frames(10)
	_check("restore: the file is open again at its place, paused (%s at %.1f)" % [main.current_path,
			main.player.get_position()], main.current_path == "stub://flat_mono"
			and absf(main.player.get_position() - 42.0) < 0.5 and not main.player.is_playing())
	main.close_media()
	await _frames(3)


func _test_marker(up: Node) -> void:
	var st := _tmp.path_join("state")
	up.state_dir = st
	up.install_dir = _tmp
	up.installed = "0.2.0"
	up._mark_started()
	_check("marker: none without a swap record", not FileAccess.file_exists(st.path_join("started")))
	Core.write_text(st.path_join("swapped"), "new 0.2.0\nold 0.1.0\nlaunched\n")
	up._mark_started()
	_check("marker: written after a swap", Core.read_text(st.path_join("started")) == "0.2.0\n")
	up.install_dir = ""
	up.state_dir = Core.default_state_dir()
	up.installed = ""


func _test_row(up: Node) -> void:
	var row: Node = main.ui.ui.system.update_row
	_check("row: in the System tab", row != null and row.get_parent() != null)
	_check("row: the check toggle is on", row._toggle.button_pressed)
	_check("row: outside an install it says so", row._status.text == "This copy does not run from an install: no updates.")
	up.install_dir = _tmp
	up.installed = "0.1.0"
	up.state = "ready"
	up.staged_version = "0.2.0"
	up.latest = {"version": "0.2.0", "notes": "Faster menus.", "size": 10}
	up.changed.emit()
	_check("row: ready, with Restart now and the notes (%s)" % row._status.text, row._restart.visible
			and row._status.text == "Version 0.1.0  ·  Version 0.2.0 is downloaded. It installs when you say yes in the menu.\nFaster menus.")
	_check("row: ready, no Check now", not row._check.visible)
	up.state = "checking"
	up.changed.emit()
	_check("row: checking, it says so, no Check now (%s)" % row._status.text, not row._check.visible
			and row._status.text.ends_with("Looking for a new version...\nFaster menus."))
	up.state = "idle"
	up.changed.emit()
	_check("row: idle in an install, Check now", row._check.visible)
	up.state = "ready"
	up.changed.emit()
	row._toggle.button_pressed = false
	_check("row: the toggle turns the check off", up.enabled == false
			and main.settings.get_value("update", "check", true) == false)
	up.set_enabled(true)
	up.state = "idle"
	up.staged_version = ""
	up.install_dir = ""
	up.changed.emit()
	await _frames(1)
	_check("row: idle, no Restart now", not row._restart.visible)
