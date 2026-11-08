extends RefCounted

## The Ice cinema's pieces (docs/environments.md, "The kit" and "Room: Ice cinema"; since 2026-11-08, "continue
## working on the environments one-by-one ... really improving their quality, imagination, delight, detail, lighting
## and so on", the user, 2026-11-08). An ice hotel's cinema far in the Arctic: walls of sawn ice blocks you can read
## (each its own clearness, bubbles and cracks frozen deep inside, snow in the joints), a vault of packed snow on ribs
## of clear ice with clear-ice skylights in its haunches where the aurora shows, candles in niches whose glow sits
## inside the ice round them, the screen in a carved frame with animals in relief round it (a polar bear, a whale, a
## fox, a hare, a snowy owl), benches of ice under the hides, and outside the window and the doorway a moonlit
## snowfield, spruces under snow, the fells and a cabin far off with its windows lit.
## Everything is ours, drawn here; no figure anywhere.
##
## Pieces (pieces.gd dispatches here; they read the room's domestic builder, style ice, shell "kit"):
##   ice_shell    the floor, the walls of blocks (cut round the window, the doorway and the niches), the vault with
##                its ribs and skylights, the window's and the doorway's reveals, the niches and their candles
##   ice_screen   the screen's smoothed panel, its carved frame and the reliefs on the front wall
##   ice_benches  a bench of ice under each row of the room's seats (the seats system lays the hides on them)
##   ice_outside  the night outside: snowfield, drifts, the path from the doorway, spruces, the fells, a cabin
##
## Materials: the ice is the light system's house material on shaders/room_material_house_ice.gdshader (fake depth,
## the candles' glow inside, the film seeping through round the screen; per-vertex tint and clearness); the snow
## (joints, vault, floor) a house material; the outside its own unshaded shader (env_ice_outside.gdshader), not dimmed
## by the house lights. The candles' flames are the light system's accent group: the ritual takes them low for the
## film and the glow inside the ice follows them.
## Cost: IceBlocks (baked, the ice), IceSnow (baked), IceWax (unbaked), IceFlames, IceGlass (the panes), IceOutside.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Domestic := preload("res://scripts/env/systems/domestic.gd")
const ICE_SHADER := preload("res://shaders/room_material_house_ice.gdshader")
const OUTSIDE_SHADER := preload("res://shaders/env_ice_outside.gdshader")

const PIECES: Array[String] = ["ice_shell", "ice_screen", "ice_benches", "ice_outside"]

## The walls' thickness (the doorway's tunnel, the window's reveal, the niches' depth behind the face).
const THICK := 0.7
## A block's face stands this far out of the joints, its edges chamfered this much; the joints this wide.
const PROUD := 0.035
const BEVEL := 0.012
const JOINT := 0.012
## The courses' height (five to the side walls' top).
const COURSE := 0.44
## The vault's ribs (z in the room) and the bays between them with skylights (their index from the front).
const RIB_DEPTH := 0.11
const RIB_WIDTH := 0.26
## Skylights: the arc's segments (of VAULT_SEGMENTS over the half ellipse) on each side, the bays that have them.
const VAULT_SEGMENTS := 24
const SKY_LEFT := [19, 22]
const SKY_RIGHT := [2, 5]
const SKY_BAYS := [2, 3, 4]
## The candles' flame colour, and the glow they give the ice (energy, metres to fall to a third).
const FLAME := Color(1.0, 0.62, 0.3)
const CANDLE_GLOW := 1.5
const CANDLE_REACH := 0.5
## A candle's light in the bake (a share of the kit's lamp), and the niches' size.
const CANDLE_BAKE := 0.25
const NICHE := Vector2(0.4, 0.44)
const NICHE_DEPTH := 0.26
## Colours (linear): the ice's face, the snow, the wax.
const ICE_TINT := Color(0.24, 0.29, 0.32)
const SNOW := Color(0.8, 0.86, 0.95)
## What the fill shows deep in the ice (sRGB), and how much of the screen's spill the ice and the snow take (the
## light system's is for the whole room; the ice takes the film's colour inside it instead, round the screen).
const ICE_DEEP := Color(0.5, 0.78, 0.9)
const ICE_SPILL := 0.5
## The night's light through the walls (the snow and the Moon outside): a faint cold glow in the clear ice.
const ICE_NIGHT := 0.035
const SNOW_SPILL := 0.2
const WAX := Color(0.92, 0.86, 0.72)


## The hall's meshes over its pieces (kept on the kit's ctx.ice), and what finish() adds.
class Hall:
	var ice := RoomMesh.new()
	var snow := RoomMesh.new()
	var wax := RoomMesh.new()
	var glass := RoomMesh.new()
	var outside := RoomMesh.new()
	var fur := RoomMesh.new()
	## Flame quads by light group ({group: [[centre, half across, half up, facing]]}) and the candles [position,
	## energy, group].
	var flames := {}
	var candles: Array = []
	var p := {}
	var rng := RandomNumberGenerator.new()
	var ice_m: ShaderMaterial
	var snow_m: ShaderMaterial
	var wax_m: ShaderMaterial
	var outside_m: ShaderMaterial
	var fur_m: ShaderMaterial
	var screen := {}
	var kit: Node
	var sky: Node
	## The niches already cut, per wall: [Rect2 (along, up)].
	var niches := {}
	## The kit's lamps (ctx.lamps): each candle's light in the bake.
	var kit_lamps: Array = []
	## The kit's floodlights for the bake (ctx.spots): the Moon's light through the window.
	var kit_spots: Array = []

	## Adds the meshes once every piece has drawn (kit.gd calls it).
	func finish(k: Node) -> void:
		if ice.triangle_count() > 0:
			k._add_static("IceBlocks", ice)
		if snow.triangle_count() > 0:
			k._add_static("IceSnow", snow)
		if fur.triangle_count() > 0:
			k._add_static("IceFurs", fur)
		if wax.triangle_count() > 0:
			k._add_unbaked("IceWax", wax)
		if glass.triangle_count() > 0:
			k._add_glass("IceGlass", glass, Color(0.7, 0.86, 0.95), 0.07)
		for group: String in flames:
			k._add_glow("IceFlames" if group == "accent" else "IceFlames_" + group, flames[group], Procedural.flame(),
					FLAME, 1.6, group, false)
		if outside.triangle_count() > 0:
			var mi: MeshInstance3D = k._add_unbaked("IceOutside", outside)
			mi.material_override = outside_m
		_set_glows()
		for s: Node in k.host.systems_of_kind("sky"):
			if s.has_method("sky_light"):
				sky = s
				break
		tick(0.0)

	## The candles' places in the ice's shader.
	func _set_glows() -> void:
		if ice_m == null:
			return
		var pos := PackedVector4Array()
		for cd: Array in candles:
			var at: Vector3 = cd[0]
			pos.append(Vector4(at.x, at.y, at.z, CANDLE_REACH))
		while pos.size() < 12:
			pos.append(Vector4.ZERO)
		ice_m.set_shader_parameter("ice_glow_pos", pos)
		ice_m.set_shader_parameter("ice_glow_count", mini(candles.size(), 12))
		ice_m.set_shader_parameter("ice_glow_level", 1.0)
		_glow_levels.clear()

	## The candles' light in the ice, each as bright as its group is now (accent: the niches; house: the front
	## wall's, which go lower for the film). Set only when a level changes.
	var _glow_levels := {}

	func _set_glow_colours() -> void:
		var levels := {}
		for cd: Array in candles:
			levels[cd[2]] = kit._group_level(str(cd[2]))
		if levels == _glow_levels:
			return
		_glow_levels = levels
		var col := PackedVector4Array()
		for cd: Array in candles:
			var c: Color = FLAME * CANDLE_GLOW * float(cd[1]) * float(levels[cd[2]])
			col.append(Vector4(c.r, c.g, c.b, 0.0))
		while col.size() < 12:
			col.append(Vector4.ZERO)
		ice_m.set_shader_parameter("ice_glow_col", col)

	## The glow in the ice now, candle by candle (tests): [colour x energy].
	func glow_colours() -> PackedVector4Array:
		return ice_m.get_shader_parameter("ice_glow_col") if ice_m != null else PackedVector4Array()

	## Each frame: the candles' levels (their groups': the ritual's), and the night's light outside from the sky.
	func tick(_delta: float) -> void:
		if ice_m != null and kit != null:
			_set_glow_colours()
		if outside_m == null or kit == null or not kit.room.is_inside_tree():
			return
		var basis: Basis = kit.room.global_transform.basis
		var zenith := Color(0.02, 0.03, 0.06)
		var horizon := Color(0.05, 0.06, 0.09)
		var moon := Vector3(0.0, 0.3, -1.0)
		var moon_level := 0.0
		var aurora := 0.0
		var aurora_dir := Vector3.LEFT
		var aurora_colour := Color(0.36, 1.0, 0.62)
		if sky != null and is_instance_valid(sky):
			var l: Dictionary = sky.call("sky_light")
			zenith = l["zenith"]
			horizon = l["horizon"]
			var md: Vector3 = sky.call("moon_direction")
			if md != Vector3.ZERO:
				moon = md
				moon_level = float(sky.params.get("moon", 0.0))
			aurora = float(sky.params.get("aurora", 0.0))
			aurora_dir = sky.call("bearing_dir", float(sky.params["aurora_bearing"]), float(sky.params["facing"]))
			aurora_colour = sky.call("color_param", "aurora_low")
		outside_m.set_shader_parameter("sky_top", zenith)
		outside_m.set_shader_parameter("sky_low", horizon)
		outside_m.set_shader_parameter("moon_dir", (basis * moon).normalized())
		outside_m.set_shader_parameter("moon_light", Vector3(0.36, 0.42, 0.58) * moon_level)
		outside_m.set_shader_parameter("aurora_dir", (basis * aurora_dir).normalized())
		var a := aurora_colour.srgb_to_linear() * aurora * 0.08
		outside_m.set_shader_parameter("aurora_light", Vector3(a.r, a.g, a.b))


static func build(piece: String, c: Object, xf: Transform3D, size: Vector3, e: Dictionary) -> void:
	var h := hall(c)
	match piece:
		"ice_shell":
			_shell(h, e)
		"ice_screen":
			_screen(h, e)
		"ice_benches":
			_benches(h, c, e)
		"ice_outside":
			_outside(h, e)
	for b: RoomMesh in [h.ice, h.snow, h.wax, h.fur, h.outside]:
		b.colour = Color.WHITE


## The hall on the kit's ctx (made with the first piece): the room's layout from its domestic builder, the materials.
static func hall(c: Object) -> Hall:
	if c.ice != null:
		return c.ice
	var h := Hall.new()
	h.kit = c.kit
	h.rng.seed = 6830
	h.p = Domestic.resolved(c.builder_params)
	# The screen as the builder places it (the room's anchor may not be set yet while the room builds).
	var scr: Dictionary = Domestic.screen_for(c.builder_params)
	var scr_c: Array = scr["center"]
	h.screen = {"xf": Transform3D(Basis(), Vector3(float(scr_c[0]), float(scr_c[1]), float(scr_c[2]))),
			"size": Vector2(float(scr["size"][0]), float(scr["size"][1]))}
	h.kit_lamps = c.lamps
	h.kit_spots = c.spots
	var light: Node = c.kit._light
	h.ice_m = light.from_param({"library": "smooth_plaster", "color": [ICE_TINT.r, ICE_TINT.g, ICE_TINT.b],
			"tiling": 1.6, "spill": ICE_SPILL})
	h.ice_m.shader = ICE_SHADER
	h.ice_m.set_shader_parameter("instance_tint", true)
	h.ice_m.set_shader_parameter("normal_strength", 0.35)
	h.ice_m.set_shader_parameter("ice_map", ice_map())
	h.ice_m.set_shader_parameter("ice_deep", ICE_DEEP)
	h.ice_m.set_shader_parameter("ice_scale", 0.9)
	var sc: Transform3D = h.screen.get("xf", Transform3D())
	var ss: Vector2 = h.screen.get("size", Vector2(3.2, 1.8))
	h.ice_m.set_shader_parameter("ice_screen_c", sc.origin)
	h.ice_m.set_shader_parameter("ice_screen_half", ss * 0.5)
	h.ice_m.set_shader_parameter("ice_film", 0.75)
	h.ice_m.set_shader_parameter("ice_fill", 0.25)
	h.ice_m.set_shader_parameter("ice_night", ICE_NIGHT)
	h.snow_m = light.from_param({"library": "rough_plaster", "color": [SNOW.r, SNOW.g, SNOW.b], "tiling": 1.4,
			"spill": SNOW_SPILL})
	h.snow_m.set_shader_parameter("instance_tint", true)
	h.wax_m = light.from_param({"library": "felt", "color": [1.0, 1.0, 1.0]}, true)
	h.wax_m.set_shader_parameter("instance_tint", true)
	h.wax_m.set_shader_parameter("emission", Color(0.16, 0.07, 0.02))
	h.fur_m = light.from_param({"library": "cream_carpet", "color": [1.0, 1.0, 1.0], "tiling": 0.6})
	h.fur_m.set_shader_parameter("instance_tint", true)
	h.outside_m = ShaderMaterial.new()
	h.outside_m.shader = OUTSIDE_SHADER
	h.ice.surface(h.ice_m)
	h.snow.surface(h.snow_m)
	h.wax.surface(h.wax_m)
	h.fur.surface(h.fur_m)
	h.glass.surface(c.kit.GLASS)
	h.outside.surface(h.outside_m)
	c.ice = h
	return h


# --- The ice map --------------------------------------------------------------------------------------------------

static var _ice_map: ImageTexture

## What is frozen inside the ice, tileable, 256 a side: R bubbles (some in rising strings, as river ice has them),
## G cracks and feathery veils, B milky cloud, A the saw's marks on the face. Made once.
static func ice_map() -> ImageTexture:
	if _ice_map != null:
		return _ice_map
	const N := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = 1909
	var r := PackedFloat32Array()
	r.resize(N * N)
	var g := PackedFloat32Array()
	g.resize(N * N)
	# Bubbles: single ones and strings rising.
	var dots: Array = []
	for i in 70:
		dots.append([rng.randf() * N, rng.randf() * N, rng.randf_range(0.6, 2.0), rng.randf_range(0.4, 1.0)])
	for s in 12:
		var x := rng.randf() * N
		var y := rng.randf() * N
		var drift := rng.randf_range(-0.3, 0.3)
		for k in rng.randi_range(5, 14):
			dots.append([x, y, rng.randf_range(0.5, 1.3), rng.randf_range(0.5, 1.0)])
			y += rng.randf_range(3.0, 7.0)
			x += drift + rng.randf_range(-0.4, 0.4)
	for d: Array in dots:
		var rad: float = d[2]
		for oy in range(-3, 4):
			for ox in range(-3, 4):
				var dd := Vector2(ox, oy).length() / rad
				if dd > 1.6:
					continue
				var px := posmod(int(d[0]) + ox, N)
				var py := posmod(int(d[1]) + oy, N)
				# A ring brighter than its middle: a bubble's rim catches the light.
				var v := float(d[3]) * (smoothstep(1.6, 0.9, dd) * (0.55 + 0.45 * smoothstep(0.2, 0.9, dd)))
				r[py * N + px] = maxf(r[py * N + px], v)
	# Cracks: long wandering fractures fading along their length; veils: bundles of short parallel hairlines.
	for k in 3:
		var p := Vector2(rng.randf() * N, rng.randf() * N)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var steps := rng.randi_range(25, 60)
		for i in steps:
			dir = dir.rotated(rng.randf_range(-0.08, 0.08))
			var v := lerpf(0.9, 0.25, float(i) / steps)
			for t in 4:
				var q := p + dir * t
				_plot(g, N, q, v)
			p += dir * 4.0
	for k in 4:
		var c := Vector2(rng.randf() * N, rng.randf() * N)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var side := dir.orthogonal()
		for j in 9:
			var start := c + side * (j * 2.2) + dir * rng.randf_range(-4.0, 4.0)
			var length := rng.randi_range(8, 22)
			for t in length:
				_plot(g, N, start + dir * t, 0.32 * (1.0 - absf(float(t) / length - 0.5)))
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.006
	noise.fractal_octaves = 3
	var cloud := noise.get_seamless_image(N, N)
	var marks := FastNoiseLite.new()
	marks.seed = 5
	marks.frequency = 0.02
	var bytes := PackedByteArray()
	bytes.resize(N * N * 4)
	var rows := PackedFloat32Array()
	rows.resize(N)
	# The saw's marks: fine grooves across the face, a little uneven along the row (tileable: whole periods).
	for y in N:
		rows[y] = 0.5 + 0.3 * sin(TAU * y * 23.0 / N) + 0.2 * sin(TAU * y * 9.0 / N + 1.3)
	for y in N:
		for x in N:
			var i := y * N + x
			var cl := smoothstep(0.55, 0.92, cloud.get_pixel(x, y).r)
			var mk := rows[y] * (0.7 + 0.3 * sin(TAU * (x * 2.0 / N + y * 1.0 / N)))
			bytes[i * 4] = int(clampf(r[i], 0.0, 1.0) * 255.0)
			bytes[i * 4 + 1] = int(clampf(g[i], 0.0, 1.0) * 255.0)
			bytes[i * 4 + 2] = int(clampf(cl, 0.0, 1.0) * 255.0)
			bytes[i * 4 + 3] = int(clampf(mk, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	_ice_map = ImageTexture.create_from_image(img)
	return _ice_map


static func _plot(a: PackedFloat32Array, n: int, q: Vector2, v: float) -> void:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var px := posmod(int(q.x) + ox, n)
			var py := posmod(int(q.y) + oy, n)
			var k := v * (1.0 if ox == 0 and oy == 0 else 0.3)
			a[py * n + px] = maxf(a[py * n + px], k)


# --- Walls --------------------------------------------------------------------------------------------------------

## A wall's frame: [origin (its bottom corner), along (unit), normal (into the room), length], as domestic's.
static func _wall(h: Hall, side: String) -> Array:
	return Domestic._wall(h.p, side)


static func _on(w: Array, a: float, y: float, out: float) -> Vector3:
	return (w[0] as Vector3) + (w[1] as Vector3) * a + Vector3.UP * y + (w[2] as Vector3) * out


## The vault's height over a point across the room (the end walls' top).
static func _arch_y(h: Hall, x: float) -> float:
	var hw := float(h.p["half_width"])
	var k := clampf(x / hw, -1.0, 1.0)
	return float(h.p["height"]) + float(h.p["vault_rise"]) * sqrt(maxf(1.0 - k * k, 0.0))


## A block: its outline on the wall (convex, metres along and up), its face PROUD out of the joint with chamfered
## edges, its sides back to the joint. Its colour (tint, clearness in alpha) from the hall's rng.
static func _block(h: Hall, w: Array, poly: PackedVector2Array, proud := PROUD, bevel := BEVEL, colour := Color()) -> void:
	var pts := _clean(poly)
	if pts.size() < 3:
		return
	if colour == Color():
		colour = _ice_colour(h)
	h.ice.colour = colour
	var inner := _inset(pts, bevel)
	var n: Vector3 = w[2]
	var along: Vector3 = w[1]
	var front := PackedVector3Array()
	for q: Vector2 in inner:
		front.append(_on(w, q.x, q.y, proud))
	h.ice.face(Array(front), n)
	var count := pts.size()
	for i in count:
		var a := pts[i]
		var b := pts[(i + 1) % count]
		var e := (b - a).normalized()
		# The edge's outward normal on the wall (the outline runs counter-clockwise).
		var o2 := Vector2(e.y, -e.x)
		var o3 := (along * o2.x + Vector3.UP * o2.y).normalized()
		var ia := inner[i]
		var ib := inner[(i + 1) % count]
		h.ice.face([_on(w, a.x, a.y, proud - bevel), _on(w, b.x, b.y, proud - bevel), _on(w, ib.x, ib.y, proud),
				_on(w, ia.x, ia.y, proud)], (o3 + n).normalized())
		if proud - bevel > 0.004:
			h.ice.face([_on(w, a.x, a.y, 0.0), _on(w, b.x, b.y, 0.0), _on(w, b.x, b.y, proud - bevel),
					_on(w, a.x, a.y, proud - bevel)], o3)


## A block's colour: the ice's tint, a little bluer or greener, milkier or clearer (alpha: clearness and the block's
## own seed for what is inside it).
static func _ice_colour(h: Hall) -> Color:
	var v := h.rng.randf_range(0.82, 1.08)
	var blue := h.rng.randf_range(-0.06, 0.06)
	return Color(v * (1.0 - blue), v, v * (1.0 + blue * 0.6), h.rng.randf_range(0.5, 1.0))


## Counter-clockwise, without points closer than a millimetre.
static func _clean(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Vector2 in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(q) > 0.001:
			out.append(q)
	if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 0.001:
		out.remove_at(out.size() - 1)
	if out.size() > 2 and not Geometry2D.is_polygon_clockwise(out):
		return out
	out.reverse()
	return out


## A convex outline (counter-clockwise) moved in by d: each corner where its two edges, moved in, meet.
static func _inset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var prev := pts[(i - 1 + n) % n]
		var cur := pts[i]
		var next := pts[(i + 1) % n]
		var e0 := (cur - prev).normalized()
		var e1 := (next - cur).normalized()
		var n0 := Vector2(-e0.y, e0.x)
		var n1 := Vector2(-e1.y, e1.x)
		var m := n0 + n1
		var k := 1.0 + n0.dot(n1)
		out.append(cur + (m / maxf(k, 0.2)) * d)
	return out


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## A rectangle less the holes: the rectangles left.
static func _cut(r: Rect2, holes: Array) -> Array:
	var parts: Array = [r]
	for hole: Rect2 in holes:
		var next: Array = []
		for p: Rect2 in parts:
			if not p.intersects(hole):
				next.append(p)
				continue
			var i := p.intersection(hole)
			if i.position.y > p.position.y:
				next.append(Rect2(p.position.x, p.position.y, p.size.x, i.position.y - p.position.y))
			if i.end.y < p.end.y:
				next.append(Rect2(p.position.x, i.end.y, p.size.x, p.end.y - i.end.y))
			if i.position.x > p.position.x:
				next.append(Rect2(p.position.x, i.position.y, i.position.x - p.position.x, i.size.y))
			if i.end.x < p.end.x:
				next.append(Rect2(i.end.x, i.position.y, p.end.x - i.end.x, i.size.y))
		parts = next
	return parts


## A wall of blocks: courses up to its top (an end wall's to the vault's arch), the blocks staggered course to course,
## each cut round the holes; the joints' snow behind them. big: an end wall's larger blocks.
static func _wall_blocks(h: Hall, side: String, holes: Array, big := false) -> void:
	var w := _wall(h, side)
	var length: float = w[3]
	var top := float(h.p["height"])
	var end_wall := side in ["front", "back"]
	var hw := float(h.p["half_width"])
	if end_wall:
		top += float(h.p["vault_rise"])
	# The joints: the wall's face behind the blocks (snow), and on an end wall the lunette under the vault.
	h.snow.colour = Color(0.9, 0.92, 0.95)
	var flat_holes: Array = []
	for hole: Rect2 in holes:
		if hole.end.y <= float(h.p["height"]) + 0.001:
			flat_holes.append(hole)
	Shapes.wall(h.snow, w[0], w[1], w[2], length, float(h.p["height"]), flat_holes)
	if end_wall:
		var cap := PackedVector3Array()
		for k in 25:
			var t := PI * k / 24.0
			var x := cos(t) * hw
			cap.append(_on(w, x + hw, _arch_y(h, x), 0.0))
		h.snow.polygon(cap, w[2])
	var arch := PackedVector2Array()
	if end_wall:
		arch.append(Vector2(0.0, 0.0))
		arch.append(Vector2(length, 0.0))
		for k in 33:
			var t := PI * k / 32.0
			var x := cos(t) * hw
			arch.append(Vector2(x + hw, _arch_y(h, x) - 0.02))
	var y := 0.0
	var course := 0
	while y < top - 0.05:
		var ch := COURSE * (1.25 if big and y > 2.0 else 1.0)
		var a := -h.rng.randf_range(0.1, 0.5) if course % 2 == 0 else -h.rng.randf_range(0.5, 0.9)
		while a < length:
			var bl := h.rng.randf_range(0.75, 1.15) * (1.3 if big else 1.0)
			var r := Rect2(maxf(a, 0.0), y, minf(a + bl, length) - maxf(a, 0.0), ch)
			a += bl
			if r.size.x < 0.05:
				continue
			r = r.grow_individual(-JOINT * 0.5, -JOINT * 0.5, -JOINT * 0.5, -JOINT * 0.5)
			for part: Rect2 in _cut(r, holes):
				if part.size.x < 0.07 or part.size.y < 0.07:
					continue
				var poly := _rect_poly(part)
				if end_wall and part.end.y > float(h.p["height"]) - 0.01:
					var clipped := Geometry2D.intersect_polygons(poly, arch)
					for cp: PackedVector2Array in clipped:
						var bb := _bounds(cp)
						if bb.size.x > 0.07 and bb.size.y > 0.05:
							_block(h, w, cp)
				else:
					_block(h, w, poly)
		y += ch
		course += 1


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q: Vector2 in poly:
		r = r.expand(q)
	return r


# --- The shell ----------------------------------------------------------------------------------------------------

static func _shell(h: Hall, e: Dictionary) -> void:
	var p := h.p
	var hw := float(p["half_width"])
	var fz := float(p["front_z"])
	var bz := float(p["back_z"])
	var wh := float(p["height"])
	# The floor: packed snow.
	h.snow.colour = Color(0.94, 0.95, 0.97)
	h.snow.face([Vector3(-hw, 0, fz), Vector3(hw, 0, fz), Vector3(hw, 0, bz), Vector3(-hw, 0, bz)], Vector3.UP)
	var win := Domestic._window(p)
	var door := Domestic._door(p)
	# The niches with their candles: along each side wall clear of the window, and either side of the doorway.
	var niches := {"left": [], "right": [], "back": [], "front": []}
	var y0 := COURSE * 2.0
	for along: float in _niche_places(h, "left", win, door):
		niches["left"].append(Rect2(along - NICHE.x * 0.5, y0, NICHE.x, NICHE.y))
	for along: float in _niche_places(h, "right", win, door):
		niches["right"].append(Rect2(along - NICHE.x * 0.5, y0, NICHE.x, NICHE.y))
	if not door.is_empty() and str(door[0]) == "back":
		var dr: Rect2 = door[1]
		for along: float in [dr.end.x + 0.75, hw * 2.0 - 1.0]:
			niches["back"].append(Rect2(along - NICHE.x * 0.5, y0, NICHE.x, NICHE.y))
	# On the front wall either side of the screen, between the carvings: their candles light the bear and the
	# whale, the fox and the hare, and go lower than the others for the film (the house group).
	var fr := _frame_rect(h)
	for along: float in [fr.position.x * 0.5, (fr.end.x + hw * 2.0) * 0.5]:
		niches["front"].append(Rect2(along - NICHE.x * 0.5, y0, NICHE.x, NICHE.y))
	h.niches = niches
	for side: String in ["left", "right", "back", "front"]:
		var holes: Array = (niches[side] as Array).duplicate()
		if not win.is_empty() and str(win[0]) == side:
			holes.append(win[1])
		if not door.is_empty() and str(door[0]) == side:
			holes.append((door[1] as Rect2).grow_individual(SURROUND, 0.0, SURROUND, SURROUND))
		if side == "front":
			holes.append(_frame_rect(h))
		_wall_blocks(h, side, holes, side == "front")
		for r: Rect2 in niches[side]:
			_niche(h, _wall(h, side), r, "house" if side == "front" else "accent")
	if not win.is_empty():
		_window(h, str(win[0]), win[1])
	if not door.is_empty():
		_doorway(h, str(door[0]), door[1])
	_cornices(h)
	_floor_hides(h)
	_vault(h)


## Where a side wall's niches go: at these places down the room (z), clear of the window and the doorway; none
## beside the screen, so no candle stands near the picture.
const NICHE_Z := [-4.5, -2.5, -0.6, 1.4]


static func _niche_places(h: Hall, side: String, win: Array, door: Array) -> Array:
	var w := _wall(h, side)
	var blocked: Array = []
	if not win.is_empty() and str(win[0]) == side:
		var r: Rect2 = win[1]
		blocked.append(Vector2(r.position.x - 0.45, r.end.x + 0.45))
	if not door.is_empty() and str(door[0]) == side:
		var r: Rect2 = door[1]
		blocked.append(Vector2(r.position.x - 0.45, r.end.x + 0.45))
	var out: Array = []
	for z: float in NICHE_Z:
		var along := (z - (w[0] as Vector3).z) / (w[1] as Vector3).z
		if blocked.any(func(b: Vector2) -> bool: return along > b.x and along < b.y):
			continue
		out.append(along)
	return out


## The screen's frame's outer edge on the front wall (along, up): the blocks keep clear of it.
static func _frame_rect(h: Hall) -> Rect2:
	var sc: Transform3D = h.screen.get("xf", Transform3D())
	var ss: Vector2 = h.screen.get("size", Vector2(3.2, 1.8))
	var hw := float(h.p["half_width"])
	var m := 0.24
	return Rect2(sc.origin.x + hw - ss.x * 0.5 - m, sc.origin.y - ss.y * 0.5 - m, ss.x + m * 2.0, ss.y + m * 2.0)


## A niche cut into the wall behind a hole of the blocks: its back, sides, floor and roof in ice; a candle on its
## floor whose glow lights the ice round it.
static func _niche(h: Hall, w: Array, r: Rect2, group := "accent") -> void:
	var n: Vector3 = w[2]
	h.ice.colour = Color(1.0, 1.0, 1.0, 0.85)
	var a0 := r.position.x
	var a1 := r.end.x
	var y0 := r.position.y
	var y1 := r.end.y
	var d := -NICHE_DEPTH
	h.ice.face([_on(w, a0, y0, d), _on(w, a1, y0, d), _on(w, a1, y1, d), _on(w, a0, y1, d)], n)
	h.ice.face([_on(w, a0, y0, d), _on(w, a0, y0, PROUD), _on(w, a0, y1, PROUD), _on(w, a0, y1, d)], w[1])
	h.ice.face([_on(w, a1, y0, d), _on(w, a1, y0, PROUD), _on(w, a1, y1, PROUD), _on(w, a1, y1, d)], -(w[1] as Vector3))
	h.ice.face([_on(w, a0, y0, d), _on(w, a1, y0, d), _on(w, a1, y0, PROUD), _on(w, a0, y0, PROUD)], Vector3.UP)
	h.ice.face([_on(w, a0, y1, d), _on(w, a1, y1, d), _on(w, a1, y1, PROUD), _on(w, a0, y1, PROUD)], Vector3.DOWN)
	# A sill: the block under the niche reaching out a little.
	h.ice.colour = _ice_colour(h)
	_block(h, w, _rect_poly(Rect2(a0 - 0.06, y0 - 0.06, NICHE.x + 0.12, 0.06)), PROUD + 0.05, 0.01)
	_candle(h, _on(w, (a0 + a1) * 0.5, y0, d * 0.5), 0.15, 0.045, 1.0, group)


## A pillar candle standing at `at` (its foot), its flame above (crossed glow quads), its glow in the ice; group:
## the light group its flame and glow follow (accent, or house: lower for the film).
static func _candle(h: Hall, at: Vector3, height: float, radius: float, energy := 1.0, group := "accent") -> void:
	h.wax.colour = WAX.srgb_to_linear()
	Shapes.cylinder(h.wax, at, radius, height, 10)
	# The well the flame has melted in its top: a darker ring.
	h.wax.colour = (WAX * 0.6).srgb_to_linear()
	Shapes.cylinder(h.wax, at + Vector3(0, height, 0), radius * 0.7, 0.004, 10)
	var f := at + Vector3(0, height + 0.035, 0)
	var quads: Array = h.flames.get(group, [])
	for k in 2:
		var t := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		quads.append([f, t * 0.022, Vector3(0, 0.04, 0), t.cross(Vector3.UP)])
	h.flames[group] = quads
	h.candles.append([f, energy, group])
	h.kit_lamps.append([f, FLAME, CANDLE_BAKE * energy])


## The window: its reveal through the wall's thickness in ice, a sill reaching into the room, a clear pane of ice
## halfway out, a candle on the sill.
static func _window(h: Hall, side: String, r: Rect2) -> void:
	var w := _wall(h, side)
	var n: Vector3 = w[2]
	var along: Vector3 = w[1]
	var a0 := r.position.x
	var a1 := r.end.x
	var y0 := r.position.y
	var y1 := r.end.y
	var d := -THICK
	h.ice.colour = Color(0.95, 1.0, 1.02, 0.7)
	h.ice.face([_on(w, a0, y0, d), _on(w, a0, y0, PROUD), _on(w, a0, y1, PROUD), _on(w, a0, y1, d)], along)
	h.ice.face([_on(w, a1, y0, d), _on(w, a1, y0, PROUD), _on(w, a1, y1, PROUD), _on(w, a1, y1, d)], -along)
	h.ice.face([_on(w, a0, y1, d), _on(w, a1, y1, d), _on(w, a1, y1, PROUD), _on(w, a0, y1, PROUD)], Vector3.DOWN)
	h.ice.face([_on(w, a0, y0, d), _on(w, a1, y0, d), _on(w, a1, y0, PROUD), _on(w, a0, y0, PROUD)], Vector3.UP)
	# The sill: a slab of ice reaching into the room.
	h.ice.colour = _ice_colour(h)
	_block(h, w, _rect_poly(Rect2(a0 - 0.1, y0 - 0.08, r.size.x + 0.2, 0.08)), PROUD + 0.09, 0.015)
	# The pane: a clear slab of ice, its edges frosted into the reveal.
	var pane := -THICK * 0.55
	Shapes.quad(h.glass, _on(w, (a0 + a1) * 0.5, (y0 + y1) * 0.5, pane), along * (r.size.x * 0.5),
			Vector3(0, r.size.y * 0.5, 0), n)
	_candle(h, _on(w, (a0 + a1) * 0.5 + 0.55, y0, -0.12), 0.11, 0.04, 0.8)
	# The Moon's light through the window, for the bake: a cold patch across the floor and the far wall.
	var moon := _moon_direction(h)
	if moon != Vector3.ZERO and moon.dot(n) < 0.0:
		var c := _on(w, (a0 + a1) * 0.5, (y0 + y1) * 0.5, 0.0)
		h.kit_spots.append([c + moon * 6.0, c - moon * 2.0, MOONLIGHT, 0.9, 16.0, 14.0])


## The Moon's light in the bake: cold, faint.
const MOONLIGHT := Color(0.55, 0.66, 0.95)


## Where the room's sky puts the Moon (the room's frame; zero without one): read from the document, as the sky system
## may not be built yet when the kit builds.
static func _moon_direction(h: Hall) -> Vector3:
	var d: Variant = h.kit.room.get("doc")
	if not (d is Dictionary):
		return Vector3.ZERO
	for s: Dictionary in (d as Dictionary).get("systems", []):
		if str(s.get("system", "")) != "sky":
			continue
		var p: Dictionary = s.get("params", {})
		var m: Variant = p.get("moon", 0.0)
		if (m is float or m is int) and float(m) <= 0.0:
			return Vector3.ZERO
		var a := deg_to_rad(float(p.get("moon_bearing", 220.0)) - float(p.get("facing", 0.0)))
		var alt := deg_to_rad(float(p.get("moon_altitude", 45.0)))
		return (Vector3(sin(a), 0.0, -cos(a)) * cos(alt) + Vector3.UP * sin(alt)).normalized()
	return Vector3.ZERO


## The doorway's surround of carved ice: this wide at the sides and over the arch.
const SURROUND := 0.15


## The doorway: a tunnel through the wall's thickness with a round arch, in a surround of carved ice (jambs and an
## arched lintel standing out of the wall), trodden snow on its floor.
static func _doorway(h: Hall, side: String, r: Rect2) -> void:
	var w := _wall(h, side)
	var along: Vector3 = w[1]
	var a0 := r.position.x
	var a1 := r.end.x
	var rad := r.size.x * 0.5
	var spring := r.end.y - rad
	var mid := (a0 + a1) * 0.5
	var d := -THICK
	var face := PROUD + 0.05
	# The tunnel starts just behind the wall's face: the surround's own sides are its first few centimetres.
	var back := -0.002
	h.ice.colour = Color(0.95, 1.0, 1.02, 0.75)
	h.ice.face([_on(w, a0, 0.0, d), _on(w, a0, 0.0, back), _on(w, a0, spring, back), _on(w, a0, spring, d)], along)
	h.ice.face([_on(w, a1, 0.0, d), _on(w, a1, 0.0, back), _on(w, a1, spring, back), _on(w, a1, spring, d)], -along)
	# The arch's soffit: a half cylinder through the wall.
	var la := PackedVector3Array()
	var lb := PackedVector3Array()
	var ns := PackedVector3Array()
	for k in 13:
		var t := PI * k / 12.0
		var q := Vector2(mid + cos(t) * rad, spring + sin(t) * rad)
		la.append(_on(w, q.x, q.y, back))
		lb.append(_on(w, q.x, q.y, d))
		ns.append((-along * cos(t) - Vector3.UP * sin(t)).normalized())
	h.ice.strip(la, lb, ns)
	# The floor of the tunnel: trodden snow.
	h.snow.colour = Color(0.86, 0.88, 0.92)
	h.snow.face([_on(w, a0, 0.002, d), _on(w, a1, 0.002, d), _on(w, a1, 0.002, 0.0), _on(w, a0, 0.002, 0.0)],
			Vector3.UP)
	# The surround: two jambs and the lintel cut to the arch.
	var col := Color(1.04, 1.06, 1.08, 0.2)
	_block(h, w, _rect_poly(Rect2(a0 - SURROUND, 0.0, SURROUND, spring)), face, 0.015, col)
	_block(h, w, _rect_poly(Rect2(a1, 0.0, SURROUND, spring)), face, 0.015, col)
	var lintel := PackedVector2Array([Vector2(a0 - SURROUND, spring)])
	for k in range(12, -1, -1):
		var t := PI * k / 12.0
		lintel.append(Vector2(mid + cos(t) * rad, spring + sin(t) * rad))
	lintel.append(Vector2(a1 + SURROUND, spring))
	lintel.append(Vector2(a1 + SURROUND, r.end.y + SURROUND))
	lintel.append(Vector2(a0 - SURROUND, r.end.y + SURROUND))
	_relief(h, w, lintel, face, 0.015, col)


## A band of ice along each side wall's top, where the vault springs, and a plinth course along the floor.
static func _cornices(h: Hall) -> void:
	var wh := float(h.p["height"])
	for side: String in ["left", "right"]:
		var w := _wall(h, side)
		var length: float = w[3]
		h.ice.colour = Color(1.02, 1.04, 1.06, 0.8)
		_block(h, w, _rect_poly(Rect2(0.0, wh - 0.1, length, 0.14)), PROUD + 0.07, 0.02, Color(1.02, 1.04, 1.06, 0.8))


## A reindeer's pelt flat on the floor (its right half, metres: neck to tail along +z, legs out at the sides).
const PELT_HALF := [[0.0, -0.72], [0.09, -0.7], [0.12, -0.6], [0.18, -0.5], [0.36, -0.49], [0.43, -0.43],
		[0.31, -0.36], [0.32, -0.2], [0.35, 0.0], [0.33, 0.2], [0.3, 0.3], [0.42, 0.35], [0.47, 0.45], [0.34, 0.44],
		[0.22, 0.5], [0.12, 0.6], [0.05, 0.67], [0.0, 0.68]]
## Pelts on the floor: [x, z, turn (degrees)]: one before the front row, below the screen; one in the right aisle.
const FLOOR_PELTS := [[0.15, -2.75, 84.0], [2.42, -2.3, 8.0]]


static func _floor_hides(h: Hall) -> void:
	for fp: Array in FLOOR_PELTS:
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(fp[2]))), Vector3(float(fp[0]), 0.0, float(fp[1])))
		var outline := PackedVector2Array()
		for q: Array in PELT_HALF:
			outline.append(Vector2(float(q[0]), float(q[1])))
		for k in range(PELT_HALF.size() - 2, 0, -1):
			outline.append(Vector2(-float(PELT_HALF[k][0]), float(PELT_HALF[k][1])))
		# The pale belly's edge, then the darker back over it, then a darker stripe down the spine: each a little
		# higher, so the pelt has its thickness.
		var layers := [[0.0, 0.012, Color(0.9, 0.86, 0.78)], [0.07, 0.018, Color(0.62, 0.52, 0.42)],
				[0.17, 0.021, Color(0.4, 0.32, 0.25)]]
		for layer: Array in layers:
			var pts := outline if float(layer[0]) == 0.0 else _inset(_clean(outline), float(layer[0]))
			if float(layer[0]) > 0.0 and Geometry2D.triangulate_polygon(pts).is_empty():
				continue
			h.fur.colour = (layer[2] as Color).srgb_to_linear()
			var top := PackedVector3Array()
			for q: Vector2 in pts:
				top.append(xf * Vector3(q.x, float(layer[1]), q.y))
			h.fur.polygon(top, Vector3.UP)
			if float(layer[0]) == 0.0:
				# The rim: the pelt's edge down to the snow.
				var a := PackedVector3Array()
				var b := PackedVector3Array()
				var ns := PackedVector3Array()
				for i in pts.size() + 1:
					var q := pts[i % pts.size()]
					a.append(xf * Vector3(q.x, float(layer[1]), q.y))
					b.append(xf * Vector3(q.x * 1.02, 0.001, q.y * 1.02))
					ns.append((xf.basis * Vector3(q.x, 0.3, q.y)).normalized())
				h.fur.strip(a, b, ns)


## The vault: packed snow sprayed over arched forms (each bay sags a little between its ribs), ribs of clear ice
## blocks, and in the haunches between some ribs skylights of clear ice: a reveal through the vault's thickness and a
## pane at its outer end (the aurora over the east shows in the left ones).
static func _vault(h: Hall) -> void:
	var p := h.p
	var hw := float(p["half_width"])
	var fz := float(p["front_z"])
	var bz := float(p["back_z"])
	var ribs: Array[float] = []
	var bays := 5
	for k in bays + 1:
		ribs.append(lerpf(fz, bz, float(k) / bays))
	for k in bays:
		var z0 := ribs[k]
		var z1 := ribs[k + 1]
		var zs: Array[float] = [z0, z0 + 0.45, (z0 + z1) * 0.5, z1 - 0.45, z1]
		var sky := k in SKY_BAYS
		# Each row across the bay one strip over the arch (smooth from wall to wall); the skylights' rows in three.
		for j in zs.size() - 1:
			var runs: Array = [[0, VAULT_SEGMENTS]]
			if sky and j in [1, 2]:
				runs = [[0, SKY_RIGHT[0]], [SKY_RIGHT[1], SKY_LEFT[0]], [SKY_LEFT[1], VAULT_SEGMENTS]]
			for run: Array in runs:
				_vault_strip(h, int(run[0]), int(run[1]), zs[j], zs[j + 1])
		if sky:
			for range_: Array in [SKY_LEFT, SKY_RIGHT]:
				_skylight(h, range_[0], range_[1], zs[1], zs[3])
	# No rib against the front wall: the lunette over the screen is the owl's, whole.
	for z: float in ribs.slice(1):
		_rib(h, clampf(z, fz + RIB_WIDTH * 0.5, bz - RIB_WIDTH * 0.5))


static func _in(i: int, r: Array) -> bool:
	return i >= int(r[0]) and i < int(r[1])


## The vault's point at segment boundary i (of VAULT_SEGMENTS) and z, and its normal into the room. Between the ribs
## the snow sags up a little (sprayed over arched forms).
static func _vault_point(h: Hall, i: int, z: float, out := 0.0) -> Vector3:
	var hw := float(h.p["half_width"])
	var rise := float(h.p["vault_rise"])
	var t := PI * float(i) / VAULT_SEGMENTS
	var n := _vault_normal(h, i)
	var bay := (float(h.p["back_z"]) - float(h.p["front_z"])) / 5.0
	var f := fposmod(z - float(h.p["front_z"]), bay) / bay
	var sag := 0.035 * sin(PI * f) * sin(t)
	return Vector3(cos(t) * hw, float(h.p["height"]) + sin(t) * rise, z) - n * (sag + out)


static func _vault_normal(h: Hall, i: int) -> Vector3:
	var t := PI * float(i) / VAULT_SEGMENTS
	return -Vector3(cos(t) / float(h.p["half_width"]), sin(t) / float(h.p["vault_rise"]), 0.0).normalized()


## A strip of the vault over the arch from segment i0 to i1, between z0 and z1 (one lightmap chart, smooth).
static func _vault_strip(h: Hall, i0: int, i1: int, z0: float, z1: float) -> void:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in range(i0, i1 + 1):
		a.append(_vault_point(h, i, z0))
		b.append(_vault_point(h, i, z1))
		ns.append(_vault_normal(h, i))
	h.snow.colour = Color(0.9, 0.93, 0.97)
	h.snow.strip(a, b, ns)


## A skylight: the reveal through the vault (ice) and the pane at its outer end.
static func _skylight(h: Hall, i0: int, i1: int, z0: float, z1: float) -> void:
	var depth := 0.38
	h.ice.colour = Color(0.95, 1.02, 1.05, 0.95)
	for z: float in [z0, z1]:
		var a := PackedVector3Array()
		var b := PackedVector3Array()
		var ns := PackedVector3Array()
		for i in range(i0, i1 + 1):
			a.append(_vault_point(h, i, z))
			b.append(_vault_point(h, i, z, depth))
			ns.append(Vector3(0, 0, 1) if z == z0 else Vector3(0, 0, -1))
		h.ice.strip(a, b, ns)
	for i: int in [i0, i1]:
		var t := PI * float(i) / VAULT_SEGMENTS
		var tangent := Vector3(-sin(t) * float(h.p["half_width"]), cos(t) * float(h.p["vault_rise"]), 0).normalized()
		var facing := tangent if i == i0 else -tangent
		h.ice.face([_vault_point(h, i, z0), _vault_point(h, i, z1), _vault_point(h, i, z1, depth),
				_vault_point(h, i, z0, depth)], facing)
	var c := (_vault_point(h, i0, z0, depth * 0.8) + _vault_point(h, i1, z1, depth * 0.8)) * 0.5
	var across := (_vault_point(h, i1, z0, depth * 0.8) - _vault_point(h, i0, z0, depth * 0.8)) * 0.5
	Shapes.quad(h.glass, c, Vector3(0, 0, (z1 - z0) * 0.5), across, _vault_normal(h, (i0 + i1) / 2))


## A rib of clear ice blocks under the vault (voussoirs along the arch), its foot on the cornice.
static func _rib(h: Hall, z: float) -> void:
	var count := 12
	for k in count:
		var i0 := k * VAULT_SEGMENTS / count
		var i1 := (k + 1) * VAULT_SEGMENTS / count
		var a := _vault_point(h, i0, z)
		var b := _vault_point(h, i1, z)
		var n := (_vault_normal(h, i0) + _vault_normal(h, i1)).normalized()
		var mid := (a + b) * 0.5 + n * (RIB_DEPTH * 0.5 - 0.02)
		var along := (b - a).normalized()
		var basis := Basis(along, n, along.cross(n).normalized())
		_box(h, mid, Vector3(a.distance_to(b) - JOINT, RIB_DEPTH + 0.04, RIB_WIDTH), basis, 0.018, _ice_colour(h))


## A box of ice with chamfered edges (its faces, the chamfers along its edges, the corners' triangles).
static func _box(h: Hall, centre: Vector3, size: Vector3, basis: Basis, bevel: float, colour: Color,
		skip_down := false) -> void:
	h.ice.colour = colour
	var half := size * 0.5
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	# The faces, each moved in by the bevel at its edges.
	for ax in 3:
		for s: float in [-1.0, 1.0]:
			if skip_down and ax == 1 and s < 0.0:
				continue
			var nrm: Vector3 = axes[ax] * s
			var u: Vector3 = axes[(ax + 1) % 3]
			var v: Vector3 = axes[(ax + 2) % 3]
			var hu: float = half[(ax + 1) % 3] - bevel
			var hv: float = half[(ax + 2) % 3] - bevel
			var c := nrm * half[ax]
			var corners: Array = []
			for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				corners.append(centre + basis * (c + u * hu * k.x + v * hv * k.y))
			h.ice.face(corners, (basis * nrm).normalized())
	# The chamfers: one along each edge.
	for ax in 3:
		var u: Vector3 = axes[(ax + 1) % 3]
		var v: Vector3 = axes[(ax + 2) % 3]
		var hl: float = half[ax] - bevel
		for su: float in [-1.0, 1.0]:
			for sv: float in [-1.0, 1.0]:
				if skip_down and ((ax + 1) % 3 == 1 and su < 0.0 or (ax + 2) % 3 == 1 and sv < 0.0):
					continue
				var p1: Vector3 = u * su * half[(ax + 1) % 3] + v * sv * (half[(ax + 2) % 3] - bevel)
				var p2: Vector3 = u * su * (half[(ax + 1) % 3] - bevel) + v * sv * half[(ax + 2) % 3]
				var ax_v: Vector3 = axes[ax]
				h.ice.face([centre + basis * (p1 - ax_v * hl), centre + basis * (p1 + ax_v * hl),
						centre + basis * (p2 + ax_v * hl), centre + basis * (p2 - ax_v * hl)],
						(basis * (u * su + v * sv)).normalized())
	# The corners' small triangles.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			if skip_down and sy < 0.0:
				continue
			for sz: float in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				var hb := half - Vector3.ONE * bevel
				h.ice.face([centre + basis * (s * Vector3(half.x, hb.y, hb.z)), centre + basis * (s * Vector3(hb.x,
						half.y, hb.z)), centre + basis * (s * Vector3(hb.x, hb.y, half.z))], (basis * s).normalized())


# --- The screen wall ----------------------------------------------------------------------------------------------

## The animals in relief (metres; x along the wall, y up): outlines drawn here, each walking or sitting towards the
## screen when placed. Ours, simple and bold enough to read across the room.
const BEAR := [[1.0, 0.42], [0.96, 0.37], [0.88, 0.35], [0.8, 0.32], [0.75, 0.26], [0.75, 0.17], [0.77, 0.05],
		[0.81, 0.0], [0.66, 0.0], [0.66, 0.1], [0.63, 0.18], [0.55, 0.19], [0.4, 0.17], [0.3, 0.18], [0.27, 0.13],
		[0.28, 0.04], [0.31, 0.0], [0.15, 0.0], [0.14, 0.08], [0.1, 0.18], [0.06, 0.28], [0.05, 0.37], [0.03, 0.4],
		[0.07, 0.44], [0.15, 0.5], [0.3, 0.52], [0.45, 0.53], [0.58, 0.56], [0.68, 0.53], [0.78, 0.48], [0.85, 0.48],
		[0.86, 0.515], [0.89, 0.505], [0.92, 0.47], [0.97, 0.45]]
const FOX := [[0.0, 0.5], [0.03, 0.47], [0.08, 0.46], [0.1, 0.42], [0.11, 0.34], [0.1, 0.26], [0.11, 0.13],
		[0.04, 0.1], [-0.04, 0.1], [-0.1, 0.07], [-0.08, 0.01], [0.05, 0.0], [0.25, 0.0], [0.38, 0.02], [0.44, 0.08],
		[0.46, 0.18], [0.44, 0.28], [0.38, 0.38], [0.3, 0.46], [0.22, 0.52], [0.19, 0.58], [0.18, 0.66], [0.14, 0.7],
		[0.11, 0.62], [0.07, 0.58], [0.02, 0.53]]
const HARE := [[0.0, 0.22], [0.02, 0.19], [0.06, 0.15], [0.065, 0.03], [0.03, 0.0], [0.11, 0.0], [0.13, 0.05],
		[0.16, 0.035], [0.14, 0.0], [0.34, 0.0], [0.38, 0.06], [0.38, 0.16], [0.32, 0.25], [0.22, 0.29], [0.15, 0.3],
		[0.16, 0.46], [0.13, 0.53], [0.1, 0.47], [0.09, 0.33], [0.06, 0.31], [0.02, 0.27]]
const WHALE := [[1.0, 0.16], [0.95, 0.1], [0.85, 0.06], [0.7, 0.04], [0.5, 0.05], [0.35, 0.08], [0.2, 0.12],
		[0.12, 0.15], [0.04, 0.06], [0.0, 0.05], [0.03, 0.12], [0.06, 0.17], [0.02, 0.24], [0.04, 0.29], [0.1, 0.21],
		[0.18, 0.2], [0.35, 0.24], [0.42, 0.26], [0.46, 0.31], [0.5, 0.27], [0.7, 0.27], [0.86, 0.24], [0.95, 0.21]]
const FLIPPER := [[0.72, 0.07], [0.6, -0.09], [0.56, -0.07], [0.66, 0.06]]
## The snowy owl's right half, wings spread (mirrored for the left), and its size over the screen.
const OWL_SCALE := 0.85
const OWL_HALF := [[0.0, 0.66], [0.05, 0.655], [0.09, 0.635], [0.115, 0.6], [0.12, 0.555], [0.13, 0.53],
		[0.2, 0.56], [0.32, 0.6], [0.46, 0.63], [0.6, 0.63], [0.72, 0.6], [0.82, 0.55], [0.86, 0.5], [0.8, 0.48],
		[0.83, 0.43], [0.76, 0.42], [0.78, 0.37], [0.7, 0.37], [0.71, 0.32], [0.63, 0.33], [0.63, 0.28],
		[0.55, 0.3], [0.5, 0.26], [0.45, 0.29], [0.4, 0.24], [0.35, 0.27], [0.3, 0.23], [0.25, 0.26], [0.19, 0.25],
		[0.15, 0.28], [0.14, 0.18], [0.12, 0.1], [0.08, 0.03], [0.05, 0.0], [0.02, 0.02]]


static func _outline(pts: Array, at: Vector2, scale: float, flip: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Array in pts:
		out.append(at + Vector2((-float(q[0]) if flip else float(q[0])) * scale, float(q[1]) * scale))
	return out


static func _owl(at: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Array in OWL_HALF:
		out.append(at + Vector2(float(q[0]), float(q[1])) * scale)
	for k in range(OWL_HALF.size() - 1, 0, -1):
		var q: Array = OWL_HALF[k]
		out.append(at + Vector2(-float(q[0]), float(q[1])) * scale)
	return out


## A relief carved standing out of the wall: its front face (any outline) `proud` out, its edges rounded over in
## two steps back to the wall.
static func _relief(h: Hall, w: Array, poly: PackedVector2Array, proud: float, round_: float,
		colour := Color(1.06, 1.08, 1.1, 0.05)) -> void:
	var pts := _clean(poly)
	if pts.size() < 3:
		return
	h.ice.colour = colour
	var n: Vector3 = w[2]
	var along: Vector3 = w[1]
	var mid := _inset(pts, round_ * 0.45)
	var inner := _inset(pts, round_)
	# Where the rounding would turn an outline inside out (a sharp notch), the face keeps the outline itself.
	if Geometry2D.triangulate_polygon(inner).is_empty():
		mid = pts
		inner = pts
	var front := PackedVector3Array()
	for q: Vector2 in inner:
		front.append(_on(w, q.x, q.y, proud))
	h.ice.polygon(front, n)
	var rings := [[pts, 0.0], [pts, proud - round_], [mid, proud - round_ * 0.3], [inner, proud]]
	var count := pts.size()
	for k in rings.size() - 1:
		var la := PackedVector3Array()
		var lb := PackedVector3Array()
		var ns := PackedVector3Array()
		var ra: PackedVector2Array = rings[k][0]
		var rb: PackedVector2Array = rings[k + 1][0]
		var lean := float(k) / (rings.size() - 2)
		for i in count + 1:
			var j := i % count
			var prev := pts[(j - 1 + count) % count]
			var next := pts[(j + 1) % count]
			var e := (next - prev).normalized()
			var o3 := (along * e.y - Vector3.UP * e.x).normalized()
			la.append(_on(w, ra[j].x, ra[j].y, float(rings[k][1])))
			lb.append(_on(w, rb[j].x, rb[j].y, float(rings[k + 1][1])))
			ns.append((o3 * (1.0 - lean) + n * (0.3 + lean)).normalized())
		if float(rings[k + 1][1]) - float(rings[k][1]) > 0.001 or k > 0:
			h.ice.strip(la, lb, ns)


static func _screen(h: Hall, e: Dictionary) -> void:
	var w := _wall(h, "front")
	var hw := float(h.p["half_width"])
	var sc: Transform3D = h.screen.get("xf", Transform3D())
	var ss: Vector2 = h.screen.get("size", Vector2(3.2, 1.8))
	var cx := sc.origin.x + hw
	var cy := sc.origin.y
	var fr := _frame_rect(h)
	# The smoothed panel the picture lies on, a little behind the picture's plane.
	h.snow.colour = Color(0.95, 0.97, 1.0)
	h.snow.face([_on(w, fr.position.x, fr.position.y, 0.004), _on(w, fr.end.x, fr.position.y, 0.004),
			_on(w, fr.end.x, fr.end.y, 0.004), _on(w, fr.position.x, fr.end.y, 0.004)], w[2])
	# The frame: three carved steps round the picture (a lip, a raised band, a broad outer band).
	var half := ss * 0.5
	for band: Array in [[0.025, 0.07, 0.04], [0.07, 0.15, 0.075], [0.15, 0.24, 0.05]]:
		var i0 := float(band[0])
		var i1 := float(band[1])
		var proud := float(band[2])
		var col := Color(1.08, 1.1, 1.12, 0.3)
		var lo := Vector2(cx - half.x - i1, cy - half.y - i1)
		var hi := Vector2(cx + half.x + i1, cy + half.y + i1)
		var li := Vector2(cx - half.x - i0, cy - half.y - i0)
		var ui := Vector2(cx + half.x + i0, cy + half.y + i0)
		# Four mitred pieces: bottom, right, top, left.
		_block(h, w, PackedVector2Array([lo, Vector2(hi.x, lo.y), Vector2(ui.x, li.y), li]), proud, 0.01, col)
		_block(h, w, PackedVector2Array([Vector2(hi.x, lo.y), hi, ui, Vector2(ui.x, li.y)]), proud, 0.01, col)
		_block(h, w, PackedVector2Array([hi, Vector2(lo.x, hi.y), Vector2(li.x, ui.y), ui]), proud, 0.01, col)
		_block(h, w, PackedVector2Array([Vector2(lo.x, hi.y), lo, li, Vector2(li.x, ui.y)]), proud, 0.01, col)
	# The reliefs: a polar bear and a whale on the left, a fox and a hare on the right, all turned to the picture; a
	# snowy owl with its wings spread over it.
	var left := fr.position.x
	var right := fr.end.x
	var deep := PROUD + 0.045
	var places := [[BEAR, BEAR_LINES, Vector2(left - 1.04, 0.16), 0.98, false],
			[WHALE, WHALE_LINES, Vector2(left - 1.02, 1.42), 0.94, false],
			[FOX, FOX_LINES, Vector2(right + 0.66, 0.1), 1.0, true],
			[HARE, HARE_LINES, Vector2(right + 0.6, 1.38), 1.35, true]]
	for pl: Array in places:
		_relief(h, w, _outline(pl[0], pl[2], pl[3], pl[4]), deep, 0.018)
		_strokes(h, w, pl[1], pl[2], pl[3], pl[4], deep)
	_relief(h, w, _outline(FLIPPER, Vector2(left - 1.02, 1.42), 0.94, false), deep - 0.012, 0.01)
	var owl_y := fr.end.y + 0.03
	_relief(h, w, _owl(Vector2(cx, owl_y), OWL_SCALE), deep, 0.016)
	var owl_lines: Array = []
	for line: Array in OWL_LINES:
		owl_lines.append(line)
		var mirrored: Array = []
		for q: Array in line:
			mirrored.append([-float(q[0]), float(q[1])])
		owl_lines.append(mirrored)
	_strokes(h, w, owl_lines, Vector2(cx, owl_y), OWL_SCALE, false, deep)


## The carvings' cut lines (in the outlines' units): a polyline each, or one point for an eye.
const BEAR_LINES := [[[0.935, 0.455]], [[0.975, 0.405], [0.93, 0.395]], [[0.7, 0.33], [0.71, 0.22], [0.705, 0.1]],
		[[0.2, 0.36], [0.25, 0.25], [0.27, 0.14]], [[0.79, 0.46], [0.75, 0.38], [0.74, 0.3]],
		[[0.5, 0.5], [0.42, 0.44]], [[0.36, 0.48], [0.29, 0.43]]]
const WHALE_LINES := [[[0.86, 0.155]], [[0.995, 0.15], [0.9, 0.125], [0.82, 0.12]], [[0.88, 0.09], [0.7, 0.07],
		[0.52, 0.075]], [[0.86, 0.105], [0.68, 0.09], [0.54, 0.095]], [[0.18, 0.18], [0.12, 0.16]]]
const FOX_LINES := [[[0.07, 0.535]], [[0.135, 0.655], [0.13, 0.6]], [[0.1, 0.27], [0.095, 0.13]],
		[[0.12, 0.095], [0.28, 0.06], [0.42, 0.06]], [[0.33, 0.36], [0.4, 0.22], [0.38, 0.1]]]
const HARE_LINES := [[[0.06, 0.245]], [[0.125, 0.47], [0.11, 0.34]], [[0.29, 0.05], [0.35, 0.13], [0.3, 0.21]],
		[[0.07, 0.14], [0.08, 0.04]]]
## The owl's (its right half; mirrored): the eyes, the beak, the wing feathers, the breast's chevrons.
const OWL_LINES := [[[0.048, 0.585]], [[0.0, 0.555], [0.012, 0.52]], [[0.22, 0.52], [0.27, 0.3]],
		[[0.34, 0.56], [0.39, 0.31]], [[0.47, 0.58], [0.51, 0.33]], [[0.6, 0.58], [0.62, 0.36]],
		[[0.72, 0.55], [0.72, 0.42]], [[0.0, 0.4], [0.05, 0.37]], [[0.0, 0.3], [0.06, 0.27]], [[0.0, 0.2], [0.05, 0.17]]]


## Lines cut into a carving's face: clear ice (dark against the frost) a hair proud of it, an eye a small disc.
static func _strokes(h: Hall, w: Array, lines: Array, at: Vector2, scale: float, flip: bool, proud: float) -> void:
	var col := Color(0.55, 0.62, 0.68, 1.0)
	h.ice.colour = col
	var n: Vector3 = w[2]
	var z := proud + 0.002
	var half := 0.006
	for line: Array in lines:
		var pts := _outline(line, at, scale, flip)
		if pts.size() == 1:
			var ring := PackedVector3Array()
			for k in 8:
				var q := pts[0] + Vector2.from_angle(TAU * k / 8.0) * 0.016
				ring.append(_on(w, q.x, q.y, z))
			h.ice.polygon(ring, n)
			continue
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var side := (b - a).normalized().orthogonal() * half
			h.ice.face([_on(w, a.x - side.x, a.y - side.y, z), _on(w, b.x - side.x, b.y - side.y, z),
					_on(w, b.x + side.x, b.y + side.y, z), _on(w, a.x + side.x, a.y + side.y, z)], n)


# --- Benches ------------------------------------------------------------------------------------------------------

## A bench of ice under each row of the room's seats, as long as the row and a little more; the seats system lays a
## hide on it at each place (its pelt's top just over the bench, its front hanging down the bench's front). The seats'
## own boxes are its physics (the seats system's, there before the room builds).
static func _benches(h: Hall, c: Object, e: Dictionary) -> void:
	var rows := {}
	for s: Dictionary in Domestic.seat_slots_for(c.builder_params):
		var o := (s["transform"] as Transform3D).origin
		var key := snappedf(o.z, 0.01)
		var r: Vector2 = rows.get(key, Vector2(INF, -INF))
		rows[key] = Vector2(minf(r.x, o.x), maxf(r.y, o.x))
	for z: float in rows:
		var r: Vector2 = rows[z]
		var x0 := r.x - 0.42
		var x1 := r.y + 0.42
		var centre := Vector3((x0 + x1) * 0.5, 0.199, z - 0.045)
		var size := Vector3(x1 - x0, 0.398, 0.565)
		_box(h, centre, size, Basis(), 0.02, _ice_colour(h), true)


# --- Outside ------------------------------------------------------------------------------------------------------

## The snow's colour (linear), the spruces' needles, the cabin's red, its windows' glow.
const OUT_SNOW := Color(0.8, 0.84, 0.92)
const OUT_TRODDEN := Color(0.66, 0.7, 0.78)
const NEEDLES := Color(0.018, 0.03, 0.024)
const CABIN_RED := Color(0.2, 0.035, 0.025)
const CABIN_WINDOW := Color(1.0, 0.5, 0.16)
## The path from the doorway out into the snow (x, z in the room's frame), and the cabin far off (where, its turn).
const PATH := [[-2.07, 3.0], [-2.2, 5.5], [-3.6, 9.0], [-6.2, 13.5], [-9.8, 18.5], [-15.0, 25.0], [-22.0, 31.0],
		[-30.0, 36.0]]
const CABIN_AT := Vector3(-58.0, 0.0, -45.0)
## Spruces: [x, z, height] near the room (the window looks east, the doorway north-east), and the forest's edge far
## off made by rule.
## The window's view (south-east) is left open near the room: snow, the forest's edge, the cabin, the Moon; the
## nearer trees stand either side of it and round the path.
const SPRUCES := [[-13.9, -1.2, 7.0], [-21.7, -3.8, 9.0], [-6.8, -14.5, 8.0], [-6.2, -23.2, 10.0],
		[-17.0, -29.4, 9.0], [-32.9, -19.0, 8.0], [-21.2, -21.2, 6.5], [-24.1, -34.4, 9.5], [-6.8, 8.2, 6.5],
		[-10.6, 10.6, 9.0], [-4.1, 15.5, 7.0], [-16.4, 11.5, 8.5], [-18.5, 19.5, 9.0], [-1.9, 21.9, 10.0],
		[-24.4, 8.9, 7.5], [-14.4, 30.8, 8.0], [2.5, 12.0, 6.0]]


## The night outside: a snowfield from the walls' feet out to the fells (drifts, snow banked against the walls, a
## path trodden from the doorway), spruces under snow, the forest's dark edge, the fells on the horizon, a cabin far
## off with its windows lit.
static func _outside(h: Hall, e: Dictionary) -> void:
	var p := h.p
	var hw := float(p["half_width"]) + THICK
	var fz := float(p["front_z"]) - THICK
	var bz := float(p["back_z"]) + THICK
	var noise := FastNoiseLite.new()
	noise.seed = 68
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var b := h.outside
	var centre := Vector2(0.0, (fz + bz) * 0.5)
	var rings: Array[float] = [0.0, 0.35, 0.9, 1.8, 3.2, 5.0, 7.5, 11.0, 16.0, 23.0, 33.0, 47.0, 66.0, 90.0, 125.0]
	const SEGS := 96
	var rows: Array = []
	var normals: Array = []
	var colours: Array = []
	for r: float in rings:
		var row := PackedVector3Array()
		for k in SEGS + 1:
			var a := TAU * float(k % SEGS) / SEGS
			var d := Vector2(cos(a), sin(a))
			# Where the ray from the middle leaves the walls' outer faces.
			var tx := hw / maxf(absf(d.x), 1e-4)
			var tz := ((bz if d.y > 0.0 else fz) - centre.y) / (d.y if absf(d.y) > 1e-4 else 1e-4)
			var edge := minf(tx, absf(tz))
			var q := centre + d * (edge + r)
			row.append(Vector3(q.x, _snow_height(q, hw, fz, bz, noise), q.y))
		rows.append(row)
	for i in rows.size():
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for k in SEGS + 1:
			var q: Vector3 = rows[i][k]
			var eps := 0.3
			var hx := _snow_height(Vector2(q.x + eps, q.z), hw, fz, bz, noise) - _snow_height(Vector2(q.x - eps, q.z),
					hw, fz, bz, noise)
			var hz := _snow_height(Vector2(q.x, q.z + eps), hw, fz, bz, noise) - _snow_height(Vector2(q.x, q.z - eps),
					hw, fz, bz, noise)
			nrow.append(Vector3(-hx, 2.0 * eps, -hz).normalized())
			var trod := 1.0 - smoothstep(0.5, 1.2, _path_distance(Vector2(q.x, q.z)))
			var c := OUT_SNOW.lerp(OUT_TRODDEN, trod)
			crow.append(Color(c.r, c.g, c.b, 1.0))
		normals.append(nrow)
		colours.append(crow)
	# grid() winds its triangles by the normals: the rings run so the faces look up.
	b.grid(rows, normals, colours)
	h.rng.seed = 1968
	for s: Array in SPRUCES:
		var at := Vector2(float(s[0]), float(s[1]))
		_spruce(b, Vector3(at.x, _snow_height(at, hw, fz, bz, noise) - 0.1, at.y), float(s[2]), h.rng)
	# The forest's edge: smaller spruces in a band far off to the east and north-east, where the window and the
	# doorway look.
	for k in 70:
		var bearing := deg_to_rad(h.rng.randf_range(10.0, 170.0))
		var dist := h.rng.randf_range(55.0, 85.0)
		var at := Vector2(-sin(bearing) * dist, cos(bearing) * dist)
		if at.distance_to(Vector2(CABIN_AT.x, CABIN_AT.z)) < 9.0:
			continue
		_spruce(b, Vector3(at.x, _snow_height(at, hw, fz, bz, noise) - 0.2, at.y), h.rng.randf_range(6.0, 12.0), h.rng,
				6)
	_cabin(b, Vector3(CABIN_AT.x, _snow_height(Vector2(CABIN_AT.x, CABIN_AT.z), hw, fz, bz, noise), CABIN_AT.z))
	_fells(b, h.rng)


## The snow's height at a point outside: gentle drifts, rising slowly to the far land, banked against the walls, dug
## down along the path from the doorway.
static func _snow_height(q: Vector2, hw: float, fz: float, bz: float, noise: FastNoiseLite) -> float:
	var out := Vector2(maxf(absf(q.x) - hw, 0.0), maxf(maxf(fz - q.y, q.y - bz), 0.0)).length()
	var far := smoothstep(4.0, 60.0, out)
	var y := noise.get_noise_2d(q.x, q.y) * (0.25 + 2.2 * far) + far * 1.2
	y += 0.55 * exp(-out / 1.1)
	var path := _path_distance(q)
	y = lerpf(y, minf(y, -0.05 + 0.02 * out), 1.0 - smoothstep(0.6, 1.6, path))
	return y


static func _path_distance(q: Vector2) -> float:
	var best := INF
	for k in PATH.size() - 1:
		var a := Vector2(float(PATH[k][0]), float(PATH[k][1]))
		var c := Vector2(float(PATH[k + 1][0]), float(PATH[k + 1][1]))
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, c)))
	return best


## A spruce under snow: tiers of drooping boughs, each a jagged cone, snow lying on their tops; the trunk under them.
static func _spruce(b: RoomMesh, foot: Vector3, height: float, rng: RandomNumberGenerator, sides := 9) -> void:
	var tiers := 8 if sides > 6 else 6
	var turn := rng.randf() * TAU
	for t in tiers:
		var f := float(t) / tiers
		var y0 := foot.y + height * lerpf(0.12, 0.86, f)
		var top := y0 + height * (0.2 if t < tiers - 1 else 0.24)
		var r := height * 0.3 * (1.0 - f * 0.85) * rng.randf_range(0.85, 1.1)
		var rim := PackedVector3Array()
		for k in sides + 1:
			var a := turn + TAU * float(k % sides) / sides + t * 0.4
			var jag := 1.0 if k % 2 == 0 else 0.72
			rim.append(foot + Vector3(cos(a) * r * jag, y0 - foot.y - r * 0.12 * jag, sin(a) * r * jag))
		var apex := Vector3(foot.x, top, foot.z)
		# The tier's top: a cap of snow lying on its inner part, the boughs' dark tips showing beyond it.
		var dark := NEEDLES.lerp(OUT_SNOW, 0.06)
		var snowy := OUT_SNOW * 0.92
		for k in sides:
			var a0 := rim[k]
			var a1 := rim[k + 1]
			var n := (a1 - a0).cross(apex - a0).normalized()
			if n.y < 0.0:
				n = -n
			var cap := rng.randf_range(0.45, 0.65)
			var m0 := apex.lerp(a0, cap)
			var m1 := apex.lerp(a1, cap)
			_tri(b, [apex, m0, m1], [n, n, n], [snowy, snowy, snowy])
			_tri(b, [m0, a0, a1], [n, n, n], [NEEDLES.lerp(OUT_SNOW, 0.35), dark, dark])
			_tri(b, [m0, a1, m1], [n, n, n], [NEEDLES.lerp(OUT_SNOW, 0.35), dark, NEEDLES.lerp(OUT_SNOW, 0.35)])
			# The underside, dark.
			var under := Vector3(foot.x, y0 - r * 0.05, foot.z)
			_tri(b, [under, a1, a0], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], [NEEDLES, NEEDLES, NEEDLES])
	# The trunk's foot under the lowest boughs.
	var tr := height * 0.025
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var p0 := foot + Vector3(cos(a0) * tr, 0, sin(a0) * tr)
		var p1 := foot + Vector3(cos(a1) * tr, 0, sin(a1) * tr)
		var up := Vector3(0, height * 0.16, 0)
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var dark := Color(0.03, 0.022, 0.016)
		_tri(b, [p0, p1, p1 + up], [n, n, n], [dark, dark, dark])
		_tri(b, [p0, p1 + up, p0 + up], [n, n, n], [dark, dark, dark])


## One triangle into the outside's mesh, its corners' normals and colours (a lit surface).
static func _tri(b: RoomMesh, pts: Array, ns: Array, cols: Array) -> void:
	var rows := [PackedVector3Array([pts[0], pts[0]]), PackedVector3Array([pts[1], pts[2]])]
	var nrm := [PackedVector3Array([ns[0], ns[0]]), PackedVector3Array([ns[1], ns[2]])]
	var c0: Color = cols[0]
	var c1: Color = cols[1]
	var c2: Color = cols[2]
	var col := [PackedColorArray([Color(c0, 1.0), Color(c0, 1.0)]), PackedColorArray([Color(c1, 1.0), Color(c2, 1.0)])]
	b.grid(rows, nrm, col)


## A cabin far off: red log walls, a roof heavy with snow, a chimney, two windows lit warm towards the room.
static func _cabin(b: RoomMesh, foot: Vector3) -> void:
	var face := (Vector3(0, 0, -1.5) - foot)
	face.y = 0.0
	var fwd := face.normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	var basis := Basis(right, Vector3.UP, fwd)
	var w := 5.2
	var d := 3.8
	var wall := 2.5
	var ridge := 1.7
	var at := func(x: float, y: float, z: float) -> Vector3: return foot + basis * Vector3(x, y, z)
	var red := Color(CABIN_RED, 1.0)
	# The walls (the two gable ends to the ridge's height).
	for s: float in [-1.0, 1.0]:
		_quad(b, [at.call(-w * 0.5, -0.3, s * d * 0.5), at.call(w * 0.5, -0.3, s * d * 0.5),
				at.call(w * 0.5, wall, s * d * 0.5), at.call(-w * 0.5, wall, s * d * 0.5)], basis * Vector3(0, 0, s), red)
		_quad(b, [at.call(s * w * 0.5, -0.3, -d * 0.5), at.call(s * w * 0.5, -0.3, d * 0.5),
				at.call(s * w * 0.5, wall, d * 0.5), at.call(s * w * 0.5, wall, -d * 0.5)], basis * Vector3(s, 0, 0), red)
		_tri(b, [at.call(s * w * 0.5, wall, -d * 0.5), at.call(s * w * 0.5, wall, d * 0.5),
				at.call(s * w * 0.5, wall + ridge, 0.0)], [basis * Vector3(s, 0, 0), basis * Vector3(s, 0, 0),
				basis * Vector3(s, 0, 0)], [red, red, red])
	# The roof, its snow thick on both slopes, its eaves over the walls.
	for s: float in [-1.0, 1.0]:
		var n := (basis * Vector3(0, d * 0.5 + 0.4, s * ridge)).normalized()
		_quad(b, [at.call(-w * 0.5 - 0.35, wall + ridge + 0.25, 0.0), at.call(w * 0.5 + 0.35, wall + ridge + 0.25, 0.0),
				at.call(w * 0.5 + 0.35, wall - 0.25, s * (d * 0.5 + 0.5)),
				at.call(-w * 0.5 - 0.35, wall - 0.25, s * (d * 0.5 + 0.5))], n, Color(OUT_SNOW, 1.0))
	# The chimney.
	for k in 4:
		var n := basis * Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5))
		var t := basis * Vector3(-sin(k * PI * 0.5), 0, cos(k * PI * 0.5))
		var c: Vector3 = at.call(1.2, wall + ridge + 0.3, -0.5) + n * 0.25
		_quad(b, [c - t * 0.25 - Vector3(0, 0.9, 0), c + t * 0.25 - Vector3(0, 0.9, 0), c + t * 0.25, c - t * 0.25], n,
				Color(0.08, 0.06, 0.05, 1.0))
	# Two windows lit warm on the side towards the room (and one in the gable), a little proud of the wall.
	var lit := Color(CABIN_WINDOW, 0.0)
	for x: float in [-1.3, 1.1]:
		_quad(b, [at.call(x - 0.4, 0.95, d * 0.5 + 0.02), at.call(x + 0.4, 0.95, d * 0.5 + 0.02),
				at.call(x + 0.4, 1.75, d * 0.5 + 0.02), at.call(x - 0.4, 1.75, d * 0.5 + 0.02)], fwd, lit)


static func _quad(b: RoomMesh, pts: Array, n: Vector3, colour: Color) -> void:
	var rows := [PackedVector3Array([pts[0], pts[1]]), PackedVector3Array([pts[3], pts[2]])]
	var nrm := [PackedVector3Array([n, n]), PackedVector3Array([n, n])]
	var col := [PackedColorArray([colour, colour]), PackedColorArray([colour, colour])]
	b.grid(rows, nrm, col)


## The fells all round on the horizon: low snowy hills, the forest dark along their feet.
static func _fells(b: RoomMesh, rng: RandomNumberGenerator) -> void:
	const SEGS := 120
	var noise := FastNoiseLite.new()
	noise.seed = 1909
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	var dist := 150.0
	var low := PackedVector3Array()
	var mid := PackedVector3Array()
	var top := PackedVector3Array()
	var nl := PackedVector3Array()
	var nt := PackedVector3Array()
	var cl := PackedColorArray()
	var cm := PackedColorArray()
	var ct := PackedColorArray()
	for k in SEGS + 1:
		var a := TAU * float(k % SEGS) / SEGS
		var d := Vector3(cos(a), 0.0, sin(a))
		var hgt := 7.0 + 9.0 * (0.5 + 0.5 * noise.get_noise_1d(float(k % SEGS) / SEGS * 6.0)) + 4.0 * maxf(
				noise.get_noise_1d(float(k % SEGS) / SEGS * 6.0 + 40.0), 0.0)
		# Lower to the south-east, where the Moon rises in the window.
		hgt *= lerpf(1.0, 0.45, maxf(-d.x, 0.0) * maxf(-d.z * 1.4, 0.0))
		low.append(d * dist + Vector3(0, -2.0, 0))
		mid.append(d * dist + Vector3(0, 2.2, 0))
		top.append(d * (dist + 8.0) + Vector3(0, hgt, 0))
		nl.append(-d)
		nt.append((-d + Vector3.UP * 0.6).normalized())
		cl.append(Color(NEEDLES, 1.0))
		cm.append(Color(NEEDLES.lerp(OUT_SNOW, 0.15), 1.0))
		ct.append(Color(OUT_SNOW * 0.9, 1.0))
	b.grid([low, mid], [nl, nl], [cl, cm])
	b.grid([mid, top], [nt, nt], [cm, ct])
