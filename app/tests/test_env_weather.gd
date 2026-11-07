extends SceneTree

## The weather system (scripts/env/systems/weather.gd; docs/environments.md, "Atmosphere and weather") in a small test
## room (a hall with half its ceiling open): rain falls through two areas as GPU particles inside the particle budget,
## shared by floor area; a pane takes drops; a puddle reflects the film; the cycle runs clear, drizzle, rain, clearing,
## clear; the room's Weather setting turns it off or holds it at rain through a map; a cue's shower and clear-up; the
## channels weather.rain, weather.snow and weather.wet follow, and another system's parameter can follow them; snow in
## place of rain; no sound of its own; the room passes the checks. No main scene.
## godot --headless --xr-mode off --path app --script res://tests/test_env_weather.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const Weather := preload("res://scripts/env/systems/weather.gd")
const ScreenFrame := preload("res://scripts/env/systems/screen_frame.gd")

var _failures := 0
var _checks := 0
var _states: Array[String] = []


func _init() -> void:
	_run.call_deferred()


static func test_doc() -> Dictionary:
	return {"schema": 4, "name": "Rain test", "room": {"ambient": 0.05, "screen_glow": 1.0},
		"screen": {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]},
		"systems": [{"system": "light", "params": {"accent": {"bind": "weather.wet", "range": [0.0, 1.0],
				"smooth": 1.0}}},
			{"system": "auditorium", "id": "hall", "params": {"ceiling_cover": 0.5}},
			{"system": "screen_frame"},
			{"system": "weather", "params": {
				"mode": {"bind": "setting.weather", "map": {"changing": "changing", "rain": "heavy", "clear": "clear"}},
				"cycle_minutes": 4.0, "cycle_start": 0.0, "change_seconds": 6.0, "dry_minutes": 0.5,
				"areas": [{"min": [-9.0, -1.0, -3.0], "max": [9.0, 8.5, 5.5]},
						{"min": [-1.5, -3.0, -12.5], "max": [1.5, 8.5, -10.5]}],
				"particles": 1500, "pane": true, "pane_center": [9.5, 2.5, 0.0], "pane_yaw": -90.0,
				"pane_size": [1.6, 1.2], "puddle": true, "puddle_center": [0.0, -3.0, -11.5]}}],
		"settings": [{"name": "weather", "type": "choice", "choices": ["changing", "rain", "clear"],
			"labels": ["Changing", "Rain", "Clear"], "default": "changing", "label": "Weather",
			"description": "Rain now and then, rain all the time, or none."}],
		"cues": [{"name": "drip", "when": {"signal": "weather.rain", "above": 0.5, "for": 2}, "states": ["playing"],
			"steps": [{"wait": 1.0}]}]}


func _build(doc: Dictionary) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	room.host.auto = false
	room.host.on_screen_changed(room.get_screen_anchor(), Vector2(12.0, 5.0))
	return room


func _steps(host: Node, seconds: float, delta := 0.25) -> void:
	for i in int(round(seconds / delta)):
		host.step(delta)


func _run() -> void:
	var s := Registry.spec("weather")
	_check("registered, kind atmosphere", Registry.has("weather") and s["kind"] == "atmosphere")
	_check("its channels are known", Weather.CHANNELS.all(func(c: String) -> bool: return EnvDoc.CHANNELS.has(c)))
	var doc := test_doc()
	var v := EnvDoc.validate(doc)
	_check("the test room validates: a mode mapped from a setting, a binding and a cue on its channels (%s)"
			% [v["errors"]], v["ok"])
	var bad := test_doc()
	bad["systems"][0]["params"]["accent"]["bind"] = "weather.fog"
	_check("an unknown weather channel refused", not EnvDoc.validate(bad)["ok"])
	var st := EnvChecks.static_checks(doc)
	for k: String in st:
		_check("static check %s %s" % [k, st[k]], (st[k] as Array).is_empty())
	var room := _build(doc)
	await process_frame
	var host: Node = room.host
	var w: Node = host.system("weather")
	w.weather_changed.connect(func(state: String) -> void: _states.append(state))
	_check("built", w != null and w.get_script() == Weather)
	# The areas.
	var areas: Array = w.areas()
	_check("two areas, one emitter each", areas.size() == 2)
	var total := 0
	for a: Array in areas:
		total += (a[0] as GPUParticles3D).amount
	_check("the drops shared, within the parameter (%d)" % total, total <= 1520 and total >= 1480)
	var big: GPUParticles3D = areas[0][0]
	var small: GPUParticles3D = areas[1][0]
	_check("by floor area (%d, %d)" % [big.amount, small.amount], big.amount > small.amount * 20)
	_check("each falls from its top to its floor (%.2f s)" % big.lifetime,
			is_equal_approx(big.lifetime, 9.5 / Weather.RAIN_SPEED))
	_check("rain streaks, not flakes", w.fall_material().get_shader_parameter("flake") == false)
	_check("the pane and the puddle, see-through", w.pane() != null and w.puddle() != null
			and w.pane().is_in_group(ScreenFrame.SEE_THROUGH) and w.puddle().is_in_group(ScreenFrame.SEE_THROUGH))
	_check("the pane faces into the room", is_equal_approx(w.pane().rotation.y, deg_to_rad(-90.0)))
	# At the cycle's start: clear.
	host.step(0.1)
	_check("the cycle starts clear (%s, %.2f)" % [w.weather_state(), w.rain_amount()], w.weather_state() == "clear"
			and w.rain_amount() < 0.01)
	_check("nothing falls while clear", not big.emitting)
	# The cycle, four minutes in quarter seconds.
	var peak := 0.0
	var peak_wet := 0.0
	var follows := true
	for i in 4 * 60 * 4:
		host.step(0.25)
		peak = maxf(peak, w.rain_amount())
		peak_wet = maxf(peak_wet, w.wet_amount())
		if not is_equal_approx(float(host.signals.value("weather.rain")), w.rain_amount()):
			follows = false
		if i == 4 * 60 * 2 + 40:
			# In the rain (phase 0.54 + easing): the particles show it.
			_check("raining: the drops show (ratio %.2f)" % big.amount_ratio, big.emitting and big.amount_ratio > 0.2)
			var pane_rain := float(w.pane().material_override.get_shader_parameter("rain"))
			_check("the pane has it (%.2f)" % pane_rain, is_equal_approx(pane_rain, w.rain_amount()))
			_check("the puddle has it", is_equal_approx(float(w.puddle().material_override.get_shader_parameter(
					"rain")), w.rain_amount()))
	_check("the channel weather.rain follows the rain", follows)
	_check("it rained fully (%.2f) and got wet (%.2f)" % [peak, peak_wet], peak > 0.95 and peak_wet > 0.6)
	_check("the cycle: clear, drizzle, rain, clearing, clear (%s)" % [_states], _in_order(_states,
			["drizzle", "rain", "clearing", "clear"]))
	_check("the accent lamps follow weather.wet through a binding (%.2f, wet %.2f)" % [
			float(host.system("light").params["accent"]), w.wet_amount()],
			absf(float(host.system("light").params["accent"]) - w.wet_amount()) < 0.05)
	# The room's setting: rain all the time, then none.
	_states.clear()
	host.set_setting("weather", "rain")
	_check("the setting maps onto mode", w.params["mode"] == "heavy")
	_steps(host, 30.0)
	_check("rain, held (%s, %.2f)" % [w.weather_state(), w.rain_amount()], w.weather_state() == "rain"
			and w.rain_amount() > 0.95)
	host.set_setting("weather", "clear")
	_steps(host, 4.0)
	_check("off: easing off, not at once (%.2f)" % w.rain_amount(), w.rain_amount() > 0.1
			and w.weather_state() == "clearing")
	_steps(host, 30.0)
	_check("off: nothing falls (%.3f)" % w.rain_amount(), w.rain_amount() < 0.01)
	_steps(host, 40.0)
	_check("and it dries (%s, wet %.2f)" % [w.weather_state(), w.wet_amount()], w.weather_state() == "clear"
			and w.wet_amount() < 0.01)
	# A cue's shower over the clear weather, and a clear-up.
	w.act("shower", {"seconds": 20.0, "amount": 0.8})
	_steps(host, 18.0)
	_check("a shower (%.2f)" % w.rain_amount(), w.rain_amount() > 0.7)
	_steps(host, 30.0)
	_check("it passes (%.2f)" % w.rain_amount(), w.rain_amount() < 0.05)
	host.set_setting("weather", "rain")
	_steps(host, 30.0)
	w.act("clear_up", {"seconds": 60.0})
	_steps(host, 30.0)
	_check("a clear-up in the rain (%.2f)" % w.rain_amount(), w.rain_amount() < 0.02)
	# The puddle sees the screen.
	var inv: Projection = w.puddle().material_override.get_shader_parameter("screen_inverse")
	var screen_world: Transform3D = room.global_transform * room.get_screen_anchor()
	var probe: Vector4 = inv * Vector4(screen_world.origin.x, screen_world.origin.y, screen_world.origin.z, 1.0)
	_check("the puddle's view of the screen (%s)" % probe, Vector3(probe.x, probe.y, probe.z).length() < 0.01)
	_check("no film: the water takes the bias light's colours", w.puddle().material_override.get_shader_parameter(
			"has_picture") == false)
	_check("no sound of its own", host.sounds.is_empty())
	# Budget and the sight line, with the rain at its heaviest.
	host.set_setting("weather", "rain")
	_steps(host, 70.0)
	var stats := EnvChecks.measure(room)
	print("  rain test room: %s" % [stats])
	_check("within the headset's budget %s" % [EnvChecks.budget(stats)], EnvChecks.budget(stats).is_empty())
	var own := {"draws": 0, "triangles": 0, "particles": 0}
	var holder := Node3D.new()
	for n: Node in w.owned():
		holder.add_child(n.duplicate())
	var m := EnvChecks.measure(holder)
	holder.free()
	print("  weather's own: %s (spec: %s)" % [m, s["cost"]])
	_check("its own: two areas, a pane and a puddle, 1500 drops (%s)" % [m], m["draws"] == 4
			and m["particles"] == total and m["triangles"] == 4)
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("a clear sight line from every seat %s" % [blocked.slice(0, 2)], blocked.is_empty())
	var signals: RefCounted = host.signals
	room.queue_free()
	await process_frame
	_check("gone: its channels back to 0", float(signals.value("weather.rain")) == 0.0
			and float(signals.value("weather.wet")) == 0.0)
	# Snow.
	var snow := {"schema": 4, "name": "Snow test", "screen": {"center": [0.0, 1.6, -8.0], "size": [6.0, 3.0]},
		"systems": [{"system": "weather", "params": {"falls": "snow", "mode": "heavy",
			"areas": [{"min": [-6.0, 0.0, -20.0], "max": [6.0, 6.0, -12.0]}], "particles": 800}}]}
	_check("snow validates (%s)" % [EnvDoc.validate(snow)["errors"]], EnvDoc.validate(snow)["ok"])
	room = _build(snow)
	await process_frame
	w = room.host.system("weather")
	_steps(room.host, 20.0)
	var flakes: GPUParticles3D = w.areas()[0][0]
	_check("flakes, slow (%.1f s to fall 6 m)" % flakes.lifetime, w.fall_material().get_shader_parameter("flake")
			== true and is_equal_approx(flakes.lifetime, 6.0 / Weather.SNOW_SPEED))
	_check("snowing (%s): weather.snow, not weather.rain" % w.weather_state(), w.weather_state() == "snow"
			and float(room.host.signals.value("weather.snow")) > 0.9
			and float(room.host.signals.value("weather.rain")) == 0.0)
	_check("800 flakes", flakes.amount == 800)
	room.queue_free()
	await process_frame
	# A cycle's shape.
	_check("the cycle: clear, then drizzle, rain, easing", Weather.cycle_amount(0.2) == 0.0
			and is_equal_approx(Weather.cycle_amount(0.5), Weather.LIGHT) and Weather.cycle_amount(0.7) == 1.0
			and Weather.cycle_amount(0.97) == 0.0)
	print("test_env_weather: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## Whether `want` appears in `got` in this order (other states may come between).
static func _in_order(got: Array[String], want: Array) -> bool:
	var i := 0
	for g in got:
		if i < want.size() and g == want[i]:
			i += 1
	return i == want.size()


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
