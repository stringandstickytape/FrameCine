extends Node

## Picture controls (ideas #27): brightness, contrast, saturation, gamma, a dark-scene lift and a light sharpen (#90,
## off by default), applied in video.gdshader (pc_* uniforms, skipped entirely at the defaults), remembered per
## environment: a dark cinema and the void want different settings.
##
##   values                  {brightness, contrast, saturation, gamma, lift, sharpen} in effect
##   RANGES                  name -> [min, max, default, step] for the pane's sliders
##   set_value(name, v)      clamped, applied, saved for the current environment
##   reset()                 this environment back to the defaults
##   signal changed(values)
## Settings: [picture_<environment id>] brightness, contrast, saturation, gamma, lift, sharpen (only values that differ
## from the default are stored).

signal changed(values: Dictionary)

const RANGES := {
	"brightness": [-0.3, 0.3, 0.0, 0.01],
	"contrast": [0.5, 1.5, 1.0, 0.02],
	"saturation": [0.0, 2.0, 1.0, 0.05],
	"gamma": [0.6, 1.6, 1.0, 0.02],
	"lift": [0.0, 0.25, 0.0, 0.01],
	# Light sharpen (ideas #90): off by default.
	"sharpen": [0.0, 1.0, 0.0, 0.05],
}

var main: Node3D
var values := {}
var _env := ""


func _ready() -> void:
	main.environment_changed.connect(func(id: String, _l: float) -> void: load_for(id))
	load_for(main.env_id)


static func defaults() -> Dictionary:
	var d := {}
	for k: String in RANGES:
		d[k] = RANGES[k][2]
	return d


func load_for(env_id: String) -> void:
	_env = env_id
	values = defaults()
	for k: String in RANGES:
		values[k] = clampf(float(main.settings.get_value(_section(), k, RANGES[k][2])), RANGES[k][0], RANGES[k][1])
	_apply()


func set_value(key: String, v: float) -> void:
	if not RANGES.has(key):
		push_warning("Picture controls: no '%s'" % key)
		return
	var r: Array = RANGES[key]
	v = clampf(snappedf(v, 0.001), r[0], r[1])
	values[key] = v
	main.settings.set_value(_section(), key, null if is_equal_approx(v, r[2]) else v)
	_apply()


func reset() -> void:
	for k: String in RANGES:
		main.settings.set_value(_section(), k, null)
	load_for(_env)


func is_default() -> bool:
	for k: String in RANGES:
		if not is_equal_approx(float(values[k]), float(RANGES[k][2])):
			return false
	return true


func _section() -> String:
	return "picture_" + _env


func _apply() -> void:
	var m: ShaderMaterial = main.screen.material
	m.set_shader_parameter("pc_enabled", not is_default())
	for k: String in RANGES:
		m.set_shader_parameter("pc_" + k, values[k])
	changed.emit(values)
