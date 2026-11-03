extends RefCounted

## Renders the effect library's effects off screen for its tools and tests (tools/fx_lab.gd, tests/test_effects.gd;
## docs/effects.md): a preview, a clip of the brightness over time with the shader's clock stepped by hand, and the
## GPU time of a surface filling the view. Needs a renderer (WSL: lavapipe under xvfb-run); headless every function
## returns empty.
##
## Each picture is its own SubViewport with its own world, a camera and the part (a sphere, or the sky sphere around
## the camera), so the world positions are the same in every frame of a clip.

const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const PLAIN_SHADER := preload("res://shaders/env_unlit_tex.gdshader")

## The colour under an effect in previews and clips (a mid wood; the room tests' too).
const BASE_COLOR := Color("#8a6e4b")
## Clips use a dark base, so an effect's own light is most of the brightness: the strictest case for its swing.
const DARK_BASE := Color(0.06, 0.06, 0.06)
## Options pushed to their maximum for the photosensitivity clip (the fastest, largest case), unless the entry's
## photo_test says otherwise.
const FAST_OPTIONS: Array[String] = ["rate", "speed", "swing", "strength", "depth", "twinkle", "react"]
## The ceiling as a slope: a 3 Hz wave of the full swing changes by at most 2 pi x 3 x 0.4 of its mean a second.
const MAX_SLOPE := TAU * EffectLibrary.MAX_HZ * EffectLibrary.MAX_SWING


static func has_renderer() -> bool:
	return DisplayServer.get_name() != "headless"


## The room's light as the previews and clips use it: a dim room with the screen's light and a film's colours
## (warm left, cool right), loud enough for the reactive effects.
static func set_room(tree: SceneTree, react := 0.6) -> void:
	RenderingServer.global_shader_parameter_set("env_light", 0.35)
	RenderingServer.global_shader_parameter_set("screen_center", Vector3(0.0, 1.0, 4.0))
	RenderingServer.global_shader_parameter_set("screen_glow", 0.8)
	RenderingServer.global_shader_parameter_set("screen_axis", Vector3(0.333, 0.0, 0.0))
	var img := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	for x in 4:
		for y in 2:
			img.set_pixel(x, y, Color(0.75, 0.45, 0.25).lerp(Color(0.25, 0.45, 0.8), x / 3.0))
	RenderingServer.global_shader_parameter_set("screen_thumb", ImageTexture.create_from_image(img))
	RenderingServer.global_shader_parameter_set("screen_tint", 1.0)
	tree.set_meta("fx_lab_react", react)


## A material with the effect on it, as the room builder would make it: colour, the effect's options, a fixed seed.
static func material(id: String, options := {}, base := BASE_COLOR, test_clock := false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	EffectLibrary.apply(mat, id, options, 0.37, {"test_clock": test_clock})
	mat.set_shader_parameter("albedo", base)
	mat.set_shader_parameter("alpha", base.a)
	return mat


## One picture's stage: a SubViewport with its own world, a camera and the part. sky: the camera inside a sky sphere,
## looking 28 degrees up with sky_fov 90 (a preview), or 20 up with a narrow one (a clip: stars about a pixel wide);
## else a sphere of radius 1 at the origin, `fill` of the view's height across.
static func stage(size: Vector2i, mat: Material, sky := false, fill := 0.8, backdrop := true,
		sky_fov := 90.0) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.world_3d = World3D.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	var cam := Camera3D.new()
	vp.add_child(cam)
	var mi := MeshInstance3D.new()
	if sky:
		var s := SphereMesh.new()
		s.radius = 50.0
		s.height = 100.0
		s.radial_segments = 64
		s.rings = 32
		mi.mesh = s
		cam.fov = sky_fov
		cam.far = 200.0
		cam.rotation_degrees = Vector3(28.0 if sky_fov >= 60.0 else 20.0, 0.0, 0.0)
	else:
		var s := SphereMesh.new()
		s.radial_segments = 64
		s.rings = 32
		s.radius = 1.0
		s.height = 2.0
		mi.mesh = s
		cam.fov = 40.0
		# Distance so the sphere's diameter is `fill` of the view's height.
		cam.position = Vector3(0.0, 0.0, 1.0 / (fill * tan(deg_to_rad(cam.fov) * 0.5)))
		if backdrop:
			var back := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(12.0, 12.0)
			back.mesh = q
			back.position = Vector3(0.0, 0.0, -3.0)
			var bm := StandardMaterial3D.new()
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.albedo_color = Color(0.1, 0.105, 0.12)
			back.material_override = bm
			vp.add_child(back)
	mi.material_override = mat
	vp.add_child(mi)
	return vp


static func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


## A preview: the effect on a sphere (or the sky) with its defaults, the clock stopped at a set time.
static func preview(tree: SceneTree, id: String, size := Vector2i(160, 160)) -> Image:
	if not has_renderer() or not EffectLibrary.has(id):
		return null
	var e := EffectLibrary.entry(id)
	var mat := material(id, e.get("preview_options", {}), BASE_COLOR, true)
	mat.set_shader_parameter("fx_test_time", 3.7)
	mat.set_shader_parameter("react_level", float(tree.get_meta("fx_lab_react", 0.6)))
	var vp := stage(size, mat, str(e["surfaces"]) == "sky")
	tree.root.add_child(vp)
	await _frames(tree, 3)
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


## The options a photosensitivity clip uses: the entry's photo_test, else the fast options at their maximum.
static func fastest_options(id: String) -> Dictionary:
	var e := EffectLibrary.entry(id)
	if e.has("photo_test"):
		return (e["photo_test"] as Dictionary).duplicate()
	var out := {}
	for k: String in e["options"]:
		var o: Dictionary = e["options"][k]
		if k in FAST_OPTIONS and str(o["type"]) == "float":
			out[k] = o["max"]
	return out


## The effect's brightness over `seconds` at `hz` pictures a second, the shader's clock stepped by hand: every
## picture rendered at once, each in its own viewport. [Image, ...]; empty headless or for an effect on the room
## shader (its clock is the engine's). A sky is seen 64 x 64 through 5 degrees, about the headset's pixels per degree
## (a star a pixel or two wide, as it is there); a part, a sphere filling `size` (64: a 24 px clip blurs away the
## steps a slow drift over a magnified noise texture takes, which a finer one sees).
static func clip(tree: SceneTree, id: String, options: Dictionary, seconds := 4.0, hz := 30.0,
		size := Vector2i(64, 64)) -> Array[Image]:
	var out: Array[Image] = []
	if not has_renderer() or str(EffectLibrary.entry(id).get("shader", "")).ends_with("room_effect.gdshader"):
		return out
	var sky := str(EffectLibrary.entry(id)["surfaces"]) == "sky"
	var vps: Array[SubViewport] = []
	var n := int(seconds * hz)
	for k in n:
		var mat := material(id, options, DARK_BASE, true)
		mat.set_shader_parameter("fx_test_time", 11.0 + k / hz)
		mat.set_shader_parameter("react_level", float(tree.get_meta("fx_lab_react", 0.6)))
		var vp := stage(Vector2i(64, 64) if sky else size, mat, sky, 0.95, false, 5.0)
		tree.root.add_child(vp)
		vps.append(vp)
	await _frames(tree, 3)
	for vp in vps:
		out.append(vp.get_texture().get_image())
		vp.queue_free()
	return out


## What a clip says about the ceiling: per pixel, the steepest change between pictures over the pixel's mean
## brightness (linear light), a second; the worst pixel's against MAX_SLOPE; and the largest swing ((max - min) /
## (max + min)). Pixels darker than 2 % are left out (black, the backdrop).
static func photo_check(frames: Array[Image], hz := 30.0) -> Dictionary:
	if frames.size() < 2:
		return {}
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var lum: Array[PackedFloat32Array] = []
	for img in frames:
		var data := img.get_data()
		var ch := 4 if img.get_format() == Image.FORMAT_RGBA8 else 3
		var l := PackedFloat32Array()
		l.resize(w * h)
		for i in w * h:
			var r := _lin(data[i * ch] / 255.0)
			var g := _lin(data[i * ch + 1] / 255.0)
			var b := _lin(data[i * ch + 2] / 255.0)
			l[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
		lum.append(l)
	var worst := 0.0
	var worst_swing := 0.0
	var counted := 0
	for i in w * h:
		var lo := 1e9
		var hi := -1e9
		var sum := 0.0
		var steep := 0.0
		for k in lum.size():
			var x := lum[k][i]
			lo = minf(lo, x)
			hi = maxf(hi, x)
			sum += x
			if k > 0:
				steep = maxf(steep, absf(x - lum[k - 1][i]))
		var mean := sum / lum.size()
		if mean < 0.02:
			continue
		counted += 1
		worst = maxf(worst, steep * hz / mean)
		worst_swing = maxf(worst_swing, (hi - lo) / maxf(hi + lo, 1e-6))
	return {"slope": snappedf(worst, 0.001), "max_slope": snappedf(MAX_SLOPE, 0.001),
			"of_ceiling": snappedf(worst / MAX_SLOPE, 0.001), "swing": snappedf(worst_swing, 0.001),
			"pixels": counted}


static func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## The GPU time (ms, the median of `frames`) of a viewport `size` square with mat on a sphere filling most of it (the
## sky around the camera for a sky effect), after `warmup` frames. mat null: the empty stage.
static func gpu_ms(tree: SceneTree, mat: Material, sky := false, size := 1024, frames := 30, warmup := 8) -> float:
	if not has_renderer():
		return -1.0
	var vp := stage(Vector2i(size, size), mat if mat != null else StandardMaterial3D.new(), sky, 1.15, false)
	if mat == null:
		for c in vp.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false
	tree.root.add_child(vp)
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(tree, warmup)
	var times: Array[float] = []
	for i in frames:
		await RenderingServer.frame_post_draw
		times.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	RenderingServer.viewport_set_measure_render_time(rid, false)
	vp.queue_free()
	times.sort()
	return times[times.size() / 2]


## The plain surface every effect is measured against: env_unlit_tex.gdshader, opaque, a colour.
static func plain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PLAIN_SHADER
	mat.set_shader_parameter("albedo", BASE_COLOR)
	return mat
