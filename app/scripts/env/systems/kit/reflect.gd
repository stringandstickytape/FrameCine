extends RefCounted

## Reflective house materials (shaders/room_material_house_reflect.gdshader; since 2026-11-08, for the drive-in: "chrome
## needs believable reflections done cheaply (sky/cubemap-based specular, not a live probe)", the brief): a light
## system's house material turned into lacquered paint or chrome that shows the sky, a skyline, the ground, the screen
## with the picture's colours and one glint (a neon sign), with no probe and no extra pass. The builder that made them
## calls update() each frame: the sky's colours (they change as dusk falls), the screen's place, the glint's.
## Static; preload to use.
##
##   make(material, metal, amount, roughness, flat_maps) -> material   the material on the reflecting shader
##   update(materials, sky, room, screen_local, screen_size, glint_local, glint_colour, glint_size, screen_level)

const SHADER := preload("res://shaders/room_material_house_reflect.gdshader")
const ProcCache := preload("res://scripts/env/proc_cache.gd")

static var _flat := {}


## A material's maps swapped for flat ones: an even colour (the tint's), a flat normal, this roughness (paint and
## chrome show their reflections, not a texture's grain).
static func flat_maps(roughness: float, metal: float) -> Dictionary:
	var key := "%.2f %.2f" % [roughness, metal]
	if _flat.has(key):
		return _flat[key]
	# Drawn from the values as the key has them (to 0.01), so the key is all the maps depend on: two materials a
	# hair apart get one set of maps, the same in every run, whichever asked first.
	var drawn := ProcCache.images("reflect.gd:_flat:" + key,
			func() -> Array: return _draw_flat_maps(snappedf(roughness, 0.01), snappedf(metal, 0.01)))
	var out := {"albedo": ImageTexture.create_from_image(drawn[0]), "normal": ImageTexture.create_from_image(drawn[1]),
			"orm": ImageTexture.create_from_image(drawn[2])}
	_flat[key] = out
	return out


static func _draw_flat_maps(roughness: float, metal: float) -> Array:
	var albedo := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	albedo.fill(Color(1.0, 1.0, 1.0))
	var normal := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	normal.fill(Color(0.5, 0.5, 0.5, 0.5))
	var orm := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	orm.fill(Color(1.0, roughness, metal))
	return [albedo, normal, orm]


## The material on the reflecting shader. metal 0: a clear coat over paint (Fresnel); 1: chrome. amount: how much it
## reflects. flat: an even surface of this roughness instead of the library's maps (paint, chrome, glass).
static func make(m: ShaderMaterial, metal: float, amount: float, roughness := 0.1, flat := true) -> ShaderMaterial:
	m.shader = SHADER
	if flat:
		var maps := flat_maps(roughness, metal)
		m.set_shader_parameter("albedo_map", maps["albedo"])
		m.set_shader_parameter("normal_map", maps["normal"])
		m.set_shader_parameter("orm_map", maps["orm"])
		m.set_shader_parameter("roughness_scale", 1.0)
		m.set_shader_parameter("normal_strength", 0.0)
		m.set_shader_parameter("ao_strength", 0.0)
	m.set_shader_parameter("reflect_metal", metal)
	m.set_shader_parameter("reflect_amount", amount)
	return m


## The reflections' world now: the sky's colours (sky system or none), the screen (its place in the room's frame and
## size), the glint (in the room's frame; colour times energy; half size in metres), the picture's level.
static func update(materials: Array, sky: Node, room: Node3D, screen_local: Transform3D, screen_size: Vector2,
		glint_local: Vector3, glint_colour: Color, glint_size: Vector2, screen_level: float) -> void:
	if materials.is_empty() or not room.is_inside_tree():
		return
	var zenith := Color(0.02, 0.025, 0.05)
	var horizon := Color(0.05, 0.06, 0.09)
	var glow := Color(0, 0, 0)
	var glow_dir := Vector3(0, 0, -1)
	if sky != null and is_instance_valid(sky) and sky.has_method("sky_light"):
		var l: Dictionary = sky.call("sky_light")
		zenith = l["zenith"]
		horizon = l["horizon"]
		var dusk := float(l.get("dusk", 1.0))
		glow = sky.call("color_param", "glow") * (1.0 - smoothstep(0.0, 0.8, dusk)) * 0.8
		glow_dir = sky.call("glow_direction") if sky.has_method("glow_direction") else glow_dir
	var g := room.global_transform
	var sc := g * screen_local
	var sx := (g.basis * screen_local.basis.x).normalized() * screen_size.x * 0.5
	var sy := (g.basis * screen_local.basis.y).normalized() * screen_size.y * 0.5
	var gp := g * glint_local
	var gd := (g.basis * glow_dir).normalized()
	for m: ShaderMaterial in materials:
		m.set_shader_parameter("refl_zenith", zenith)
		m.set_shader_parameter("refl_horizon", horizon)
		m.set_shader_parameter("refl_glow", glow)
		m.set_shader_parameter("refl_glow_dir", gd)
		m.set_shader_parameter("refl_ground", horizon.darkened(0.85))
		m.set_shader_parameter("refl_screen_centre", sc.origin)
		m.set_shader_parameter("refl_screen_x", sx)
		m.set_shader_parameter("refl_screen_y", sy)
		m.set_shader_parameter("refl_screen_level", screen_level)
		m.set_shader_parameter("refl_glint_pos", gp)
		m.set_shader_parameter("refl_glint_colour", Vector3(glint_colour.r, glint_colour.g, glint_colour.b))
		m.set_shader_parameter("refl_glint_size", glint_size)
