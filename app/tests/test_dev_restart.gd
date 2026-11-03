extends SceneTree

## PC audio and the watch party restart cleanly (app-shell's report): a start while one runs replaces it under the
## same node name, also twice in one frame, and the party's new host gets the UDP port of the old one.
## godot --headless --xr-mode off --path app --script res://tests/test_dev_restart.gd

const PCAudio := preload("res://scripts/dev/pc_audio.gd")
const WatchParty := preload("res://scripts/party/watch_party.gd")

var main: Node3D
var _fails := 0


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main  # the nodes find main as the current scene, as in the app
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _named(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for c in root.get_children():
		if str(c.name).begins_with(prefix):
			out.append(str(c.name))
	return out


func _run() -> void:
	await _frames(3)
	# PC audio to a closed local port: the node lives and retries; only names and lifetimes matter here.
	var a := PCAudio.start(main, "127.0.0.1:47999")
	_check(PCAudio.instance() == a, "pc audio: instance() finds a node not added yet")
	await _frames(2)
	_check(a.is_inside_tree() and str(a.name) == PCAudio.NODE_NAME, "pc audio: added under its name")
	var b := PCAudio.start(main, "127.0.0.1:47998")
	_check(not a.is_inside_tree(), "pc audio: the old node leaves the tree at once")
	await _frames(2)
	_check(_named("PCAudio") == [PCAudio.NODE_NAME] and PCAudio.instance() == b, "pc audio: restart keeps the name (%s)"
			% [_named("PCAudio")])
	PCAudio.start(main, "127.0.0.1:47997")
	var d := PCAudio.start(main, "127.0.0.1:47996")  # twice in one frame
	await _frames(2)
	_check(_named("PCAudio") == [PCAudio.NODE_NAME] and PCAudio.instance() == d and d.get("port") == 47996,
			"pc audio: two starts in a frame leave the second (%s)" % [_named("PCAudio")])
	PCAudio.stop()
	PCAudio.start(main, "127.0.0.1:47995")
	PCAudio.stop()  # stopped before it was added
	await _frames(2)
	_check(_named("PCAudio").is_empty() and PCAudio.instance() == null, "pc audio: stop before the add leaves none")

	var h := WatchParty.host(main, "A", "", 47893)
	await _frames(2)
	_check(h.is_inside_tree() and str(h.get("role")) == "host", "party: host up")
	var h2 := WatchParty.host(main, "B", "", 47893)  # same port, at once
	await _frames(2)
	_check(_named("WatchParty") == [WatchParty.NODE_NAME] and WatchParty.instance() == h2,
			"party: rehost keeps the name (%s)" % [_named("WatchParty")])
	_check(str(h2.get("role")) == "host", "party: the new host got the UDP port of the old one")
	WatchParty.join(main, "C", "127.0.0.1:47893")
	var j := WatchParty.join(main, "D", "127.0.0.1:47893")
	await _frames(2)
	_check(_named("WatchParty") == [WatchParty.NODE_NAME] and WatchParty.instance() == j,
			"party: two joins in a frame leave the second (%s)" % [_named("WatchParty")])
	WatchParty.leave()
	await _frames(2)
	_check(_named("WatchParty").is_empty(), "party: leave removes it")

	print("test_dev_restart: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)
