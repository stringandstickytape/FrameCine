extends "res://scripts/env/systems/env_system.gd"

## The vista (docs/environments.md, "The vista"): far scenery round a room, made here from simple shapes, never from a
## file: hills and mesas as silhouettes on the horizon, an acropolis on its hill with floodlit ruins and a town's lamps
## at its foot, birches in snow, cypresses, a pool glowing in a garden. Each item of `items` is one of these, placed by
## its azimuth (degrees from the room's front, positive to the right) and distance. Generic shapes only.
##
## All the items are one mesh, one draw (shaders/env_vista.gdshader). It is lit by the sky (the sky system's colours
## overhead and at the horizon, read every frame, so dusk falls on the hills too; without a sky system, the `light`
## colour) and by the screen's spill where it is near enough to matter. The floodlights, the lamps, the pool's glow and
## the snow are live parameters (a setting or a cue can change them). Nothing moves but the pool's water.

const SHADER := preload("res://shaders/env_vista.gdshader")
const SkySystem := preload("res://scripts/env/systems/sky.gd")
const SHAPES: Array[String] = ["hills", "mesas", "acropolis", "birches", "cypresses", "pool", "cacti"]
## The shader's materials (UV2.x).
const M_ROCK := 0
const M_BARK := 1
const M_FLOOD := 2
const M_FOLIAGE := 3
const M_GROUND := 4
const M_LAMP := 5
const M_TWIG := 6
const M_WATER := 7
const M_POOLSIDE := 8
## Each shape's defaults where an item leaves them out.
const DEFAULTS := {
	"hills": {"azimuth": 0.0, "spread": 360.0, "distance": 160.0, "size": 1.0, "colour": "#141820"},
	"mesas": {"azimuth": 0.0, "spread": 140.0, "distance": 165.0, "size": 1.0, "count": 6, "colour": "#2a1e1c"},
	"acropolis": {"azimuth": 0.0, "spread": 18.0, "distance": 150.0, "size": 1.0, "count": 160,
			"colour": "#1c1a18"},
	"birches": {"azimuth": 0.0, "spread": 120.0, "distance": 40.0, "depth": 25.0, "size": 1.0, "count": 40,
			"colour": "#2a2722"},
	"cypresses": {"azimuth": 0.0, "spread": 90.0, "distance": 30.0, "depth": 10.0, "size": 1.0, "count": 14,
			"colour": "#16261a"},
	"pool": {"azimuth": 0.0, "distance": 14.0, "size": 1.0, "colour": "#16201a"},
	"cacti": {"azimuth": 0.0, "spread": 60.0, "distance": 70.0, "depth": 40.0, "size": 1.0, "count": 16,
			"colour": "#1c2418"},
}
## The grounds (under trees, the pool's lawn) keep this far clear of the room's middle (metres): the room's own floor
## is there, and two floors at one height would fight.
const CLEAR := 8.0
## The acropolis's stone, in the floodlights.
const STONE := Color(0.62, 0.55, 0.44)


static func spec() -> Dictionary:
	var item := {
		"shape": {"type": "enum", "values": SHAPES, "description": "what it is"},
		"azimuth": {"type": "float", "min": -180.0, "max": 180.0,
				"description": "its middle, in degrees from the room's front (positive: to the right)"},
		"spread": {"type": "float", "min": 1.0, "max": 360.0,
				"description": "degrees of the horizon it covers (hills, mesas, the acropolis's hill, trees)"},
		"distance": {"type": "float", "min": 3.0, "max": 170.0, "description": "metres from the room's middle"},
		"depth": {"type": "float", "min": 0.0, "max": 80.0, "description": "trees: metres deep the grove is"},
		"size": {"type": "float", "min": 0.1, "max": 6.0, "description": "times its natural size"},
		"count": {"type": "int", "min": 1, "max": 200,
				"description": "trees, mesas, or the town's lamps under the acropolis"},
		"seed": {"type": "int", "min": 0, "max": 100000, "description": "another arrangement of the same"},
		"floor_y": {"type": "float", "min": -60.0, "max": 60.0, "description": "the height of its ground"},
		"colour": {"type": "color", "description": "its main colour (rock, the hill, the ground, the leaves)"},
	}
	return {
		"kind": "sky",
		"description": "Far scenery round the room, made of simple shapes: hills and mesas on the horizon, an "
				+ "acropolis with floodlit ruins on its hill, birches in snow, cypresses, a pool glowing in a garden, "
				+ "desert cacti and yucca trees. One draw, lit by the sky and by the screen where it is near.",
		"params": {
			"items": {"type": "list", "max": 12, "of": {"type": "object", "fields": item},
					"default": [{"shape": "hills"}],
					"description": "the scenery: [{shape, azimuth, spread, distance, depth, size, count, seed, "
					+ "floor_y, colour}], each shape's own defaults for what it leaves out"},
			"sky_light": {"type": "bool", "default": true,
					"description": "lit by the room's sky system (its colours overhead and at the horizon)"},
			"light": {"type": "color", "default": "#1b2236", "live": true,
					"description": "the sky's light on the scenery when there is no sky system (or sky_light is off)"},
			"spill": {"type": "float", "min": 0.0, "max": 4.0, "default": 1.0,
					"description": "how much the near scenery catches the screen's light"},
			"floodlight": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true,
					"brightness": true, "description": "the floodlights on the acropolis's stone"},
			"flood_colour": {"type": "color", "default": "#ffb46a", "live": true,
					"description": "the floodlights' colour"},
			"town_lights": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.6, "live": true,
					"brightness": true, "description": "the lamps of the town under the acropolis"},
			"pool_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true,
					"brightness": true, "description": "the pool's underwater lights"},
			"pool_colour": {"type": "color", "default": "#2fc8e0", "live": true, "description": "the pool's glow"},
			"snow": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
					"description": "snow on the ground under the trees: 0 none (bind it to a snow setting)"},
			"water_motion": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "live": true,
					"motion": {"max": 1.0}, "description": "how fast the light ripples in the pool"},
			# Since 2026-11-08, for the Palace of Culture 1974 (its birches seen overhead through the open roof); the
			# other rooms keep their trees: frost 0 and no glow by default.
			"frost": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
					"description": "birches in hoar frost: finer twigs, more of them, white with rime against the sky"},
			"room_glow": {"type": "color", "default": "#000000", "live": true,
					"description": "the room's own light thrown up on the scenery near it (an open roof's glow)"},
			"room_glow_level": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.0, "live": true,
					"brightness": true, "description": "how much of room_glow reaches the scenery (a cue takes it down "
					+ "with the house lights); 0: none"},
			"room_glow_at": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [0.0, 10.0, 0.0],
					"description": "where the room's light comes out (an opening in its roof), in the room's frame"},
		},
		"cost": {"draws": 1, "triangles": 9000, "lights": 0, "particles": 0, "texture_mb": 0.3},
		"provides": [],
	}


var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _sky: Node
var _water_time := 0.0
## The first pool: [centre (room frame), axis along, axis across, half size] or [].
var _pool: Array = []
var _last_light: Array = []
## The pool's light placed once the room is in its place (the first frame).
var _placed_once := false
## The items as built, defaults filled (tests).
var built: Array = []

# The mesh being built.
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _i := PackedInt32Array()


func setup() -> void:
	_sky = null
	if bool(params["sky_light"]) and host != null:
		for s: Node in host.systems_of_kind("sky"):
			if s.has_method("sky_light"):
				_sky = s
				break
	_v.clear()
	_n.clear()
	_c.clear()
	_uv.clear()
	_uv2.clear()
	_i.clear()
	_pool = []
	built.clear()
	for raw: Variant in params["items"]:
		if not (raw is Dictionary):
			continue
		var it := item_with_defaults(raw)
		built.append(it)
		match str(it["shape"]):
			"hills":
				_ridge(it, false)
			"mesas":
				_ridge(it, true)
			"acropolis":
				_acropolis(it)
			"birches":
				_birches(it)
			"cypresses":
				_cypresses(it)
			"pool":
				_pool_garden(it)
			"cacti":
				_cacti(it)
	if _v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_INDEX] = _i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("noise_tex", SkySystem.noise_texture())
	_mesh = MeshInstance3D.new()
	_mesh.name = "Vista"
	_mesh.mesh = mesh
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	own(_mesh)
	_apply()
	_light_from_sky(true)


## An item with its shape's defaults filled in.
static func item_with_defaults(raw: Dictionary) -> Dictionary:
	var shape := str(raw.get("shape", "hills"))
	var it: Dictionary = {"shape": shape, "azimuth": 0.0, "spread": 90.0, "distance": 100.0, "depth": 0.0,
			"size": 1.0, "count": 1, "seed": 0, "floor_y": 0.0, "colour": "#202020"}
	it.merge(DEFAULTS.get(shape, {}), true)
	it.merge(raw, true)
	return it


func _apply() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("spill", float(params["spill"]))
	_material.set_shader_parameter("floodlight", float(params["floodlight"]))
	_material.set_shader_parameter("flood_colour", color_param("flood_colour"))
	_material.set_shader_parameter("town_lights", float(params["town_lights"]))
	_material.set_shader_parameter("pool_glow", float(params["pool_glow"]))
	_material.set_shader_parameter("pool_colour", color_param("pool_colour"))
	_material.set_shader_parameter("snow", float(params["snow"]))
	var glow := color_param("room_glow").srgb_to_linear() * float(params["room_glow_level"])
	_material.set_shader_parameter("room_glow", Vector3(glow.r, glow.g, glow.b))
	_place_pool()
	_light_from_sky(true)


func _param_changed(_param: String, _value: Variant) -> void:
	_apply()


func on_room_moved() -> void:
	_place_pool()


func _place_pool() -> void:
	if _material == null or not room.is_inside_tree():
		return
	var g := room.global_transform
	var at: Array = params.get("room_glow_at", [0.0, 10.0, 0.0])
	_material.set_shader_parameter("room_glow_at", g * Vector3(float(at[0]), float(at[1]), float(at[2])))
	if _pool.is_empty():
		return
	_material.set_shader_parameter("pool_centre", g * (_pool[0] as Vector3))
	_material.set_shader_parameter("pool_x", (g.basis * (_pool[1] as Vector3)).normalized())
	_material.set_shader_parameter("pool_z", (g.basis * (_pool[2] as Vector3)).normalized())
	_material.set_shader_parameter("pool_half", _pool[3])


## The sky's light onto the scenery (the sky system's, or the `light` colour): only when it changed.
func _light_from_sky(force := false) -> void:
	if _material == null:
		return
	var top: Color
	var low: Color
	if _sky != null and is_instance_valid(_sky):
		var l: Dictionary = _sky.call("sky_light")
		top = l["zenith"]
		low = l["horizon"]
	else:
		top = color_param("light")
		low = top.lerp(Color(0.0, 0.0, 0.0), 0.3)
	if force or _last_light.is_empty() or not (_last_light[0] as Color).is_equal_approx(top) \
			or not (_last_light[1] as Color).is_equal_approx(low):
		_last_light = [top, low]
		_material.set_shader_parameter("sky_top", top)
		_material.set_shader_parameter("sky_low", low)


func tick(delta: float) -> void:
	if _material == null:
		return
	_light_from_sky()
	if not _pool.is_empty():
		_water_time += float(params["water_motion"]) * delta
		_material.set_shader_parameter("water_time", _water_time)
	if not _placed_once:
		_placed_once = true
		_place_pool()


## The shader's light on the scenery now: [top, low] (tests).
func light_now() -> Array:
	return _last_light


func material() -> ShaderMaterial:
	return _material


func mesh_instance() -> MeshInstance3D:
	return _mesh


# --- Mesh helpers -----------------------------------------------------------------------------------------------------

static func _dir(az_deg: float) -> Vector3:
	var a := deg_to_rad(az_deg)
	return Vector3(sin(a), 0.0, -cos(a))


## The horizontal direction to the right of _dir(az).
static func _side(az_deg: float) -> Vector3:
	var a := deg_to_rad(az_deg)
	return Vector3(cos(a), 0.0, sin(a))


func _vert(p: Vector3, n: Vector3, col: Color, uv: Vector2, mat: int, extra := 0.0) -> int:
	_v.append(p)
	_n.append(n)
	_c.append(col)
	_uv.append(uv)
	_uv2.append(Vector2(mat, extra))
	return _v.size() - 1


## A quad a-b-c-d (any winding: the shader draws both sides).
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, mat: int, hf := Vector4(0, 0, 1, 1),
		uvs: Array = [], extra := 0.0) -> void:
	var u: Array = uvs if uvs.size() == 4 else [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var k := _v.size()
	var hs := [hf.x, hf.y, hf.z, hf.w]
	var ps := [a, b, c, d]
	for i in 4:
		var cc := col
		cc.a = hs[i]
		_vert(ps[i], n, cc, u[i], mat, extra)
	_i.append_array([k, k + 1, k + 2, k, k + 2, k + 3])


## A box's faces (the ones named; all by default) from its centre, half sizes and frame. hf: the height fraction at its
## bottom and top (for the floodlight's fall).
func _box(centre: Vector3, half: Vector3, basis: Basis, col: Color, mat: int, hf := Vector2(0, 1),
		faces := "tbnsew") -> void:
	var x := basis.x * half.x
	var y := basis.y * half.y
	var z := basis.z * half.z
	var lo := Vector4(hf.x, hf.x, hf.y, hf.y)
	if "n" in faces:
		_quad(centre - x - y - z, centre + x - y - z, centre + x + y - z, centre - x + y - z, -basis.z, col, mat, lo)
	if "s" in faces:
		_quad(centre - x - y + z, centre + x - y + z, centre + x + y + z, centre - x + y + z, basis.z, col, mat, lo)
	if "w" in faces:
		_quad(centre - x - y - z, centre - x - y + z, centre - x + y + z, centre - x + y - z, -basis.x, col, mat, lo)
	if "e" in faces:
		_quad(centre + x - y - z, centre + x - y + z, centre + x + y + z, centre + x + y - z, basis.x, col, mat, lo)
	if "t" in faces:
		_quad(centre - x + y - z, centre + x + y - z, centre + x + y + z, centre - x + y + z, basis.y, col, mat,
				Vector4(hf.y, hf.y, hf.y, hf.y))
	if "b" in faces:
		_quad(centre - x - y - z, centre + x - y - z, centre + x - y + z, centre - x - y + z, -basis.y, col, mat,
				Vector4(hf.x, hf.x, hf.x, hf.x))


static func _lin(c: Variant) -> Color:
	var col := RoomSchemaRef.to_color(c)
	var l := col.srgb_to_linear()
	return Color(l.r, l.g, l.b, 1.0)


# --- The shapes -----------------------------------------------------------------------------------------------------------

## Hills or mesas: a silhouette strip along an arc of the horizon, facing the room, from under the ground to the profile.
func _ridge(it: Dictionary, mesas: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(it["seed"]) + (11 if mesas else 3)
	var d := float(it["distance"])
	var spread := float(it["spread"])
	var y0 := float(it["floor_y"])
	var col := _lin(it["colour"])
	var top := d * tan(deg_to_rad((5.0 if mesas else 2.5) * float(it["size"])))
	var step := 0.3 if mesas else 1.0
	var steps := maxi(2, ceili(spread / step))
	var from := float(it["azimuth"]) - spread * 0.5
	var phases := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var tops: Array = []
	if mesas:
		var count := int(it["count"])
		for m in count:
			var c := from + spread * (m + 0.5 + rng.randf_range(-0.3, 0.3)) / count
			var w := spread / count * rng.randf_range(0.12, 0.38)
			tops.append([c, w, w * rng.randf_range(0.25, 0.5), top * rng.randf_range(0.45, 1.0)])
	var prev := -1
	for i in steps + 1:
		var az := from + spread * float(i) / steps
		var a := deg_to_rad(az)
		var h: float
		if mesas:
			h = top * 0.1 * (1.0 + 0.5 * sin(a * 5.0 + phases[0]))
			for m: Array in tops:
				var f := clampf((float(m[1]) + float(m[2]) - absf(az - float(m[0]))) / float(m[2]), 0.0, 1.0)
				h = maxf(h, float(m[3]) * pow(f, 0.6))
		else:
			h = top * (0.5 + 0.3 * sin(a * 3.0 + phases[0]) * sin(a * 1.3 + phases[1]) + 0.2 * sin(a * 7.0 + phases[2]))
			h = maxf(h, top * 0.1)
		if spread < 360.0:
			# The ends come down to the ground.
			var edge := minf(float(i), float(steps - i)) / maxf(steps * 0.08, 1.0)
			h *= clampf(edge, 0.0, 1.0)
		var dir := _dir(az)
		var n := (-dir + Vector3.UP * 0.25).normalized()
		var lo_c := col
		lo_c.a = 0.0
		var hi_c := col
		hi_c.a = 1.0
		var k := _vert(dir * d + Vector3(0, y0 - 4.0, 0), n, lo_c, Vector2(float(i) / steps, 0.0), M_ROCK)
		_vert(dir * d + Vector3(0, y0 + h, 0), n, hi_c, Vector2(float(i) / steps, 1.0), M_ROCK)
		if prev >= 0:
			_i.append_array([prev, prev + 1, k + 1, prev, k + 1, k])
		prev = k


## An acropolis: a rounded hill with a flat top and a wall round it, a ruined temple of columns on it and a smaller one
## beside, all floodlit from below, and a town's lamps at the hill's foot.
func _acropolis(it: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(it["seed"]) + 29
	var d := float(it["distance"])
	var spread := float(it["spread"])
	var y0 := float(it["floor_y"])
	var size := float(it["size"])
	var az0 := float(it["azimuth"])
	var hill_h := d * tan(deg_to_rad(3.0 * size))
	var col := _lin(it["colour"])
	var steps := maxi(8, ceili(spread / 0.25))
	var prev := -1
	var wall_h := hill_h * 0.09
	for i in steps + 1:
		var x := float(i) / steps * 2.0 - 1.0
		var az := az0 + x * spread * 0.5
		var f := clampf(1.0 - pow(maxf(absf(x) - 0.38, 0.0) / 0.62, 1.7), 0.0, 1.0)
		var h := hill_h * f * (0.96 + 0.04 * sin(x * 23.0))
		var dir := _dir(az)
		var n := (-dir + Vector3.UP * 0.2).normalized()
		var lo_c := col
		lo_c.a = 0.0
		var hi_c := col
		hi_c.a = 1.0
		var k := _vert(dir * d + Vector3(0, y0 - 4.0, 0), n, lo_c, Vector2(x, 0.0), M_ROCK)
		_vert(dir * d + Vector3(0, y0 + h, 0), n, hi_c, Vector2(x, 1.0), M_ROCK)
		if prev >= 0:
			_i.append_array([prev, prev + 1, k + 1, prev, k + 1, k])
		prev = k
	# The wall round the top, floodlit.
	var wall_from := -0.42
	var wall_to := 0.42
	var wsteps := 24
	for i in wsteps:
		var xa := lerpf(wall_from, wall_to, float(i) / wsteps)
		var xb := lerpf(wall_from, wall_to, float(i + 1) / wsteps)
		var da := _dir(az0 + xa * spread * 0.5) * (d - 0.4)
		var db := _dir(az0 + xb * spread * 0.5) * (d - 0.4)
		var n := -_dir(az0 + (xa + xb) * 0.25 * spread)
		var base := y0 + hill_h - wall_h * 0.6
		_quad(da + Vector3(0, base, 0), db + Vector3(0, base, 0), db + Vector3(0, base + wall_h, 0),
				da + Vector3(0, base + wall_h, 0), n, STONE.lerp(col, 0.25), M_FLOOD, Vector4(0, 0, 0.5, 0.5))
	# The temple: its long side to the room, turned a little, on the top behind the wall.
	var width := d * tan(deg_to_rad(4.2 * size))
	var deep := width * 0.44
	var centre := _dir(az0 + spread * 0.04) * (d + deep * 0.6) + Vector3(0, y0 + hill_h - wall_h * 0.2, 0)
	var basis := Basis(Vector3.UP, deg_to_rad(-az0 - 22.0))
	_temple(centre, width, deep, basis, rng, 17, 8, 2)
	# A smaller one to the side, with fewer columns.
	var c2 := _dir(az0 - spread * 0.22) * (d + deep * 0.3) + Vector3(0, y0 + hill_h * 0.97 - wall_h * 0.2, 0)
	_temple(c2, width * 0.36, width * 0.22, Basis(Vector3.UP, deg_to_rad(-az0 + 8.0)), rng, 6, 4, 0)
	# The town's lamps at the hill's foot and in front of it.
	var lamp := tan(deg_to_rad(0.09)) * d
	for i in int(it["count"]):
		var x := rng.randf_range(-1.6, 1.6)
		var az := az0 + x * spread * 0.5
		var dist := d * rng.randf_range(0.82, 0.98)
		var rise := hill_h * 0.3 * clampf(1.0 - absf(x), 0.0, 1.0) * rng.randf()
		var p := _dir(az) * dist + Vector3(0, y0 + rise + 0.2, 0)
		var s := _side(az) * lamp * rng.randf_range(0.6, 1.2)
		var u := Vector3.UP * lamp * rng.randf_range(0.6, 1.0)
		var warm := Color(1.0, 0.72, 0.42) if rng.randf() < 0.8 else Color(0.8, 0.88, 1.0)
		_quad(p - s - u, p + s - u, p + s + u, p - s + u, -_dir(az), warm, M_LAMP)


## A ruined temple: a platform, a ring of columns (long sides `along`, short sides `across`), its beams and the
## pediments at the short ends; `missing` columns gone. Floodlit stone, brighter low down.
func _temple(centre: Vector3, width: float, deep: float, basis: Basis, rng: RandomNumberGenerator, along: int,
		across: int, missing: int) -> void:
	var plat := width * 0.025
	var col_h := width * 0.16
	var beam := width * 0.05
	var total := plat + col_h + beam + width * 0.06
	var hf := func(y: float) -> float: return clampf(y / total, 0.0, 1.0)
	_box(centre + basis.y * plat * 0.5, Vector3(width * 0.53, plat * 0.5, deep * 0.55), basis, STONE, M_FLOOD,
			Vector2(0.0, hf.call(plat)), "tnsew")
	var r := width * 0.014
	var gone := {}
	for i in missing:
		gone[rng.randi_range(2, along - 3)] = true
	var spots: Array = []
	for i in along:
		var x := lerpf(-width * 0.5, width * 0.5, float(i) / (along - 1))
		if not gone.has(i):
			spots.append(Vector2(x, -deep * 0.5))
		spots.append(Vector2(x, deep * 0.5))
	for j in range(1, across - 1):
		var z := lerpf(-deep * 0.5, deep * 0.5, float(j) / (across - 1))
		spots.append(Vector2(-width * 0.5, z))
		spots.append(Vector2(width * 0.5, z))
	for s: Vector2 in spots:
		var c := centre + basis.x * s.x + basis.z * s.y + basis.y * (plat + col_h * 0.5)
		_box(c, Vector3(r, col_h * 0.5, r), basis, STONE, M_FLOOD, Vector2(hf.call(plat), hf.call(plat + col_h)),
				"nsew")
	# The beams over the columns.
	var by := plat + col_h + beam * 0.5
	var bh := Vector2(hf.call(plat + col_h), hf.call(plat + col_h + beam))
	for z: float in [-deep * 0.5, deep * 0.5]:
		_box(centre + basis.y * by + basis.z * z, Vector3(width * 0.5 + r, beam * 0.5, r * 1.3), basis, STONE,
				M_FLOOD, bh)
	for x: float in [-width * 0.5, width * 0.5]:
		_box(centre + basis.y * by + basis.x * x, Vector3(r * 1.3, beam * 0.5, deep * 0.5 + r), basis, STONE,
				M_FLOOD, bh)
		# The pediment: a low triangle over the short end.
		var top := plat + col_h + beam
		var a := centre + basis.x * x + basis.y * top - basis.z * (deep * 0.5 + r)
		var b := centre + basis.x * x + basis.y * top + basis.z * (deep * 0.5 + r)
		var p := centre + basis.x * x + basis.y * (top + width * 0.06)
		var k := _v.size()
		var lo := STONE
		lo.a = hf.call(top)
		var hi := STONE
		hi.a = 1.0
		var n := basis.x * signf(x)
		_vert(a, n, lo, Vector2(0, 0), M_FLOOD)
		_vert(b, n, lo, Vector2(1, 0), M_FLOOD)
		_vert(p, n, hi, Vector2(0.5, 1), M_FLOOD)
		_i.append_array([k, k + 1, k + 2])


## Birches in snow: white trunks with dark marks, bare branches, and the snowy ground under them.
func _birches(it: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(it["seed"]) + 41
	var d := float(it["distance"])
	var spread := float(it["spread"])
	var depth := float(it["depth"])
	var y0 := float(it["floor_y"])
	var size := float(it["size"])
	_ground(it, _lin(it["colour"]))
	# Frost: rime on every twig (pale against the night), the twigs finer and more of them.
	var frost := float(params.get("frost", 0.0))
	var twig := Color(0.1, 0.085, 0.075).lerp(Color(0.62, 0.64, 0.7), frost)
	var thin := lerpf(1.0, 0.5, frost)
	for t in int(it["count"]):
		var az := float(it["azimuth"]) + rng.randf_range(-0.5, 0.5) * spread
		var dist := maxf(3.0, d + rng.randf_range(-0.5, 0.5) * depth)
		var base := _dir(az) * dist + Vector3(0, y0, 0)
		var side := _side(az)
		var n := -_dir(az)
		var h := rng.randf_range(10.0, 17.0) * size
		var w := 0.15 * size * rng.randf_range(0.8, 1.2)
		var lean := side * rng.randf_range(-0.04, 0.04) * h
		var extra := rng.randf()
		var rows := 4
		var k0 := _v.size()
		for r in rows + 1:
			var f := float(r) / rows
			var c := base + Vector3.UP * h * f + lean * f * f
			var ww := w * lerpf(1.0, 0.3, f)
			var col := Color(1, 1, 1, f)
			_vert(c - side * ww, n, col, Vector2(0.0, h * f), M_BARK, extra)
			_vert(c + side * ww, n, col, Vector2(1.0, h * f), M_BARK, extra)
		for r in rows:
			var k := k0 + r * 2
			_i.append_array([k, k + 1, k + 3, k, k + 3, k + 2])
		for b in 11 + int(10.0 * frost):
			var f := rng.randf_range(0.35, 0.95)
			var start := base + Vector3.UP * h * f + lean * f * f
			var out := side * (1.0 if rng.randf() < 0.5 else -1.0)
			var up := deg_to_rad(rng.randf_range(25.0, 65.0))
			var length := h * rng.randf_range(0.1, 0.26) * (1.0 - f * 0.45)
			var tip := start + (out * cos(up) + Vector3.UP * sin(up)) * length
			_branch(start, tip, n, 0.035 * size * thin, twig)
			if rng.randf() < 0.6 + 0.3 * frost:
				var mid := start.lerp(tip, 0.6)
				var up2 := up + deg_to_rad(rng.randf_range(15.0, 35.0))
				_branch(mid, mid + (out * cos(up2) + Vector3.UP * sin(up2)) * length * 0.5, n, 0.02 * size * thin, twig)
			if frost > 0.0:
				# A birch's fine twigs hang from its branches: a few drooping strands from each.
				for k in 3:
					var from := start.lerp(tip, rng.randf_range(0.4, 1.0))
					var hang := from + (out * rng.randf_range(0.2, 0.5) - Vector3.UP * rng.randf_range(0.5, 1.1)) \
							* length * 0.35
					_branch(from, hang, n, 0.012 * size, twig)


func _branch(a: Vector3, b: Vector3, n: Vector3, w: float, col: Color) -> void:
	var along := (b - a).normalized()
	var across := along.cross(n).normalized() * w
	_quad(a - across, a + across, b + across * 0.4, b - across * 0.4, n, col, M_TWIG)


## The ground under trees: an arc of the floor round the grove (snow, or the colour under it).
func _ground(it: Dictionary, col: Color) -> void:
	var d := float(it["distance"])
	var depth := float(it["depth"])
	var spread := float(it["spread"])
	var inner := maxf(CLEAR, d - depth * 0.5 - 6.0)
	var outer := minf(170.0, d + depth * 0.5 + 30.0)
	var from := float(it["azimuth"]) - spread * 0.5 - 10.0
	var to := float(it["azimuth"]) + spread * 0.5 + 10.0
	var steps := maxi(2, ceili((to - from) / 3.0))
	var y := float(it["floor_y"])
	for i in steps:
		var a := from + (to - from) * float(i) / steps
		var b := from + (to - from) * float(i + 1) / steps
		_quad(_dir(a) * inner + Vector3(0, y, 0), _dir(b) * inner + Vector3(0, y, 0),
				_dir(b) * outer + Vector3(0, y, 0), _dir(a) * outer + Vector3(0, y, 0), Vector3.UP, col, M_GROUND)


## Cypresses: tall, narrow, flame-shaped trees, dark green.
func _cypresses(it: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(it["seed"]) + 53
	var d := float(it["distance"])
	var spread := float(it["spread"])
	var depth := float(it["depth"])
	var y0 := float(it["floor_y"])
	var size := float(it["size"])
	var col := _lin(it["colour"])
	var profile := [[0.0, 0.3], [0.08, 0.8], [0.25, 1.0], [0.5, 0.85], [0.72, 0.55], [0.9, 0.22], [1.0, 0.0]]
	var sides := 7
	for t in int(it["count"]):
		var az := float(it["azimuth"]) + rng.randf_range(-0.5, 0.5) * spread
		var dist := maxf(3.0, d + rng.randf_range(-0.5, 0.5) * depth)
		var base := _dir(az) * dist + Vector3(0, y0, 0)
		var h := rng.randf_range(11.0, 17.0) * size
		var rmax := 0.95 * size * rng.randf_range(0.8, 1.2)
		var extra := rng.randf()
		var spin := rng.randf() * TAU
		var k0 := _v.size()
		for p: Array in profile:
			for s in sides + 1:
				var a := spin + TAU * s / sides
				var out := Vector3(cos(a), 0.0, sin(a))
				var r := rmax * float(p[1])
				var n := (out + Vector3.UP * 0.35).normalized()
				var c := col
				c.a = float(p[0])
				_vert(base + out * r + Vector3.UP * h * float(p[0]), n, c, Vector2(float(s) / sides, h * float(p[0])),
						M_FOLIAGE, extra)
		var row := sides + 1
		for ring in profile.size() - 1:
			for s in sides:
				var k := k0 + ring * row + s
				_i.append_array([k, k + 1, k + row + 1, k, k + row + 1, k + row])


## Desert plants (since 2026-11-08, the drive-in): tall columnar cacti with arms that turn up, and branching yucca
## trees with a spiky tuft at each branch's end, scattered over a stretch of desert; dark against the sky after sunset.
## Generic shapes (no particular species' likeness beyond the kind). Their bases go into the ground a little, so a
## swell of the plain never leaves one standing on air.
func _cacti(it: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(it["seed"]) + 71
	var d := float(it["distance"])
	var spread := float(it["spread"])
	var depth := float(it["depth"])
	var y0 := float(it["floor_y"])
	var size := float(it["size"])
	var col := _lin(it["colour"])
	for t in int(it["count"]):
		var az := float(it["azimuth"]) + rng.randf_range(-0.5, 0.5) * spread
		var dist := maxf(3.0, d + rng.randf_range(-0.5, 0.5) * depth)
		var base := _dir(az) * dist + Vector3(0, y0 - 0.6, 0)
		var c := col * rng.randf_range(0.8, 1.15)
		if rng.randf() < 0.6:
			# A column with up to three arms.
			var h := rng.randf_range(4.5, 9.0) * size
			var r := rng.randf_range(0.26, 0.4) * size
			_tube([base, base + Vector3(0, h * 0.6, 0), base + Vector3(0, h - r, 0), base + Vector3(0, h, 0)],
					[r, r, r * 0.92, r * 0.35], c)
			for k in rng.randi_range(0, 3):
				var a := rng.randf() * TAU
				var out := Vector3(cos(a), 0, sin(a))
				var y := h * rng.randf_range(0.35, 0.6)
				var reach := rng.randf_range(0.7, 1.2) * size
				var up := rng.randf_range(1.2, 2.8) * size
				var p0 := base + Vector3(0, y, 0)
				_tube([p0, p0 + out * reach * 0.7 + Vector3(0, 0.1, 0), p0 + out * reach + Vector3(0, 0.5, 0),
						p0 + out * reach + Vector3(0, up, 0), p0 + out * reach + Vector3(0, up + r * 0.7, 0)],
						[r * 0.7, r * 0.7, r * 0.7, r * 0.7, r * 0.25], c)
		else:
			# A yucca tree: a leaning trunk forking twice or three times, a tuft at each end.
			var h := rng.randf_range(2.5, 4.5) * size
			var lean := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
			var top := base + lean * h
			_tube([base, base + lean * h * 0.5, top], [0.22 * size, 0.18 * size, 0.15 * size], c * 0.85)
			var ends: Array = [[top, lean, 0]]
			var tips: Array = []
			while not ends.is_empty():
				var e: Array = ends.pop_back()
				var at: Vector3 = e[0]
				var dirv: Vector3 = e[1]
				var level := int(e[2])
				if level >= 2 or (level >= 1 and rng.randf() < 0.3):
					tips.append(at)
					continue
				for k in 2 + int(rng.randf() < 0.3):
					var a := rng.randf() * TAU
					var nd := (dirv * 0.6 + Vector3(cos(a), 0.3, sin(a)) * 0.8).normalized()
					var len := rng.randf_range(0.8, 1.5) * size
					var to := at + nd * len
					_tube([at, to], [0.12 * size, 0.09 * size], c * 0.85)
					ends.append([to, Vector3(nd.x, maxf(nd.y, 0.4), nd.z).normalized(), level + 1])
			for p: Vector3 in tips:
				_tuft(p, 0.55 * size, c)


## A tube along a polyline with a radius at each point (five sides: far off, a smooth column).
func _tube(points: Array, radii: Array, col: Color) -> void:
	var sides := 5
	var k0 := _v.size()
	for i in points.size():
		var p: Vector3 = points[i]
		var along: Vector3 = ((points[mini(i + 1, points.size() - 1)] as Vector3) - (points[maxi(i - 1, 0)] as Vector3))
		along = along.normalized() if along.length() > 0.001 else Vector3.UP
		var u := along.cross(Vector3.FORWARD if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
		var w := along.cross(u).normalized()
		for s in sides + 1:
			var a := TAU * s / sides
			var out := u * cos(a) + w * sin(a)
			var c := col
			c.a = clampf(p.y / 8.0, 0.0, 1.0)
			_vert(p + out * float(radii[i]), out, c, Vector2(float(s) / sides, p.y), M_TWIG)
	var row := sides + 1
	for i in points.size() - 1:
		for s in sides:
			var k := k0 + i * row + s
			_i.append_array([k, k + 1, k + row + 1, k, k + row + 1, k + row])


## A spiky tuft: six thin blades out from a point.
func _tuft(at: Vector3, r: float, col: Color) -> void:
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		var out := Vector3(cos(a), 0.55 + 0.4 * float(k % 2), sin(a)).normalized()
		var side := out.cross(Vector3.UP).normalized() * r * 0.12
		var c := col * 0.8
		c.a = 1.0
		var k0 := _v.size()
		_vert(at - side, out, c, Vector2.ZERO, M_TWIG)
		_vert(at + side, out, c, Vector2.ZERO, M_TWIG)
		_vert(at + out * r, out, c, Vector2.ZERO, M_TWIG)
		_i.append_array([k0, k0 + 1, k0 + 2])


## A pool glowing in a garden: the water and its walls lit from below, the stone coping, a lawn round it that takes
## its glow, and a hedge behind.
func _pool_garden(it: Dictionary) -> void:
	var d := float(it["distance"])
	var size := float(it["size"])
	var az := float(it["azimuth"])
	var y := float(it["floor_y"])
	var along := _side(az)
	var across := _dir(az)
	var centre := across * d + Vector3(0, y, 0)
	var hl := 4.5 * size
	var hw := 2.0 * size
	var deep := 0.25
	if _pool.is_empty():
		_pool = [centre, along, across, Vector2(hl, hw)]
	var water := Color(1, 1, 1, 0)
	var corners := [centre - along * hl - across * hw, centre + along * hl - across * hw,
			centre + along * hl + across * hw, centre - along * hl + across * hw]
	var dn := Vector3.UP * -deep
	_quad(corners[0] + dn, corners[1] + dn, corners[2] + dn, corners[3] + dn, Vector3.UP, water, M_WATER,
			Vector4(0, 0, 0, 0), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], 0.5)
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var n := (centre - (a + b) * 0.5).normalized()
		_quad(a + dn, b + dn, b, a, n, water, M_WATER, Vector4(0, 0, 0, 0), [], 0.9)
	# The coping and the lawn: rings of quads round the water.
	var stone := Color(0.42, 0.4, 0.36)
	_ring(centre, along, across, hl, hw, 0.45, y + 0.01, stone, M_POOLSIDE)
	var lawn := clampf(d - hw - 0.45 - CLEAR, 1.0, 14.0)
	_ring(centre, along, across, hl + 0.45, hw + 0.45, lawn, y, _lin(it["colour"]), M_POOLSIDE)
	# The hedge behind it.
	var hedge := Color(0.03, 0.07, 0.035)
	_box(centre + across * (hw + 7.0) + Vector3.UP * 0.9, Vector3(hl + 5.0, 0.9, 0.6),
			Basis(along, Vector3.UP, across), hedge, M_FOLIAGE, Vector2(0, 1), "tnsew")


## A flat rectangular ring of quads round a rectangle (half sizes hl, hw), `width` wide, at height y.
func _ring(centre: Vector3, along: Vector3, across: Vector3, hl: float, hw: float, width: float, y: float, col: Color,
		mat: int) -> void:
	var c := Vector3(centre.x, y, centre.z)
	var il := along * hl
	var iw := across * hw
	var ol := along * (hl + width)
	var ow := across * (hw + width)
	_quad(c - ol - ow, c + ol - ow, c + ol - iw, c - ol - iw, Vector3.UP, col, mat)
	_quad(c - ol + iw, c + ol + iw, c + ol + ow, c - ol + ow, Vector3.UP, col, mat)
	_quad(c - ol - iw, c - il - iw, c - il + iw, c - ol + iw, Vector3.UP, col, mat)
	_quad(c + il - iw, c + ol - iw, c + ol + iw, c + il + iw, Vector3.UP, col, mat)
