extends RefCounted

## Particles for the assistant's rooms (docs/assistant.md, "Rooms", particles): named presets the app draws well; the
## assistant names one, an area and a few bounded numbers. A part {"type": "particles", "size": [w, h, d] (the area,
## a box centred on position), "particles": {"preset": "snow", "rate": 40, "color": "#ffffff", "size": 0.03,
## "speed": 1}}.
##
## GPUParticles3D: the particles move on the GPU (compute), so a few hundred cost the CPU nothing, and noise turbulence
## (drift, flutter) is available, which CPUParticles3D lacks. Each preset: soft round (or leaf, or streak) sprites
## made here once, mipmapped and filtered; size and alpha over the lifetime; size, speed and lifetime varied per
## particle; turbulence so nothing moves in a grid or in step. No depth fade where they meet surfaces: on the Mobile
## renderer it costs a full depth copy every frame, which the film can't spare.
##
##   validate(v, path, errors)       build(p) -> GPUParticles3D       amount(p) -> particles it will hold
##   add_when_safe(parent, particles)     hold(), allow(): see SAFE_AFTER

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

## Per preset: rate (default, max, per second), size (metres), speed (m/s along its way), life (seconds; or 0: the
## time to cross the area), where it starts (top, bottom, all), its colours over its life, additive or not.
const PRESETS := {
	"snow": {"rate": [40.0, 150.0], "size": 0.025, "speed": 0.3, "from": "top", "sprite": "soft",
			"description": "flakes that tumble and drift down"},
	"rain": {"rate": [250.0, 600.0], "size": 0.012, "speed": 5.0, "from": "top", "sprite": "streak",
			"description": "thin streaks falling fast"},
	"leaves": {"rate": [6.0, 40.0], "size": 0.06, "speed": 0.5, "from": "top", "sprite": "leaf",
			"description": "autumn leaves that flutter and turn as they fall"},
	# Glows: the size is the whole sprite, a bright core about a sixth of it inside a wide faint halo.
	"embers": {"rate": [25.0, 120.0], "size": 0.08, "speed": 0.45, "from": "bottom", "sprite": "glow",
			"additive": true, "description": "sparks that rise, glow and cool from yellow to red to dark, shrinking"},
	"fireflies": {"rate": [4.0, 20.0], "size": 0.14, "speed": 0.05, "from": "all", "life": 6.0, "sprite": "glow",
			"additive": true, "description": "soft green-gold lights that drift and pulse, each at its own pace"},
	"dust": {"rate": [8.0, 60.0], "size": 0.045, "speed": 0.015, "from": "all", "life": 14.0, "sprite": "bokeh",
			"opacity": 0.12, "additive": true,
			"description": "faint out-of-focus motes catching the light (in a projector's beam: "
			+ "make the area the beam)"},
}
const RATE_MIN := 0.5
const SIZE_RANGE := [0.002, 0.3]
const SPEED_RANGE := [0.25, 3.0]
## The area's sides, metres.
const AREA_MAX := 30.0
const LIFE_MIN := 0.3
const LIFE_MAX := 30.0

static var _sprites := {}
## Seconds the headset must have shown the app before particles are added. Added while its first frames were shown
## (the app starting in a room with particles), they crashed the GPU driver on the first visible frame (Steam Frame,
## 2026-11-03); loaded later they are fine. main.gd calls hold() when it starts XR and allow() SAFE_AFTER seconds after
## the session is first visible; until then add_when_safe() keeps them back. Without XR (tests, the desktop) nothing
## is held.
const SAFE_AFTER := 3.0
static var _held := false
static var _waiting: Array = [] # [weakref(parent), particles]


static func hold() -> void:
	_held = true


static func allow() -> void:
	_held = false
	for w: Array in _waiting:
		var parent: Node = (w[0] as WeakRef).get_ref()
		if parent != null:
			parent.add_child(w[1])
		else:
			(w[1] as Node).free()
	_waiting.clear()


static func add_when_safe(parent: Node, particles: Node) -> void:
	if _held:
		_waiting.append([weakref(parent), particles])
	else:
		parent.add_child(particles)


static func validate(v: Variant, path: String, errors: Array) -> void:
	if not (v is Dictionary):
		errors.append({"path": path, "error": "{preset, rate, color, size, speed}"})
		return
	var d: Dictionary = v
	var preset := str(d.get("preset", ""))
	if not PRESETS.has(preset):
		errors.append({"path": path + ".preset", "error": "one of %s" % ", ".join(PRESETS.keys())})
		return
	for k: Variant in d:
		var p := "%s.%s" % [path, k]
		var x: Variant = d[k]
		match str(k):
			"preset":
				pass
			"rate":
				var mx: float = PRESETS[preset]["rate"][1]
				if not (RoomSchema._num(x) >= RATE_MIN and RoomSchema._num(x) <= mx):
					errors.append({"path": p, "error": "%s..%s a second for %s" % [RATE_MIN, mx, preset]})
			"color":
				if not RoomSchema.is_color(x):
					errors.append({"path": p, "error": "#rrggbb or [r, g, b] 0..1"})
			"size":
				if not (RoomSchema._num(x) >= SIZE_RANGE[0] and RoomSchema._num(x) <= SIZE_RANGE[1]):
					errors.append({"path": p, "error": "%s..%s metres" % SIZE_RANGE})
			"speed":
				if not (RoomSchema._num(x) >= SPEED_RANGE[0] and RoomSchema._num(x) <= SPEED_RANGE[1]):
					errors.append({"path": p, "error": "%s..%s (times the preset's own)" % SPEED_RANGE})
			_:
				errors.append({"path": p, "error": "unknown key (preset, rate, color, size, speed)"})


static func _area(p: Dictionary) -> Vector3:
	var s: Array = p.get("size", [1, 1, 1])
	return Vector3(float(s[0]), float(s[1]), float(s[2]))


static func lifetime(p: Dictionary) -> float:
	var d: Dictionary = p["particles"]
	var pr: Dictionary = PRESETS[str(d["preset"])]
	var speed: float = float(pr["speed"]) * float(d.get("speed", 1.0))
	if pr.has("life"):
		return clampf(float(pr["life"]) / float(d.get("speed", 1.0)), LIFE_MIN, LIFE_MAX)
	return clampf(_area(p).y / maxf(speed, 0.01), LIFE_MIN, LIFE_MAX)


## How many particles the emitter holds at once: its rate times their life, capped (RoomSchema.LIMITS).
static func amount(p: Dictionary) -> int:
	var d: Dictionary = p.get("particles", {})
	if not PRESETS.has(str(d.get("preset", ""))):
		return 0
	var rate := float(d.get("rate", PRESETS[str(d["preset"])]["rate"][0]))
	return clampi(ceili(rate * lifetime(p)), 1, int(RoomSchema.LIMITS["particles_per_emitter"]))


static func build(p: Dictionary) -> GPUParticles3D:
	var d: Dictionary = p["particles"]
	var name := str(d["preset"])
	var pr: Dictionary = PRESETS[name]
	var area := _area(p)
	var k := float(d.get("speed", 1.0))
	var life := lifetime(p)
	var size := float(d.get("size", pr["size"]))
	var gp := GPUParticles3D.new()
	gp.name = "Particles"
	gp.amount = amount(p)
	gp.lifetime = life
	gp.preprocess = life
	gp.randomness = 0.6
	gp.fixed_fps = 30
	gp.interpolate = true
	gp.fract_delta = true
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(-area * 0.5 - Vector3.ONE * 0.5, area + Vector3.ONE)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	match str(pr["from"]):
		"top":
			m.emission_box_extents = Vector3(area.x * 0.5, 0.02, area.z * 0.5)
			m.emission_shape_offset = Vector3(0, area.y * 0.5, 0)
		"bottom":
			m.emission_box_extents = Vector3(area.x * 0.5, 0.02, area.z * 0.5)
			m.emission_shape_offset = Vector3(0, -area.y * 0.5, 0)
		_:
			m.emission_box_extents = area * 0.5
	m.lifetime_randomness = 0.35
	m.scale_min = 0.6
	m.scale_max = 1.3
	m.scale_curve = _curve([[0.0, 0.4], [0.12, 1.0], [0.85, 1.0], [1.0, 0.5]])
	m.turbulence_enabled = true
	var colours: Array = []
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	match name:
		"snow":
			m.direction = Vector3.DOWN
			m.spread = 15.0
			# Falling at their own steady pace, pushed about by the noise.
			m.initial_velocity_min = 0.75 * 0.3 * k
			m.initial_velocity_max = 1.25 * 0.3 * k
			# The noise drags them like air does; this pull holds them near their falling speed against it.
			m.gravity = Vector3(0, -0.2 * k, 0)
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -70.0
			m.angular_velocity_max = 70.0
			m.turbulence_noise_strength = 0.8
			m.turbulence_noise_scale = 2.5
			m.turbulence_noise_speed_random = 0.3
			m.turbulence_influence_min = 0.01
			m.turbulence_influence_max = 0.03
			colours = [[0.0, Color(1, 1, 1, 0)], [0.08, Color(1, 1, 1, 0.9)], [0.85, Color(1, 1, 1, 0.9)],
					[1.0, Color(1, 1, 1, 0)]]
		"rain":
			m.direction = Vector3.DOWN
			m.spread = 2.0
			m.initial_velocity_min = 0.85 * 5.0 * k
			m.initial_velocity_max = 1.15 * 5.0 * k
			m.gravity = Vector3.ZERO
			m.particle_flag_align_y = true
			m.turbulence_noise_strength = 0.1
			m.turbulence_influence_min = 0.0
			m.turbulence_influence_max = 0.005
			m.scale_curve = _curve([[0.0, 1.0], [1.0, 1.0]])
			quad.size = Vector2(size, size * 18.0)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			mat.billboard_keep_scale = true
			colours = [[0.0, Color(0.8, 0.88, 1, 0)], [0.05, Color(0.8, 0.88, 1, 0.35)],
					[0.9, Color(0.8, 0.88, 1, 0.35)], [1.0, Color(0.8, 0.88, 1, 0)]]
		"leaves":
			m.direction = Vector3.DOWN
			m.spread = 25.0
			m.initial_velocity_min = 0.7 * 0.5 * k
			m.initial_velocity_max = 1.3 * 0.5 * k
			m.gravity = Vector3(0, -0.5 * k, 0)
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -140.0
			m.angular_velocity_max = 140.0
			m.hue_variation_min = -0.04
			m.hue_variation_max = 0.04
			m.turbulence_noise_strength = 1.6
			m.turbulence_noise_scale = 3.0
			m.turbulence_influence_min = 0.02
			m.turbulence_influence_max = 0.05
			quad.size = Vector2(size, size * 0.62)
			colours = [[0.0, Color(0.95, 0.55, 0.15, 0)], [0.06, Color(0.95, 0.55, 0.15, 1)],
					[0.5, Color(0.85, 0.32, 0.1, 1)], [0.9, Color(0.6, 0.28, 0.1, 1)], [1.0, Color(0.6, 0.28, 0.1, 0)]]
		"embers":
			m.direction = Vector3.UP
			m.spread = 20.0
			m.initial_velocity_min = 0.6 * 0.45 * k
			m.initial_velocity_max = 1.4 * 0.45 * k
			m.gravity = Vector3(0, 0.35 * k, 0)
			m.damping_min = 0.1
			m.damping_max = 0.4
			m.turbulence_noise_strength = 1.4
			m.turbulence_noise_scale = 1.6
			m.turbulence_noise_speed = Vector3(0, 0.3, 0)
			m.turbulence_influence_min = 0.015
			m.turbulence_influence_max = 0.04
			# The halo shrinks as it rises and cools.
			m.scale_curve = _curve([[0.0, 1.0], [0.5, 0.6], [1.0, 0.25]])
			# Glowing yellow-white, cooling to orange, red, then out: brightness falls slowly, never flashes.
			colours = [[0.0, Color(1.6, 1.25, 0.7, 0)], [0.05, Color(1.6, 1.2, 0.6, 1)], [0.35, Color(1.3, 0.55, 0.15, 1)],
					[0.7, Color(0.7, 0.16, 0.05, 0.8)], [1.0, Color(0.25, 0.04, 0.02, 0)]]
		"fireflies":
			m.direction = Vector3.UP
			m.spread = 180.0
			m.initial_velocity_min = 0.02 * k
			m.initial_velocity_max = 0.08 * k
			m.gravity = Vector3.ZERO
			m.lifetime_randomness = 0.5
			m.turbulence_noise_strength = 0.5
			m.turbulence_noise_scale = 1.2
			m.turbulence_noise_speed_random = 0.5
			m.turbulence_influence_min = 0.02
			m.turbulence_influence_max = 0.06
			# The glow breathes with its brightness.
			m.scale_curve = _curve([[0.0, 0.6], [0.18, 1.0], [0.4, 0.7], [0.62, 0.7], [0.8, 1.0], [1.0, 0.6]])
			# Two slow glows a life (a life of 3 to 6 s: under 1 Hz), each firefly at its own pace.
			var g := Color(0.75, 1.0, 0.35)
			colours = [[0.0, Color(g, 0)], [0.18, Color(g, 1)], [0.4, Color(g, 0.12)], [0.62, Color(g, 0.12)],
					[0.8, Color(g, 0.9)], [1.0, Color(g, 0)]]
		"dust":
			m.direction = Vector3.UP
			m.spread = 180.0
			m.initial_velocity_min = 0.3 * 0.015 * k
			m.initial_velocity_max = 1.5 * 0.015 * k
			m.gravity = Vector3(0, -0.002, 0)
			m.lifetime_randomness = 0.3
			m.turbulence_noise_strength = 0.25
			m.turbulence_noise_scale = 0.8
			m.turbulence_noise_speed = Vector3(0.02, 0.01, 0)
			m.turbulence_influence_min = 0.01
			m.turbulence_influence_max = 0.04
			# Faint (the preset's opacity), like motes out of focus in a beam.
			colours = [[0.0, Color(1, 0.96, 0.88, 0)], [0.25, Color(1, 0.96, 0.88, 1)],
					[0.75, Color(1, 0.96, 0.88, 1)], [1.0, Color(1, 0.96, 0.88, 0)]]
	m.color_ramp = _ramp(colours)
	gp.process_material = m
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if bool(pr.get("additive", false)):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = sprite(str(pr["sprite"]))
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.albedo_color = RoomSchema.to_color(d.get("color", "#ffffff"))
	# A faint preset is dimmed in its colour and drawn additively: faint whatever else is drawn around it.
	var dim := float(pr.get("opacity", 1.0))
	var tint := mat.albedo_color
	mat.albedo_color = Color(tint.r * dim, tint.g * dim, tint.b * dim, tint.a)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	gp.draw_pass_1 = quad
	return gp


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt: Array in points:
		c.add_point(Vector2(pt[0], pt[1]), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp(points: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(points.map(func(pt: Array) -> float: return pt[0]))
	g.colors = PackedColorArray(points.map(func(pt: Array) -> Color: return pt[1]))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	return t


## A small sprite, made once: soft (a round glow, smooth to its edge), leaf (a soft pointed oval with a vein),
## streak (a thin line fading at both ends). Mipmapped, so it stays smooth far away.
static func sprite(kind: String) -> Texture2D:
	if _sprites.has(kind):
		return _sprites[kind]
	var w := 128 if kind in ["glow", "bokeh"] else 64
	var h := 128 if kind in ["streak", "glow", "bokeh"] else 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var a := 0.0
			match kind:
				"soft":
					var r := sqrt(u * u + v * v)
					a = pow(clampf(1.0 - r, 0.0, 1.0), 1.6)
				"leaf":
					# An oval pointed at both ends, a little darker along its middle.
					var half_w := 0.62 * (1.0 - absf(u)) * (0.5 + 0.5 * (1.0 - absf(u)))
					var edge := clampf((half_w - absf(v)) / 0.08, 0.0, 1.0)
					a = edge * smoothstep(1.0, 0.85, absf(u))
				"streak":
					a = clampf(1.0 - absf(u) * 1.6, 0.0, 1.0) * (1.0 - absf(v)) * (1.0 - absf(v))
				"glow":
					# A bright core (gaussian, about a sixth of the sprite across) in a wide faint halo that falls
					# off smoothly to nothing at the edge: drawn additively, it reads as a small light, not a dot.
					var r := sqrt(u * u + v * v)
					var core := exp(-r * r / 0.005)
					var halo := 0.25 * exp(-r * r / 0.03) + 0.1 * exp(-r * r / 0.1)
					a = clampf((core + halo) * smoothstep(1.0, 0.75, r), 0.0, 1.0)
				"bokeh":
					# An out-of-focus disc: even inside, a slightly brighter rim, a soft edge.
					var r := sqrt(u * u + v * v)
					a = smoothstep(0.92, 0.72, r) * (0.65 + 0.35 * smoothstep(0.45, 0.82, r))
			var shade := 1.0
			if kind == "leaf":
				shade = 0.8 + 0.2 * smoothstep(0.0, 0.08, absf(v))
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_sprites[kind] = tex
	return tex
