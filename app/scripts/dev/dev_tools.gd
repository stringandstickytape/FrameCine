extends Node

## Dev plumbing: the node that holds the development tools (docs/dev/). Made by dev_host.gd's attach() only when dev
## mode is on (--dev, --listener=, or the [dev] settings), so none of these scripts is even compiled otherwise. It
## lives under the scene tree's root as "DevHost", not under main, so it survives `reload app`; attach() points it at
## the new main. Holds: hot-reload, the link to the PC listener, the command registry's built-ins, screenshots, the
## scene control port and the permission ring.

const HotReload := preload("res://scripts/dev/hot_reload.gd")
const DevLink := preload("res://scripts/dev/dev_link.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const InfoOverlay := preload("res://scripts/info_overlay.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const DevShots := preload("res://scripts/dev/dev_shots.gd")
const SceneCommands := preload("res://scripts/dev/scene_commands.gd")
const PermissionRing := preload("res://scripts/dev/permission_ring.gd")
const RecipeCommands := preload("res://scripts/dev/recipe_commands.gd")
const Stats := preload("res://scripts/dev/stats.gd")

## While playing, a state event this often (position); always on play / pause.
const STATE_PERIOD := 10.0
const BATTERY_PERIOD := 60.0
## screen_changed fires every frame while the screen is dragged: at most this often, plus the final value.
const SCREEN_THROTTLE := 0.5
## Log lines and errors forwarded per frame at most; the rest are counted.
const LOG_PER_FRAME := 200
## The events this node sends, for `describe`: [name, when, data].
const EVENTS: Array = [
	["state", "on connect, on play or pause, every 10 s while playing",
			{"path": "string", "playing": "bool", "position": "s", "duration": "s", "mode": "id",
			"environment": "id", "...": "see control-protocol.md"}],
	["file_opened", "a file opened (path \"\": closed)", {"path": "string", "title": "string", "kind": "string"}],
	["mode_changed", "projection or layout changed", {"mode": "id", "describe": "string", "source": "string"}],
	["environment_changed", "the room changed", {"id": "string", "light": "float"}],
	["screen_changed", "the screen moved or resized (at most every 0.5 s)",
			{"width": "m", "distance": "m", "height_offset": "m", "yaw": "rad"}],
	["settings_changed", "volume, A/V offset or overlay", {"volume": "0..1", "av_offset": "s", "overlay": "bool"}],
	["playback_ended", "the file ended and nothing plays next", {"path": "string"}],
	["session", "XR session state", {"state": "begun|synchronized|visible|focussed|stopping|..."}],
	["battery", "on connect and when it changes (checked every 60 s)", {"percent": "int, -1 = none"}],
	["log", "a line the app printed", {"level": "info|stderr", "text": "string"}],
	["error", "an engine or script error", {"text": "string", "kind": "error|script|shader", "file": "", "line": 0}],
	["warning", "an engine or script warning", {"text": "string", "file": "", "line": 0}],
	["reload", "hot-reload reloaded a file", {"path": "res://...", "kind": "ext", "ok": "bool", "ms": "float"}],
	["screenshot", "the screenshot command saved pictures", {"images": "[{view, path, width, height, camera, fov}]"}],
	["stats", "every N s after `stats every=N`", {"...": "as the stats command returns"}],
	["voice_state", "push-to-talk pressed or let go (docs/dev/voice.md)", {"recording": "bool"}],
	["voice_clip", "push-to-talk let go: the clip", {"wav_b64": "16 kHz mono 16-bit WAV", "seconds": "s",
			"rate": "Hz", "peak": "0..1"}],
	["heartbeat", "every 15 s", {"uptime": "s", "dropped": "events dropped so far"}],
]


## Forwards the engine's log (print, push_error, script errors) to the dev link. Called from any thread, so it only
## queues; dev_host.gd drains the queue on the main thread. Never prints.
class LinkLogger extends Logger:
	var _mutex := Mutex.new()
	var _queue: Array[Dictionary] = []
	var dropped := 0

	func _log_message(message: String, error: bool) -> void:
		_push({"level": "stderr" if error else "info", "text": message.strip_edges(false, true)})

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kinds := ["error", "warning", "script", "shader"]
		_push({"level": "warning" if error_type == ERROR_TYPE_WARNING else "error",
				"kind": kinds[clampi(error_type, 0, 3)], "text": rationale if rationale != "" else code,
				"code": code, "function": function, "file": file, "line": line})

	func _push(entry: Dictionary) -> void:
		_mutex.lock()
		if _queue.size() < 2000:
			_queue.append(entry)
		else:
			dropped += 1
		_mutex.unlock()

	func take(limit: int) -> Array[Dictionary]:
		_mutex.lock()
		var out: Array[Dictionary] = _queue.slice(0, limit)
		_queue = _queue.slice(limit)
		_mutex.unlock()
		return out


## scripts/main.gd
var main: Node
var hot_reload: HotReload
var link: DevLink
var shots: DevShots
var scene_commands: SceneCommands
var recipe_commands: RecipeCommands
## Gates and records remote changes (toast, undo).
var permissions: PermissionRing
## Stats for nerds (the `stats` command and event).
var stats: Stats
var _stats_every := 0.0
var _stats_timer := 0.0
var _logger: LinkLogger
var _state_timer := 0.0
var _battery_timer := 0.0
var _last_battery := -2
var _screen_pending := false
var _screen_sent_at := 0.0
var _connected_main: Node


func _ready() -> void:
	permissions = PermissionRing.new()
	permissions.name = "PermissionRing"
	add_child(permissions)
	permissions.set_main(main)
	permissions.code_flag = bool(get_meta("allow_code", false))
	if float(get_meta("allow_minutes", 0.0)) > 0.0:
		permissions.allow_for(float(get_meta("allow_minutes")) * 60.0)
	if get_meta("want_reload", false):
		ensure_hot_reload()
	var listener: Array = get_meta("listener", ["", 0])
	if str(listener[0]) != "":
		link = DevLink.new()
		link.name = "DevLink"
		link.host = listener[0]
		link.port = listener[1]
		link.hello = _hello()
		link.message_received.connect(_on_message)
		link.connected.connect(func() -> void: link.send_event("state", app_state()))
		add_child(link)
		_logger = LinkLogger.new()
		OS.add_logger(_logger)
		if hot_reload != null:
			hot_reload.reloaded.connect(func(info: Dictionary) -> void: link.send_event("reload", info))
		_connect_xr()
		# Push-to-talk (docs/dev/voice.md): clips go to the PC over this link.
		var ptt: Node = (load("res://scripts/dev/push_to_talk.gd") as GDScript).new()
		ptt.name = "PushToTalk"
		ptt.link = link
		add_child(ptt)
	stats = Stats.new()
	stats.name = "Stats"
	add_child(stats)
	_register_commands()
	_on_main_changed()
	set_process(link != null)


## The hot-reload node; made on first use when dev mode is off (the `reload` command), and then it watches too.
func ensure_hot_reload() -> HotReload:
	if hot_reload == null:
		hot_reload = HotReload.new()
		hot_reload.name = "HotReload"
		hot_reload.main = main
		add_child(hot_reload)
		if link != null:
			hot_reload.reloaded.connect(func(info: Dictionary) -> void: link.send_event("reload", info))
	return hot_reload


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


func _on_main_changed() -> void:
	if hot_reload != null:
		hot_reload.main = main
	if permissions != null:
		permissions.set_main(main)
	if stats != null:
		stats.main = main
	if link == null or main == _connected_main or main == null:
		return
	_connected_main = main
	main.file_opened.connect(func(path: String) -> void:
		link.send_event("file_opened", {"path": path, "title": main.display_title() if path != "" else "",
				"kind": main.player.source.get_kind() if main.player.source != null else "",
				"playlist_index": main.playlist_index, "playlist_size": main.playlist.size(),
				"mode": main.mode.to_id(), "mode_source": main.mode_source}))
	main.mode_changed.connect(func(m: RefCounted, auto_text: String) -> void:
		link.send_event("mode_changed", {"mode": m.to_id(), "describe": m.describe(), "source": main.mode_source,
				"auto": auto_text}))
	main.environment_changed.connect(func(id: String, light: float) -> void:
		link.send_event("environment_changed", {"id": id, "light": light}))
	main.screen_changed.connect(func(_w: float, _d: float, _h: float) -> void: _screen_pending = true)
	main.audio_settings_changed.connect(func() -> void:
		link.send_event("settings_changed", {"volume": main.volume, "av_offset": main.player.av_offset,
				"overlay": main.overlay_on}))
	main.playback_ended.connect(func() -> void: link.send_event("playback_ended", {"path": main.current_path}))
	main.player.playing_changed.connect(func(_p: bool) -> void:
		_state_timer = 0.0
		link.send_event("state", app_state()))


func _connect_xr() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null:
		return
	for s: String in ["session_begun", "session_synchronized", "session_visible", "session_focussed",
			"session_stopping", "session_loss_pending", "instance_exiting"]:
		if xr.has_signal(s):
			xr.connect(s, func() -> void: link.send_event("session", {"state": s.trim_prefix("session_")}))


func _process(delta: float) -> void:
	_drain_log()
	if _stats_every > 0.0:
		_stats_timer += delta
		if _stats_timer >= _stats_every:
			_stats_timer = 0.0
			link.send_event("stats", stats.collect())
	if main == null or not is_instance_valid(main):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _screen_pending and now - _screen_sent_at >= SCREEN_THROTTLE:
		_screen_pending = false
		_screen_sent_at = now
		link.send_event("screen_changed", {"width": main.screen_width, "distance": main.screen_distance,
				"height_offset": main.screen_height_offset, "yaw": main.screen_yaw})
	if main.player.is_playing():
		_state_timer += delta
		if _state_timer >= STATE_PERIOD:
			_state_timer = 0.0
			link.send_event("state", app_state())
	_battery_timer -= delta
	if _battery_timer <= 0.0:
		_battery_timer = BATTERY_PERIOD
		var battery := InfoOverlay.read_battery()
		if battery != _last_battery:
			_last_battery = battery
			link.send_event("battery", {"percent": battery})


func _drain_log() -> void:
	if _logger == null:
		return
	for entry in _logger.take(LOG_PER_FRAME):
		var level: String = entry["level"]
		link.send_event("error" if level == "error" else ("warning" if level == "warning" else "log"), entry)


## What the app is doing now: the `state` event (command_host.gd builds it).
func app_state() -> Dictionary:
	return CommandHost.state_of(main)


func _hello() -> Dictionary:
	var v := Engine.get_version_info()
	return {
		"app": str(ProjectSettings.get_setting("application/config/name")),
		"engine": str(v.get("string", "")),
		"os": OS.get_name(),
		"model": OS.get_model_name(),
		"pid": OS.get_process_id(),
		"app_dir": ProjectSettings.globalize_path("res://"),
		"user_dir": OS.get_user_data_dir(),
		"hot_reload": hot_reload != null,
	}


# --- Commands ----------------------------------------------------------------------------------------------------

func _register_commands() -> void:
	DevCommands.register("ping", _cmd_ping,
			{"description": "Answers at once: checks the link.", "returns": "{pong: unix time, uptime: s}"})
	# The built-in commands live on the shared command host (also used by the phone remote).
	CommandHost.ensure(get_tree())
	shots = DevShots.new()
	shots.host = self
	shots.register_all()
	scene_commands = SceneCommands.new()
	scene_commands.host = self
	scene_commands.register_all()
	recipe_commands = RecipeCommands.new()
	recipe_commands.host = self
	recipe_commands.register_all()
	DevCommands.register("undo", _cmd_undo, {
		"description": "Undoes a remote change (the toast in the headset showed it).",
		"params": [{"name": "id", "type": "int", "default": -1, "description": "a change id; -1 = the latest"}],
		"level": "control", "returns": "the permissions status"})
	DevCommands.register("stats", _cmd_stats, {
		"description": "Stats for nerds: frame times and histogram, video, decoder queue, bitrate, GPU clock, power, "
				+ "thermals, CPU. Rates are measured since the previous call. every > 0 also sends a stats event that "
				+ "often; 0 stops it.",
		"params": [{"name": "every", "type": "float", "default": -1.0, "description": "seconds; -1 leaves it as is"}],
		"returns": "{render, frames, video, gpu, battery, thermal, cpu}"})
	DevCommands.register("permissions", _cmd_permissions, {"description": "The permission ring: mode, seconds left in the allowed window, and recent remote changes.",
		"returns": "{remote_changes, allowed_seconds, remote_code, history: [{id, summary, state, undoable}]}"})
	for e: Array in EVENTS:
		DevCommands.register_event(e[0], e[1], e[2])


func _cmd_stats(args: Dictionary, _ctx: RefCounted) -> Variant:
	var every: float = args["every"]
	if every >= 0.0:
		_stats_every = maxf(every, 0.25) if every > 0.0 else 0.0
		_stats_timer = 0.0
	var d := stats.collect()
	d["every"] = _stats_every
	return d


func _cmd_permissions(_args: Dictionary, _ctx: RefCounted) -> Variant:
	return permissions.status()


func _cmd_undo(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var err := permissions.undo(args["id"])
	if err != "":
		return ctx.fail(err)
	return permissions.status()


func _cmd_ping(_args: Dictionary, _ctx: RefCounted) -> Variant:
	return {"pong": Time.get_unix_time_from_system(), "uptime": Time.get_ticks_msec() / 1000.0}


func _on_message(msg: Dictionary) -> void:
	var id: Variant = msg.get("id")
	if id is float and id == floorf(id):
		id = int(id)  # JSON numbers arrive as floats; answer with the id as sent.
	var command := str(msg.get("cmd", ""))
	if command == "":
		link.send_reply(id, false, null, "no cmd")
		return
	var args: Variant = msg.get("args", {})
	if args is Array:
		args = _positional(command, args)
	if not (args is Dictionary):
		link.send_reply(id, false, null, "args must be an object or a list")
		return
	var r: Dictionary = await DevCommands.execute(command, args, true, permissions)
	if r["ok"]:
		permissions.record(r["call"])
	link.send_reply(id, r["ok"], r.get("result"), str(r.get("error", "")))


## A list of arguments, in the order of the command's params, as an object.
static func _positional(command: String, values: Array) -> Variant:
	var params: Array = DevCommands.get_spec(command).get("params", [])
	if values.size() > params.size():
		return "too many arguments for %s" % command
	var out := {}
	for i in values.size():
		out[params[i]["name"]] = values[i]
	return out
