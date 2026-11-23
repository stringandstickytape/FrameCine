extends RefCounted

## The Journeys rooms' tests' common part (docs/environments/rooms/journeys.md, "Before a third room"): loads and
## checks a shipped Journey room (Narrowboat, Showboat 1927, Liner 1936, ...): category and passing system, comfort
## and flow clearance, glass layers, cruise speed and film-length route, house lamps dimming and rising, start and end
## landmarks, arrival at the route's end; a sound bed bound to journey.speed; the cabin's kit fittings inside its box
## and clear of the seat; the room's figures and its comfort table. Not a test itself (no test_ prefix). Static;
## preload to use. `t` is the test (env_builder_harness.gd): its check(what, ok) and check_room().

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Cabin := preload("res://scripts/env/systems/cabin.gd")
const Passing := preload("res://scripts/env/systems/passing.gd")
const PassingShapes := preload("res://scripts/env/systems/passing/shapes.gd")
const FILM := 7200.0


## Reads a Journey room's document and checks that it validates. Returns {} on error.
static func load_doc(t: Object, path: String) -> Dictionary:
	var r := EnvDoc.load_file(path)
	t.check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	return r["doc"]


## Builds and checks a Journey room: builder checks, comfort, flow clearance, glass layers, cruise speed, film-length
## route, house lamps dimming on play and rising on end, start and end landmarks, arrival at the route's end, and
## prints its comfort table. Returns the room (in the tree; free it with t.done()).
## spec: {min_speed, max_speed, start_landmark, end_landmark}
static func check_journey(t: Object, label: String, doc: Dictionary, cabin_id: String, passing_id: String,
		spec: Dictionary) -> Node3D:
	var room: Node3D = await t.check_room(label, doc, cabin_id)
	var host: Node = room.host
	host.auto = false
	var way: Node = host.system(passing_id)
	t.check("it is a journey", str(doc["room"]["category"]) == "journey" and way != null)
	if way == null:
		return room
	var comfort: Array = EnvChecks.comfort(doc)
	t.check("comfort: nothing that goes by comes too near or too fast (%s)" % [comfort], comfort.is_empty())
	var clear: Array = await EnvChecks.flow_clear(t, room)
	t.check("nothing goes by within %s degrees of the picture (%s)" % [EnvChecks.FLOW_CLEAR_DEG, clear.slice(0, 2)],
			clear.is_empty())
	var layers: Dictionary = await EnvChecks.blend_layers(t, room)
	t.check("the windows' glass is well under a layer over the view (%s)" % [layers],
			float(layers["mean"]) <= EnvChecks.BLEND_BUDGET * 0.5)
	# The journey is as long as the film and ends at its destination.
	host.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": FILM}
	for i in 40:
		host.step(0.25)
	var speed := float(way.own_speed)
	var lo := float(spec.get("min_speed", 0.5))
	var hi := float(spec.get("max_speed", 12.0))
	t.check("under way (%.2f m/s)" % speed, speed >= lo and speed <= hi)
	t.check("the route is the film's length at that pace, less the slowing for the end (%.0f m)" % way.route_length(),
			absf(way.route_length() - (speed * FILM - speed * speed / (2.0 * Passing.BRAKE))) < 0.5)
	t.check("the lamps go down with the film (%.2f)" % float(host.param("light.house_lamps")),
			float(host.param("light.house_lamps")) < 0.2)
	var landmarks: Array = way.params["landmarks"]
	var start_shape := str(spec.get("start_landmark", ""))
	var end_shape := str(spec.get("end_landmark", ""))
	if start_shape != "" and end_shape != "":
		t.check("it leaves from %s and ends at %s (%s, %s)" % [start_shape, end_shape, landmarks[0]["shape"],
				landmarks[-1]["shape"]], str(landmarks[0]["shape"]) == start_shape and float(landmarks[0]["at"]) == 0.0
				and str(landmarks[-1]["shape"]) == end_shape and float(landmarks[-1]["at"]) == 1.0)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": FILM, "duration": FILM}
	for i in 60:
		host.step(0.25)
	t.check("the film over: stopped at the route's end, the lamps up (%.1f of %.1f m, %.2f m/s, lamps %.2f)" % [
			way.travel, way.route_length(), way.speed_now, float(host.param("light.house_lamps"))],
			absf(way.travel - way.route_length()) < 0.5 and way.speed_now == 0.0
			and float(host.param("light.house_lamps")) > 0.95)
	comfort_table(way.params)
	return room


## A sound bed whose level follows journey.speed: full (> 0.9) under way, settled near stopped_level when paused.
static func check_speed_bed(t: Object, room: Node3D, bed_id: String, label: String, stopped_level: float) -> void:
	var host: Node = room.host
	var bed: Node = host.system(bed_id)
	host.timeline.state = ""
	var pos := 600.0
	for i in 120:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": FILM}
		host.step(0.25)
	var going := float(bed.params["level"])
	host.snapshot_override = {"open": true, "playing": false, "position": pos, "duration": FILM}
	for i in 120:
		host.step(0.25)
	var stopped := float(bed.params["level"])
	t.check("%s under way (%.2f) and stopped (%.2f)" % [label, going, stopped], going > 0.9
			and absf(stopped - stopped_level) <= 0.05)


## The cabin's kit fittings: inside the cabin's box (unless allow_outside returns true for a box, e.g. a flue or
## exterior rail), clear of 0.45 m round the viewer's own seat at the origin, and placed with no problems.
static func check_fittings(t: Object, room: Node3D, cabin_id: String, kit_id: String, label: String, min_boxes := 1,
		allow_outside := Callable()) -> void:
	var host: Node = room.host
	var kit: Node = host.system(kit_id)
	t.check("%s (the kit %s)" % [label, kit_id], kit != null)
	if kit == null:
		return
	var cabin_box: AABB = Cabin._box(host.system(cabin_id).params).grow(0.001)
	var inside := true
	var clear := true
	var boxes: Array = kit.collision_shapes()
	for s: Array in boxes:
		var shape := s[0] as BoxShape3D
		var box: AABB = (s[1] as Transform3D) * AABB(-shape.size * 0.5, shape.size)
		var exempt := allow_outside.is_valid() and bool(allow_outside.call(box))
		if not cabin_box.encloses(box) and not exempt:
			inside = false
		var nearest := Vector2(clampf(0.0, box.position.x, box.end.x), clampf(0.0, box.position.z, box.end.z))
		if nearest.length() < 0.45:
			clear = false
	t.check("%s: boxes (%d) inside the cabin" % [label, boxes.size()], boxes.size() >= min_boxes and inside)
	t.check("%s: nothing within 0.45 m of the seat" % label, clear)
	t.check("%s: nothing the kit could not place (%s)" % [label, kit.problems()], kit.problems().is_empty())


## Measures and checks the room's draws, triangles and live lights.
static func check_figures(t: Object, label: String, room: Node3D, max_draws: int, max_tris: int) -> Dictionary:
	var stats := EnvChecks.measure(room)
	print("  %s: %d draws, %d triangles, %d lights, %.1f MB of textures" % [label, int(stats["draws"]),
			int(stats["triangles"]), int(stats["lights"]), float(stats["texture_mb"])])
	t.check("the figures: at most %d draws, %d triangles, no live light (%s)" % [max_draws, max_tris, stats],
			int(stats["draws"]) <= max_draws and int(stats["triangles"]) <= max_tris and int(stats["lights"]) == 0)
	return stats


## The comfort figures of every band and landmark: the nearest any part comes (Shapes.nearest(), as passing.gd
## comfort_for() asks) and the degrees a second it crosses the eye there at the fastest the journey goes.
static func comfort_table(p: Dictionary) -> void:
	var top := float(p.get("speed", 1.0)) * (1.0 + Passing.CATCH_UP)
	print("  comfort at %.2f m/s:" % top)
	var bands: Array = p["bands"]
	for i in bands.size():
		var band := Passing.band_with_defaults(bands[i])
		var shape := str(band["shape"])
		var largest := float(band["size"]) * (1.0 if PassingShapes.SEGMENT.has(shape) else PassingShapes.VARY.y)
		var near := PassingShapes.nearest(shape, largest, float(band["near"]), float(band["height"]),
				EnvChecks.EYE_HEIGHT)
		print("    band %d %s %s: nearest %.2f m, %.1f deg/s" % [i, shape, band["side"], near,
				rad_to_deg(top / float(band["seems"]) / near)])
	var landmarks: Array = p["landmarks"]
	for k in landmarks.size():
		var lm := Passing.landmark_with_defaults(landmarks[k])
		var shape := str(lm["shape"])
		var near := PassingShapes.nearest(shape, float(lm["size"]), float(lm["distance"]), float(lm["height"]),
				EnvChecks.EYE_HEIGHT)
		print("    landmark %d %s %s at %.3f: nearest %.2f m, %.1f deg/s" % [k, shape, lm["side"], float(lm["at"]),
				near, rad_to_deg(top / near)])


## Steps a rendered room to a fraction of the film (for lavapipe shots).
static func step_stage(host: Node, fraction: float, film := FILM) -> void:
	var at := fraction * film
	host.snapshot_override = {"open": true, "playing": at < film, "ended": at >= film, "position": at,
			"duration": film}
	# (No player here: the film's own channels are given by hand, as the snapshot is.)
	host.signals.fake("film.progress", fraction)
	host.signals.fake("film.minutes", at / 60.0)
	for i in 80:
		host.step(0.25)
