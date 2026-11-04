extends Node

## What a room costs, measured (docs/assistant.md, "Performance"): the GPU and CPU time of the app's own viewport
## (both eyes in XR) per frame, the frame rate held, the video frames the decoder dropped, and the headroom against
## the frame budget (1000 / the display's refresh rate: 13.9 ms at 72 Hz). The static cost cap (RoomSchema.COSTS) is
## the cheap check before a change; this is the truth after it.
##
## One node under the scene root ("RoomPerf", made by ensure()), so it survives `reload app`. It measures only while
## something wants it: an assistant connected (hold), or for KEEP_SECONDS after a GET /perf, a room change or a
## calibration (want). Measuring is the renderer's own timestamp pair around the viewport
## (RenderingServer.viewport_set_measure_render_time): no measurable cost on the software renderer; perf() says how
## long it has been on, so the 60 s window is honest about its history.
##
##   RoomPerf.ensure(tree) -> RoomPerf
##   perf() -> Dictionary                       now: windows of 2 s and 60 s (GET /perf, the perf command)
##   await after_change() -> Dictionary         about AFTER_CHANGE s after a room change is on show, with warnings
##   static await calibrate(main, part, count, arrangement, options) -> Dictionary
##                                              N copies of a part built by the real room builder into a temporary
##                                              node, measured, removed (dev link: perf_calibrate, or run)
##   static verdict(report) -> Array[String]    the guard's warnings
##   static await measure_rooms(main, rooms, levels, options) -> Dictionary
##                                              rooms one after another at each foveation level (dev link:
##                                              perf_rooms; the showrooms, docs/showrooms.md)

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const NODE_NAME := "RoomPerf"
## Measuring stays on this long after the last want().
const KEEP_SECONDS := 120.0
const WINDOW_SHORT := 2.0
const WINDOW_LONG := 60.0
## After a room change: skipped first (shaders compiling, the first frames), then measured up to AFTER_CHANGE.
const SETTLE := 0.5
const AFTER_CHANGE := 2.0
## The guard: less GPU headroom than this (ms) after a change is a warning (not a refusal, yet).
const MARGIN_MS := 3.0
## The frame budget when the display's rate is unknown (the Frame's usual rate).
const DEFAULT_HZ := 72
## A frame rate held: at least this share of the display's rate.
const HELD := 0.97
## Calibration: the baseline and the loaded measurement, seconds each (the caller may give its own).
const CALIBRATE_SECONDS := 3.0
const CALIBRATE_MAX := 400
## Rooms one after another (measure_rooms): the foveation levels, the wait after each change (the room's shaders
## compile, the runtime takes the new level) and the measurement, seconds.
const ROOMS_LEVELS := ["off", "low", "high"]
const ROOMS_SETTLE := 3.0
const ROOMS_SECONDS := 5.0
const Showrooms := preload("res://scripts/env/showrooms.gd")

var _on := false
var _keep_until := 0.0
var _holds := {}
var _since := 0.0
## Per frame: time (s), GPU ms, CPU ms (the viewport's render plus the frame's setup), frame interval ms.
var _t := PackedFloat64Array()
var _gpu := PackedFloat32Array()
var _cpu := PackedFloat32Array()
var _frame := PackedFloat32Array()
## The decoder's dropped-frame count, 4 times a second: [time, total, source id].
var _drops: Array[Array] = []
var _drop_timer := 0.0


static func ensure(tree: SceneTree) -> Node:
	var n := tree.root.get_node_or_null(NODE_NAME)
	if n != null:
		return n
	if tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		return tree.root.get_meta(NODE_NAME)
	n = (load("res://scripts/assistant/room_perf.gd") as GDScript).new()
	n.name = NODE_NAME
	tree.root.set_meta(NODE_NAME, n)
	tree.root.add_child.call_deferred(n)
	return n


## The dev link's commands (scripts/dev/command_host.gd registers them): perf, perf_calibrate and perf_rooms.
static func register_commands(host: Node) -> void:
	var DevCommands := load("res://scripts/dev/dev_commands.gd")
	DevCommands.register("perf", func(_a: Dictionary, _ctx: RefCounted) -> Variant:
			return ensure(host.get_tree()).perf(), {
		"description": "The room's measured cost: GPU and CPU ms per frame over the last 2 s and 60 s, the frame "
				+ "rate held, video frames dropped in the last minute, headroom against the frame budget, whether a "
				+ "film plays (numbers without one are not representative).",
		"assistant": "read",
		"returns": "{gpu_ms, cpu_ms, headroom_ms, budget_ms, fps, dropped_last_minute, film_playing, windows}"})
	DevCommands.register("perf_calibrate", func(a: Dictionary, _ctx: RefCounted) -> Variant:
			return await calibrate(host.main, a["part"], a["count"], a["arrangement"], a["options"]), {
		"description": "Builds count copies of a room part (the room builder's own materials and shaders) into a "
				+ "temporary node in the room on show, measures the GPU for a few seconds against before, removes "
				+ "them and returns the difference. The room document is not touched or saved.",
		"params": [{"name": "part", "type": "object", "required": true, "description": "a room document part"},
				{"name": "count", "type": "int", "default": 20},
				{"name": "arrangement", "type": "string", "default": "grid",
					"description": "grid, ring, line, scatter or stack (all in one place: the overdraw case)"},
				{"name": "options", "type": "object", "default": {},
					"description": "seconds, spacing, radius, center [x, y, z]"}],
		"level": "change", "returns": "{delta_gpu_ms, per_part_ms, baseline, loaded, cost, ms_per_cost}"})
	DevCommands.register("perf_rooms", func(a: Dictionary, ctx: RefCounted) -> Variant:
			var r: Dictionary = await measure_rooms(host.main, _list(a["rooms"]), _list(a["foveation"]), {
				"baseline": a["baseline"], "settle": a["settle"], "seconds": a["seconds"]})
			return ctx.call("fail", r["error"]) if r.has("error") else r, {
		"description": "Measures rooms one after another (the showrooms by default, docs/showrooms.md) at each "
				+ "foveation level: shows the room, sets the level, waits settle s, measures the GPU for seconds s; "
				+ "a baseline room first. Then the room and foveation the viewer had. Takes about (rooms + 1) x levels "
				+ "x (settle + seconds) s: give the dev link's send a long timeout. Play a film first.",
		"params": [{"name": "rooms", "type": "any", "default": ["showrooms"],
					"description": "room ids (room_settings lists them) as a list or comma-separated; showrooms: "
					+ "every showroom"},
				{"name": "foveation", "type": "any", "default": ROOMS_LEVELS,
					"description": "the levels, a list or comma-separated: off, low, medium, high"},
				{"name": "baseline", "type": "string", "default": "void",
					"description": "a room measured first at each level, for the differences; empty for none"},
				{"name": "settle", "type": "float", "default": ROOMS_SETTLE},
				{"name": "seconds", "type": "float", "default": ROOMS_SECONDS}],
		"level": "change", "returns": "{rows: [{room, name, foveation, foveation_applied, gpu_ms, gpu_ms_p95, "
				+ "delta_gpu_ms, cpu_ms, fps, dropped, frames}], table, film_playing, budget_ms, notes}"})


## A list argument: a list, or words separated by commas.
static func _list(v: Variant) -> Array:
	if v is Array:
		return v
	var out: Array = []
	for s in str(v).split(",", false):
		out.append(s.strip_edges())
	return out


## Keeps measuring for `seconds` from now (at least).
func want(seconds := KEEP_SECONDS) -> void:
	_keep_until = maxf(_keep_until, _now() + seconds)
	_start()


## Keeps measuring while `who` holds it (an assistant connected).
func hold(who: Object, on: bool) -> void:
	if on:
		_holds[who.get_instance_id()] = true
		_start()
	else:
		_holds.erase(who.get_instance_id())


func measuring() -> bool:
	return _on


func _start() -> void:
	if _on:
		return
	_on = true
	_since = _now()
	_t.clear()
	_gpu.clear()
	_cpu.clear()
	_frame.clear()
	_drops.clear()
	if is_inside_tree():
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)


func _stop() -> void:
	_on = false
	if is_inside_tree():
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), false)


func _enter_tree() -> void:
	if _on:
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)


func _process(delta: float) -> void:
	if not _on:
		return
	var now := _now()
	for id: int in _holds.keys():
		if not is_instance_id_valid(id):
			_holds.erase(id)
	if now > _keep_until and _holds.is_empty():
		_stop()
		return
	var rid := get_tree().root.get_viewport_rid()
	_t.append(now)
	_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid)
			+ RenderingServer.get_frame_setup_time_cpu())
	_frame.append(delta * 1000.0)
	var cut := 0
	while cut < _t.size() and _t[cut] < now - WINDOW_LONG - 1.0:
		cut += 1
	if cut > 64:
		_t = _t.slice(cut)
		_gpu = _gpu.slice(cut)
		_cpu = _cpu.slice(cut)
		_frame = _frame.slice(cut)
	_drop_timer -= delta
	if _drop_timer <= 0.0:
		_drop_timer = 0.25
		_drops.append([now, dropped_total(), _source_id()])
		while _drops.size() > 2 and float(_drops[0][0]) < now - WINDOW_LONG - 1.0:
			_drops.pop_front()


func _now() -> float:
	return Time.get_ticks_usec() / 1e6


func _main() -> Node:
	return get_tree().current_scene if is_inside_tree() else null


func _source() -> Object:
	var m := _main()
	if m == null or not ("player" in m) or m.player == null:
		return null
	return m.player.source


func _source_id() -> int:
	var s := _source()
	return s.get_instance_id() if s != null else 0


## The decoder's dropped frames since the film opened.
func dropped_total() -> int:
	var s := _source()
	if s == null or not s.has_method("get_stats"):
		return 0
	return int((s.get_stats() as Dictionary).get("frames_dropped", 0))


## Frames dropped between two times (the same film only: a new film starts its count again).
func _dropped_between(from: float, to: float) -> int:
	var n := 0
	for i in range(1, _drops.size()):
		var a: Array = _drops[i - 1]
		var b: Array = _drops[i]
		if float(b[0]) < from or float(a[0]) > to or int(a[2]) != int(b[2]):
			continue
		n += maxi(0, int(b[1]) - int(a[1]))
	return n


## The display's refresh rate now (the XR runtime's, else the screen's), and whether it is known.
func refresh() -> Array:
	var m := _main()
	if m != null and m.get("features") != null and m.features.get("latency") != null:
		var r: int = m.features.latency.refresh_rate()
		if r > 0:
			return [r, true]
	return [DEFAULT_HZ, false]


## Is a film playing (the numbers are representative only then): {playing, kind, path}.
func film() -> Dictionary:
	var m := _main()
	var s := _source()
	if m == null or s == null:
		return {"playing": false, "kind": ""}
	var kind := str(s.get_kind()) if s.has_method("get_kind") else ""
	var playing: bool = m.player.is_playing() and not (kind in ["image", "music"])
	return {"playing": playing, "kind": kind, "path": str(m.get("current_path"))}


## The frames between two times: {gpu_ms, gpu_ms_p95, cpu_ms, frame_ms, fps, frames, seconds}.
func window(from: float, to: float) -> Dictionary:
	var g := PackedFloat32Array()
	var c := 0.0
	var f := 0.0
	var first := INF
	var last := -INF
	for i in _t.size():
		if _t[i] < from or _t[i] > to:
			continue
		g.append(_gpu[i])
		c += _cpu[i]
		f += _frame[i]
		first = minf(first, _t[i])
		last = maxf(last, _t[i])
	var n := g.size()
	if n == 0:
		return {"frames": 0, "seconds": 0.0}
	var sum := 0.0
	for x in g:
		sum += x
	var sorted := g.duplicate()
	sorted.sort()
	var span := maxf(last - first, 0.001)
	return {"gpu_ms": snappedf(sum / n, 0.01), "gpu_ms_p95": snappedf(sorted[mini(n - 1, int(n * 0.95))], 0.01),
			"cpu_ms": snappedf(c / n, 0.01), "frame_ms": snappedf(f / n, 0.01),
			"fps": snappedf((n - 1) / span if n > 1 else 0.0, 0.1), "frames": n, "seconds": snappedf(span, 0.01)}


## Now: the last 2 s and the last 60 s (GET /perf). Starts measuring if it wasn't (and says so).
func perf() -> Dictionary:
	var was := _on
	want()
	var now := _now()
	return _report(window(now - WINDOW_SHORT, now), window(now - WINDOW_LONG, now),
			_dropped_between(now - WINDOW_LONG, now), was)


func _report(short: Dictionary, long: Dictionary, dropped: int, was_on := true) -> Dictionary:
	var r := refresh()
	var budget := 1000.0 / float(r[0])
	var f := film()
	var renderer := DisplayServer.get_name() != "headless"
	var out := {"refresh_hz": r[0], "refresh_known": r[1], "budget_ms": snappedf(budget, 0.01),
			"film_playing": f["playing"], "source": f["kind"], "renderer": renderer,
			"measuring_for_s": snappedf(_now() - _since, 0.1) if _on else 0.0,
			"windows": {"2s": short, "60s": long}, "dropped_last_minute": dropped, "margin_ms": MARGIN_MS}
	if renderer and int(short.get("frames", 0)) > 0:
		out["gpu_ms"] = short["gpu_ms"]
		out["cpu_ms"] = short["cpu_ms"]
		out["fps"] = short["fps"]
		out["headroom_ms"] = snappedf(budget - float(short["gpu_ms"]), 0.01)
		out["frame_rate_held"] = float(short["fps"]) >= float(r[0]) * HELD
	notes(out, was_on)
	return out


static func notes(out: Dictionary, was_on := true) -> void:
	var n: Array[String] = []
	if not bool(out["renderer"]):
		n.append("no renderer (headless): nothing to measure")
	if not bool(out["film_playing"]):
		n.append("no film playing: the numbers are without the decoder and the film's texture, not representative; "
				+ "play one and ask again")
	elif str(out.get("source", "")) == "stub":
		n.append("a test pattern plays, not a decoded film: the decoder's load is missing")
	if not bool(out["refresh_known"]):
		n.append("the display's refresh rate is unknown: the budget assumes %d Hz" % DEFAULT_HZ)
	if not was_on:
		n.append("measuring just started: ask again in a few seconds (the 60 s window fills over a minute)")
	elif float(out["measuring_for_s"]) < WINDOW_LONG:
		n.append("the 60 s window has %.0f s of history" % float(out["measuring_for_s"]))
	if not n.is_empty():
		out["notes"] = n
	if out.has("gpu_ms"):
		out["summary"] = "%.1f ms GPU of %.1f, %d drop%s" % [out["gpu_ms"], out["budget_ms"],
				out.get("dropped", out["dropped_last_minute"]), "" if int(out.get("dropped",
				out["dropped_last_minute"])) == 1 else "s"]


## About AFTER_CHANGE s after a room change is on show (await it right after the change): the frames from SETTLE to
## AFTER_CHANGE, the video frames dropped since the change, and the guard's warnings. Headless: at once, unmeasured.
func after_change() -> Dictionary:
	want()
	var t0 := _now()
	var d0 := dropped_total()
	var s0 := _source_id()
	if DisplayServer.get_name() == "headless":
		var out := _report({"frames": 0, "seconds": 0.0}, {"frames": 0, "seconds": 0.0}, 0)
		out.erase("windows")
		return out
	while _now() < t0 + AFTER_CHANGE and is_inside_tree():
		await get_tree().process_frame
	var now := _now()
	var w := window(t0 + SETTLE, now)
	var dropped := maxi(0, dropped_total() - d0) if _source_id() == s0 else 0
	var out := _report(w, window(now - WINDOW_LONG, now), _dropped_between(now - WINDOW_LONG, now))
	out["dropped"] = dropped
	out["measured"] = "%.1f s to %.1f s after the change" % [SETTLE, now - t0]
	if out.has("gpu_ms"):
		out["summary"] = "after this change: %.1f ms GPU of %.1f, %d drop%s" % [out["gpu_ms"], out["budget_ms"],
				dropped, "" if dropped == 1 else "s"]
	out["warnings"] = verdict(out)
	return out


## The guard: too little headroom, or frames dropped since the change. Warnings, in plain words with the numbers.
static func verdict(r: Dictionary) -> Array[String]:
	var w: Array[String] = []
	var simplify := "simplify the room: fewer or smaller parts, fewer lights or a shorter range, no key shadows, " \
			+ "fewer particles or effects"
	if r.has("headroom_ms") and float(r["headroom_ms"]) < MARGIN_MS:
		w.append("after this change the room takes %.1f ms of the GPU's %.1f ms a frame: %.1f ms left, under the "
				% [r["gpu_ms"], r["budget_ms"], r["headroom_ms"]] + "%.0f ms margin; %s%s" % [MARGIN_MS, simplify,
				"" if bool(r["film_playing"]) else " (no film was playing: with one it is tighter)"])
	if int(r.get("dropped", 0)) > 0:
		w.append("%d video frame%s dropped since this change; %s" % [r["dropped"], " was" if int(r["dropped"]) == 1
				else "s were", simplify])
	return w


# --- Calibration (the lead's measurements on the device) ---------------------------------------------------------

## Where copy i of count goes (room frame, on the floor plane at y), for an arrangement.
static func place(i: int, count: int, arrangement: String, footprint: float, options: Dictionary) -> Vector3:
	# A ring goes round the seat by default; the rest stand ahead of it.
	var c: Vector3 = RoomSchema.vec3(options["center"]) if options.has("center") \
			else (Vector3.ZERO if arrangement == "ring" else Vector3(0, 0, -6))
	var spacing := float(options.get("spacing", footprint + 0.5))
	match arrangement:
		"ring":
			var radius := float(options.get("radius", 10.0))
			var a := TAU * i / maxf(count, 1)
			return c + Vector3(sin(a) * radius, 0, -cos(a) * radius)
		"line":
			return c + Vector3((i - (count - 1) * 0.5) * spacing, 0, 0)
		"scatter":
			var rng := RandomNumberGenerator.new()
			rng.seed = 1234 + i
			var radius := float(options.get("radius", 12.0))
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * radius
			return c + Vector3(sin(a) * d, 0, -cos(a) * d)
		"stack":
			return c
	var cols := ceili(sqrt(float(count)))
	var row := i / cols
	var col := i % cols
	return c + Vector3((col - (cols - 1) * 0.5) * spacing, 0, -(row - (ceili(float(count) / cols) - 1) * 0.5)
			* spacing)


## count copies of a room part, built by the room builder (AssistantRoom._part: the real materials, shaders, effects
## and the room's lighting) into a temporary node in the room on show, measured against before, then removed. The room
## document is not touched or saved. options: seconds (each measurement, default CALIBRATE_SECONDS), spacing, radius,
## center [x, y, z]. Returns {delta_gpu_ms, per_part_ms, baseline, loaded, cost, ms_per_cost, ...} or {error}.
static func calibrate(main: Node, part: Dictionary, count := 20, arrangement := "grid", options := {}) -> Dictionary:
	if main == null or main.get("env") == null:
		return {"error": "no room on show"}
	if count < 1 or count > CALIBRATE_MAX:
		return {"error": "count: 1..%d" % CALIBRATE_MAX}
	if not (arrangement in ["grid", "ring", "line", "scatter", "stack"]):
		return {"error": "arrangement: grid, ring, line, scatter or stack"}
	var p := part.duplicate(true)
	p["name"] = "Calibration"
	var v := RoomSchema.validate({"schema": RoomSchema.VERSION, "parts": [p]}, "patch")
	if not v["ok"]:
		return {"error": "the part has problems", "errors": v["errors"]}
	var RoomEditor := load("res://scripts/assistant/room_editor.gd")
	var assets: Dictionary = RoomEditor.load_assets_now({"parts": [p]})
	if assets.has("error"):
		return {"error": assets["error"]}
	var perf: Node = ensure(main.get_tree())
	perf.want()
	var seconds := clampf(float(options.get("seconds", CALIBRATE_SECONDS)), 0.5, 30.0)
	var tree := main.get_tree()
	await _wait(tree, 0.3)
	var t0: float = perf._now()
	var d0: int = perf.dropped_total()
	await _wait(tree, seconds)
	var base: Dictionary = perf.window(t0, perf._now())
	var dropped_base: int = perf.dropped_total() - d0
	# Build: the room's own lighting for the materials, every copy's assets under its own name.
	var env: Node3D = main.env
	var holder := Node3D.new()
	holder.name = "PerfCalibration"
	var doc: Dictionary = env.get("doc") if env.get("doc") is Dictionary else {}
	AssistantRoom._lighting = AssistantRoom.lighting_of(doc)
	var size: Array = p.get("size", [1.0]) if p.get("size") is Array else [1.0]
	var footprint := 0.0
	for x: Variant in size:
		footprint = maxf(footprint, float(x))
	var y := float(p["position"][1]) if p.get("position") is Array and (p["position"] as Array).size() == 3 \
			else (float(size[1]) * 0.5 if size.size() > 1 else footprint * 0.5)
	var parts: Array = []
	for i in count:
		var q := p.duplicate(true)
		q["name"] = "Calibration %d" % i
		var at := place(i, count, arrangement, footprint, options)
		q["position"] = [at.x, at.y + y, at.z]
		for k in ["images", "alpha", "models"]:
			if (assets.get(k, {}) as Dictionary).has("part:Calibration"):
				assets[k]["part:" + q["name"]] = assets[k]["part:Calibration"]
			if (assets.get(k, {}) as Dictionary).has("Calibration"):
				assets[k][q["name"]] = assets[k]["Calibration"]
		holder.add_child(AssistantRoom._part(q, assets))
		parts.append(q)
	var light: Dictionary = doc.get("light", {}) if doc.get("light") is Dictionary else {}
	if bool(light.get("contact_shadows", true)):
		AssistantRoom._add_contact_shadows(holder, {"parts": parts})
	AssistantRoom._lighting = {}
	var layer := env.get_node_or_null(AssistantRoom.LAYER)
	(layer if layer != null else env).add_child(holder)
	await _wait(tree, SETTLE + 0.5)
	var t1: float = perf._now()
	var d1: int = perf.dropped_total()
	await _wait(tree, seconds)
	var loaded: Dictionary = perf.window(t1, perf._now())
	var dropped_loaded: int = perf.dropped_total() - d1
	holder.queue_free()
	RoomEditor.free_assets({"models": assets.get("models", {})})
	await tree.process_frame
	var cost := RoomSchema.part_cost(p, int((assets.get("models", {}) as Dictionary).get("Calibration", {}).get(
			"triangles", 0))) * count
	var out := {"part": str(p.get("type", "")), "count": count, "arrangement": arrangement, "seconds": seconds,
			"baseline": base, "loaded": loaded, "dropped": {"baseline": dropped_base, "loaded": dropped_loaded},
			"cost": snappedf(cost, 0.01), "film_playing": perf.film()["playing"], "refresh_hz": perf.refresh()[0]}
	if base.has("gpu_ms") and loaded.has("gpu_ms"):
		var delta := float(loaded["gpu_ms"]) - float(base["gpu_ms"])
		out["delta_gpu_ms"] = snappedf(delta, 0.001)
		out["delta_cpu_ms"] = snappedf(float(loaded["cpu_ms"]) - float(base["cpu_ms"]), 0.001)
		out["per_part_ms"] = snappedf(delta / count, 0.0001)
		if cost > 0.0:
			out["ms_per_cost"] = snappedf(delta / cost, 0.0001)
	if not bool(out["film_playing"]):
		out["note"] = "no film playing: measure with one for numbers that count"
	return out


## Rooms measured one after another (docs/showrooms.md, "Measuring"): for each room (the baseline first), shown as
## the Room tab shows it, then at each foveation level (set as the System tab does, but not saved, and kept even while
## the panel shows): wait settle s, measure seconds s. Then the room and the foveation the viewer had. rooms: ids, or
## "showrooms" for every showroom; levels: main.FOVEATION_LEVELS words; options: baseline (a room id, "" for none),
## settle, seconds. Returns {rows: [{room, name, foveation, foveation_applied, gpu_ms, gpu_ms_p95, delta_gpu_ms, cpu_ms,
## fps, frames, dropped}], table (a line per room), film_playing, refresh_hz, budget_ms, renderer, notes} or {error}.
static func measure_rooms(main: Node, rooms: Array, levels: Array, options := {}) -> Dictionary:
	if main == null or not main.has_method("all_environments"):
		return {"error": "no app"}
	var names := {}
	for e: Array in main.all_environments():
		names[str(e[0])] = str(e[1])
	var ids: Array[String] = []
	for r: Variant in rooms:
		if str(r) == "showrooms":
			for e: Array in Showrooms.environments():
				ids.append(str(e[0]))
		elif names.has(str(r)):
			ids.append(str(r))
		else:
			return {"error": "no room %s (room_settings lists them; showrooms: every showroom)" % r}
	var baseline := str(options.get("baseline", "void"))
	if baseline != "":
		if not names.has(baseline):
			return {"error": "no room %s for the baseline" % baseline}
		ids.erase(baseline)
		ids.push_front(baseline)
	if ids.is_empty():
		return {"error": "no rooms to measure"}
	var words: Array = (main.get_script() as GDScript).get_script_constant_map().get("FOVEATION_LEVELS", [])
	for l: Variant in levels:
		if not str(l) in words:
			return {"error": "foveation: %s is not one of %s" % [l, ", ".join(words)]}
	if levels.is_empty():
		return {"error": "foveation: give at least one level"}
	var settle := clampf(float(options.get("settle", ROOMS_SETTLE)), 0.2, 30.0)
	var seconds := clampf(float(options.get("seconds", ROOMS_SECONDS)), 0.2, 60.0)
	var tree: SceneTree = main.get_tree()
	var perf: Node = ensure(tree)
	var was := {"room": str(main.env_id), "foveation": str(main.foveation), "sharp": bool(main.foveation_sharp_panel)}
	var panel_open := bool(main.get("menu_shown"))
	# Not saved: the viewer's own setting comes back at the end, whatever happens to the dev link meanwhile.
	main.foveation_sharp_panel = false
	var rows: Array = []
	for id in ids:
		main.set_environment(id)
		for l: Variant in levels:
			main.foveation = str(l)
			main._update_foveation()
			perf.want()
			await _wait(tree, settle)
			var t0: float = perf._now()
			var d0: int = perf.dropped_total()
			await _wait(tree, seconds)
			var row := {"room": id, "name": names[id], "foveation": str(l), "foveation_applied": _applied(main),
					"dropped": maxi(0, perf.dropped_total() - d0)}
			row.merge(perf.window(t0, perf._now()))
			rows.append(row)
	main.foveation = was["foveation"]
	main.foveation_sharp_panel = was["sharp"]
	main._update_foveation()
	if names.has(was["room"]) and str(main.env_id) != was["room"]:
		main.set_environment(was["room"])
	# Each row against the baseline at the same level.
	var base := {}
	for r: Dictionary in rows:
		if r["room"] == baseline and r.has("gpu_ms"):
			base[r["foveation"]] = float(r["gpu_ms"])
	var table: Array[String] = []
	for id in ids:
		var cells: Array[String] = []
		for r: Dictionary in rows:
			if r["room"] != id:
				continue
			if r.has("gpu_ms") and base.has(r["foveation"]) and id != baseline:
				r["delta_gpu_ms"] = snappedf(float(r["gpu_ms"]) - float(base[r["foveation"]]), 0.01)
			cells.append("%s %s ms%s" % [r["foveation"], r.get("gpu_ms", "?"), " (%+.2f)" % r["delta_gpu_ms"]
					if r.has("delta_gpu_ms") else ""])
		table.append("%s: %s" % [names[id], ", ".join(cells)])
	var hz: Array = perf.refresh()
	var out := {"rows": rows, "table": table, "baseline": baseline, "levels": levels, "settle": settle,
			"seconds": seconds, "film_playing": perf.film()["playing"], "refresh_hz": hz[0],
			"budget_ms": snappedf(1000.0 / float(hz[0]), 0.01), "renderer": DisplayServer.get_name() != "headless",
			"foveation_available": bool(main.foveation_available())}
	var notes: Array[String] = []
	if not bool(out["renderer"]):
		notes.append("no renderer (headless): nothing to measure")
	if not bool(out["film_playing"]):
		notes.append("no film playing: the numbers are without the decoder and the film's texture; play one first")
	if rows.any(func(r: Dictionary) -> bool: return int(r["foveation_applied"]) < 0):
		notes.append("foveation was not applied (no XR, or this build starts without it): the levels are the same")
	if panel_open:
		notes.append("the panel was open: it is in the numbers; close it for the rooms alone")
	if not notes.is_empty():
		out["notes"] = notes
	return out


## The foveation level the runtime has now (0 off .. 3 high), or -1 when it isn't applied.
static func _applied(main: Node) -> int:
	var xr: Object = main.get("foveation_xr")
	if xr == null or not "foveation_level" in xr or not bool(main.foveation_available()):
		return -1
	return int(xr.foveation_level)


static func _wait(tree: SceneTree, seconds: float) -> void:
	var end := Time.get_ticks_usec() / 1e6 + seconds
	while Time.get_ticks_usec() / 1e6 < end:
		await tree.process_frame
