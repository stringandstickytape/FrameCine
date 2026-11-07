extends "res://scripts/env/systems/env_system.gd"

## The air of a room (docs/environments.md, "Atmosphere and weather"): haze, dust or smoke in the projector's beam,
## ground fog or mist, and breath fog in a cold room. Cheap by design: no volumetric fog, no depth texture.
##   Haze     a beam-shaped volume from the lens to the screen's corners (shaders/env_haze_beam.gdshader, additive):
##            the cone's four sides and a cross of two planes through its axis, each sampling a drifting noise field.
##            The lens is the screen_frame system's when the room has one, else this system's own. It shows while the
##            beam would: a flat film playing, and not the projector feature's own beam. It is brightest near the lens
##            and gone before the screen, and takes the picture's colour and brightness (the bias light) unless
##            follow_picture is off; beam_haze and beam_colour are live, so a room can bind them to film.brightness
##            and film.colour as well.
##   Fog      fog_layers soft horizontal layers up to fog_height (shaders/room_fog.gdshader, as an assistant room's
##            fog): low ground fog, or a taller, thinner mist. fog is live (it can follow weather.wet: mist after rain).
##   Breath   now and then a puff from under the viewer's nose (shaders/env_haze_breath.gdshader, BREATH_PARTICLES
##            GPU particles): it starts BREATH_DOWN under the eyes and BREATH_AHEAD in front, drifts forward and down
##            and fades in BREATH_LIFE seconds. It never rises to the eyes' level and never reaches the screen.
## Nothing here moves the viewer. Everything it draws is see-through for the sight-line check.

const BEAM_SHADER := preload("res://shaders/env_haze_beam.gdshader")
const FOG_SHADER := preload("res://shaders/room_fog.gdshader")
const BREATH_SHADER := preload("res://shaders/env_haze_breath.gdshader")
const ScreenFrame := preload("res://scripts/env/systems/screen_frame.gd")
## The beam's lens without a screen_frame system and without a lens given (the cinema's booth).
const DEFAULT_LENS := Vector3(0.0, 3.45, 6.15)
const BREATH_PARTICLES := 16
const BREATH_LIFE := 2.4
## Where a puff starts: metres under the eyes and in front of them.
const BREATH_DOWN := 0.14
const BREATH_AHEAD := 0.1
## A puff's direction (forward and down, in the head's level frame: -Z ahead).
const BREATH_DIRECTION := Vector3(0.0, -0.6, -1.0)


static func spec() -> Dictionary:
	return {
		"kind": "atmosphere",
		"description": "The room's air: haze, dust or smoke in the projector's beam (brighter and tinted with the "
				+ "picture), ground fog or mist in layers, and breath fog from the viewer in a cold room.",
		"params": {
			"beam_haze": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"description": "haze in the projector's beam; 0: none (bind it to film.brightness to follow the "
					+ "picture more)"},
			"beam_dust": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"description": "dust motes that twinkle in the beam (a 1906 shopfront)"},
			"beam_smoke": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"brightness": true, "description": "the haze billows into slow rising smoke (a 1983 multiplex)"},
			"beam_colour": {"type": "color", "default": [1.0, 0.95, 0.85], "live": true,
					"description": "the beam's light (it can follow film.colour)"},
			"follow_picture": {"type": "bool", "default": true,
					"description": "the haze takes the picture's colour and brightness from the bias light"},
			"lens": {"type": "vec3", "min": -200.0, "max": 200.0, "default": null, "nullable": true,
					"description": "the beam's lens in the room's frame; null: the screen_frame system's"},
			"fog": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "ground fog or mist: how thick; 0: none"},
			"fog_height": {"type": "float", "min": 0.1, "max": 4.0, "default": 0.6,
					"description": "metres the fog reaches over its floor (low: ground fog; high: mist)"},
			"fog_colour": {"type": "color", "default": [0.75, 0.8, 0.85], "live": true,
					"description": "the fog's colour (lit by the room and the screen)"},
			"fog_center": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [0.0, 0.0, 0.0],
					"description": "the fog's middle on its floor, in the room's frame"},
			"fog_size": {"type": "vec2", "min": 1.0, "max": 200.0, "default": [16.0, 16.0],
					"description": "metres the fog covers, across (x) and deep (z)"},
			"fog_layers": {"type": "int", "min": 1, "max": 6, "default": 4,
					"description": "layers in the fog (one draw each)"},
			"fog_speed": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.3,
					"description": "how fast the wisps drift"},
			"fog_walls": {"type": "bool", "default": false,
					"description": "the fog ends at walls round its area (else it fades out in a circle)"},
			"breath": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "breath fog in a cold room: how much a puff shows; 0: none"},
			"breath_seconds": {"type": "float", "min": 3.0, "max": 20.0, "default": 5.0,
					"description": "seconds between puffs (each a little more or less)"},
			"breath_colour": {"type": "color", "default": [0.9, 0.93, 1.0],
					"description": "the breath's colour"},
		},
		"cost": {"draws": 6, "triangles": 14, "lights": 0, "particles": BREATH_PARTICLES, "texture_mb": 0},
		"provides": ["haze", "fog", "breath"],
	}


var _beam: MeshInstance3D
var _beam_material: ShaderMaterial
var _lens := Vector3.ZERO
var _beam_key := ""
var _fog: Node3D
var _fog_materials: Array[ShaderMaterial] = []
var _fog_weights: Array[float] = []
var _breath: GPUParticles3D
var _breath_material: ShaderMaterial
var _breath_wait := 0.0
var _rng := RandomNumberGenerator.new()
## Puffs so far (tests).
var puffs := 0
## Tests: the viewer's head (world), instead of the camera; and whether the beam shows (no main: shown).
var head_override: Variant = null


func setup() -> void:
	_rng.seed = hash(id)
	_lens = _find_lens()
	if _wanted("beam_haze") or _wanted("beam_dust") or _wanted("beam_smoke"):
		_build_beam()
	if _wanted("fog"):
		_build_fog()
	if _wanted("breath"):
		_build_breath()
	_apply_all()


## Whether the document gives a parameter (a value over 0, or a binding): only then is its part built and counted.
func _wanted(param: String) -> bool:
	if float(params.get(param, 0.0)) > 0.0:
		return true
	if host == null:
		return false
	for entry: Dictionary in host.doc.get("systems", []):
		if str(entry.get("id", entry["system"])) == id:
			return (entry.get("params", {}) as Dictionary).has(param)
	return false


## The screen_frame's lens when the room has a beam, else this system's own (or the cinema's booth).
func _find_lens() -> Vector3:
	if params.get("lens") is Array:
		var v: Array = params["lens"]
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if host != null:
		for s: Node in host.systems_of_kind("screen"):
			if s.get_script() == ScreenFrame and s.params.get("lens") is Array:
				var v: Array = s.params["lens"]
				return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return DEFAULT_LENS


func _build_beam() -> void:
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = BEAM_SHADER
	_beam_material.set_shader_parameter("house_reference", float(room.get("ambient_level")))
	_beam = MeshInstance3D.new()
	_beam.name = "BeamHaze"
	_beam.position = _lens
	_beam.material_override = _beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_beam.add_to_group(ScreenFrame.SEE_THROUGH)
	own(_beam)


func on_screen_changed(local: Transform3D, size: Vector2) -> void:
	if _beam == null or size == Vector2.ZERO:
		return
	var c: Array[Vector3] = []
	for k: Vector2 in [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5),
			Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.0, 0.5), Vector2(0.0, -0.5)]:
		c.append(local * Vector3(k.x * size.x, k.y * size.y, 0.0) - _lens)
	var key := str(c)
	if key == _beam_key:
		return
	_beam_key = key
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The four sides (UV2.y 0), then the cross: across the middle and up the middle (UV2.y 1).
	var faces: Array = [[c[0], c[1], 0.0], [c[1], c[2], 0.0], [c[2], c[3], 0.0], [c[3], c[0], 0.0],
			[c[4], c[5], 1.0], [c[6], c[7], 1.0]]
	for f: Array in faces:
		for v: Array in [[Vector3.ZERO, 0.0, 0.5], [f[0], 1.0, 0.0], [f[1], 1.0, 1.0]]:
			st.set_uv(Vector2(0.0, v[1]))
			st.set_uv2(Vector2(v[2], f[2]))
			st.add_vertex(v[0])
	st.generate_normals()
	_beam.mesh = st.commit()


func _build_fog() -> void:
	_fog = Node3D.new()
	_fog.name = "Fog"
	var cv: Array = params["fog_center"]
	_fog.position = Vector3(float(cv[0]), float(cv[1]), float(cv[2]))
	own(_fog)
	var size: Array = params["fog_size"]
	var half := Vector2(float(size[0]), float(size[1])) / 2.0
	var n := int(params["fog_layers"])
	var total := 0.0
	for i in n:
		_fog_weights.append(exp(-2.0 * float(i) / n))
		total += _fog_weights[i]
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var height := float(params["fog_height"])
	for i in n:
		_fog_weights[i] /= total
		var m := ShaderMaterial.new()
		m.shader = FOG_SHADER
		m.set_shader_parameter("speed", float(params["fog_speed"]))
		m.set_shader_parameter("level", float(i) / maxf(n - 1, 1))
		m.set_shader_parameter("half_size", half)
		m.set_shader_parameter("boxed", bool(params["fog_walls"]))
		_fog_materials.append(m)
		var mi := MeshInstance3D.new()
		mi.name = "Layer%d" % i
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.scale = Vector3(half.x, 1.0, half.y)
		mi.position = Vector3(0.0, 0.03 + (height - 0.03) * float(i) / maxf(n - 1, 1), 0.0)
		# The upper layers first, so the denser low ones blend over them seen from above.
		mi.sorting_offset = float(n - i)
		mi.add_to_group(ScreenFrame.SEE_THROUGH)
		_fog.add_child(mi)


func _build_breath() -> void:
	_breath_material = ShaderMaterial.new()
	_breath_material.shader = BREATH_SHADER
	_breath_material.set_shader_parameter("colour", color_param("breath_colour"))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.11)
	quad.material = _breath_material
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.015
	pm.direction = BREATH_DIRECTION.normalized()
	pm.spread = 8.0
	pm.initial_velocity_min = 0.18
	pm.initial_velocity_max = 0.28
	pm.gravity = Vector3(0.0, 0.01, 0.0)
	pm.damping_min = 0.06
	pm.damping_max = 0.12
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	_breath = GPUParticles3D.new()
	_breath.name = "Breath"
	_breath.amount = BREATH_PARTICLES
	_breath.lifetime = BREATH_LIFE
	_breath.one_shot = true
	_breath.explosiveness = 0.7
	_breath.local_coords = false
	_breath.emitting = false
	_breath.process_material = pm
	_breath.draw_pass_1 = quad
	_breath.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))
	_breath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(_breath)
	_breath_wait = float(params["breath_seconds"]) * _rng.randf_range(0.3, 0.8)


func _param_changed(_param: String, _value: Variant) -> void:
	_apply_all()


func _apply_all() -> void:
	if _beam_material != null:
		_beam_material.set_shader_parameter("haze", float(params["beam_haze"]))
		_beam_material.set_shader_parameter("dust", float(params["beam_dust"]))
		_beam_material.set_shader_parameter("smoke", float(params["beam_smoke"]))
		_beam_material.set_shader_parameter("colour", color_param("beam_colour"))
		_beam_material.set_shader_parameter("follow_picture", 1.0 if bool(params["follow_picture"]) else 0.0)
	var fog := float(params["fog"])
	for i in _fog_materials.size():
		# Together the layers reach the fog's opacity where the view crosses them all.
		_fog_materials[i].set_shader_parameter("opacity", 0.7 * fog * _fog_weights[i])
		_fog_materials[i].set_shader_parameter("fog_color", color_param("fog_colour"))
	if _fog != null:
		_fog.visible = fog > 0.001
	if _breath_material != null:
		_breath_material.set_shader_parameter("opacity", 0.35 * float(params["breath"]))


# --- Each frame -------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if _beam != null:
		var any := float(params["beam_haze"]) + float(params["beam_dust"]) + float(params["beam_smoke"]) > 0.001
		_beam.visible = any and _beam_shows() and _beam.mesh != null
	if _breath != null:
		_tick_breath(delta)


## The beam shows as screen_frame's does: a flat film playing, and not while the projector feature draws its own.
func _beam_shows() -> bool:
	var main := main_node()
	if main == null:
		return true
	var on: bool = main.player.is_playing() and main.screen.is_shown() and not main.mode.is_spherical()
	var projector: Node = main.features.get("projector") if main.get("features") != null else null
	if projector != null and projector.beam_applies():
		on = false
	return on


func _head() -> Variant:
	if head_override != null:
		return head_override
	var main := main_node()
	if main != null and main.get("camera") != null:
		return (main.camera as Node3D).global_transform
	return null


func _tick_breath(delta: float) -> void:
	_breath.visible = float(params["breath"]) > 0.001
	if not _breath.visible:
		return
	_breath_wait -= delta
	if _breath_wait > 0.0:
		return
	_breath_wait = float(params["breath_seconds"]) * _rng.randf_range(0.8, 1.2)
	var head: Variant = _head()
	if head is Vector3:
		head = Transform3D(Basis(), head)
	if not (head is Transform3D):
		return
	_breath.global_transform = breath_origin(head)
	_breath.restart()
	_breath.emitting = true
	puffs += 1


## Where a puff starts and which way it goes, for a head (world): level (the head's yaw only), under the eyes and a
## little ahead. Its -Z is ahead; BREATH_DIRECTION is in this frame.
static func breath_origin(head: Transform3D) -> Transform3D:
	var ahead := -head.basis.z
	ahead.y = 0.0
	if ahead.length() < 0.01:
		ahead = -head.basis.y
		ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var level := Basis.looking_at(ahead, Vector3.UP)
	return Transform3D(level, head.origin + Vector3.DOWN * BREATH_DOWN + ahead * BREATH_AHEAD)


# --- Tests ------------------------------------------------------------------------------------------------------------

func beam() -> MeshInstance3D:
	return _beam


func beam_material() -> ShaderMaterial:
	return _beam_material


func lens() -> Vector3:
	return _lens


func fog_node() -> Node3D:
	return _fog


func fog_materials() -> Array[ShaderMaterial]:
	return _fog_materials


func breath_node() -> GPUParticles3D:
	return _breath
