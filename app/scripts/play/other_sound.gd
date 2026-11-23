extends RefCounted

## The sound of other programs (a browser on the screen), quiet while the microphone records (scripts/dev/
## push_to_talk.gd): their sound never passes through the app, so the dip of the app's own bus does not reach it, and
## the microphone heard the page over the speaker (the user, 2026-11-23). hush(true) mutes every other program's
## playing stream at the headset's sound server (pactl); hush(false) unmutes the ones it muted, and only those: a
## stream the viewer had muted stays so. Off the main thread, one call after the other in order. Linux with pactl
## only; elsewhere nothing happens.
##
##   hush(on)
##   targets(json_text) -> Array[int]   the streams to mute, from `pactl -f json list sink-inputs` (tests)

const OWN := "FrameCine"

static var _muted: Array[int] = []
static var _task := -1
static var _tool := -1


static func available() -> bool:
	if _tool < 0:
		_tool = 0
		if OS.get_name() == "Linux":
			for dir: String in OS.get_environment("PATH").split(":", false):
				if FileAccess.file_exists(dir.path_join("pactl")):
					_tool = 1
					break
	return _tool == 1


static func hush(on: bool) -> void:
	if not available():
		return
	# In order: an unmute never overtakes the mute before it.
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
	_task = WorkerThreadPool.add_task(_mute_now if on else _unmute_now)


static func _mute_now() -> void:
	var out: Array = []
	if OS.execute("pactl", ["-f", "json", "list", "sink-inputs"], out) != 0 or out.is_empty():
		return
	for index in targets(str(out[0])):
		if OS.execute("pactl", ["set-sink-input-mute", str(index), "1"]) == 0 and not index in _muted:
			_muted.append(index)


static func _unmute_now() -> void:
	for index in _muted:
		OS.execute("pactl", ["set-sink-input-mute", str(index), "0"])
	_muted.clear()


## Other programs' streams that sound now: not the app's own, not the sound server's inner ones (no program named),
## not one already muted.
static func targets(json_text: String) -> Array[int]:
	var found: Array[int] = []
	var list: Variant = JSON.parse_string(json_text)
	if not (list is Array):
		return found
	for e: Variant in list:
		if not (e is Dictionary) or bool((e as Dictionary).get("mute", false)):
			continue
		var props: Variant = (e as Dictionary).get("properties")
		var app := str((props as Dictionary).get("application.name", "")) if props is Dictionary else ""
		if app == "" or app == OWN or str((props as Dictionary).get("application.process.binary", "")).contains("framecine"):
			continue
		found.append(int((e as Dictionary).get("index", -1)))
	return found
