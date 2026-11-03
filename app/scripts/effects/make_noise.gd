extends SceneTree

## Makes the effect library's shared noise textures (docs/effects.md, "Noise"), committed under app/textures/fx/ and
## read at run time by effect_library.gd (the app runs from its folder: nothing is imported). Run it again only to
## change them; the output is the same every time (fixed seeds).
##
##   godot --headless --path app --script res://scripts/effects/make_noise.gd
##
## fx_value.png, 64 x 64 RGBA: white noise for one-tap 3D value noise (fx_common.gdshaderinc fx_noise3). R is a
## random value per texel and G is R moved by (37, 17) texels, so one bilinear tap at (x + 37 z, y + 17 z) gives the
## lattice's values at z (R) and z + 1 (G); B and A are a second, independent pair. Sampled without mipmaps.
## fx_fbm.png, 256 x 256 RGBA, tiling, mipmapped at load: R and G two smooth fractal noises (four octaves of
## periodic value noise baked in, so a shader samples one tap instead of four octaves), B the distance to the nearest
## of 8 x 8 jittered cell points (Worley F1: caustics, cells, bubbles), A the gap to the second nearest (F2 - F1:
## the cells' borders, for leads, cracks and facets). Each channel stretched to 0..1.

const OUT := "res://textures/fx"
const VALUE_SIZE := 64
const FBM_SIZE := 256
## The lattice move between one z slice and the next (fx_common.gdshaderinc uses the same numbers).
const SHIFT := Vector2i(37, 17)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_value().save_png(OUT.path_join("fx_value.png"))
	_fbm().save_png(OUT.path_join("fx_fbm.png"))
	for f in ["fx_value.png", "fx_fbm.png"]:
		print("%s: %d bytes" % [f, FileAccess.get_file_as_bytes(OUT.path_join(f)).size()])
	quit()


func _value() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7341
	var n := VALUE_SIZE
	var r := PackedByteArray()
	var b := PackedByteArray()
	r.resize(n * n)
	b.resize(n * n)
	for i in n * n:
		r[i] = rng.randi_range(0, 255)
		b[i] = rng.randi_range(0, 255)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var o := ((y + SHIFT.y) % n) * n + (x + SHIFT.x) % n
			img.set_pixel(x, y, Color.from_rgba8(r[y * n + x], r[o], b[y * n + x], b[o]))
	return img


func _fbm() -> Image:
	var n := FBM_SIZE
	var lat_a := _lattice(1201, 64)
	var lat_b := _lattice(5507, 64)
	var cells := 8
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var pts: Array[Vector2] = []
	for i in cells * cells:
		pts.append(Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9)))
	var ch: Array[PackedFloat32Array] = []
	for c in 4:
		var a := PackedFloat32Array()
		a.resize(n * n)
		ch.append(a)
	for y in n:
		for x in n:
			var u := float(x) / n
			var v := float(y) / n
			var i := y * n + x
			ch[0][i] = _fractal(lat_a, u, v)
			ch[1][i] = _fractal(lat_b, u, v)
			# Worley on a torus: the nearest two of the 3 x 3 cells around.
			var p := Vector2(u, v) * cells
			var c := Vector2i(floori(p.x), floori(p.y))
			var d1 := 9.0
			var d2 := 9.0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var q := c + Vector2i(ox, oy)
					var k := posmod(q.y, cells) * cells + posmod(q.x, cells)
					var d := p.distance_to(Vector2(q) + pts[k])
					if d < d1:
						d2 = d1
						d1 = d
					elif d < d2:
						d2 = d
			ch[2][i] = d1
			ch[3][i] = d2 - d1
	for c in 4:
		_stretch(ch[c])
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var i := y * n + x
			img.set_pixel(x, y, Color(ch[0][i], ch[1][i], ch[2][i], ch[3][i]))
	return img


## Random values on a period x period lattice.
func _lattice(seed_value: int, period: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedFloat32Array()
	out.resize(period * period)
	for i in out.size():
		out[i] = rng.randf()
	return out


## Periodic value noise at (u, v) in 0..1, freq cells across, read off a 64 x 64 lattice (wraps at the freq).
func _value_noise(lat: PackedFloat32Array, u: float, v: float, freq: int, offset: int) -> float:
	var x := u * freq
	var y := v * freq
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
	fy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
	var at := func(a: int, b: int) -> float:
		return lat[(posmod(b, freq) + offset) % 64 * 64 + (posmod(a, freq) + offset * 3) % 64]
	return lerpf(lerpf(at.call(ix, iy), at.call(ix + 1, iy), fx), lerpf(at.call(ix, iy + 1), at.call(ix + 1, iy + 1),
			fx), fy)


## Four octaves, 4 to 32 cells across, each half the last.
func _fractal(lat: PackedFloat32Array, u: float, v: float) -> float:
	var s := 0.0
	var a := 0.5
	var f := 4
	for o in 4:
		s += a * _value_noise(lat, u, v, f, o * 7)
		f *= 2
		a *= 0.5
	return s / 0.9375


## To 0..1, cutting the extreme 0.5 % at each end.
func _stretch(a: PackedFloat32Array) -> void:
	var sorted := a.duplicate()
	sorted.sort()
	var lo := sorted[int(sorted.size() * 0.005)]
	var hi := sorted[int(sorted.size() * 0.995)]
	for i in a.size():
		a[i] = clampf((a[i] - lo) / maxf(hi - lo, 1e-6), 0.0, 1.0)
