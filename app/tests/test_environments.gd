extends SceneTree

## Every environment document passes the checks (docs/environments.md, "The checks"): every app/environments/*.env.json
## is built headless and checked for its schema, the headset budget (measured), a clear sight line from every seat,
## comfort, licences, names and no people. Prints each room's figures.
## godot --headless --xr-mode off --path app --script res://tests/test_environments.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const EnvLibrary := preload("res://scripts/env/env_library.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://environments"):
		if f.ends_with(".env.json"):
			files.append(f)
	_check("rooms as documents: %s" % [files], files.has("cinema.env.json") and files.has("void.env.json"))
	for f in files:
		var r := EnvDoc.load_file("res://environments/" + f)
		var doc: Dictionary = r["doc"]
		_check("%s: schema (%s)" % [f, r["errors"]], (r["errors"] as Array).is_empty())
		if doc.is_empty():
			continue
		var s := EnvChecks.static_checks(doc)
		for k: String in s:
			_check("%s: %s %s" % [f, k, s[k]], (s[k] as Array).is_empty())
		var room: Node3D = EnvRoom.new()
		room.doc = doc
		root.add_child(room)
		await process_frame
		var stats := EnvChecks.measure(room)
		print("  %s: %s" % [f, stats])
		var over := EnvChecks.budget(stats)
		_check("%s: within the headset's budget %s" % [f, over], over.is_empty())
		var blocked: Array = await EnvChecks.sight_line(self, room)
		_check("%s: a clear sight line from every seat (%d seats) %s" % [f, maxi(room.get_seats().size(), 1),
				blocked], blocked.is_empty())
		room.queue_free()
		await process_frame
	# A room that ships as its document alone is listed and built from it; the cinema and the Void have scenes.
	var listed: Array = EnvLibrary.document_rooms().map(func(e: Array) -> String: return str(e[0]))
	_check("document rooms: listed without the rooms that have scenes %s" % [listed],
			not listed.has("cinema") and not listed.has("void"))
	var ids: Array = EnvLibrary.environments().map(func(e: Array) -> String: return str(e[0]))
	_check("document rooms: in the environment list", listed.all(func(i: String) -> bool: return ids.has(i)))
	var built: Node3D = EnvLibrary.instantiate(["void_doc", "Void", "res://environments/void.env.json", []])
	root.add_child(built)
	await process_frame
	_check("document rooms: an entry's document builds an env_room with its systems",
			built.get_script() == EnvRoom and built.get_node_or_null("Systems") != null)
	built.queue_free()
	await process_frame
	print("test_environments: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
