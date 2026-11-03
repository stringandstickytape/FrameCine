extends RefCounted

## Shared commands for what the built-ins don't cover and voice commands need (docs/dev/voice.md): chapters, subtitles
## on / off, recentring the screen. Registered by command_host.gd, so the PC link, voice and the phone have them.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")


static func register_commands(host: Node) -> void:
	DevCommands.register("chapter", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var ch: Object = _feature(host.main, "chapters")
		if ch == null:
			return ctx.fail("no chapters feature")
		var list: Array = ch.get("chapters")
		if list.is_empty():
			return ctx.fail("this file has no chapters")
		var old: float = host.main.player.get_position()
		var n: int = args["n"]
		var step: int = args["step"]
		if n > 0:
			if n > list.size():
				return ctx.fail("there are %d chapters" % list.size())
			ch.go_to(n - 1)
		elif step > 0:
			ch.next_chapter()
		elif step < 0:
			ch.previous_chapter()
		else:
			return ctx.fail("give n (1 = the first) or step (1 or -1)")
		ctx.summary = "chapter %s" % (str(n) if n > 0 else ("next" if step > 0 else "previous"))
		ctx.undo = func() -> void: host.main.player.seek(old)
		return {"chapters": list.size(), "position": host.main.player.get_position()}, {
		"description": "Goes to chapter n (1 = the first), or the next / previous one with step.",
		"params": [{"name": "n", "type": "int", "default": 0,
				"description": "the chapter to go to, 1 = the first (chapters lists them); 0 to use step"},
				{"name": "step", "type": "int", "default": 0,
				"description": "1: the next chapter; -1: the previous one (or this one's start after 3 s)"}],
		"level": "control", "assistant": "control", "returns": "{chapters, position}"})
	DevCommands.register("subtitles", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var subs: Object = _feature(host.main, "subtitles")
		if subs == null:
			return ctx.fail("no subtitles feature")
		subs.set_enabled(args["on"])
		ctx.summary = "subtitles %s" % ("on" if args["on"] else "off")
		return subs.get_state(), {
		"description": "Subtitles on or off.", "params": [{"name": "on", "type": "bool", "required": true,
				"description": "true shows the subtitle track (the remembered or first one), false hides them"}],
		"level": "control", "assistant": "control", "returns": "the subtitle state"})
	DevCommands.register("recenter", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		host.main.recenter_screen_to_gaze()
		ctx.summary = "screen to where you look"
		return {"yaw_degrees": snappedf(rad_to_deg(host.main.screen_yaw), 0.1)}, {
		"description": "Puts the screen (or the sphere's front) where the head looks.",
		"level": "control", "returns": "{yaw_degrees}"})
	DevCommands.register("chapters", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var ch: Object = _feature(host.main, "chapters")
		if ch == null:
			return ctx.fail("no chapters feature")
		var list: Array = ch.get("chapters")
		var i: int = ch.index_at(host.main.player.get_position()) if not list.is_empty() else -1
		var out: Array = []
		for c: Dictionary in list:
			out.append({"n": int(c["index"]) + 1, "title": str(c["title"]), "start": snappedf(float(c["start"]), 0.01),
					"end": snappedf(float(c["end"]), 0.01)})
		return {"count": list.size(), "current": i + 1, "title": str(list[i]["title"]) if i >= 0 else "",
				"list": out}, {
		"description": "The open file's chapters, and the one playing now (current: 1 = the first, 0 = none). For "
				+ "the watch-along context (tools/listener.py ask).",
		"assistant": "read", "returns": "{count, current, title, list: [{n, title, start, end}]}"})


static func _feature(main: Node, name: String) -> Object:
	if main == null or not ("features" in main) or main.features == null:
		return null
	return main.features.get(name)
