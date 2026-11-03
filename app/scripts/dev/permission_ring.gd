extends Node

## The permission ring for remote changes (idea #23). Every command from the PC passes check() first, by its level
## (dev_commands.gd):
##   read      always.
##   control   playback and view (play, seek, open, volume, screen): unless [dev] remote_changes = "deny".
##   change    settings files, the scene, reloads: when remote_changes = "allow", or inside an allowed window.
##   code      `run`: as change, and only with [dev] remote_code = true or --dev-code.
## [dev] remote_changes is "ask" by default: change-level commands are refused until the user allows them for a while.
## That window is opened by --dev-allow=MINUTES at start, or by allow_for(seconds).
## TODO(app-shell): "hold grip to allow for an hour" calls DevHost.instance().permissions.allow_for(3600) after a
## long grip hold with the pane open; and a System-tab switch for remote_changes.
##
## Every remote change that went through shows a toast in the headset (remote_toast.gd) with its summary, and is
## kept for undo: the `undo` command from the PC, Ctrl+Z on a desktop, or the pane (signal remote_change; undo(id)).

## A remote change went through, was undone, or was refused: {id, summary, command, undoable, t, state}
## (state: "done", "undone", "refused"). For the pane's toast with an Undo button.
signal remote_change(entry: Dictionary)

const RemoteToast := preload("res://scripts/dev/remote_toast.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

## Undo entries kept; older ones are dropped (their cleanup runs).
const HISTORY := 20
const MODES: Array[String] = ["ask", "allow", "deny"]

## scripts/main.gd
var main: Node
var toast: RemoteToast
var _allowed_until_msec := 0
## [{id, summary, command, undo, cleanup, t, state}]
var _history: Array[Dictionary] = []
var _next_id := 1


func _ready() -> void:
	toast = RemoteToast.new()
	toast.name = "RemoteToast"
	add_child(toast)


func set_main(m: Node) -> void:
	main = m
	toast.main = m


## "ask", "allow" or "deny", from [dev] remote_changes.
func mode() -> String:
	var m := str(main.settings.get_value("dev", "remote_changes", "ask")) if main != null else "ask"
	return m if m in MODES else "ask"


## --dev-code on the command line: `run` allowed for this run.
var code_flag := false


func code_allowed() -> bool:
	return code_flag or (main != null and bool(main.settings.get_value("dev", "remote_code", false)))


## Opens a window in which change-level commands are allowed (in "ask" mode).
func allow_for(seconds: float) -> void:
	_allowed_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	print("Remote changes allowed for %d min" % roundi(seconds / 60.0))
	toast.show_text("Remote changes allowed for %d min" % roundi(seconds / 60.0))


func revoke() -> void:
	_allowed_until_msec = 0
	toast.show_text("Remote changes off")


## Seconds left in the allowed window (0: none).
func allowed_seconds() -> float:
	return maxf(0.0, (_allowed_until_msec - Time.get_ticks_msec()) / 1000.0)


func status() -> Dictionary:
	var hist: Array = []
	for e in _history:
		hist.append(_public(e))
	return {"remote_changes": mode(), "allowed_seconds": roundi(allowed_seconds()), "remote_code": code_allowed(),
			"history": hist}


## "" when the call may run, else why not. Local calls (the pane, tests) always may.
func check(ctx: DevCommands.Call, spec: Dictionary) -> String:
	if not ctx.remote:
		return ""
	var level := str(spec.get("level", "read"))
	if ctx.name == "set":
		var setting := str(ctx.args.get("setting", ""))
		level = str(DevCommands.setting_spec(setting).get("level", "change")) if DevCommands.has_setting(setting) \
				else "change"
	if level == "read":
		return ""
	var m := mode()
	var refusal := ""
	if m == "deny":
		refusal = "remote changes are off on the headset ([dev] remote_changes = deny)"
	elif level == "control":
		return ""
	elif level == "code" and not code_allowed():
		refusal = "running code is off on the headset: start with --dev-code, or set [dev] remote_code = true"
	elif m != "allow" and allowed_seconds() <= 0.0:
		refusal = ("%s needs permission on the headset: start with --dev-allow=MINUTES, or set "
				+ "[dev] remote_changes = allow") % ctx.name
	if refusal != "":
		_add({"summary": "refused: %s" % ctx.name, "command": ctx.name, "state": "refused"})
		toast.show_text("Refused remote %s" % ctx.name)
	return refusal


## A remote call went through: toast and undo entry (calls without a summary changed nothing worth showing).
func record(ctx: DevCommands.Call) -> void:
	if not ctx.remote or ctx.summary == "":
		return
	_add({"summary": ctx.summary, "command": ctx.name, "undo": ctx.undo, "cleanup": ctx.cleanup, "state": "done"})
	toast.show_text("Remote: %s" % ctx.summary, ctx.undo.is_valid())


## Undoes entry `id` (-1: the latest that can be undone). Returns "" or why not.
func undo(id := -1) -> String:
	for i in range(_history.size() - 1, -1, -1):
		var e := _history[i]
		if (id == -1 and e["state"] == "done" and (e["undo"] as Callable).is_valid()) or int(e["id"]) == id:
			if e["state"] != "done":
				return "change %d is %s" % [e["id"], e["state"]]
			var u: Callable = e["undo"]
			if not u.is_valid():
				return "change %d (%s) can't be undone" % [e["id"], e["summary"]]
			u.call()
			e["state"] = "undone"
			toast.show_text("Undone: %s" % e["summary"])
			remote_change.emit(_public(e))
			return ""
	return "nothing to undo" if id == -1 else "no change %d" % id


func _add(fields: Dictionary) -> Dictionary:
	var e := {"id": _next_id, "t": Time.get_unix_time_from_system(), "undo": Callable(), "cleanup": Callable()}
	e.merge(fields, true)
	_next_id += 1
	_history.append(e)
	while _history.size() > HISTORY:
		var old: Dictionary = _history.pop_front()
		var c: Callable = old["cleanup"]
		if c.is_valid() and old["state"] == "done":
			c.call()
	remote_change.emit(_public(e))
	return e


static func _public(e: Dictionary) -> Dictionary:
	return {"id": e["id"], "summary": e["summary"], "command": e.get("command", ""), "state": e["state"],
			"undoable": e["state"] == "done" and (e["undo"] as Callable).is_valid(), "t": e["t"]}


func _unhandled_input(event: InputEvent) -> void:
	# Desktop: Ctrl+Z undoes the latest remote change.
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_Z and key.ctrl_pressed:
		var err := undo()
		if err != "":
			toast.show_text(err)
		get_viewport().set_input_as_handled()
