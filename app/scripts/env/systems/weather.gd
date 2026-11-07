extends "res://scripts/env/systems/env_system.gd"

## Weather (docs/environments.md, "Atmosphere and weather"): rain or snow falling in areas the document gives (an open
## roof, the view outside a window), rain on a window pane, a puddle that reflects the film, and a weather cycle.
##   mode       clear, light (a drizzle, or flurries), heavy (rain, or snow), or changing: the cycle, clear -> drizzle
##              -> rain -> clearing -> clear, over cycle_minutes. A room setting turns it off by mapping onto mode.
##              A change of mode eases over change_seconds; surfaces stay wet after rain and dry over dry_minutes.
##   falls      rain or snow (built once)
##   areas      up to MAX_AREAS boxes the rain or snow falls through: GPU particles (shaders/env_rain_fall.gdshader),
##              particles shared between them by their floor area, their share of drops showing with the amount
##   pane       drops on a window pane (shaders/env_rain_pane.gdshader): beads and running drops with trails
##   puddle     a puddle on the floor that reflects the film, with rings while it rains (shaders/env_rain_puddle
##              .gdshader, the screen's uniforms copied each frame as the floor reflection does)
## The state for other systems and cues: the channels weather.rain, weather.snow and weather.wet (0..1, written into
## the host's film signals each frame; 0 without a weather system), the signal weather_changed(state), and
## rain_amount(), snow_amount(), wet_amount(), weather_state(). The weather makes no sound of its own: a sound_bed
## follows the channels (rain on glass, drips on leaves).

signal weather_changed(state: String)

const FALL_SHADER := preload("res://shaders/env_rain_fall.gdshader")
const PANE_SHADER := preload("res://shaders/env_rain_pane.gdshader")
const PUDDLE_SHADER := preload("res://shaders/env_rain_puddle.gdshader")
const ScreenFrame := preload("res://scripts/env/systems/screen_frame.gd")
const MAX_AREAS := 3
## The amount of a drizzle (light), of rain (heavy) is 1.
const LIGHT := 0.3
## Metres a second a drop or a flake falls.
const RAIN_SPEED := 7.5
const SNOW_SPEED := 0.75
## The cycle's amount over its phase (0..1): clear, drizzle, rain, easing off, clear.
const CYCLE := [[0.0, 0.0], [0.4, 0.0], [0.47, LIGHT], [0.55, LIGHT], [0.62, 1.0], [0.78, 1.0], [0.86, LIGHT],
		[0.93, 0.0], [1.0, 0.0]]
## Seconds wet surfaces take to catch up with rain.
const WETTING := 20.0
## The channels the weather writes (env_doc.gd CHANNELS).
const CHANNELS: Array[String] = ["weather.rain", "weather.snow", "weather.wet"]
## The puddle's own uniforms (not copied from the screen).
const PUDDLE_OWN: Array[String] = ["screen_inverse", "screen_size", "water_y", "half_size", "seed", "strength", "rain",
		"has_picture", "water", "pc_deband"]


static func spec() -> Dictionary:
	return {
		"kind": "atmosphere",
		"description": "Rain or snow falling through an open roof or outside a window, rain on a window pane, a "
				+ "puddle that reflects the film, and a slow weather cycle (clear, drizzle, rain, clearing).",
		"params": {
			"mode": {"type": "enum", "values": ["clear", "light", "heavy", "changing"], "default": "changing",
					"live": true, "description": "clear; light (drizzle or flurries); heavy (rain or snow); or "
					+ "changing: the cycle. Map a room setting onto it to turn the weather off"},
			"falls": {"type": "enum", "values": ["rain", "snow"], "default": "rain",
					"description": "what falls"},
			"intensity": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true,
					"description": "how much of it falls at the heaviest"},
			"cycle_minutes": {"type": "float", "min": 4.0, "max": 240.0, "default": 24.0,
					"description": "minutes the changing cycle takes, clear to clear"},
			"cycle_start": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3,
					"description": "where in the cycle the room starts (0.4: the drizzle begins)"},
			"change_seconds": {"type": "float", "min": 1.0, "max": 300.0, "default": 40.0,
					"description": "seconds a change of weather takes"},
			"dry_minutes": {"type": "float", "min": 0.5, "max": 60.0, "default": 4.0,
					"description": "minutes the wet takes to dry after the rain"},
			"areas": {"type": "list", "max": MAX_AREAS, "default": [],
					"of": {"type": "object", "fields": {"min": {"type": "vec3", "min": -200.0, "max": 200.0},
							"max": {"type": "vec3", "min": -200.0, "max": 200.0}}},
					"description": "boxes ({min, max}, the room's frame) the rain or snow falls through, top to floor"},
			"particles": {"type": "int", "min": 0, "max": 3000, "default": 1200,
					"description": "drops or flakes over all the areas (the room's budget is 4000)"},
			"wind": {"type": "vec2", "min": -5.0, "max": 5.0, "default": [0.2, 0.0],
					"description": "the wind in metres a second, along x and z"},
			"colour": {"type": "color", "default": [0.75, 0.8, 0.9],
					"description": "the drops' or flakes' colour (lit by the room and the film)"},
			"pane": {"type": "bool", "default": false, "description": "drops on a window pane"},
			"pane_center": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [0.0, 1.5, -3.0],
					"description": "the pane's middle, the room's frame"},
			"pane_size": {"type": "vec2", "min": 0.1, "max": 10.0, "default": [1.2, 1.0],
					"description": "the pane's width and height in metres"},
			"pane_yaw": {"type": "float", "min": -180.0, "max": 180.0, "default": 0.0,
					"description": "degrees the pane turns about the vertical; 0 faces +z (seen from in front)"},
			"puddle": {"type": "bool", "default": false, "description": "a puddle on the floor that reflects the film"},
			"puddle_center": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [0.0, 0.0, -4.0],
					"description": "the puddle's middle on the floor, the room's frame"},
			"puddle_size": {"type": "vec2", "min": 0.2, "max": 20.0, "default": [2.5, 1.6],
					"description": "metres across (x) and deep (z)"},
			"puddle_reflect": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.6, "live": true,
					"brightness": true, "description": "how much of the picture the puddle gives back"},
		},
		"actions": {"shower": "a passing shower whatever the mode (args: seconds, default 90; amount, default 1)",
				"clear_up": "the rain eases off now and holds off (args: seconds, default 300)"},
		"cost": {"draws": 3, "triangles": 4, "lights": 0, "particles": 1200, "texture_mb": 0},
		"provides": ["weather"],
	}


## [GPUParticles3D, ParticleProcessMaterial, area AABB]
var _areas: Array = []
var _fall_material: ShaderMaterial
var _pane: MeshInstance3D
var _pane_material: ShaderMaterial
var _puddle: MeshInstance3D
var _puddle_material: ShaderMaterial
var _puddle_copy: Array[String] = []
var _screen_local := Transform3D()
var _screen_size := Vector2.ZERO
## Seconds the room has shown (the cycle's clock), the amount now (eased, before intensity), the wet.
var elapsed := 0.0
var _amount := 0.0
var _wet := 0.0
var _state := ""
## A cue's shower or clear-up: {amount, left} (seconds left), or {}.
var _override := {}


func setup() -> void:
	_amount = _target()
	_wet = _amount * float(params["intensity"])
	var falls := str(params["falls"])
	if int(params["particles"]) > 0 and not (params["areas"] as Array).is_empty():
		_build_areas(falls == "snow")
	if bool(params["pane"]):
		_build_pane()
	if bool(params["puddle"]):
		_build_puddle()
	_state = _state_now()
	_apply()


# --- Building ---------------------------------------------------------------------------------------------------------

func _build_areas(snow: bool) -> void:
	var boxes: Array[AABB] = []
	var floor_total := 0.0
	for a: Dictionary in params["areas"]:
		var lo := _vec3(a.get("min", [0, 0, 0]))
		var hi := _vec3(a.get("max", [0, 0, 0]))
		var box := AABB(lo.min(hi), (hi - lo).abs())
		if box.size.y < 0.2 or box.size.x * box.size.z < 0.01:
			continue
		boxes.append(box)
		floor_total += box.size.x * box.size.z
	_fall_material = ShaderMaterial.new()
	_fall_material.shader = FALL_SHADER
	_fall_material.set_shader_parameter("flake", snow)
	_fall_material.set_shader_parameter("colour", color_param("colour"))
	_fall_material.set_shader_parameter("opacity", 0.75 if snow else 0.45)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03) if snow else Vector2(0.006, 0.24)
	quad.material = _fall_material
	var total := int(params["particles"])
	var wv: Array = params["wind"]
	var wind := Vector3(float(wv[0]), 0.0, float(wv[1]))
	var speed := SNOW_SPEED if snow else RAIN_SPEED
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.06, 0.9, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0.2)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	for i in boxes.size():
		var box := boxes[i]
		var n := maxi(int(round(total * box.size.x * box.size.z / floor_total)), 1)
		var life := box.size.y / speed
		var drift := wind * life
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(box.size.x / 2.0, 0.02, box.size.z / 2.0)
		var v := Vector3(wind.x, -speed, wind.z)
		pm.direction = v.normalized()
		pm.spread = 6.0 if snow else 1.0
		pm.initial_velocity_min = v.length() * (0.85 if snow else 0.95)
		pm.initial_velocity_max = v.length() * (1.15 if snow else 1.05)
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.6 if snow else 0.8
		pm.scale_max = 1.3 if snow else 1.2
		pm.color_ramp = fade_tex
		var p := GPUParticles3D.new()
		p.name = "Fall%d" % i
		p.amount = n
		p.lifetime = life
		p.preprocess = life
		p.local_coords = false
		p.process_material = pm
		p.draw_pass_1 = quad
		# Upwind of the box, so what falls drifts across it and lands inside.
		var top := Vector3(box.get_center().x, box.end.y, box.get_center().z) - drift / 2.0
		p.position = top
		var reach := Vector3(box.size.x / 2.0 + absf(drift.x) + 0.5, 0.0, box.size.z / 2.0 + absf(drift.z) + 0.5)
		p.visibility_aabb = AABB(Vector3(-reach.x, -box.size.y - 0.5, -reach.z),
				Vector3(reach.x * 2.0, box.size.y + 1.0, reach.z * 2.0))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		own(p)
		_areas.append([p, pm, box])


func _build_pane() -> void:
	_pane_material = ShaderMaterial.new()
	_pane_material.shader = PANE_SHADER
	var size := _vec2(params["pane_size"])
	_pane_material.set_shader_parameter("pane_size", size)
	var quad := QuadMesh.new()
	quad.size = size
	_pane = MeshInstance3D.new()
	_pane.name = "RainPane"
	_pane.mesh = quad
	_pane.material_override = _pane_material
	_pane.position = _vec3(params["pane_center"])
	_pane.rotation.y = deg_to_rad(float(params["pane_yaw"]))
	_pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pane.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_pane.add_to_group(ScreenFrame.SEE_THROUGH)
	own(_pane)


func _build_puddle() -> void:
	_puddle_material = ShaderMaterial.new()
	_puddle_material.shader = PUDDLE_SHADER
	var size := _vec2(params["puddle_size"])
	_puddle_material.set_shader_parameter("half_size", size / 2.0)
	_puddle_material.set_shader_parameter("seed", float(hash(id) % 997) * 0.37)
	_puddle_material.set_shader_parameter("pc_deband", 0.0)
	for u: Dictionary in PUDDLE_SHADER.get_shader_uniform_list():
		var n := str(u["name"])
		if not (n in PUDDLE_OWN) and not (u.get("usage", 0) & PROPERTY_USAGE_GROUP):
			_puddle_copy.append(n)
	var plane := PlaneMesh.new()
	plane.size = size
	_puddle = MeshInstance3D.new()
	_puddle.name = "Puddle"
	_puddle.mesh = plane
	_puddle.material_override = _puddle_material
	_puddle.position = _vec3(params["puddle_center"]) + Vector3(0.0, 0.004, 0.0)
	_puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puddle.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_puddle.add_to_group(ScreenFrame.SEE_THROUGH)
	own(_puddle)


static func _vec3(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _vec2(v: Variant) -> Vector2:
	var a: Array = v
	return Vector2(float(a[0]), float(a[1]))


# --- The weather -------------------------------------------------------------------------------------------------------

## The cycle's amount at a phase (0..1).
static func cycle_amount(phase: float) -> float:
	phase = fposmod(phase, 1.0)
	for i in range(1, CYCLE.size()):
		if phase <= float(CYCLE[i][0]):
			var a: Array = CYCLE[i - 1]
			var b: Array = CYCLE[i]
			var f := (phase - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-6)
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, f))
	return 0.0


func phase() -> float:
	return fposmod(float(params["cycle_start"]) + elapsed / (float(params["cycle_minutes"]) * 60.0), 1.0)


## What the weather is heading for (before intensity).
func _target() -> float:
	if not _override.is_empty():
		return float(_override["amount"])
	match str(params["mode"]):
		"clear":
			return 0.0
		"light":
			return LIGHT
		"heavy":
			return 1.0
	return cycle_amount(phase())


func act(action: String, args: Dictionary) -> void:
	match action:
		"shower":
			_override = {"amount": clampf(float(args.get("amount", 1.0)), 0.0, 1.0),
					"left": float(args.get("seconds", 90.0))}
		"clear_up":
			_override = {"amount": 0.0, "left": float(args.get("seconds", 300.0))}


func tick(delta: float) -> void:
	elapsed += delta
	if not _override.is_empty():
		_override["left"] = float(_override["left"]) - delta
		if float(_override["left"]) <= 0.0:
			_override = {}
	var target := _target()
	var tau := float(params["change_seconds"]) / 3.0
	if delta > 0.0:
		_amount = lerpf(_amount, target, 1.0 - exp(-delta / tau))
		if absf(_amount - target) < 0.002:
			_amount = target
	var falling := falling_amount()
	if falling > _wet:
		_wet = lerpf(_wet, falling, 1.0 - exp(-delta / WETTING)) if delta > 0.0 else _wet
	else:
		_wet = maxf(_wet - delta / (float(params["dry_minutes"]) * 60.0), falling)
	_publish()
	_apply()
	var s := _state_now()
	if s != _state:
		_state = s
		weather_changed.emit(s)


## What falls now, 0..1 (the eased amount times the intensity).
func falling_amount() -> float:
	return clampf(_amount * float(params["intensity"]), 0.0, 1.0)


func rain_amount() -> float:
	return falling_amount() if str(params["falls"]) == "rain" else 0.0


func snow_amount() -> float:
	return falling_amount() if str(params["falls"]) == "snow" else 0.0


func wet_amount() -> float:
	return clampf(_wet, 0.0, 1.0)


## clear, drizzle, rain or clearing (snow: clear, flurries, snow, clearing).
func weather_state() -> String:
	return _state


func _state_now() -> String:
	var a := falling_amount()
	var snow := str(params["falls"]) == "snow"
	var easing := _target() * float(params["intensity"]) < a - 0.05
	if a > 0.6 and not easing:
		return "snow" if snow else "rain"
	if a > 0.05:
		return "clearing" if easing else ("flurries" if snow else "drizzle")
	return "clearing" if _wet > 0.08 else "clear"


## The channels for bindings and cues (sound beds follow weather.rain and weather.wet).
func _publish() -> void:
	if host == null or host.get("signals") == null:
		return
	var v: Dictionary = host.signals.values
	v["weather.rain"] = rain_amount()
	v["weather.snow"] = snow_amount()
	v["weather.wet"] = wet_amount()


func _apply() -> void:
	var f := falling_amount()
	for a: Array in _areas:
		var p: GPUParticles3D = a[0]
		p.amount_ratio = f
		var on := f > 0.003
		if p.emitting != on:
			p.emitting = on
	if _pane_material != null:
		_pane_material.set_shader_parameter("rain", rain_amount())
		_pane_material.set_shader_parameter("wet", wet_amount())
	if _puddle_material != null:
		_puddle_material.set_shader_parameter("rain", rain_amount())
		_puddle_material.set_shader_parameter("strength", float(params["puddle_reflect"]))
		_place_puddle()


func _param_changed(param: String, _value: Variant) -> void:
	if param == "puddle_reflect" and _puddle_material != null:
		_puddle_material.set_shader_parameter("strength", float(params["puddle_reflect"]))


func on_screen_changed(local: Transform3D, size: Vector2) -> void:
	_screen_local = local
	_screen_size = size
	_place_puddle()


## The puddle's view of the screen (the room may move with a seat), and the picture when there is one.
func _place_puddle() -> void:
	if _puddle == null or _screen_size == Vector2.ZERO or not room.is_inside_tree():
		return
	var screen := room.global_transform * _screen_local
	_puddle_material.set_shader_parameter("screen_inverse", Projection(screen.affine_inverse()))
	_puddle_material.set_shader_parameter("screen_size", _screen_size)
	_puddle_material.set_shader_parameter("water_y", _puddle.global_position.y)
	var main := main_node()
	var picture: bool = main != null and main.player.has_source() and main.screen.is_shown() \
			and not main.mode.is_spherical()
	_puddle_material.set_shader_parameter("has_picture", picture)
	if picture:
		var src: ShaderMaterial = main.screen.material
		for n in _puddle_copy:
			_puddle_material.set_shader_parameter(n, src.get_shader_parameter(n))


func _exit_tree() -> void:
	if host != null and host.get("signals") != null:
		for c in CHANNELS:
			host.signals.values[c] = 0.0


# --- Tests ------------------------------------------------------------------------------------------------------------

func areas() -> Array:
	return _areas


func pane() -> MeshInstance3D:
	return _pane


func puddle() -> MeshInstance3D:
	return _puddle


func fall_material() -> ShaderMaterial:
	return _fall_material
