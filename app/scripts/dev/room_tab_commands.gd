extends RefCounted

## The Room tab's controls as commands (ui/room_tab.gd; docs/dev/assistant-coverage/room-system.md): the room, the
## seat, the floor reflection, the effects, the time of day, the room light, the showing and the sleep timer. Each
## handler calls what the tab's control calls, then syncs the tab. Registered by command_host.gd for every client of
## the registry; "assistant" in a spec is the consumer level that reaches it (scripts/assistant/assistant_commands.gd).
## The room document (scripts/assistant/room_*.gd) has its own commands.
##
## A change command takes only what it changes: a parameter left out stays as it is.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const EnvLibrary := preload("res://scripts/env/env_library.gd")
const TimeOfDay := preload("res://scripts/env/time_of_day.gd")

## The sleep timer's choices, as the tab shows them: off, 15 / 30 / 60 / 90 minutes, the end of the file.
const SLEEP_CHOICES := ["off", "15", "30", "60", "90", "end_of_file"]

## scripts/dev/command_host.gd
var host: Node


func _main() -> Node:
	return host.main if host != null and is_instance_valid(host.main) else null


func register_all() -> void:
	var R := DevCommands
	R.register("room_settings", _cmd_room_settings, {
		"description": "Everything the Room tab shows: the room and the rooms to pick from, the seat, the floor "
				+ "reflection, the effects, the time of day, the room light, the showing and the sleep timer.",
		"returns": "{environment, environments, seat, reflection, bias_light, react, projector_beam, time_of_day, "
				+ "room_light, dim_while_playing, showing, sleep, this_room: [{name, type, label, description, common, "
				+ "schema (JSON Schema of its value), default, value}]}",
		"assistant": "read"})
	R.register("room_setting", _cmd_room_setting, {
		"description": "One of this room's own settings (room_settings' this_room lists them, each with a JSON Schema "
				+ "of its value: every room has dim, ambience_db and, where they have an effect, life, ritual, "
				+ "flicker and motion; a room's document adds its own), or every one of them back to its default "
				+ "with reset (the room's own seat too). Kept per room.",
		"params": [{"name": "name", "type": "string", "default": "",
				"description": "The setting's name, from room_settings' this_room."},
				{"name": "value", "type": "any", "default": null,
				"description": "Its new value, as its schema says: true or false, a number in its range, or a choice."},
				{"name": "reset", "type": "bool", "default": false,
				"description": "Every setting of this room back to its default (name and value left out)."}],
		"level": "change", "returns": "{this_room}", "assistant": "room"})
	R.register("set_environment", _cmd_set_environment, {
		"description": "Changes the room around the screen (as a row of the Room tab's Environment list).",
		"params": [{"name": "id", "type": "string", "required": true,
				"description": "The room's id, from room_settings' environments (the list changes as rooms are added)."}],
		"level": "control", "returns": "{environment, name}", "assistant": "room"})
	R.register("use_picture_as_room", _cmd_use_picture, {
		"description": "Makes the picture on show a photo room and shows it at once (only a picture on the headset, "
				+ "not on a share).",
		"level": "change", "returns": "{environment}", "assistant": "room"})
	R.register("seat", _cmd_seat, {
		"description": "Moves the viewer to a seat of the room (a short fade, never a slide), the next or the previous "
				+ "one, or the room's own spot.",
		"params": [{"name": "to", "type": "string", "required": true,
				"description": "A seat's name from room_settings' seat.names, or next, previous or own (the room's own "
				+ "spot)."}],
		"level": "control", "returns": "{seat, index, count, moved, names}", "assistant": "control"})
	R.register("floor_reflection", _cmd_reflection, {
		"description": "The screen's reflection in the floor, in rooms with a floor for it.",
		"params": [{"name": "on", "type": "bool", "description": "Shows the reflection (true) or hides it (false)."},
				{"name": "strength", "type": "float", "description": "How strong it is, 0 to 0.6."}],
		"level": "change", "returns": "the reflection's state", "assistant": "room"})
	R.register("bias_light", _cmd_bias, {
		"description": "The bias light: a soft glow behind the screen in the film's colours.",
		"params": [{"name": "on", "type": "bool", "description": "Turns the bias light on (true) or off (false)."},
				{"name": "strength", "type": "float", "description": "How bright it is, 0 to 1."}],
		"level": "change", "returns": "the bias light's state", "assistant": "room"})
	R.register("react_to_film", _cmd_react, {
		"description": "The room reacts to the film: it pulses with the bass, and rooms that opt in flash with loud "
				+ "moments.",
		"params": [{"name": "on", "type": "bool", "description": "Turns the reaction on (true) or off (false)."},
				{"name": "strength", "type": "float", "description": "How strong the reaction is, 0 to 1."}],
		"level": "change", "returns": "the reaction's state", "assistant": "room"})
	R.register("projector_beam", _cmd_beam, {
		"description": "Shows or hides the projector's beam of light over the viewer's head, with dust in it.",
		"params": [{"name": "on", "type": "bool", "required": true,
				"description": "Shows the beam (true) or hides it (false)."}],
		"level": "change", "returns": "{on}", "assistant": "room"})
	R.register("time_of_day", _cmd_time_of_day, {
		"description": "The sky's time of day in outdoor rooms: a fixed night, dusk or day, or the sun where it is now.",
		"params": [{"name": "mode", "type": "string", "enum": TimeOfDay.MODES,
				"description": "night, dusk or day, or clock for the sun's place now (the tab's Now)."},
				{"name": "latitude", "type": "float",
				"description": "The latitude for clock, -90 to 90 degrees (north is positive)."}],
		"level": "change", "returns": "{mode, latitude}", "assistant": "room"})
	R.register("room_light", _cmd_room_light, {
		"description": "The room's light (remembered for each room).",
		"params": [{"name": "level", "type": "float", "required": true,
				"description": "0 is dark, 1 is as the room was made, 2 is twice as bright."}],
		"level": "change", "returns": "{room_light}", "assistant": "room"})
	R.register("dim_while_playing", _cmd_dim, {
		"description": "Whether the room light dims while the film plays, and how far.",
		"params": [{"name": "on", "type": "bool", "description": "Dims while playing (true) or not (false)."},
				{"name": "level", "type": "float",
				"description": "The light while playing, 0 to 1 of the room light."}],
		"level": "change", "returns": "{on, level}", "assistant": "room"})
	R.register("curtains", _cmd_curtains, {
		"description": "Curtains that open when the film starts and close when it ends (in the cinema and the home "
				+ "theatre, on a flat screen).",
		"params": [{"name": "on", "type": "bool", "required": true,
				"description": "Turns the curtains on (true) or off (false)."}],
		"level": "change", "returns": "{on, available}", "assistant": "room"})
	R.register("up_next", _cmd_up_next, {
		"description": "The countdown to the next file at the end of one.",
		"params": [{"name": "on", "type": "bool", "description": "Turns the countdown on (true) or off (false)."},
				{"name": "seconds", "type": "float", "description": "How long it counts down, 3 to 30 seconds."}],
		"level": "change", "returns": "{on, seconds}", "assistant": "room"})
	R.register("intermission", _cmd_intermission, {
		"description": "An intermission near the middle of a long film with chapters.",
		"params": [{"name": "on", "type": "bool", "description": "Turns the intermission on (true) or off (false)."},
				{"name": "minutes", "type": "float", "description": "How long it lasts, 1 to 20 minutes."}],
		"level": "change", "returns": "{on, minutes, at, active}", "assistant": "room"})
	R.register("crossfade", _cmd_crossfade, {
		"description": "The crossfade into the next file; 0 is a plain cut.",
		"params": [{"name": "music_seconds", "type": "float", "description": "Between music files, 0 to 12 seconds."},
				{"name": "video_seconds", "type": "float", "description": "Between films, 0 to 10 seconds."}],
		"level": "change", "returns": "{music_seconds, video_seconds}", "assistant": "room"})
	R.register("sleep_timer", _cmd_sleep, {
		"description": "The sleep timer: playback fades out and pauses after a time, or at the end of the file; then "
				+ "the film stays paused, the app closes, or the headset turns off (then).",
		"params": [{"name": "set", "type": "string", "enum": SLEEP_CHOICES,
				"description": "off, a number of minutes (15, 30, 60 or 90), or end_of_file (default: as it is)."},
				{"name": "then", "type": "string", "enum": ["pause", "close", "off"],
				"description": "What happens once the film has paused: pause (stays paused), close (the app closes) "
				+ "or off (the headset turns off); remembered."}],
		"level": "control", "returns": "{active, end_of_file, remaining, status}", "assistant": "control"})
	R.register("time_travel", _cmd_time_travel, {
		"description": "Time travel through television: while the film plays, the room moves forward through the "
				+ "TV rooms, oldest set to newest, an era at a time; the film plays on.",
		"params": [{"name": "on", "type": "bool", "required": true,
				"description": "Starts it (true; in a room that isn't a TV era, the first era at once) or stops it."},
				{"name": "minutes", "type": "int", "enum": [0, 5, 10, 15],
				"description": "Minutes in each era; 0 spreads them over the rest of the film (default: the last)."},
				{"name": "advance", "type": "bool",
				"description": "true: the next era now (with on true)."}],
		"level": "change", "returns": "{active, minutes, remaining, era, eras}", "assistant": "room"})


# --- Reads -------------------------------------------------------------------------------------------------------

func _cmd_room_settings(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
	return room_settings(_main())


func _cmd_room_setting(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var rs: Node = m.features.room_settings
	var before: Dictionary = rs.values()
	if bool(args.get("reset", false)):
		rs.reset()
		ctx.summary = "this room's settings back to their defaults"
	else:
		var n := str(args.get("name", ""))
		if n == "":
			return ctx.fail("give name and value, or reset: true")
		var why: String = rs.set_value(n, args.get("value"))
		if why != "":
			return ctx.fail(why)
		ctx.summary = "%s: %s" % [n.replace("_", " "), str(rs.value(n))]
	_sync_tab()
	ctx.undo = func() -> void:
		for k: String in before:
			rs.set_value(k, before[k])
		_sync_tab()
	return {"this_room": rs.schema()}


static func room_settings(m: Node) -> Dictionary:
	var f: Node = m.features
	var envs: Array = []
	for e: Array in m.get_environment_list():
		envs.append({"id": str(e[0]), "name": str(e[1])})
	var showing := {"curtains": bool(f.preshow.enabled), "curtains_available": bool(f.preshow.available()),
			"up_next": bool(f.up_next.enabled), "up_next_seconds": float(f.up_next.seconds),
			"intermission": bool(f.intermission.enabled), "intermission_minutes": float(f.intermission.minutes),
			"intermission_active": bool(f.intermission.active),
			"crossfade_music_seconds": float(f.crossfade.music_seconds),
			"crossfade_video_seconds": float(f.crossfade.video_seconds)}
	return {
		"environment": m.env_id, "environments": envs,
		"use_picture_available": _picture_shown(m),
		"seat": _seat_state(m),
		"reflection": {"available": bool(f.reflection.available()), "on": bool(f.reflection.enabled),
				"strength": snappedf(float(f.reflection.strength), 0.01)},
		"bias_light": {"on": bool(f.bias.enabled), "strength": snappedf(float(f.bias.strength), 0.01)},
		"react": {"on": bool(f.react.enabled), "strength": snappedf(float(f.react.strength), 0.01),
				"room_flashes": bool(f.react.room_opts_in())},
		"projector_beam": bool(f.projector.beam),
		"time_of_day": {"available": _has_time_of_day(m), "mode": str(f.time_of_day.mode),
				"latitude": float(f.time_of_day.latitude)},
		"room_light": snappedf(float(m.room_light), 0.01),
		"dim_while_playing": {"on": bool(f.light_follow.enabled), "level": snappedf(float(f.light_follow.play_level), 0.01)},
		"showing": showing,
		"sleep": _sleep_state(m),
		"time_travel": _time_travel_state(m),
		"this_room": f.room_settings.schema(),
	}


static func _seat_state(m: Node) -> Dictionary:
	var seat: Node = m.features.seat
	var names: Array = seat.names()
	var at := int(seat.seat)
	return {"seat": names[at] if at >= 0 and at < names.size() else null, "index": at, "count": names.size(),
			"moved": bool(seat.moved), "names": names}


static func _sleep_state(m: Node) -> Dictionary:
	var sleep: Node = m.features.sleep
	return {"active": bool(sleep.active), "end_of_file": bool(sleep.end_of_file),
			"remaining": snappedf(float(sleep.remaining()), 1.0), "status": sleep.status_text(),
			"then": str(sleep.then)}


static func _time_travel_state(m: Node) -> Dictionary:
	var tt: Node = m.features.time_travel
	return {"active": bool(tt.active), "minutes": int(tt.minutes), "remaining": snappedf(float(tt.remaining()), 1.0),
			"era": str(m.env_id) if str(m.env_id) in tt.eras() else "", "eras": tt.eras()}


static func _picture_shown(m: Node) -> bool:
	return bool(m.features.slideshow.is_picture()) and not str(m.current_path).begins_with("smb://")


static func _has_time_of_day(m: Node) -> bool:
	return m.env != null and m.env.has_method("set_time_of_day")


## The Room tab shows the change (its sync() reads every row again; it skips while its name or PIN form is open).
func _sync_tab() -> void:
	var m := _main()
	var layer: Node = m.get("ui") if m != null else null
	var pane: Node = layer.get("ui") if layer != null else null
	var tab: Node = pane.get("room") if pane != null else null
	if tab != null and tab.has_method("sync"):
		tab.sync()


## A change command with nothing to change.
static func _none(args: Dictionary, ctx: DevCommands.Call, keys: Array) -> bool:
	for k: String in keys:
		if args.has(k):
			return false
	ctx.fail("give %s" % " or ".join(keys))
	return true


static func _percent(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


# --- The room and the seat -------------------------------------------------------------------------------------------

func _cmd_set_environment(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var id: String = args["id"]
	var label := ""
	for e: Array in m.get_environment_list():
		if str(e[0]) == id:
			label = str(e[1])
	if label == "":
		return ctx.fail("no room %s (room_settings lists the environments)" % id)
	var old: String = m.env_id
	m.set_environment(id)
	_sync_tab()
	ctx.summary = "room: %s" % label
	# An assistant's room that was never kept has no id to come back to.
	if not old.begins_with("assistant:") and old != id:
		ctx.undo = func() -> void:
			_main().set_environment(old)
			_sync_tab()
	return {"environment": m.env_id, "name": label}


func _cmd_use_picture(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	if not _picture_shown(m):
		return ctx.fail("no picture on show (only a picture on the headset can be a room)")
	# What the tab's "Use this picture as the room" does.
	var id := EnvLibrary.add_skybox(m.current_path)
	if id == "":
		return ctx.fail("this picture can't be a room (only local pictures)")
	var old: String = m.env_id
	m.set_environment(id)
	_sync_tab()
	ctx.summary = "room: this picture"
	if not old.begins_with("assistant:"):
		ctx.undo = func() -> void:
			_main().set_environment(old)
			_sync_tab()
	return {"environment": m.env_id}


func _cmd_seat(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var seat: Node = m.features.seat
	var names: Array = seat.names()
	if names.is_empty():
		return ctx.fail("this room has no seats")
	var old := int(seat.seat)
	var to := str(args["to"]).strip_edges()
	var index := -1
	match to.to_lower():
		"next":
			index = posmod(old + 1, names.size()) if old >= 0 else 0
		"previous":
			index = posmod(old - 1, names.size()) if old >= 0 else names.size() - 1
		"own":
			index = -1
		_:
			index = names.find(to)
			if index < 0:
				for i in names.size():
					if str(names[i]).to_lower() == to.to_lower():
						index = i
			if index < 0:
				return ctx.fail("no seat %s here (the seats: %s)" % [to, ", ".join(names)])
	# What the seat plan, Default seat and the laser's pick do: the fade, then the move.
	seat.go_to_seat(index)
	_sync_tab()
	ctx.summary = "seat: %s" % (names[index] if index >= 0 else "the room's own spot")
	ctx.undo = func() -> void:
		_main().features.seat.go_to_seat(old)
		_sync_tab()
	var out := _seat_state(m)
	# In the headset the move happens behind the fade, a moment after the reply.
	out["to"] = names[index] if index >= 0 else null
	return out


# --- The effects ---------------------------------------------------------------------------------------------------

func _cmd_reflection(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "strength"]):
		return null
	var r: Node = _main().features.reflection
	if not bool(r.available()):
		return ctx.fail("this room has no floor for a reflection")
	var was := [bool(r.enabled), float(r.strength)]
	if args.has("strength"):
		r.set_strength(clampf(float(args["strength"]), 0.0, 0.6))
	if args.has("on"):
		r.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "floor reflection %s" % (_percent(r.strength) if r.enabled else "off")
	ctx.undo = func() -> void:
		r.set_strength(was[1])
		r.set_enabled(was[0])
		_sync_tab()
	return {"on": bool(r.enabled), "strength": snappedf(float(r.strength), 0.01)}


func _cmd_bias(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "strength"]):
		return null
	var b: Node = _main().features.bias
	var was := [bool(b.enabled), float(b.strength)]
	if args.has("strength"):
		b.set_strength(clampf(float(args["strength"]), 0.0, 1.0))
	if args.has("on"):
		b.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "bias light %s" % (_percent(b.strength) if b.enabled else "off")
	ctx.undo = func() -> void:
		b.set_strength(was[1])
		b.set_enabled(was[0])
		_sync_tab()
	return {"on": bool(b.enabled), "strength": snappedf(float(b.strength), 0.01)}


func _cmd_react(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "strength"]):
		return null
	var r: Node = _main().features.react
	var was := [bool(r.enabled), float(r.strength)]
	if args.has("strength"):
		r.set_strength(clampf(float(args["strength"]), 0.0, 1.0))
	if args.has("on"):
		r.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "react to the film %s" % (_percent(r.strength) if r.enabled else "off")
	ctx.undo = func() -> void:
		r.set_strength(was[1])
		r.set_enabled(was[0])
		_sync_tab()
	return {"on": bool(r.enabled), "strength": snappedf(float(r.strength), 0.01),
			"room_flashes": bool(r.room_opts_in())}


func _cmd_beam(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var p: Node = _main().features.projector
	var was := bool(p.beam)
	p.set_beam(bool(args["on"]))
	_sync_tab()
	ctx.summary = "projector beam %s" % ("on" if p.beam else "off")
	ctx.undo = func() -> void:
		p.set_beam(was)
		_sync_tab()
	return {"on": bool(p.beam)}


func _cmd_time_of_day(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["mode", "latitude"]):
		return null
	var m := _main()
	if not _has_time_of_day(m):
		return ctx.fail("this room has no sky that changes (outdoor rooms only)")
	var t: Node = m.features.time_of_day
	var was := [str(t.mode), float(t.latitude)]
	if args.has("latitude"):
		t.set_latitude(clampf(float(args["latitude"]), -90.0, 90.0))
	if args.has("mode"):
		t.set_mode(str(args["mode"]))
	_sync_tab()
	ctx.summary = "time of day: %s" % ("now" if t.mode == "clock" else t.mode)
	ctx.undo = func() -> void:
		t.set_latitude(was[1])
		t.set_mode(was[0])
		_sync_tab()
	return {"mode": str(t.mode), "latitude": float(t.latitude)}


func _cmd_room_light(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var old: float = m.room_light
	m.set_room_light(clampf(float(args["level"]), 0.0, 2.0))
	_sync_tab()
	ctx.summary = "room light %s" % _percent(m.room_light)
	var env := str(m.env_id)
	ctx.undo = func() -> void:
		var mm := _main()
		if str(mm.env_id) == env:
			mm.set_room_light(old)
			_sync_tab()
	return {"room_light": snappedf(float(m.room_light), 0.01)}


func _cmd_dim(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "level"]):
		return null
	var f: Node = _main().features.light_follow
	var was := [bool(f.enabled), float(f.play_level)]
	if args.has("level"):
		f.set_play_level(clampf(float(args["level"]), 0.0, 1.0))
	if args.has("on"):
		f.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "dim while playing %s" % (_percent(f.play_level) if f.enabled else "off")
	ctx.undo = func() -> void:
		f.set_play_level(was[1])
		f.set_enabled(was[0])
		_sync_tab()
	return {"on": bool(f.enabled), "level": snappedf(float(f.play_level), 0.01)}


# --- The showing ---------------------------------------------------------------------------------------------------

func _cmd_curtains(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var p: Node = _main().features.preshow
	var was := bool(p.enabled)
	p.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "curtains %s" % ("on" if p.enabled else "off")
	ctx.undo = func() -> void:
		p.set_enabled(was)
		_sync_tab()
	return {"on": bool(p.enabled), "available": bool(p.available())}


func _cmd_up_next(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "seconds"]):
		return null
	var u: Node = _main().features.up_next
	var was := [bool(u.enabled), float(u.seconds)]
	if args.has("seconds"):
		u.set_seconds(clampf(float(args["seconds"]), 3.0, 30.0))
	if args.has("on"):
		u.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "up next %s" % ("%d s" % roundi(u.seconds) if u.enabled else "off")
	ctx.undo = func() -> void:
		u.set_seconds(was[1])
		u.set_enabled(was[0])
		_sync_tab()
	return {"on": bool(u.enabled), "seconds": float(u.seconds)}


func _cmd_intermission(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["on", "minutes"]):
		return null
	var i: Node = _main().features.intermission
	var was := [bool(i.enabled), float(i.minutes)]
	if args.has("minutes"):
		i.set_minutes(clampf(float(args["minutes"]), 1.0, 20.0))
	if args.has("on"):
		i.set_enabled(bool(args["on"]))
	_sync_tab()
	ctx.summary = "intermission %s" % ("%d min" % roundi(i.minutes) if i.enabled else "off")
	ctx.undo = func() -> void:
		i.set_minutes(was[1])
		i.set_enabled(was[0])
		_sync_tab()
	var at: float = i.point() if i.enabled else -1.0
	return {"on": bool(i.enabled), "minutes": float(i.minutes), "at": snappedf(at, 0.1) if at >= 0.0 else null,
			"active": bool(i.active)}


func _cmd_crossfade(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	if _none(args, ctx, ["music_seconds", "video_seconds"]):
		return null
	var c: Node = _main().features.crossfade
	var was := [float(c.music_seconds), float(c.video_seconds)]
	if args.has("music_seconds"):
		c.set_music_seconds(clampf(roundf(float(args["music_seconds"])), 0.0, 12.0))
	if args.has("video_seconds"):
		c.set_video_seconds(clampf(roundf(float(args["video_seconds"])), 0.0, 10.0))
	_sync_tab()
	ctx.summary = "crossfade: music %d s, films %d s" % [roundi(c.music_seconds), roundi(c.video_seconds)]
	ctx.undo = func() -> void:
		c.set_music_seconds(was[0])
		c.set_video_seconds(was[1])
		_sync_tab()
	return {"music_seconds": float(c.music_seconds), "video_seconds": float(c.video_seconds)}


# --- The sleep timer --------------------------------------------------------------------------------------------------

func _cmd_time_travel(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var tt: Node = m.features.time_travel
	var was := [bool(tt.active), int(tt.minutes), str(m.env_id)]
	if tt.eras().is_empty():
		return ctx.fail("no TV rooms to travel through")
	if bool(args["on"]):
		var minutes := int(args.get("minutes", tt.minutes))
		if not (minutes in tt.CHOICES):
			return ctx.fail("minutes: 0 (over the film), 5, 10 or 15")
		tt.start(minutes)
		if bool(args.get("advance", false)):
			tt.advance()
		ctx.summary = "time travel: %s, in %s" % ["over the film" if tt.minutes == 0 else "every %d min" % tt.minutes,
				m.env_id]
	else:
		tt.stop()
		ctx.summary = "time travel off"
	_sync_tab()
	ctx.undo = func() -> void:
		if str(m.env_id) != was[2]:
			m.set_environment(was[2])
		if was[0]:
			tt.start(was[1])
		else:
			tt.stop()
			tt.minutes = was[1]
		_sync_tab()
	return _time_travel_state(m)


func _cmd_sleep(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var m := _main()
	var sleep: Node = m.features.sleep
	var was := [bool(sleep.active), bool(sleep.end_of_file), float(sleep.remaining()), str(sleep.then)]
	if not args.has("set") and not args.has("then"):
		return ctx.fail("give set, then or both")
	if args.has("then"):
		sleep.set_then(str(args["then"]))
	# What the tab's choices do.
	match str(args.get("set", "")):
		"":
			pass
		"off":
			sleep.cancel()
		"end_of_file":
			sleep.start_end_of_file()
		var minutes:
			sleep.start(float(minutes))
	_sync_tab()
	ctx.summary = "sleep timer: %s" % (sleep.status_text() if sleep.active else "off")
	ctx.undo = func() -> void:
		sleep.set_then(str(was[3]))
		if not args.has("set"):
			pass
		elif not was[0]:
			sleep.cancel()
		elif was[1]:
			sleep.start_end_of_file()
		else:
			sleep.start(maxf(ceilf(was[2] / 60.0), 1.0))
		_sync_tab()
	return _sleep_state(m)
