extends RefCounted

## The checks every room document passes (docs/environments.md, "The checks"): schema, the headset budget (the room
## built and measured), a clear sight line from every seat, comfort, licences, names, no people. Each returns a list
## of problems ([] when it passes), worded for the person or the agent who made the room. Static; preload to use.
## tests/test_environments.gd runs them over every app/environments/*.env.json; tests/test_env_checks.gd shows each
## one catching a bad document.

const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const ScreenFrame := preload("res://scripts/env/systems/screen_frame.gd")
const RoomMesh := preload("res://scripts/env/room_mesh.gd")

## The headset budget per room (the Frame at 72 Hz with a film playing; docs/environments.md has the table).
const BUDGET := {"draws": 40, "triangles": 400000, "lights": 2, "particles": 4000, "texture_mb": 96.0}
## Eyes over a seat's floor point.
const EYE_HEIGHT := 1.2
## The screen's points the sight line goes to: its centre, corners and edges, this far in.
const SCREEN_INSET := 0.05
## Real marks a room's text may not name (whole words, any case). Pastiche is fine ("Sirclive", "FreeDTV"); the mark
## itself never. Add to it; never take one out.
const MARKS: Array[String] = ["Odeon", "Nickelodeon", "Regal", "Omnimax", "IMAX", "Atmos", "Dolby", "THX",
		"Compton", "Wurlitzer", "Tron", "Quality Street", "Kia-Ora", "Trinitron", "Baird Televisor", "HD Ready",
		"Sinclair", "Freeview", "Cinerama", "Technicolor", "Cineworld", "Showcase Cinemas", "AMC", "Pathe",
		"Gaumont", "Sony", "Panasonic", "Philips", "Grundig", "Teletext", "Ceefax", "Betamax", "VHS", "Walkman",
		"Coca-Cola", "Pepsi", "Butterkist", "Maltesers", "Kit Kat", "Space Invaders", "Pac-Man", "ZX Spectrum",
		"Commodore", "Atari", "Nintendo", "SEGA", "Disney", "Pixar", "Warner Bros", "Paramount", "MGM", "Netflix"]
## Words that mark a person, a people or a crowd in an object's or a system's name.
const PEOPLE_WORDS: Array[String] = ["person", "people", "crowd", "audience", "human", "mannequin", "figure",
		"man", "woman", "child", "usher", "projectionist", "spectator", "avatar"]
## Comfort: a brightness may change no faster than the photosensitivity ceiling.
static var MIN_SMOOTH: float = 1.0 / (TAU * RoomSchema.MAX_HZ)
static var MIN_FADE: float = 1.0 / (2.0 * RoomSchema.MAX_HZ)
## Comfort: scenery that goes by (the passing system). The viewer sits still and the world outside the windows
## moves, which gives the feeling of moving with nothing felt to match it. "No system moves the viewer" is there to
## prevent exactly that feeling, so scenery that goes by has limits of its own, and no room can loosen them:
##   - it goes straight, at a steady height: no turn, no tilt, no rise or fall of the horizon. (The system has no
##     parameter that could ask for one; this line is why.)
##   - at its nearest, nothing crosses the eye faster than FLOW_MAX_DEG degrees a second
##   - nothing passes nearer than FLOW_NEAREST metres from the line the room's own seat travels along
##   - its speed changes no faster than FLOW_ACCEL (the motion system's limit for a thing in the room, kept)
##   - from the room's own seat none of it shows within FLOW_CLEAR_DEG degrees of the picture's edges: the eye that
##     rests on the film has still wall beside it, not movement
##   - the room's Motion setting scales the speed, and under a quarter the journey does not go at all
## FLOW_MAX_DEG is a judgment, not a finding. It is the motion system's turning limit for one thing in a room,
## which scenery in a window is not: it fills more of the view. A canal bank four metres off at a narrowboat's
## walking pace comes to 18. Whether that is right is what the first journey on the headset is for; change it here.
const FLOW_MAX_DEG := 20.0
const FLOW_NEAREST := 3.0
const FLOW_ACCEL := 0.3
const FLOW_CLEAR_DEG := 10.0
## Under this much of the Motion setting scenery does not go by at all (the motion system's own threshold for a
## travel: under it a thing snaps or fades to its end instead of moving).
const FLOW_MOTION_FLOOR := 0.25


# --- Schema ------------------------------------------------------------------------------------------------------------

static func schema(doc: Dictionary) -> Array:
	return EnvDoc.validate(doc)["errors"].map(func(e: Dictionary) -> String: return "%s: %s" % [e["path"], e["error"]])


# --- Budget ------------------------------------------------------------------------------------------------------------

## The built room's figures: draws (a mesh surface each), triangles, live lights (visible, not the bake's hidden
## ones), particles (their amounts) and texture memory (the images' bytes with their mip levels, each texture once).
## Texture memory is the headset's: a library map loaded from its .mtex counts its ASTC blocks (MaterialLibrary's
## frame_bytes meta), also where this GPU has no ASTC and holds it decompressed (lavapipe, a PC), so the figure is
## the same headless, rendered and on the Frame.
static func measure(room: Node) -> Dictionary:
	var draws := 0
	var tris := 0
	var particles := 0
	var lights := 0
	var textures := {}
	for g: Node in room.find_children("*", "GeometryInstance3D", true, false):
		if not (g as GeometryInstance3D).visible:
			continue
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			draws += mi.mesh.get_surface_count()
			tris += _triangles(mi.mesh)
			for s in mi.mesh.get_surface_count():
				_textures(mi.get_active_material(s), textures)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			var n := int(g.get_meta("instances", mm.instance_count))
			draws += mm.mesh.get_surface_count()
			tris += _triangles(mm.mesh) * n
			for s in mm.mesh.get_surface_count():
				_textures(mm.mesh.surface_get_material(s), textures)
		elif g is GPUParticles3D:
			draws += 1
			particles += (g as GPUParticles3D).amount
		elif g is CPUParticles3D:
			draws += 1
			particles += (g as CPUParticles3D).amount
	for l: Node in room.find_children("*", "Light3D", true, false):
		if (l as Light3D).is_visible_in_tree() or ((l as Light3D).visible and not l.is_inside_tree()):
			lights += 1
	var bytes := 0
	for t: Variant in textures.values():
		bytes += int(t)
	return {"draws": draws, "triangles": tris, "lights": lights, "particles": particles,
			"texture_mb": snappedf(bytes / 1048576.0, 0.1)}


static func _triangles(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null and (idx as PackedInt32Array).size() > 0 \
				else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


static func _textures(m: Material, out: Dictionary) -> void:
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		for u: Dictionary in (m as ShaderMaterial).shader.get_shader_uniform_list():
			var t: Variant = (m as ShaderMaterial).get_shader_parameter(u["name"])
			if t is ImageTexture and not out.has((t as Texture2D).get_rid()):
				out[(t as Texture2D).get_rid()] = _texture_bytes(t as ImageTexture)
	elif m is BaseMaterial3D:
		var t: Texture2D = (m as BaseMaterial3D).albedo_texture
		if t is ImageTexture and not out.has(t.get_rid()):
			out[t.get_rid()] = _texture_bytes(t as ImageTexture)


## A texture's bytes on the headset: its frame_bytes meta (a library map's ASTC size), else its image's.
static func _texture_bytes(t: ImageTexture) -> int:
	if t.has_meta(MaterialLibrary.FRAME_BYTES_META):
		return int(t.get_meta(MaterialLibrary.FRAME_BYTES_META))
	var img := t.get_image()
	return img.get_data_size() if img != null else 0


static func budget(stats: Dictionary, limits := BUDGET) -> Array:
	var out: Array = []
	for k: String in limits:
		if float(stats.get(k, 0)) > float(limits[k]):
			out.append("%s: %s, over the headset's budget of %s" % [k, stats[k], limits[k]])
	return out


# --- Build time -------------------------------------------------------------------------------------------------------

## A room is built on the main thread when the viewer chooses it, and no frame is drawn until it is done. How long
## that takes depends on the machine, so the check measures the machine first: pace() is the time a fixed piece of
## the same kind of work takes here (a RoomMesh of PACE_BOXES boxes, committed with its lightmap atlas), and a
## room's build is counted in those. Measured 2026-11-09 on the desktop the tests run on, where pace() is about
## 75 ms: a television room builds in 0.1 to 0.3, the cinema in 0.2, the Nave (the slowest of the others) in 3.1,
## the Crater in 7.1 and Reclaimed in 13.9. The first time a room is built in a run it also draws its pictures,
## and that is the longer wait: 1.3 s here for the Shopfront against 0.04 s after it. Those are kept between runs
## (scripts/env/proc_cache.gd), so the budget is for the second build.
const PACE_BOXES := 2000
## The longest a room may take to build, in pace() units, once its pictures are made. A third over the slowest
## room that makes no trouble (the Nave): room for a new room as rich as that one, and no more.
const BUILD_BUDGET := 4.0
## Rooms over BUILD_BUDGET when the check came in (2026-11-09), by id: their geometry is made again, slowly, at
## every visit. A list to shorten, never to add to: a new room builds within the budget.
const BUILD_WAIVED: Array[String] = ["crater", "reclaimed"]
static var _pace := 0.0


## How long the reference work takes on this machine, in milliseconds (the least of three runs; measured once).
static func pace() -> float:
	if _pace > 0.0:
		return _pace
	var best := INF
	for run in 3:
		var t0 := Time.get_ticks_usec()
		var b := RoomMesh.new()
		b.surface(StandardMaterial3D.new())
		for i in PACE_BOXES:
			b.box(Vector3(float(i % 50), float(i / 50), 0.0), Vector3(0.5, 0.5, 0.5))
		b.commit(true)
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	_pace = best
	return _pace


## A build time in milliseconds as pace() units.
static func build_units(ms: float) -> float:
	return snappedf(ms / maxf(pace(), 0.001), 0.1)


# --- Blended layers ---------------------------------------------------------------------------------------------------

## The view the blended layers are counted over: this far to each side of the line from the room's own seat to the
## screen's centre, and this far above and below it (degrees: about what the headset shows of someone watching the
## film), in cells this many degrees across. Equal angles, not pixels: the lenses give the middle more pixels a degree
## and foveation gives the edges fewer, and neither is known here.
const VIEW_HALF := Vector2(55.0, 50.0)
const VIEW_CELL := 2.5
## How far a ray looks (the ground of a lot or a plain goes on to 400 m).
const VIEW_FAR := 450.0
## A ray stops counting here (two faces lying in one plane could otherwise hold it for ever).
const BLEND_STOP := 24
## The most blended layers a room may put over its view, on average. Not a measured limit of the headset. Measured
## on 2026-11-09, no room that ships puts more than 0.6 there (the Bathysphere's glass dome: 0.57; the Crater's:
## 0.43), and the Bathysphere already runs at the frame's edge on the headset, though for its water's shading more
## than for its glass. One whole layer leaves room for a dome like those and for scenery behind a window, and stops
## a room that stacks glass on haze on glass before it reaches the headset.
const BLEND_BUDGET := 1.0
## The group of a mesh whose vertices are not where it is drawn: a vertex shader carries them there (the passing
## system's scenery lies about each item's own foot in its mesh, and is spread along the way when it is drawn). No
## check here that casts rays reads such a mesh: read as it is, it is a heap at the room's origin, round the viewer's
## head, and it would hide everything behind it from the sight line, the blended layers and the flow check alike.
## What it costs is still counted (draws, triangles); where it can be is its system's to say (flow_volumes()).
const PLACED_IN_SHADER := "env_placed_in_shader"
static var _blend_re: RegEx
static var _blends := {}


## Whether a material's surface is blended over what is behind it (the frame is filled again where it shows), as
## glass, haze, a glow and a flame are; a cut-out (alpha scissor or hash) is not.
static func blends(m: Material) -> bool:
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh == null:
			return false
		if not _blends.has(sh):
			if _blend_re == null:
				_blend_re = RegEx.create_from_string(
						"\\bblend_(add|sub|mul|premul_alpha)\\b|\\bALPHA\\s*[*+\\-]?=[^=]")
			var code := sh.code
			_blends[sh] = _blend_re.search(code) != null and not code.contains("ALPHA_SCISSOR_THRESHOLD") \
					and not code.contains("ALPHA_HASH_SCALE")
		return _blends[sh]
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return b.blend_mode != BaseMaterial3D.BLEND_MODE_MIX or b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				or b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	return false


## The room's drawn triangles as two physics bodies for rays from the eyes: what is solid on layer 1, what is
## blended (glass, haze, glows) on layer 2, back faces too. Awaitable (a shape needs a physics frame). Returns
## {space, bodies, blended}: the space to cast in, the bodies to free afterwards, and whether anything is blended.
static func _view_bodies(tree: SceneTree, room: Node3D) -> Dictionary:
	var solid := PackedVector3Array()
	var blended := PackedVector3Array()
	var inv := room.global_transform.affine_inverse()
	for n: Node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null or mi.is_in_group(PLACED_IN_SHADER):
			continue
		var xf: Transform3D = inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			# Lines and points have no area (a primitive mesh is always triangles, and has no such question to ask).
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var out := blended if blends(mi.get_active_material(s)) else solid
			var a := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: Variant = a[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				for i: int in idx as PackedInt32Array:
					out.append(xf * verts[i])
			else:
				for v in verts:
					out.append(xf * v)
	var bodies: Array = []
	for part: Array in [[solid, 1], [blended, 2]]:
		if (part[0] as PackedVector3Array).is_empty():
			continue
		var body := StaticBody3D.new()
		body.collision_layer = int(part[1])
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(part[0])
		cs.shape = shape
		body.add_child(cs)
		tree.root.add_child(body)
		body.global_transform = room.global_transform
		bodies.append(body)
	await tree.physics_frame
	await tree.physics_frame
	return {"space": tree.root.get_world_3d().direct_space_state, "bodies": bodies, "blended": not blended.is_empty()}


## The blended layers over the view from the room's own seat towards the screen: for every cell of the view, how
## many blended surfaces a ray from the eyes crosses before the first solid one. It is what the triangle count cannot
## see and what fills the frame on the headset: a glass dome is a few thousand triangles and the whole view, twice
## where a beam's haze hangs in it. Every crossing counts, a volume's far side as its near one (both are drawn).
## Not counted: particles (the budget has their number), a MultiMesh (headless it keeps no transforms), quads a
## vertex shader turns to the eye (halos: no size until they are drawn), and a mesh in PLACED_IN_SHADER. Awaitable. Returns {mean, peak, share}: the
## layers a cell on average, the most in one cell, and the share of the view with any.
## room: the built room, in the tree at the origin.
static func blend_layers(tree: SceneTree, room: Node3D) -> Dictionary:
	var view := await _view_bodies(tree, room)
	var bodies: Array = view["bodies"]
	if not bool(view["blended"]):
		for body: Node in bodies:
			body.queue_free()
		return {"mean": 0.0, "peak": 0, "share": 0.0}
	var space: PhysicsDirectSpaceState3D = view["space"]
	var eye: Vector3 = room.global_transform * (Vector3.UP * EYE_HEIGHT)
	var anchor: Transform3D = room.call("get_screen_anchor")
	var ahead: Vector3 = room.global_transform * anchor.origin - eye
	ahead = ahead.normalized() if ahead.length() > 0.01 else -room.global_transform.basis.z
	var right := ahead.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else room.global_transform.basis.x
	var up := right.cross(ahead)
	var total := 0
	var peak := 0
	var any := 0
	var cells := 0
	var yaw := -VIEW_HALF.x + VIEW_CELL * 0.5
	while yaw < VIEW_HALF.x:
		var pitch := -VIEW_HALF.y + VIEW_CELL * 0.5
		while pitch < VIEW_HALF.y:
			var dir := (ahead * cos(deg_to_rad(yaw)) + right * sin(deg_to_rad(yaw))) * cos(deg_to_rad(pitch)) \
					+ up * sin(deg_to_rad(pitch))
			var reach := VIEW_FAR
			var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * reach, 1)
			q.hit_back_faces = true
			var wall := space.intersect_ray(q)
			if not wall.is_empty():
				reach = eye.distance_to(wall["position"])
			var layers := 0
			var from := 0.0
			while layers < BLEND_STOP and from < reach:
				var b := PhysicsRayQueryParameters3D.create(eye + dir * from, eye + dir * reach, 2)
				b.hit_back_faces = true
				var hit := space.intersect_ray(b)
				if hit.is_empty():
					break
				layers += 1
				from = eye.distance_to(hit["position"]) + 0.01
			total += layers
			peak = maxi(peak, layers)
			any += 1 if layers > 0 else 0
			cells += 1
			pitch += VIEW_CELL
		yaw += VIEW_CELL
	for body: Node in bodies:
		body.queue_free()
	return {"mean": snappedf(float(total) / maxi(cells, 1), 0.01), "peak": peak,
			"share": snappedf(float(any) / maxi(cells, 1), 0.01)}


# --- Sight line -----------------------------------------------------------------------------------------------------------

## From every seat's eyes to the screen's nine points, nothing static in the way: the room's meshes and seats as one
## physics mesh in the tree's world, ray by ray. Awaitable (the shape needs a physics frame). [] when clear.
## room: the built room, in the tree at the origin.
static func sight_line(tree: SceneTree, room: Node3D, max_reports := 8) -> Array:
	var faces := PackedVector3Array()
	var inv := room.global_transform.affine_inverse()
	for mi: Node in room.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree() or mi.is_in_group(ScreenFrame.SEE_THROUGH) \
				or mi.is_in_group(PLACED_IN_SHADER) or (mi as MeshInstance3D).mesh == null:
			continue
		var xf: Transform3D = inv * (mi as MeshInstance3D).global_transform
		for v: Vector3 in (mi as MeshInstance3D).mesh.get_faces():
			faces.append(xf * v)
	var seats: Array[Transform3D] = room.call("room_seat_transforms") if room.has_method("room_seat_transforms") \
			else []
	for mm: Node in room.find_children("*", "MultiMeshInstance3D", true, false):
		var mesh_faces := (mm as MultiMeshInstance3D).multimesh.mesh.get_faces()
		# Things placed by their own instances, not seats (the cars parked round a drive-in's: since 2026-11-08):
		# each where it stands, its transform in the meta env_placed (a headless MultiMesh keeps none).
		# (has_meta first: get_meta with a null default still prints an error when the key is missing.)
		var placed: Variant = mm.get_meta("env_placed") if mm.has_meta("env_placed") else null
		if placed is Array:
			var mxf: Transform3D = inv * (mm as MultiMeshInstance3D).global_transform
			for t: Transform3D in placed:
				var ixf := mxf * t
				for v: Vector3 in mesh_faces:
					faces.append(ixf * v)
			continue
		for st in seats:
			for v: Vector3 in mesh_faces:
				faces.append(st * v)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	tree.root.add_child(body)
	body.global_transform = room.global_transform
	await tree.physics_frame
	await tree.physics_frame
	var space := tree.root.get_world_3d().direct_space_state
	var anchor: Transform3D = room.call("get_screen_anchor")
	var w := float(room.get("default_screen_width"))
	var doc: Dictionary = room.get("doc") if room.get("doc") is Dictionary else {}
	var h := w * 9.0 / 16.0
	if doc.get("screen") is Dictionary and (doc["screen"]["size"] as Array).size() > 1:
		h = float(doc["screen"]["size"][1])
	var points: Array[Vector3] = []
	for sx: float in [-0.5 + SCREEN_INSET, 0.0, 0.5 - SCREEN_INSET]:
		for sy: float in [-0.5 + SCREEN_INSET, 0.0, 0.5 - SCREEN_INSET]:
			# A hair in front of the picture: the masking behind it is not in the way.
			points.append(room.global_transform * (anchor * Vector3(sx * w, sy * h, 0.05)))
	var out: Array = []
	if seats.is_empty():
		seats = [Transform3D()]
	for i in seats.size():
		var eye: Vector3 = room.global_transform * (seats[i].origin + Vector3.UP * EYE_HEIGHT)
		for p in points:
			var q := PhysicsRayQueryParameters3D.create(eye, p)
			q.hit_back_faces = true
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				out.append("seat %d (%s): the view of the screen's point %s is blocked at %s" % [i, seats[i].origin,
						_r(p), _r(hit["position"])])
				break
		if out.size() >= max_reports:
			out.append("(and maybe more)")
			break
	body.queue_free()
	return out


static func _r(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


# --- Comfort --------------------------------------------------------------------------------------------------------------

## No system moves the viewer; motion parameters within their limits; brightness kept under the photosensitivity
## ceiling (bindings smoothed, fades long enough). spec_of(system name) -> spec (the registry's by default).
static func comfort(doc: Dictionary, spec_of := Callable()) -> Array:
	var specs := spec_of if spec_of.is_valid() else func(n: String) -> Dictionary: return Registry.spec(n)
	var out: Array = []
	var by_id := {}
	for entry: Dictionary in doc.get("systems", []):
		var n := str(entry["system"])
		var spec: Dictionary = specs.call(n)
		by_id[str(entry.get("id", n))] = spec
		if bool(spec.get("moves_viewer", false)):
			out.append("%s moves the viewer: no system may" % n)
		var ps: Dictionary = spec.get("params", {})
		var given: Dictionary = entry.get("params", {})
		for k: String in ps:
			var v: Variant = given.get(k, ps[k].get("default"))
			if ps[k].has("motion"):
				var limit := float(ps[k]["motion"].get("max", 0.0))
				var top := _max_value(v)
				if absf(top) > limit:
					out.append("%s.%s: %s, over its motion limit of %s" % [entry.get("id", n), k, top, limit])
			if bool(ps[k].get("brightness", false)) and EnvDoc.is_binding(v):
				var ch := str(v["bind"])
				if not ch.begins_with(EnvDoc.SETTING_PREFIX) and float(v.get("smooth", 0.0)) < MIN_SMOOTH:
					out.append("%s.%s follows %s with smooth %s: at least %.3f s (the photosensitivity ceiling)" % [
							entry.get("id", n), k, ch, v.get("smooth", 0.0), MIN_SMOOTH])
		# What only the system can judge of its own parameters (scenery that goes by: how fast across the eye, how
		# near): its script's static comfort_for(params), from the parameters alone.
		var script := Registry.script_of(n) if not spec_of.is_valid() else null
		if script != null and script.has_method("comfort_for"):
			for problem: Variant in script.call("comfort_for", EnvDoc.with_defaults(ps, _plain(given))):
				out.append("%s: %s" % [entry.get("id", n), problem])
	# A film-time track is a binding too (by film.minutes or film.progress). The film moves it slowly, but a seek
	# takes it from one key to another in a frame, so on a brightness it needs the same smoothing. (Before
	# 2026-11-09 the tracks were not read here, and one with no `smooth` passed.)
	var timeline: Dictionary = doc.get("timeline", {}) if doc.get("timeline") is Dictionary else {}
	for track: Variant in timeline.get("tracks", []):
		if not (track is Dictionary):
			continue
		var bits := str(track.get("target", "")).split(".")
		if bits.size() == 2 and bool(by_id.get(bits[0], {}).get("params", {}).get(bits[1], {}).get("brightness", false)) \
				and float(track.get("smooth", 0.0)) < MIN_SMOOTH:
			out.append("track %s follows %s with smooth %s: at least %.3f s (a seek moves it in one frame)" % [
					track["target"], track.get("by"), track.get("smooth", 0.0), MIN_SMOOTH])
	for c: Dictionary in doc.get("cues", []):
		for s: Dictionary in c.get("steps", []):
			if s.has("set") or s.has("release"):
				var t := str(s.get("set", s.get("release")))
				var bits := t.split(".")
				var ps: Dictionary = by_id.get(bits[0], {}).get("params", {})
				if bits.size() == 2 and bool(ps.get(bits[1], {}).get("brightness", false)) \
						and float(s.get("seconds", 0.0)) < MIN_FADE:
					out.append("cue %s: %s changes in %s s: at least %.3f s (the photosensitivity ceiling)" % [c["name"],
							t, s.get("seconds", 0.0), MIN_FADE])
	return out


## A system's given parameters with every binding at its strongest (its range's or its keys' largest value; a map's
## largest number): what comfort_for() judges, since a binding may take the parameter that far.
static func _plain(given: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in given:
		var v: Variant = given[k]
		if EnvDoc.is_binding(v):
			if (v as Dictionary).has("range") or (v as Dictionary).has("keys") or (v as Dictionary).has("map"):
				out[k] = _max_value(v)
		else:
			out[k] = v
	return out


## From the room's own seat, no scenery that goes by shows within FLOW_CLEAR_DEG degrees of the picture's edges
## (the comment at FLOW_MAX_DEG has why). Every system with flow_volumes() gives the boxes its moving scenery
## keeps to, in the room's frame; a ray from the eyes that reaches one before it reaches anything solid is a
## problem (glass is not solid). Awaitable. [] when clear, or when nothing in the room goes by.
## room: the built room, in the tree at the origin.
static func flow_clear(tree: SceneTree, room: Node3D) -> Array:
	var volumes: Array[AABB] = []
	var host: Node = room.get("host")
	if host != null:
		for s: Node in host.order:
			if s.has_method("flow_volumes"):
				volumes.append_array(s.call("flow_volumes"))
	if volumes.is_empty():
		return []
	var view := await _view_bodies(tree, room)
	var space: PhysicsDirectSpaceState3D = view["space"]
	var eye: Vector3 = room.global_transform * (Vector3.UP * EYE_HEIGHT)
	var anchor: Transform3D = room.global_transform * (room.call("get_screen_anchor") as Transform3D)
	var w := float(room.get("default_screen_width"))
	var doc: Dictionary = room.get("doc") if room.get("doc") is Dictionary else {}
	var h := w * 9.0 / 16.0
	if doc.get("screen") is Dictionary and (doc["screen"]["size"] as Array).size() > 1:
		h = float(doc["screen"]["size"][1])
	var dist := maxf(eye.distance_to(anchor.origin), 0.1)
	# The picture grown so its edges stand FLOW_CLEAR_DEG further out as the eye sees them.
	var margin := deg_to_rad(FLOW_CLEAR_DEG)
	var half := Vector2(dist * tan(atan(w * 0.5 / dist) + margin), dist * tan(atan(h * 0.5 / dist) + margin))
	var inv := room.global_transform.affine_inverse()
	var out: Array = []
	for ix in range(-6, 7):
		for iy in range(-4, 5):
			var p := anchor * Vector3(half.x * ix / 6.0, half.y * iy / 4.0, 0.0)
			var dir := (p - eye).normalized()
			var reach := VIEW_FAR
			var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * reach, 1)
			q.hit_back_faces = true
			var wall := space.intersect_ray(q)
			if not wall.is_empty():
				reach = eye.distance_to(wall["position"])
			for box in volumes:
				var enters := _ray_enters(inv * eye, inv.basis * dir, box)
				if enters >= 0.0 and enters < reach:
					out.append("scenery that goes by shows %.0f degrees from the picture's middle (within %.0f of its edge)"
							% [rad_to_deg(dir.angle_to((anchor.origin - eye).normalized())), FLOW_CLEAR_DEG]
							+ ": no window that close to the screen")
					break
			if out.size() >= 4:
				break
		if out.size() >= 4:
			break
	for body: Node in view["bodies"]:
		body.queue_free()
	return out


## How far along a ray it enters a box (0 when it starts inside); -1 when it misses.
static func _ray_enters(from: Vector3, dir: Vector3, box: AABB) -> float:
	var t0 := 0.0
	var t1 := INF
	for axis in 3:
		var lo := box.position[axis]
		var hi := box.end[axis]
		if absf(dir[axis]) < 1e-9:
			if from[axis] < lo or from[axis] > hi:
				return -1.0
			continue
		var a := (lo - from[axis]) / dir[axis]
		var b := (hi - from[axis]) / dir[axis]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	return t0 if t0 <= t1 else -1.0


static func _max_value(v: Variant) -> float:
	if EnvDoc.is_binding(v):
		var top := 0.0
		for x: Variant in v.get("range", []):
			top = maxf(top, absf(float(x)))
		for p: Variant in v.get("keys", []):
			top = maxf(top, absf(float(p[1])))
		for x: Variant in (v.get("map", {}) as Dictionary).values():
			top = maxf(top, absf(float(x)))
		return top
	return float(v) if (v is float or v is int) else 0.0


# --- Licences ------------------------------------------------------------------------------------------------------------

## Every library material the room uses (its systems' material parameters, defaults included) is CC0 and credited;
## every asset in its credits is CC0, exists, and is in app/environments/CREDITS.md. Synthesised sounds are ours.
static func licences(doc: Dictionary, credits_file := "res://environments/CREDITS.md",
		materials_credits := "res://materials/CREDITS.md") -> Array:
	var out: Array = []
	var mat_credits := FileAccess.get_file_as_string(materials_credits)
	for id: String in materials_of(doc):
		var e := MaterialLibrary.entry(id)
		var lic := str((e.get("source", {}) as Dictionary).get("licence", ""))
		if not lic.begins_with("CC0"):
			out.append("library material %s: licence %s, not CC0" % [id, lic if lic != "" else "not given"])
		if not mat_credits.contains("`%s`" % id):
			out.append("library material %s: not in %s" % [id, materials_credits])
	var credits := FileAccess.get_file_as_string(credits_file)
	for c: Dictionary in doc.get("credits", []):
		var asset := str(c.get("asset", ""))
		if not str(c.get("licence", "")).begins_with("CC0"):
			out.append("%s: licence %s, not CC0" % [asset, c.get("licence")])
		if not FileAccess.file_exists("res://environments/" + asset):
			out.append("%s: not bundled under environments/" % asset)
		if not credits.contains(asset):
			out.append("%s: not credited in %s" % [asset, credits_file])
	return out


## The library materials a document's systems use (their material parameters, the defaults too).
static func materials_of(doc: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in doc.get("systems", []):
		var ps: Dictionary = Registry.spec(str(entry["system"])).get("params", {})
		var p := EnvDoc.with_defaults(ps, entry.get("params", {}))
		for k: String in ps:
			if ps[k].get("type") == "material" and p[k] is Dictionary and (p[k] as Dictionary).has("library"):
				var id := str(p[k]["library"])
				if not (id in out):
					out.append(id)
	for part: Variant in doc.get("parts", []):
		if part is Dictionary and (part as Dictionary).get("material") is Dictionary:
			var id := str(part["material"].get("library_material", ""))
			if id != "" and not (id in out):
				out.append(id)
	return out


# --- Names -----------------------------------------------------------------------------------------------------------------

## No real mark in any text of the document (whole words, any case).
static func names(doc: Variant) -> Array:
	var texts: Array[String] = []
	_texts(doc, texts)
	var out: Array = []
	for m: String in MARKS:
		var re := RegEx.create_from_string("(?i)(^|[^\\p{L}\\p{N}])" + _escape(m) + "($|[^\\p{L}\\p{N}])")
		for t in texts:
			if re.search(t) != null:
				out.append("\"%s\" names a real mark (%s): use a pastiche of your own" % [t.left(60), m])
				break
	return out


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += "\\" + ch if ch in ".^$*+?()[]{}|\\-" else ch
	return out


static func _texts(v: Variant, out: Array[String]) -> void:
	if v is String:
		out.append(v)
	elif v is Array:
		for x: Variant in v:
			_texts(x, out)
	elif v is Dictionary:
		for k: Variant in v:
			if k is String:
				out.append(k)
			_texts(v[k], out)


# --- No people ------------------------------------------------------------------------------------------------------------

## No system of a people kind, no object or system whose name says person, people, crowd, audience and so on.
static func no_people(doc: Dictionary) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("(?i)(^|[^a-z])(" + "|".join(PEOPLE_WORDS) + ")s?($|[^a-z])")
	for entry: Dictionary in doc.get("systems", []):
		var kind := str(Registry.spec(str(entry["system"])).get("kind", ""))
		if kind in ["people", "crowd"]:
			out.append("system %s: no people in a room" % entry["system"])
		for t: String in [str(entry["system"]), str(entry.get("id", ""))]:
			if re.search(t.replace("_", " ")) != null:
				out.append("system %s: no people in a room" % t)
	for part: Variant in doc.get("parts", []):
		if not (part is Dictionary):
			continue
		for k: String in ["name", "object", "model"]:
			var t := str((part as Dictionary).get(k, "")).replace("_", " ")
			if k != "model" and re.search(t) != null:
				out.append("%s %s: no people in a room (no person models, no crowds)" % [k, part[k]])
	return out


## Every check that needs no built room: [{check, problems}].
static func static_checks(doc: Dictionary) -> Dictionary:
	return {"schema": schema(doc), "comfort": comfort(doc), "licences": licences(doc), "names": names(doc),
			"no_people": no_people(doc)}
