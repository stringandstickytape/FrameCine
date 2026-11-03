extends RefCounted

## Meshes for the spherical projections, built once per mode change. Viewed from the centre (inside-out: front faces
## wind clockwise as seen from inside, the engine's front-face order). UV = position in ONE EYE's picture (0..1, v down);
## video.gdshader adds the stereo layout. The UV is exact at the vertices and interpolated between them, so the grid
## density sets the mapping error: about (step^2)/8, 0.02 degrees for 2.8-degree steps, well under a pixel.
##
## Directions: -Z is straight ahead, +X right, +Y up (the engine's camera convention).

## 360 x 180 degrees: 128 x 64 quads (8,385 vertices); 180 x 180: 64 x 64.
const STEP_DEG := 2.8125


## Equirectangular: longitude span_deg (360 or 180) centred on -Z, latitude -90..90. u = 0.5 at straight ahead and
## grows to the right; v = 0 at the top (straight up).
static func equirect(span_deg: float, radius: float) -> ArrayMesh:
	var cols := maxi(8, roundi(span_deg / STEP_DEG))
	var rows := maxi(8, roundi(180.0 / STEP_DEG))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize((rows + 1) * (cols + 1))
	uvs.resize(verts.size())
	var k := 0
	for i in rows + 1:
		var v := float(i) / rows
		var lat := deg_to_rad(90.0 - 180.0 * v)
		for j in cols + 1:
			var u := float(j) / cols
			var lon := deg_to_rad((u - 0.5) * span_deg)
			verts[k] = radius * Vector3(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat))
			uvs[k] = Vector2(u, v)
			k += 1
	var indices := PackedInt32Array()
	for i in rows:
		for j in cols:
			var a := i * (cols + 1) + j  # top left (as seen from inside)
			var b := a + 1               # top right
			var c := a + cols + 1        # bottom left
			var d := c + 1               # bottom right
			indices.append_array([a, b, d, a, d, c])
	return _mesh(verts, uvs, indices)


## Fisheye cap of fov_deg around -Z: rings every STEP_DEG off axis, 128 segments around. The image circle is inscribed
## in the eye's picture: uv = 0.5 + 0.5 * r(theta) * (cos phi, -sin phi), phi from +X towards +Y. r is the lens's
## mapping (theta in radians -> 0..1 of the circle's radius; scripts/play/fisheye_lens.gd, ideas #73); none:
## equidistant, r = theta / (fov / 2).
static func fisheye(fov_deg: float, radius: float, lens: Callable = Callable()) -> ArrayMesh:
	var half := deg_to_rad(fov_deg * 0.5)
	var rings := maxi(8, roundi(fov_deg * 0.5 / STEP_DEG))
	var segs := 128
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in rings + 1:
		var theta := half * float(i) / rings
		var r_uv := 0.5 * (float(lens.call(theta)) if lens.is_valid() else float(i) / rings)
		for j in segs + 1:
			var phi := TAU * float(j) / segs
			verts.append(radius * Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), -cos(theta)))
			uvs.append(Vector2(0.5 + r_uv * cos(phi), 0.5 - r_uv * sin(phi)))
	var indices := PackedInt32Array()
	for i in rings:
		for j in segs:
			var inner := i * (segs + 1) + j
			var outer := inner + segs + 1
			# phi grows counter-clockwise on screen, so clockwise is inner -> outer+1 -> outer.
			indices.append_array([inner, outer + 1, outer, inner, inner + 1, outer + 1])
	return _mesh(verts, uvs, indices)


## Dual fisheye 360 (a 360 camera's raw frame: two image circles, one lens looking ahead and one looking back): the whole
## sphere as rings every STEP_DEG around straight ahead (-Z), 128 segments around, with extra rings every BAND_STEP_DEG
## through the seam band. Each vertex carries both lenses' places in the frame and how much of each to show:
##   UV       the front lens's place (0..1 of the whole frame, v down)
##   UV2      the back lens's place
##   COLOR.r  the front lens's weight: 1 up to (90 - blend) degrees from straight ahead, 0 from (90 + blend), a
##            smoothstep between, so the seam is a soft cross-fade over 2 x blend degrees where both lenses see
##            (each lens sees past 90 degrees: a 195 degree lens 7.5 degrees). video.gdshader samples once outside
##            the band and twice inside it.
## lens (scripts/play/dual_fisheye.gd): {front: {fov, cx, cy, radius, yaw, pitch, roll}, back: {...}, blend, model}.
## cx, cy: the circle's centre in fractions of the frame's width and height; radius: of the frame's height (0.5 = the
## circle touches the top and bottom); fov: degrees across the circle; yaw, pitch, roll: the lens turned from its
## nominal direction, degrees (yaw about up, then pitch about right, then roll about the lens axis). frame_aspect:
## width / height of the frame. mapping(model, fov) -> Callable(theta) -> 0..1 of the radius (FisheyeLens.mapping).
## Each circle is upright in the frame; the back lens's picture is mirrored left-right against the front's, as a lens
## looking the other way sees it (its picture's right is the viewer's left).
const BAND_STEP_DEG := 0.5


static func dual_fisheye(lens: Dictionary, radius: float, frame_aspect: float, mapping: Callable) -> ArrayMesh:
	var front: Dictionary = lens["front"]
	var back: Dictionary = lens["back"]
	var blend := clampf(float(lens.get("blend", 3.0)), 0.0, 20.0)
	var model := str(lens.get("model", "equidistant"))
	var map_front: Callable = mapping.call(model, float(front["fov"]))
	var map_back: Callable = mapping.call(model, float(back["fov"]))
	var inv_front := lens_basis(front).transposed()
	var inv_back := lens_basis(back).transposed()
	# Ring angles: the plain grid, plus the band's finer rings (merged, sorted, no near-duplicates).
	var thetas: Array[float] = []
	var rings := roundi(180.0 / STEP_DEG)
	for i in rings + 1:
		thetas.append(180.0 * float(i) / rings)
	if blend > 0.0:
		var t := 90.0 - blend
		while t <= 90.0 + blend + 0.001:
			thetas.append(t)
			t += minf(BAND_STEP_DEG, blend)
	thetas.sort()
	var unique: Array[float] = []
	for t in thetas:
		if unique.is_empty() or t - unique[-1] > 0.05:
			unique.append(t)
	var segs := 128
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colours := PackedColorArray()
	for t_deg in unique:
		var theta := deg_to_rad(t_deg)
		var w := 1.0 - smoothstep(90.0 - blend, 90.0 + blend, t_deg) if blend > 0.0 else (1.0 if t_deg < 90.0 else 0.0)
		for j in segs + 1:
			var phi := TAU * float(j) / segs
			var d := Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), -cos(theta))
			verts.append(radius * d)
			var f := inv_front * d
			uvs.append(_circle_uv(Vector3(f.x, f.y, -f.z), front, frame_aspect, map_front))
			var b := inv_back * d
			uv2s.append(_circle_uv(Vector3(-b.x, b.y, b.z), back, frame_aspect, map_back))
			colours.append(Color(w, w, w, 1.0))
	var indices := PackedInt32Array()
	for i in unique.size() - 1:
		for j in segs:
			var inner := i * (segs + 1) + j
			var outer := inner + segs + 1
			indices.append_array([inner, outer + 1, outer, inner, inner + 1, outer + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A lens's turn from its nominal direction: yaw about +Y, then pitch about +X, then roll about the lens axis (Z).
static func lens_basis(l: Dictionary) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(float(l.get("yaw", 0.0)))) \
			* Basis(Vector3.RIGHT, deg_to_rad(float(l.get("pitch", 0.0)))) \
			* Basis(Vector3.BACK, deg_to_rad(float(l.get("roll", 0.0))))


## A direction in the lens's own frame (x right, y up, z along the lens) -> its place in the frame (0..1, v down).
static func _circle_uv(local: Vector3, l: Dictionary, frame_aspect: float, map: Callable) -> Vector2:
	var theta := acos(clampf(local.z, -1.0, 1.0))
	var phi := atan2(local.y, local.x)
	var r := float(map.call(theta))
	var rad := float(l["radius"])
	return Vector2(float(l["cx"]) + rad / frame_aspect * r * cos(phi), float(l["cy"]) - rad * r * sin(phi))


static func _mesh(verts: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
